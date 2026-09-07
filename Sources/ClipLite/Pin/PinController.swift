import AppKit

/// 管理所有存活贴图窗口。关闭即从列表移除并释放图像内存。
final class PinController {
    private var pins: [PinWindowController] = []

    func pin(image: CGImage, at frame: NSRect) {
        let c = PinWindowController(image: image, frame: frame)
        c.onClose = { [weak self, weak c] in
            guard let c else { return }
            self?.remove(c)
        }
        pins.append(c)
        c.show()
    }

    private func remove(_ c: PinWindowController) {
        pins.removeAll { $0 === c }
    }

    /// 诊断用：关闭并释放所有贴图（拷贝快照后逐个 close，避免 remove 期间遍历突变）。
    func closeAll() {
        let snapshot = pins
        snapshot.forEach { $0.close() }
    }
}
