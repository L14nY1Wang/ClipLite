# 更新日志

本文件记录 ClipLite 每个版本的显著变更。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [0.2.0] - 2026-09-08

标注二次编辑 + 可靠性修复 + 发布工程化。标注元素画完可再选中移动/删除/撤销；修复 OCR 管道死锁与多显示器坐标换算；建立最小 CI 门禁、签名身份隔离，发布二进制剥离诊断代码。

### 新增
- **标注元素二次编辑**：新增选择工具，可点选已绘制的标注元素进行移动、单个删除，配 undo 快照栈；文字标注双击可再次进入编辑。含一系列边界处理（`renderFinal` 前先提交进行中的文字编辑、马赛克移动后重建源、箭头命中区、序号回收等）。
- **最小 CI 门禁**：PR/push 触发编译验证 + 全量脚本语法检查（`bash -n`）+ `concurrency` 自动取消同分支旧 run。
- **录屏授权后自动重试截图**：权限弹窗引导用户去系统设置授权后，轮询 `CGPreflightScreenCaptureAccess`（`didBecomeActive` 时立即加急检查）探测授权完成并自动重试当次截图，5 分钟超时放弃；截图异常（catch）路径不挂自动重试。
- **截图保存增强**：文件名改为可读日期格式（DateFormatter 固定 `en_US_POSIX` locale 保证公历年份）；记忆上次保存目录；保存失败弹提示，不再静默失败。

### 变更
- **诊断代码从发布二进制剥离**：SelfTest / MemTest / deinit 探针改用 `#if !RELEASE_BUILD` 条件编译，发布构建不含诊断代码。
- **发布流程版本一致性校验**：发布脚本比对 Info.plist 版本与 git tag，不一致即中止；DMG 校验改用精确路径。
- **开发版与发布版签名身份隔离**：`make app` 默认构建开发版 `build/ClipLite.app`，bundle id `com.lianyi.cliplite.dev`、显示名「ClipLite Dev」；发布脚本 `scripts/build-dmg.sh` 固定使用 `com.lianyi.cliplite`、产物在 `build/release/ClipLite.app`，默认 ad-hoc 签名，不读取本地 `SnapLite Dev` 身份。两版分别授权，互不影响。
- **DistributedNotification 名称改为跟随 bundle id**：`com.lianyi.cliplite.dev.trigger`（开发版）/ `com.lianyi.cliplite.trigger`（发布版），避免两版实例互相触发。
- **Esc 语义拆分**：标注窗口内 Esc = 放弃并退出、Return = 确认并复制；文字编辑态中 Esc = 取消当前文字编辑（回到标注态），不再一步退出整个窗口。
- **`build-dmg.sh`**：`set -euo pipefail`；`codesign --verify` 失败即中止；向 GitHub Actions 输出 `notarized` 标志，Release 说明按签名/公证状态区分措辞。

### 修复
- **OCR 子进程管道死锁**：子进程输出量大时写满管道缓冲、父进程先 `wait` 后读导致永久阻塞。改为并发排空 stdout/stderr 后再 `wait`，加 30s 超时保护（定时器可取消）与 stderr 捕获；`OCRError` 实现 `LocalizedError`，失败时暴露子进程 stderr 原因。
- **多显示器坐标换算错误**：CG 逻辑点转 AppKit 翻转坐标时按目标屏高度翻转（此前误用主屏）；`backingScaleFactor` 改为按目标屏取值，副屏缩放比不同（如 1x 外接屏）时截图不再错位/错缩放。
- **重启应用「只退不开」**：v0.1.1 的 relaunch 用 `NSWorkspace.shared.open` + `asyncAfter` 延迟打开，但进程 `terminate` 后已不在会话中，open 无效。改为拉起独立 `/bin/sh` 进程，以 `while kill -0 $PID` 轮询等待父进程退出后再 `exec /usr/bin/open`，路径以参数传递避免 shell 插值。
- **截图权限缺失/失败无反馈**：`SelectionController.start` 在权限不足或截图异常时改为弹 `NSAlert`（含「打开录屏设置」按钮），不再静默取消。
- **CHANGELOG 0.1.1 的 relaunch 描述**：原文称「改用 `NSWorkspace.shared.open` 替代 `/bin/sh` 子进程拼接，更稳更省」，实际该方案存在只退不开问题，已由本版本修复回 shell watcher 方式。

---

## [0.1.1] - 2026-09-07

首个内存治理版本。主线：「贴图后常驻 200MB」根治为主，顺带落地 Phase 2 全量代码审阅修复。

### 修复
- **标注窗关闭后整屏 backing store 不回收**：`AnnotationWindowController.windowWillClose` 设 `contentView=nil`，断开窗口→画布强引用，整屏 backing store（22MB@2x）随控制器 deinit 立即回收。footprint 从 46MB 降到 20MB。
- **贴图关闭后 OCR 面板残留屏幕**：`PinWindowController.windowWillClose` 补 `ocrPanel?.orderOut(nil)`，关闭贴图时连带带走 OCR 面板（可见窗口会被 AppKit 隐式持有，不 orderOut 会永久残留）。
- **热键存储改用原生 NSNumber 键**（旧版 JSON Data 回退兼容），避免 Codable 反序列化失败导致热键丢失。
- **relaunch 改用 `NSWorkspace.shared.open`** 替代 `/bin/sh` 子进程拼接，更稳更省。（后证实该方案「只退不开」，已在 [0.2.0] 中改回 shell watcher 等父 PID 退出。）
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
