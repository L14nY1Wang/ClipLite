import AppKit

/// 贴图窗口本体：非激活面板，从不抢焦点。
final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isReleasedWhenClosed = false   // 贴图窗口由控制器强引用管理，close() 不得再释放
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }
}

final class PinWindowController: NSObject, NSWindowDelegate {
    let panel: PinPanel
    let pinView: PinView
    var onClose: (() -> Void)?
    private var ocrPanel: OCRResultPanel?

    init(image: CGImage, frame: NSRect) {
        var f = frame
        if f.width <= 0 || f.height <= 0 {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            f.size = NSSize(width: CGFloat(image.width) / scale,
                            height: CGFloat(image.height) / scale)
        }
        panel = PinPanel(frame: f)
        pinView = PinView(image: image, baseSize: f.size)
        super.init()
        pinView.owner = self
        panel.contentView = pinView
        panel.delegate = self
    }

    func show() { panel.orderFrontRegardless() }

    func windowWillClose(_ notification: Notification) { onClose?() }

    // MARK: - 右键菜单动作
    @objc func close() { panel.close() }
    @objc func copyImage() { Clipboard.write(image: pinView.cgImage) }
    @objc func setOpacity100() { panel.alphaValue = 1 }
    @objc func setOpacity80() { panel.alphaValue = 0.8 }
    @objc func setOpacity60() { panel.alphaValue = 0.6 }
    @objc func setOpacity40() { panel.alphaValue = 0.4 }
    @objc func toggleShadow() {
        panel.hasShadow.toggle()
        panel.invalidateShadow()
    }

    /// 对整张贴图做离线 OCR，结果停靠面板显示。
    @objc func recognize() {
        if ocrPanel == nil { ocrPanel = OCRResultPanel() }
        let img = pinView.cgImage
        VisionOCR.recognize(img) { [weak self] text in
            guard let self = self else { return }
            let above = NSWindow.Level(rawValue: Int(self.panel.level.rawValue) + 1)
            self.ocrPanel?.show(text: text, below: self.panel.frame, level: above)
        }
    }

    func showMenu(event: NSEvent) {
        let m = NSMenu()
        m.addItem(titled("识别文字", #selector(recognize)))
        m.addItem(titled("复制图片", #selector(copyImage)))
        m.addItem(.separator())
        m.addItem(titled("关闭", #selector(close)))
        m.addItem(.separator())
        let op = NSMenu(title: "不透明度")
        op.addItem(titled("100%", #selector(setOpacity100)))
        op.addItem(titled("80%", #selector(setOpacity80)))
        op.addItem(titled("60%", #selector(setOpacity60)))
        op.addItem(titled("40%", #selector(setOpacity40)))
        let opItem = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        opItem.submenu = op
        m.addItem(opItem)
        m.addItem(titled("阴影", #selector(toggleShadow)))
        NSMenu.popUpContextMenu(m, with: event, for: pinView)
    }

    private func titled(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }
}
