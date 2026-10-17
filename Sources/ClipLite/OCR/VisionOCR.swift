import Vision
import AppKit
import Foundation

/// 系统内置 Vision OCR：离线、免费、无 key。中英文混排。
///
/// 走子进程：Vision 模型常驻 ~52MB，进程内无法卸载；放到子进程里，识别完随 exit
/// 自动回收，主进程 footprint 不再增长。序列化用临时 PNG（一张 1133×744 约 200–500KB）。
///
/// 返回结构化结果（文字 + 归一化坐标框）：调用方把文字按原位叠加渲染在图片上就地划选复制
/// （见 `OCRTextOverlay`），不再弹独立结果窗。子进程 stdout 走 JSON 行数组。
enum VisionOCR {
    /// 串行队列：Vision 子进程常驻 ~52MB，并发识别会同时拉起多个子进程；同一时刻只跑一个。
    private static let queue = DispatchQueue(label: "com.cliplite.ocr", qos: .userInitiated)
    static func recognize(_ image: CGImage, completion: @escaping (Result<[OCRLine], Error>) -> Void) {
        queue.async {
            do {
                let text = try recognizeInSubprocess(image)
                DispatchQueue.main.async { completion(.success(text)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func recognizeInSubprocess(_ image: CGImage) throws -> [OCRLine] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliplite-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try PNGWriter.write(image, to: url)

        guard let exe = Bundle.main.executableURL else { throw OCRError.noExecutable }
        let p = Process()
        p.executableURL = exe
        p.arguments = ["--ocr-worker", url.path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        try p.run()

        // 先并发排空管道再 waitUntilExit：子进程输出超过 64KB 管道缓冲时会写阻塞，
        // 父进程若先 waitUntilExit 会在子进程阻塞写入时永久死锁。
        let readQueue = DispatchQueue.global(qos: .userInitiated)
        let outSemaphore = DispatchSemaphore(value: 0)
        let errSemaphore = DispatchSemaphore(value: 0)
        var outData = Data()
        var errData = Data()
        readQueue.async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            outSemaphore.signal()
        }
        readQueue.async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            errSemaphore.signal()
        }

        // 超时保护：30 秒未退出则 terminate，避免子进程卡死导致父进程永久挂起。
        let deadline = DispatchTime.now() + .seconds(30)
        let timeout = DispatchWorkItem { [weak p] in
            guard let p = p, p.isRunning else { return }
            p.terminate()
            // 子进程可能忽略 SIGTERM，此时 waitUntilExit 会永久挂起串行队列；0.5s 后强杀兜底。
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: timeout)

        p.waitUntilExit()
        timeout.cancel()
        outSemaphore.wait()
        errSemaphore.wait()

        guard p.terminationStatus == 0 else {
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            throw OCRError.workerFailed(status: Int(p.terminationStatus), stderr: stderr)
        }
        return try decodeJSON(outData)
    }

    // MARK: - 子进程 JSON 协议（stdout：`[{"t": 文字, "b": [x,y,w,h], "c": [{"c": 字符, "b": [...]}, ...]}, ...]`，box 归一化）
    static func encodeJSON(_ lines: [OCRLine]) throws -> Data {
        let payload: [[String: Any]] = lines.map { l in
            [
                "t": l.text,
                "b": [l.box.minX, l.box.minY, l.box.width, l.box.height],
                "c": l.chars.map { ["c": String($0.char),
                                    "b": [$0.box.minX, $0.box.minY, $0.box.width, $0.box.height]] },
            ]
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func decodeJSON(_ data: Data) throws -> [OCRLine] {
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw OCRError.badOutput
        }
        return arr.compactMap { d in
            guard let t = d["t"] as? String, let b = d["b"] as? [CGFloat], b.count == 4 else { return nil }
            let chars: [OCRChar] = ((d["c"] as? [[String: Any]]) ?? []).compactMap { cd in
                guard let cs = cd["c"] as? String, cs.count == 1,
                      let cb = cd["b"] as? [CGFloat], cb.count == 4 else { return nil }
                return OCRChar(char: cs.first!, box: CGRect(x: cb[0], y: cb[1], width: cb[2], height: cb[3]))
            }
            return OCRLine(text: t, box: CGRect(x: b[0], y: b[1], width: b[2], height: b[3]), chars: chars)
        }
    }

    /// 同步识别：供 `--ocr-worker` 子进程直接调用。
    static func perform(_ image: CGImage) throws -> [OCRLine] {
        var lines: [OCRLine] = []
        let request = VNRecognizeTextRequest { req, _ in
            lines = ((req.results as? [VNRecognizedTextObservation]) ?? []).compactMap { obs in
                guard let cand = obs.topCandidates(1).first else { return nil }
                return OCRLine(text: cand.string, box: obs.boundingBox,
                               chars: Self.charBoxes(of: cand))
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        // 截图常含小字：不设检测下限，避免整行小字被 Vision 直接丢弃（参考 TextGrab）
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return lines
    }

    /// 逐字符取归一化坐标框，实现「逐字选择」。
    /// 注意 accurate 模式下 `boundingBox(for:)` 对英文是**词级**精度（Apple 文档明示），
    /// 对中文是字符级；`fast` 模式才是真正字符级但识别质量差。取舍：accurate 为主识别，
    /// 中文逐字、英文逐词——中文截图场景（本项目主要用户）拿到完整逐字能力。
    /// 空格没有框（返回 .zero），直接跳过，复制时按 text 拼接不丢字。
    private static func charBoxes(of cand: VNRecognizedText) -> [OCRChar] {
        let s = cand.string
        var out: [OCRChar] = []
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let n = s.index(after: i)
            if let b = (try? cand.boundingBox(for: i..<n))?.boundingBox, b != .zero, b.width > 0 {
                out.append(OCRChar(char: s[i], box: b))
            }
            i = n
        }
        return out
    }
}

enum OCRError: Error {
    case noExecutable
    case badOutput
    case workerFailed(status: Int, stderr: String = "")
}

extension OCRError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .badOutput:
            return "OCR 子进程输出无法解析"
        case .workerFailed(let status, let stderr):
            return stderr.isEmpty ? "OCR 子进程异常退出（exit \(status)）"
                                  : "OCR 子进程异常退出（exit \(status)）：\(stderr)"
        default:
            return nil  // 其余 case 维持系统默认描述，行为不变
        }
    }
}

extension VisionOCR {
    /// 清扫上次强杀残留的 OCR 临时 PNG。正常路径 `defer` 必清，但父进程被 SIGKILL 时
    /// （或子进程 exit 前父进程先死）会漏；只删 1 小时前的，避免误伤并发识别中的文件。
    static func cleanupStaleTempFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for url in files where url.lastPathComponent.hasPrefix("cliplite-ocr-")
            && url.pathExtension == "png" {
            guard let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  d < cutoff else { continue }
            try? fm.removeItem(at: url)
        }
    }
}

/// 子进程入口：从 PNG 路径惰性加载 CGImage。
enum OCRWorker {
    static func loadImage(path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let src = CGImageSourceCreateWithURL(url, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
