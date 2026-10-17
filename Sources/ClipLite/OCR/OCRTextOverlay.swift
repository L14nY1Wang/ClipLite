import AppKit

/// OCR 文字叠加层：识别结果直接渲染在图片原位，就地逐字划选复制，不再弹结果窗。
/// 数据模型见 `OCRCharModel.swift`（`OCRLine` / `OCRChar` / `OCRCharSelection`）。
/// 技术路线参考 Umi-OCR 的 `ImageWithText`（半透明底 + 白字叠在原位、左键拖选、
/// 右键菜单 / ⌘C 复制、无有效选中时复制全部）；几何部分为纯函数，便于单测。

enum OCRTextOverlay {
    /// 阅读顺序：先按竖直中心从上到下，同一行内从左到右（容差 1% 图高）。
    static func readingOrder(_ lines: [OCRLine]) -> [OCRLine] {
        lines.sorted { a, b in
            let ay = a.box.midY, by = b.box.midY
            if abs(ay - by) > 0.01 { return ay > by }   // 归一化坐标 y 大 = 更靠上
            return a.box.minX < b.box.minX
        }
    }

    /// 归一化 box → 宿主视图坐标矩形（宿主 = 图片在视图中所占区域）。
    static func viewRect(_ line: OCRLine, in host: NSRect) -> NSRect {
        NSRect(x: host.minX + line.box.minX * host.width,
               y: host.minY + line.box.minY * host.height,
               width: line.box.width * host.width,
               height: line.box.height * host.height)
    }

    /// 单个字符的归一化 box → 宿主视图坐标矩形。
    static func viewRectForChar(_ ch: OCRChar, in host: NSRect) -> NSRect {
        viewRect(OCRLine(text: String(ch.char), box: ch.box), in: host)
    }

    /// 命中测试：视图点落在哪个文字块内（外扩 padding 便于抓取）。
    static func hitTest(lines: [OCRLine], host: NSRect, point: NSPoint, padding: CGFloat = 2) -> Int? {
        for (i, line) in lines.enumerated() {
            if viewRect(line, in: host).insetBy(dx: -padding, dy: -padding).contains(point) { return i }
        }
        return nil
    }

    /// 拖拽 marquee 选中的文字行下标。
    /// 水平/竖直拖拽时 marquee 有一条边为 0，`CGRect.intersects` 会因零面积交集返回 false
    /// （用户横着拖选一行都选不中）；把零厚度的边当线段处理：与该边重叠即算相交。
    static func selectedIndices(lines: [OCRLine], host: NSRect, marquee: NSRect) -> Set<Int> {
        let probe = NSPoint(x: marquee.midX, y: marquee.midY)
        let zeroH = marquee.height < 1
        let zeroW = marquee.width < 1
        var out: Set<Int> = []
        for (i, line) in lines.enumerated() {
            let r = viewRect(line, in: host)
            let hit: Bool
            switch (zeroH, zeroW) {
            case (true, true):    hit = r.contains(probe)
            case (true, false):   hit = r.minY <= probe.y && probe.y <= r.maxY
                                            && r.minX < marquee.maxX && marquee.minX < r.maxX
            case (false, true):   hit = r.minX <= probe.x && probe.x <= r.maxX
                                            && r.minY < marquee.maxY && marquee.minY < r.maxY
            case (false, false):  hit = r.intersects(marquee)
            }
            if hit { out.insert(i) }
        }
        return out
    }

    /// 拼接待复制文本（按传入顺序，通常已是阅读顺序）；indices 为空 = 全选复制
    /// （同 Umi-OCR：无有效选中时「复制」复制全部，避免用户以为复制失败）。
    static func copyText(lines: [OCRLine], indices: Set<Int>) -> String {
        let sel = indices.isEmpty ? Set(lines.indices) : indices
        return lines.indices.filter { sel.contains($0) }.map { lines[$0].text }.joined(separator: "\n")
    }

