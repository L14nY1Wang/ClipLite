import AppKit

/// 标注画布（覆盖整屏）：显示完整截图，中间一个可拖动/缩放的蓝色选取框，框内可绘制标注。
/// 最终输出 = 按蓝色框区域裁剪底图并合成标注。视图坐标 = 所在屏的局部点坐标（左下原点）。
final class AnnotationCanvas: NSView, NSTextFieldDelegate {
    let baseImage: CGImage
    let screen: NSScreen

    var selection: NSRect          // 蓝色选取框（局部点坐标）
    var items: [AnnotationItem] = []
    var currentTool: AnnotationTool = .rect
    var currentColor: NSColor = NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
    var sizeScale: CGFloat = 1 { didSet { needsDisplay = true } }   // 拖动条：整体缩放线宽/字号/序号圆
    var lineWidth: CGFloat { 3 * sizeScale }
    var textFontSize: CGFloat { 18 * sizeScale }
    var badgeRadius: CGFloat { 15 * sizeScale }
    var onSelectionChanged: (() -> Void)?
    weak var windowController: AnnotationWindowController?

    private var scaleX: CGFloat = 1
    private var scaleY: CGFloat = 1

    // 交互状态
    private enum Mode { case none, draw, move, resize(Handle) }
    // 按方位命名：n=上, s=下, e=右, w=左（含四角 ne/nw/se/sw）
    private enum Handle: Hashable { case n, s, e, w, ne, nw, se, sw }
    private var mode: Mode = .none
    private var dragAnchor: NSPoint = .zero
    private var startSel: NSRect = .zero
    private var draftStart: NSPoint?
    private var draft: AnnotationItem?
    private var textEditor: NSTextField?
    private var nextNumber: Int = 1     // 序号标记自增

    private let handleSize: CGFloat = 11
    private let borderBand: CGFloat = 6
    private let minSize: CGFloat = 16

