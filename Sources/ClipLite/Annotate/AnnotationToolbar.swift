import AppKit

enum ToolbarAction {
    case undo, ocr, copy, save, pin, cancel
}

/// 浮动标注工具条：非激活面板，点击不抢走画布键盘焦点。
final class AnnotationToolbar: NSPanel {
    var onSelectTool: ((AnnotationTool) -> Void)?
    var onAction: ((ToolbarAction) -> Void)?
    var onColor: ((NSColor) -> Void)?

    private var toolButtons: [NSButton: AnnotationTool] = [:]
    private var actionButtons: [NSButton: ToolbarAction] = [:]
    private var colorButtons: [NSButton: NSColor] = [:]

    private let palette: [(String, NSColor)] = [
        ("systemRed", NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)),
        ("systemOrange", NSColor.systemOrange),
        ("systemYellow", NSColor.systemYellow),
        ("systemGreen", NSColor.systemGreen),
        ("systemBlue", NSColor.systemBlue),
        ("labelColor", NSColor.labelColor)
    ]

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 46),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = false

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 10, height: 46))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        let tools: [(AnnotationTool, String, String)] = [
            (.select, "cursorarrow", "选择"),
            (.rect, "rectangle", "矩形"),
            (.ellipse, "circle", "椭圆"),
            (.arrow, "arrow.up.right", "箭头"),
            (.pen, "pencil.tip", "画笔"),
            (.text, "textformat", "文字"),
            (.number, "1.circle", "序号标记"),
            (.mosaic, "square.grid.3x3", "马赛克")
        ]
        for (tool, symbol, tip) in tools {
            let b = symbolButton(symbol, tip)
            toolButtons[b] = tool
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(separator())

        for (name, color) in palette {
            let b = symbolButton("circle.fill", name)
            b.image = colorSwatch(color)
            colorButtons[b] = color
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(separator())

        let actions: [(ToolbarAction, String, String)] = [
            (.undo, "arrow.uturn.backward", "撤销"),
            (.ocr, "doc.text.viewfinder", "OCR 文字识别"),
            (.copy, "doc.on.doc", "复制到剪贴板"),
            (.save, "square.and.arrow.down", "保存文件"),
            (.pin, "pin", "贴图"),
            (.cancel, "xmark.circle", "取消")
        ]
        for (action, symbol, tip) in actions {
            let b = symbolButton(symbol, tip)
            actionButtons[b] = action
            stack.addArrangedSubview(b)
        }

        let size = stack.fittingSize
        effect.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        stack.frame = effect.frame
        contentView = effect
        addSubviewFixed(stack)
        setFrame(NSRect(x: 0, y: 0, width: size.width, height: size.height), display: false)
    }

    private func addSubviewFixed(_ v: NSView) {
        contentView?.addSubview(v)
    }

    private func symbolButton(_ symbol: String, _ tip: String) -> NSButton {
        let b = NSButton(title: "", target: self, action: #selector(clicked(_:)))
        let cfg = NSImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(cfg)
        b.imagePosition = .imageOnly
        b.isBordered = false
        b.controlSize = .large
        b.contentTintColor = .secondaryLabelColor
        b.toolTip = tip
        return b
    }

    private func separator() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 30))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return v
    }

    private func colorSwatch(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return img
    }

    @objc private func clicked(_ sender: NSButton) {
        if let tool = toolButtons[sender] {
            highlightTool(sender)
            onSelectTool?(tool)
        } else if let action = actionButtons[sender] {
            onAction?(action)
        } else if let color = colorButtons[sender] {
            onColor?(color)
        }
    }

    /// 高亮当前工具按钮
    func highlightTool(_ button: NSButton) {
        for (b, _) in toolButtons {
            b.contentTintColor = (b === button) ? .controlAccentColor : .secondaryLabelColor
        }
    }

    func highlightDefaultTool() {
        // 默认高亮矩形工具（与 canvas.currentTool 初始值一致；"选择"按钮虽排最左但不是默认）
        if let first = toolButtons.first(where: { $0.value == .rect }) {
            highlightTool(first.key)
        }
    }
}
