import Foundation

nonisolated struct EngineLogParser: Sendable {
    func parse(level: Int32, message: String) -> EngineEvent? {
        let lowercased = message.lowercased()

        if let geometry = parseVideoGeometry(from: message) {
            return .videoStarted(geometry)
        }

        if lowercased.contains("stopping raop server") {
            return .engineStopped
        }

        if lowercased.contains("worker exited unexpectedly") {
            return .engineError(message)
        }

        if lowercased.contains("framerelay avlayer watchdog: action=restart") {
            return .displayStalled(message)
        }

        if lowercased.contains("open connections: 0") ||
            lowercased.contains("stop mirroring") ||
            lowercased.contains("client disconnected") ||
            lowercased.contains("disconnected from client") {
            return .clientDisconnected
        }

        if lowercased.contains("connection reset") ||
            lowercased.contains("resetting connection") ||
            lowercased.contains("lost connection with client") ||
            lowercased.contains("video_reset") ||
            lowercased.contains("full_video_reset") {
            return .clientReset
        }

        // This is emitted after the video geometry has already been reported.
        // It describes the GStreamer pipeline, not a new client connection.
        // Treating it as .clientConnected re-arms the host's 12-second
        // pre-video watchdog and deterministically stops a healthy stream.
        if lowercased.contains("begin streaming to gstreamer video pipeline") {
            return nil
        }

        if lowercased.contains("open connections: 1") ||
            lowercased.contains("connection request from") ||
            lowercased.contains("registered new client") ||
            lowercased.contains("begin streaming") ||
            lowercased.contains("begin stream") ||
            lowercased.contains("client connected") {
            return .clientConnected
        }

        if lowercased.contains("initialized server socket") ||
            lowercased.contains("advertised airplay service") ||
            lowercased.contains("server ready") ||
            lowercased.contains("start_raop_server") {
            return .serverReady
        }

        if level >= 3 || lowercased.contains("error") || lowercased.contains("fatal") {
            return .engineError(message)
        }

        return nil
    }

    private func parseVideoGeometry(from message: String) -> VideoGeometry? {
        let lowercased = message.lowercased()
        guard let marker = lowercased.range(of: "begin video stream wxh = ") else {
            return nil
        }

        let remainder = message[marker.upperBound...]
        let dimensionText = remainder.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let dimensionText else {
            return nil
        }

        let dimensions = dimensionText.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: true)
        guard dimensions.count == 2,
              let width = Int(dimensions[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let height = Int(dimensions[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              width > 0,
              height > 0 else {
            return nil
        }

        let rotation: Int
        if let rotationRange = lowercased.range(of: "rot=0x") {
            let rotationText = lowercased[rotationRange.upperBound...]
                .prefix { $0.isHexDigit }
            rotation = Int(rotationText, radix: 16) ?? 0
        } else {
            rotation = 0
        }

        return VideoGeometry(width: width, height: height, rotationHint: rotation)
    }
}