    init(fullImage: CGImage, screen: NSScreen, initialSelection: NSRect) {
        self.baseImage = fullImage
        self.screen = screen
        self.selection = initialSelection
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        scaleX = CGFloat(fullImage.width) / screen.frame.width
        scaleY = CGFloat(fullImage.height) / screen.frame.height
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 鼠标
    override func mouseDown(with event: NSEvent) {
        commitTextEditorIfNeeded()
        let p = convert(event.locationInWindow, from: nil)
        if let h = handleAt(p) {
            mode = .resize(h); startSel = selection; needsDisplay = true; return
        }
        if selection.contains(p), distanceToBorder(p) <= borderBand {
            mode = .move; dragAnchor = p; startSel = selection; needsDisplay = true; return
        }
        if selection.contains(p) {
            if currentTool == .text { beginText(at: p); return }
            if currentTool == .number {
                items.append(AnnotationItem(kind: .number, color: currentColor, lineWidth: lineWidth,
                                            rect: NSRect(origin: p, size: .zero),
                                            number: nextNumber, badgeRadius: badgeRadius))
                nextNumber += 1
                needsDisplay = true; return
            }
            mode = .draw; draftStart = p
            draft = AnnotationItem(kind: currentTool, color: currentColor, lineWidth: lineWidth,
                                   rect: NSRect(origin: p, size: .zero), points: [p])
            needsDisplay = true; return
        }
        // 框外按下：不响应（已有可拖拽的蓝框负责调整选区，避免与直接框选冲突）
        mode = .none
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch mode {
        case .move:
            let dx = p.x - dragAnchor.x, dy = p.y - dragAnchor.y
            var r = startSel.offsetBy(dx: dx, dy: dy)
            r = clampInside(r)
            selection = r; onSelectionChanged?(); needsDisplay = true
        case let .resize(h):
            selection = clampSize(resize(h, to: p)); onSelectionChanged?(); needsDisplay = true
        case .draw:
            guard var d = draft, let s = draftStart else { return }
            switch currentTool {
            case .pen: d.points.append(p)
            case .rect, .ellipse, .mosaic: d.rect = normalizeRect(s, p)
            case .arrow: d.points = [s, p]
            case .text, .number: break
            }
            draft = d; needsDisplay = true
        case .none: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch mode {
        case .draw:
            guard var d = draft, let s = draftStart else { break }
            switch currentTool {
            case .pen: d.points.append(p); if d.points.count > 1 { items.append(d) }
            case .rect, .ellipse: d.rect = normalizeRect(s, p); if d.rect.width > 2, d.rect.height > 2 { items.append(d) }
            case .mosaic:
                d.rect = normalizeRect(s, p)
                if d.rect.width > 2, d.rect.height > 2 { d.mosaicSource = buildMosaic(d.rect); if d.mosaicSource != nil { items.append(d) } }
            case .arrow: d.points = [s, p]; items.append(d)
            case .text, .number: break
            }
        case .resize, .move:
            break
        case .none, .draw: break
        }
        mode = .none; draft = nil; draftStart = nil; needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53, 36, 76:               // Esc / Return / KeypadReturn：应用标注后复制并结束
            commitTextEditorIfNeeded()
            windowController?.copyAndClose()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - 选取框几何
    // 画布非翻转（y 轴向上）：maxY=上边、minY=下边。手柄按“移动哪条边”来算，与坐标翻转无关。
    private func handlePoints() -> [(Handle, NSPoint)] {
        let r = selection
        return [
            (.n,  NSPoint(x: r.midX, y: r.maxY)), (.s,  NSPoint(x: r.midX, y: r.minY)),
            (.e,  NSPoint(x: r.maxX, y: r.midY)), (.w,  NSPoint(x: r.minX, y: r.midY)),
            (.ne, NSPoint(x: r.maxX, y: r.maxY)), (.nw, NSPoint(x: r.minX, y: r.maxY)),
            (.se, NSPoint(x: r.maxX, y: r.minY)), (.sw, NSPoint(x: r.minX, y: r.minY)),
        ]
    }
    private func handleRect(_ pt: NSPoint) -> NSRect {
        NSRect(x: pt.x - handleSize/2, y: pt.y - handleSize/2, width: handleSize, height: handleSize)
    }
    private func handleAt(_ p: NSPoint) -> Handle? {
        for (h, pt) in handlePoints() where handleRect(pt).insetBy(dx: -3, dy: -3).contains(p) { return h }
        return nil
    }
    private func distanceToBorder(_ p: NSPoint) -> CGFloat {
        let r = selection
        return min(min(abs(p.x - r.minX), abs(p.x - r.maxX)), min(abs(p.y - r.minY), abs(p.y - r.maxY)))
    }
    private func resize(_ h: Handle, to p: NSPoint) -> NSRect {
        let movesLeft = (h == .w || h == .nw || h == .sw)
        let movesRight = (h == .e || h == .ne || h == .se)
        let movesTop = (h == .n || h == .ne || h == .nw)
        let movesBottom = (h == .s || h == .se || h == .sw)
        let left = movesLeft ? p.x : startSel.minX
        let right = movesRight ? p.x : startSel.maxX
        let bottom = movesBottom ? p.y : startSel.minY
        let top = movesTop ? p.y : startSel.maxY
        return NSRect(x: min(left, right), y: min(bottom, top),
                      width: abs(right - left), height: abs(top - bottom))
    }
    private func clampInside(_ r: NSRect) -> NSRect {
        var o = r
        if o.minX < 0 { o.origin.x = 0 }
        if o.minY < 0 { o.origin.y = 0 }
        if o.maxX > bounds.width { o.origin.x = bounds.width - o.width }
        if o.maxY > bounds.height { o.origin.y = bounds.height - o.height }
        return o
    }
    private func clampSize(_ r0: NSRect) -> NSRect {
        var r = r0
        if r.width < 0 { r.origin.x += r.width; r.size.width = -r.width }
        if r.height < 0 { r.origin.y += r.height; r.size.height = -r.height }
        r.size.width = max(minSize, min(bounds.width, r.width))
        r.size.height = max(minSize, min(bounds.height, r.height))
        return clampInside(r)
    }

    // MARK: - 文字
    private func beginText(at p: NSPoint) {
        guard textEditor == nil else { return }
        let fs = textFontSize
        let editor = NSTextField(frame: NSRect(x: p.x, y: p.y - fs * 1.4, width: max(160, fs * 12), height: fs * 1.4))
        editor.isBordered = false; editor.drawsBackground = false; editor.focusRingType = .none
        editor.font = NSFont.systemFont(ofSize: fs); editor.textColor = currentColor
        editor.delegate = self
        addSubview(editor); textEditor = editor
        window?.makeFirstResponder(editor)
    }
    func controlTextDidEndEditing(_ obj: Notification) { commitTextEditorIfNeeded() }
    private func commitTextEditorIfNeeded() {
        guard let editor = textEditor else { return }
        let str = editor.stringValue
        let origin = NSPoint(x: editor.frame.minX, y: editor.frame.maxY)
        editor.removeFromSuperview(); textEditor = nil
        if !str.isEmpty {
            items.append(AnnotationItem(kind: .text, color: currentColor, lineWidth: lineWidth,
                                        rect: NSRect(origin: origin, size: .zero),
                                        text: str, fontSize: textFontSize))
        }
        window?.makeFirstResponder(self); needsDisplay = true
    }

    // MARK: - 工具
    func undo() {
        if let last = items.popLast() {
            if last.kind == .number { nextNumber = last.number }   // 撤销序号后，下一次点击复用该号
        }
        needsDisplay = true
    }

    // MARK: - 绘制
    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.interpolationQuality = .high
        ctx.draw(baseImage, in: bounds)

        // 框外暗化
        let sel = selection
        NSColor.black.withAlphaComponent(0.45).setFill()
        [NSRect(x: 0, y: 0, width: bounds.width, height: sel.minY),
         NSRect(x: 0, y: sel.maxY, width: bounds.width, height: bounds.height - sel.maxY),
         NSRect(x: 0, y: sel.minY, width: sel.minX, height: sel.height),
         NSRect(x: sel.maxX, y: sel.minY, width: bounds.width - sel.maxX, height: sel.height)]
            .forEach { $0.fill() }

        // 框内裁切后绘制标注
        ctx.saveGState()
        NSBezierPath(rect: sel).addClip()
        for item in items { item.draw(in: ctx, scale: 1) }
        draft?.draw(in: ctx, scale: 1)
        ctx.restoreGState()

        // 蓝色选取框 + 手柄
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: sel); border.lineWidth = 2; border.stroke()
        for (_, pt) in handlePoints() {
            let hr = handleRect(pt)
            NSColor.white.setFill(); NSBezierPath(rect: hr).fill()
            NSColor.systemBlue.setStroke()
            let hp = NSBezierPath(rect: hr.insetBy(dx: 1, dy: 1)); hp.lineWidth = 1.5; hp.stroke()
        }

        drawSizeLabel(sel)
    }

    private func drawSizeLabel(_ sel: NSRect) {
        let px = Int(sel.width * scaleX), py = Int(sel.height * scaleY)
        let text = "\(px) × \(py)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        var box = NSRect(x: sel.minX, y: sel.maxY + 6, width: size.width + 12, height: size.height + 6)
        if box.maxY > bounds.maxY { box.origin.y = sel.maxY - 6 - box.height }
        if box.maxX > bounds.maxX { box.origin.x = bounds.maxX - box.width }
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
    }

    // MARK: - 合成输出（按选取框裁剪）
    func renderFinal() -> CGImage? {
        let px = pixelRect(of: selection)
        guard px.width >= 1, px.height >= 1,
              let crop = baseImage.cropping(to: px),
              let ctx = CGContext(data: nil, width: Int(px.width), height: Int(px.height),
                                  bitsPerComponent: 8, bytesPerRow: Int(px.width) * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: px.width, height: px.height))
        let scale = px.width / selection.width
        ctx.saveGState()
        ctx.translateBy(x: -selection.minX * scale, y: -selection.minY * scale)
        for item in items { item.draw(in: ctx, scale: scale) }
        ctx.restoreGState()
        return ctx.makeImage()
    }

    private func pixelRect(of sel: NSRect) -> CGRect {
        CGRect(x: (sel.minX * scaleX).rounded(),
               y: ((bounds.height - sel.maxY) * scaleY).rounded(),
               width: (sel.width * scaleX).rounded(),
               height: (sel.height * scaleY).rounded())
    }

    // MARK: - 马赛克
    private func buildMosaic(_ rect: NSRect) -> CGImage? {
        let px = pixelRect(of: rect.intersection(selection))
        guard px.width >= 2, px.height >= 2, let crop = baseImage.cropping(to: px) else { return nil }
        let blockPx = 12 * scaleX
        let w = max(1, Int(px.width / blockPx)), h = max(1, Int(px.height / blockPx))
        guard let small = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        small.interpolationQuality = .low
        small.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        return small.makeImage()
    }

    private func normalizeRect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
