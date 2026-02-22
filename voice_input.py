#!/usr/bin/env python3
"""
本地语音输入工具 - macOS
按快捷键录音，再按停止，自动输入转换后的文字
"""

import os
import sys
import time
import threading
import wave
import tempfile
import subprocess
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
stop_recording_event = threading.Event()
audio_frames = []
config = {}
keyboard_controller = KeyboardController()
model_instance = None  # 缓存模型实例


def load_config():
    """加载配置文件"""
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def get_model(model_size, device, compute_type, download_root):
    """获取或创建模型实例（带缓存）"""
    global model_instance

    if model_instance is None:
        from faster_whisper import WhisperModel, download_model

        # 检查模型是否已下载
        if download_root is None:
            download_root = Path.home() / '.cache' / 'whisper'
        else:
            download_root = Path(download_root)

        model_path = download_root / f'models--Systran--faster-whisper-{model_size}'
        snapshot_path = model_path / 'snapshots'

        if not snapshot_path.exists() or not any(snapshot_path.iterdir()):
            print(f"⚠ 模型 {model_size} 未下载，开始下载...")
            print(f"   下载位置: {download_root}")
            try:
                # 使用 download_model 预先下载
                download_model(model_size, output_dir=download_root)
                print(f"✓ 模型 {model_size} 下载完成")
            except Exception as e:
                print(f"⚠ 预下载失败，将尝试自动下载: {e}")
        else:
            print(f"✓ 模型 {model_size} 已存在")

        print(f"正在加载模型: {model_size} (设备: {device}, 计算类型: {compute_type})...")
        try:
            model_instance = WhisperModel(
                model_size,
                device=device,
                compute_type=compute_type,
                download_root=str(download_root)
            )
            print("✓ 模型加载完成")
        except Exception as e:
            print(f"✗ 模型加载失败: {e}")
            raise

    return model_instance


def record_audio(sample_rate=16000, device_index=None, silence_timeout=0, max_duration=60):
    """录音线程函数"""
    global is_recording, audio_frames

    audio = pyaudio.PyAudio()

    # 打开音频流
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

            # 检查音量（简单的静音检测）
            if silence_timeout > 0:
                audio_data = bytes(data)
                max_val = max(abs(int.from_bytes(audio_data[i:i+2], 'little', signed=True))
                             for i in range(0, len(audio_data), 2))
                if max_val > 500:  # 阈值
                    last_sound_time = time.time()
                elif time.time() - last_sound_time > silence_timeout:
                    print("检测到静音，自动停止")
                    is_recording = False
                    break

            # 检查最大时长
            if time.time() - start_time > max_duration:
                print("达到最大录音时长，自动停止")
                is_recording = False
                break

        except Exception as e:
            print(f"录音错误: {e}")
            break

    # 停止录音
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


def transcribe_audio(model, audio_path, language):
    """使用模型转录音频"""
    segments, info = model.transcribe(
        audio_path,
        language=None if language == "auto" else language,
        vad_filter=True,
        vad_parameters=dict(min_silence_duration_ms=500),
        condition_on_previous_text=False,
    )

    text = " ".join([segment.text for segment in segments])
    return text.strip()


def type_text(text):
    """模拟键盘输入文字"""
    print(f"[DEBUG] type_text 开始，输入内容: '{text}'")

    # 增加延迟，确保 Command 键已释放
    print("[DEBUG] 等待 0.5 秒确保按键释放...")
    time.sleep(0.5)

    try:
        # 方法1: 使用 pynput 模拟键盘输入
        print("[DEBUG] 使用 pynput 输入文字...")
        keyboard_controller.type(text)
        print("[DEBUG] pynput 输入完成")
    except Exception as e:
        print(f"[DEBUG] pynput 输入失败: {e}")
        # 方法2: 使用 AppleScript 输入
        try:
            print("[DEBUG] 尝试使用 AppleScript 输入...")
            safe_text = text.replace('"', '\\"').replace("'", "\\'")
            cmd = f'''osascript -e 'tell application "System Events" to keystroke "{safe_text}"' '''
            result = os.system(cmd)
            print(f"[DEBUG] AppleScript 执行结果: {result}")
        except Exception as e2:
            print(f"[DEBUG] AppleScript 输入也失败: {e2}")


