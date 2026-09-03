import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护：同一 bundle 已有其它进程在跑，则激活它并退出，避免多个截图热键实例互相串扰
        let myID = Bundle.main.bundleIdentifier ?? ""
        let myPID = ProcessInfo.processInfo.processIdentifier
        if let other = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == myID && $0.processIdentifier != myPID
        }) {
            other.activate(options: [])
            NSLog("ClipLite: 检测到已运行实例 pid=\(other.processIdentifier)，当前实例退出")
            NSApp.terminate(nil)
            return
        }
        coordinator.start()
    }
}

/// 单一协调中枢：持有菜单栏、热键、各功能控制器，避免互相 retain 的环。
final class AppCoordinator: NSObject {
    let statusItem = StatusBarController()
    let hotKeys = HotKeyCenter.shared
    let settings = AppSettings.shared

    private var selection: SelectionController?
    private var annotation: AnnotationWindowController?
    private let pinController = PinController()
    private lazy var settingsWC = SettingsWindowController(coordinator: self)

    func start() {
        statusItem.coordinator = self
        statusItem.rebuildMenu()

        // 首次运行主动发起屏幕录制授权（系统弹窗归属本应用）
        if !ScreenCapture.preflight() {
            _ = ScreenCapture.request()
        }

        applyHotKeys()

        // 自动化接口：`ClipLite --trigger-capture`（供脚本/测试调用）
        DistributedNotificationCenter.default().addObserver(self,
                                                            selector: #selector(onTrigger(_:)),
                                                            name: .init("com.lianyi.cliplite.trigger"),
                                                            object: nil)

        // 调试：启动即打开设置窗（`open ClipLite.app --args --open-settings`）
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showSettings() }
        }
    }

    /// 依据当前设置注册全局热键（截图 / 贴图），改键后重新调用即可热更新。
    func applyHotKeys() {
        let s = settings.screenshotHotKey
        hotKeys.register(id: 1, keyCode: s.keyCode, modifiers: s.modifiers) { [weak self] in
            self?.startCapture()
        }
        let p = settings.pinClipboardHotKey
        hotKeys.register(id: 2, keyCode: p.keyCode, modifiers: p.modifiers) { [weak self] in
            self?.pinClipboard()
        }
    }

    @objc private func onTrigger(_ note: Notification) {
        let action = (note.userInfo?["action"] as? String) ?? "capture"
        NSLog("ClipLite.trace onTrigger action=\(action)")
        DispatchQueue.main.async {
            switch action {
            case "capture": self.startCapture()
            case "pin": self.pinClipboard()
            case "settings": self.showSettings()
            default: break
            }
        }
    }

    // MARK: - 截图
    @objc func startCapture() {
        NSLog("ClipLite.trace startCapture enter (selection=\(selection == nil ? "nil" : "busy"))")
        guard selection == nil else { return } // 已有进行中的会话则忽略
        let sel = SelectionController()
        sel.coordinator = self
        selection = sel
        sel.start()
    }

    /// 选区确认后回调：把整屏截图 + 选区交给标注层（框可在标注时再拖动/缩放）。
    func didFinishSelection(fullImage: CGImage, screen: NSScreen, selectionLocal: NSRect) {
        selection = nil   // 关键：成功路径也要复位，否则 startCapture 的 guard 会永久拦截后续截图
        let ann = AnnotationWindowController(fullImage: fullImage, screen: screen, initialSelection: selectionLocal)
        ann.coordinator = self
        annotation = ann
        DispatchQueue.main.async { ann.show() }
    }

    func didCancelSelection() {
        selection = nil
    }

    func annotationDidClose() {
        annotation = nil
    }

    /// 供标注层调用：贴图
    func pin(image: CGImage, at frame: NSRect) {
        pinController.pin(image: image, at: frame)
    }

    // MARK: - 贴图
    @objc func pinClipboard() {
        guard let img = Clipboard.readImage() else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let sizePt = NSSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
        let pt = NSEvent.mouseLocation
        let frame = NSRect(x: pt.x - sizePt.width / 2,
                           y: pt.y - sizePt.height / 2,
                           width: sizePt.width, height: sizePt.height)
        pinController.pin(image: img, at: frame)
    }

    // MARK: - 菜单动作
    @objc func showSettings() {
        settingsWC.showAndActivate()
    }

    @objc func openScreenCapturePrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; open \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
