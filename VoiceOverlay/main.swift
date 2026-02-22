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
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))

        let background = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.95).cgColor
        background.layer?.cornerRadius = 25
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0).cgColor
        contentView.addSubview(background)

        let label = NSTextField(frame: NSRect(x: 15, y: 12, width: 80, height: 26))
        label.stringValue = "语音输入"
        label.textColor = NSColor.white
        label.font = NSFont(name: "PingFang SC", size: 14) ?? NSFont.systemFont(ofSize: 14)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = NSColor.clear
        label.alignment = .center
        contentView.addSubview(label)

        let separator = NSView(frame: NSRect(x: 100, y: 12, width: 1, height: 26))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(red: 0.27, green: 0.27, blue: 0.27, alpha: 1.0).cgColor
        contentView.addSubview(separator)

        waveView = WaveView(frame: NSRect(x: 110, y: 0, width: 80, height: 50))
        contentView.addSubview(waveView)

        self.contentView = contentView
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
    private var amplitudes: [CGFloat] = [0.5, 0.5, 0.5, 0.5, 0.5]
    private var isAnimating = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barWidth: CGFloat = 4
        let barGap: CGFloat = 6
        let totalWidth = 5 * barWidth + 4 * barGap
        let startX = (bounds.width - totalWidth) / 2
        let centerY = bounds.height / 2

        for (i, amp) in amplitudes.enumerated() {
            let barHeight = 4 + amp * 20
            let x = startX + CGFloat(i) * (barWidth + barGap)
            let y = centerY - barHeight / 2

            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)

            NSColor(red: 0.0, green: 0.82, blue: 0.42, alpha: 1.0).setFill()
            path.fill()
        }
    }

    func startAnimation() {
        isAnimating = true
        animate()
    }

    func stopAnimation() {
        isAnimating = false
    }

    func animate() {
        guard isAnimating else { return }

        amplitudes = (0..<5).map { _ in CGFloat.random(in: 0.2...1.0) }
        needsDisplay = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.animate()
        }
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

// MARK: - 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: VoiceOverlayWindow!
    var statusItem: NSStatusItem!
    var recorder = AudioRecorder()
    var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建悬浮窗
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 200
        let windowHeight: CGFloat = 50
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
        statusItem.button?.title = "🎤"

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
            print("  按左 Command 开始/停止录音")
        } else {
            print("  ⚠️ 快捷键注册失败，请授予辅助功能权限")
            print("     系统设置 -> 隐私与安全性 -> 辅助功能")
        }

        // 检查 ASR 服务端
        checkASRServer()
    }

    func checkASRServer() {
        let socketPath = "/tmp/voice_asr_socket"
        if !FileManager.default.fileExists(atPath: socketPath) {
            print("  ⚠️ ASR 服务端未运行")
            print("     请运行: python3 VoiceOverlay/asr_server.py")
        } else {
            print("  ✓ ASR 服务端已就绪")
        }
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
