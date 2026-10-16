import Foundation
import CoreGraphics
import ImageIO

/// CGImage 直写 PNG。绕开 `NSBitmapImageRep(cgImage:)` 的整幅位图拷贝
/// （4K 选区即 48MB 堆分配），只保留编码缓冲。
enum PNGWriter {
    static func write(_ image: CGImage, to url: URL) throws {
        guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dst, image, nil)
        guard CGImageDestinationFinalize(dst) else { throw CocoaError(.fileWriteUnknown) }
    }
}
