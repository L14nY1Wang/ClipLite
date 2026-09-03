import AppKit

/// 管理所有存活贴图窗口。关闭即从列表移除并释放图像内存。
final class PinController {
    private var pins: [PinWindowController] = []

    func pin(image: CGImage, at frame: NSRect) {
        let c = PinWindowController(image: image, frame: frame)
        c.onClose = { [weak self] in self?.remove(c) }
        pins.append(c)
        c.show()
    }

    private func remove(_ c: PinWindowController) {
        pins.removeAll { $0 === c }
    }
}
