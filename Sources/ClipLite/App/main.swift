import AppKit

// 自测模式：截屏 → 裁剪中心区域 → 写 PNG → 打印内存，用于命令行验证
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

// 自动化触发：向运行中的实例发通知开始截图（无需任何系统权限）
if CommandLine.arguments.contains("--trigger-capture") {
    DistributedNotificationCenter.default().post(name: .init("com.lianyi.cliplite.trigger"),
                                                  object: nil, userInfo: ["action": "capture"])
    // post 是异步的，发进程需存活片刻，否则消息可能来不及投递给常驻实例
    Thread.sleep(forTimeInterval: 0.5)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 无 Dock 图标、无前台焦点
app.run()
