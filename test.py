#!/usr/bin/env python3
"""
语音输入工具 - 功能测试
"""

import sys
from pathlib import Path

def test_imports():
    """测试所有依赖是否能正常导入"""
    print("测试模块导入...")
    try:
        import pyaudio
        import pynput
        import faster_whisper
        import yaml
        import pyperclip
        print("  ✓ 所有模块导入成功")
        return True
    except ImportError as e:
        print(f"  ✗ 导入失败: {e}")
        return False

def test_audio_devices():
    """测试音频设备"""
    print("\n测试音频设备...")
    try:
        import pyaudio
        p = pyaudio.PyAudio()

        input_devices = []
        for i in range(p.get_device_count()):
            info = p.get_device_info_by_index(i)
            if info['maxInputChannels'] > 0:
                input_devices.append((i, info['name']))

        if input_devices:
            print(f"  ✓ 发现 {len(input_devices)} 个录音设备:")
            for idx, name in input_devices:
                print(f"    [{idx}] {name}")
        else:
            print("  ⚠ 未找到录音设备")

        p.terminate()
        return True
    except Exception as e:
        print(f"  ✗ 音频设备测试失败: {e}")
        return False

def test_config():
    """测试配置文件"""
    print("\n测试配置文件...")
    try:
        import yaml
        config_path = Path(__file__).parent / "config.yaml"
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)

        print(f"  ✓ 配置加载成功")
        print(f"    快捷键: {config.get('hotkey', 'f8')}")
        print(f"    模型: {config['model']['size']}")
        print(f"    输出模式: {config['output'].get('mode', 'type')}")
        return True
    except Exception as e:
        print(f"  ✗ 配置测试失败: {e}")
        return False

def test_model_download():
    """检查模型下载状态"""
    print("\n测试模型状态...")
    try:
        import yaml
        config_path = Path(__file__).parent / "config.yaml"
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)

        model_size = config['model']['size']
        download_root = Path.home() / '.cache' / 'whisper'

        # 检查模型目录
        model_dir = download_root / f'models--Systran--faster-whisper-{model_size}'
        if model_dir.exists():
            print(f"  ✓ 模型 {model_size} 已下载")
            return True
        else:
            print(f"  ○ 模型 {model_size} 未下载")
            print(f"    首次运行时会自动从 HuggingFace 下载")
            print(f"    如果下载慢，可以手动下载放到: {download_root}")
            return True
    except Exception as e:
        print(f"  ✗ 模型状态检查失败: {e}")
        return False

def main():
    print("=" * 50)
    print("🎙️  语音输入工具 - 功能测试")
    print("=" * 50)
    print()

    results = []
    results.append(("模块导入", test_imports()))
    results.append(("音频设备", test_audio_devices()))
    results.append(("配置文件", test_config()))
    results.append(("模型状态", test_model_download()))

    print()
    print("=" * 50)
    print("测试结果汇总")
    print("=" * 50)

    all_passed = True
    for name, passed in results:
        status = "✓ 通过" if passed else "✗ 失败"
        print(f"  {status}: {name}")
        if not passed:
            all_passed = False

    print()
    if all_passed:
        print("🎉 所有测试通过！可以运行 ./run.sh 启动")
        return 0
    else:
        print("⚠️  部分测试未通过，请检查错误信息")
        return 1

if __name__ == '__main__':
    sys.exit(main())
