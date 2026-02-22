#!/bin/bash
# 语音输入工具启动脚本

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 检查虚拟环境
if [ ! -d "venv" ]; then
    echo "❌ 虚拟环境不存在，请先运行 ./install.sh"
    exit 1
fi

# 激活虚拟环境
source venv/bin/activate

# 检查依赖（快速检查，不输出）
if ! python3 -c "import pyaudio, pynput, faster_whisper" 2>/dev/null; then
    echo "⚠️ 依赖未安装，正在安装..."
    pip install -q -r requirements.txt
fi

# 运行程序
echo "🎙️  启动语音输入工具..."
echo "   快捷键: F8 (开始/停止录音)"
echo "   按 Ctrl+C 退出"
echo ""

python3 voice_input.py "$@"
