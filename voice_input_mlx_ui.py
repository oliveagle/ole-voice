#!/usr/bin/env python3
"""
语音输入工具 - MLX 版本 + 悬浮窗 UI
按快捷键录音，显示悬浮窗 + 音波动画
"""

import os
import sys
import time
import threading
import wave
import tempfile
from datetime import datetime
from pathlib import Path

import yaml
import pyaudio
import pyperclip
from pynput import keyboard
from pynput.keyboard import Controller as KeyboardController

# 全局状态
is_recording = False
recording_thread = None
audio_frames = []
config = {}
keyboard_controller = KeyboardController()

# UI 相关
ui_window = None
ui_showing = False


def load_config():
    """加载配置文件"""
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def check_model_downloaded(model_size):
    """检查 MLX Whisper 模型是否已下载"""
    cache_dir = Path.home() / '.cache' / 'mlx_whisper'
    model_dir = cache_dir / f'whisper-{model_size}-mlx'

    if not model_dir.exists():
        print(f"[MLX] 模型 {model_size} 未下载，首次使用时会自动下载...")
        return False
    else:
        print(f"[MLX] ✓ 模型 {model_size} 已存在")
        return True


def show_native_ui():
    """显示原生 macOS 悬浮窗"""
    global ui_window, ui_showing

    try:
        from AppKit import (
            NSApplication, NSWindow, NSView, NSColor, NSFont,
            NSTextField, NSMakeRect, NSScreen,
            NSFloatingWindowLevel, NSBorderlessWindowMask
        )

        # 创建窗口
        screen = NSScreen.mainScreen()
        screen_frame = screen.frame()

        window_width = 200
        window_height = 50
        x = (screen_frame.size.width - window_width) / 2
        y = 100  # 距离底部

        ui_window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(x, y, window_width, window_height),
            NSBorderlessWindowMask,
            2,
            False
        )

        ui_window.setLevel_(NSFloatingWindowLevel)
        ui_window.setOpaque_(False)
        ui_window.setBackgroundColor_(
            NSColor.colorWithRed_green_blue_alpha_(0.1, 0.1, 0.1, 0.95)
        )

        # 内容
        content = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, window_width, window_height))

        # 圆角
        content.setWantsLayer_(True)
        content.layer().setCornerRadius_(25)

        # 标签
        label = NSTextField.alloc().initWithFrame_(NSMakeRect(0, 12, window_width, 26))
        label.setStringValue_("🎤 语音输入 ●●●")
        label.setTextColor_(NSColor.whiteColor())
        label.setFont_(NSFont.systemFontOfSize_(14))
        label.setEditable_(False)
        label.setBordered_(False)
        label.setBackgroundColor_(NSColor.clearColor())
        label.setAlignment_(1)  # 居中

        content.addSubview_(label)
        ui_window.setContentView_(content)
        ui_window.makeKeyAndOrderFront_(None)

        ui_showing = True

        # 启动动画线程
        def animate():
            dots = ["●○○", "○●○", "○○●", "○●○"]
            i = 0
            while ui_showing:
                label.setStringValue_(f"🎤 语音输入 {dots[i % 4]}")
                time.sleep(0.3)
                i += 1

        threading.Thread(target=animate, daemon=True).start()

    except Exception as e:
        print(f"[UI] 创建悬浮窗失败: {e}")


def hide_native_ui():
    """隐藏悬浮窗"""
    global ui_window, ui_showing

    ui_showing = False
    if ui_window:
        try:
            ui_window.orderOut_(None)
            ui_window = None
        except:
            pass


