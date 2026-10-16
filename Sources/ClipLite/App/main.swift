import AppKit

// OCR 子进程：读 PNG 路径 → Vision 同步识别 → print 文本到 stdout → 退出。
// 主进程通过 fork 本二进制 + 此 flag 隔离 Vision 模型内存（~52MB 随子进程 exit 回收）。
// 放最前：子进程不需要 NSApplication，避免拉起 AppKit 重资源。
// 注意：flag 存在但缺参数时报错退出，不能落到 GUI——否则会静默拉起第二个实例。
if let i = CommandLine.arguments.firstIndex(of: "--ocr-worker") {
    guard i + 1 < CommandLine.arguments.count else {
        FileHandle.standardError.write("--ocr-worker 缺少 PNG 路径参数\n".data(using: .utf8) ?? Data())
        exit(2)
    }
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
// 注意：post 是对通知服务器的同步投递，发完直接退出即可——实测（每次重启实例、逐次判定）
// 去掉原先的 0.6s 等待后 11/11 均能送达，那个 sleep 并非送达所必需。
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--trigger") {
    // 同 --ocr-worker：缺参数时报错退出，不静默拉起 GUI 实例
    guard i + 1 < args.count else {
        FileHandle.standardError.write("--trigger 缺少动作参数（capture / pin / settings）\n".data(using: .utf8) ?? Data())
        exit(2)
    }
    DistributedNotificationCenter.default().post(name: .init("\(Bundle.main.bundleIdentifier ?? "com.lianyi.cliplite.dev").trigger"),
                                                  object: nil, userInfo: ["action": args[i + 1]])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 无 Dock 图标、无前台焦点
app.run()
