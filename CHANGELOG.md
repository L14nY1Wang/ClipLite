# 更新日志

本文件记录 ClipLite 每个版本的显著变更。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [未发布]

OCR 改为「图片原位文字叠加层 + 就地划选复制」，删除独立结果弹窗。

### 新增
- **OCR 逐字选择**：数据粒度从「行」下沉到「字符」——`VisionOCR` 用 `VNRecognizedText.boundingBox(for:)` 逐字符取归一化坐标框（accurate 模式下中文为字符级、英文为词级，Apple 文档明示；空格无框会跳过）。拖拽 marquee 只框住「字符框与选框重叠」的字符，不再整行点亮；复制结果按行序拼接、行尾补 `\n`。
- **隐藏叠字**：`H` 键（截图模式）/ 右键菜单「隐藏叠字」（贴图模式）切换「只看原图」。隐藏后不画识别文字、只保留选中区域的强调色高亮，划选与复制完全不受影响——解决了「叠字盖住原图看不清」的问题。**默认即为隐藏**：叠字只是辅助核对，原图才是用户要看的内容。
### 修复
- **水平/竖直拖拽选不中文字**：marquee 有一条边为 0 时 `CGRect.intersects` 因零面积交集返回 false——用户横着拖选一个字都选不中（实测踩到）。改为把零厚度的边当**线段**处理（与该边重叠即算相交），单击（两边都为 0）仍退化为点包含。

