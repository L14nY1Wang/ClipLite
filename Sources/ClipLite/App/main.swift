import AppKit

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

// 自动化触发：向运行中的实例发通知执行动作（capture / pin / settings）。无需任何系统权限。
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--trigger"), i + 1 < args.count {
    DistributedNotificationCenter.default().post(name: .init("com.lianyi.cliplite.trigger"),
                                                  object: nil, userInfo: ["action": args[i + 1]])
    Thread.sleep(forTimeInterval: 0.6)   // 让异步 post 有机会投递给常驻实例
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 无 Dock 图标、无前台焦点
app.run()
