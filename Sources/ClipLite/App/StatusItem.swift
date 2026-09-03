import AppKit
import Carbon.HIToolbox

/// 菜单栏图标 + 下拉菜单
final class StatusBarController {
    let statusItem: NSStatusItem
    weak var coordinator: AppCoordinator?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: "ClipLite")
            button.image?.isTemplate = true
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let s = AppSettings.shared
        menu.addItem(item("截图  \(label(for: s.screenshotHotKey))", #selector(AppCoordinator.startCapture)))
        menu.addItem(item("贴图：剪贴板  \(label(for: s.pinClipboardHotKey))", #selector(AppCoordinator.pinClipboard)))
        menu.addItem(.separator())
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

    private func label(for hk: HotKey) -> String {
        var s = ""
        if hk.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if hk.modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if hk.modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if hk.modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += HotKeyLabel.keyCodeToString(hk.keyCode)
        return s
    }
}
