import Cocoa
import Carbon
import AVFoundation

// MARK: - 数值扩展 (小端字节序)
extension UInt32 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

extension UInt16 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

// MARK: - 全局快捷键管理器
class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var toggleCallback: (() -> Void)?
    var cancelCallback: (() -> Void)?

    private var isRegistered = false

    func registerHotkey(toggleCallback: @escaping () -> Void, cancelCallback: @escaping () -> Void) -> Bool {
        // 防止重复注册
        if isRegistered {
            print("[Hotkey] 已经注册过了")
            return true
        }

        self.toggleCallback = toggleCallback
        self.cancelCallback = cancelCallback

        // 监听 flagsChanged (修饰键) 和 keyDown (ESC 键)
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                return GlobalHotkeyManager.handleEvent(proxy: proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("⚠️ 无法创建事件监听，请授予辅助功能权限")
            return false
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRegistered = true
        return true
    }

    static func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
        let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()

        if type == .flagsChanged {
            let flags = event.flags
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)

            struct Static {
                static var lastTrigger: TimeInterval = 0
                static var wasRightCommandPressed = false
            }

            // 只处理右 Command (keycode 54)
            guard keycode == 54 else {
                return Unmanaged.passUnretained(event)
            }

            let isCommandPressed = flags.contains(.maskCommand)

            if isCommandPressed && !Static.wasRightCommandPressed {
                Static.wasRightCommandPressed = true
            } else if !isCommandPressed && Static.wasRightCommandPressed {
                Static.wasRightCommandPressed = false
                let now = Date().timeIntervalSince1970
                // 增加防抖动时间到 1 秒
                if now - Static.lastTrigger > 1.0 {
                    Static.lastTrigger = now
                    DispatchQueue.main.async {
                        manager.toggleCallback?()
                    }
                }
            }
        } else if type == .keyDown {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            // ESC 键 keycode 是 53
            if keycode == 53 {
                DispatchQueue.main.async {
                    manager.cancelCallback?()
                }
                // 消费 ESC 键事件，防止传递给其他应用
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

// MARK: - 悬浮窗控制器
class VoiceOverlayWindow: NSWindow {
    var waveView: WaveView!

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false

        setupUI()
    }

    func setupUI() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 44))

        // 毛玻璃效果背景
        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 140, height: 44))
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 22
        visualEffectView.layer?.masksToBounds = true

        // 深色半透明覆盖层
        let darkOverlay = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 44))
        darkOverlay.wantsLayer = true
        darkOverlay.layer?.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.85).cgColor
        darkOverlay.layer?.cornerRadius = 22

        // 精致的发光边框
        let borderView = NSView(frame: NSRect(x: 0.5, y: 0.5, width: 139, height: 43))
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 21.5
        borderView.layer?.borderWidth = 0.8
        borderView.layer?.borderColor = NSColor(red: 0.35, green: 0.35, blue: 0.4, alpha: 0.5).cgColor

        // 内部高光边框
        let innerBorder = NSView(frame: NSRect(x: 1.5, y: 1.5, width: 137, height: 41))
        innerBorder.wantsLayer = true
        innerBorder.layer?.cornerRadius = 20.5
        innerBorder.layer?.borderWidth = 0.5
        innerBorder.layer?.borderColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.06).cgColor

        // 文字标签 - 使用更细的字体
        let label = NSTextField(frame: NSRect(x: 14, y: 10, width: 52, height: 20))
        label.stringValue = "语音输入"
        label.textColor = NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
        // 使用更细的系统字体
        if #available(macOS 11.0, *) {
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        } else {
            label.font = NSFont(name: "PingFangSC-Medium", size: 12) ?? NSFont.systemFont(ofSize: 12)
        }
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = .left

        // 精致的分隔线 - 渐变效果
        let separator = NSView(frame: NSRect(x: 78, y: 10, width: 1, height: 24))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 0.35).cgColor

        // 音波视图
        waveView = WaveView(frame: NSRect(x: 79, y: 0, width: 56, height: 44))

        // 组装视图层次
        containerView.addSubview(visualEffectView)
        containerView.addSubview(darkOverlay)
        containerView.addSubview(borderView)
        containerView.addSubview(innerBorder)
        containerView.addSubview(label)
        containerView.addSubview(separator)
        containerView.addSubview(waveView)

        self.contentView = containerView
    }

    func showWindow() {
        // 使用 orderFrontRegardless 而不是 makeKeyAndOrderFront
        // 这样窗口显示但不会抢夺焦点
        self.orderFrontRegardless()
        waveView?.startAnimation()
    }

    func hideWindow() {
        waveView?.stopAnimation()
        self.orderOut(nil)
    }
}

