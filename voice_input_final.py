#!/usr/bin/env python3
"""
语音输入工具 - 最终版本
悬浮窗提示 + 音波动画 (终端内显示)
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

# 音波显示
display_thread = None
display_running = False


def load_config():
    """加载配置文件"""
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def show_recording_ui():
    """在终端显示录音状态 UI"""
    global display_running
    display_running = True

    # 清屏并显示悬浮窗样式的提示
    print("\n" + "=" * 40)
    print("║      🎤 语音输入 - 正在录音...       ║")
    print("=" * 40)

    # 音波动画
    waves = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    i = 0

    while display_running:
        # 生成随机音波
        wave_str = ""
        for _ in range(10):
            level = int(abs(os.urandom(1)[0] - 128) / 16)  # 随机音量
            wave_str += waves[min(level, 7)]

        # 显示在同一行
        print(f"\r  {wave_str}  {i//10}s", end='', flush=True)
        i += 1
        time.sleep(0.1)

    print("\n" + "=" * 40)
    print("║        ⏹ 录音结束，处理中...         ║")
    print("=" * 40 + "\n")


def hide_recording_ui():
    """隐藏录音状态 UI"""
    global display_running
    display_running = False


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
                    is_recording = False
                    break

            if time.time() - start_time > max_duration:
                is_recording = False
                break

        except Exception as e:
            print(f"\n录音错误: {e}")
            break

    stream.stop_stream()
    stream.close()
    audio.terminate()


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
            model_path = str(cache_path)

        model = load_model(model_path)

        # 语言映射
        lang_map = {
            'zh': 'Chinese', 'en': 'English', 'ja': 'Japanese',
            'ko': 'Korean', 'fr': 'French', 'de': 'German', 'es': 'Spanish',
            'auto': 'Chinese'
        }
        mlx_lang = lang_map.get(language, 'Chinese')

        result = generate_transcription(
            model=model,
            audio=audio_path,
            verbose=False,
            language=mlx_lang
        )

        text = result.text.strip() if hasattr(result, 'text') else str(result).strip()
        return text

    except Exception as e:
        # 回退到 mlx-whisper
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
    except:
        os.system("osascript -e 'tell application \"System Events\" to keystroke \"v\" using command down'")


def on_hotkey():
    """快捷键回调函数"""
    global is_recording, recording_thread, display_thread

    if not is_recording:
        # 开始录音
        is_recording = True

        # 显示录音 UI
        display_thread = threading.Thread(target=show_recording_ui, daemon=True)
        display_thread.start()

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
        # 停止录音
        is_recording = False
        recording_thread.join()

        # 隐藏 UI
        hide_recording_ui()
        display_thread.join()

        # 保存并转录
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
            audio_path = tmp.name

        save_audio(audio_frames, config['recording'].get('sample_rate', 16000), audio_path)

        try:
            model_config = config['model']
            text = transcribe_audio_mlx(
                audio_path,
                model_config.get('language', 'auto'),
                model_config['size']
            )

            if text:
                print(f"✓ 识别结果: {text}")

                if config['output'].get('mode', 'paste') == 'paste':
                    paste_text(text)
                else:
                    pyperclip.copy(text)
            else:
                print("⚠ 未能识别语音")

        except Exception as e:
            print(f"✗ 转录错误: {e}")

        finally:
            try:
                os.unlink(audio_path)
            except:
                pass


def main():
    global config

    print("=" * 50)
    print("🎙  语音输入工具")
    print("=" * 50)

    config = load_config()

    print(f"快捷键: {config.get('hotkey', 'f8')}")
    print(f"模型: {config['model']['size']}")
    print(f"语言: {config['model'].get('language', 'zh')}")
    print("-" * 50)
    print("按快捷键开始/停止录音，按 Ctrl+C 退出")
    print()

    # 解析快捷键
    hotkey_str = config.get('hotkey', 'f8')
    key_map = {
        'cmd_r': keyboard.Key.cmd_r, 'cmd_l': keyboard.Key.cmd,
        'cmd': keyboard.Key.cmd, 'ctrl': keyboard.Key.ctrl,
        'alt': keyboard.Key.alt, 'shift': keyboard.Key.shift,
        'f1': keyboard.Key.f1, 'f2': keyboard.Key.f2, 'f3': keyboard.Key.f3,
        'f4': keyboard.Key.f4, 'f5': keyboard.Key.f5, 'f6': keyboard.Key.f6,
        'f7': keyboard.Key.f7, 'f8': keyboard.Key.f8, 'f9': keyboard.Key.f9,
        'f10': keyboard.Key.f10, 'f11': keyboard.Key.f11, 'f12': keyboard.Key.f12,
    }

    hotkey_lower = hotkey_str.lower().strip()
    if hotkey_lower in key_map:
        key, modifiers = key_map[hotkey_lower], None
    else:
        parts = hotkey_lower.split('+')
        modifiers = [getattr(keyboard.Key, p) for p in parts if p in ('cmd', 'ctrl', 'alt', 'shift')]
        key = parts[-1] if parts else 'f8'

    current_keys = set()
    last_trigger_time = 0

    def on_press(k):
        nonlocal last_trigger_time
        current_keys.add(k)

        if time.time() - last_trigger_time < 0.5:
            return

        if modifiers is None:
            if k == key:
                last_trigger_time = time.time()
                threading.Thread(target=on_hotkey, daemon=True).start()
        else:
            if all(m in current_keys for m in modifiers):
                last_trigger_time = time.time()
                threading.Thread(target=on_hotkey, daemon=True).start()

    def on_release(k):
        if k in current_keys:
            current_keys.remove(k)

    with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
        listener.join()


if __name__ == '__main__':
    main()
