#!/bin/bash
# 语音输入工具启动脚本 - MLX 版本 (Apple Silicon 优化)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 检查虚拟环境
if [ ! -d "venv" ]; then
    echo "❌ 虚拟环境不存在，请先运行 ./install_mlx.sh"
    exit 1
fi

source venv/bin/activate

# 检查 MLX 依赖
if ! python3 -c "import mlx_whisper" 2>/dev/null; then
    echo "⚠️ MLX 依赖未安装，正在安装..."
    pip install -q mlx-whisper
fi

echo "🎙️  启动语音输入工具 (MLX 版本 - Apple Silicon 优化)..."
echo "   快捷键: $(grep 'hotkey:' config.yaml | head -1 | cut -d'"' -f2)"
echo "   模型: $(grep 'size:' config.yaml | head -1 | cut -d'"' -f2)"
echo "   按 Ctrl+C 退出"
echo ""

python3 voice_input_mlx.py "$@"
