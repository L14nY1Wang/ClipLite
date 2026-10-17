import XCTest
@testable import ClipLite

/// OCR 叠加层几何：归一化坐标映射、marquee 划选、命中测试、阅读顺序、复制拼接。
/// 这些是「拖选复制」正确性的骨架——坐标原点错一次，叠加层就会整片错位。
final class OCRTextOverlayTests: XCTestCase {
    private let host = NSRect(x: 50, y: 100, width: 400, height: 200)   // 宿主（视图坐标，左下原点）
    private func line(_ text: String, _ box: CGRect) -> OCRLine { OCRLine(text: text, box: box) }

    /// 三行文字（归一化 y 大 = 靠上）：top / middle / bottom。
    private var lines: [OCRLine] {
        [line("TOP",    CGRect(x: 0.10, y: 0.60, width: 0.30, height: 0.10)),
         line("MIDDLE", CGRect(x: 0.10, y: 0.35, width: 0.50, height: 0.10)),
         line("BOTTOM", CGRect(x: 0.55, y: 0.10, width: 0.30, height: 0.10))]
    }

    /// 归一化框 → 宿主坐标：Vision 原点左下，与 AppKit 视图同向，直接缩放即可。
    func testViewRectMapping() {
        let r = OCRTextOverlay.viewRect(lines[0], in: host)   // y 0.60~0.70 → 视图 y 220~240
        XCTAssertEqual(r.minX, 50 + 0.10 * 400, accuracy: 1e-9)
        XCTAssertEqual(r.minY, 100 + 0.60 * 200, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.30 * 400, accuracy: 1e-9)
        XCTAssertEqual(r.height, 0.10 * 200, accuracy: 1e-9)
    }

    /// 单个字符的归一化框 → 宿主坐标。
    func testViewRectForCharMapping() {
        let ch = OCRChar(char: "A", box: CGRect(x: 0.25, y: 0.50, width: 0.10, height: 0.08))
        let r = OCRTextOverlay.viewRectForChar(ch, in: host)
        XCTAssertEqual(r.minX, 50 + 0.25 * 400, accuracy: 1e-9)
        XCTAssertEqual(r.minY, 100 + 0.50 * 200, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.10 * 400, accuracy: 1e-9)
    }

    /// 阅读顺序：先上后下（midY 降序），与输入顺序无关。
    func testReadingOrderSortsTopToBottom() {
        let shuffled = [lines[2], lines[0], lines[1]]
        XCTAssertEqual(OCRTextOverlay.readingOrder(shuffled).map(\.text), ["TOP", "MIDDLE", "BOTTOM"])
    }

    /// 同一行（midY 差 < 1%）内按 x 从左到右。
    func testReadingOrderSameRowLeftToRight() {
        let row = [line("RIGHT", CGRect(x: 0.60, y: 0.50, width: 0.2, height: 0.1)),
                   line("LEFT",  CGRect(x: 0.10, y: 0.50, width: 0.2, height: 0.1))]
        XCTAssertEqual(OCRTextOverlay.readingOrder(row).map(\.text), ["LEFT", "RIGHT"])
    }

    /// marquee 横扫中间两行：只选中相交的行。
    func testMarqueeSelectsIntersectedLines() {
        let m = NSRect(x: 50 + 0.05 * 400, y: 100 + 0.30 * 200, width: 400, height: 0.35 * 200)
        XCTAssertEqual(OCRTextOverlay.selectedIndices(lines: lines, host: host, marquee: m), [0, 1])
    }

    /// marquee 只覆盖 BOTTOM：单行选中。
    func testMarqueeSelectsSingleLine() {
        let m = NSRect(x: 50 + 0.55 * 400, y: 100 + 0.10 * 200, width: 0.30 * 400, height: 0.10 * 200)
        XCTAssertEqual(OCRTextOverlay.selectedIndices(lines: lines, host: host, marquee: m), [2])
    }

    /// 单击（零面积 marquee）：点包含判定，不能把仅边缘相接的邻行带进来。
    func testClickSelectsOnlyContainingLine() {
        let p = NSPoint(x: 50 + 0.15 * 400, y: 100 + 0.63 * 200)
        let m = NSRect(x: p.x, y: p.y, width: 0, height: 0)
        XCTAssertEqual(OCRTextOverlay.selectedIndices(lines: lines, host: host, marquee: m), [0])
    }

    /// 单击在行间空隙：什么都不选。
    func testClickInGapSelectsNothing() {
        let p = NSPoint(x: 50 + 0.5 * 400, y: 100 + 0.58 * 200)   // TOP 与 MIDDLE 之间
        let m = NSRect(x: p.x, y: p.y, width: 0, height: 0)
        XCTAssertEqual(OCRTextOverlay.selectedIndices(lines: lines, host: host, marquee: m), [])
    }

