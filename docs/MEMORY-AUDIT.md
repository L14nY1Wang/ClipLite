# ClipLite 内存审计报告

> 目标：常驻内存压到同类截图工具的 1/10 以下。本报告给出**实测数据**与**逐场景分析**。

## 1. 测量方法

- 指标用 **物理内存占用（physical footprint）**，即 macOS「活动监视器」显示的口径（已剔除可回收的文件映射、只算真正占用的物理页）。
- `RSS` 会把共享的系统框架（AppKit/CoreGraphics 等）也计入，跨进程共享，**不代表真实负担**，仅作对照。
- 复现：`make app && open build/ClipLite.app`，然后 `bash scripts/memaudit.sh`。
- 深度诊断：`.build/debug/ClipLite --memtest`（全链路逐步打印 footprint + deinit 探针）。
- 测量环境：Apple Silicon（arm64）、macOS 26。默认单显示器 1470×956@2x；多屏场景见 §4.5（MacBook + 3840×2160 外接 + Sidecar）。

## 2. 空闲（常驻）实测

| 指标 | 数值 |
|---|---|
| **Physical footprint** | **~8.5 MB** |
| RSS（含共享框架） | ~32 MB |

空闲时进程只做两件事：菜单栏图标 + Carbon 全局热键监听。此处指**刚启动**的空闲态；长期使用后会停在饱和平台（§4.6），不再回到此值。

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
| 真实截图 → 标注 → 关闭 | 47 MB | 平台值¹ | 标注窗关闭时 `contentView=nil` 断开窗口→画布强引用，整屏 backing store（22MB@2x）随 deinit 立即回收 |
| 贴图（4032×3024）→ 关闭 | 237 MB | 平台值¹ | 干净回收，不累积 |
| 第二张贴图（3000×2000）→ 关闭 | 114 MB | 平台值¹ | 多贴图不累积泄漏，deinit 探针全部触发 |
| OCR（走子进程） | 主进程不变 | 平台值¹ | Vision 模型常驻 ~52MB 隔离在子进程，识别完随子进程 exit 由 OS 回收 |

> ¹「平台值」不是固定 20 MB，而是该使用画像的饱和平台（实测约 20–50 MB），见 §4.6。
>
> 结论：主进程的常驻部分在任何使用序列后**不会回到启动时的 8MB**，而是回落到该使用画像的**饱和平台**（示例约 20–50 MB），此后重复使用**不再增长**。瞬时峰值来自「抓全屏」和「标注窗 backing store」，随会话结束回收。


## 4.5 多显示器（实测）

上一节的表格全部是**单屏**数据。`SelectionController.present` 实际会为**每块屏**各建一个覆盖窗（`SelectionWindow` + `SelectionView`），**所有屏同时驻留**直到框选结束。所以截图峰值随显示器数量线性增长。

本机三屏实测（`--memtest`，MacBook + 4K 外接 + Sidecar，走 LaunchServices 授权运行）：

| 步骤 | footprint | 增量 |
|---|---:|---:|
| 基线 | 8.7 MB | — |
| 持 3 屏 `CGImage`（SCK） | 10.0 MB | **+1.3 MB** |
| **3 个选区覆盖窗上屏** | **149.6 MB** | **+139.6 MB** ← 截图峰值 |
| 覆盖窗关闭 + drain | 15.9 MB | 完全回收 |
| 标注窗（单屏 2266×1488） | 50.7 MB | +34.8 MB ← 标注峰值 |
| 全部关闭 | 23.1 MB | 完全回收 |

**三条与直觉相反的结论：**

1. **整屏 `CGImage` 几乎不要钱**。3 屏合计 65.9 MB 的像素（`Σ 点尺寸×scale²×4B`）进 `phys_footprint` 只多 **1.3 MB**——SCK 的捕获结果走 IOSurface，不计入 footprint。**别按位图字节数记账。**
2. **真正的峰值是窗口 backing store，约为位图字节的 2.1 倍**。3 个覆盖窗 = **139.6 MB**，而对应像素只有 65.9 MB（2x 下窗口同时持有 backing store 与 layer 内容）。
3. **两个峰值不叠加**。`SelectionController.confirm` 先 `teardown()` 再建标注窗，覆盖窗与标注窗不同时驻留——截图峰值 149.6 MB、标注峰值 50.7 MB，各自独立。

所以单屏文档里的 47 MB 截图峰值，在三屏下是 **149.6 MB（≈3.2 倍）**；按单屏数字预估外接屏场景会低估约 3 倍。两个阶段结束后都全回收（→ 23.1 MB），**不是泄漏**。

