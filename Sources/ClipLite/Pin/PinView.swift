import AppKit

/// 贴图内容视图。拖主体移动、拖右下角手柄按比例缩放、双击关闭、滚轮缩放（辅助）。
/// 透明度改由右键菜单内的滑条控制（不再叠在图片上）。
final class PinView: NSView {
    let cgImage: CGImage
    let baseSize: NSSize
    weak var owner: PinWindowController?

    private enum Mode { case idle, move, resize }
    private var mode: Mode = .idle
    private var grabOffset = NSPoint.zero
    private var startFrame = NSRect.zero
    private let grip: CGFloat = 18

    // 切分模式：在贴图上框选一块区域，松手即以该区域生成新贴图；右键取消
    var cropMode = false { didSet { needsDisplay = true } }
    private var cropStart: NSPoint?
    private var cropRect: NSRect = .zero
    private let minCropSize: CGFloat = 8

    init(image: CGImage, baseSize: NSSize) {
        self.cgImage = image
        self.baseSize = baseSize
        super.init(frame: NSRect(origin: .zero, size: baseSize))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - 绘制
    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.interpolationQuality = .high
        ctx?.draw(cgImage, in: bounds)
        ctx?.restoreGState()

        // 右下角缩放手柄（三条斜线）
        let g = grip
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.5
        for i in stride(from: 4, through: g - 2, by: 5) {
            path.move(to: NSPoint(x: bounds.maxX - g + i, y: bounds.minY + 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + g - i))
        }
        path.stroke()

        if cropMode { drawCropOverlay() }
    }

    /// 切分模式覆盖层：选区外压暗 + 蓝框 + 操作提示
    private func drawCropOverlay() {
        let sel = cropRect
        NSColor.black.withAlphaComponent(0.35).setFill()
        if sel.isEmpty {
            bounds.fill()
        } else {
            NSRect(x: 0, y: sel.maxY, width: bounds.width, height: bounds.height - sel.maxY).fill()
            NSRect(x: 0, y: 0, width: sel.minX, height: sel.height).fill()
            NSRect(x: sel.maxX, y: 0, width: bounds.width - sel.maxX, height: sel.height).fill()
            NSRect(x: 0, y: 0, width: bounds.width, height: sel.minY).fill()
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: sel)
            border.lineWidth = 1.5
            border.stroke()
        }
        let hint = "拖拽框选区域生成新贴图，右键取消"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = hint.size(withAttributes: attrs)
        // 提示条贴在选区上边缘上方（无选区时贴窗口顶部），保证始终在压暗区域内可读
        let y = sel.isEmpty ? bounds.height - size.height - 10 : min(bounds.height - size.height - 4, sel.maxY + 6)
        let x = min(max(sel.midX - size.width / 2, 6), bounds.width - size.width - 6)
        hint.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    private func gripRect() -> NSRect {
        NSRect(x: bounds.maxX - grip, y: bounds.minY, width: grip, height: grip)
    }

