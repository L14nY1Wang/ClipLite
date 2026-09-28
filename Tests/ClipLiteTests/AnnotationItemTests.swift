import AppKit
import XCTest
@testable import ClipLite

/// 标注元素的命中几何：箭头尖端必须落在 boundingBox 内，
/// 否则「选择工具」点不到箭头（命中区与绘制共用同一套线宽公式）。
final class AnnotationItemTests: XCTestCase {
    func testArrowHeadInsideBoundingBox() {
        let item = AnnotationItem(kind: .arrow, color: .red, lineWidth: 3,
                                  rect: .zero,
                                  points: [NSPoint(x: 100, y: 100), NSPoint(x: 200, y: 100)])
        let headLength: CGFloat = 12 + 3 * 2          // 与 draw() 中 scale=1 的 hl 一致
        let tip = NSPoint(x: 200 - headLength * 0.9,
                          y: 100 + headLength * CGFloat(sin(.pi * 0.15)))
        XCTAssertTrue(item.boundingBox.contains(tip),
                      "箭头尖端 \(tip) 落在命中区 \(item.boundingBox) 之外")
    }

    /// 数字序号标记的外接框必须以圆心为中心、半径 badgeRadius。
    func testNumberBadgeBoundingBox() {
        let item = AnnotationItem(kind: .number, color: .red, lineWidth: 3,
                                  rect: NSRect(origin: NSPoint(x: 50, y: 60), size: .zero),
                                  number: 1, badgeRadius: 15)
        XCTAssertEqual(item.boundingBox, NSRect(x: 35, y: 45, width: 30, height: 30))
    }
}