#!/usr/bin/env python3
"""
语音输入悬浮窗 UI - macOS 原生 (AppKit)
黑色圆角悬浮条 + 音波动画
"""

import objc
from Foundation import NSObject, NSTimer
from AppKit import (
    NSApplication, NSWindow, NSView,
    NSTextField, NSTextFieldCell,
    NSColor, NSFont, NSAttributedString,
    NSBezierPath, NSRectFill, NSGraphicsContext,
    NSMakeRect, NSMakeSize,
    NSVisualEffectView, NSAppearance,
    NSVisualEffectMaterial, NSVisualEffectState,
    NSFloatingWindowLevel, NSNormalWindowLevel,
    NSBorderlessWindowMask,
    NSFullSizeContentViewWindowMask,
    NSViewMinXMargin, NSViewMaxXMargin,
    NSViewMinYMargin, NSViewMaxYMargin,
    NSAnimationContext,
    NSScreen,
)
from PyObjCTools import AppHelper
import threading
import time
import math
import random


class WaveView(NSView):
    """音波动画视图"""

    def initWithFrame_(self, frame):
        self = objc.super(WaveView, self).initWithFrame_(frame)
        if self is None:
            return None

        self.amplitudes = [0.3, 0.5, 0.8, 0.6, 0.4]  # 音波振幅
        self.animation_running = False
        self.timer = None
        return self

    def drawRect_(self, rect):
        """绘制音波"""
        context = NSGraphicsContext.currentContext()

        # 绘制5个音波条
        bar_width = 4
        bar_gap = 6
        total_width = 5 * bar_width + 4 * bar_gap
        start_x = (self.frame().size.width - total_width) / 2
        center_y = self.frame().size.height / 2

        for i, amp in enumerate(self.amplitudes):
            bar_height = 8 + amp * 16  # 基础高度 + 振幅变化
            x = start_x + i * (bar_width + bar_gap)
            y = center_y - bar_height / 2

            bar_rect = NSMakeRect(x, y, bar_width, bar_height)
            path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
                bar_rect, 2, 2
            )

            # 绿色音波
            color = NSColor.colorWithRed_green_blue_alpha_(
                0.0, 0.82, 0.42, 1.0  # #00d26a
            )
            color.setFill()
            path.fill()

    def start_animation(self):
        """开始音波动画"""
        if self.animation_running:
            return

        self.animation_running = True

        def animate():
            while self.animation_running:
                # 随机更新振幅
                self.amplitudes = [
                    random.uniform(0.2, 1.0) for _ in range(5)
                ]
                self.setNeedsDisplay_(True)
                time.sleep(0.08)

        self.animation_thread = threading.Thread(target=animate, daemon=True)
        self.animation_thread.start()

    def stop_animation(self):
        """停止动画"""
        self.animation_running = False


class VoiceInputWindow(NSWindow):
    """语音输入悬浮窗口"""

    def init(self):
        # 获取屏幕尺寸
        screen = NSScreen.mainScreen()
        screen_frame = screen.frame()

        window_width = 200
        window_height = 50

        x = (screen_frame.size.width - window_width) / 2
        y = 100  # 距离底部 100px

        self = objc.super(VoiceInputWindow, self).initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(x, y, window_width, window_height),
            NSBorderlessWindowMask | NSFullSizeContentViewWindowMask,
            2,  # NSBackingStoreBuffered
            False
        )

        if self is None:
            return None

        # 窗口设置
        self.setLevel_(NSFloatingWindowLevel)  # 置顶
        self.setOpaque_(False)
        self.setBackgroundColor_(NSColor.clearColor())
        self.setHasShadow_(True)
        self.setMovableByWindowBackground_(False)

        # 创建内容视图
        content_view = NSView.alloc().initWithFrame_(
            NSMakeRect(0, 0, window_width, window_height)
        )

        # 圆角背景
        background = NSView.alloc().initWithFrame_(
            NSMakeRect(0, 0, window_width, window_height)
        )
        background.setWantsLayer_(True)
        background.layer().setBackgroundColor_(
            NSColor.colorWithRed_green_blue_alpha_(
                0.1, 0.1, 0.1, 0.95  # #1a1a1a 深灰半透明
            ).CGColor()
        )
        background.layer().setCornerRadius_(20)
        background.layer().setBorderWidth_(0.5)
        background.layer().setBorderColor_(
            NSColor.colorWithRed_green_blue_alpha_(
                0.2, 0.2, 0.2, 1.0
            ).CGColor()
        )
        content_view.addSubview_(background)

        # 文字标签 - 语音输入
        label = NSTextField.alloc().initWithFrame_(
            NSMakeRect(20, 12, 80, 26)
        )
        label.setStringValue_("语音输入")
        label.setTextColor_(NSColor.whiteColor())
        label.setFont_(NSFont.fontWithName_size_("PingFang SC", 14))
        label.setEditable_(False)
        label.setBordered_(False)
        label.setBackgroundColor_(NSColor.clearColor())
        label.setAlignment_(1)  # 居中
        content_view.addSubview_(label)

        # 分隔线
        separator = NSView.alloc().initWithFrame_(
            NSMakeRect(100, 12, 1, 26)
        )
        separator.setWantsLayer_(True)
        separator.layer().setBackgroundColor_(
            NSColor.colorWithRed_green_blue_alpha_(
                0.27, 0.27, 0.27, 1.0  # #444444
            ).CGColor()
        )
        content_view.addSubview_(separator)

        # 音波动画视图
        self.wave_view = WaveView.alloc().initWithFrame_(
            NSMakeRect(110, 0, 80, 50)
        )
        content_view.addSubview_(self.wave_view)

        self.setContentView_(content_view)

        # 初始隐藏
        self.orderOut_(None)

        return self

    def show(self):
        """显示窗口"""
        self.makeKeyAndOrderFront_(None)
        self.wave_view.start_animation()

    def hide(self):
        """隐藏窗口"""
        self.wave_view.stop_animation()
        self.orderOut_(None)


class VoiceInputUI:
    """语音输入悬浮窗管理器"""

    def __init__(self):
        self.window = None
        self.is_showing = False

    def create_window(self):
        """创建窗口"""
        # 确保有 NSApplication
        app = NSApplication.sharedApplication()
        self.window = VoiceInputWindow.alloc().init()

    def show(self):
        """显示悬浮窗"""
        if self.is_showing:
            return

        if self.window is None:
            self.create_window()

        self.is_showing = True
        self.window.show()

    def hide(self):
        """隐藏悬浮窗"""
        if not self.is_showing:
            return

        self.is_showing = False
        if self.window:
            self.window.hide()

    def toggle(self):
        """切换显示/隐藏"""
        if self.is_showing:
            self.hide()
        else:
            self.show()


# 测试
if __name__ == '__main__':
    import signal
    signal.signal(signal.SIGINT, lambda s, f: AppHelper.stopEventLoop())

    ui = VoiceInputUI()

    print("测试语音输入悬浮窗")
    print("2秒后显示...")

    def test():
        time.sleep(2)
        ui.show()
        print("显示中，3秒后隐藏...")
        time.sleep(3)
        ui.hide()
        print("已隐藏，2秒后退出...")
        time.sleep(2)
        AppHelper.stopEventLoop()

    threading.Thread(target=test, daemon=True).start()
    AppHelper.runEventLoop()
