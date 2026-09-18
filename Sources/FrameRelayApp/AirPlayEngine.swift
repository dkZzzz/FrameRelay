import Foundation
import FrameRelayCoreBridge
import os
import Darwin

nonisolated private final class EngineLogSink: @unchecked Sendable {
    private let continuation: AsyncStream<EngineLog>.Continuation

    init(continuation: AsyncStream<EngineLog>.Continuation) {
        self.continuation = continuation
    }

    nonisolated func receive(level: Int32, message: String) {
        continuation.yield(
            EngineLog(timestamp: Date(), level: level, message: message)
        )
    }
}

nonisolated(unsafe) private let frameRelayCoreLogCallback: FRCoreLogCallback = { level, message, user in
    guard let user else {
        return
    }

    let copiedMessage: String
    if let message {
        copiedMessage = String(cString: message)
    } else {
        copiedMessage = "<null AirPlay core log message>"
    }

    let sink = Unmanaged<EngineLogSink>.fromOpaque(user).takeUnretainedValue()
    sink.receive(level: level, message: copiedMessage)
}

actor AirPlayEngine {
    private let coreURL: URL
    private let configuration: AirPlayConfiguration
    private let parser = EngineLogParser()
    private let logWriter: LogWriter
    private let logger = Logger(subsystem: "com.framerelay.FrameRelay", category: "engine")

    private let logStream: AsyncStream<EngineLog>
    private let logContinuation: AsyncStream<EngineLog>.Continuation
    private let events: AsyncStream<EngineEvent>
    private let eventContinuation: AsyncStream<EngineEvent>.Continuation

    private var logTask: Task<Void, Never>?
    private var core: OpaquePointer?
    private var logSink: EngineLogSink?
    private var logUser: UnsafeMutableRawPointer?

    init(coreURL: URL, configuration: AirPlayConfiguration, logDirectory: URL) {
        self.coreURL = coreURL
        self.configuration = configuration
        self.logWriter = LogWriter(directoryURL: logDirectory)

        let logPair = AsyncStream<EngineLog>.makeStream()
        self.logStream = logPair.stream
        self.logContinuation = logPair.continuation

        let eventPair = AsyncStream<EngineEvent>.makeStream()
        self.events = eventPair.stream
        self.eventContinuation = eventPair.continuation
    }

    func eventStream() -> AsyncStream<EngineEvent> {
        events
    }

    func appendHostDiagnostic(_ message: String) async {
        await logWriter.append(
            EngineLog(
                timestamp: Date(),
                level: 6,
                message: "FrameRelay diagnostic host: \(message)"
            )
        )
    }

    func appendLifecycleLog(_ message: String) async {
        await logWriter.append(
            EngineLog(
                timestamp: Date(),
                level: 5,
                message: "FrameRelay lifecycle: \(message)"
            )
        )
    }

    func start(hostViewAddress: UInt) async throws {
        guard core == nil else {
            throw EngineFailure.alreadyRunning
        }

        configureRuntimeEnvironment()
        startLogProcessingIfNeeded()

        var errorBuffer = [CChar](repeating: 0, count: 1024)
        let handle = coreURL.path.withCString { path in
            errorBuffer.withUnsafeMutableBufferPointer { buffer in
                fr_core_open(path, buffer.baseAddress, buffer.count)
            }
        }

        guard let handle else {
            throw EngineFailure.coreUnavailable(Self.errorMessage(from: errorBuffer))
        }

        let sink = EngineLogSink(continuation: logContinuation)
        let user = Unmanaged.passRetained(sink).toOpaque()
        let viewPointer = UnsafeMutableRawPointer(bitPattern: hostViewAddress)

        guard fr_core_set_window(handle, viewPointer) == FRCoreStatusOK else {
            fr_core_close(handle)
            Unmanaged<EngineLogSink>.fromOpaque(user).release()
            throw EngineFailure.configurationFailed("无法绑定视频宿主 NSView")
        }

        let deviceNameStatus = configuration.deviceName.withCString {
            fr_core_set_device_name(handle, $0)
        }
        guard deviceNameStatus == FRCoreStatusOK else {
            fr_core_close(handle)
            Unmanaged<EngineLogSink>.fromOpaque(user).release()
            throw EngineFailure.configurationFailed("无法设置 AirPlay 设备名称")
        }

        let optionStatus = configuration.options.withCString {
            fr_core_set_options(handle, $0)
        }
        guard optionStatus == FRCoreStatusOK else {
            fr_core_close(handle)
            Unmanaged<EngineLogSink>.fromOpaque(user).release()
            throw EngineFailure.configurationFailed("无法设置 AirPlay 参数")
        }

        fr_core_set_log_callback(handle, frameRelayCoreLogCallback, user)
        eventContinuation.yield(.serverStarting)
        let startStatus = fr_core_start(handle)
        guard startStatus == FRCoreStatusOK else {
            fr_core_close(handle)
            Unmanaged<EngineLogSink>.fromOpaque(user).release()
            throw EngineFailure.configurationFailed("AirPlay 核心启动失败，状态码 \(startStatus)")
        }

        core = handle
        logSink = sink
        logUser = user
        logger.info("AirPlay core started")
    }

    func stop() async {
        stop(emitEvent: true)
    }

    private func stop(emitEvent: Bool) {
        guard let handle = core else {
            return
        }

        fr_core_stop(handle)
        fr_core_close(handle)

        if let user = logUser {
            Unmanaged<EngineLogSink>.fromOpaque(user).release()
        }

        core = nil
        logSink = nil
        logUser = nil
        if emitEvent {
            eventContinuation.yield(.engineStopped)
        }
        logger.info("AirPlay core stopped")
    }

    func restart(hostViewAddress: UInt) async throws {
        /* A restart is one logical operation.  Suppressing the intermediate
         * engineStopped marker prevents the AppKit state machine from racing
         * its own fixed-backoff restart with this intentional stop/start pair. */
        stop(emitEvent: false)
        try await start(hostViewAddress: hostViewAddress)
    }

    private func startLogProcessingIfNeeded() {
        guard logTask == nil else {
            return
        }

        let stream = logStream
        logTask = Task { [weak self] in
            for await log in stream {
                guard !Task.isCancelled else {
                    return
                }
                guard let self else {
                    return
                }
                await self.process(log)
            }
        }
    }

    private func process(_ log: EngineLog) async {
        await logWriter.append(log)

        if let event = parser.parse(level: log.level, message: log.message) {
            eventContinuation.yield(event)
        }
    }

    private func configureRuntimeEnvironment() {
        let bundleRoot = coreURL.deletingLastPathComponent().deletingLastPathComponent()
        let resources = bundleRoot.appendingPathComponent("Resources", isDirectory: true)
        let pluginPath = resources.appendingPathComponent("gstreamer-1.0", isDirectory: true)
        let registryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.framerelay.FrameRelay/gstreamer-registry.bin")

        setenv("UXPLAYRC", resources.appendingPathComponent("FrameRelay.uxplayrc").path, 1)
        setenv("GST_PLUGIN_PATH_1_0", pluginPath.path, 1)
        setenv("GST_PLUGIN_SYSTEM_PATH_1_0", "", 1)
        setenv("GST_PLUGIN_SCANNER", pluginPath.appendingPathComponent("gst-plugin-scanner").path, 1)
        setenv("GST_REGISTRY_1_0", registryURL.path, 1)
    }

    private static func errorMessage(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let message = String(bytes: bytes, encoding: .utf8), !message.isEmpty else {
            return "未知加载错误"
        }
        return message
    }
}
