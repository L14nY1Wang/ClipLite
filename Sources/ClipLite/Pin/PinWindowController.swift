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
    /// 切分出的子贴图经此回调交还 PinController 创建（避免控制器反向持有 PinController）
    var onSplit: ((CGImage, NSRect) -> Void)?

    init(image: CGImage, frame: NSRect) {
        var f = frame
        if f.width <= 0 || f.height <= 0 {
            let scale = NSScreen.backingScaleFactor(at: NSPoint(x: f.midX, y: f.midY))
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

    func windowWillClose(_ notification: Notification) {
        // 关闭贴图前先撤掉文字叠加层，避免残留的光标矩形/绘制状态挂在即将释放的视图上
        pinView.hideOCROverlay()
        // 断开 panel→pinView 强引用，让 pinView/cgImage 随控制器释放。
        panel.contentView = nil
        let callback = onClose
        onClose = nil
        callback?()
    }

    // MARK: - 右键菜单动作
    @objc func close() { panel.close() }
    @objc func copyImage() { Clipboard.write(image: pinView.cgImage) }
    /// 进入/退出切分模式：框选一块区域生成新贴图，原贴图保留
    @objc func toggleSplit() { pinView.cropMode.toggle() }
    /// PinView 框选完成回调
    func splitOut(image: CGImage, frame: NSRect) { onSplit?(image, frame) }
    @objc func toggleShadow() {
        panel.hasShadow.toggle()
        panel.invalidateShadow()
    }

    /// 识别文字：结果按原位叠加在贴图上；已在叠加状态则再点一次隐藏（菜单项随之变「隐藏文字」）。
    @objc func recognize() {
        if pinView.isOCROverlayActive { pinView.hideOCROverlay(); return }
        let img = pinView.cgImage
        VisionOCR.recognize(img) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let lines):
                self.pinView.showOCROverlay(lines: OCRTextOverlay.readingOrder(lines),
                                            message: lines.isEmpty ? "未识别到文字" : nil)
            case .failure(let error):
                self.pinView.showOCROverlay(lines: [], message: "识别失败（\(error.localizedDescription)）")
            }
        }
    }

    /// 复制划选文字（无选中则复制全部）
    @objc func copyOCRText() { pinView.copyOCRSelection() }
    @objc func copyAllOCRText() { pinView.copyAllOCR() }

    func showMenu(event: NSEvent) {
        let m = NSMenu()
        let overlay = pinView.isOCROverlayActive
        if overlay {
            m.addItem(titled("复制选中文字", #selector(copyOCRText)))
            m.addItem(titled("复制全部文字", #selector(copyAllOCRText)))
            m.addItem(.separator())
        }
        m.addItem(titled(overlay ? "隐藏文字" : "识别文字", #selector(recognize)))
        m.addItem(titled("复制图片", #selector(copyImage)))
        m.addItem(titled(pinView.cropMode ? "退出切分" : "切分贴图", #selector(toggleSplit)))
        m.addItem(titled("关闭", #selector(close)))
        m.addItem(.separator())

        // 不透明度：标题单独一行，滑条换到下一行，菜单更窄
        let header = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)

        let rowH: CGFloat = 26, rowW: CGFloat = 150
        let container = NSView(frame: NSRect(x: 0, y: 0, width: rowW, height: rowH))
        let slider = NSSlider(frame: NSRect(x: 10, y: (rowH - 18) / 2, width: rowW - 20, height: 18))
        slider.sliderType = .linear
        slider.minValue = 0.2; slider.maxValue = 1.0
        slider.doubleValue = Double(panel.alphaValue)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(opacityChanged(_:))
        container.addSubview(slider)
        let opItem = NSMenuItem()
        opItem.view = container
        m.addItem(opItem)

        m.addItem(titled("阴影", #selector(toggleShadow)))
        NSMenu.popUpContextMenu(m, with: event, for: pinView)
    }

    @objc private func opacityChanged(_ s: NSSlider) {
        panel.alphaValue = CGFloat(s.doubleValue)
    }

    private func titled(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }
}
