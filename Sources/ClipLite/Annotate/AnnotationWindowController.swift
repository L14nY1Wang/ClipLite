import AppKit

/// 标注会话：选区确认后出现，覆盖整屏。画布上有可调整选取框 + 标注；工具条悬浮在框下方。
final class AnnotationWindowController: NSObject, NSWindowDelegate {
    let window: SelectionWindow
    let canvas: AnnotationCanvas
    let toolbar: AnnotationToolbar
    let sizeBar: AnnotationSizeBar
    let screen: NSScreen
    weak var coordinator: AppCoordinator?
    private var ocrPanel: OCRResultPanel?

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
            self.canvas.currentTool = tool
            self.setShowSizeBar(tool.isSizeAdjustable)   // 仅可缩放工具出现大小条
        }
        toolbar.onColor = { [weak self] color in self?.canvas.currentColor = color }
        toolbar.onAction = { [weak self] action in self?.handle(action) }

        sizeBar.onSize = { [weak self] s in self?.canvas.sizeScale = s }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        // 工具条/大小条必须浮在整屏标注窗之上，否则会被 .screenSaver 层覆盖
        let above = NSWindow.Level(rawValue: Int(window.level.rawValue) + 1)
        toolbar.level = above
        sizeBar.level = above
        setShowSizeBar(canvas.currentTool.isSizeAdjustable)
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
        ocrPanel?.orderOut(nil)
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
        var below = selGlobal.minY - stackH - gap
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

    /// 渲染带标注的最终图 → 写剪贴板 → 关闭。
    func copyAndClose() {
        if let img = canvas.renderFinal() { Clipboard.write(image: img) }
        close()
    }

    func close() { window.close() }

    private func saveFile() {
        guard let img = canvas.renderFinal() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "ClipLite-\(Int(Date().timeIntervalSince1970)).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
        close()
    }

    private func runOCR() {
        guard let img = canvas.renderFinal() else { return }
        VisionOCR.recognize(img) { [weak self] text in
            guard let self = self else { return }
            if self.ocrPanel == nil { self.ocrPanel = OCRResultPanel() }
            // 蓝框的全局坐标
            let g = NSRect(x: self.screen.frame.minX + self.canvas.selection.minX,
                           y: self.screen.frame.minY + self.canvas.selection.minY,
                           width: self.canvas.selection.width, height: self.canvas.selection.height)
            // 面板浮在整屏标注窗之上，并停靠蓝框下方
            let above = NSWindow.Level(rawValue: Int(self.window.level.rawValue) + 1)
            self.ocrPanel?.show(text: text, below: g, level: above)
        }
    }
}
