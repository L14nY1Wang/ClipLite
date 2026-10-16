import XCTest
@testable import ClipLite

/// OCR 文字叠加层几何：归一化坐标映射、marquee 划选、命中测试、阅读顺序、复制拼接。
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
