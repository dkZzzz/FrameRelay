import Foundation

actor LogWriter {
    private let directoryURL: URL
    private let logURL: URL
    private let maximumBytes = 5 * 1024 * 1024

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.logURL = directoryURL.appendingPathComponent("FrameRelay.log")
    }

    func append(_ log: EngineLog) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try rotateIfNeeded()

            let formatter = ISO8601DateFormatter()
            let line = "[\(formatter.string(from: log.timestamp))] [\(log.level)] \(log.message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Logging must never take down the receiver. The OS Logger in the app
            // layer remains available when a user-facing diagnostic is requested.
        }
    }

    func url() -> URL {
        logURL
    }

    private func rotateIfNeeded() throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue >= maximumBytes else {
            return
        }

        let second = directoryURL.appendingPathComponent("FrameRelay.log.2")
        let first = directoryURL.appendingPathComponent("FrameRelay.log.1")

        if FileManager.default.fileExists(atPath: second.path) {
            try FileManager.default.removeItem(at: second)
        }
        if FileManager.default.fileExists(atPath: first.path) {
            try FileManager.default.moveItem(at: first, to: second)
        }
        if FileManager.default.fileExists(atPath: logURL.path) {
            try FileManager.default.moveItem(at: logURL, to: first)
        }
    }
}
