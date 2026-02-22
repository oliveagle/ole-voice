#!/usr/bin/env python3
"""
语音输入工具诊断脚本
用于排查问题
"""

import os
import sys
from pathlib import Path

print("=" * 60)
print("🩺 语音输入工具 - 诊断模式")
print("=" * 60)
print()

# 1. 检查 Python 版本
print("1. Python 版本")
print(f"   版本: {sys.version}")
print()

# 2. 检查依赖模块
print("2. 依赖模块检查")
try:
    import pyaudio
    print("   ✓ pyaudio 已安装")
except ImportError as e:
    print(f"   ✗ pyaudio 未安装: {e}")

try:
    import pynput
    print("   ✓ pynput 已安装")
except ImportError as e:
    print(f"   ✗ pynput 未安装: {e}")

try:
    import faster_whisper
    print("   ✓ faster-whisper 已安装")
except ImportError as e:
    print(f"   ✗ faster-whisper 未安装: {e}")

try:
    import yaml
    print("   ✓ pyyaml 已安装")
except ImportError as e:
    print(f"   ✗ pyyaml 未安装: {e}")

try:
    import pyperclip
    print("   ✓ pyperclip 已安装")
except ImportError as e:
    print(f"   ✗ pyperclip 未安装: {e}")

print()

# 3. 检查音频设备
print("3. 音频设备检查")
try:
    import pyaudio
    p = pyaudio.PyAudio()

    input_devices = []
    for i in range(p.get_device_count()):
        info = p.get_device_info_by_index(i)
        if info['maxInputChannels'] > 0:
            input_devices.append((i, info['name']))

    if input_devices:
        print(f"   ✓ 发现 {len(input_devices)} 个录音设备:")
        for idx, name in input_devices:
            print(f"     [{idx}] {name}")
    else:
        print("   ⚠ 未找到录音设备")

    p.terminate()
except Exception as e:
    print(f"   ✗ 音频设备检查失败: {e}")

print()

# 4. 检查模型状态
print("4. 模型状态检查")
try:
    import yaml
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)

    model_size = config['model']['size']
    download_root = Path.home() / '.cache' / 'whisper'
    model_path = download_root / f'models--Systran--faster-whisper-{model_size}'
    snapshot_path = model_path / 'snapshots'

    print(f"   配置模型: {model_size}")
    print(f"   模型路径: {model_path}")

    if snapshot_path.exists() and any(snapshot_path.iterdir()):
        print(f"   ✓ 模型 {model_size} 已下载")
        # 显示模型大小
        total_size = 0
        for file in model_path.rglob('*'):
            if file.is_file():
                total_size += file.stat().st_size
        print(f"   模型大小: {total_size / 1024 / 1024:.1f} MB")
    else:
        print(f"   ⚠ 模型 {model_size} 未下载")
        print(f"   首次使用时会自动下载")
except Exception as e:
    print(f"   ✗ 模型检查失败: {e}")

print()

# 5. 测试键盘权限
print("5. 键盘权限检查")
print("   尝试模拟键盘输入 'test'...")
try:
    from pynput.keyboard import Controller
    import time

    controller = Controller()
    time.sleep(0.5)
    controller.type("test")
    print("   ✓ 键盘模拟成功（应该在光标处看到 'test'）")
except Exception as e:
    print(f"   ✗ 键盘模拟失败: {e}")
    print("   请检查：系统偏好设置 → 安全性与隐私 → 辅助功能")

print()

# 6. 检查配置文件
print("6. 配置文件检查")
try:
    import yaml
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)

    print(f"   ✓ 配置文件加载成功")
    print(f"   快捷键: {config.get('hotkey', 'f8')}")
    print(f"   模型: {config['model']['size']}")
    print(f"   设备: {config['model'].get('device', 'auto')}")
    print(f"   输出模式: {config['output'].get('mode', 'type')}")
except Exception as e:
    print(f"   ✗ 配置文件错误: {e}")

print()
print("=" * 60)
print("诊断完成")
print("=" * 60)
