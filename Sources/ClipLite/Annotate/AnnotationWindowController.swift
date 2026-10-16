import AppKit

/// 标注会话：选区确认后出现，覆盖整屏。画布上有可调整选取框 + 标注；工具条悬浮在框下方。
final class AnnotationWindowController: NSObject, NSWindowDelegate {
    let window: SelectionWindow
    let canvas: AnnotationCanvas
    let toolbar: AnnotationToolbar
    let sizeBar: AnnotationSizeBar
    let screen: NSScreen
    weak var coordinator: AppCoordinator?

    init(fullImage: CGImage, screen: NSScreen, initialSelection: NSRect) {
        self.screen = screen
        self.canvas = AnnotationCanvas(fullImage: fullImage, screen: screen, initialSelection: initialSelection)
        self.window = SelectionWindow(frame: screen.frame)
        self.toolbar = AnnotationToolbar()
        self.sizeBar = AnnotationSizeBar()
        super.init()

        canvas.windowController = self
        canvas.onSelectionChanged = { [weak self] in self?.repositionToolbar() }
        window.contentView = canvas
        window.delegate = self
        window.level = .screenSaver   // 完全置顶，覆盖整屏

        toolbar.onSelectTool = { [weak self] tool in
            guard let self = self else { return }
            self.canvas.hideOCROverlay()          // 切工具即退出文字模式
            self.canvas.switchTool(tool)          // 内部先提交编辑中的文字，见 switchTool 注释
            self.setShowSizeBar(tool != .select)  // 选择工具无线宽/字号可调，隐藏大小条
        }
        toolbar.onColor = { [weak self] color in self?.canvas.currentColor = color }
        toolbar.onAction = { [weak self] action in self?.handle(action) }

        sizeBar.onSize = { [weak self] s in self?.canvas.sizeScale = s }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        // 同 SelectionController.present：标注窗由框选确认进入，本进程可能仍非前台，
        // 不激活则 Esc（放弃）/回车（完成并复制）会被此前的前台应用收走。
        NSApp.activate(ignoringOtherApps: true)
        // 工具条/大小条必须浮在整屏标注窗之上，否则会被 .screenSaver 层覆盖
        let above = NSWindow.Level(rawValue: Int(window.level.rawValue) + 1)
        toolbar.level = above
        sizeBar.level = above
        setShowSizeBar(true)
        repositionToolbar()
        toolbar.orderFrontRegardless()
        toolbar.highlightDefaultTool()
    }

    private func setShowSizeBar(_ show: Bool) {
        if show { sizeBar.orderFrontRegardless() } else { sizeBar.orderOut(nil) }
        repositionToolbar()
    }

    func windowWillClose(_ notification: Notification) {
        toolbar.orderOut(nil)
        sizeBar.orderOut(nil)
        canvas.hideOCROverlay()
        // 断开 window→canvas 强引用，让 canvas/baseImage 随控制器一起释放，
        // 否则整屏 backing store（22MB@2x）要等 AppKit 内部延迟回收。
        window.contentView = nil
        toolbar.contentView = nil
        sizeBar.contentView = nil
        coordinator?.annotationDidClose()
    }

