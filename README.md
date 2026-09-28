# ClipLite

> 一款追求**极低内存占用**的 macOS 截图 / 贴图 / 标注 / OCR 小工具。

用 **纯 Swift + AppKit、零第三方依赖**从零实现。刚启动空闲物理内存约 **8MB**（长期使用后为**有界平台值**，非累积泄漏，见[内存表现](#内存表现)），功能覆盖截图、贴图、标注、离线 OCR。

## 安装

**Homebrew（推荐）**

```bash
brew tap L14nY1Wang/cliplite
brew install --cask cliplite
```

**下载 DMG**

到 [Releases](https://github.com/L14nY1Wang/ClipLite/releases) 下载 `ClipLite-<版本>.dmg`，打开后把 ClipLite 拖进 Applications。

> 本版本默认使用 ad-hoc 签名、未做 Apple 公证。首次打开若被 Gatekeeper 拦截：在 App 上**右键 → 打开**，或在「终端」执行 `xattr -dr com.apple.quarantine /Applications/ClipLite.app`。

**从源码构建**见下方「构建与运行」。

## 功能

- **截图**：`⌥1` 进入整屏截图，支持鼠标框选、悬停高亮并点选整个窗口、放大镜取色、窗口边界自动吸附。
- **蓝色选取框**：框选后以半透明蒙层覆盖全屏，中间蓝框可**拖动移动 / 8 向手柄缩放**，框外不误触发；工具条实时跟随蓝框。
- **标注**：矩形、椭圆、箭头、画笔、文字、**数字序号**（点击自动递增 1·2·3…）、马赛克，多种配色。
- **完成**：回车 / `Esc` = 带标注裁剪并**写入剪贴板**；工具条另有「复制 / 保存 PNG / 贴图 / OCR」；`撤销` 可逐步回退（含序号回收）。
- **贴图**：置顶可缩放图片窗；拖主体移动、拖右下角手柄**等比缩放**、双击关闭；右键菜单含识别文字 / 复制 / 透明度滑条 / 阴影；`⌥2` 直接把剪贴板内容贴图（位图，或在 Finder 里复制的图片文件）。
- **OCR**：调用系统 **Vision** 框架离线识别（中/英），结果以可划选面板嵌在截图/贴图下方；无需联网、无任何 API 费用。
- **设置**：菜单栏「设置…」可自定义截图/贴图**热键**、开关**开机自启**。

## 系统要求

- macOS **14.0** 或更高（使用 ScreenCaptureKit、Vision）。
- 首次运行需在 **系统设置 → 隐私与安全性 → 录屏与系统录音** 中勾选 ClipLite（改 bundle id / 重签名后需重新授权一次）。

## 升级后无法截图

发布版目前默认使用 **ad-hoc 签名、未公证**。升级后代码指纹变化，或之前运行过使用同一 bundle id 的本地签名版本，都可能使旧录屏授权失效；设置里已勾选也可能需要重新授权。

1. 从菜单栏选择 **「重置录屏授权并重启」** —— 它等价于下面的命令并会自动重启本应用。想手工做也可以：

   ```bash
   tccutil reset ScreenCapture com.lianyi.cliplite
   open /Applications/ClipLite.app
   ```

2. 在 **系统设置 → 隐私与安全性 → 录屏与系统录音** 中允许 ClipLite（也可从菜单栏「屏幕录制权限…」进入）。
3. 授权后**完全退出 ClipLite，再手动打开 `/Applications/ClipLite.app`**，然后尝试截图。

后续 ad-hoc 版本升级仍可能需要重新授权。不要用开发构建覆盖 `/Applications/ClipLite.app`；新版源码构建使用独立的 `com.lianyi.cliplite.dev` 身份和「ClipLite Dev」显示名，与发布版分别授权。两版默认热键相同，使用时请只运行其中一版。

## 构建与运行

需要 Command Line Tools（`xcode-select --install`）或 Xcode，无需 `.xcodeproj`。

```bash
make                # 编译 release 配置，组装开发版 build/ClipLite.app（ClipLite Dev）
open build/ClipLite.app
```

其他命令：

```bash
make selftest       # 命令行自测：截屏 → 裁剪 → /tmp/cliplite-selftest.png → 打印内存
make grant          # 直接打开「录屏与系统录音」授权页
make reset-perm     # 仅重置开发版 com.lianyi.cliplite.dev 的屏幕录制授权
make dmg            # 发布版 build/release/ClipLite.app → dist/*.dmg；默认 ad-hoc
make clean
```

发布、Developer ID 签名与公证、GitHub Actions 及 Homebrew tap 的完整流程见 [docs/RELEASE.md](docs/RELEASE.md)。

## 开发版减少「重复授权」（可选，一次性）

macOS 的 ad-hoc 临时签名会随代码变化改变指纹，可能需要重新授权。下面的脚本为**开发版**创建稳定的本地签名身份 `SnapLite Dev`，`make app` 会自动选用它；发布脚本不会读取该身份，仍默认使用 ad-hoc。需要 Developer ID 发布时显式设置 `CLIPLITE_SIGN_IDENTITY`，并另配公证凭证。签名或校验失败会中止构建。

```bash
bash scripts/make-identity.sh        # 在你自己的「终端」里运行，按提示输入 Mac 登录密码
make reset-perm && make app && open build/ClipLite.app
```

首次签名若弹出「codesign 想要使用密钥 SnapLite Dev」，点 **始终允许**。开发版首次需单独授权；保持同一签名身份后，通常可跨重编译保留授权。

## 快捷键

| 操作 | 默认 |
|---|---|
| 截图 | `⌥1` |
| 贴图（剪贴板内容） | `⌥2` |
| 完成标注并复制 | 回车 / `Esc` |

（可在菜单栏「设置…」中自定义热键，无需改代码。）

## 内存表现

**刚启动空闲**常驻物理占用约 **8 MB**（Activity Monitor 口径；`RSS` 约 32 MB 含共享的系统框架，不代表真实负担）。

使用过后**不会回到 8 MB**，而是回落到该使用画像的**饱和平台**：单屏小图约 20 MB，多屏 4K + 大图贴图可到 ~75 MB。此后**重复使用不再增长**（实测 20 轮，前 10 轮涨 14 MB、后 10 轮仅涨 0.4 MB）——这是 AppKit/图形栈与 malloc 的**有界缓存**，不是累计泄漏。详见 [docs/MEMORY-AUDIT.md](docs/MEMORY-AUDIT.md) §4.6。

**截图峰值随显示器数量增长**：三屏（4K 外接 + 内建 + Sidecar）实测 **149.6 MB**（其中整屏 `CGImage` 只占 +1.3 MB，主因是各屏覆盖窗的 backing store），框选结束即全回收。见 §4.5。

复现：`make app && open build/ClipLite.app`，再 `bash scripts/memaudit.sh`。完整测量方法与逐场景分析见 [docs/MEMORY-AUDIT.md](docs/MEMORY-AUDIT.md)。

## 已知限制

- **不支持跨屏框选**：框选范围限于起手所在的那一块屏，光标移到副屏不会延续选区（各屏覆盖层互相独立）。想要整屏，直接按回车。
- **仅 Apple Silicon（arm64）**：未提供 Intel 版本。
- **ad-hoc 签名、未公证**：首次打开需**右键 → 打开**；分享给别人时对方同样会遇到这个提示。

## 目录结构

```
Sources/ClipLite/
├── App/       入口、AppCoordinator、菜单栏、热键(Carbon)、设置项、自测、单实例
├── Capture/   ScreenCaptureKit 截屏、选区窗口/视图（框选/吸附/放大镜/取色）
├── Annotate/  标注元素、可拖放蓝色选区画布、工具条、大小子条、合成渲染
├── Pin/       贴图窗口（置顶、等比缩放、菜单内透明度）
├── OCR/       Vision 识别 + 可划选结果面板
├── Settings/  设置窗口（热键自定义 + 开机自启）
└── Output/    剪贴板读写
Tests/ClipLiteTests/  单元测试（缩放几何 / 命中区 / 设置往返），CI 跑 `swift test`
docs/          内存审计报告等
```

## 隐私

完全本地运行——**不联网、不上传、不收集**任何数据；OCR 由系统内置 Vision 离线完成；唯一需要的是系统级「屏幕录制」权限。

## 许可

[MIT](LICENSE)
