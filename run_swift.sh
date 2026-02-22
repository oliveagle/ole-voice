#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate

# 检查 Swift 程序
if [ ! -f "VoiceOverlay/VoiceOverlay" ]; then
    echo "编译 Swift 程序..."
    cd VoiceOverlay
    chmod +x build.sh
    ./build.sh
    cd ..
fi

# 启动 Swift 悬浮窗
echo "启动 Swift 悬浮窗..."
./VoiceOverlay/VoiceOverlay &
echo $! > /tmp/voice_overlay.pid
sleep 1

# 启动 Python
echo "启动语音输入..."
python3 voice_with_overlay.py

# 清理
kill $(cat /tmp/voice_overlay.pid) 2>/dev/null
