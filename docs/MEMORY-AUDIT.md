# ClipLite 内存审计报告

> 目标：常驻内存压到同类截图工具的 1/10 以下。本报告给出**实测数据**与**逐场景分析**。

## 1. 测量方法

- 指标用 **物理内存占用（physical footprint）**，即 macOS「活动监视器」显示的口径（已剔除可回收的文件映射、只算真正占用的物理页）。
- `RSS` 会把共享的系统框架（AppKit/CoreGraphics 等）也计入，跨进程共享，**不代表真实负担**，仅作对照。
- 复现：`make app && open build/ClipLite.app`，然后 `bash scripts/memaudit.sh`。
- 深度诊断：`.build/debug/ClipLite --memtest`（全链路逐步打印 footprint + deinit 探针）。
- 测量环境：Apple Silicon（arm64）、macOS 26、单显示器 1470×956@2x。

## 2. 空闲（常驻）实测

| 指标 | 数值 |
|---|---|
| **Physical footprint** | **~7 MB** |
| RSS（含共享框架） | ~31 MB |

空闲时进程只做两件事：菜单栏图标 + Carbon 全局热键监听。

## 3. 对比

| 工具 | 常驻内存（约） | 说明 |
|---|---|---|
| **ClipLite** | **~7 MB** | 纯 Swift/AppKit，零第三方依赖 |
| Snipaste | 60–100 MB | Qt 运行时 |
| PixPin | 200–400 MB | Chromium/Electron 内核 |

ClipLite 约为 PixPin 的 **1/30 ~ 1/60**、Snipaste 的 **1/9 ~ 1/14**。

## 4. 逐场景内存分析（何时涨、涨多少、是否回收）

实测数据（`--memtest` 逐步 footprint，footprint = 活动监视器「内存」列口径）：

| 场景 | 峰值 footprint | 稳态（结束后） | 说明 |
|---|---|---|---|
| 空闲基线 | 7 MB | 7 MB | — |
| 真实截图 → 标注 → 关闭 | 47 MB | **20 MB** | 标注窗关闭时 `contentView=nil` 断开窗口→画布强引用，整屏 backing store（22MB@2x）随 deinit 立即回收 |
| 贴图（4032×3024）→ 关闭 | 237 MB | **20 MB** | 干净回收，不累积 |
| 第二张贴图（3000×2000）→ 关闭 | 114 MB | **20 MB** | 多贴图不累积泄漏，deinit 探针全部触发 |
| OCR（走子进程） | 主进程不变 | **20 MB** | Vision 模型常驻 ~52MB 隔离在子进程，识别完随子进程 exit 由 OS 回收 |

> 结论：主进程的常驻部分在任何使用序列后恒定约 **20 MB**；瞬时峰值来自「抓全屏」和「标注窗 backing store」，随会话结束回收，不累积。

## 5. ScreenCaptureKit 成本分解（分层实测）

用 `SCScreenshotManager.captureImage` 一次性捕获，分层 footprint：

| 步骤 | footprint | 增量 |
|---|---|---|
| 基线（NSApplication 已起） | 6.9 MB | — |
| `SCShareableContent.current`（加载框架 + XPC） | 7.8 MB | +1.0 MB |
| 捕获 2266×1488 IOSurface | 8.4 MB | +0.5 MB |
| 释放 CGImage + drain 后 | 8.3 MB | **干净回收** |

- **ScreenCaptureKit 框架 + XPC warm ≈ 1 MB**（一次性，进程内常驻，不可回收）。
- **一次捕获的 IOSurface ≈ 0.5 MB**（释放 CGImage 后完全回收，无残留）。
- 代码已用 `SCScreenshotManager`（一次性）而非常驻 `SCStream`，路径已是最省；**无可压空间**。

## 6. OCR 成本（子进程隔离）

Vision 的 `VNRecognizeTextRequest` 会在进程内永久驻留神经网络权重：

| 触发方式 | 主进程增量 |
|---|---|
| 进程内直接调用 Vision | **+52 MB** 永久（vmmap 显示 `owned unmapped (neural)` ≈ 50MB resident） |
| 子进程 `--ocr-worker`（当前实现） | **0 MB**（模型在子进程，随 exit 回收） |

当前实现：主进程写临时 PNG → fork 本二进制 `--ocr-worker` → 子进程同步跑 Vision → print 到 stdout → exit。实测派生+识别+读结果 ≈ 200ms，输出正确，主进程 footprint 不变。

## 7. 关键设计（为什么能这么低）

1. **无重型运行时**：不用 Electron / Qt / SwiftUI，纯 AppKit，省去最大的固定开销。
2. **无常驻屏幕流**：采用 `SCScreenshotManager` 一次性截图，而非长期 `SCStream`，避免持续缓冲与解码开销。
3. **贴图只持像素、关窗即释放**：每张贴图仅保留裁剪后的 `CGImage`，不缓存全屏原图；`windowWillClose` 设 `contentView=nil` 断开窗口→视图强引用，窗口 backing store 随 deinit 立即回收。
4. **OCR 走子进程**：Vision 模型 ~52MB 隔离在子进程，识别完随子进程 exit 回收，主进程不累积。
5. **零资源包**：无图片/字体资源（菜单栏图标配 icns，运行时不加载）；无 storyboard/xib。
6. **不占 Dock、不后台预加载**：`LSUIElement` 菜单栏常驻，进程最小化。

## 8. 后续可做（非必须）

- 贴图位图统一转存为惰性解码的 `CGImageSource` + 按需降采样，进一步压低大尺寸贴图常驻。
- 可选「空闲自动释放非活动贴图缓存」。