    /// 选中文字总字数（用于复制反馈）。
    static func selectedCharCount(lines: [OCRLine], indices: Set<Int>) -> Int {
        let sel = indices.isEmpty ? Set(lines.indices) : indices
        return lines.indices.filter { sel.contains($0) }.reduce(0) { $0 + lines[$1].text.count }
    }

    // MARK: - 绘制
    /// 逐字绘制叠加层（选中按字符高亮）。`showText=false` 时只画选中底色、不画文字——
    /// 即「隐藏叠字、看原图」，选中区域仍以强调色标出，不影响划选与复制。
    static func drawChars(lines: [OCRLine], selected: OCRCharSelection, host: NSRect,
                          showText: Bool) {
        for (li, line) in lines.enumerated() {
            guard !line.chars.isEmpty else {
                // 无字符粒度数据：退化为整行绘制，保证老结果仍可用
                let r = viewRect(line, in: host)
                guard r.width > 0.5, r.height > 0.5, !line.text.isEmpty else { continue }
                let lineSel = selected.contains(OCRCharRef(line: li, charIndex: 0))
                (lineSel ? NSColor.controlAccentColor.withAlphaComponent(0.92)
                         : NSColor.black.withAlphaComponent(0.45)).setFill()
                NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).fill()
                if showText {
                    let font = fittedFont(line.text, box: r)
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                    let size = (line.text as NSString).size(withAttributes: attrs)
                    let baseline = r.midY - (font.ascender - font.descender) / 2
                    (line.text as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: baseline),
                                                 withAttributes: attrs)
                }
                continue
            }
            for (ci, ch) in line.chars.enumerated() {
                let r = viewRectForChar(ch, in: host)
                guard r.width > 0.5, r.height > 0.5 else { continue }
                let on = selected.contains(OCRCharRef(line: li, charIndex: ci))
                (on ? NSColor.controlAccentColor.withAlphaComponent(0.92)
                    : NSColor.black.withAlphaComponent(0.32)).setFill()
                NSBezierPath(rect: r.insetBy(dx: 0.25, dy: 0.5)).fill()
                if showText {
                    let font = fittedFont(String(ch.char), box: r)
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                    let size = (String(ch.char) as NSString).size(withAttributes: attrs)
                    let baseline = r.midY - (font.ascender - font.descender) / 2
                    (String(ch.char) as NSString).draw(
                        at: NSPoint(x: r.midX - size.width / 2, y: baseline), withAttributes: attrs)
                }
            }
        }
    }

    /// 绘制居中的占位/失败文案（空结果、识别失败），避免「点了 OCR 什么都没发生」。
    static func drawMessage(_ text: String, in host: NSRect) {
        let font = NSFont.systemFont(ofSize: 13)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: NSPoint(x: host.midX - size.width / 2, y: host.midY - size.height / 2),
            withAttributes: attrs)
    }

    /// 字号自适应：以 10pt 起测，按「框面积/文字面积」开方缩放，再按高度/宽度收敛。
    /// （Umi-OCR resetFontSize 同思路；截图里框小字密时必须缩小才不溢出。）
    private static func fittedFont(_ text: String, box: NSRect) -> NSFont {
        let measure: (CGFloat) -> NSSize = { ps in
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: ps)])
        }
        var ps: CGFloat = 10
        let s0 = measure(ps)
        if s0.width > 0, s0.height > 0 {
            ps = 10 * ((box.width * box.height) / (s0.width * s0.height)).squareRoot()
        }
        ps = min(ps, box.height / 1.15)          // 高度优先：行高通常是硬约束
        var guardCount = 0
        while measure(ps).height > box.height, guardCount < 20 { ps -= 1; guardCount += 1 }
        while measure(ps).width > box.width, guardCount < 40 { ps -= 1; guardCount += 1 }
        return NSFont.systemFont(ofSize: max(3, ps))
    }
}
