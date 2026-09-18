import AppKit

@MainActor
final class ReceiverWindowController: NSWindowController {
    let hostView: VideoHostView

    private var lastAppliedGeometry: VideoGeometry?

    init() {
        self.hostView = VideoHostView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FrameRelay"
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 320, height: 240)
        window.level = .normal
        window.sharingType = .readOnly
        window.contentView = hostView

        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("ReceiverWindowController does not support NSCoder initialization")
    }

    var hostViewAddress: UInt {
        hostView.opaqueAddress
    }

    func showReceiverWindow() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hideReceiverWindow() {
        window?.orderOut(nil)
    }

    func clearVideo() {
        lastAppliedGeometry = nil
        hostView.clearVideoLayers()
    }

    @discardableResult
    func applyVideoGeometry(_ geometry: VideoGeometry) -> Bool {
        guard geometry.width > 0, geometry.height > 0,
              let window else { return false }
        guard lastAppliedGeometry != geometry else { return false }

        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let available = VideoWindowSize(
            width: max(VideoWindowSizer.minimumContent.width, visibleFrame.width - 80),
            height: max(VideoWindowSizer.minimumContent.height, visibleFrame.height - 120)
        )
        let target = VideoWindowSizer.contentSize(for: geometry, available: available)
        let contentSize = NSSize(width: target.width, height: target.height)

        // Lock manual resizing to the actual negotiated video aspect ratio.
        // The title bar remains native; only the content rectangle follows the
        // phone's orientation and negotiated dimensions.
        window.contentAspectRatio = contentSize

        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        let oldFrame = window.frame
        var targetFrame = NSRect(
            x: oldFrame.midX - targetFrameSize.width / 2,
            y: oldFrame.midY - targetFrameSize.height / 2,
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )

        // Keep the resized window on the current display, including when an
        // orientation change makes the portrait window taller than before.
        targetFrame.origin.x = min(
            max(targetFrame.origin.x, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - targetFrame.width)
        )
        targetFrame.origin.y = min(
            max(targetFrame.origin.y, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - targetFrame.height)
        )

        window.setFrame(targetFrame, display: true, animate: window.isVisible)
        lastAppliedGeometry = geometry
        return true
    }
}
