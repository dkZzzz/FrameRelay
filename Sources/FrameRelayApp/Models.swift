import Foundation

nonisolated struct AirPlayConfiguration: Sendable, Equatable {
    let deviceName: String
    let options: String
}

extension AirPlayConfiguration {
    private nonisolated static let liveStreamOptions = "-p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080"

    nonisolated static let liveVideo = AirPlayConfiguration(
        deviceName: "FrameRelay",
        // Leave UxPlay's timestamp-based video sync enabled.  `-fps 60` is a
        // maximum request, not a promise that the phone sends 60 frames/s;
        // carrying the negotiated timestamps lets the display layer pace the
        // frames instead of presenting an arrival-rate burst.
        options: liveStreamOptions
    )

    // These profiles are intentionally opt-in command-line diagnostics. The
    // normal app path above remains the fixed production configuration. `-FPSdata`
    // asks the pinned UxPlay core to log the performance plist sent by the
    // iPhone once per second; the 720p and no-sync profiles change only one
    // diagnostic variable for a controlled A/B test.
    nonisolated static let diagnostic1080p = AirPlayConfiguration(
        deviceName: "FrameRelay",
        options: "\(liveStreamOptions) -FPSdata"
    )

    nonisolated static let diagnostic1080pNoSync = AirPlayConfiguration(
        deviceName: "FrameRelay",
        options: "\(liveStreamOptions) -vsync no -FPSdata"
    )

    nonisolated static let diagnostic720p = AirPlayConfiguration(
        deviceName: "FrameRelay",
        options: "-p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1280x720 -FPSdata"
    )
}

nonisolated enum FrameRelayLaunchProfile: String, Sendable, Equatable {
    case normal
    case diagnostic1080p
    case diagnostic1080pNoSync
    case diagnostic720p

    init(arguments: [String]) {
        if arguments.contains("--diagnostic-1080p-nosync") {
            self = .diagnostic1080pNoSync
        } else if arguments.contains("--diagnostic-720p") {
            self = .diagnostic720p
        } else if arguments.contains("--diagnostic-1080p") {
            self = .diagnostic1080p
        } else {
            self = .normal
        }
    }

    var configuration: AirPlayConfiguration {
        switch self {
        case .normal:
            return .liveVideo
        case .diagnostic1080p:
            return .diagnostic1080p
        case .diagnostic1080pNoSync:
            return .diagnostic1080pNoSync
        case .diagnostic720p:
            return .diagnostic720p
        }
    }

    var displayName: String {
        switch self {
        case .normal:
            return "normal"
        case .diagnostic1080p:
            return "diagnostic-1080p"
        case .diagnostic1080pNoSync:
            return "diagnostic-1080p-nosync"
        case .diagnostic720p:
            return "diagnostic-720p"
        }
    }

    var isDiagnostic: Bool {
        self != .normal
    }
}

nonisolated struct VideoGeometry: Sendable, Equatable {
    let width: Int
    let height: Int
    let rotationHint: Int
}

nonisolated struct EngineLog: Sendable, Equatable {
    let timestamp: Date
    let level: Int32
    let message: String
}

nonisolated enum EngineEvent: Sendable, Equatable {
    case serverStarting
    case serverReady
    case clientConnected
    case videoStarted(VideoGeometry)
    case clientReset
    case clientDisconnected
    case engineError(String)
    case displayStalled(String)
    case engineStopped
}

nonisolated enum ReceiverState: Sendable, Equatable {
    case stopped
    case starting
    case waitingForIPhone
    case connecting
    case streaming(VideoGeometry)
    case reconnecting
    case failed(String)
}

enum EngineFailure: LocalizedError, Sendable {
    case coreUnavailable(String)
    case configurationFailed(String)
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .coreUnavailable(let message):
            return "AirPlay 核心不可用：\(message)"
        case .configurationFailed(let message):
            return "AirPlay 核心配置失败：\(message)"
        case .alreadyRunning:
            return "AirPlay 核心已经在运行"
        }
    }
}
