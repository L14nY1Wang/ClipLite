import AppKit

/// 命令行自测：截屏 → 裁剪中心区域 → 写 PNG → 打印内存占用。
enum SelfTest {
    static func run() {
        guard ScreenCapture.preflight() else {
            print("SELFTEST: 屏幕录制权限未授予。请在 系统设置 → 隐私与安全 → 屏幕录制 中允许 ClipLite 后重启应用。")
            _ = ScreenCapture.request()
            return
        }
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let displays = try await ScreenCapture.captureAll()
                guard let d = displays.first, d.image.width > 0 else {
                    print("SELFTEST: 未捕获到任何显示器"); sem.signal(); return
                }
                // 打印真实比例数字，定位缩放畸变
                let sf = d.screen.frame
                let bs = d.screen.backingScaleFactor
                print("SELFTEST: screen.frame(points)=\(sf) backingScale=\(bs)")
                print("SELFTEST: capture(px)=\(d.image.width)x\(d.image.height) CGDisplayBounds=\(d.cgRect)")
                print("SELFTEST: 期望px=\(sf.width)bx\(sf.height)b=  (\(sf.width*bs)x\(sf.height*bs))  scaleX=\(Double(d.image.width)/sf.width) scaleY=\(Double(d.image.height)/sf.height)")
                let img = d.image
                let w = min(300, img.width)
                let h = min(150, img.height)
                let crop = img.cropping(to: CGRect(x: (img.width - w) / 2,
                                                  y: (img.height - h) / 2,
                                                  width: w, height: h))!
                let url = URL(fileURLWithPath: "/tmp/cliplite-selftest.png")
                let rep = NSBitmapImageRep(cgImage: crop)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: url)
                }
                let rss = rssKB()
                print("SELFTEST: OK display=\(d.displayID) image=\(img.width)x\(img.height) crop=\(w)x\(h) png=\(url.path) RSS=\(rss)KB")
            } catch {
                print("SELFTEST: 捕获失败 \(error)")
            }
            sem.signal()
        }
        sem.wait()
    }

    private static func rssKB() -> UInt64 {
        let p = Process()
        p.launchPath = "/bin/ps"
        p.arguments = ["-o", "rss=", "-p", "\(getpid())"]
        let pipe = Pipe()
        p.standardOutput = pipe
        do { try p.run(); p.waitUntilExit() } catch { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return UInt64(s) ?? 0
    }
}
