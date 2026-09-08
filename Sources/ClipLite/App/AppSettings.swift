import AppKit
import Carbon.HIToolbox
import ServiceManagement

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
}

enum HotKeyFormatter {
    static func label(_ hk: HotKey) -> String {
        var s = ""
        if hk.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if hk.modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if hk.modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if hk.modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += HotKeyLabel.keyCodeToString(hk.keyCode)
        return s
    }
}

/// 把 Carbon 键码转成人类可读字符，仅用于菜单显示。
enum HotKeyLabel {
    static func keyCodeToString(_ kc: UInt32) -> String {
        switch Int(kc) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            if kc >= UInt32(kVK_F1) && kc <= UInt32(kVK_F12) {
                return "F\(kc - UInt32(kVK_F1) + 1)"
            }
            return "Key\(kc)"
        }
    }
}

/// UserDefaults 包装。热键等可配置项集中在此。
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    // 原生整数键（keyCode / modifiers 分两个 NSNumber）；
    // 旧版存 JSON Data 于 kScreenshot/kPinClipboard，读取时兼容回退。
    private let kScreenshotKC = "screenshotHotKeyKC"
    private let kScreenshotMods = "screenshotHotKeyMods"
    private let kPinClipboardKC = "pinClipboardHotKeyKC"
    private let kPinClipboardMods = "pinClipboardHotKeyMods"
    private let kScreenshotLegacy = "screenshotHotKey"
    private let kPinClipboardLegacy = "pinClipboardHotKey"

    var screenshotHotKey: HotKey {
        decodeInts(kScreenshotKC, kScreenshotMods) ?? decodeLegacy(kScreenshotLegacy)
            ?? HotKey(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(optionKey))
    }
    var pinClipboardHotKey: HotKey {
        decodeInts(kPinClipboardKC, kPinClipboardMods) ?? decodeLegacy(kPinClipboardLegacy)
            ?? HotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(optionKey))
    }
    func setScreenshot(_ hk: HotKey) {
        encodeInts(kScreenshotKC, kScreenshotMods, hk)
        d.removeObject(forKey: kScreenshotLegacy)
    }
    func setPinClipboard(_ hk: HotKey) {
        encodeInts(kPinClipboardKC, kPinClipboardMods, hk)
        d.removeObject(forKey: kPinClipboardLegacy)
    }

    // 开机自启（SMAppService，macOS 13+）
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("AppSettings: 开机自启切换失败 \(error)")
            }
        }
    }

    // 上次保存目录（跨进程记忆；App 非沙盒，直接存 URL 字符串即可）
    private let kLastSaveDir = "lastSaveDirectory"
    var lastSaveDirectory: URL? {
        get { d.string(forKey: kLastSaveDir).flatMap(URL.init(string:)) }
        set { d.set(newValue?.absoluteString, forKey: kLastSaveDir) }
    }

    private func decodeInts(_ kcKey: String, _ modsKey: String) -> HotKey? {
        guard let kc = d.object(forKey: kcKey) as? NSNumber,
              let mods = d.object(forKey: modsKey) as? NSNumber else { return nil }
        return HotKey(keyCode: kc.uint32Value, modifiers: mods.uint32Value)
    }
    private func encodeInts(_ kcKey: String, _ modsKey: String, _ hk: HotKey) {
        d.set(hk.keyCode, forKey: kcKey)
        d.set(hk.modifiers, forKey: modsKey)
    }
    private func decodeLegacy(_ key: String) -> HotKey? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }
}

#if !RELEASE_BUILD
extension AppSettings {
    /// 可运行检查：lastSaveDirectory 经 UserDefaults 往返必须无损（含空格/CJK 路径），且不残留脏值。
    static func selfCheck() {
        let old = shared.lastSaveDirectory
        let dir = URL(fileURLWithPath: "/tmp/ClipLite 自测 目录", isDirectory: true)
        shared.lastSaveDirectory = dir
        assert(shared.lastSaveDirectory?.path == dir.path, "lastSaveDirectory 往返失败")
        shared.lastSaveDirectory = old
        assert(shared.lastSaveDirectory == old, "lastSaveDirectory 恢复失败")
    }
}
#endif
