import AppKit

/// 单屏选区视图。坐标用 AppKit 全局空间（左下原点，与 NSScreen/NSEvent.mouseLocation 一致）；
/// 视图覆盖所在屏，视图坐标 = 全局 - screenFrame.origin。
final class SelectionView: NSView {
    let display: ScreenCapture.Display
    let windowRects: [NSRect]   // AppKit 全局，已过滤到本屏
    weak var controller: SelectionController?

    private let screenFrame: NSRect
    private let image: CGImage
    private let imageRep: NSImage          // NSImage 包装，绘制时自动正向
    private let scaleX: CGFloat
    private let scaleY: CGFloat

    private var anchorGlobal: NSPoint?
    private var selectionGlobal: NSRect?
    private var isDragging = false
    private var mouseGlobal: NSPoint = .zero
    private var snappedRect: NSRect?       // 悬停时命中的窗口矩形（全局）

    init(display: ScreenCapture.Display, windowRects: [NSRect], controller: SelectionController) {
        self.display = display
        self.windowRects = windowRects
        self.controller = controller
        self.screenFrame = display.screen.frame
        self.image = display.image
        self.imageRep = NSImage(cgImage: display.image,
                                size: NSSize(width: display.screen.frame.width,
                                            height: display.screen.frame.height))
        self.scaleX = CGFloat(display.image.width) / display.screen.frame.width
        self.scaleY = CGFloat(display.image.height) / display.screen.frame.height
        super.init(frame: NSRect(origin: .zero, size: display.screen.frame.size))
        wantsLayer = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // MARK: - 鼠标
    override func mouseDown(with event: NSEvent) {
        mouseGlobal = NSEvent.mouseLocation
        anchorGlobal = mouseGlobal
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        mouseGlobal = NSEvent.mouseLocation
        isDragging = true
        if let a = anchorGlobal {
            selectionGlobal = normalizeRect(a, mouseGlobal)
            snappedRect = nil
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseGlobal = NSEvent.mouseLocation
        // 有拖拽 → 用选区；无拖拽 → 用命中的窗口（窗口吸附）
        if isDragging, let sel = selectionGlobal, sel.width > 4, sel.height > 4 {
            confirm(rect: sel)
            return
        }
        if let snap = snappedRect {
            confirm(rect: snap)
            return
        }
        // 空白处单击：不操作，保持选区界面
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouseGlobal = NSEvent.mouseLocation
        if !isDragging {
            snappedRect = windowRects
                .filter { $0.contains(mouseGlobal) }
                .min(by: { $0.width * $0.height < $1.width * $1.height })
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // ESC
            controller?.cancel()
        case 36, 76: // Return / KeypadEnter
            if let sel = selectionGlobal, sel.width > 4, sel.height > 4 {
                confirm(rect: sel)
            } else if let snap = snappedRect {
                confirm(rect: snap)
            } else {
                // 无选区：确认整屏
                confirm(rect: screenFrame)
            }
        default:
            super.keyDown(with: event)
        }
    }

    private func confirm(rect: NSRect) {
        // 限定到本屏，避免跨屏裁剪越界
        let clamped = rect.intersection(screenFrame)
        guard !clamped.isNull, clamped.width > 1, clamped.height > 1 else {
            controller?.cancel()
            return
        }
        controller?.confirm(view: self, rect: clamped)
    }

    // MARK: - 绘制
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.saveGState()
        defer { NSGraphicsContext.current?.cgContext.restoreGState() }

        // 1. 背景截图
        imageRep.draw(in: bounds)

        let selView = selectionGlobal.map { $0.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY) }

        // 2. 选区外暗化
        if let s = selView {
            let dim = NSColor.black.withAlphaComponent(0.35)
            dim.setFill()
            let rects = [
                NSRect(x: 0, y: 0, width: bounds.width, height: max(0, s.minY)),
                NSRect(x: 0, y: s.maxY, width: bounds.width, height: max(0, bounds.height - s.maxY)),
                NSRect(x: 0, y: s.minY, width: max(0, s.minX), height: s.height),
                NSRect(x: s.maxX, y: s.minY, width: max(0, bounds.width - s.maxX), height: s.height)
            ]
            for r in rects { r.fill() }
        } else {
            NSColor.black.withAlphaComponent(0.35).setFill()
            bounds.fill()
        }

        // 3. 窗口吸附高亮（橙）
        if !isDragging, let snap = snappedRect {
            let sv = snap.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            NSColor.systemOrange.withAlphaComponent(0.9).setStroke()
            let p = NSBezierPath(rect: sv)
            p.lineWidth = 2
            p.stroke()
        }

        // 4. 选区边框
        if let s = selView {
            NSColor.white.setStroke()
            let p = NSBezierPath(rect: s)
            p.lineWidth = 1.5
            p.stroke()
        }

        // 5. 尺寸标签 + 放大镜
        if let s = selView {
            drawSizeLabel(s)
        }
        // 仅在光标落在本屏范围内时绘制放大镜，避免初始 .zero 采样越界
        if screenFrame.contains(mouseGlobal) {
            drawMagnifier()
        }
    }

