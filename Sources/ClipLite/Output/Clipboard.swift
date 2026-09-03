import AppKit

/// 剪贴板读写。同时写 PNG 和 TIFF，兼容更多粘贴目标。
enum Clipboard {
    static func write(image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    static func readImage() -> CGImage? {
        let pb = NSPasteboard.general
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
            return rep.cgImage
        }
        if let png = pb.data(forType: .png), let rep = NSBitmapImageRep(data: png) {
            return rep.cgImage
        }
        return nil
    }
}
