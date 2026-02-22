#!/usr/bin/env python3
"""
模型切换工具 - 切换 ASR 模型 (0.6B / 1.7B)
用法:
    python switch_model.py          # 查看当前模型和可用选项
    python switch_model.py 0.6B     # 切换到小模型
    python switch_model.py 1.7B     # 切换到大模型
"""

import sys
import yaml
from pathlib import Path

def get_config_path():
    """获取配置文件路径"""
    return Path(__file__).parent / "config.yaml"

def load_config():
    """加载配置"""
    config_path = get_config_path()
    if not config_path.exists():
        print(f"❌ 配置文件不存在: {config_path}")
        return None

    with open(config_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f) or {}

def save_config(config):
    """保存配置"""
    config_path = get_config_path()
    with open(config_path, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, allow_unicode=True, sort_keys=False)

def show_status(config):
    """显示当前状态"""
    print("\n📊 当前 ASR 配置")
    print("-" * 40)

    asr_config = config.get('asr', {})
    current_model = asr_config.get('model', '0.6B')
    language = asr_config.get('language', 'zh')
    models = asr_config.get('models', {
        '0.6B': 'mlx-community/Qwen3-ASR-0.6B-8bit',
        '1.7B': 'mlx-community/Qwen3-ASR-1.7B-8bit'
    })

    print(f"🎯 当前模型: {current_model}")
    print(f"   路径: {models.get(current_model, 'N/A')}")
    print(f"🌐 语言: {language}")
    print("\n📦 可用模型:")
    for key, path in models.items():
        marker = " ✅" if key == current_model else ""
        desc = "快速，内存占用小" if key == "0.6B" else "高精度，质量更好"
        print(f"   {key}: {desc}{marker}")

    print("\n💡 使用方法:")
    print(f"   python {sys.argv[0]} 0.6B    # 切换到小模型")
    print(f"   python {sys.argv[0]} 1.7B    # 切换到大模型")
    print("\n⚠️  注意: 切换模型后需要重启 ASR 服务才能生效")

def switch_model(model_key):
    """切换模型"""
    config = load_config()
    if config is None:
        return False

    # 确保 asr 配置存在
    if 'asr' not in config:
        config['asr'] = {
            'model': '0.6B',
            'language': 'zh',
            'models': {
                '0.6B': 'mlx-community/Qwen3-ASR-0.6B-8bit',
                '1.7B': 'mlx-community/Qwen3-ASR-1.7B-8bit'
            }
        }

    models = config['asr'].get('models', {})

    if model_key not in models:
        print(f"❌ 未知模型: {model_key}")
        print(f"可用模型: {', '.join(models.keys())}")
        return False

    old_model = config['asr'].get('model', '0.6B')
    config['asr']['model'] = model_key

    save_config(config)

    print(f"✅ 模型已切换: {old_model} → {model_key}")
    print(f"   新模型: {models[model_key]}")
    print("\n⚠️  请重启 VoiceOverlay 以应用新配置:")
    print("   pkill VoiceOverlay; pkill asr_server")
    print("   ./VoiceOverlay/VoiceOverlay")

    return True

def main():
    if len(sys.argv) < 2:
        # 显示当前状态
        config = load_config()
        if config:
            show_status(config)
        return

    model_key = sys.argv[1]

    if model_key in ('-h', '--help', 'help'):
        print(__doc__)
        return

    switch_model(model_key)

if __name__ == '__main__':
    main()
