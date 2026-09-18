import Foundation

nonisolated struct RestartPolicy: Sendable {
    private static let window: TimeInterval = 60
    private var attempts: [Date] = []

    mutating func reset() {
        attempts.removeAll(keepingCapacity: true)
    }

    mutating func nextDelayNanoseconds(now: Date = Date()) -> UInt64? {
        attempts.removeAll { now.timeIntervalSince($0) > Self.window }
        guard attempts.count < 3 else {
            return nil
        }

        let attempt = attempts.count
        attempts.append(now)
        switch attempt {
        case 0:
            return 500_000_000
        case 1:
            return 1_000_000_000
        default:
            return 2_000_000_000
        }
    }
}
