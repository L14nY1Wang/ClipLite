import AppKit
import CoreGraphics

/// 截图会话控制器：发起截屏 → 每屏建一个覆盖层窗口 → 等待用户框选 → 裁剪并回调。
final class SelectionController {
    weak var coordinator: AppCoordinator?
    private var windows: [SelectionWindow] = []
    /// 自己记录的 push/pop 配对。原来用 `NSCursor.current == .crosshair` 判断该不该 pop，
    /// 但那是**对象比较**：关闭瞬间若当前光标已被他处改过（如漏到屏外时底层应用的 I 型），
    /// pop 被跳过 → crosshair 永久留在全局光标栈，之后别的 push/pop 会把它翻成系统光标。
    private var cursorPushed = false

    func start() {
        guard ScreenCapture.preflight() || ScreenCapture.request() else {
            showFailure("需要屏幕录制权限", detail: "请在系统设置的「录屏与系统录音」中允许本应用。授权后将自动重试截图。若升级后仍无法截图，请按 README 的升级恢复步骤重置本应用权限。", isPermissionIssue: true)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let displays = try await ScreenCapture.captureAll()
                let windowList = Self.snapshotWindowList()
                await MainActor.run {
                    self.present(displays: displays, windowList: windowList)
                }
            } catch {
                NSLog("SelectionController: capture failed \(error)")
                await MainActor.run {
                    self.showFailure("截图失败", detail: "\(error.localizedDescription)\n\n请检查屏幕录制权限后重试。")
                }
            }
        }
    }

    /// - Parameter isPermissionIssue: 仅 preflight 授权失败时为 true，才挂授权自动重试；capture 报错时权限通常已正常，重试大概率命中同一错误。
    private func showFailure(_ title: String, detail: String, isPermissionIssue: Bool = false) {
        // 弹窗期间保留会话，避免热键重复创建弹窗；关闭后释放，允许重试。
        defer { coordinator?.didCancelSelection() }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "打开录屏设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            coordinator?.openScreenCapturePrefs()
            if isPermissionIssue {
                // 用户在系统设置完成授权后当场重试截图（defer 的 didCancelSelection 已先复位 selection）
                coordinator?.startPermissionRetry()
            }
        }
    }

    private func present(displays: [ScreenCapture.Display], windowList: [NSRect]) {
        guard !displays.isEmpty else {
            showFailure("截图失败", detail: "没有找到可截图的显示器。请检查屏幕录制权限和显示器连接后重试。")
            return
        }
        NSCursor.crosshair.push()
        cursorPushed = true
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
        // accessory 应用不会因弹窗而自动成为前台：⌥1 从别的应用触发时，本进程不是活跃应用，
        // Esc/回车会发给此前的前台应用（A/B 实测：无此行 overlay 在屏但按键全被 Safari 吃掉，
        // 149.7MB 不回落；有此行 Esc 正常关闭，回落到 18.5MB）。showFailure 一直有这句，主路径漏了。
        NSApp.activate(ignoringOtherApps: true)
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
        // 弹出 crosshair 时压栈，关闭时弹栈恢复（按自有标志，见 cursorPushed 注释）
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
    }

    // MARK: - 窗口列表快照（用于窗口吸附点击）
    static func snapshotWindowList() -> [NSRect] {
        guard let arr = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPID = getpid()
        // kCGWindowBounds 是 CG 全局「点」：翻转锚点必须用主屏点高度（PixelsHigh 在 HiDPI 下返回物理像素，会把矩形翻出屏幕）
        let mainH = CGDisplayBounds(CGMainDisplayID()).height
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