def record_audio(sample_rate=16000, device_index=None, silence_timeout=0, max_duration=60):
    """录音线程函数"""
    global is_recording, audio_frames

    audio = pyaudio.PyAudio()

    stream = audio.open(
        format=pyaudio.paInt16,
        channels=1,
        rate=sample_rate,
        input=True,
        input_device_index=device_index,
        frames_per_buffer=1024
    )

    print("🎤 开始录音...")
    audio_frames = []
    start_time = time.time()
    last_sound_time = time.time()

    while is_recording:
        try:
            data = stream.read(1024, exception_on_overflow=False)
            audio_frames.append(data)

            if silence_timeout > 0:
                audio_data = bytes(data)
                max_val = max(abs(int.from_bytes(audio_data[i:i+2], 'little', signed=True))
                             for i in range(0, len(audio_data), 2))
                if max_val > 500:
                    last_sound_time = time.time()
                elif time.time() - last_sound_time > silence_timeout:
                    print("检测到静音，自动停止")
                    is_recording = False
                    break

            if time.time() - start_time > max_duration:
                print("达到最大录音时长，自动停止")
                is_recording = False
                break

        except Exception as e:
            print(f"录音错误: {e}")
            break

    stream.stop_stream()
    stream.close()
    audio.terminate()

    print("⏹ 录音结束")


def save_audio(frames, sample_rate, filepath):
    """保存录音到文件"""
    wf = wave.open(filepath, 'wb')
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(sample_rate)
    wf.writeframes(b''.join(frames))
    wf.close()


def transcribe_audio_mlx(audio_path, language, model_size):
    """使用 MLX Audio (Qwen3-ASR) 转录音频"""
    try:
        from mlx_audio.stt.utils import load_model
        from mlx_audio.stt.generate import generate_transcription

        model_path = "mlx-community/Qwen3-ASR-0.6B-8bit"
        cache_path = Path.home() / ".cache/modelscope/hub/models/mlx-community/Qwen3-ASR-0.6B-8bit"

        if cache_path.exists():
            print(f"[MLX-Audio] 使用本地缓存模型")
            model_path = str(cache_path)

        print("[MLX-Audio] 加载 Qwen3-ASR 模型...")
        model = load_model(model_path)

        # 语言映射
        lang_map = {
            'zh': 'Chinese', 'en': 'English', 'ja': 'Japanese',
            'ko': 'Korean', 'fr': 'French', 'de': 'German', 'es': 'Spanish',
            'auto': 'Chinese'
        }
        mlx_lang = lang_map.get(language, 'Chinese')

        print(f"[MLX-Audio] 开始转录 (语言: {mlx_lang})...")
        result = generate_transcription(
            model=model,
            audio=audio_path,
            verbose=False,
            language=mlx_lang
        )

        text = result.text.strip() if hasattr(result, 'text') else str(result).strip()
        return text

    except Exception as e:
        print(f"[MLX-Audio] 错误: {e}，回退到 mlx-whisper...")
        import mlx_whisper
        model_repo = f"mlx-community/whisper-{model_size}"
        result = mlx_whisper.transcribe(audio_path, path_or_hf_repo=model_repo, verbose=False)
        return result.get('text', '').strip()


def paste_text(text):
    """复制到剪贴板并粘贴"""
    pyperclip.copy(text)
    time.sleep(0.2)

    try:
        with keyboard_controller.pressed(keyboard.Key.cmd):
            keyboard_controller.press('v')
            keyboard_controller.release('v')
    except Exception as e:
        try:
            os.system("osascript -e 'tell application \"System Events\" to keystroke \"v\" using command down'")
        except:
            pass


def on_hotkey():
    """快捷键回调函数"""
    global is_recording, recording_thread

    if not is_recording:
        print("\n[DEBUG] 收到快捷键，开始录音...")
        is_recording = True

        # 显示悬浮窗（在主线程）
        show_native_ui()

        recording_thread = threading.Thread(
            target=record_audio,
            args=(
                config['recording'].get('sample_rate', 16000),
                config['recording'].get('device_index'),
                config['advanced'].get('silence_timeout', 0),
                config['advanced'].get('max_duration', 60),
            )
        )
        recording_thread.start()

    else:
        print("\n[DEBUG] 收到快捷键，停止录音...")
        is_recording = False
        recording_thread.join()

        # 隐藏悬浮窗
        hide_native_ui()

        print(f"[DEBUG] 录音结束，音频帧数: {len(audio_frames)}")

        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
            audio_path = tmp.name

        save_audio(
            audio_frames,
            config['recording'].get('sample_rate', 16000),
            audio_path
        )

        try:
            model_config = config['model']
            model_size = model_config['size']

            print("[MLX] 开始转录...")
            start_time = time.time()
            text = transcribe_audio_mlx(
                audio_path,
                model_config.get('language', 'auto'),
                model_size
            )
            elapsed = time.time() - start_time
            print(f"[MLX] 转录完成，耗时: {elapsed:.2f}秒")

            if text:
                print(f"✓ 识别结果: {text}")

                output_mode = config['output'].get('mode', 'type')
                if output_mode == 'paste':
                    paste_text(text)
                elif output_mode == 'clipboard':
                    pyperclip.copy(text)

            else:
                print("⚠ 未能识别语音")

        except Exception as e:
            print(f"✗ 转录错误: {e}")
            import traceback
            traceback.print_exc()

        finally:
            if not config['output'].get('keep_audio', False):
                try:
                    os.unlink(audio_path)
                except:
                    pass