    /// 命中测试带 2pt 外扩，便于抓取；未命中返回 nil。
    func testHitTestWithPadding() {
        let r = OCRTextOverlay.viewRect(lines[0], in: host)
        XCTAssertEqual(OCRTextOverlay.hitTest(lines: lines, host: host, point: NSPoint(x: r.minX - 1, y: r.midY)), 0)
        XCTAssertNil(OCRTextOverlay.hitTest(lines: lines, host: host, point: NSPoint(x: r.maxX + 10, y: r.midY)))
    }

    /// 复制拼接：选中行按传入顺序 \n 连接；空集合 = 全部（Umi-OCR 语义）。
    func testCopyTextSelectedAndEmptyMeansAll() {
        XCTAssertEqual(OCRTextOverlay.copyText(lines: lines, indices: [0, 2]), "TOP\nBOTTOM")
        XCTAssertEqual(OCRTextOverlay.copyText(lines: lines, indices: []), "TOP\nMIDDLE\nBOTTOM")
        XCTAssertEqual(OCRTextOverlay.selectedCharCount(lines: lines, indices: [0, 2]), 9)
        XCTAssertEqual(OCRTextOverlay.selectedCharCount(lines: lines, indices: []), 15)
    }

    /// 子进程 JSON 协议往返：文字 + 归一化框不丢精度。
    func testJSONRoundTrip() throws {
        let data = try VisionOCR.encodeJSON(lines)
        let back = try VisionOCR.decodeJSON(data)
        XCTAssertEqual(back.map(\.text), lines.map(\.text))
        for (a, b) in zip(lines, back) {
            XCTAssertEqual(a.box.minX, b.box.minX, accuracy: 1e-12)
            XCTAssertEqual(a.box.minY, b.box.minY, accuracy: 1e-12)
            XCTAssertEqual(a.box.width, b.box.width, accuracy: 1e-12)
            XCTAssertEqual(a.box.height, b.box.height, accuracy: 1e-12)
        }
    }

    /// 空结果往返为空数组（空结果也要能过协议，宿主据此显示占位文案）。
    func testJSONRoundTripEmpty() throws {
        XCTAssertEqual(try VisionOCR.decodeJSON(try VisionOCR.encodeJSON([])).count, 0)
    }
}

// MARK: - 字符级选择（逐字划选）

/// 逐字选择是本次升级的核心：拖拽应只框住「字符框与 marquee 相交」的字符，
/// 而不是像以前那样整行点亮。坐标/顺序错一次，复制结果就会多字少字。
final class OCRCharSelectionTests: XCTestCase {
    private let host = NSRect(x: 50, y: 100, width: 400, height: 200)

    /// 构造一行 4 个等宽字符（归一化 x 0.1~0.5，每字 0.1 宽，y 0.4~0.5）。
    private var charLine: OCRLine {
        let chars: [OCRChar] = ["A", "B", "C", "D"].enumerated().map { i, c in
            OCRChar(char: c, box: CGRect(x: 0.10 + 0.10 * Double(i), y: 0.40, width: 0.10, height: 0.10))
        }
        return OCRLine(text: "ABCD", box: CGRect(x: 0.10, y: 0.40, width: 0.40, height: 0.10), chars: chars)
    }

    /// 拖选框住前两个字符：只选中 A、B（不是整行 ABCD）。
    func testMarqueeSelectsOnlyCoveredChars() {
        let line = charLine
        // A: 视图 x 90~130；B: 130~170。marquee 覆盖 x 88~165（含 A 全部 + B 全部）
        let m = NSRect(x: 88, y: 100 + 0.40 * 200, width: 77, height: 0.10 * 200)
        let sel = OCRCharQuery.select(lines: [line], host: host, marquee: m)
        XCTAssertFalse(sel.isEmpty)
        XCTAssertEqual(sel.copyText(lines: [line]), "AB")
    }

    /// 拖拽只框住右半边：选中 C、D（不吞 A、B）。
    func testMarqueeSelectsRightHalfOnly() {
        let line = charLine
        // C: 视图 x 170~210；D: 210~250
        let m = NSRect(x: 172, y: 100 + 0.40 * 200, width: 90, height: 0.10 * 200)
        let sel = OCRCharQuery.select(lines: [line], host: host, marquee: m)
        XCTAssertEqual(sel.copyText(lines: [line]), "CD")
    }

    /// 跨行拖选：两行各选一部分，复制结果按行序 \n 连接且不粘行。
    func testMarqueeAcrossLinesJoinsWithNewline() {
        let upper = charLine
        let lower = OCRLine(text: "EFGH", box: CGRect(x: 0.10, y: 0.10, width: 0.40, height: 0.10),
                            chars: ["E", "F", "G", "H"].enumerated().map { i, c in
                                OCRChar(char: c, box: CGRect(x: 0.10 + 0.10 * Double(i), y: 0.10, width: 0.10, height: 0.10))
                            })
        // marquee 视图范围 x 88~208（宽 120）、y 120~200：覆盖上行的 A,B,C 与下行的 E,F,G
        let m = NSRect(x: 88, y: 100 + 0.10 * 200, width: 120, height: 0.40 * 200)
        let sel = OCRCharQuery.select(lines: [upper, lower], host: host, marquee: m)
        XCTAssertEqual(sel.copyText(lines: [upper, lower]), "ABC\nEFG")
    }

