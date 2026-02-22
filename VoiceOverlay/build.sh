#!/bin/bash
# 编译 Swift 悬浮窗程序

cd "$(dirname "$0")"

echo "编译 VoiceOverlay..."

# 编译 Swift 程序
swiftc -O main.swift -o VoiceOverlay \
    -framework Cocoa \
    -framework Carbon \
    -framework AVFoundation

if [ $? -eq 0 ]; then
    echo "✓ 编译成功"
    echo "运行: ./VoiceOverlay"
else
    echo "✗ 编译失败"
fi
