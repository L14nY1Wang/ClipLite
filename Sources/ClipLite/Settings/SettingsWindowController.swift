import AppKit
import Carbon.HIToolbox

/// 设置窗口：自定义截图 / 贴图热键，开机自启。分组卡片 + 键帽式按钮。
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Kind { case screenshot, pin }

    private weak var coordinator: AppCoordinator?
    private var recorders: [Kind: NSButton] = [:]
    private var recording: Kind?
    private var monitor: Any?
    private let launchSwitch = NSSwitch()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "ClipLite 设置"
        w.isReleasedWhenClosed = false
        w.center()
        super.init(window: w)
        w.delegate = self
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI
    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // 头部：图标 + 标题
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 12
        let icon = makeIconTile()
        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.spacing = 2
        let title = NSTextField(labelWithString: "ClipLite")
        title.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        let subtitle = NSTextField(labelWithString: "截图 · 贴图 · 标注 · OCR")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        titleStack.addArrangedSubview(title)
        titleStack.addArrangedSubview(subtitle)
        header.addArrangedSubview(icon)
        header.addArrangedSubview(titleStack)
        root.addArrangedSubview(header)

        // 卡片：快捷键
        let hkCard = makeCard("快捷键")
        let grid = NSGridView(views: [
            [rowLabel("截图"), recorderButton(.screenshot)],
            [rowLabel("贴图"), recorderButton(.pin)],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        hkCard.content.addArrangedSubview(grid)
        root.addArrangedSubview(hkCard.box)

        // 卡片：通用
        let genCard = makeCard("通用")
        let launchRow = NSStackView()
        launchRow.orientation = .horizontal
        launchRow.spacing = 8
        let launchLabel = NSTextField(labelWithString: "开机时自动启动")
        launchLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        launchSwitch.target = self
        launchSwitch.action = #selector(toggleLaunch(_:))
        genCard.content.addArrangedSubview(launchRow)   // 先入树，再取子视图
        launchRow.addArrangedSubview(launchLabel)
        launchRow.addArrangedSubview(launchSwitch)
        root.addArrangedSubview(genCard.box)

        // 提示
        let hint = NSTextField(wrappingLabelWithString: "点击热键框，再按下新的组合键（需包含 ⌘ / ⌥ / ⌃ / ⇧ 之一）；按 Esc 取消。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.widthAnchor.constraint(equalToConstant: 360).isActive = true
        root.addArrangedSubview(hint)

        refreshTitles()
    }

    private func makeIconTile() -> NSView {
        let tile = NSView(frame: .zero)
        tile.wantsLayer = true
        tile.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        tile.layer?.cornerRadius = 9
        tile.widthAnchor.constraint(equalToConstant: 40).isActive = true
        tile.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let iv = NSImageView()
        iv.contentTintColor = .white
        iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        iv.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        iv.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
        ])
        return tile
    }

    private func makeCard(_ title: String) -> (box: NSView, content: NSStackView) {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let header = NSTextField(labelWithString: title)
        header.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        stack.addArrangedSubview(header)
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        box.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return (box, stack)
    }

    private func rowLabel(_ s: String) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = NSFont.systemFont(ofSize: 13)
        return t
    }

    private func recorderButton(_ kind: Kind) -> NSButton {
        let b = NSButton(title: "", target: self, action: #selector(beginRecord(_:)))
        b.tag = kind == .screenshot ? 1 : 2
        b.bezelStyle = .roundRect
        b.controlSize = .regular
        b.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        b.widthAnchor.constraint(equalToConstant: 150).isActive = true
        recorders[kind] = b
        return b
    }

    // MARK: - 逻辑
    private func refreshTitles() {
        let s = AppSettings.shared
        recorders[.screenshot]?.title = HotKeyFormatter.label(s.screenshotHotKey)
        recorders[.pin]?.title = HotKeyFormatter.label(s.pinClipboardHotKey)
        launchSwitch.state = s.launchAtLogin ? .on : .off
    }

    @objc private func beginRecord(_ sender: NSButton) {
        let kind: Kind = sender.tag == 1 ? .screenshot : .pin
        if recording == kind { stopRecording(); return }
        stopRecording()
        recording = kind
        sender.title = "按下新快捷键…"
        sender.contentTintColor = .controlAccentColor
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if Int(event.keyCode) == kVK_Escape { self.stopRecording(); return nil }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if mods.isEmpty { return nil }
            let hk = HotKey(keyCode: UInt32(event.keyCode), modifiers: HotKeyCenter.carbonFlags(from: mods))
            self.save(kind, hk)
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        recording = nil
        recorders.values.forEach { $0.contentTintColor = .controlColor }
        refreshTitles()
    }

    private func save(_ kind: Kind, _ hk: HotKey) {
        let s = AppSettings.shared
        switch kind {
        case .screenshot: s.setScreenshot(hk)
        case .pin:        s.setPinClipboard(hk)
        }
        coordinator?.applyHotKeys()
        coordinator?.statusItem.rebuildMenu()
    }

    @objc private func toggleLaunch(_ sender: NSSwitch) {
        AppSettings.shared.launchAtLogin = (sender.state == .on)
        refreshTitles()
    }

    func windowWillClose(_ notification: Notification) {
        window?.level = .normal
        // 关设置后回到“仅菜单栏常驻”
        NSApp.setActivationPolicy(.accessory)
    }

    func showAndActivate() {
        refreshTitles()
        // accessory 应用从后台弹普通窗口会被压住看不见：临时转普通策略 + 激活 + 强制前置
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.level = .floating
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        window?.center()
    }
}
