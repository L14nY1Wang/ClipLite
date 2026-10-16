import AppKit
import Carbon.HIToolbox
import XCTest
@testable import ClipLite

/// 热键链路的纯逻辑回归：0.2.0 修过修饰键映射与标签拼装，但一直没有测试兜底。
/// 只覆盖不依赖 GUI/权限的部分——Carbon 注册、事件回调不在测试范围内。
final class HotKeyTests: XCTestCase {

    // MARK: - carbonFlags

    /// 单个修饰键各映射到对应 Carbon 掩码；空集合映射为 0。
    func testCarbonFlagsSingleAndEmpty() {
        XCTAssertEqual(HotKeyCenter.carbonFlags(from: []), 0, "空修饰键应映射为 0")
        XCTAssertEqual(HotKeyCenter.carbonFlags(from: .command), UInt32(cmdKey))
        XCTAssertEqual(HotKeyCenter.carbonFlags(from: .option), UInt32(optionKey))
        XCTAssertEqual(HotKeyCenter.carbonFlags(from: .shift), UInt32(shiftKey))
        // Carbon 里 control 不是 command 的一部分，必须单独携带
        XCTAssertEqual(HotKeyCenter.carbonFlags(from: .control), UInt32(controlKey))
    }

    /// 多修饰键组合必须按位全部保留（漏掉任一掩码都会让注册的热键失效或冲突）。
    func testCarbonFlagsCombinations() {
        XCTAssertEqual(HotKeyCenter.carbonFlags(from: [.command, .option]),
                       UInt32(cmdKey) | UInt32(optionKey))
        XCTAssertEqual(HotKeyCenter.carbonFlags(from: [.command, .option, .shift, .control]),
                       UInt32(cmdKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(controlKey))
    }

    // MARK: - HotKeyFormatter.label

    /// 修饰键按 ⌃⇧⌥⌘ 固定顺序拼装，后接键名；顺序错则菜单与设置界面的提示会和用户预期不符。
    func testLabelModifierOrder() {
        let all = HotKey(keyCode: UInt32(kVK_ANSI_A),
                         modifiers: UInt32(controlKey) | UInt32(shiftKey)
                            | UInt32(optionKey) | UInt32(cmdKey))
        XCTAssertEqual(HotKeyFormatter.label(all), "⌃⇧⌥⌘A")

        XCTAssertEqual(HotKeyFormatter.label(HotKey(keyCode: UInt32(kVK_ANSI_1),
                                                    modifiers: UInt32(optionKey))), "⌥1")
        XCTAssertEqual(HotKeyFormatter.label(HotKey(keyCode: UInt32(kVK_ANSI_A),
                                                    modifiers: UInt32(controlKey) | UInt32(shiftKey))),
                       "⌃⇧A")
        // 传参顺序不影响输出
        XCTAssertEqual(HotKeyFormatter.label(HotKey(keyCode: UInt32(kVK_ANSI_A),
                                                    modifiers: UInt32(shiftKey) | UInt32(controlKey))),
                       "⌃⇧A")
    }

    /// 无修饰键时只输出键名。
    func testLabelWithoutModifiers() {
        XCTAssertEqual(HotKeyFormatter.label(HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)), "A")
    }

    // MARK: - HotKeyLabel.keyCodeToString

    /// 常见键码映射；未知键码退化为 "Key<码>"，不能崩溃或产生空串。
    func testKeyCodeToString() {
        XCTAssertEqual(HotKeyLabel.keyCodeToString(UInt32(kVK_ANSI_A)), "A")
        XCTAssertEqual(HotKeyLabel.keyCodeToString(UInt32(kVK_ANSI_0)), "0")
        XCTAssertEqual(HotKeyLabel.keyCodeToString(UInt32(kVK_Return)), "↩")
        XCTAssertEqual(HotKeyLabel.keyCodeToString(UInt32(kVK_F1)), "F1")
        XCTAssertEqual(HotKeyLabel.keyCodeToString(UInt32(kVK_F12)), "F12")
        XCTAssertEqual(HotKeyLabel.keyCodeToString(999), "Key999")
    }

    // MARK: - AppSettings 往返

    /// 热键经 UserDefaults 往返必须无损，用完恢复原值以免污染其它测试或真实配置。
    func testScreenshotHotKeyRoundTrip() {
        let settings = AppSettings.shared
        let old = settings.screenshotHotKey
        defer { settings.setScreenshot(old) }

        let hk = HotKey(keyCode: UInt32(kVK_F5),
                        modifiers: UInt32(optionKey) | UInt32(cmdKey))
        settings.setScreenshot(hk)
        XCTAssertEqual(settings.screenshotHotKey, hk, "screenshotHotKey 往返失败")

        settings.setScreenshot(old)
        XCTAssertEqual(settings.screenshotHotKey, old, "screenshotHotKey 未恢复")
    }
}
