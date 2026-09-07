import AppKit

/// 选区尺寸标签的公共绘制（SelectionView / AnnotationCanvas 共用），保证两处视觉一致。
enum SizeLabelPainter {
    static func draw(for rect: NSRect, px: Int, py: Int, in bounds: NSRect) {
        let text = "\(px) × \(py)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        var box = NSRect(x: rect.minX, y: rect.maxY + 6, width: size.width + 12, height: size.height + 6)
        if box.maxY > bounds.maxY { box.origin.y = rect.maxY - 6 - box.height }
        if box.maxX > bounds.maxX { box.origin.x = bounds.maxX - box.width }
        if box.minX < 0 { box.origin.x = 0 }
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
    }
}