// MARK: - 音波动画视图
class WaveView: NSView {
    private var bars: [CGFloat] = Array(repeating: 0.3, count: 5)
    private var targetBars: [CGFloat] = Array(repeating: 0.3, count: 5)
    private var isAnimating = false
    private var animationTimer: Timer?

    // 渐变色定义 (青色到蓝色)
    private let gradientColors = [
        NSColor(red: 0.0, green: 0.9, blue: 0.6, alpha: 1.0),   // 青绿
        NSColor(red: 0.0, green: 0.8, blue: 0.85, alpha: 1.0),  // 青蓝
        NSColor(red: 0.1, green: 0.65, blue: 1.0, alpha: 1.0),  // 蓝色
        NSColor(red: 0.3, green: 0.55, blue: 1.0, alpha: 1.0),  // 紫蓝
        NSColor(red: 0.1, green: 0.65, blue: 1.0, alpha: 1.0)   // 蓝色
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barWidth: CGFloat = 3
        let barGap: CGFloat = 4
        let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * barGap
        let startX = (bounds.width - totalWidth) / 2
        let maxBarHeight: CGFloat = 26
        let minBarHeight: CGFloat = 3
        let centerY = bounds.height / 2

        for (i, amplitude) in bars.enumerated() {
            let barHeight = minBarHeight + amplitude * (maxBarHeight - minBarHeight)
            let x = startX + CGFloat(i) * (barWidth + barGap)
            let y = centerY - barHeight / 2

            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)

            // 使用渐变色
            let color = gradientColors[i % gradientColors.count]
            color.setFill()
            path.fill()

            // 添加微妙的发光效果
            let glowPath = NSBezierPath(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5), xRadius: 2, yRadius: 2)
            color.withAlphaComponent(0.3).setStroke()
            glowPath.lineWidth = 0.5
            glowPath.stroke()
        }
    }

    func startAnimation() {
        isAnimating = true
        // 使用 Timer 替代 DispatchQueue 以获得更平滑的动画
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateAnimation()
        }
        RunLoop.current.add(animationTimer!, forMode: .common)
    }

    func stopAnimation() {
        isAnimating = false
        animationTimer?.invalidate()
        animationTimer = nil
        // 重置为平静状态
        bars = Array(repeating: 0.3, count: 5)
        needsDisplay = true
    }

    private func updateAnimation() {
        guard isAnimating else { return }

        // 生成新的目标值 (中间条形更高，形成波浪效果)
        let centerIndex = bars.count / 2
        targetBars = bars.indices.map { i in
            let distance = abs(i - centerIndex)
            let baseAmplitude = 1.0 - Double(distance) * 0.15
            let randomVariation = CGFloat.random(in: 0.3...1.0)
            return max(0.2, min(1.0, baseAmplitude * randomVariation))
        }

        // 平滑插值到目标值
        for i in bars.indices {
            let diff = targetBars[i] - bars[i]
            bars[i] += diff * 0.3 // 平滑系数
        }

        needsDisplay = true
    }
}

