import AppKit

/// 贴图内容视图。自己处理移动 / 缩放 / 透明度，避免非激活无边框面板收不到滚轮的问题。
/// - 拖主体 = 移动窗口；拖右下角手柄 = 缩放；双击 = 关闭；滚轮 = 缩放（辅助）
/// - 鼠标悬停顶部出现「透明度」拖动条。
final class PinView: NSView {
    let cgImage: CGImage
    let baseSize: NSSize
    var zoom: CGFloat = 1
    weak var owner: PinWindowController?

    private enum Mode { case idle, move, resize }
    private var mode: Mode = .idle
    private var grabOffset = NSPoint.zero        // 移动：窗口原点相对鼠标的偏移
    private var startFrame = NSRect.zero
    private let grip: CGFloat = 18

    private let opacitySlider = NSSlider()
    private var sliderVisible = false

    init(image: CGImage, baseSize: NSSize) {
        self.cgImage = image
        self.baseSize = baseSize
        super.init(frame: NSRect(origin: .zero, size: baseSize))

        opacitySlider.sliderType = .linear
        opacitySlider.minValue = 0.2
        opacitySlider.maxValue = 1.0
        opacitySlider.doubleValue = 1.0
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.isContinuous = true
        opacitySlider.controlSize = .mini
        opacitySlider.isHidden = true
        addSubview(opacitySlider)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    // 关闭系统背景拖动，改由本视图处理移动
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { setSlider(true) }
    override func mouseExited(with event: NSEvent)  { setSlider(false) }

    private func setSlider(_ visible: Bool) {
        guard visible != sliderVisible else { return }
        sliderVisible = visible
        layoutSlider()
        opacitySlider.isHidden = !visible
    }
    private func layoutSlider() {
        let w = min(bounds.width - 12, 130)
        opacitySlider.frame = NSRect(x: 6, y: bounds.maxY - 22, width: w, height: 18)
    }
    @objc private func opacityChanged(_ s: NSSlider) { window?.alphaValue = CGFloat(s.doubleValue) }

    // MARK: - 绘制
    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.interpolationQuality = .high
        ctx?.draw(cgImage, in: bounds)
        ctx?.restoreGState()

        // 右下角缩放手柄（三条斜线）
        let g = grip
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.5
        for i in stride(from: 4, through: g - 2, by: 5) {
            path.move(to: NSPoint(x: bounds.maxX - g + i, y: bounds.minY + 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + g - i))
        }
        path.stroke()
    }

    private func gripRect() -> NSRect {
        NSRect(x: bounds.maxX - grip, y: bounds.minY, width: grip, height: grip)
    }

    // MARK: - 鼠标
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { window?.close(); return }
        let p = convert(event.locationInWindow, from: nil)
        guard let w = window else { return }
        if gripRect().insetBy(dx: -6, dy: -6).contains(p) {
            mode = .resize
            startFrame = w.frame
        } else {
            mode = .move
            grabOffset = NSPoint(x: w.frame.origin.x - NSEvent.mouseLocation.x,
                                 y: w.frame.origin.y - NSEvent.mouseLocation.y)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        switch mode {
        case .move:
            let loc = NSEvent.mouseLocation
            w.setFrameOrigin(NSPoint(x: loc.x + grabOffset.x, y: loc.y + grabOffset.y))
        case .resize:
            // 拖右下角手柄：固定左上角，改变宽高（非翻转，y 向上）
            var f = startFrame
            let mouseGlobal = NSEvent.mouseLocation
            let width = max(30, mouseGlobal.x - f.minX)
            let height = max(30, f.maxY - mouseGlobal.y)
            f.size = NSSize(width: width, height: height)
            w.setFrame(f, display: true, animate: false)
            layoutSlider()
            needsDisplay = true
        case .idle: break
        }
    }

    override func mouseUp(with event: NSEvent) { mode = .idle }

    override func rightMouseDown(with event: NSEvent) { owner?.showMenu(event: event) }

    override func scrollWheel(with event: NSEvent) {
        guard let w = window else { return }
        let factor: CGFloat = event.deltaY > 0 ? 1.1 : (event.deltaY < 0 ? 1 / 1.1 : 1)
        let newZoom = min(16, max(0.1, zoom * factor))
        if newZoom == zoom { return }
        zoom = newZoom
        let newSize = NSSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
        let cursor = NSEvent.mouseLocation
        var f = w.frame
        let fx = (cursor.x - f.minX) / f.width
        let fy = (cursor.y - f.minY) / f.height
        f.size = newSize
        f.origin.x = cursor.x - fx * newSize.width
        f.origin.y = cursor.y - fy * newSize.height
        w.setFrame(f, display: true, animate: false)
        needsDisplay = true
    }
}