    // MARK: - 鼠标
    override func mouseDown(with event: NSEvent) {
        if cropMode {
            cropStart = convert(event.locationInWindow, from: nil)
            cropRect = .zero
            needsDisplay = true
            return
        }
        if event.clickCount >= 2 { window?.close(); return }
        let p = convert(event.locationInWindow, from: nil)
        guard let w = window else { return }
        if gripRect().insetBy(dx: -6, dy: -6).contains(p) {
            mode = .resize; startFrame = w.frame
        } else {
            mode = .move
            grabOffset = NSPoint(x: w.frame.origin.x - NSEvent.mouseLocation.x,
                                 y: w.frame.origin.y - NSEvent.mouseLocation.y)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if cropMode {
            guard let start = cropStart else { return }
            let now = convert(event.locationInWindow, from: nil)
            cropRect = NSRect(x: min(start.x, now.x), y: min(start.y, now.y),
                              width: abs(start.x - now.x), height: abs(start.y - now.y))
            needsDisplay = true
            return
        }
        guard let w = window else { return }
        switch mode {
        case .move:
            let loc = NSEvent.mouseLocation
            w.setFrameOrigin(NSPoint(x: loc.x + grabOffset.x, y: loc.y + grabOffset.y))
        case .resize:
            w.setFrame(Self.resizedFrame(from: startFrame, to: NSEvent.mouseLocation),
                       display: true, animate: false)
            needsDisplay = true
        case .idle: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if cropMode {
            let tooSmall = cropRect.width < minCropSize || cropRect.height < minCropSize
            if !tooSmall { emitSplit() }
            finishCrop()
            return
        }
        mode = .idle
    }

    override func rightMouseDown(with event: NSEvent) {
        if cropMode { finishCrop(); return }   // 右键 = 取消切分
        owner?.showMenu(event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if cropMode { return }
        guard let w = window else { return }
        let factor: CGFloat = event.deltaY > 0 ? 1.1 : (event.deltaY < 0 ? 1 / 1.1 : 1)
        // 以当前窗口尺寸为基准缩放（尊重 grip 拖出的自定义宽高比），上下限保留相对 baseSize 的 0.1×…16×
        let newSize = NSSize(width: w.frame.width * factor, height: w.frame.height * factor)
        guard newSize.width >= baseSize.width * 0.1, newSize.height >= baseSize.height * 0.1,
              newSize.width <= baseSize.width * 16, newSize.height <= baseSize.height * 16 else { return }
        let cursor = NSEvent.mouseLocation
        var f = w.frame
        let fx = (cursor.x - f.minX) / f.width
        let fy = (cursor.y - f.minY) / f.height
        f.size = newSize
        f.origin.x = cursor.x - fx * newSize.width
        f.origin.y = cursor.y - fy * newSize.height
        w.setFrame(f, display: true, animate: false)
        needsDisplay = true
    }

    /// 结束切分：无论成功、选区过小还是右键取消，一律回到普通模式
    private func finishCrop() {
        cropStart = nil
        cropRect = .zero
        cropMode = false
        needsDisplay = true
    }

    /// 按框选区域裁出子图并上报：贴图点坐标 → 图像像素（CGImage 原点在左上，需翻转 y）
    private func emitSplit() {
        let scaleX = CGFloat(cgImage.width) / bounds.width
        let scaleY = CGFloat(cgImage.height) / bounds.height
        let px = CGRect(x: (cropRect.minX * scaleX).rounded(),
                        y: ((bounds.height - cropRect.maxY) * scaleY).rounded(),
                        width: (cropRect.width * scaleX).rounded(),
                        height: (cropRect.height * scaleY).rounded())
        guard px.width >= 1, px.height >= 1, let crop = cgImage.cropping(to: px) else { return }
        let frame = NSRect(x: window!.frame.minX + cropRect.minX,
                           y: window!.frame.minY + cropRect.minY,
                           width: cropRect.width, height: cropRect.height)
        owner?.splitOut(image: crop, frame: frame)
    }

    /// 右下角手柄拖动后的新窗口 frame：对角（左上 = minX/maxY）固定，等比缩放到光标处。
    /// 曾因只改 size、不更新 origin.y 而钉死下边、让顶边反向飞走。
    static func resizedFrame(from start: NSRect, to mouse: NSPoint, minSide: CGFloat = 30) -> NSRect {
        let aspect = start.width / max(1, start.height)
        let wantW = max(minSide, mouse.x - start.minX)
        let wantH = max(minSide, start.maxY - mouse.y)
        let size = wantW / aspect >= wantH
            ? NSSize(width: wantW, height: wantW / aspect)
            : NSSize(width: wantH * aspect, height: wantH)
        // 锚左上角：left/top 不变，底部随 size 下移（手柄在右下 → 光标方向与增长方向一致）
        return NSRect(x: start.minX, y: start.maxY - size.height,
                      width: size.width, height: size.height)
    }
}

#if !RELEASE_BUILD
extension PinView {
    /// 可运行检查：右下角手柄必须锚定左上角（minX/maxY 不变、minY 随尺寸走），保持宽高比。
    /// 回归的是「拖右下角却动了顶边」——旧实现钉死 minY，maxY 反向漂移。
    static func selfCheck() {
        let start = NSRect(x: 100, y: 200, width: 400, height: 300)   // minY=200, maxY=500
        let aspect = 400.0 / 300.0
        // 向右下拖动（宽度主导）：left/top 必须不动，底边随尺寸下移
        let out = resizedFrame(from: start, to: NSPoint(x: 900, y: 150))
        assert(out.minX == start.minX, "左边漂移 \(out.minX) ≠ \(start.minX)")
        assert(out.maxY == start.maxY, "顶边漂移 \(out.maxY) ≠ \(start.maxY)（应只有底边动）")
        assert(out.minY < start.minY, "向下拖动未让底边下移 minY=\(out.minY)")
        assert(abs(out.width / out.height - aspect) < 1e-9, "宽高比失真 \(out.size)")
        assert(out.maxX == 900, "右边界未跟住光标 maxX=\(out.maxX)")
        // 高度主导：底边应精确落在光标上，锚点不动
        let tall = resizedFrame(from: start, to: NSPoint(x: 900, y: -300))
        assert(tall.minY == -300, "高度主导时底边未跟住光标 minY=\(tall.minY)")
        assert(tall.maxY == start.maxY && tall.minX == start.minX, "高度主导时锚点漂移")
        assert(abs(tall.width / tall.height - aspect) < 1e-9, "高度主导宽高比失真 \(tall.size)")
        // 往上拖过头：钳到下限，不翻转、不越过顶边
        let tiny = resizedFrame(from: start, to: NSPoint(x: 110, y: 900))
        assert(tiny.width >= 30 && tiny.height >= 22, "未钳到下限 \(tiny.size)")
        assert(tiny.maxY == start.maxY && tiny.minX == start.minX, "钳制时锚点漂移")
        print("PinView.selfCheck OK")
    }
}
#endif
