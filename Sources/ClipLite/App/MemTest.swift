import AppKit

/// 内存诊断 harness（--memtest）：真实走 截图→标注→贴图→关闭 全链路，逐步打印
/// RSS + physical footprint（Activity Monitor「内存」列口径），验证对象是否释放。
///   A. 真实截屏 → 建标注窗 → show → 渲染 → 关闭，观察整屏 baseImage 是否回收
///   B. 大图贴图（4032×3024）→ 关闭 → drain 后是否回落到基线
///   C. 第二轮贴图（3000×2000）→ 关闭，验证不累积泄漏
///   D. 贴图 → 识别文字（弹 OCR 面板）→ 关闭贴图，验证 OCR 面板不残留
/// 各步之间让 runloop 转起来，保证 windowWillClose / 通知送达。
enum MemTest {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let h = Harness()          // NSApplication.delegate 是 weak，必须强持有
        app.delegate = h
        app.run()
    }
}

final class Harness: NSObject, NSApplicationDelegate {
    private var pinController = PinController()
    private var scenarioDPin: PinWindowController?
    private var ocrTestImage: CGImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("MEMSTEP[0] baseline \(Harness.memLine())")
        // --memtest-ocr：单独量化一次 OCR 的常驻开销（冷进程，不跑截图/贴图）
        if CommandLine.arguments.contains("--memtest-ocr") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.scenarioE() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.scenarioA() }
        }
    }

    // MARK: E. 单次 OCR 的常驻开销（验证「Vision 模型不常驻」）
    @MainActor
    private func scenarioE() {
        let w = 1200, h = 800
        guard let ctx = Harness.makeContext(w: w, h: h), let img = ctx.makeImage() else {
            print("MEMSTEP[E] 合成图失败"); finishOrHold(); return
        }
        print("MEMSTEP[E1] 首次 OCR 前 \(Harness.memLine())")
        ocrTestImage = img
        VisionOCR.recognize(img) { [weak self] result in
            switch result {
            case .success(let t): print("MEMSTEP[E2] OCR 完成 文本长度=\(t.count) \(Harness.memLine())")
            case .failure(let e): print("MEMSTEP[E2] OCR 失败 \(e.localizedDescription)")
            }
            self?.afterOCR()
        }
    }

    @MainActor
    private func afterOCR() {
        ocrTestImage = nil   // 释放被测图，只看 Vision 自身的残留
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            print("MEMSTEP[E3] OCR 后 3s \(Harness.memLine())")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self else { return }
                print("MEMSTEP[E4] OCR 后 8s \(Harness.memLine())")
                self.finishOrHold()
            }
        }
    }

    // MARK: A. 真实截屏 → 标注 → 渲染 → 关闭
    @MainActor
    private func scenarioA() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var captured: ScreenCapture.Display?
            do {
                captured = try await ScreenCapture.captureAll().first
            } catch {
                print("MEMSTEP[A] 截屏失败（权限？）: \(error)")
            }
            // 只取出需要的 image + screen，立刻释放 ScreenCapture.Display（含可能的 IOSurface 句柄），
            // 否则它会被 Task 闭包捕获直到整条链结束，污染后续所有测量。
            let img = captured?.image
            let scr = captured?.screen
            captured = nil
            if let img = img, let scr = scr {
                print("MEMSTEP[A1] captured \(img.width)x\(img.height) \(Harness.memLine())")
                let sel = NSRect(x: scr.frame.width * 0.25, y: scr.frame.height * 0.25,
                                 width: scr.frame.width * 0.5, height: scr.frame.height * 0.5)
                var ann: AnnotationWindowController? =
                    AnnotationWindowController(fullImage: img, screen: scr, initialSelection: sel)
                print("MEMSTEP[A2] annotation created \(Harness.memLine())")
                ann!.show()
                print("MEMSTEP[A2b] annotation shown \(Harness.memLine())")
                var cropped: CGImage? = ann!.canvas.renderFinal()
                print("MEMSTEP[A3] rendered \(cropped?.width ?? 0)x\(cropped?.height ?? 0) \(Harness.memLine())")
                ann?.close()
                ann = nil
                cropped = nil
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                print("MEMSTEP[A4] annotation closed \(Harness.memLine())")
            } else {
                print("MEMSTEP[A] 无可用显示器，跳过场景 A")
            }
            self.scenarioB()
        }
    }

    // MARK: B. 大图贴图 → 关闭全部贴图
    @MainActor
    private func scenarioB() {
        let w = 4032, h = 3024
        guard let ctx = Harness.makeContext(w: w, h: h), let img = ctx.makeImage() else {
            print("MEMSTEP[B] 合成图失败"); Harness.finish(); return
        }
        print("MEMSTEP[B1] synthetic \(w)x\(h) ready \(Harness.memLine())")
        pinController.pin(image: img, at: Harness.centerFrame(w: w, h: h))
        print("MEMSTEP[B2] pinned \(Harness.memLine())")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.pinController.closeAll()
            print("MEMSTEP[B3] closeAll \(Harness.memLine())")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                autoreleasepool { print("MEMSTEP[B4] after drain \(Harness.memLine())") }
                Harness.releaseMalloc()
                print("MEMSTEP[B4b] after malloc_zone_reclaim \(Harness.memLine())")
                self.scenarioC()
            }
        }
    }

    // MARK: C. 第二轮贴图，验证不累积泄漏
    @MainActor
    private func scenarioC() {
        let w = 3000, h = 2000
        guard let ctx = Harness.makeContext(w: w, h: h), let img = ctx.makeImage() else {
            print("MEMSTEP[C] 合成图失败"); Harness.finish(); return
        }
        print("MEMSTEP[C1] synthetic2 \(w)x\(h) ready \(Harness.memLine())")
        pinController.pin(image: img, at: Harness.centerFrame(w: w, h: h))
        print("MEMSTEP[C2] pinned2 \(Harness.memLine())")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.pinController.closeAll()
            print("MEMSTEP[C3] closeAll2 \(Harness.memLine())")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("MEMSTEP[C4] after drain2 \(Harness.memLine())")
                self.scenarioD()
            }
        }
    }

    // MARK: D. 贴图 → 识别文字（弹 OCR 面板）→ 关闭贴图，验证面板不残留
    @MainActor
    private func scenarioD() {
        let w = 1200, h = 800
        guard let ctx = Harness.makeContext(w: w, h: h), let img = ctx.makeImage() else {
            print("MEMSTEP[D] 合成图失败")
            finishOrHold()
            return
        }
        scenarioDPin = PinWindowController(image: img, frame: Harness.centerFrame(w: w, h: h))
        scenarioDPin!.show()
        print("MEMSTEP[D1] 贴图已显示 windows=\(NSApp.windows.count)")
        scenarioDPin!.perform(Selector(("recognize")))
        print("MEMSTEP[D2] 已发起 OCR（异步），等待回调")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            let appeared = NSApp.windows.contains { $0 is OCRResultPanel }
            print("MEMSTEP[D2] OCR 面板出现=\(appeared) windows=\(NSApp.windows.count)")
            self.scenarioDPin?.close()
            let lingering = NSApp.windows.contains { $0 is OCRResultPanel && $0.isVisible }
            print("MEMSTEP[D3] 关闭贴图后 OCR面板仍可见=\(lingering) windows=\(NSApp.windows.count)")
            self.scenarioDPin = nil
            self.finishOrHold()
        }
    }

    private func finishOrHold() {
        print("MEMSTEP[5] \(Harness.memLine())")
        if CommandLine.arguments.contains("--memtest-hold") {
            print("MEMSTEP[hold] 观察衰减 60s")
            var tick = 0
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { t in
                tick += 1
                print("MEMSTEP[hold+\(tick * 2)s] \(Harness.memLine())")
                if tick >= 30 { t.invalidate(); Harness.finish() }
            }
        } else {
            Harness.finish()
        }
    }

    static func finish() {
        print("MEMSTEP[done]")
        NSApp.terminate(nil)
    }

    // MARK: - 工具
    static func makeContext(w: Int, h: Int) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))   // 强制物化 backing store
        return ctx
    }

    static func centerFrame(w: Int, h: Int) -> NSRect {
        let pt = NSEvent.mouseLocation
        let scale = NSScreen.backingScaleFactor(at: pt)
        let sizePt = NSSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale)
        return NSRect(x: pt.x - sizePt.width / 2, y: pt.y - sizePt.height / 2,
                      width: sizePt.width, height: sizePt.height)
    }

    /// 一行内存快照：RSS + physical footprint
    static func memLine() -> String { "rss=\(rssKB())KB footprint=\(footprintKB())KB" }

    /// 建议 malloc 子系统归还已释放但未 decommit 的页给 OS，看能否压低 RSS
    static func releaseMalloc() {
        if let zone = malloc_default_zone() {
            let released = malloc_zone_pressure_relief(zone, .max)
            print("MEMSTEP[relief] 已释放 \(released) 字节")
        }
    }

    static func rssKB() -> UInt64 {
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

    /// vmmap --summary 的 Physical footprint（Activity Monitor 口径）
    static func footprintKB() -> UInt64 {
        let p = Process()
        p.launchPath = "/usr/bin/vmmap"
        p.arguments = ["--summary", "\(getpid())"]
        let pipe = Pipe()
        p.standardOutput = pipe
        do { try p.run(); p.waitUntilExit() } catch { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        guard let line = out.split(separator: "\n").first(where: { $0.contains("Physical footprint:") }),
              let last = line.split(separator: ":").last else { return 0 }
        let tok = last.trimmingCharacters(in: .whitespaces)
        let num = Double(tok.dropLast()) ?? 0
        switch tok.last {
        case "K": return UInt64(num)
        case "M": return UInt64(num * 1024)
        case "G": return UInt64(num * 1024 * 1024)
        default: return 0
        }
    }
}
