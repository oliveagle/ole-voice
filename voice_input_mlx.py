#!/usr/bin/env python3
"""
语音输入工具 - MLX 版本 (Apple Silicon 优化)
使用 Apple MLX 框架，在 M1/M2/M3 上速度更快
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
import numpy as np
from pynput import keyboard
from pynput.keyboard import Controller as KeyboardController

# 全局状态
is_recording = False
recording_thread = None
audio_frames = []
config = {}
keyboard_controller = KeyboardController()
model_instance = None


def load_config():
    """加载配置文件"""
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def check_model_downloaded(model_size):
    """检查 MLX Whisper 模型是否已下载"""
    cache_dir = Path.home() / '.cache' / 'mlx_whisper'
    # MLX Whisper 使用 HuggingFace 格式缓存
    model_dir = cache_dir / f'whisper-{model_size}-mlx'

    if not model_dir.exists():
        print(f"[MLX] 模型 {model_size} 未下载，首次使用时会自动下载...")
        print(f"[MLX] 下载位置: {cache_dir}")
        return False
    else:
        print(f"[MLX] ✓ 模型 {model_size} 已存在")
        return True


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
        # 优先使用 mlx-audio (Qwen3-ASR 模型)
        from mlx_audio.stt.utils import load_model
        from mlx_audio.stt.generate import generate_transcription

        # 使用 Qwen3-ASR 模型（中文优化）
        model_path = "mlx-community/Qwen3-ASR-0.6B-8bit"
        cache_path = Path.home() / ".cache/modelscope/hub/models/mlx-community/Qwen3-ASR-0.6B-8bit"

        if cache_path.exists():
            print(f"[MLX-Audio] 使用本地缓存模型: {cache_path}")
            model_path = str(cache_path)
        else:
            print(f"[MLX-Audio] 使用在线模型: {model_path}")

        print("[MLX-Audio] 加载 Qwen3-ASR 模型...")
        model = load_model(model_path)

        print("[MLX-Audio] 开始转录...")

        # 语言映射
        lang_map = {
            'zh': 'Chinese',
            'en': 'English',
            'ja': 'Japanese',
            'ko': 'Korean',
            'fr': 'French',
            'de': 'German',
            'es': 'Spanish',
            'auto': 'Chinese'  # 默认中文
        }
        mlx_lang = lang_map.get(language, 'Chinese')
        print(f"[MLX-Audio] 语言设置: {mlx_lang}")

        result = generate_transcription(
            model=model,
            audio=audio_path,
            verbose=False,
            language=mlx_lang  # 传递语言参数
        )

        text = result.text.strip() if hasattr(result, 'text') else str(result).strip()
        return text

    except ImportError as e:
        print(f"[MLX-Audio] 未安装或导入失败: {e}，回退到 mlx-whisper...")
        # 回退到 mlx-whisper
        import mlx_whisper
        model_repo = f"mlx-community/whisper-{model_size}"
        result = mlx_whisper.transcribe(audio_path, path_or_hf_repo=model_repo, verbose=False)
        return result.get('text', '').strip()


def type_text(text):
    """模拟键盘输入文字"""
    print(f"[DEBUG] type_text 开始，输入内容: '{text}'")
    time.sleep(0.5)

    try:
        print("[DEBUG] 使用 pynput 输入文字...")
        keyboard_controller.type(text)
        print("[DEBUG] pynput 输入完成")
    except Exception as e:
        print(f"[DEBUG] pynput 输入失败: {e}")
        try:
            print("[DEBUG] 尝试使用 AppleScript 输入...")
            safe_text = text.replace('"', '\\"').replace("'", "\\'")
            cmd = f'''osascript -e 'tell application "System Events" to keystroke "{safe_text}"' '''
            os.system(cmd)
        except Exception as e2:
            print(f"[DEBUG] AppleScript 输入也失败: {e2}")


def paste_text(text):
    """复制到剪贴板并粘贴"""
    print("[DEBUG] paste_text 开始")
    pyperclip.copy(text)
    print("[DEBUG] 已复制到剪贴板")
    time.sleep(0.2)

    try:
        print("[DEBUG] 模拟 Cmd+V 粘贴...")
        with keyboard_controller.pressed(keyboard.Key.cmd):
            keyboard_controller.press('v')
            keyboard_controller.release('v')
        print("[DEBUG] 粘贴完成")
    except Exception as e:
        print(f"[DEBUG] 粘贴失败: {e}")


def show_notification(title, message):
    """显示 macOS 通知"""
    try:
        message = message.replace('"', '\\"').replace("'", "\\'")
        title = title.replace('"', '\\"').replace("'", "\\'")
        os.system(f'''osascript -e 'display notification "{message}" with title "{title}"' ''')
    except:
        pass


def on_hotkey():
    """快捷键回调函数"""
    global is_recording, recording_thread

    if not is_recording:
        print("\n[DEBUG] 收到快捷键，开始录音...")
        is_recording = True

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

        show_notification("语音输入", "🎤 开始录音，请说话...")
    else:
        print("\n[DEBUG] 收到快捷键，停止录音...")
        is_recording = False
        recording_thread.join()

        print(f"[DEBUG] 录音结束，音频帧数: {len(audio_frames)}")
        show_notification("语音输入", "处理中...")

        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
            audio_path = tmp.name

        print(f"[DEBUG] 保存音频到: {audio_path}")
        save_audio(
            audio_frames,
            config['recording'].get('sample_rate', 16000),
            audio_path
        )
        print("[DEBUG] 音频保存完成")

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

            print(f"[DEBUG] 转录结果: '{text}'")

            if text:
                print(f"✓ 识别结果: {text}")

                output_mode = config['output'].get('mode', 'type')
                print(f"[DEBUG] 输出模式: {output_mode}")

                if output_mode == 'type':
                    print("[DEBUG] 开始模拟键盘输入...")
                    type_text(text)
                    print("[DEBUG] 键盘输入完成")
                elif output_mode == 'paste':
                    print("[DEBUG] 开始粘贴...")
                    paste_text(text)
                    print("[DEBUG] 粘贴完成")
                elif output_mode == 'clipboard':
                    print("[DEBUG] 复制到剪贴板...")
                    pyperclip.copy(text)
                    print("[DEBUG] 复制完成")

                display_text = text[:50] + '...' if len(text) > 50 else text
                show_notification("语音输入完成", display_text)
            else:
                print("⚠ 未能识别语音")
                show_notification("语音输入", "未能识别语音")

        except Exception as e:
            print(f"✗ 转录错误: {e}")
            import traceback
            traceback.print_exc()
            show_notification("语音输入失败", str(e)[:100])

        finally:
            if not config['output'].get('keep_audio', False):
                try:
                    os.unlink(audio_path)
                    print("[DEBUG] 临时音频文件已删除")
                except Exception as e:
                    print(f"[DEBUG] 删除临时文件失败: {e}")


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
    print("🎙  语音输入工具 - MLX 版本 (Apple Silicon 优化)")
    print("=" * 50)

    config = load_config()

    hotkey_str = config.get('hotkey', 'f8')
    print(f"快捷键: {hotkey_str}")
    print(f"模型: {config['model']['size']}")
    print(f"输出模式: {config['output'].get('mode', 'type')}")
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
