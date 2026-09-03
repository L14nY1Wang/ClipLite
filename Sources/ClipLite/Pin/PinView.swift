import AppKit

/// 贴图内容视图。拖主体移动、拖右下角手柄按比例缩放、双击关闭、滚轮缩放（辅助）。
/// 透明度改由右键菜单内的滑条控制（不再叠在图片上）。
final class PinView: NSView {
    let cgImage: CGImage
    let baseSize: NSSize
    var zoom: CGFloat = 1
    weak var owner: PinWindowController?

    private enum Mode { case idle, move, resize }
    private var mode: Mode = .idle
    private var grabOffset = NSPoint.zero
    private var startFrame = NSRect.zero
    private let grip: CGFloat = 18

    init(image: CGImage, baseSize: NSSize) {
        self.cgImage = image
        self.baseSize = baseSize
        super.init(frame: NSRect(origin: .zero, size: baseSize))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

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
            mode = .resize; startFrame = w.frame
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
            var f = startFrame
            let aspect = startFrame.width / max(1, startFrame.height)
            let m = NSEvent.mouseLocation
            let wantW = max(30, m.x - f.minX)
            let wantH = max(30, f.maxY - m.y)
            if wantW / aspect >= wantH {
                f.size = NSSize(width: wantW, height: wantW / aspect)
            } else {
                f.size = NSSize(width: wantH * aspect, height: wantH)
            }
            w.setFrame(f, display: true, animate: false)
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
