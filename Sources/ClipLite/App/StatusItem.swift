import AppKit

/// 菜单栏图标 + 下拉菜单
final class StatusBarController {
    let statusItem: NSStatusItem
    weak var coordinator: AppCoordinator?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let icon = Bundle.main.url(forResource: "ClipLiteMenuBar", withExtension: "svg")
                .flatMap { NSImage(contentsOf: $0) }
            button.image = icon ?? NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "ClipLite")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
            button.toolTip = "ClipLite"
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let s = AppSettings.shared
        menu.addItem(item("截图  \(HotKeyFormatter.label(s.screenshotHotKey))", #selector(AppCoordinator.startCapture)))
        menu.addItem(item("贴图：剪贴板  \(HotKeyFormatter.label(s.pinClipboardHotKey))", #selector(AppCoordinator.pinClipboard)))
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(AppCoordinator.showSettings)))
        menu.addItem(item("屏幕录制权限…", #selector(AppCoordinator.openScreenCapturePrefs)))
        menu.addItem(item("重启应用", #selector(AppCoordinator.relaunch)))
        menu.addItem(.separator())
        menu.addItem(item("退出 ClipLite", #selector(AppCoordinator.quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: action, keyEquivalent: "")
        m.target = coordinator
        return m
    }
}
