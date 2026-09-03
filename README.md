# ClipLite

> 一款追求**极低内存占用**的 macOS 截图 / 贴图 / 标注 / OCR 小工具。

用 **纯 Swift + AppKit、零第三方依赖**从零实现。空闲物理内存约 **10MB**（实测 footprint ~9–11MB），而功能覆盖截图、贴图、标注、离线 OCR。

## 功能

- **截图**：`⌥1` 进入整屏截图，支持鼠标框选、悬停高亮并点选整个窗口、放大镜取色、窗口边界自动吸附。
- **蓝色选取框**：框选后以半透明蒙层覆盖全屏，中间蓝框可**拖动移动 / 8 向手柄缩放**，框外不误触发；工具条实时跟随蓝框。
- **标注**：矩形、椭圆、箭头、画笔、文字、**数字序号**（点击自动递增 1·2·3…）、马赛克，多种配色。
- **完成**：回车 / `Esc` = 带标注裁剪并**写入剪贴板**；工具条另有「复制 / 保存 PNG / 贴图 / OCR」；`撤销` 可逐步回退（含序号回收）。
- **贴图**：置顶可缩放图片窗；拖动移动、滚轮缩放、`⌃+滚轮`调透明度、双击关闭、右键菜单；`⌥2` 直接把剪贴板内容贴图。
- **OCR**：调用系统 **Vision** 框架离线识别（中/英），无需联网、无任何 API 费用。

## 系统要求

- macOS **14.0** 或更高（使用 ScreenCaptureKit、Vision）。
- 首次运行需在 **系统设置 → 隐私与安全性 → 录屏与系统录音** 中勾选 ClipLite（改 bundle id / 重签名后需重新授权一次）。

## 构建与运行

需要 Command Line Tools（`xcode-select --install`）或 Xcode，无需 `.xcodeproj`。

```bash
make                # 编译 release + 组装 build/ClipLite.app（自动本地签名）
open build/ClipLite.app
```

其他命令：

```bash
make selftest       # 命令行自测：截屏 → 裁剪 → /tmp/cliplite-selftest.png → 打印内存
make grant          # 直接打开「录屏与系统录音」授权页
make reset-perm     # 清除本 App 的屏幕录制授权记录（授权错乱时用）
make clean
```

## 免「重复授权」（推荐，一次性）

macOS 的 ad-hoc 临时签名会在每次重编译后改变代码指纹，导致屏幕录制权限被反复要求重新授权。运行下面的脚本创建一个**稳定的本地签名身份**，之后授权可跨重编译保留：

```bash
bash scripts/make-identity.sh        # 在你自己的「终端」里运行，按提示输入 Mac 登录密码
make reset-perm && make app && open build/ClipLite.app
```

首次签名若弹出「codesign 想要使用密钥 SnapLite Dev」，点 **始终允许**。此后改代码再 `make app` 不再要求重新授权。

## 快捷键

| 操作 | 默认 |
|---|---|
| 截图 | `⌥1` |
| 贴图（剪贴板内容） | `⌥2` |
| 完成标注并复制 | 回车 / `Esc` |

（键位见 `Sources/ClipLite/App/AppSettings.swift`。）

## 目录结构

```
Sources/ClipLite/
├── App/       入口、AppCoordinator、菜单栏、热键(Carbon)、设置、自测
├── Capture/   ScreenCaptureKit 截屏、选区窗口/视图（框选/吸附/放大镜/取色）
├── Annotate/  标注元素、可拖放蓝色选区画布、浮动工具条、合成渲染
├── Pin/       贴图窗口（置顶、缩放、透明度）
├── OCR/       Vision 识别 + 结果面板
└── Output/    剪贴板读写
```

## 隐私

完全本地运行——**不联网、不上传、不收集**任何数据；OCR 由系统内置 Vision 离线完成；唯一需要的是系统级「屏幕录制」权限。

## 许可

[MIT](LICENSE)
