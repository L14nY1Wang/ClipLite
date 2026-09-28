import AppKit
import ImageIO

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
        // 在 Finder 里复制图片文件时，剪贴板只有 file URL、没有位图数据——
        // 原先这里直接返回 nil，用户按 ⌥2 毫无反应。取第一个能解码的文件。
        let urls = pb.readObjects(forClasses: [NSURL.self],
                                  options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls {
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return img
            }
        }
        return nil
    }
}
