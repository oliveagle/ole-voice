#!/usr/bin/env python3
"""
语音输入悬浮窗 UI - 简化版本
使用 rumps 的弹出窗口显示录音状态
"""

import rumps
import threading
import time


class VoiceInputUI:
    """语音输入悬浮窗管理器"""

    def __init__(self):
        self.is_showing = False
        self.window = None

    def show(self):
        """显示录音状态"""
        if self.is_showing:
            return

        self.is_showing = True

        # rumps 的弹出窗口会在 2 秒后自动消失
        # 或者我们可以创建一个自定义窗口
        rumps.notification(
            title="🎤 语音输入",
            subtitle="正在录音...",
            message="请说话，再次按下快捷键停止",
            sound=False  # 静音
        )

    def hide(self):
        """隐藏状态"""
        self.is_showing = False
        # rumps 的通知会自动消失

    def toggle(self):
        """切换显示/隐藏"""
        if self.is_showing:
            self.hide()
        else:
            self.show()


# 如果用户想要一个真正的悬浮窗，可以使用这个基于 AppKit 的版本（需要在主线程运行）
class VoiceInputUINative:
    """原生 macOS 悬浮窗（必须在主线程使用）"""

    def __init__(self):
        self.is_showing = False
        self._create_in_main()

    def _create_in_main(self):
        """在主线程创建窗口"""
        from AppKit import (
            NSApplication, NSWindow, NSView, NSColor,
            NSFloatingWindowLevel, NSBorderlessWindowMask,
            NSTextField, NSFont, NSMakeRect
        )

        # 获取屏幕尺寸
        screen = NSScreen.mainScreen()
        screen_frame = screen.frame()

        window_width = 200
        window_height = 50
        x = (screen_frame.size.width - window_width) / 2
        y = 100

        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(x, y, window_width, window_height),
            NSBorderlessWindowMask,
            2,
            False
        )

        self.window.setLevel_(NSFloatingWindowLevel)
        self.window.setOpaque_(False)
        self.window.setBackgroundColor_(NSColor.blackColor())

        # 内容视图
        content = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, window_width, window_height))

        # 文字
        label = NSTextField.alloc().initWithFrame_(NSMakeRect(20, 12, 160, 26))
        label.setStringValue_("🎤 正在录音...")
        label.setTextColor_(NSColor.whiteColor())
        label.setFont_(NSFont.systemFontOfSize_(14))
        label.setEditable_(False)
        label.setBordered_(False)
        label.setBackgroundColor_(NSColor.clearColor())

        content.addSubview_(label)
        self.window.setContentView_(content)

    def show(self):
        if not self.is_showing:
            self.is_showing = True
            self.window.makeKeyAndOrderFront_(None)

    def hide(self):
        if self.is_showing:
            self.is_showing = False
            self.window.orderOut_(None)

    def toggle(self):
        if self.is_showing:
            self.hide()
        else:
            self.show()


if __name__ == '__main__':
    # 测试
    ui = VoiceInputUI()
    ui.show()
    print("显示中...")
    time.sleep(3)
    ui.hide()
    print("已隐藏")
