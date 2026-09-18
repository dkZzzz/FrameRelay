import AppKit

@main
@MainActor
struct FrameRelayMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate(arguments: CommandLine.arguments)
        application.delegate = delegate
        // FrameRelay owns a real, user-visible window.  A regular activation
        // policy gives it a Dock item, a normal application menu, and the
        // window participation that Stage Manager expects.
        application.setActivationPolicy(.regular)
        application.run()
    }
}