def paste_text(text):
    """复制到剪贴板并粘贴"""
    print("[DEBUG] paste_text 开始")
    pyperclip.copy(text)
    print("[DEBUG] 已复制到剪贴板")
    time.sleep(0.2)

    try:
        # 模拟 Cmd+V 粘贴
        print("[DEBUG] 模拟 Cmd+V 粘贴...")
        with keyboard_controller.pressed(keyboard.Key.cmd):
            keyboard_controller.press('v')
            keyboard_controller.release('v')
        print("[DEBUG] 粘贴完成")
    except Exception as e:
        print(f"[DEBUG] 粘贴失败: {e}")
        # 使用 AppleScript 粘贴
        try:
            os.system("osascript -e 'tell application \"System Events\" to keystroke \"v\" using command down'")
        except Exception as e2:
            print(f"[DEBUG] AppleScript 粘贴也失败: {e2}")


def show_notification(title, message):
    """显示 macOS 通知"""
    try:
        # 转义特殊字符
        message = message.replace('"', '\\"').replace("'", "\\'")
        title = title.replace('"', '\\"').replace("'", "\\'")
        os.system(f'''osascript -e 'display notification "{message}" with title "{title}"' ''')
    except:
        pass


def on_hotkey():
    """快捷键回调函数"""
    global is_recording, recording_thread

    if not is_recording:
        # 开始录音
        print("\n[DEBUG] 收到快捷键，开始录音...")
        is_recording = True
        stop_recording_event.clear()

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
        # 停止录音
        print("\n[DEBUG] 收到快捷键，停止录音...")
        is_recording = False
        recording_thread.join()

        print(f"[DEBUG] 录音结束，音频帧数: {len(audio_frames)}")
        show_notification("语音输入", "处理中...")

        # 保存录音
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
            audio_path = tmp.name

        print(f"[DEBUG] 保存音频到: {audio_path}")
        save_audio(
            audio_frames,
            config['recording'].get('sample_rate', 16000),
            audio_path
        )
        print("[DEBUG] 音频保存完成")

        # 转录
        try:
            model_config = config['model']
            download_root = model_config.get('download_root')
            if download_root:
                download_root = os.path.expanduser(download_root)

            print("[DEBUG] 加载模型...")
            model = get_model(
                model_config['size'],
                model_config.get('device', 'auto'),
                model_config.get('compute_type', 'int8'),
                download_root
            )

            print(f"[DEBUG] 开始转录 (语言: {model_config.get('language', 'auto')})...")
            text = transcribe_audio(
                model,
                audio_path,
                model_config.get('language', 'auto')
            )

            print(f"[DEBUG] 转录完成，原文: '{text}'")

            if text:
                print(f"✓ 识别结果: {text}")

                # 输出文字
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
                print("⚠ 未能识别语音 (返回空文本)")
                show_notification("语音输入", "未能识别语音")

        except Exception as e:
            print(f"✗ 转录错误: {e}")
            import traceback
            traceback.print_exc()
            show_notification("语音输入失败", str(e)[:100])

        finally:
            # 清理录音文件
            if not config['output'].get('keep_audio', False):
                try:
                    os.unlink(audio_path)
                    print("[DEBUG] 临时音频文件已删除")
                except Exception as e:
                    print(f"[DEBUG] 删除临时文件失败: {e}")
            else:
                # 保存到指定目录
                try:
                    audio_dir = Path(os.path.expanduser(
                        config['output'].get('audio_path', '~/voice_recordings')
                    ))
                    audio_dir.mkdir(parents=True, exist_ok=True)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    new_path = audio_dir / f"recording_{timestamp}.wav"
                    os.rename(audio_path, new_path)
                    print(f"[DEBUG] 音频已保存到: {new_path}")
                except Exception as e:
                    print(f"保存录音文件失败: {e}")


def parse_hotkey_for_listener(hotkey_str):
    """解析快捷键，返回适合 Listener 的按键"""
    key_map = {
        'cmd_r': keyboard.Key.cmd_r,
        'cmd_l': keyboard.Key.cmd,  # macOS 上 cmd_l 就是 cmd
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

    # 检查是否是特殊按键
    if hotkey_lower in key_map:
        return key_map[hotkey_lower], None  # 单键

    # 解析组合键
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
    print("🎙  本地语音输入工具")
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

    # 用于检测组合键的状态
    current_keys = set()
    last_trigger_time = 0
    trigger_cooldown = 0.5  # 防止重复触发的冷却时间

    def on_press(k):
        nonlocal last_trigger_time
        current_keys.add(k)

        # 检查冷却时间
        if time.time() - last_trigger_time < trigger_cooldown:
            return

        if modifiers is None:
            # 单键模式 (如 cmd_l, cmd_r, f8)
            if k == key:
                last_trigger_time = time.time()
                threading.Thread(target=on_hotkey, daemon=True).start()
        else:
            # 组合键模式
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
