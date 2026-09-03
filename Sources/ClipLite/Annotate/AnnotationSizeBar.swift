import AppKit

/// 独立的“标记大小”子工具条：够长的滑块，只在选中可缩放工具时出现。
final class AnnotationSizeBar: NSPanel {
    var onSize: ((CGFloat) -> Void)?

    private let slider = NSSlider()

    init() {
        let w: CGFloat = 260, h: CGFloat = 34
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = false

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "大小")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 12, y: (h - 16) / 2, width: 30, height: 16)
        effect.addSubview(label)

        slider.frame = NSRect(x: 48, y: (h - 20) / 2, width: w - 64, height: 20)
        slider.sliderType = .linear
        slider.minValue = 0.5; slider.maxValue = 4.0; slider.doubleValue = 1.0
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed(_:))
        effect.addSubview(slider)

        contentView = effect
    }

    var currentValue: CGFloat { CGFloat(slider.doubleValue) }
    func setValue(_ v: CGFloat) { slider.doubleValue = Double(v) }

    @objc private func changed(_ s: NSSlider) { onSize?(CGFloat(s.doubleValue)) }
}
