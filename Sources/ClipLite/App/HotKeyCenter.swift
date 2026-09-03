import AppKit
import Carbon.HIToolbox

/// 全局热键中心。基于 Carbon RegisterEventHotKey，注册时无需辅助功能权限。
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x534E504C // "CLPL"

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installIfNeeded()
        unregister(id: id)
        var ref: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode,
                                         modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr, let ref = ref {
            refs[id] = ref
            handlers[id] = handler
        } else {
            NSLog("HotKeyCenter: register failed id=\(id) status=\(status)")
        }
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: id)
    }

    // MARK: - Carbon 事件处理
    private func installIfNeeded() {
        guard eventHandlerRef == nil else { return }
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
        }
    }
}
