import Vision
import AppKit

/// 系统内置 Vision OCR：离线、免费、无 key。中英文混排。
enum VisionOCR {
    static func recognize(_ image: CGImage, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var text = ""
            let request = VNRecognizeTextRequest { req, _ in
                text = ((req.results as? [VNRecognizedTextObservation]) ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                NSLog("VisionOCR: \(error)")
            }
            DispatchQueue.main.async { completion(text) }
        }
    }
}
