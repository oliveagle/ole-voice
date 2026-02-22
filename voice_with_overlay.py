#!/usr/bin/env python3
"""
语音输入工具 - 带 Swift 悬浮窗
Python 负责录音和识别，Swift 负责显示悬浮窗
"""

import os
import sys
import threading
import time
import wave
import tempfile
import signal
from pathlib import Path

import yaml
import pyaudio
import pyperclip
from pynput import keyboard
from pynput.keyboard import Controller, Key

# 全局状态
is_recording = False
recording_thread = None
audio_frames = []
config = {}
controller = Controller()

# 控制文件路径
CONTROL_FILE = Path("/tmp/voice_overlay_control")


def load_config():
    """加载配置"""
    try:
        config_path = Path(__file__).parent / "config.yaml"
        with open(config_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except:
        return {}


def show_overlay():
    """显示悬浮窗"""
    CONTROL_FILE.write_text("show")


def hide_overlay():
    """隐藏悬浮窗"""
    CONTROL_FILE.write_text("hide")


def record_audio():
    """录音"""
    global audio_frames

    try:
        audio = pyaudio.PyAudio()
        stream = audio.open(
            format=pyaudio.paInt16, channels=1, rate=16000,
            input=True, frames_per_buffer=1024
        )

        audio_frames = []
        start = time.time()

        while is_recording and time.time() - start < 60:
            try:
                data = stream.read(1024, exception_on_overflow=False)
                audio_frames.append(data)
            except:
                break

        stream.stop_stream()
        stream.close()
        audio.terminate()
    except Exception as e:
        print(f"录音错误: {e}")


def transcribe_audio(audio_path):
    """转录"""
    try:
        from mlx_audio.stt.utils import load_model
        from mlx_audio.stt.generate import generate_transcription

        cache = Path.home() / ".cache/modelscope/hub/models/mlx-community/Qwen3-ASR-0.6B-8bit"
        model_path = str(cache) if cache.exists() else "mlx-community/Qwen3-ASR-0.6B-8bit"

        model = load_model(model_path)

        lang = config.get('model', {}).get('language', 'zh')
        lang_map = {'zh': 'Chinese', 'en': 'English', 'auto': 'Chinese'}

        result = generate_transcription(
            model=model,
            audio=audio_path,
            language=lang_map.get(lang, 'Chinese'),
            verbose=False
        )

        return result.text.strip() if hasattr(result, 'text') else str(result).strip()
    except Exception as e:
        print(f"转录错误: {e}")
        return ""


def process_recording():
    """处理录音"""
    try:
        # 保存
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
            path = f.name

        wf = wave.open(path, 'wb')
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(16000)
        wf.writeframes(b''.join(audio_frames))
        wf.close()

        # 转录
        print("[MLX] 转录中...")
        text = transcribe_audio(path)

        if text:
            print(f"✓ {text}")
            pyperclip.copy(text)
            time.sleep(0.1)
            with controller.pressed(Key.cmd):
                controller.press('v')
                controller.release('v')
        else:
            print("⚠ 未能识别")

        # 清理
        try:
            os.unlink(path)
        except:
            pass

    except Exception as e:
        print(f"处理错误: {e}")


def toggle_recording():
    """切换录音状态"""
    global is_recording, recording_thread

    if not is_recording:
        # 开始录音
        is_recording = True
        show_overlay()

        recording_thread = threading.Thread(target=record_audio, daemon=True)
        recording_thread.start()
    else:
        # 停止录音
        is_recording = False
        if recording_thread:
            recording_thread.join(timeout=2)

        hide_overlay()
        process_recording()


def main():
    global config

    signal.signal(signal.SIGINT, lambda s, f: sys.exit(0))

    config = load_config()

    print("=" * 50)
    print("🎙  语音输入工具 - Swift 悬浮窗版本")
    print("=" * 50)
    print(f"快捷键: {config.get('hotkey', 'cmd_l')}")
    print()

    # 检查 Swift 程序是否运行
    if not CONTROL_FILE.exists():
        CONTROL_FILE.write_text("hidden")
        print("⚠️ 请先运行 Swift 悬浮窗程序:")
        print("   cd VoiceOverlay && ./VoiceOverlay")
        print()

    # 启动键盘监听
    key_map = {
        'cmd_l': keyboard.Key.cmd,
        'cmd_r': keyboard.Key.cmd_r,
        'cmd': keyboard.Key.cmd,
        'f8': keyboard.Key.f8,
    }

    target_key = key_map.get(config.get('hotkey', 'cmd_l'), keyboard.Key.cmd)
    last_trigger = [0]

    def on_press(k):
        if time.time() - last_trigger[0] < 0.5:
            return
        if k == target_key:
            last_trigger[0] = time.time()
            toggle_recording()

    listener = keyboard.Listener(on_press=on_press)
    listener.start()

    print("✓ 已启动，按左 Command 开始录音")
    print()

    # 保持运行
    while True:
        time.sleep(1)


if __name__ == '__main__':
    main()
