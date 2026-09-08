import AppKit

// OCR 子进程：读 PNG 路径 → Vision 同步识别 → print 文本到 stdout → 退出。
// 主进程通过 fork 本二进制 + 此 flag 隔离 Vision 模型内存（~52MB 随子进程 exit 回收）。
// 放最前：子进程不需要 NSApplication，避免拉起 AppKit 重资源。
if let i = CommandLine.arguments.firstIndex(of: "--ocr-worker"), i + 1 < CommandLine.arguments.count {
    let pngPath = CommandLine.arguments[i + 1]
    if let img = OCRWorker.loadImage(path: pngPath) {
        do {
            let text = try VisionOCR.perform(img)
            print(text)
            exit(0)
        } catch {
            FileHandle.standardError.write("OCR worker failed: \(error)\n".data(using: .utf8) ?? Data())
        }
    } else {
        FileHandle.standardError.write("OCR worker: 无法加载图片 \(pngPath)\n".data(using: .utf8) ?? Data())
    }
    exit(1)
}

#if !RELEASE_BUILD
// 自测模式：截屏 → 裁剪中心区域 → 写 PNG → 打印内存，用于命令行验证
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

// 内存诊断：真实截屏→标注→贴图→关闭全链路 RSS/deinit 观察
if CommandLine.arguments.contains("--memtest") {
    MemTest.run()
    exit(0)
}
#endif

// 自动化触发：向运行中的实例发通知执行动作（capture / pin / settings）。无需任何系统权限。
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--trigger"), i + 1 < args.count {
    DistributedNotificationCenter.default().post(name: .init("\(Bundle.main.bundleIdentifier ?? "com.lianyi.cliplite.dev").trigger"),
                                                  object: nil, userInfo: ["action": args[i + 1]])
    Thread.sleep(forTimeInterval: 0.6)   // 让异步 post 有机会投递给常驻实例
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 无 Dock 图标、无前台焦点
app.run()
