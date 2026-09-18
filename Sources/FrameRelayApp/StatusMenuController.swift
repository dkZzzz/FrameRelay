import AppKit

@MainActor
final class StatusMenuController: NSObject {
    private weak var owner: AppDelegate?
    private let statusItem: NSStatusItem
    private let stateItem = NSMenuItem(title: "状态：未启动", action: nil, keyEquivalent: "")
    private let startItem = NSMenuItem(title: "启动接收", action: #selector(AppDelegate.startReceiver), keyEquivalent: "")
    private let stopItem = NSMenuItem(title: "停止接收", action: #selector(AppDelegate.stopReceiver), keyEquivalent: "")
    private let restartItem = NSMenuItem(title: "重新启动", action: #selector(AppDelegate.restartReceiver), keyEquivalent: "")

    init(owner: AppDelegate) {
        self.owner = owner
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "FrameRelay", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "显示接收窗口", action: #selector(AppDelegate.showReceiverWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "隐藏接收窗口", action: #selector(AppDelegate.hideReceiverWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(restartItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "复制诊断信息", action: #selector(AppDelegate.copyDiagnostics), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开日志目录", action: #selector(AppDelegate.openLogs), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 FrameRelay", action: #selector(AppDelegate.quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = owner }
        statusItem.menu = menu
        statusItem.button?.image = NSImage(
            systemSymbolName: "dot.radiowaves.left.and.right",
            accessibilityDescription: "FrameRelay"
        )
    }

    func update(state: ReceiverState) {
        stateItem.title = "状态：\(Self.title(for: state))"
        startItem.isEnabled = {
            if case .stopped = state { return true }
            if case .failed = state { return true }
            return false
        }()
        stopItem.isEnabled = {
            if case .stopped = state { return false }
            return true
        }()
        restartItem.isEnabled = {
            if case .stopped = state { return false }
            return true
        }()
    }

    private static func title(for state: ReceiverState) -> String {
        switch state {
        case .stopped:
            return "未启动"
        case .starting:
            return "正在启动"
        case .waitingForIPhone:
            return "等待 iPhone"
        case .connecting:
            return "正在连接"
        case .streaming(let geometry):
            return "正在接收 \(geometry.width)×\(geometry.height)"
        case .reconnecting:
            return "正在重连"
        case .failed:
            return "启动失败"
        }
    }
}