// MARK: - 录音管理器
class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var tempFileURL: URL?

    func startRecording() -> Bool {
        // 设置录音参数 16kHz, 16bit, 单声道
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        // 创建临时文件
        tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("voice_\(UUID().uuidString).wav")

        guard let url = tempFileURL else {
            print("[Audio] 无法创建临时文件")
            return false
        }

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()

            if audioRecorder?.record() == true {
                print("[Audio] 开始录音: \(url.path)")
                return true
            } else {
                print("[Audio] 录音启动失败")
                return false
            }
        } catch {
            print("[Audio] 录音错误: \(error)")
            return false
        }
    }

    func stopRecording() -> Data? {
        audioRecorder?.stop()

        guard let url = tempFileURL else {
            print("[Audio] 临时文件不存在")
            return nil
        }

        // 读取文件并添加 WAV 头
        do {
            let pcmData = try Data(contentsOf: url)
            let wavData = createWAVData(pcmData: pcmData, sampleRate: 16000, channels: 1, bitsPerSample: 16)
            print("[Audio] 录音结束，PCM: \(pcmData.count) bytes, WAV: \(wavData.count) bytes")

            // 清理临时文件
            try? FileManager.default.removeItem(at: url)

            return wavData
        } catch {
            print("[Audio] 读取录音文件失败: \(error)")
            return nil
        }
    }

    private func createWAVData(pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var wavData = Data()

        // RIFF chunk
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(fileSize.littleEndianBytes)
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt subchunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(UInt32(16).littleEndianBytes)
        wavData.append(UInt16(1).littleEndianBytes)
        wavData.append(channels.littleEndianBytes)
        wavData.append(sampleRate.littleEndianBytes)
        wavData.append(byteRate.littleEndianBytes)
        wavData.append(blockAlign.littleEndianBytes)
        wavData.append(bitsPerSample.littleEndianBytes)

        // data subchunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(dataSize.littleEndianBytes)
        wavData.append(pcmData)

        return wavData
    }
}

// MARK: - ASR 客户端
class ASRClient {
    static let shared = ASRClient()
    let socketPath = "/tmp/voice_asr_socket"

    func transcribe(audioData: Data, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                print("[ASR] 创建 socket...")
                let socket = try self.createSocket()
                defer { socket.close() }
                print("[ASR] Socket 连接成功")

                // 发送音频数据长度
                var length = UInt32(audioData.count).bigEndian
                let sentLen = withUnsafeBytes(of: &length) { socket.write(Data($0)) }
                print("[ASR] 发送长度: \(sentLen) bytes")

                // 发送音频数据
                let sentData = socket.write(audioData)
                print("[ASR] 发送数据: \(sentData) bytes")

                // 接收结果长度
                var resultLengthBuffer = Data(repeating: 0, count: 4)
                let readLen = socket.read(into: &resultLengthBuffer)
                print("[ASR] 读取长度: \(readLen) bytes")
                let resultLength = resultLengthBuffer.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                print("[ASR] 结果长度: \(resultLength)")

                // 接收结果
                var resultBuffer = Data(repeating: 0, count: Int(resultLength))
                let readResult = socket.read(into: &resultBuffer)
                print("[ASR] 读取结果: \(readResult) bytes")

                if let json = try? JSONSerialization.jsonObject(with: resultBuffer) as? [String: Any] {
                    print("[ASR] JSON: \(json)")
                    if let success = json["success"] as? Bool, success {
                        let text = json["text"] as? String
                        print("[ASR] 识别成功: \"\(text ?? "nil")\"")
                        DispatchQueue.main.async { completion(text) }
                        return
                    } else {
                        print("[ASR] 识别失败: success=\(json["success"] ?? "nil")")
                    }
                } else {
                    print("[ASR] JSON 解析失败")
                    if let str = String(data: resultBuffer, encoding: .utf8) {
                        print("[ASR] 原始响应: \(str)")
                    }
                }
                DispatchQueue.main.async { completion(nil) }
            } catch {
                print("[ASR] 通信错误: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func createSocket() throws -> Socket {
        let socket = try Socket.create(family: .unix, type: .stream, protocol: .unix)
        try socket.connect(to: socketPath)
        return socket
    }
}

// MARK: - Socket 包装类
class Socket {
    private var fd: Int32 = -1

    static func create(family: SocketFamily, type: SocketType, protocol: SocketProtocol) throws -> Socket {
        let socket = Socket()
        socket.fd = Darwin.socket(family.rawValue, type.rawValue, `protocol`.rawValue)
        if socket.fd < 0 {
            throw SocketError.createFailed
        }
        return socket
    }

    func connect(to path: String) throws {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        strncpy(&addr.sun_path.0, path, Int(strlen(path)) + 1)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if result < 0 {
            throw SocketError.connectFailed
        }
    }

