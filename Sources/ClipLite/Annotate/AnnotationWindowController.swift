import AppKit

/// 标注会话：选区确认后出现，覆盖整屏。画布上有可调整选取框 + 标注；工具条悬浮在框下方。
final class AnnotationWindowController: NSObject, NSWindowDelegate {
    let window: SelectionWindow
    let canvas: AnnotationCanvas
    let toolbar: AnnotationToolbar
    let screen: NSScreen
    weak var coordinator: AppCoordinator?
    private var ocrPanel: OCRResultPanel?

    init(fullImage: CGImage, screen: NSScreen, initialSelection: NSRect) {
        self.screen = screen
        self.canvas = AnnotationCanvas(fullImage: fullImage, screen: screen, initialSelection: initialSelection)
        self.window = SelectionWindow(frame: screen.frame)
        self.toolbar = AnnotationToolbar()
        super.init()

        canvas.windowController = self
        canvas.onSelectionChanged = { [weak self] in self?.repositionToolbar() }
        window.contentView = canvas
        window.delegate = self
        window.level = .screenSaver   // 完全置顶，覆盖整屏

        toolbar.onSelectTool = { [weak self] tool in self?.canvas.currentTool = tool }
        toolbar.onColor = { [weak self] color in self?.canvas.currentColor = color }
        toolbar.onAction = { [weak self] action in self?.handle(action) }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        // 工具条必须浮在整屏标注窗之上，否则会被 .screenSaver 层覆盖而“消失”
        toolbar.level = NSWindow.Level(rawValue: Int(window.level.rawValue) + 1)
        repositionToolbar()
        toolbar.orderFrontRegardless()
        toolbar.highlightDefaultTool()
    }

    func windowWillClose(_ notification: Notification) {
        toolbar.orderOut(nil)
        ocrPanel?.orderOut(nil)
        coordinator?.annotationDidClose()
    }

    private func repositionToolbar() {
        let selGlobal = NSRect(x: screen.frame.minX + canvas.selection.minX,
                               y: screen.frame.minY + canvas.selection.minY,
                               width: canvas.selection.width, height: canvas.selection.height)
        let tb = toolbar.frame.size
        var origin = NSPoint(x: selGlobal.maxX - tb.width, y: selGlobal.minY - tb.height - 8)
        let sf = screen.frame
        if origin.y < sf.minY { origin.y = selGlobal.maxY + 8 }      // 下方放不下 → 放上方
        origin.x = min(max(origin.x, sf.minX + 4), sf.maxX - tb.width - 4)
        origin.y = min(max(origin.y, sf.minY + 4), sf.maxY - tb.height - 4)
        toolbar.setFrameOrigin(origin)
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
            self.ocrPanel?.orderOut(nil)
            let panel = OCRResultPanel(); self.ocrPanel = panel
            let g = NSRect(x: self.screen.frame.minX + self.canvas.selection.minX,
                           y: self.screen.frame.minY + self.canvas.selection.minY,
                           width: self.canvas.selection.width, height: self.canvas.selection.height)
            panel.show(text: text, near: g)
        }
    }
}