    private func repositionToolbar() {
        let selGlobal = NSRect(x: screen.frame.minX + canvas.selection.minX,
                               y: screen.frame.minY + canvas.selection.minY,
                               width: canvas.selection.width, height: canvas.selection.height)
        let tb = toolbar.frame.size
        let sb = sizeBar.frame.size
        let gap: CGFloat = 8
        // 工具条放选区下方；大小条再往下叠。若下方放不下，整体翻到上方（大小条在最上）。
        var toolbarOrigin = NSPoint(x: selGlobal.maxX - tb.width, y: selGlobal.minY - tb.height - gap)
        let sf = screen.frame
        let stackH = tb.height + (sizeBar.isVisible ? sb.height + gap : 0)
        let below = selGlobal.minY - stackH - gap
        let placeAbove = below < sf.minY
        if placeAbove { toolbarOrigin.y = selGlobal.maxY + gap }
        toolbarOrigin.x = min(max(toolbarOrigin.x, sf.minX + 4), sf.maxX - tb.width - 4)
        toolbarOrigin.y = min(max(toolbarOrigin.y, sf.minY + 4), sf.maxY - tb.height - 4)
        toolbar.setFrameOrigin(toolbarOrigin)

        if sizeBar.isVisible {
            let sx = toolbarOrigin.x + (tb.width - sb.width) / 2
            let tbTop = toolbarOrigin.y + tb.height
            let sy = placeAbove ? tbTop + gap : toolbarOrigin.y - sb.height - gap
            sizeBar.setFrameOrigin(NSPoint(x: min(max(sx, sf.minX + 4), sf.maxX - sb.width - 4),
                                           y: min(max(sy, sf.minY + 4), sf.maxY - sb.height - 4)))
        }
    }

    private func handle(_ action: ToolbarAction) {
        // 点工具/撤销/复制/保存/贴图/取消都先退出文字模式；.ocr 由 runOCR 自身 toggle
        if action != .ocr, canvas.isOCROverlayActive { canvas.hideOCROverlay() }
        switch action {
        case .undo:  canvas.undo()
        case .copy:  copyAndClose()
        case .save:  saveFile()
        case .pin:
            if let img = canvas.renderFinal() {
                let g = NSRect(x: screen.frame.minX + canvas.selection.minX,
                               y: screen.frame.minY + canvas.selection.minY,
                               width: canvas.selection.width, height: canvas.selection.height)
                coordinator?.pin(image: img, at: g)
            }
            close()
        case .ocr:   runOCR()
        case .cancel: close()
        }
    }

    /// 叠加层开关时由画布回调：工具条 OCR 按钮高亮跟随状态。
    func ocrOverlayVisibilityChanged() {
        if canvas.isOCROverlayActive { toolbar.setActionHighlight(.ocr) } else { toolbar.clearActionHighlight() }
    }

    /// 渲染带标注的最终图 → 写剪贴板 → 关闭。
    func copyAndClose() {
        if let img = canvas.renderFinal() { Clipboard.write(image: img) }
        close()
    }

    func close() { window.close() }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH-mm-ss"
        panel.nameFieldStringValue = "ClipLite \(fmt.string(from: Date())).png"
        panel.directoryURL = AppSettings.shared.lastSaveDirectory
        // 标注窗在 .screenSaver 层整屏覆盖，普通层级的保存面板会被盖住（点「保存」看似没反应），临时抬到其上一层
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        let response = panel.runModal()
        panel.level = .normal
        // 先拿 URL 再渲染：挂起期间不驻留整幅渲染结果（4K 选区 13~48MB），取消保存则完全不分配
        guard response == .OK, let url = panel.url else { return }
        guard let img = canvas.renderFinal() else { return }
        do {
            try PNGWriter.write(img, to: url)
        } catch {
            NSLog("ClipLite: 保存 PNG 失败 \(url.path): \(error)")
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = "无法写入 \(url.path)：\(error.localizedDescription)"
            alert.window.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
            alert.runModal()
            return  // 不关窗，用户可重试
        }
        AppSettings.shared.lastSaveDirectory = url.deletingLastPathComponent()
        close()
    }

    private func runOCR() {
        if canvas.isOCROverlayActive { canvas.hideOCROverlay(); return }   // 再点一次 OCR = 退出文字模式
        guard let img = canvas.renderFinal() else { return }
        VisionOCR.recognize(img) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let lines):
                self.canvas.showOCROverlay(lines: OCRTextOverlay.readingOrder(lines),
                                           message: lines.isEmpty ? "未识别到文字" : nil)
            case .failure(let error):
                self.canvas.showOCROverlay(lines: [], message: "识别失败（\(error.localizedDescription)）")
            }
        }
    }
}
