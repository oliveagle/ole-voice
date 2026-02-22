#!/bin/bash
# 语音输入工具 - 最终版本 (带终端音波 UI)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -d "venv" ]; then
    echo "❌ 虚拟环境不存在，请先运行 ./install_mlx.sh"
    exit 1
fi

source venv/bin/activate

echo "🎙️  启动语音输入工具..."
echo "   快捷键: 左 Command"
echo "   模型: Qwen3-ASR (中文优化)"
echo "   按 Ctrl+C 退出"
echo ""

python3 voice_input_final.py "$@"
