import AppKit
import CoreGraphics

/// 截图会话控制器：发起截屏 → 每屏建一个覆盖层窗口 → 等待用户框选 → 裁剪并回调。
final class SelectionController {
    weak var coordinator: AppCoordinator?
    private var windows: [SelectionWindow] = []

    func start() {
        let ok = ScreenCapture.preflight()
        NSLog("ClipLite.trace Selection.start preflight=\(ok)")
        guard ok else {
            _ = ScreenCapture.request()
            coordinator?.didCancelSelection()
            return
        }
        Task { [weak self] in
            do {
                let displays = try await ScreenCapture.captureAll()
                NSLog("ClipLite.trace captured displays=\(displays.count) px=\(displays.first.map{ "\($0.image.width)x\($0.image.height)" } ?? "n/a")")
                let windowList = Self.snapshotWindowList()
                await MainActor.run {
                    self?.present(displays: displays, windowList: windowList)
                }
            } catch {
                NSLog("SelectionController: capture failed \(error)")
                await MainActor.run { self?.coordinator?.didCancelSelection() }
            }
        }
    }

    private func present(displays: [ScreenCapture.Display], windowList: [NSRect]) {
        guard !displays.isEmpty else {
            coordinator?.didCancelSelection()
            return
        }
        NSCursor.crosshair.push()
        var made: [SelectionWindow] = []
        for d in displays {
            let rects = windowList.filter { $0.intersects(d.screen.frame) }
            let view = SelectionView(display: d, windowRects: rects, controller: self)
            let win = SelectionWindow(screen: d.screen)
            win.contentView = view
            made.append(win)
        }
        self.windows = made
        // 先全部上屏，再把光标所在屏设为键
        for w in made { w.orderFrontRegardless() }
        let cursor = NSEvent.mouseLocation
        let keyWin = made.first { $0.frame.contains(cursor) } ?? made.first
        keyWin?.makeKeyAndOrderFront(nil)
        if let kv = keyWin, let v = kv.contentView { kv.makeFirstResponder(v) }
        NSLog("ClipLite.trace present windows=\(made.count) frames=\(made.map{ NSStringFromRect($0.frame) }.joined(separator: ","))")
    }

    // MARK: - 回调
    func confirm(view: SelectionView, rect: NSRect) {
        // 不预先裁图：把整屏截图 + 选区（该屏局部点坐标）交给标注层，标注层内可再调整蓝色选取框
        let sf = view.display.screen.frame
        let local = rect.offsetBy(dx: -sf.minX, dy: -sf.minY)
        teardown()
        coordinator?.didFinishSelection(fullImage: view.display.image,
                                        screen: view.display.screen,
                                        selectionLocal: local)
    }

    func cancel() {
        teardown()
        coordinator?.didCancelSelection()
    }

    private func teardown() {
        for w in windows {
            w.orderOut(nil)
            w.close()
        }
        windows.removeAll()
        // 弹出 crosshair 时压栈，关闭时弹栈恢复
        if NSCursor.current == NSCursor.crosshair { NSCursor.pop() }
    }

    // MARK: - 窗口列表快照（用于窗口吸附点击）
    static func snapshotWindowList() -> [NSRect] {
        guard let arr = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPID = getpid()
        let mainH = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
        var rects: [NSRect] = []
        for w in arr {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1.0) > 0.1,
                  ((w[kCGWindowOwnerPID as String] as? Int) ?? -1) != myPID else { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let wid = b["Width"] as? CGFloat, let hei = b["Height"] as? CGFloat,
                  wid > 4, hei > 4 else { continue }
            let cg = CGRect(x: x, y: y, width: wid, height: hei)
            rects.append(appkitFromCG(cg, mainHeight: mainH))
        }
        return rects
    }

    /// CG 全局（左上原点）→ AppKit 全局（左下原点）。
    private static func appkitFromCG(_ r: CGRect, mainHeight: CGFloat) -> NSRect {
        NSRect(x: r.origin.x,
               y: mainHeight - r.origin.y - r.size.height,
               width: r.size.width,
               height: r.size.height)
    }
}
