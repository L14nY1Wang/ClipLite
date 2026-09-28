import XCTest
@testable import ClipLite

/// 贴图右下角手柄的等比缩放几何。
/// 回归的是「拖右下角手柄却让顶边朝反方向飞走」——旧实现只改 size、钉死 minY。
final class PinViewResizeTests: XCTestCase {
    private let start = NSRect(x: 100, y: 200, width: 400, height: 300)   // minY=200, maxY=500
    private let aspect: CGFloat = 400.0 / 300.0

    /// 向右下拖动（宽度主导）：左上角必须不动，只有底边随尺寸下移。
    func testAnchorsTopLeftWhenWidthDominated() {
        let out = PinView.resizedFrame(from: start, to: NSPoint(x: 900, y: 150))
        XCTAssertEqual(out.minX, start.minX, "左边不该动")
        XCTAssertEqual(out.maxY, start.maxY, "顶边不该动——应该只有底边动")
        XCTAssertLessThan(out.minY, start.minY)
        XCTAssertEqual(out.maxX, 900, "右边界应跟住光标")
        XCTAssertEqual(out.width / out.height, aspect, accuracy: 1e-9)
    }

    /// 高度主导分支：底边精确落在光标上，锚点不动。
    func testBottomEdgeFollowsCursorWhenHeightDominated() {
        let tall = PinView.resizedFrame(from: start, to: NSPoint(x: 900, y: -300))
        XCTAssertEqual(tall.minY, -300)
        XCTAssertEqual(tall.maxY, start.maxY)
        XCTAssertEqual(tall.minX, start.minX)
        XCTAssertEqual(tall.width / tall.height, aspect, accuracy: 1e-9)
    }

    /// 往上拖过头：钳到下限，不翻转、不越过顶边。
    func testClampsWithoutFlipping() {
        let tiny = PinView.resizedFrame(from: start, to: NSPoint(x: 110, y: 900))
        XCTAssertGreaterThanOrEqual(tiny.width, 30)
        XCTAssertGreaterThan(tiny.height, 0)
        XCTAssertEqual(tiny.maxY, start.maxY, "钳制时顶边仍不动")
        XCTAssertEqual(tiny.minX, start.minX)
    }
}