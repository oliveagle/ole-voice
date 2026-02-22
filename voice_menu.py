#!/usr/bin/env python3
"""
语音输入工具 - 菜单栏版本 (稳定可靠)
使用 rumps 创建 macOS 菜单栏应用
"""

import rumps
import threading
import time
import wave
import tempfile
import os
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
app = None


def load_config():
    """加载配置"""
    try:
        config_path = Path(__file__).parent / "config.yaml"
        with open(config_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except:
        return {}


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
        text = transcribe_audio(path)

        if text:
            # 粘贴
            pyperclip.copy(text)
            time.sleep(0.1)
            with controller.pressed(Key.cmd):
                controller.press('v')
                controller.release('v')

            # 显示结果
            rumps.notification("语音输入", "识别完成", text)
        else:
            rumps.notification("语音输入", "提示", "未能识别语音")

        # 清理
        try:
            os.unlink(path)
        except:
            pass

    except Exception as e:
        rumps.notification("语音输入", "错误", str(e))


def toggle_recording():
    """切换录音状态"""
    global is_recording, recording_thread

    if not is_recording:
        # 开始录音
        is_recording = True
        app.title = "🔴 录音中..."

        recording_thread = threading.Thread(target=record_audio, daemon=True)
        recording_thread.start()

        # 显示 HUD 提示
        rumps.notification("语音输入", "开始录音", "请说话，再次按快捷键停止")
    else:
        # 停止录音
        is_recording = False
        if recording_thread:
            recording_thread.join(timeout=2)

        app.title = "🎤"

        # 处理录音
        threading.Thread(target=process_recording, daemon=True).start()


class VoiceApp(rumps.App):
    """语音输入菜单栏应用"""

    def __init__(self):
        global config
        config = load_config()

        super().__init__(
            name="语音输入",
            title="🎤",
            icon=None,
            menu=[
                rumps.MenuItem("开始录音", callback=self.on_record),
                rumps.MenuItem("设置", callback=self.on_settings),
                None,  # 分隔线
                rumps.MenuItem("退出", callback=self.on_quit),
            ]
        )

        # 启动键盘监听
        self.start_keyboard_listener()

    def start_keyboard_listener(self):
        """启动键盘监听"""
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
                # 在主线程执行
                rumps.Timer(lambda _: toggle_recording(), 0.01).start()

        self.listener = keyboard.Listener(on_press=on_press)
        self.listener.start()

    def on_record(self, _):
        """菜单点击：录音"""
        toggle_recording()

    def on_settings(self, _):
        """菜单点击：设置"""
        rumps.alert("设置", "编辑 config.yaml 文件修改配置")

    def on_quit(self, _):
        """菜单点击：退出"""
        rumps.quit_application()


def main():
    global app
    app = VoiceApp()
    app.run()


if __name__ == '__main__':
    main()
