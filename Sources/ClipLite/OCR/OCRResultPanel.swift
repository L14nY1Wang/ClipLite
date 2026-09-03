import AppKit

/// OCR 结果面板：可选中、可复制。非激活标题面板，不抢走其他应用焦点。
final class OCRResultPanel: NSPanel {
    private var textView: NSTextView!

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 380, height: 280)
        super.init(contentRect: contentRect,
                   styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false   // 由标注控制器强引用管理
        title = "OCR 识别结果"
        level = .floating

        let scroll = NSScrollView(frame: contentRect)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .noBorder

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        // 底部工具条：复制全文
        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: 36))
        bar.material = .headerView
        bar.state = .active

        contentView = scroll

        let copyBtn = NSButton(title: "复制全文", target: self, action: #selector(copyAll))
        copyBtn.bezelStyle = .rounded
        copyBtn.frame = NSRect(x: 280, y: 5, width: 90, height: 26)
        copyBtn.autoresizingMask = [.minXMargin, .maxYMargin]
        bar.addSubview(copyBtn)
        addSubviewToContent(bar)
    }

    private func addSubviewToContent(_ v: NSView) {
        contentView?.addSubview(v)
        v.autoresizingMask = [.width]
        v.frame.origin.y = 0
    }

    func show(text: String, near rect: NSRect) {
        textView.string = text
        let screen = NSScreen.screens.first { $0.frame.contains(rect) } ?? NSScreen.main
        let sf = screen?.frame ?? .zero
        var origin = NSPoint(x: rect.maxX + 12, y: rect.midY - frame.height / 2)
        if origin.x + frame.width > sf.maxX {
            origin.x = rect.minX - frame.width - 12
        }
        if origin.x < sf.minX {
            origin.x = sf.maxX - frame.width - 20
        }
        origin.y = min(max(origin.y, sf.minY + 20), sf.maxY - frame.height - 20)
        setFrameTopLeftPoint(origin)
        makeKeyAndOrderFront(nil)
    }

    @objc private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(textView.string, forType: .string)
    }
}
