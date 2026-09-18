import AppKit

@MainActor
final class VideoHostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    func clearVideoLayers() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        layer?.backgroundColor = NSColor.black.cgColor
    }

    var opaqueAddress: UInt {
        UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
    }
}
