import XCTest
@testable import ClipLite

final class AppSettingsTests: XCTestCase {
    /// 记忆的保存目录经 UserDefaults 往返必须无损（含空格与 CJK 路径），且用完不残留脏值。
    func testLastSaveDirectoryRoundTrip() {
        let settings = AppSettings.shared
        let old = settings.lastSaveDirectory
        defer { settings.lastSaveDirectory = old }

        let dir = URL(fileURLWithPath: "/tmp/ClipLite 自测 目录", isDirectory: true)
        settings.lastSaveDirectory = dir
        XCTAssertEqual(settings.lastSaveDirectory?.path, dir.path, "lastSaveDirectory 往返失败")

        settings.lastSaveDirectory = old
        XCTAssertEqual(settings.lastSaveDirectory, old, "lastSaveDirectory 未恢复")
    }
}