def parse_hotkey_for_listener(hotkey_str):
    """解析快捷键"""
    key_map = {
        'cmd_r': keyboard.Key.cmd_r,
        'cmd_l': keyboard.Key.cmd,
        'ctrl_r': keyboard.Key.ctrl_r,
        'ctrl_l': keyboard.Key.ctrl_l,
        'alt_r': keyboard.Key.alt_r,
        'alt_l': keyboard.Key.alt_l,
        'shift_r': keyboard.Key.shift_r,
        'shift_l': keyboard.Key.shift_l,
        'cmd': keyboard.Key.cmd,
        'ctrl': keyboard.Key.ctrl,
        'alt': keyboard.Key.alt,
        'shift': keyboard.Key.shift,
        'f1': keyboard.Key.f1, 'f2': keyboard.Key.f2, 'f3': keyboard.Key.f3,
        'f4': keyboard.Key.f4, 'f5': keyboard.Key.f5, 'f6': keyboard.Key.f6,
        'f7': keyboard.Key.f7, 'f8': keyboard.Key.f8, 'f9': keyboard.Key.f9,
        'f10': keyboard.Key.f10, 'f11': keyboard.Key.f11, 'f12': keyboard.Key.f12,
        'space': keyboard.Key.space,
        'tab': keyboard.Key.tab,
        'esc': keyboard.Key.esc,
        'enter': keyboard.Key.enter,
    }

    hotkey_lower = hotkey_str.lower().strip()

    if hotkey_lower in key_map:
        return key_map[hotkey_lower], None

    parts = hotkey_lower.split('+')
    modifiers = []
    key = None

    for part in parts:
        part = part.strip()
        if part in ('cmd', 'ctrl', 'alt', 'shift'):
            modifiers.append(getattr(keyboard.Key, part))
        elif part in key_map:
            key = key_map[part]
        elif len(part) == 1:
            key = part

    return key, modifiers


def main():
    global config

    print("=" * 50)
    print("🎙  语音输入工具 - MLX 版本 + UI")
    print("=" * 50)

    config = load_config()

    hotkey_str = config.get('hotkey', 'f8')
    print(f"快捷键: {hotkey_str}")
    print(f"模型: {config['model']['size']}")
    print(f"输出模式: {config['output'].get('mode', 'paste')}")
    print("-" * 50)
    print("按快捷键开始/停止录音，按 Ctrl+C 退出")
    print()

    key, modifiers = parse_hotkey_for_listener(hotkey_str)

    current_keys = set()
    last_trigger_time = 0
    trigger_cooldown = 0.5

    def on_press(k):
        nonlocal last_trigger_time
        current_keys.add(k)

        if time.time() - last_trigger_time < trigger_cooldown:
            return

        if modifiers is None:
            if k == key:
                last_trigger_time = time.time()
                threading.Thread(target=on_hotkey, daemon=True).start()
        else:
            if all(m in current_keys for m in modifiers):
                if key is None or k == key or (isinstance(key, str) and hasattr(k, 'char') and k.char == key):
                    last_trigger_time = time.time()
                    threading.Thread(target=on_hotkey, daemon=True).start()

    def on_release(k):
        if k in current_keys:
            current_keys.remove(k)

    try:
        with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
            listener.join()
    except KeyboardInterrupt:
        print("\n程序已退出")
    except Exception as e:
        print(f"错误: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main()
