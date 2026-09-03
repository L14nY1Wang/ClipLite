import AppKit

/// 贴图内容视图。窗口尺寸即缩放，图像填满 bounds；滚轮缩放围绕光标。
final class PinView: NSView {
    let cgImage: CGImage
    let baseSize: NSSize
    var zoom: CGFloat = 1
    weak var owner: PinWindowController?

    init(image: CGImage, baseSize: NSSize) {
        self.cgImage = image
        self.baseSize = baseSize
        super.init(frame: NSRect(origin: .zero, size: baseSize))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.interpolationQuality = .high
        ctx?.draw(cgImage, in: bounds)
        ctx?.restoreGState()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let w = window else { return }
        if event.modifierFlags.contains(.control) {
            // Ctrl + 滚轮：调透明度
            var a = w.alphaValue + CGFloat(event.deltaY) * 0.03
            a = min(1, max(0.2, a))
            w.alphaValue = a
            return
        }
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
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 2 {
            wClose()
        }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        owner?.showMenu(event: event)
    }

    private func wClose() { window?.close() }
}
