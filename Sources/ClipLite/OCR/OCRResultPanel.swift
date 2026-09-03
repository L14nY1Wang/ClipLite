import AppKit

/// 可划选的 OCR 结果面板（无边框、停靠于目标区域下方，不再是抢焦点的独立大弹窗）。
/// 标注层与贴图层共用：show(text:below:level:)。
final class OCRResultPanel: NSPanel {
    private let textView = NSTextView()
    private let panelW: CGFloat = 400
    private let panelH: CGFloat = 260
    private let headerH: CGFloat = 30

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
                   styleMask: [.borderless, .nonactivatingPanel, .titled],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = NSColor.windowBackgroundColor
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let root = contentView!

        // 头部：标题 + 复制全部 + 关闭
        let title = NSTextField(labelWithString: "OCR 识别结果（可划选文字）")
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.frame = NSRect(x: 14, y: panelH - headerH + 5, width: 250, height: 18)
        title.autoresizingMask = [.width]
        root.addSubview(title)

        let copy = NSButton(title: "复制全部", target: self, action: #selector(copyAll))
        copy.bezelStyle = .inline; copy.controlSize = .small
        copy.frame = NSRect(x: panelW - 120, y: panelH - headerH + 2, width: 82, height: 22)
        copy.autoresizingMask = [.minXMargin]
        root.addSubview(copy)

        let close = NSButton(title: "✕", target: self, action: #selector(dismiss))
        close.isBordered = false; close.contentTintColor = .secondaryLabelColor
        close.frame = NSRect(x: panelW - 32, y: panelH - headerH + 2, width: 22, height: 22)
        close.autoresizingMask = [.minXMargin]
        root.addSubview(close)

        // 文本区（可选中/划选）
        let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: panelW - 20, height: panelH - headerH - 20))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        root.addSubview(scroll)
    }

    /// 停靠显示在 rect（全局点坐标）下方，放不下放上方。level 需高于宿主窗口以浮在其上。
    func show(text: String, below rect: NSRect, level: NSWindow.Level) {
        self.level = level
        textView.string = text
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        let sf = screen?.frame ?? .zero
        var x = rect.midX - panelW / 2
        x = min(max(x, sf.minX + 8), sf.maxX - panelW - 8)
        var y = rect.minY - panelH - 10
        if y < sf.minY + 8 { y = rect.maxY + 10 }
        y = min(max(y, sf.minY + 8), sf.maxY - panelH - 8)
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
    }

    @objc private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(textView.string, forType: .string)
    }

    @objc private func dismiss() { orderOut(nil) }
}
