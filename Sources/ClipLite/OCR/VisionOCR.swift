import Vision
import AppKit
import Foundation

/// 系统内置 Vision OCR：离线、免费、无 key。中英文混排。
///
/// 走子进程：Vision 模型常驻 ~52MB，进程内无法卸载；放到子进程里，识别完随 exit
/// 自动回收，主进程 footprint 不再增长。序列化用临时 PNG（一张 1133×744 约 200–500KB）。
enum VisionOCR {
    static func recognize(_ image: CGImage, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let text = try recognizeInSubprocess(image)
                DispatchQueue.main.async { completion(.success(text)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func recognizeInSubprocess(_ image: CGImage) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliplite-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw OCRError.pngEncodeFailed }
        try png.write(to: url)

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
        DispatchQueue.global().asyncAfter(deadline: deadline) { [weak p] in
            if p?.isRunning == true { p?.terminate() }
        }

        p.waitUntilExit()
        outSemaphore.wait()
        errSemaphore.wait()

        guard p.terminationStatus == 0 else {
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            throw OCRError.workerFailed(status: Int(p.terminationStatus), stderr: stderr)
        }
        return (String(data: outData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 同步识别：供 `--ocr-worker` 子进程直接调用。
    static func perform(_ image: CGImage) throws -> String {
        var text = ""
        let request = VNRecognizeTextRequest { req, _ in
            text = ((req.results as? [VNRecognizedTextObservation]) ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return text
    }
}

enum OCRError: Error {
    case pngEncodeFailed
    case noExecutable
    case workerFailed(status: Int, stderr: String = "")
}

/// 子进程入口：从 PNG 路径惰性加载 CGImage。
enum OCRWorker {
    static func loadImage(path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let src = CGImageSourceCreateWithURL(url, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