    private func drawSizeLabel(_ selView: NSRect) {
        let px = Int(selView.width * scaleX)
        let py = Int(selView.height * scaleY)
        let text = "\(px) × \(py)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        var box = NSRect(x: selView.minX, y: selView.maxY + 6,
                         width: size.width + 12, height: size.height + 6)
        if box.maxY > bounds.maxY { box.origin.y = selView.maxY - 6 - box.height }
        if box.maxX > bounds.maxX { box.origin.x = bounds.maxX - box.width }
        if box.minX < 0 { box.origin.x = 0 }
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
    }

    private func drawMagnifier() {
        let mag = NSRect(x: 0, y: 0, width: 150, height: 110)
        var origin = NSPoint(x: mouseGlobal.x - screenFrame.minX + 16,
                             y: mouseGlobal.y - screenFrame.minY + 16)
        // 放在光标右下，必要时翻到对侧
        if origin.x + mag.width > bounds.width { origin.x = mouseGlobal.x - screenFrame.minX - 16 - mag.width }
        if origin.y + mag.height > bounds.height { origin.y = mouseGlobal.y - screenFrame.minY - 16 - mag.height }
        let box = NSRect(origin: origin, size: mag.size)

        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        NSColor.white.withAlphaComponent(0.2).setStroke()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).stroke()

        // 像素放大区
        let inset: CGFloat = 6
        let imgRect = box.insetBy(dx: inset, dy: inset + 14) // 底部留 RGB 文字
        let zoom = imgRect.width / 21
        let center = globalToPixel(mouseGlobal)
        var src = CGRect(x: center.x - 10, y: center.y - 10, width: 21, height: 21)
        src.origin.x = max(0, min(CGFloat(image.width) - 21, src.origin.x))
        src.origin.y = max(0, min(CGFloat(image.height) - 21, src.origin.y))
        if let crop = image.cropping(to: src) {
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.saveGState()
            ctx.interpolationQuality = .none
            // 视图非翻转 → cgContext y-up，draw 为正向
            ctx.draw(crop, in: imgRect)
            ctx.interpolationQuality = .default
            // 像素网格
            NSColor.white.withAlphaComponent(0.15).setStroke()
            for i in 0...21 {
                let x = imgRect.minX + CGFloat(i) * zoom
                let y = imgRect.minY + CGFloat(i) * zoom
                NSBezierPath(rect: NSRect(x: x, y: imgRect.minY, width: 0, height: imgRect.height)).stroke()
                let _ = y
            }
            // 中心十字
            NSColor.systemRed.setStroke()
            let cx = imgRect.minX + imgRect.width / 2
            let cy = imgRect.minY + imgRect.height / 2
            NSBezierPath(rect: NSRect(x: cx - 0.5, y: imgRect.minY, width: 1, height: imgRect.height)).stroke()
            NSBezierPath(rect: NSRect(x: imgRect.minX, y: cy - 0.5, width: imgRect.width, height: 1)).stroke()
            ctx.restoreGState()
        }

        // RGB 文字：直接使用采样到的原始字节，绝不经过 NSColor 颜色空间转换
        let (r, g, b) = sampleRGBA(mouseGlobal)
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let text = "\(hex)  RGB(\(r),\(g),\(b))"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let ts = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: box.minX + inset,
                                           y: box.maxY - ts.height - 3), withAttributes: attrs)
    }

    // MARK: - 坐标换算
    private func globalToPixel(_ global: NSPoint) -> CGPoint {
        let local = NSPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
        let px = local.x * scaleX
        let py = (screenFrame.height - local.y) * scaleY
        return CGPoint(x: px, y: py)
    }

    /// 读取指定全局点的原始 RGBA 字节。全程不构造/不转换 NSColor，规避覆盖层上下文的颜色空间异常。
    private func sampleRGBA(_ global: NSPoint) -> (UInt8, UInt8, UInt8) {
        let p = globalToPixel(global)
        let ix = Int(p.x.rounded(.down)), iy = Int(p.y.rounded(.down))
        guard ix >= 0, iy >= 0, ix < image.width, iy < image.height,
              let crop = image.cropping(to: CGRect(x: ix, y: iy, width: 1, height: 1)) else {
            return (0, 0, 0)
        }
        var buf = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return (0, 0, 0)
        }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (buf[0], buf[1], buf[2])
    }

    private func normalizeRect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
