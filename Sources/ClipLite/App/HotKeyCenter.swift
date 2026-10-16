import AppKit
import Carbon.HIToolbox

/// 全局热键中心。基于 Carbon RegisterEventHotKey，注册时无需辅助功能权限。
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    /// 两个功能热键的固定 id（register/unregister 成对使用，勿改：会使用户保存的热键失效）。
    static let screenshotID: UInt32 = 1
    static let pinID: UInt32 = 2

    /// 把 NSEvent 修饰键转成 Carbon RegisterEventHotKey 需要的掩码。
    static func carbonFlags(from f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option)  { m |= UInt32(optionKey) }
        if f.contains(.shift)   { m |= UInt32(shiftKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x534E504C // "SNPL"（ClipLite 产品名缩写，任意自定义值均可）

    /// - Returns: 注册是否成功。失败通常意味着该组合已被系统或其它 App 占用。
    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        // 事件处理器没装上，热键注册了也收不到——必须如实报失败，
        // 否则上层判成功、不弹提示，用户面对一个永久按不响的快捷键。
        guard installIfNeeded() else { return false }
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode,
                                         modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr, let ref = ref {
            refs[id] = ref
            handlers[id] = handler
            return true
        }
        NSLog("HotKeyCenter: register failed id=\(id) status=\(status)")
        return false
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: id)
    }

    // MARK: - Carbon 事件处理
    /// - Returns: 事件处理器是否就绪（已装或本次装成功）。
    @discardableResult
    private func installIfNeeded() -> Bool {
        guard eventHandlerRef == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef = eventRef, let userData = userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotKeyID)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            DispatchQueue.main.async { center.handlers[id]?() }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         callback,
                                         1,
                                         &spec,
                                         Unmanaged.passUnretained(self).toOpaque(),
                                         &eventHandlerRef)
        if status != noErr {
            NSLog("HotKeyCenter: InstallEventHandler failed status=\(status)")
            return false
        }
        return true
    }
}
