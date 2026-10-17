import AppKit

/// OCR 文字数据模型（词/字粒度）。
///
/// 之前只有「行」一级（`OCRLine`），划选只能整行。用户要「逐字选择」，故把粒度下沉：
/// `OCRLine` 仍保留（作为「行」，负责阅读顺序/空结果提示/全选），内部持有一串
/// `OCRChar`（字符 + 归一化坐标框）。
///
/// 坐标约定与 Vision 一致：归一化 0~1、原点左下、y 向上，与 AppKit 视图坐标同向。
struct OCRLine {
    let text: String
    let box: CGRect
    /// 按字符切分的坐标框；可能为空（老协议/异常路径），此时退化为整行选择。
    let chars: [OCRChar]
    /// 无字符粒度数据时构造（保持向后兼容与测试便利）。
    init(text: String, box: CGRect, chars: [OCRChar] = []) {
        self.text = text
        self.box = box
        self.chars = chars
    }
}

struct OCRChar {
    let char: Character
    let box: CGRect
    /// 该字符在所属行 `text` 中的下标。空格没有坐标框、不会进 `chars`，
    /// 复制时靠它从 `text` 切片，避免「Hello World」被拼成「HelloWorld」。
    let textIndex: Int
}

extension OCRLine {
    /// 逐字拼接的文本（chars 与 text 一致时应相等；用于校验协议往返不丢字）。
    var charsText: String { String(chars.map(\.char)) }
}

/// 逐字选择的结果：命中的字符在「行内下标 → 字符下标」的集合，复制时按阅读顺序拼接。
/// 用 (line, charIndex) 二元组而不是扁平 Int，避免跨行重编号后语义模糊。
struct OCRCharSelection {
    private var picked: Set<OCRCharRef> = []

    var isEmpty: Bool { picked.isEmpty }
    var count: Int { picked.count }

    mutating func insert(_ r: OCRCharRef) { picked.insert(r) }
    mutating func remove(_ r: OCRCharRef) { picked.remove(r) }
    mutating func reset() { picked.removeAll() }

    func contains(_ r: OCRCharRef) -> Bool { picked.contains(r) }

    /// 全部字符（用于「无有效选中则复制全部」的兜底）。
    init() {}

    init(refs: some Sequence<OCRCharRef>) { picked = Set(refs) }
}

struct OCRCharRef: Hashable, Sendable {
    let line: Int
    let charIndex: Int
}

enum OCRCharQuery {
    /// 视图点命中的字符（外扩 padding 便于抓取；行内从后往前找，后画的/更近的优先）。
    static func hit(lines: [OCRLine], host: NSRect, point: NSPoint, padding: CGFloat = 2) -> OCRCharRef? {
        for (li, line) in lines.enumerated().reversed() {
            guard OCRTextOverlay.viewRect(line, in: host).insetBy(dx: -padding, dy: -padding).contains(point) else { continue }
            for (ci, ch) in line.chars.enumerated().reversed() {
                let r = OCRTextOverlay.viewRectForChar(ch, in: host).insetBy(dx: -padding, dy: -padding)
                if r.contains(point) { return OCRCharRef(line: li, charIndex: ci) }
            }
            // 命中行但没命中任何字符（空格/行尾）：落到行内最近字符，保证拖得起
            if let nearest = nearestChar(line: li, line: line, host: host, point: point) { return nearest }
        }
        return nil
    }

    /// 行内最近的字符（按水平距离；用于空格等无框字符的兜底）。
    private static func nearestChar(line li: Int, line: OCRLine, host: NSRect, point: NSPoint) -> OCRCharRef? {
        guard !line.chars.isEmpty else { return nil }
        var best: (Int, CGFloat) = (0, .greatestFiniteMagnitude)
        for (ci, ch) in line.chars.enumerated() {
            let r = OCRTextOverlay.viewRectForChar(ch, in: host)
            let d = abs(r.midX - point.x) + abs(r.midY - point.y)
            if d < best.1 { best = (ci, d) }
        }
        return OCRCharRef(line: li, charIndex: best.0)
    }