    /// 水平拖拽（marquee 高度 0）：`CGRect.intersects` 会因零面积交集返回 false，
    /// 必须退化为点包含，否则用户横着拖选不中任何字符。这是实测暴露的真 bug。
    func testHorizontalDragSelectsChars() {
        let line = charLine   // 字符 y 0.40~0.50 → 视图 y 180~200
        // 横拖 x 88~208（覆盖 A,B,C），高度 0
        let m = NSRect(x: 88, y: 190, width: 120, height: 0)
        let sel = OCRCharQuery.select(lines: [line], host: host, marquee: m)
        XCTAssertEqual(sel.copyText(lines: [line]), "ABC")
    }

    /// 竖直拖拽（marquee 宽度 0）：同理必须能选中；与行仅边缘相接的不算命中。
    func testVerticalDragSelectsLines() {
        let lines: [OCRLine] = [
            OCRLine(text: "TOP", box: CGRect(x: 0.10, y: 0.60, width: 0.30, height: 0.10)),
            OCRLine(text: "MID", box: CGRect(x: 0.10, y: 0.35, width: 0.30, height: 0.10)),
            OCRLine(text: "BOT", box: CGRect(x: 0.10, y: 0.10, width: 0.30, height: 0.10)),
        ]
        // 竖拖 x 130（在三行 x 范围内），y 120~190：覆盖 MID(170-190) 与 BOT(120-140)；
        // TOP(220-240) 只是上边缘与 marquee 上边相接，不算命中。
        let m = NSRect(x: 130, y: 120, width: 0, height: 70)
        XCTAssertEqual(OCRTextOverlay.selectedIndices(lines: lines, host: host, marquee: m), [2, 1])
    }

    /// 无选中时复制全部（Umi-OCR 语义，避免「点了没反应」）。
    func testEmptySelectionCopiesAll() {
        let line = charLine
        let sel = OCRCharSelection()
        XCTAssertTrue(sel.isEmpty)
        XCTAssertEqual(sel.copyText(lines: [line]), "ABCD")
        XCTAssertEqual(sel.charCount(lines: [line]), 4)
    }

    /// 命中测试：点中哪个字符就选中哪个字符（逐字）。
    func testHitTestReturnsSingleChar() {
        let line = charLine
        // C 的视图中心：x 190, y 100 + 0.45*200 = 190
        let p = NSPoint(x: 190, y: 190)
        let ref = OCRCharQuery.hit(lines: [line], host: host, point: p)
        XCTAssertEqual(ref?.line, 0)
        XCTAssertEqual(ref?.charIndex, 2)
    }

    /// 命中测试：点在行内但不在任何字符框内（如词间空格），回退到最近字符，保证拖得起。
    func testHitTestFallsBackToNearestChar() {
        let chars: [OCRChar] = [
            OCRChar(char: "A", box: CGRect(x: 0.10, y: 0.40, width: 0.10, height: 0.10)),
            OCRChar(char: "B", box: CGRect(x: 0.30, y: 0.40, width: 0.10, height: 0.10)),
        ]
        let line = OCRLine(text: "AB", box: CGRect(x: 0.10, y: 0.40, width: 0.30, height: 0.10), chars: chars)
        // 两点之间（归一化 x 0.20 → 视图 x 130）没有字符框
        let ref = OCRCharQuery.hit(lines: [line], host: host, point: NSPoint(x: 130, y: 190))
        XCTAssertNotNil(ref, "行内空格处必须能命中（回退最近字符），否则用户拖不动")
    }

    /// 字符数据与 text 一致：协议往返不丢字（中文/英文混排场景）。
    func testCharsTextMatchesLineText() throws {
        let chars: [OCRChar] = [
            OCRChar(char: "中", box: CGRect(x: 0.10, y: 0.40, width: 0.10, height: 0.10)),
            OCRChar(char: "文", box: CGRect(x: 0.20, y: 0.40, width: 0.10, height: 0.10)),
            OCRChar(char: "A", box: CGRect(x: 0.30, y: 0.40, width: 0.05, height: 0.10)),
        ]
        let line = OCRLine(text: "中文A", box: CGRect(x: 0.10, y: 0.40, width: 0.25, height: 0.10), chars: chars)
        XCTAssertEqual(line.charsText, line.text)
        let back = try VisionOCR.decodeJSON(try VisionOCR.encodeJSON([line]))
        XCTAssertEqual(back.first?.charsText, "中文A")
        XCTAssertEqual(back.first?.chars.count, 3)
    }

    /// 无字符粒度的行（老协议/异常）：退化为行级选择，不应崩溃或复制空串。
    func testDegenerateLineWithoutCharsFallsBackToLineSelection() {
        let plain = OCRLine(text: "PLAIN", box: CGRect(x: 0.10, y: 0.40, width: 0.30, height: 0.10))
        XCTAssertEqual(OCRTextOverlay.copyText(lines: [plain], indices: []), "PLAIN")
    }
}