### 变更
- **去掉 OCR 底部提示条**：原「拖动选择文字 · ↩/⌘C 复制 · …」pill 常驻遮挡图片底部，复制成功的 flash 提示也一并移除（剪贴板写入本身即反馈）。`drawPill` 及 `hint`/`flash` 参数随之删除。
- **OCR 结果面板删除**：`Sources/ClipLite/OCR/OCRResultPanel.swift`（`NSPanel` + `NSTextView` 弹窗）整体删除，改由 `OCRTextOverlay` 在图片原位绘制；截图/贴图两个宿主各少一个可抢焦点的窗口。
- **OCR 子进程协议**：stdout 由纯文本改为 JSON 行数组（携带归一化坐标框），父进程 `VisionOCR.recognize` 返回 `[OCRLine]`。
- **`PinView` 补 `acceptsFirstMouse`**：应用非激活时 AppKit 会把第一个左键 `mouseDown` 用于激活窗口，贴图视图此前收不到首次点击（拖拽正常是窗口级 `isMovableByWindowBackground` 的假象）——点一下文字行/双击复制都没反应。与标注画保持一致。
- **OCR 子进程串行化**：同一时刻只跑一个 Vision 子进程，避免连续识图时多个子进程同时驻留、把内存与 CPU 峰值叠起来。
- **保存 PNG 改直写，且改为弹出保存面板后才渲染**：用户取消面板时不再白渲染一张标注位图。
- 标注画笔草稿直接改 `draft.points` 存储属性，去掉每帧整份拷贝数组（长笔画由 O(n²) 降为 O(n)）。
- **保存面板 / 失败告警被全屏标注窗挡住**：告警窗层级 +1，不再被覆盖层压在下面。
- **`⌥2` 贴超大图手柄跑到屏幕外**：新窗口先钳到所在屏可见区域并等比缩小，右下角缩放柄始终可用。
- **F 键热键标签显示为 `Key96`**：`HotKeyLabel` 昔用 `kVK_F1…kVK_F12` 区间判断，而 F 键物理码非连续（F5=96、F9=101…），区间恒为空；改为显式查表。
- **⌥1 后按 `Esc`/回车无反应**：`accessory` 应用不会因弹窗而自动成为前台。从别的应用触发截图时，本进程不是活跃应用，`Esc`/回车全部发给此前的前台应用——覆盖层在屏但**关不掉、也无法完成**，只能靠点击。`present()` 与标注层 `show()` 补 `NSApp.activate(ignoringOtherApps: true)`（`showFailure` 一直有这句，主路径漏了）。A/B 实测：无此行 149.7MB 不回落，有此行 `Esc` 后回落到 18.5MB。
- **OCR「复制全部」可能复制出空串**：原用 `textView.string == "未识别到文字"` 判定占位，截图里真印着这六个字时真实结果会被当占位丢弃。改用 `isPlaceholder` 标志。
- **设置窗开过一次后常驻不释放**：`settingsWC` 为 `lazy var` 强持有，关窗只 `orderOut`，窗口与整个视图树一直背着。改为懒建 + `windowWillClose` 时经 `onClose` 回调置 nil。
- **标注会话中再按 ⌥1 会锁屏（只能强退）**：`startCapture` 只 guard `selection`，新会话照常开始，`annotation = ann` 直接顶掉旧控制器。旧标注窗从不 `close()`、工具条/大小条从不 `orderOut`（清理只有 `windowWillClose` 一条路），而旧控制器释放后 `canvas.windowController`（weak）与工具条 `[weak self]` 闭包全变 nil——旧窗既关不掉也不再响应，`.screenSaver` 层连菜单栏一起盖住。已画标注同时无声丢失。改为标注会话中也忽略 ⌥1，`didFinishSelection` 另加「先关再替换」兜底。
- **文字工具输完点工具条，文字被丢弃且画布按键全失效**：工具条是 nonactivating 面板，点它不会自动结束字段编辑。原 `onSelectTool` 只切 `currentTool`，编辑器残留、键盘焦点仍在输入框——此后画布 Esc/回车/Delete 全部失效，再按 Esc 走 `cancelOperation` 把刚输的文字直接丢掉。新增 `switchTool`，切换前先 `commitTextEditorIfNeeded`。
- **OCR 面板弹出后按回车/Esc 无反应**：`OCRResultPanel.show` 用 `makeKeyAndOrderFront` 抢走 key，标注画布失去键盘焦点，用户必须先用鼠标点一下画布才能继续。改为 `orderFrontRegardless`（面板是 `.nonactivatingPanel`，按钮/划选靠鼠标即可）。
- **马赛克拖出蓝框后块被拉大、非方形、与底图错位**：`buildMosaic` 只按 `rect∩selection` 生成小图，绘制却铺满整个 `rect`。提交与移动两条路径都把 `rect` 收敛到交集，让「生成区」与「绘制区」严格一致。
- **选择工具下无法拖动/缩放蓝框**：与 README「蓝框可拖动移动 / 8 向手柄缩放」不符。现 select 模式点到空白/边框时回落到蓝框操作（命中元素仍走元素选择，纯增量）。
- **文字提交存在重入隐患**：`textEditor = nil` 原排在 `removeFromSuperview()` 之后，若移除仍为 first responder 的控件时同步回调 `controlTextDidEndEditing`，会把同一条文字重复入栈。改为先摘引用再移除（提交/取消两条路径）。
- **微拖（≤4pt）后单击完全失灵**：`mouseUp` 未复位 `isDragging`，微拖两个分支都不进，标志残留为 true → 之后 `mouseMoved`/`draw` 的 `!isDragging` 门控失效，吸附高亮不更新、`snappedRect` 停在 nil，用户下一次单击（窗口吸附）无反应，要再点一次才好。
- **主屏左下角幽灵放大镜**：`mouseGlobal` 初值 `.zero` 落在主屏原点，一上屏就画出放大镜且 `globalToPixel` 越界、RGB 恒为 `#000000`，直到该屏收到 mouseMoved 才消失。初值改为真实光标位置。
- **光标栈可能失衡**：`teardown` 原用 `NSCursor.current == .crosshair` 对象比较决定该不该 pop，他处改过光标形状就会漏 pop，crosshair 永久滞留全局光标栈。改用自有 `cursorPushed` 标志。
- **热键事件处理器装失败仍报成功**：`installIfNeeded` 失败只 NSLog，`register` 照返 true，上层不弹提示，用户面对永久按不响的快捷键。改为如实返回失败。
- **开机自启失败零反馈**：原 catch 只 NSLog，用户只看到开关自己跳回去、没有任何解释。现弹告警说明（含「登录项里被禁用过需重新允许」）。
- **`--ocr-worker`/`--trigger` 缺参数时静默启动 GUI**：现报错并 `exit(2)`；另修正 AppDelegate 注释里不存在的 `--trigger-capture`（实为 `--trigger capture`）。
- **OCR 临时 PNG 在父进程被强杀时残留**：正常路径 `defer` 必清，但 SIGKILL 管不到。启动时清扫 1 小时前的 `cliplite-ocr-*.png`（只删旧文件，不碰并发识别中的）。
### 内存（实测）
- 全链路 footprint 与改动前基本持平（三屏覆盖窗峰值 150.1→149.8MB、标注 49.7→50.0MB、贴图大图 240.3→240.1MB）：三屏峰值主要由窗口服务器持有的 backing store 构成，不计入进程 footprint，此前「`isOpaque=true` 可压峰值」的假设经 A/B **证伪**（见 `docs/MEMORY-AUDIT.md` §4.7），已回滚。本次内存收益集中在**瞬时分配**：OCR/保存各去掉一份整幅 `NSBitmapImageRep` 拷贝（4K 选区约 13~48MB），保存面板取消时不再渲染。
### 文档
- `README.md` 更正快捷键口径：「完成标注并复制」只对应回车；`Esc` 实为**放弃标注并关闭**（有选中元素时先取消选中），原文误写为「回车 / `Esc`」。

