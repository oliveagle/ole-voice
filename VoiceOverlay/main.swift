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
    var callback: (() -> Void)?

    private var isRegistered = false

    func registerHotkey(callback: @escaping () -> Void) -> Bool {
        // 防止重复注册
        if isRegistered {
            print("[Hotkey] 已经注册过了")
            return true
        }

        self.callback = callback

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

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
                        manager.callback?()
                    }
                }
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
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 44))

        // 毛玻璃效果背景
        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 180, height: 44))
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 22
        visualEffectView.layer?.masksToBounds = true

        // 深色半透明覆盖层
        let darkOverlay = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 44))
        darkOverlay.wantsLayer = true
        darkOverlay.layer?.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.85).cgColor
        darkOverlay.layer?.cornerRadius = 22

        // 精致的发光边框
        let borderView = NSView(frame: NSRect(x: 0.5, y: 0.5, width: 179, height: 43))
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 21.5
        borderView.layer?.borderWidth = 0.8
        borderView.layer?.borderColor = NSColor(red: 0.35, green: 0.35, blue: 0.4, alpha: 0.5).cgColor

        // 内部高光边框
        let innerBorder = NSView(frame: NSRect(x: 1.5, y: 1.5, width: 177, height: 41))
        innerBorder.wantsLayer = true
        innerBorder.layer?.cornerRadius = 20.5
        innerBorder.layer?.borderWidth = 0.5
        innerBorder.layer?.borderColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.06).cgColor

        // 文字标签 - 使用更细的字体
        let label = NSTextField(frame: NSRect(x: 14, y: 10, width: 68, height: 24))
        label.stringValue = "语音输入"
        label.textColor = NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
        // 使用更细的系统字体
        if #available(macOS 11.0, *) {
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        } else {
            label.font = NSFont(name: "PingFangSC-Medium", size: 12) ?? NSFont.systemFont(ofSize: 12)
        }
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = NSColor.clear
        label.alignment = .left

        // 精致的分隔线 - 渐变效果
        let separator = NSView(frame: NSRect(x: 86, y: 10, width: 1, height: 24))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 0.35).cgColor

        // 录音状态指示器
        let indicator = NSView(frame: NSRect(x: 80, y: 20, width: 3, height: 3))
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0).cgColor
        indicator.layer?.cornerRadius = 1.5

        // 音波视图
        waveView = WaveView(frame: NSRect(x: 92, y: 0, width: 80, height: 44))

        // 组装视图层次
        containerView.addSubview(visualEffectView)
        containerView.addSubview(darkOverlay)
        containerView.addSubview(borderView)
        containerView.addSubview(innerBorder)
        containerView.addSubview(label)
        containerView.addSubview(separator)
        containerView.addSubview(indicator)
        containerView.addSubview(waveView)

        self.contentView = containerView
    }

    func showWindow() {
        self.makeKeyAndOrderFront(nil)
        waveView?.startAnimation()
    }

    func hideWindow() {
        waveView?.stopAnimation()
        self.orderOut(nil)
    }
}

// MARK: - 音波动画视图
class WaveView: NSView {
    private var bars: [CGFloat] = Array(repeating: 0.3, count: 7)
    private var targetBars: [CGFloat] = Array(repeating: 0.3, count: 7)
    private var isAnimating = false
    private var animationTimer: Timer?

    // 渐变色定义 (青色到蓝色)
    private let gradientColors = [
        NSColor(red: 0.0, green: 0.9, blue: 0.6, alpha: 1.0),   // 青绿
        NSColor(red: 0.0, green: 0.85, blue: 0.75, alpha: 1.0), // 青蓝
        NSColor(red: 0.0, green: 0.75, blue: 0.9, alpha: 1.0),  // 浅蓝
        NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),   // 蓝色
        NSColor(red: 0.4, green: 0.5, blue: 1.0, alpha: 1.0),   // 紫蓝
        NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.0, green: 0.75, blue: 0.9, alpha: 1.0)
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
        bars = Array(repeating: 0.3, count: 7)
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

// MARK: - 单实例锁
class SingleInstanceLock {
    static let shared = SingleInstanceLock()
    private let lockPath = "/tmp/voiceoverlay.lock"
    private var lockFile: FileHandle?

    func acquire() -> Bool {
        // 检查是否有其他实例在运行
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "VoiceOverlay"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let pids = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
            // 如果找到超过1个进程（包括自己），说明已有实例在运行
            if pids.count > 1 {
                print("VoiceOverlay 已在运行中 (PID: \(pids[0]))")
                return false
            }
        }
        return true
    }
}

// MARK: - 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: VoiceOverlayWindow!
    var statusItem: NSStatusItem!
    var recorder = AudioRecorder()
    var isRecording = false
    var asrProcess: Process?
    var asrMonitorTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例检查
        if !SingleInstanceLock.shared.acquire() {
            NSApplication.shared.terminate(nil)
            return
        }
        // 创建悬浮窗
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 180
        let windowHeight: CGFloat = 44
        let x = (screenFrame.width - windowWidth) / 2
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
        menu.addItem(NSMenuItem(title: "开始录音", action: #selector(startRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "停止录音", action: #selector(stopRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        // 初始隐藏悬浮窗
        window.hideWindow()

        // 注册全局快捷键
        let hotkeyRegistered = GlobalHotkeyManager.shared.registerHotkey { [weak self] in
            self?.toggleRecording()
        }

        print("✓ VoiceOverlay 已启动")
        if hotkeyRegistered {
            print("  按右 Command 开始/停止录音")
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

    func pasteText(_ text: String) {
        print("[Paste] 准备粘贴: \"\(text)\"")

        // 复制到剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(text, forType: .string)
        print("[Paste] 复制到剪贴板: \(copied ? "成功" : "失败")")

        // 模拟 Command+V 粘贴
        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        print("[Paste] 已发送 Command+V")
    }

    @objc func quit() {
        stopASRServer()
        NSApplication.shared.terminate(nil)
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
