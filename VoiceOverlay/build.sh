#!/bin/bash
# 编译 Swift 悬浮窗程序

cd "$(dirname "$0")"

echo "编译 VoiceOverlay..."

# 编译 Swift 程序 (输出到 /tmp 避免覆盖本目录)
swiftc -O main.swift -o /tmp/VoiceOverlayRun \
    -framework Cocoa \
    -framework Carbon \
    -framework AVFoundation \
    -framework CoreVideo

if [ $? -eq 0 ]; then
    echo "✓ 编译成功"
    echo "输出: /tmp/VoiceOverlayRun"
else
    echo "✗ 编译失败"
fi