    func write(_ data: Data) -> Int {
        return data.withUnsafeBytes { buffer in
            Darwin.write(fd, buffer.baseAddress!, buffer.count)
        }
    }

    func read(into buffer: inout Data) -> Int {
        return buffer.withUnsafeMutableBytes { mutableBuffer in
            Darwin.read(fd, mutableBuffer.baseAddress!, mutableBuffer.count)
        }
    }

    func close() {
        Darwin.close(fd)
    }

    enum SocketError: Error {
        case createFailed
        case connectFailed
    }

    enum SocketFamily {
        case unix
        var rawValue: Int32 {
            switch self {
            case .unix: return AF_UNIX
            }
        }
    }

    enum SocketType {
        case stream
        var rawValue: Int32 {
            switch self {
            case .stream: return SOCK_STREAM
            }
        }
    }

    enum SocketProtocol {
        case unix
        var rawValue: Int32 {
            return 0
        }
    }
}

// MARK: - 启动画面窗口
class SplashWindow: NSWindow {
    private var animationView: NSView!
    private var completionHandler: (() -> Void)?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true

        setupUI()
    }

    func setupUI() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 200))

        // 背景
        let bgView = NSView(frame: containerView.bounds)
        bgView.wantsLayer = true
        bgView.layer?.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.95).cgColor
        bgView.layer?.cornerRadius = 20
        bgView.layer?.masksToBounds = true

        // 边框
        let borderView = NSView(frame: NSRect(x: 1, y: 1, width: 278, height: 198))
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 19
        borderView.layer?.borderWidth = 1
        borderView.layer?.borderColor = NSColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 0.6).cgColor

        // 图标背景圆
        let iconBg = NSView(frame: NSRect(x: 110, y: 90, width: 60, height: 60))
        iconBg.wantsLayer = true
        iconBg.layer?.backgroundColor = NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.3).cgColor
        iconBg.layer?.cornerRadius = 30

        // 波形图标
        let waveContainer = NSView(frame: NSRect(x: 125, y: 105, width: 30, height: 30))

        // 3条波形线
        for i in 0..<3 {
            let line = NSView(frame: NSRect(x: CGFloat(i * 10), y: 5, width: 4, height: 20))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0).cgColor
            line.layer?.cornerRadius = 2
            waveContainer.addSubview(line)
        }

        // 标题
        let titleLabel = NSTextField(frame: NSRect(x: 0, y: 50, width: 280, height: 30))
        titleLabel.stringValue = "语音输入"
        titleLabel.textColor = NSColor.white
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = NSColor.clear

        // 副标题
        let subtitleLabel = NSTextField(frame: NSRect(x: 0, y: 25, width: 280, height: 20))
        subtitleLabel.stringValue = "已就绪"
        subtitleLabel.textColor = NSColor(red: 0.6, green: 0.6, blue: 0.65, alpha: 1.0)
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.alignment = .center
        subtitleLabel.isEditable = false
        subtitleLabel.isBordered = false
        subtitleLabel.backgroundColor = NSColor.clear

        containerView.addSubview(bgView)
        containerView.addSubview(borderView)
        containerView.addSubview(iconBg)
        containerView.addSubview(waveContainer)
        containerView.addSubview(titleLabel)
        containerView.addSubview(subtitleLabel)

        self.contentView = containerView

        // 淡入动画
        self.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 1
        })
    }

    func dismiss(completion: @escaping () -> Void) {
        // 淡出动画
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion()
        })
    }
}

// MARK: - 单实例锁
class SingleInstanceLock {
    static let shared = SingleInstanceLock()
    private let lockPath = "/tmp/voiceoverlay.lock"

