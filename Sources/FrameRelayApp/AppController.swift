import AppKit
import Darwin
import Foundation
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger = Logger(subsystem: "com.framerelay.FrameRelay", category: "app")
    private let launchProfile: FrameRelayLaunchProfile
    private let configuration: AirPlayConfiguration
    private let logDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/FrameRelay", isDirectory: true)

    private var engine: AirPlayEngine!
    private var receiverWindow: ReceiverWindowController!
    private var statusMenu: StatusMenuController!
    private var eventTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var state: ReceiverState = .stopped {
        didSet {
            statusMenu?.update(state: state)
        }
    }
    private var desiredRunning = false
    private var restartPolicy = RestartPolicy()
    private var restartInProgress = false
    private var lifecycleGeneration = 0
    private var recentErrorLogs: [String] = []
    private var terminationInProgress = false
    private var coreURL: URL?
    private var windowCloseInProgress = false
    private var completingWindowClose = false

    init(arguments: [String] = CommandLine.arguments) {
        let profile = FrameRelayLaunchProfile(arguments: arguments)
        self.launchProfile = profile
        self.configuration = profile.configuration
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenu()
        receiverWindow = ReceiverWindowController()
        receiverWindow.window?.delegate = self
        statusMenu = StatusMenuController(owner: self)
        statusMenu.update(state: state)

        coreURL = resolveCoreURL()
        guard let coreURL else {
            state = .failed("找不到 uxplay-core.dylib")
            logger.error("uxplay-core.dylib was not found")
            return
        }

        engine = AirPlayEngine(
            coreURL: coreURL,
            configuration: configuration,
            logDirectory: logDirectory
        )
        if launchProfile.isDiagnostic {
            logger.notice("diagnostic profile active: \(self.launchProfile.displayName, privacy: .public)")
        }
        observeEngineEvents()
        startReceiver()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine else {
            return .terminateNow
        }
        guard !terminationInProgress else { return .terminateLater }

        terminationInProgress = true
        lifecycleGeneration &+= 1
        desiredRunning = false
        restartInProgress = false
        connectionTimeoutTask?.cancel()
        restartTask?.cancel()
        connectionTimeoutTask = nil
        restartTask = nil
        state = .stopped
        Task { [engine] in
            await engine.stop()
            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    @objc func showReceiverWindow() {
        receiverWindow.showReceiverWindow()
    }

    @objc func hideReceiverWindow() {
        receiverWindow.hideReceiverWindow()
    }

    @objc func startReceiver() {
        guard let engine else {
            state = .failed("AirPlay 核心尚未加载")
            return
        }
        if case .failed = state {
            beginRestart(resetFailureCount: true, reason: "manual-from-failed")
            return
        }
        guard !isRunningState else {
            return
        }

        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        desiredRunning = true
        restartInProgress = false
        restartPolicy.reset()
        restartTask?.cancel()
        restartTask = nil
        receiverWindow.showReceiverWindow()
        state = .starting
        let hostViewAddress = receiverWindow.hostViewAddress

        Task { [weak self, engine] in
            do {
                try await engine.start(hostViewAddress: hostViewAddress)
            } catch {
                await MainActor.run {
                    guard let self,
                          self.lifecycleGeneration == generation,
                          self.desiredRunning else { return }
                    self.recordError(error.localizedDescription)
                    self.state = .failed(error.localizedDescription)
                    self.logger.error("AirPlay core start failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @objc func stopReceiver() {
        lifecycleGeneration &+= 1
        desiredRunning = false
        restartInProgress = false
        connectionTimeoutTask?.cancel()
        restartTask?.cancel()
        connectionTimeoutTask = nil
        restartTask = nil
        state = .stopped

        guard let engine else {
            receiverWindow.clearVideo()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await engine.stop()
            await MainActor.run {
                self.receiverWindow.clearVideo()
            }
        }
    }

    @objc func restartReceiver() {
        beginRestart(resetFailureCount: true, reason: "manual")
    }

    private func beginRestart(resetFailureCount: Bool, reason: String) {
        guard let engine else { return }
        guard !restartInProgress else {
            logger.notice("restart ignored: reason=\(reason, privacy: .public) generation=\(self.lifecycleGeneration)")
            return
        }

        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        desiredRunning = true
        restartInProgress = true
        logger.notice("restart requested: reason=\(reason, privacy: .public) generation=\(generation)")
        appendLifecycleLog("restart requested reason=\(reason) generation=\(generation)")
        if resetFailureCount {
            restartPolicy.reset()
        }
        connectionTimeoutTask?.cancel()
        restartTask?.cancel()
        connectionTimeoutTask = nil
        restartTask = nil
        receiverWindow.showReceiverWindow()
        receiverWindow.clearVideo()
        state = .reconnecting
        let hostViewAddress = receiverWindow.hostViewAddress

        Task { [weak self, engine] in
            do {
                try await engine.restart(hostViewAddress: hostViewAddress)
                await MainActor.run {
                    guard let self,
                          self.lifecycleGeneration == generation,
                          self.desiredRunning else { return }
                    self.restartInProgress = false
                    self.appendLifecycleLog("restart completed reason=\(reason) generation=\(generation)")
                    self.state = .waitingForIPhone
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.lifecycleGeneration == generation,
                          self.desiredRunning else { return }
                    self.restartInProgress = false
                    self.appendLifecycleLog("restart failed reason=\(reason) generation=\(generation) error=\(error.localizedDescription)")
                    self.recordError(error.localizedDescription)
                    self.state = .failed(error.localizedDescription)
                    self.logger.error("AirPlay core restart failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @objc func copyDiagnostics() {
        let text = diagnosticsText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func openLogs() {
        NSWorkspace.shared.open(logDirectory)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if completingWindowClose {
            return true
        }
        guard !windowCloseInProgress else {
            return false
        }

        windowCloseInProgress = true
        lifecycleGeneration &+= 1
        desiredRunning = false
        restartInProgress = false
        connectionTimeoutTask?.cancel()
        restartTask?.cancel()
        connectionTimeoutTask = nil
        restartTask = nil
        state = .stopped

        guard let engine else {
            receiverWindow.clearVideo()
            windowCloseInProgress = false
            completingWindowClose = true
            sender.close()
            completingWindowClose = false
            return false
        }
        Task { [weak self] in
            guard let self else { return }
            await engine.stop()
            await MainActor.run {
                self.receiverWindow.clearVideo()
                self.windowCloseInProgress = false
                self.completingWindowClose = true
                sender.close()
                self.completingWindowClose = false
            }
        }
        return false
    }

    private var isRunningState: Bool {
        switch state {
        case .stopped, .failed:
            return false
        default:
            return true
        }
    }

    private func observeEngineEvents() {
        eventTask?.cancel()
        let engine = self.engine!
        eventTask = Task { [weak self, engine] in
            let stream = await engine.eventStream()
            for await event in stream {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.handle(event: event)
                }
            }
        }
    }

    private func handle(event: EngineEvent) {
        switch event {
        case .serverStarting:
            if desiredRunning { state = .starting }
        case .serverReady:
            if desiredRunning { state = .waitingForIPhone }
        case .clientConnected:
            guard desiredRunning else { return }
            // Connection markers can be duplicated by the upstream log stream.
            // Once the first video frame has established streaming, a later
            // marker must not regress the state or restart the pre-video timer.
            if case .streaming = state {
                return
            }
            state = .connecting
            scheduleVideoStartTimeout()
        case .videoStarted(let geometry):
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            restartPolicy.reset()
            if desiredRunning {
                let applied = receiverWindow.applyVideoGeometry(geometry)
                state = .streaming(geometry)
                if launchProfile.isDiagnostic {
                    let rotation = String(format: "%02x", geometry.rotationHint)
                    let contentSize = receiverWindow.window?.contentView?.bounds.size ?? .zero
                    let contentDescription = "\(Int(contentSize.width))x\(Int(contentSize.height))"
                    appendHostDiagnostic(
                        "videoStarted geometry=\(geometry.width)x\(geometry.height) " +
                        "rotation=0x\(rotation) applied=\(applied) " +
                        "windowContent=\(contentDescription)"
                    )
                }
            }
        case .clientReset, .clientDisconnected:
            connectionTimeoutTask?.cancel()
            if desiredRunning {
                receiverWindow.clearVideo()
                state = .waitingForIPhone
            }
        case .engineError(let message):
            recordError(message)
            logger.error("AirPlay core error: \(message, privacy: .public)")
            if desiredRunning,
               !restartInProgress,
               message.localizedCaseInsensitiveContains("worker exited unexpectedly") {
                scheduleAutomaticRestart(reason: "worker-exit")
            }
        case .displayStalled(let message):
            recordError(message)
            logger.error("AVLayer watchdog requested restart: \(message, privacy: .public)")
            if desiredRunning {
                scheduleAutomaticRestart(reason: "avlayer-watchdog")
            }
        case .engineStopped:
            receiverWindow.clearVideo()
            if !desiredRunning {
                state = .stopped
            } else if !restartInProgress {
                scheduleAutomaticRestart(reason: "engine-stopped")
            }
        }
    }

    private func scheduleVideoStartTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 12_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.desiredRunning,
                      self.state == .connecting else { return }
                self.scheduleAutomaticRestart(reason: "video-start-timeout")
            }
        }
    }

    private func scheduleAutomaticRestart(reason: String) {
        guard desiredRunning, !restartInProgress, restartTask == nil else {
            if restartInProgress {
                logger.notice("automatic restart ignored: reason=\(reason, privacy: .public) activeGeneration=\(self.lifecycleGeneration)")
            }
            return
        }

        guard let delay = restartPolicy.nextDelayNanoseconds() else {
            state = .failed("AirPlay 核心连续重启 3 次失败")
            return
        }

        state = .reconnecting
        appendLifecycleLog("automatic restart scheduled reason=\(reason) delay_ns=\(delay)")
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.desiredRunning else { return }
                self.restartTask = nil
                self.beginRestart(resetFailureCount: false, reason: reason)
            }
        }
    }

    private func appendLifecycleLog(_ message: String) {
        guard let engine else { return }
        Task {
            await engine.appendLifecycleLog(message)
        }
    }

    private func resolveCoreURL() -> URL? {
        if let bundled = Bundle.main.privateFrameworksURL?.appendingPathComponent("uxplay-core.dylib"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        if let developmentPath = ProcessInfo.processInfo.environment["FRAMERELAY_CORE_PATH"] {
            let url = URL(fileURLWithPath: developmentPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()

        let applicationMenu = NSMenu(title: "FrameRelay")
        let aboutItem = NSMenuItem(
            title: "关于 FrameRelay",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        applicationMenu.addItem(aboutItem)
        applicationMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: "隐藏 FrameRelay", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        applicationMenu.addItem(hideItem)
        applicationMenu.addItem(NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        applicationMenu.addItem(NSMenuItem(title: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 FrameRelay", action: #selector(AppDelegate.quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)

        let applicationMenuItem = NSMenuItem()
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        let windowMenuItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func diagnosticsText() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        let errors = recentErrorLogs.isEmpty ? "（无）" : recentErrorLogs.joined(separator: "\n")
        return """
        FrameRelay version: \(BuildMetadata.version)
        macOS: \(version)
        Mac chip: \(machineChipDescription())
        Architecture: arm64
        AirPlay core SHA: \(BuildMetadata.coreCommit)
        GStreamer: \(BuildMetadata.gstreamerVersion)
        Launch profile: \(launchProfile.displayName)
        AirPlay options: \(configuration.options)
        Current state: \(diagnosticStateDescription())
        App bundle: \(Bundle.main.bundlePath)
        Core path: \(coreURL?.path ?? "missing")
        Log path: \(logDirectory.appendingPathComponent("FrameRelay.log").path)
        Network interfaces:
        \(networkInterfaceSummary())
        Recent 50 error logs:
        \(errors)
        """
    }

    private func recordError(_ message: String) {
        let formatter = ISO8601DateFormatter()
        recentErrorLogs.append("[\(formatter.string(from: Date()))] \(message)")
        if recentErrorLogs.count > 50 {
            recentErrorLogs.removeFirst(recentErrorLogs.count - 50)
        }
    }

    private func appendHostDiagnostic(_ message: String) {
        guard launchProfile.isDiagnostic, let engine else { return }
        logger.notice("\(message, privacy: .public)")
        Task { [engine] in
            await engine.appendHostDiagnostic(message)
        }
    }

    private func diagnosticStateDescription() -> String {
        switch state {
        case .stopped: return "未启动"
        case .starting: return "正在启动"
        case .waitingForIPhone: return "等待 iPhone"
        case .connecting: return "正在连接"
        case .streaming(let geometry): return "正在接收 \(geometry.width)×\(geometry.height)"
        case .reconnecting: return "正在重连"
        case .failed(let message): return "启动失败：\(message)"
        }
    }

    private func machineChipDescription() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 1 else {
            return "Apple Silicon (arm64)"
        }

        var bytes = [CChar](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes { rawBuffer in
            sysctlbyname("machdep.cpu.brand_string", rawBuffer.baseAddress, &size, nil, 0)
        }
        guard result == 0 else {
            return "Apple Silicon (arm64)"
        }
        return String(decoding: bytes.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    private func networkInterfaceSummary() -> String {
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let first = interfaceList else {
            return "无法读取网络接口"
        }
        defer { freeifaddrs(first) }

        var entries: [String] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            let address = interface.pointee.ifa_addr
            if let address,
               address.pointee.sa_family == UInt8(AF_INET) ||
                   address.pointee.sa_family == UInt8(AF_INET6) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = host.withUnsafeMutableBufferPointer { hostBuffer in
                    getnameinfo(
                        address,
                        socklen_t(address.pointee.sa_len),
                        hostBuffer.baseAddress,
                        socklen_t(hostBuffer.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }
                if result == 0 {
                    let name = String(cString: interface.pointee.ifa_name)
                    let value = String(decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
                    if !entries.contains("\(name)=\(value)") {
                        entries.append("\(name)=\(value)")
                    }
                }
            }
            current = interface.pointee.ifa_next
        }

        return entries.isEmpty ? "（无活动 IPv4/IPv6 地址）" : entries.joined(separator: "\n")
    }
}
