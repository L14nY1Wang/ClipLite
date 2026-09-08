import AppKit

enum AnnotationTool {
    case select, rect, ellipse, arrow, pen, text, mosaic, number
}

/// 标注元素。坐标存视图点坐标；draw 统一走 CGContext，scale=1 为画布实时绘制，
/// scale=像素比 用于最终合成渲染，两条路径完全一致。
struct AnnotationItem {
    let id = UUID()            // 选择/编辑状态按 id 定位，避免删除后数组索引失效
    var kind: AnnotationTool
    var color: NSColor
    var lineWidth: CGFloat
    var rect: NSRect          // rect/ellipse/mosaic 用；text 用 origin 作为基线起点
    var points: [NSPoint] = [] // arrow 首尾两点；pen 为路径
    var text: String = ""
    var fontSize: CGFloat = 18
    var number: Int = 0            // .number 序号标记：rect.origin 为圆心（点坐标）
    var badgeRadius: CGFloat = 15  // .number 圆半径（点）
    var mosaicSource: CGImage? // 预生成的低分辨率小图，放大绘制即马赛克

    /// 元素外接矩形（点坐标，含线宽外扩），用于命中测试与选中框绘制。
    var boundingBox: NSRect {
        switch kind {
        case .rect, .ellipse, .mosaic, .select:   // .select 不会作为元素 kind，仅为穷尽 switch
            return rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .arrow, .pen:
            guard let f = points.first else { return .zero }
            var r = NSRect(origin: f, size: .zero)
            for p in points { r = r.union(NSRect(origin: p, size: .zero)) }
            let pad = max(lineWidth / 2 + 4, 18)  // 余量覆盖箭头头部（默认线宽头部纵向延伸 ≈18）
            return r.insetBy(dx: -pad, dy: -pad)
        case .text:
            let sz = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)])
            return NSRect(origin: rect.origin, size: sz)
        case .number:
            return NSRect(x: rect.origin.x - badgeRadius, y: rect.origin.y - badgeRadius,
                          width: badgeRadius * 2, height: badgeRadius * 2)
        }
    }

    /// 偏移后的副本（选择工具拖动用）。
    func moved(by offset: NSPoint) -> AnnotationItem {
        var c = self
        if kind == .arrow || kind == .pen {
            c.points = points.map { NSPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        } else {
            c.rect.origin = NSPoint(x: rect.origin.x + offset.x, y: rect.origin.y + offset.y)
        }
        return c
    }

    func draw(in ctx: CGContext, scale: CGFloat) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setShouldAntialias(kind != .mosaic)

        switch kind {
        case .select: break   // 选择工具不产生元素

        case .rect:
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth * scale)
            ctx.stroke(rect.applying(CGAffineTransform(scaleX: scale, y: scale)))

        case .ellipse:
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth * scale)
            ctx.strokeEllipse(in: rect.applying(CGAffineTransform(scaleX: scale, y: scale)))

        case .arrow:
            guard let a0 = points.first, let b0 = points.last else { return }
            let a = CGPoint(x: a0.x * scale, y: a0.y * scale)
            let b = CGPoint(x: b0.x * scale, y: b0.y * scale)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth * scale)
            ctx.setLineCap(.round)
            ctx.move(to: a)
            ctx.addLine(to: b)
            let angle = atan2(b.y - a.y, b.x - a.x)
            let hl = (12 + lineWidth * 2) * scale
            let a1 = angle + .pi * 0.85
            let a2 = angle - .pi * 0.85
            ctx.move(to: b)
            ctx.addLine(to: CGPoint(x: b.x + cos(a1) * hl, y: b.y + sin(a1) * hl))
            ctx.move(to: b)
            ctx.addLine(to: CGPoint(x: b.x + cos(a2) * hl, y: b.y + sin(a2) * hl))
            ctx.strokePath()

        case .pen:
            guard points.count > 1 else { return }
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth * scale)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            var first = true
            for p in points {
                let q = CGPoint(x: p.x * scale, y: p.y * scale)
                if first { ctx.move(to: q); first = false } else { ctx.addLine(to: q) }
            }
            ctx.strokePath()

        case .text:
            guard !text.isEmpty else { return }
            let attr = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize * scale),
                .foregroundColor: color
            ])
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            attr.draw(at: NSPoint(x: rect.minX * scale, y: rect.minY * scale))
            NSGraphicsContext.restoreGraphicsState()

        case .mosaic:
            guard let src = mosaicSource else { return }
            ctx.interpolationQuality = .none
            ctx.draw(src, in: rect.applying(CGAffineTransform(scaleX: scale, y: scale)))

        case .number:
            let R: CGFloat = badgeRadius * scale            // 圆半径（点）× 缩放
            let cx = rect.origin.x * scale, cy = rect.origin.y * scale
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2))
            let str = "\(number)" as NSString
            let fsize = R * 1.25
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fsize, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let sz = str.size(withAttributes: attrs)
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            str.draw(at: NSPoint(x: cx - sz.width / 2, y: cy - sz.height / 2), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

#if !RELEASE_BUILD
extension AnnotationItem {
    /// 可运行检查：箭头头部端点必须落在 boundingBox 内（钉住 pad 与 draw 的 hl 公式一致）。
    static func selfCheck() {
        let a = AnnotationItem(kind: .arrow, color: .red, lineWidth: 3,
                               rect: .zero, points: [NSPoint(x: 100, y: 100), NSPoint(x: 200, y: 100)])
        let hl: CGFloat = 12 + 3 * 2   // 与 draw 中 scale=1 的 hl 一致；水平箭头头部纵向延伸 = hl·sin(0.15π) ≈ 8.2
        let tip = NSPoint(x: 200 - hl * 0.9, y: 100 + hl * CGFloat(sin(.pi * 0.15)))
        assert(a.boundingBox.contains(tip), "arrow head tip \(tip) outside boundingBox \(a.boundingBox)")
    }
}
#endif
