import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 屏幕捕获封装。一次性截图（SCScreenshotManager），不维持常驻流，内存只在捕获瞬间增长。
enum ScreenCapture {
    static func preflight() -> Bool { CGPreflightScreenCaptureAccess() }
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    struct Display {
        let displayID: CGDirectDisplayID
        let screen: NSScreen
        let cgRect: CGRect // CG 全局坐标（左上原点），用于 CGWindowList 边界换算
        let image: CGImage
    }

    static func captureAll() async throws -> [Display] {
        let content = try await SCShareableContent.current
        var out: [Display] = []
        for display in content.displays {
            guard let screen = matchScreen(displayID: display.displayID) else { continue }
            // 关键：输出尺寸 = 该屏「点尺寸 × 该屏缩放比」，与 AppKit 窗口栅格严格一致。
            // 这样覆盖层 1:1 绘制不畸变，裁剪/贴图比例正确；且完全按当前显示器动态计算，不写死。
            let scale = screen.backingScaleFactor
            let pts = screen.frame.size
            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.width  = max(1, Int((pts.width  * scale).rounded()))
            config.height = max(1, Int((pts.height * scale).rounded()))

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await captureImage(filter: filter, configuration: config)
            let cgRect = CGDisplayBounds(display.displayID)
            out.append(Display(displayID: display.displayID, screen: screen, cgRect: cgRect, image: image))
        }
        return out
    }

    private static func matchScreen(displayID: CGDirectDisplayID) -> NSScreen? {
        for screen in NSScreen.screens {
            if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               n.uint32Value == displayID {
                return screen
            }
        }
        return nil
    }

    /// 用 continuation 包裹完成式 API，保证 macOS 14+ 可用（async 重载在部分版本缺失）。
    private static func captureImage(filter: SCContentFilter,
                                     configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGImage, Error>) in
            SCScreenshotManager.captureImage(contentFilter: filter,
                                             configuration: configuration) { image, error in
                if let image = image {
                    cont.resume(returning: image)
                } else {
                    cont.resume(throwing: error ?? NSError(domain: "ClipLite.ScreenCapture", code: 1))
                }
            }
        }
    }
}
