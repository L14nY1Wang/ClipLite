# 更新日志

本文件记录 ClipLite 每个版本的显著变更。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [0.1.1] - 2026-09-07

首个内存治理版本。主线：「贴图后常驻 200MB」根治为主，顺带落地 Phase 2 全量代码审阅修复。

### 修复
- **标注窗关闭后整屏 backing store 不回收**：`AnnotationWindowController.windowWillClose` 设 `contentView=nil`，断开窗口→画布强引用，整屏 backing store（22MB@2x）随控制器 deinit 立即回收。footprint 从 46MB 降到 20MB。
- **贴图关闭后 OCR 面板残留屏幕**：`PinWindowController.windowWillClose` 补 `ocrPanel?.orderOut(nil)`，关闭贴图时连带带走 OCR 面板（可见窗口会被 AppKit 隐式持有，不 orderOut 会永久残留）。
- **热键存储改用原生 NSNumber 键**（旧版 JSON Data 回退兼容），避免 Codable 反序列化失败导致热键丢失。
- **relaunch 改用 `NSWorkspace.shared.open`** 替代 `/bin/sh` 子进程拼接，更稳更省。
- **`onTrigger` 未知/缺失 action 一律忽略**，不再默认触发截图。
- **放大镜网格漏画的横向线补上**（之前只有竖线）。
- **设置窗越层 Auto Layout 约束导致的崩溃**（点设置没反应的根因，前一版本遗留）。
- **环境变量名拼写 `CLIPITE`→`CLIPLITE`**（release.yml / RELEASE.md / build-dmg.sh）。

### 新增
- **OCR 走子进程**：Vision 神经网络权重进程内不可卸载（触发一次永久 +52MB footprint）。改为：主进程写临时 PNG → fork 本二进制 `--ocr-worker` → 子进程同步跑 Vision → print 到 stdout → exit，52MB 随子进程退出由 OS 回收。实测派生+识别+读结果 ≈ 200ms，主进程 footprint 不变。
- **应用图标**：新增 ClipLiteIcon.svg / ClipLiteMenuBar.svg，Makefile 自动生成 icns 并打包。
- **`--memtest` 诊断工具**：真实截屏→标注→贴图→OCR 全链路逐步打印 footprint + deinit 探针，验证对象图无 retain cycle。
- **`SizeLabelPainter`**：抽出选区/标注框的尺寸标签绘制公共逻辑。

### 变更
- **`VisionOCR` 改用标准 `Result<String, Error>` 回调**签名。
- **`OCRResultPanel` 用标准 `.titled`** 替代 `.borderless + .titled` 组合。
- **`entitlements` 精简为最小默认策略**（移除冗余的 `allow-jit` / `get-task-allow` 显式键）。
- **删除未使用代码**：`AnnotationTool.isSizeAdjustable`、`AnnotationSizeBar.setValue/currentValue`、`ScreenCapture.Display.cgRect`、toolbar 的 `tag` 参数、生产代码中的 NSLog trace。

### 性能（内存）
- 空闲 footprint：10.8MB → **7MB**
- 任何使用序列（截图/标注/贴图/OCR）结束后稳态：**恒定 20MB**，不累积
- OCR 模型常驻成本：**0MB**（子进程隔离，原 +52MB）

### 文档
- `docs/MEMORY-AUDIT.md` 重写：纠正「OCR 模型不常驻」「ScreenCaptureKit warm 13MB」两处错误结论，补 ScreenCaptureKit 分层实测数据（框架 warm 1MB / IOSurface 释放后完全回收）。

---

## [0.1.0] - 2026-09-07

初版。截图 / 贴图 / 标注 / OCR 四功能 + 菜单栏常驻 + 全局热键 + 开机自启 + Developer ID 签名公证流程 + Homebrew tap 发布基建。
