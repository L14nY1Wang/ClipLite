import AppKit

/// 截图覆盖层窗口：无边框、置顶于一切之上、透明、可成为键以接收键盘事件。
final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    convenience init(screen: NSScreen) {
        // contentRect 用该屏的全局 frame，窗口自然落在对应屏上
        self.init(frame: screen.frame)
    }

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        isReleasedWhenClosed = false   // 程序化窗口：生命周期由属性管理，close() 不能再释放，否则双重释放崩溃
        level = .screenSaver
        backgroundColor = .clear
        hasShadow = false
        // ponytail: isOpaque 曾试改 true 想压 backing store，A/B 实测（2026-10-16，3 屏）
        // footprint 150.1MB vs 149.8MB 无差别——backing store 由窗口服务器持有，不计本进程 footprint。
        // 见 docs/MEMORY-AUDIT.md §4.7。保持 transparent：clear 背景合成需要它。
        isOpaque = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }
}
