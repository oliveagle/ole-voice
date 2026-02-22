#!/usr/bin/env python3
"""
语音输入工具 - macOS 原生悬浮窗版本
"""

import os
import sys
import threading
import time
import wave
import tempfile
import signal
import random
from pathlib import Path

import yaml
import pyaudio
import pyperclip
from pynput import keyboard
from pynput.keyboard import Controller, Key

# AppKit 导入
from Foundation import NSObject, NSThread
from AppKit import (
    NSApplication, NSWindow, NSView, NSColor, NSFont,
    NSTextField, NSButton,
    NSFloatingWindowLevel, NSNormalWindowLevel,
    NSBorderlessWindowMask, NSFullSizeContentViewWindowMask,
    NSMakeRect, NSScreen,
    NSApplicationActivationPolicyAccessory,
)
from PyObjCTools import AppHelper
import objc

# 全局状态
is_recording = False
recording_thread = None
audio_frames = []
config = {}
controller = Controller()

# UI 引用
app_window = None
app_wave_view = None


class WaveView(NSView):
    """音波动画视图"""

    def initWithFrame_(self, frame):
        self = objc.super(WaveView, self).initWithFrame_(frame)
        if self is None:
            return None
        self.amplitudes = [0.5] * 5
        self.running = False
        return self

    def drawRect_(self, rect):
        try:
            bar_width = 4
            bar_gap = 6
            total_width = 5 * bar_width + 4 * bar_gap
            view_width = self.frame().size.width
            view_height = self.frame().size.height
            start_x = (view_width - total_width) / 2
            center_y = view_height / 2

            for i, amp in enumerate(self.amplitudes):
                bar_height = 4 + amp * 20
                x = start_x + i * (bar_width + bar_gap)
                y = center_y - bar_height / 2

                bar_rect = NSMakeRect(x, y, bar_width, bar_height)
                path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
                    bar_rect, 2, 2
                )

                # 绿色音波
                NSColor.colorWithRed_green_blue_alpha_(
                    0.0, 0.82, 0.42, 1.0
                ).setFill()
                path.fill()
        except:
            pass

    def updateWave(self):
        """更新音波（在主线程调用）"""
        if self.running:
            self.amplitudes = [random.uniform(0.2, 1.0) for _ in range(5)]
            self.setNeedsDisplay_(True)
            # 下次更新
            self.performSelector_withObject_afterDelay_(
                'updateWave', None, 0.08
            )

    def start(self):
        self.running = True
        self.updateWave()

    def stop(self):
        self.running = False


class VoiceWindow(NSObject):
    """悬浮窗控制器"""

    window = None
    waveView = None

    def create(self):
        try:
            screen = NSScreen.mainScreen()
            screen_frame = screen.frame()

            w, h = 200, 50
            x = (screen_frame.size.width - w) / 2
            y = 100

            self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
                NSMakeRect(x, y, w, h),
                NSBorderlessWindowMask | NSFullSizeContentViewWindowMask,
                2, False
            )

            self.window.setLevel_(NSFloatingWindowLevel)
            self.window.setOpaque_(False)
            self.window.setBackgroundColor_(NSColor.clearColor())
            self.window.setHasShadow_(True)

            # 内容
            content = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, w, h))

            # 背景
            bg = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, w, h))
            bg.setWantsLayer_(True)
            bg.layer().setBackgroundColor_(
                NSColor.colorWithRed_green_blue_alpha_(0.1, 0.1, 0.1, 0.95).CGColor()
            )
            bg.layer().setCornerRadius_(25)
            content.addSubview_(bg)

            # 文字
            label = NSTextField.alloc().initWithFrame_(NSMakeRect(15, 12, 80, 26))
            label.setStringValue_("语音输入")
            label.setTextColor_(NSColor.whiteColor())
            font = NSFont.fontWithName_size_("PingFang SC", 14)
            if font is None:
                font = NSFont.systemFontOfSize_(14)
            label.setFont_(font)
            label.setEditable_(False)
            label.setBordered_(False)
            label.setBackgroundColor_(NSColor.clearColor())
            content.addSubview_(label)

            # 分隔线
            line = NSView.alloc().initWithFrame_(NSMakeRect(100, 12, 1, 26))
            line.setWantsLayer_(True)
            line.layer().setBackgroundColor_(
                NSColor.colorWithRed_green_blue_alpha_(0.27, 0.27, 0.27, 1.0).CGColor()
            )
            content.addSubview_(line)

            # 音波
            self.waveView = WaveView.alloc().initWithFrame_(NSMakeRect(110, 0, 80, 50))
            content.addSubview_(self.waveView)

            self.window.setContentView_(content)
            self.window.orderOut_(None)

            return True
        except Exception as e:
            print(f"创建窗口错误: {e}")
            return False

    def show(self):
        if self.window:
            self.window.makeKeyAndOrderFront_(None)
            if self.waveView:
                self.waveView.start()

    def hide(self):
        if self.window:
            if self.waveView:
                self.waveView.stop()
            self.window.orderOut_(None)


class AppDelegate(NSObject):
    """应用代理"""

    window = None
    listener = None
    recording = False

    def applicationDidFinishLaunching_(self, notification):
        global config

        print("=" * 50)
        print("🎙  语音输入工具 - 悬浮窗版本")
        print("=" * 50)

        # 加载配置
        try:
            config_path = Path(__file__).parent / "config.yaml"
            with open(config_path, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f)
        except:
            config = {}

        hotkey = config.get('hotkey', 'cmd_l')
        print(f"快捷键: {hotkey}")
        print(f"语言: {config.get('model', {}).get('language', 'zh')}")
        print("-" * 50)

        # 创建窗口
        self.window = VoiceWindow.alloc().init()
        if not self.window.create():
            print("创建窗口失败")
            AppHelper.stopEventLoop()
            return

        # 启动键盘监听
        self.startListener()

        print("✓ 已启动，按左 Command 开始录音")

    def startListener(self):
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
                self.performSelectorOnMainThread_withObject_waitUntilDone_(
                    'toggleRecording', None, False
                )

        self.listener = keyboard.Listener(on_press=on_press)
        self.listener.start()

    def toggleRecording(self):
        """切换录音状态"""
        global is_recording, recording_thread

        if not is_recording:
            # 开始录音
            is_recording = True
            self.recording = True
            self.window.show()

            recording_thread = threading.Thread(target=self.recordAudio, daemon=True)
            recording_thread.start()
        else:
            # 停止录音
            is_recording = False
            self.recording = False
            if recording_thread:
                recording_thread.join(timeout=2)

            self.window.hide()
            self.processAudio()

    def recordAudio(self):
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

    def processAudio(self):
        """处理音频"""
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
            text = self.doTranscribe_(path)

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

    def doTranscribe_(self, audio_path):
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


def main():
    signal.signal(signal.SIGINT, lambda s, f: AppHelper.stopEventLoop())

    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

    delegate = AppDelegate.alloc().init()
    app.setDelegate_(delegate)

    AppHelper.runEventLoop()


if __name__ == '__main__':
    main()
