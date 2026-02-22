#!/bin/bash
# 语音输入工具启动脚本 - Swift + MLX ASR 混合架构

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 检查编译
if [ ! -f "VoiceOverlay/VoiceOverlay" ]; then
    echo "编译 Swift 程序..."
    cd VoiceOverlay
    chmod +x build.sh
    ./build.sh
    cd ..
fi

# 检查虚拟环境
if [ ! -d "venv" ]; then
    echo "❌ 虚拟环境不存在，请先运行 ./install_mlx.sh"
    exit 1
fi

source venv/bin/activate

# 启动 ASR 服务端
echo "启动 ASR 服务端..."
python3 VoiceOverlay/asr_server.py &
ASR_PID=$!
sleep 2

# 检查服务端是否启动
if ! kill -0 $ASR_PID 2>/dev/null; then
    echo "❌ ASR 服务端启动失败"
    exit 1
fi
echo "✓ ASR 服务端已启动 (PID: $ASR_PID)"

# 设置清理函数
cleanup() {
    echo ""
    echo "关闭 ASR 服务端..."
    kill $ASR_PID 2>/dev/null
    wait $ASR_PID 2>/dev/null
    exit 0
}

# 捕获 Ctrl+C 和退出信号
trap cleanup SIGINT SIGTERM EXIT

# 启动 Swift GUI (前台运行，这样 Ctrl+C 可以捕获到)
echo ""
echo "启动 VoiceOverlay..."
cd VoiceOverlay
./VoiceOverlay

# 清理 (如果 VoiceOverlay 正常退出)
cleanup