### 工程
- `Makefile` 新增 `test`（`swift test`）与 `memtest`（`--memtest` 逐步 footprint）目标，删掉 `.PHONY` 中并不存在的 `sign`。
- release 流程在构建 DMG 前先跑 `swift test`（此前全程不跑测试）。
- `.gitignore` 补 `*.p12` / `*.p8` / `*.keychain` / `*.cer` / `*.mobileprovision`，避免发布会话产生的签名凭据被误提交。

## [0.3.0] - 2026-09-28

可靠性与发布工程化：热键失败可见、tap 自动同步、测试基线、文档口径对齐。

### 新增
- **Homebrew tap 自动同步（零 secret）**：`homebrew-cliplite` 新增 `sync-cask.yml`，每 2 小时拉取最新 Release 并按其 asset `digest` 更新 cask，有变化才提交。此前 tap 更新依赖 `TAP_PAT`，而本仓库 `Actions secrets` 为空、该步骤**从 v0.2.0 起一直被跳过**（0.2.0/0.2.1 的 tap 均为手工更新）；现在无需任何凭据。已实测：注入过期的 0.2.0 后触发同步，机器人自动提交回 `cliplite 0.2.1` 且 sha256 正确。
- **菜单「重置录屏授权并重启」**：ad-hoc 升级后录屏授权会失效，原先要用户手敲 `tccutil reset`，现做成菜单一键（内部执行 `tccutil reset ScreenCapture <bundle id>` 后自动重启）。
- **`⌥2` 支持 Finder 里复制的图片文件**：此前 `Clipboard.readImage` 只认剪贴板里的 `tiff`/`png` 位图数据，复制图片文件后按 `⌥2` 静默无事发生；现补 `fileURL` 回退（取第一个可解码的文件）。
- **单元测试基线**：新增 `Tests/ClipLiteTests`（SwiftPM `testTarget`），把原先散落在源码 `#if !RELEASE_BUILD` 里的 3 处 `selfCheck` 迁成 XCTest 用例；CI 新增 `swift test`（原 CI 只编译，不跑任何逻辑校验）。

