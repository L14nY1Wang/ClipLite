# 签名与公证 / 发布手册（Developer ID + Notarization）

ClipLite 从「自签名」升级到「Apple Developer ID 签名 + 公证」后：Gatekeeper 直接放行、无需右键打开，也才可能被收录进官方 homebrew-cask。

## 0. 前置：Apple 侧准备（一次性）

1. **Apple Developer Program**（$99/年）。
2. **Developer ID Application 证书**：
   - 在 [developer.apple.com](https://developer.apple.com) → Certificates 里，用「证书助理」生成的 CSR 申请 **Developer ID Application** 证书，安装进钥匙串。
   - 导出为 `.p12`（含私钥），记下你设置的导出密码。
3. **App Store Connect API Key**（用于 CI 无人值守公证）：
   - App Store Connect → 用户和访问 → 集成 → 建立 **API**（权限选 Developer）。
   - 记录：`Issuer ID`、`Key ID`，下载 `.p8` 私钥文件。

## 1. 配置 GitHub Secrets（`ClipLite` 仓库 Settings → Secrets → Actions）

| Secret | 值 |
|---|---|
| `DEV_ID_CERT_P12_B64` | `base64 -i dev-id.p12` 的输出 |
| `DEV_ID_CERT_PASSWORD` | 导出 p12 时设置的密码 |
| `APPLE_ISSUER_ID` | API 的 Issuer ID |
| `APPLE_KEY_ID` | API 的 Key ID |
| `APPLE_API_KEY_B64` | `base64 -i AuthKey_XXXX.p8` 的输出 |
| `TAP_PAT` | 可写 `homebrew-cliplite` 的 PAT（自动更新 tap 用；不配则跳过） |

> 不配这些也能发布：CI 会回退到「自签名、未公证」产物。

## 2. 发布流程（自动）

打 tag 即触发 `.github/workflows/release.yml`：
```bash
# 先改 Resources/Info.plist 的 CFBundleShortVersionString，例如 0.1.1
git commit -am "release: 0.1.1" && git tag v0.1.1 && git push origin main v0.1.1
```
CI 会：建临时钥匙串→导入 Developer ID 证书→以 **Hardened Runtime + 时间戳**签名 `.app`→打 DMG→`notarytool` 提交并 `--wait`→`stapler staple`→创建 Release（附公证后的 DMG）→更新 Homebrew tap。

## 3. 本地发布（可选，有证书时）

```bash
export CLIPITE_SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)"
export APPLE_KEY_ID=... APPLE_ISSUER_ID=... APPLE_API_KEY_P8_B64="$(base64 -i ~/AuthKey.p8)"
make dmg         # 自动完成签名 + 公证 + 装订，并打印 sha256
```

## 4. 校验产物

```bash
codesign -dvv2 dist/ClipLite-0.1.0.dmg 2>&1 | head        # 看 Authority=Developer ID Application
spctl -a -vv --type open "build/ClipLite.app"              # 应 accepted（源签名有效）
xcrun stapler validate dist/ClipLite-0.1.0.dmg             # 装订票据 OK
xcrun notarytool history --key-id "$APPLE_KEY_ID" --issuer "$APPLE_ISSUER_ID" --key ~/AuthKey.p8
```

## 5. 备注

- 目前仅 **arm64** 单架构。要发通用包（Intel + Apple Silicon）需 `swift build` 产出两架构后用 `lipo` 合并二进制，再签名；届时 cask 去掉 `arch arm:`、`sha256` 改 `on_macos` 分架构，或用 `.pkg` + `notarytool` 对 pkg 公证。
- 公证只需提交 **DMG**（内含已签名 app）；staple 后离线也能通过 Gatekeeper。
- 进入官方 homebrew-cask 另需按其贡献规范提交 PR，且要求持续公证。