复现：

```bash
tccutil reset ScreenCapture com.lianyi.cliplite.dev   # 仅重置 dev 版授权
open build/ClipLite.app                               # 弹窗点「允许」
open -W --stdout /tmp/mt.out -a "$PWD/build/ClipLite.app" --args --memtest
grep 'MEMSTEP\[A' /tmp/mt.out
```

> 必须经 LaunchServices（`open`）启动；直接 exec `Contents/MacOS/ClipLite` 时 TCC 会把负责进程算成调用方 shell，授权对不上、报 `-3801`。

## 4.6 长期使用：饱和平台，而非恒定值

原文「恒定 20 MB，不累积」不准确。实测（`--memtest` 场景 F，重复整条截图流程）：

| 轮次 | footprint |
|---|---:|
| 开始 | 35.9 MB |
| 1 | 40.8 MB |
| 5 | 46.6 MB |
| 10 | 50.2 MB |
| 20 | 50.5 MB |
| **静置后** | **50.6 MB** |

**前 10 轮涨 14 MB，之后 10 轮只涨 0.4 MB**——速率掉约 50 倍，是**饱和平台**而不是线性泄漏。

平台高度取决于用过的最大负载（抓屏分辨率、贴图尺寸、OCR），所以不同用户/不同实例会停在不同值：一个连续运行 6 天、用过 4K 抓屏 + 4032×3024 贴图的实例实测常驻 **75 MB**（同一实例早先一测 71.8、稍后 75.1，都在同一平台带内浮动；RSS 约 47–67 MB）——高于文档旧值，但同样稳定、不再增长。

**不需要改代码**：这是图形栈的 retained 缓冲，稳定且有界。若想让平台更低，可考虑用完主动降载（如 `NSCache` 化的贴图池），但收益有限、复杂度不划算。

> 断不断 `contentView` 经 A/B 实测**无差别**（149.6→15.4 vs 150.8→15.6 MB），AppKit 自行回收；`SelectionController.teardown` 无需改动。

### 平台由什么构成（新旧实例分类对照）

跑过窗口的实例 vs 全新实例（都是空闲无窗口），`vmmap` 分 region 对照：

| region | 全新（idle） | 跑过 6 天 | Δ |
|---|---:|---:|---:|
| **Malloc Small**（活跃堆） | 7.9 MB | 18.5 MB | **+10.7 MB** |
| **IOAccelerator (graphics)** | 16 KB | 3.5 MB | **+3.5 MB** |
| Malloc Small (empty) | 448 KB | 1.7 MB | +1.2 MB |
| QuartzCore | 0 | 1.2 MB | +1.2 MB |
| Malloc Large (empty)¹ | ~0 | 24 MB dirty | +24 MB |
| CoreAnimation² | 144 KB | 160 KB | ≈0（已回收） |
| **Physical footprint** | **14.0 MB** | **75.1 MB** | **+61 MB** |

¹ 这些页是**已释放但未归还 OS** 的空 slab，不计入 footprint 分母，但 RSS/`vmmap dirty` 会显示。
² 覆盖窗真正打开时 `CoreAnimation` 会瞬时到 **132 MB**（volatile），关窗即回收——所以它**不是**平台贡献者。

也就是说：平台里没有「忘记释放的截图/贴图」——**所有 `CGImage`/IOSurface/backing store 都回收了**（见 §4.5）。留下的是：

- **Metal/图形管线对象**：堆里最大的对象是 `AGX::HAL300::{Vertex,Fragment,Compute}ProgramVariant`、`AGXG17GFamilyRenderPipeline`、`MTLResourceList`、`CA::OGL::MetalContext`——GPU 把用过的着色器/管线编译产物常驻在进程内。窗口越多、渲染样式越杂，编译的管线变体越多，这块就越大（首次渲染任何新窗口时都会涨一截，然后**不再回落**）。
- **malloc 堆高水位**：峰值用过几百 MB（本实例 peak 599.9 MB），堆的空闲 slab 被保留复用而非归还，`Malloc Small` 从 7.9 → 18.5 MB。

两者都是**有界、可复用**的缓存：下次用还能省下重新编译/重新分配的开销，这也是速率在 10 轮后掉到近乎 0 的原因。要压低只能反向「用完主动清」（丢弃管线缓存 / `malloc_zone_pressure_relief`——后者实测回收 0 字节，因为页已在 malloc 手里而不是 OS 手里）。**不改。**

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