### 修复
- **热键注册失败不再静默**：`HotKeyCenter.register` 改为返回结果。启动时若有快捷键已被系统或其它 App 占用会弹提示（可一键跳设置）；在设置里改键若注册失败会**回滚**并提示，不再落盘一个按不响的组合。
- **`--trigger` 去掉 0.6s 盲等**：原先靠固定 `Thread.sleep(0.6)` 赌异步投递能赶上，实测（每轮重启实例、逐次判定基线归零）无需等待即可送达，已移除。

### 变更
- 删除源码内 3 处 `selfCheck()`（断言已迁至 `Tests/`），`--selftest` 不再调用它们。

### 文档
- `README.md` 内存口径对齐实测：空闲由「约 **7MB**」更正为「约 **8MB**」，并补充「使用后回落至饱和平台（20–75MB，非累积泄漏）」与「三屏截图峰值 149.6MB」。
- `README.md` 新增「已知限制」：不支持跨屏框选、仅 Apple Silicon（arm64）、ad-hoc 未公证；「升级后无法截图」一节改为指向新的一键菜单。

## [0.2.1] - 2026-09-28

贴图交互修复 + 多屏内存实测。

### 新增
- **贴图「切分贴图」**：右键菜单进入切分模式，框选一块区域生成新贴图（原贴图保留），右键取消；框选区域过小则忽略。
- **设置窗头部显示应用名 + 版本号与真实 app 图标**（dev 构建显示「ClipLite Dev」，便于双开时区分实例）。

### 修复
- **贴图右下角手柄缩放锚点错误**：拖动右下角手柄时，旧实现只改窗口 `size` 而不更新 `origin.y`，导致下边被钉死、**顶边朝反方向飞走**（水平方向本就正确）。改为锚定手柄对角——**左上角**（`minX`/`maxY`），让底边随尺寸移动。几何抽为可测的 `PinView.resizedFrame(from:to:)`，并加 `PinView.selfCheck()` 钉住锚点与宽高比。
- **OCR 空结果不再弹空白面板**：识别不到文字时显示「未识别到文字」占位，避免被误认为功能失效；复制全部时空结果复制空串。

### 变更
- **`--memtest` 补多显示器实测**：场景 A 原先只取 `captureAll().first`，从不持有全部屏位图，与 `SelectionController` 的实际行为不符。现打印 `MEMSTEP[A0]`（屏数 / 各屏像素 / 位图合计 MB）、`MEMSTEP[A0b]`（真实建 N 个选区覆盖窗的 footprint = ⌥1 峰值）、`MEMSTEP[A0c]`（关闭后回收）。
- **`--memtest` 新增场景 F**：重复整条截图流程 20 轮，钉住「重复使用不累积」这一不变量（实测为饱和平台）。

### 文档
- `docs/MEMORY-AUDIT.md` 新增「4.5 多显示器（实测）」：3 屏实测**截图峰值 149.6 MB**（单屏记账的 ~3 倍），并纠正三处直觉——整屏 `CGImage` 走 IOSurface 只占 +1.3 MB（别按位图字节记账）、真正开销是窗口 backing store（≈位图 2.1×）、覆盖窗与标注窗峰值不叠加（`confirm` 先 teardown）。
- `docs/MEMORY-AUDIT.md` 新增「4.6 长期使用：饱和平台，而非恒定值」，**修正原文「稳态恒定 20 MB」的错误说法**：实测重复 20 轮，前 10 轮涨 14 MB、后 10 轮仅涨 0.4 MB（速率掉约 50 倍），是**饱和平台**而非泄漏；平台高度随用过的最大负载而变（6 天长跑实例实测 ~75 MB）。同时把 §2 空闲实测由 ~7 MB 更正为实测 ~8.5 MB。
- `docs/MEMORY-AUDIT.md` §4.6 补「平台由什么构成」分类对照：跑过窗口的实例 vs 全新实例分 region 对照，确认**截图/贴图内存全部回收**，平台来自 **Metal 图形管线编译产物**（`AGX::HAL300::*ProgramVariant`、`RenderPipeline`）与 **malloc 堆高水位**，均有界可复用。

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
