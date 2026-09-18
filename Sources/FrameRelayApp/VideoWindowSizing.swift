import Foundation

nonisolated struct VideoWindowSize: Sendable, Equatable {
    let width: Double
    let height: Double
}

nonisolated enum VideoWindowSizer {
    static let maximumContent = VideoWindowSize(width: 1280, height: 720)
    static let minimumContent = VideoWindowSize(width: 320, height: 240)

    static func contentSize(for geometry: VideoGeometry, available: VideoWindowSize) -> VideoWindowSize {
        guard geometry.width > 0, geometry.height > 0 else {
            return minimumContent
        }

        let aspect = Double(geometry.width) / Double(geometry.height)
        let maxWidth = max(minimumContent.width, min(maximumContent.width, available.width))
        let maxHeight = max(minimumContent.height, min(maximumContent.height, available.height))

        var width: Double
        var height: Double
        if aspect >= maxWidth / maxHeight {
            width = maxWidth
            height = width / aspect
        } else {
            height = maxHeight
            width = height * aspect
        }

        if width < minimumContent.width {
            width = minimumContent.width
            height = width / aspect
        }
        if height < minimumContent.height {
            height = minimumContent.height
            width = height * aspect
        }

        return VideoWindowSize(width: width, height: height)
    }
}