    /// marquee（拖拽矩形）相交的字符集合。
    /// 关键：水平拖拽时 marquee 高度为 0（竖直拖拽宽度为 0），`CGRect.intersects`
    /// 会因零面积交集返回 false——用户横着拖选会一个字都选不中（实测踩过）。
    /// 故把零厚度的边当成**线段**处理：与该边重叠即算相交。
    static func select(lines: [OCRLine], host: NSRect, marquee: NSRect) -> OCRCharSelection {
        let probe = NSPoint(x: marquee.midX, y: marquee.midY)
        let zeroH = marquee.height < 1
        let zeroW = marquee.width < 1
        var refs: [OCRCharRef] = []
        for (li, line) in lines.enumerated() {
            guard hit(viewRect: OCRTextOverlay.viewRect(line, in: host), marquee: marquee,
                      probe: probe, zeroH: zeroH, zeroW: zeroW) else { continue }
            for (ci, ch) in line.chars.enumerated() {
                let r = OCRTextOverlay.viewRectForChar(ch, in: host)
                if hit(viewRect: r, marquee: marquee, probe: probe, zeroH: zeroH, zeroW: zeroW) {
                    refs.append(OCRCharRef(line: li, charIndex: ci))
                }
            }
        }
        return OCRCharSelection(refs: refs)
    }

    /// 单个矩形与 marquee 的命中判定：零厚度边按线段重叠，否则按矩形相交。
    private static func hit(viewRect r: NSRect, marquee: NSRect, probe: NSPoint,
                            zeroH: Bool, zeroW: Bool) -> Bool {
        switch (zeroH, zeroW) {
        case (true, true):    return r.contains(probe)
        case (true, false):   // 水平线段：y 落在框内 + x 区间重叠
            return r.minY <= probe.y && probe.y <= r.maxY
                && r.minX < marquee.maxX && marquee.minX < r.maxX
        case (false, true):   // 竖直线段：x 落在框内 + y 区间重叠
            return r.minX <= probe.x && probe.x <= r.maxX
                && r.minY < marquee.maxY && marquee.minY < r.maxY
        case (false, false):  return r.intersects(marquee)
        }
    }


    /// 全部字符引用。
    static func all(lines: [OCRLine]) -> OCRCharSelection {
        var refs: [OCRCharRef] = []
        for (li, line) in lines.enumerated() {
            for ci in line.chars.indices { refs.append(OCRCharRef(line: li, charIndex: ci)) }
        }
        return OCRCharSelection(refs: refs)
    }
}

extension OCRCharSelection {
    /// 按阅读顺序拼接待复制文本；无选中 = 全部（同 Umi-OCR 语义）。
    /// 关键：从 `line.text` 按下标切片，而不是拼 `chars`——空格没有坐标框、
    /// 不进 `chars`，直接拼会把 "Hello World" 变成 "HelloWorld"。
    func copyText(lines: [OCRLine]) -> String {
        let picked: Set<OCRCharRef> = isEmpty ? Set(OCRCharQuery.all(lines: lines).picked) : picked
        var lastSelectedLine = -1
        for (li, line) in lines.enumerated() where hasAny(line: li, line: line, picked: picked) {
            lastSelectedLine = li
        }
        var out = ""
        for (li, line) in lines.enumerated() {
            let idx = line.chars.indices
                .filter { picked.contains(OCRCharRef(line: li, charIndex: $0)) }
                .map { line.chars[$0].textIndex }
                .sorted()
            guard !idx.isEmpty else { continue }
            let s = line.text
            let start = s.index(s.startIndex, offsetBy: idx.first!)
            let end = s.index(s.startIndex, offsetBy: idx.last! + 1)
            out += s[start..<end]
            if li != lastSelectedLine { out.append("\n") }
        }
        return out
    }

    private func hasAny(line li: Int, line: OCRLine, picked: Set<OCRCharRef>) -> Bool {
        line.chars.indices.contains { picked.contains(OCRCharRef(line: li, charIndex: $0)) }
    }

    func charCount(lines: [OCRLine]) -> Int {
        isEmpty ? lines.reduce(0) { $0 + $1.chars.count } : count
    }
}