    func acquire() -> Bool {
        let fileManager = FileManager.default

        // 清理可能残留的旧锁文件
        if fileManager.fileExists(atPath: lockPath) {
            if let pidStr = try? String(contentsOfFile: lockPath, encoding: .utf8),
               let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                // 检查进程是否还在运行且是 VoiceOverlay（不是 asr_server）
                if kill(pid, 0) == 0 {
                    // 进程存在，检查是否是 VoiceOverlay 进程
                    let task = Process()
                    task.launchPath = "/bin/ps"
                    task.arguments = ["-p", String(pid), "-o", "comm="]
                    let pipe = Pipe()
                    task.standardOutput = pipe
                    task.launch()
                    task.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8),
                       (output.contains("VoiceOverlay") || output.contains("VoiceInput")) && !output.contains("asr_server") {
                        print("VoiceOverlay 已在运行中 (PID: \(pid))")
                        return false
                    }
                }
            }
            // 进程不存在或不是 VoiceOverlay，删除旧锁
            try? fileManager.removeItem(atPath: lockPath)
        }

        // 创建新锁文件
        let currentPid = ProcessInfo.processInfo.processIdentifier
        try? String(currentPid).write(toFile: lockPath, atomically: true, encoding: .utf8)

        return true
    }
}

// MARK: - 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: VoiceOverlayWindow!
    var splashWindow: SplashWindow!
    var statusItem: NSStatusItem!
    var recorder = AudioRecorder()
    var isRecording = false
    var asrProcess: Process?
    var asrMonitorTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 重定向 stdout/stderr 到日志文件
        let logPath = "/tmp/voiceoverlay_debug.log"
        freopen(logPath.cString(using: .utf8), "w", stdout)
        freopen(logPath.cString(using: .utf8), "w", stderr)
        setbuf(stdout, nil)

        print("[DEBUG] 应用启动")

        // 单实例检查
        if !SingleInstanceLock.shared.acquire() {
            print("[DEBUG] 单实例检查失败，退出")
            NSApplication.shared.terminate(nil)
            return
        }
        print("[DEBUG] 单实例检查通过")

        // 显示启动画面
        showSplashScreen()
    }

    // 获取鼠标所在的屏幕
    func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    func showSplashScreen() {
        // 启动画面固定在内置主屏幕
        let targetScreen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let screenFrame = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        print("[DEBUG] 选中屏幕 frame: \(screenFrame), 所有屏幕: \(NSScreen.screens.map { $0.frame })")

        let splashWidth: CGFloat = 280
        let splashHeight: CGFloat = 200
        // 考虑多显示器环境，需要加上屏幕原点的偏移
        let x = screenFrame.origin.x + (screenFrame.width - splashWidth) / 2
        let y = screenFrame.origin.y + (screenFrame.height - splashHeight) / 2
        print("[DEBUG] 启动画面位置: x=\(x), y=\(y)")

        splashWindow = SplashWindow(
            contentRect: NSRect(x: x, y: y, width: splashWidth, height: splashHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        splashWindow.makeKeyAndOrderFront(nil)
        print("[DEBUG] 启动画面已显示")

        // 2秒后淡出并初始化主应用
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.splashWindow.dismiss { [weak self] in
                self?.initializeMainApp()
            }
        }
    }

    func initializeMainApp() {
        // 创建悬浮窗 - 同样优先使用内置主屏幕
        let targetScreen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let screenFrame = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 140
        let windowHeight: CGFloat = 44
        // 考虑多显示器环境，需要加上屏幕原点的 x 偏移
        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y: CGFloat = 100

        window = VoiceOverlayWindow(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "语音输入")
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()

        // 状态显示
        let statusItem = NSMenuItem(title: "🎤 语音输入已就绪", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        // 模型选择子菜单
        let modelMenu = NSMenu(title: "模型选择")
        modelMenu.autoenablesItems = false

        // 显示当前配置
        let configInfo = NSMenuItem(title: "📋 当前配置", action: nil, keyEquivalent: "")
        configInfo.isEnabled = false
        modelMenu.addItem(configInfo)

        let currentModel = getCurrentModel()
        let configModel = NSMenuItem(title: "   选中模型: \(currentModel)", action: nil, keyEquivalent: "")
        configModel.isEnabled = false
        configModel.tag = 100
        modelMenu.addItem(configModel)

        let runningModel = getRunningModel()
        let runModel = NSMenuItem(title: "   运行模型: \(runningModel)", action: nil, keyEquivalent: "")
        runModel.isEnabled = false
        runModel.tag = 101
        modelMenu.addItem(runModel)
        modelMenu.addItem(NSMenuItem.separator())

        // 模型选项
        let model0_6B = NSMenuItem(title: "☐ 0.6B - 快速 (适合日常使用)", action: #selector(selectModel0_6B), keyEquivalent: "")
        let model1_7B = NSMenuItem(title: "☐ 1.7B - 高精度 (适合长文本)", action: #selector(selectModel1_7B), keyEquivalent: "")

        model0_6B.state = currentModel == "0.6B" ? .on : .off
        model1_7B.state = currentModel == "1.7B" ? .on : .off

        model0_6B.target = self
        model1_7B.target = self

        model0_6B.tag = 200
        model1_7B.tag = 201

        modelMenu.addItem(model0_6B)
        modelMenu.addItem(model1_7B)
        modelMenu.addItem(NSMenuItem.separator())

        // 重启服务按钮
        let restartItem = NSMenuItem(title: "🔄 重启 ASR 服务", action: #selector(restartASRServer), keyEquivalent: "")
        restartItem.target = self
        modelMenu.addItem(restartItem)

        let modelItem = NSMenuItem(title: "⚙️ 模型设置", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        menu.addItem(NSMenuItem.separator())

        // 操作按钮
        menu.addItem(NSMenuItem(title: "🔴 开始录音", action: #selector(startRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⏹ 停止录音", action: #selector(stopRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        self.statusItem.menu = menu

        // 初始隐藏悬浮窗
        window.hideWindow()

        // 注册全局快捷键
        let hotkeyRegistered = GlobalHotkeyManager.shared.registerHotkey(
            toggleCallback: { [weak self] in
                self?.toggleRecording()
            },
            cancelCallback: { [weak self] in
                self?.cancelRecording()
            }
        )

        print("✓ VoiceOverlay 已启动")
        if hotkeyRegistered {
            print("  按右 Command 开始/停止录音")
            print("  录音时按 ESC 取消")
        } else {
            print("  ⚠️ 快捷键注册失败，请授予辅助功能权限")
            print("     系统设置 -> 隐私与安全性 -> 辅助功能")
        }

        // 启动 ASR 服务
        startASRServer()

        // 启动监控定时器
        startASRMonitor()
    }

    func startASRServer() {
        let socketPath = "/tmp/voice_asr_socket"

        // 如果socket已存在，检查是否可用
        if FileManager.default.fileExists(atPath: socketPath) {
            // 尝试连接测试
            var isRunning = false
            let testSocket = try? Socket.create(family: .unix, type: .stream, protocol: .unix)
            if let socket = testSocket {
                do {
                    try socket.connect(to: socketPath)
                    socket.close()
                    isRunning = true
                    print("  ✓ ASR 服务端已就绪")
                } catch {
                    print("  ⚠️ ASR socket 存在但无法连接，将清理并重启")
                    try? FileManager.default.removeItem(atPath: socketPath)
                }
            }
            if isRunning { return }
        }

        print("  启动 ASR 服务端...")

        // 获取应用bundle路径
        let bundlePath = Bundle.main.bundlePath
        let resourcesPath = Bundle.main.resourcePath ?? "\(bundlePath)/Contents/Resources"
        let asrScriptPath = "\(resourcesPath)/asr_server.py"

        let process = Process()

        // 首先尝试使用venv Python
        let venvPython = NSHomeDirectory() + "/ole/repos/github.com/oliveagle/ole_asr/venv/bin/python3"
        if FileManager.default.fileExists(atPath: venvPython) {
            process.executableURL = URL(fileURLWithPath: venvPython)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", asrScriptPath]
        }

        if process.arguments == nil {
            process.arguments = [asrScriptPath]
        }

        process.currentDirectoryURL = URL(fileURLWithPath: resourcesPath)

        // 设置环境变量
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        // 重定向输出到日志
        let logPath = "/tmp/asr_server.log"
        if let logHandle = FileHandle(forWritingAtPath: logPath) {
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        do {
            try process.run()
            asrProcess = process
            print("  ✓ ASR 服务端启动中 (PID: \(process.processIdentifier))")

            // 等待socket创建
            var attempts = 0
            while attempts < 10 {
                Thread.sleep(forTimeInterval: 0.5)
                if FileManager.default.fileExists(atPath: socketPath) {
                    print("  ✓ ASR 服务端已就绪")
                    return
                }
                attempts += 1
            }
            print("  ⚠️ ASR 服务端启动超时")
        } catch {
            print("  ✗ ASR 服务端启动失败: \(error)")
        }
    }

    func startASRMonitor() {
        asrMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkAndRestartASR()
        }
    }

    func checkAndRestartASR() {
        let socketPath = "/tmp/voice_asr_socket"

        // 检查socket是否存在且可连接
        var isRunning = false
        if FileManager.default.fileExists(atPath: socketPath) {
            let testSocket = try? Socket.create(family: .unix, type: .stream, protocol: .unix)
            if let socket = testSocket {
                do {
                    try socket.connect(to: socketPath)
                    socket.close()
                    isRunning = true
                } catch {
                    // 无法连接，需要重启
                }
            }
        }

        if !isRunning {
            print("[ASR] 服务不可用，正在重启...")
            // 清理旧socket
            try? FileManager.default.removeItem(atPath: socketPath)
            // 终止旧进程
            asrProcess?.terminate()
            // 重新启动
            startASRServer()
        }
    }

    func stopASRServer() {
        asrMonitorTimer?.invalidate()
        asrMonitorTimer = nil

        if let process = asrProcess, process.isRunning {
            process.terminate()
            // 等待进程结束
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning {
                    // 强制终止
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        // 清理socket
        let socketPath = "/tmp/voice_asr_socket"
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    @objc func toggleRecording() {
        if !isRecording {
            startRecording()
        } else {
            stopRecording()
        }
    }

    @objc func startRecording() {
        guard !isRecording else { return }

        // 获取鼠标所在的屏幕，将悬浮窗定位到该屏幕
        if let targetScreen = getScreenWithMouse() {
            let screenFrame = targetScreen.frame
            let windowWidth: CGFloat = 140
            let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
            let y: CGFloat = 100

            // 更新窗口位置
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        isRecording = true
        window.showWindow()
        _ = recorder.startRecording()
    }

    @objc func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        window.hideWindow()

        guard let audioData = recorder.stopRecording() else {
            print("⚠ 录音数据获取失败")
            return
        }

        // 发送到 ASR 服务端
        print("[ASR] 发送音频数据: \(audioData.count) bytes")
        ASRClient.shared.transcribe(audioData: audioData) { text in
            if let text = text, !text.isEmpty {
                print("✓ 识别结果: \(text)")
                self.pasteText(text)
            } else {
                print("⚠ 未能识别语音 (text is nil or empty)")
            }
        }
    }

    @objc func cancelRecording() {
        guard isRecording else { return }

        isRecording = false
        window.hideWindow()

        // 停止录音但不获取数据（丢弃）
        _ = recorder.stopRecording()

        print("[Recording] 已取消录音（按 ESC）")
    }

    // 保存剪贴板所有内容类型
    private var savedClipboardData: [(type: NSPasteboard.PasteboardType, data: Data)]?

    func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general

        // 1. 保存当前剪贴板所有内容（支持文字、图片、富文本等）
        savedClipboardData = []
        if let items = pasteboard.pasteboardItems, let firstItem = items.first {
            for type in firstItem.types {
                if let data = firstItem.data(forType: type) {
                    savedClipboardData?.append((type: type, data: data))
                }
            }
        }

        // 2. 设置新文字到剪贴板
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)

        // 3. 发送 Command+V 粘贴
        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        // 4. 延迟恢复原始剪贴板内容（0.5秒足够粘贴完成）
        let savedData = savedClipboardData
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let data = savedData, !data.isEmpty {
                let item = NSPasteboardItem()
                for (type, d) in data {
                    item.setData(d, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }

    @objc func quit() {
        stopASRServer()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 模型切换
    var selectedModel: String = "0.6B"

    func getCurrentModel() -> String {
        let configPath = NSHomeDirectory() + "/ole/repos/github.com/oliveagle/ole_asr/config.yaml"
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return selectedModel
        }
        // 简单解析 YAML 找 model 字段
        if let match = content.range(of: "model:\\s*\\\"?([^\\\"\\n]+)\\\"?", options: .regularExpression) {
            let line = String(content[match])
            if line.contains("1.7B") {
                selectedModel = "1.7B"
                return "1.7B"
            }
        }
        selectedModel = "0.6B"
        return "0.6B"
    }

    func getRunningModel() -> String {
        // 从日志文件读取当前运行的模型
        let logPath = "/tmp/asr_server.log"
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return "未知"
        }

        // 查找最新加载的模型
        let lines = content.components(separatedBy: .newlines)
        for line in lines.reversed() {
            if line.contains("加载模型 [") {
                if line.contains("1.7B") {
                    return "1.7B"
                } else if line.contains("0.6B") {
                    return "0.6B"
                }
            }
            if line.contains("当前模型:"), let range = line.range(of: "当前模型:") {
                let modelInfo = String(line[range.upperBound...])
                if modelInfo.contains("1.7B") {
                    return "1.7B"
                } else if modelInfo.contains("0.6B") {
                    return "0.6B"
                }
            }
        }
        return "未知"
    }

    func updateMenuState() {
        guard let menu = statusItem.menu else { return }

        // 更新模型设置子菜单
        for item in menu.items {
            if item.title.contains("模型设置"), let submenu = item.submenu {
                let currentModel = getCurrentModel()
                let runningModel = getRunningModel()

                for subItem in submenu.items {
                    switch subItem.tag {
                    case 100: // 选中模型
                        subItem.title = "   选中模型: \(currentModel)"
                    case 101: // 运行模型
                        subItem.title = "   运行模型: \(runningModel)"
                        subItem.title = runningModel == currentModel ?
                            "   运行模型: \(runningModel) ✅" :
                            "   运行模型: \(runningModel) ⚠️ (需重启)"
                    case 200: // 0.6B 选项
                        subItem.state = currentModel == "0.6B" ? .on : .off
                        subItem.title = subItem.state == .on ?
                            "✅ 0.6B - 快速 (适合日常使用)" :
                            "☐ 0.6B - 快速 (适合日常使用)"
                    case 201: // 1.7B 选项
                        subItem.state = currentModel == "1.7B" ? .on : .off
                        subItem.title = subItem.state == .on ?
                            "✅ 1.7B - 高精度 (适合长文本)" :
                            "☐ 1.7B - 高精度 (适合长文本)"
                    default:
                        break
                    }
                }
            }
        }
    }

    func setModel(_ model: String) {
        selectedModel = model
        let configPath = NSHomeDirectory() + "/ole/repos/github.com/oliveagle/ole_asr/config.yaml"
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }

        // 使用更精确的 YAML 替换
        if let range = content.range(of: "model:\\s*\\\"?[^\\\"\\n]*\\\"?", options: .regularExpression) {
            let oldLine = String(content[range])
            let newLine = "model: \"\(model)\""
            content = content.replacingOccurrences(of: oldLine, with: newLine)
            try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
        }

        // 更新菜单状态
        updateMenuState()

        print("[Config] 已切换模型到: \(model)")
    }

    @objc func selectModel0_6B() {
        setModel("0.6B")
    }

    @objc func selectModel1_7B() {
        setModel("1.7B")
    }

    @objc func restartASRServer() {
        print("[ASR] 重启服务以应用新模型...")
        stopASRServer()

        // 更新菜单显示重启中状态
        if let menu = statusItem.menu {
            for item in menu.items {
                if item.title.contains("模型设置"), let submenu = item.submenu {
                    for subItem in submenu.items {
                        if subItem.tag == 101 {
                            subItem.title = "   运行模型: 重启中..."
                        }
                    }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startASRServer()
            // 重启完成后更新菜单状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self?.updateMenuState()
            }
        }
    }
}

// MARK: - 信号处理 (C 函数)
func setupSignalHandler() {
    // 使用 C 函数指针设置信号处理
    typealias SignalHandler = @convention(c) (Int32) -> Void

    let handler: SignalHandler = { sig in
        print("\n收到 Ctrl+C，正在退出...")
        fflush(stdout)

        // 清理并退出
        let app = NSApplication.shared
        app.stop(nil)
        exit(0)
    }

    // 使用 Darwin 的 signal 函数
    _ = Darwin.signal(SIGINT, handler)
}

// MARK: - 程序入口
setupSignalHandler()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
