#!/bin/bash
# 构建可分发 DMG。产物：dist/ClipLite-<version>.dmg，并打印 sha256。
#
# 签名策略（自动选择）：
#   - 设了 CLIPLITE_SIGN_IDENTITY（形如 "Developer ID Application: 名字 (TEAMID)"）
#       → 用该 Developer ID + Hardened Runtime + 时间戳签名（可公证）。
#   - 否则回退本地稳定身份 "SnapLite Dev"，再退 ad-hoc（仅自测/自用）。
# 公证（可选）：需 Developer ID 签名 + 下列任一凭证：
#   A) App Store Connect API Key： APPLE_KEY_ID / APPLE_ISSUER_ID / APPLE_API_KEY_P8 (或 _B64)
#   B) notarytool 已存钥匙串配置：  CLIPLITE_NOTARY_PROFILE=<profile 名>
# 未配置凭证则跳过公证，仅本地/开发用。
set -e
cd "$(dirname "$0")/.."

VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
BUNDLE_ID="com.lianyi.cliplite"
APP="build/ClipLite.app"
ENT="Resources/ClipLite.entitlements"
STAGE="build/dmg-staging"
OUT="dist/ClipLite-${VER}.dmg"

echo "1/4 编译 release（v${VER}）…"
swift build -c release --product ClipLite

echo "2/4 组装并签名 .app…"
make app   # 复用 Makefile 组装：生成 icns、拷贝 ClipLiteMenuBar.svg、资源、PkgInfo，并完成本地签名

if [ -n "${CLIPLITE_SIGN_IDENTITY:-}" ]; then
  echo "  → Developer ID 签名（Hardened Runtime + 时间戳）：${CLIPLITE_SIGN_IDENTITY}"
  codesign --force --options runtime --timestamp \
           --entitlements "$ENT" --sign "$CLIPLITE_SIGN_IDENTITY" \
           --identifier "$BUNDLE_ID" "$APP"
else
  echo "  → 沿用 make app 的本地/回退签名（未配置 Developer ID）"
fi
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -1 || true

echo "3/4 打包 DMG…"
rm -rf "$STAGE"; mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/ClipLite.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -quiet -volname ClipLite -srcfolder "$STAGE" -ov -format UDZO "$OUT"
rm -rf "$STAGE"

echo "4/4 公证（notarization）…"
NOTARIZED=0
if [ -n "${CLIPLITE_SIGN_IDENTITY:-}" ]; then
  if [ -n "${APPLE_KEY_ID:-}" ] && [ -n "${APPLE_ISSUER_ID:-}" ] && { [ -n "${APPLE_API_KEY_P8:-}" ] || [ -n "${APPLE_API_KEY_P8_B64:-}" ]; }; then
    KEY="${TMPDIR:-/tmp}/appkey.p8"
    if [ -n "${APPLE_API_KEY_P8:-}" ]; then printf '%s' "$APPLE_API_KEY_P8" > "$KEY"
    else printf '%s' "$APPLE_API_KEY_P8_B64" | base64 --decode > "$KEY"; fi
    chmod 600 "$KEY"
    xcrun notarytool submit "$OUT" --key "$KEY" --key-id "$APPLE_KEY_ID" --issuer "$APPLE_ISSUER_ID" --wait
    rm -f "$KEY"
    NOTARIZED=1
  elif [ -n "${CLIPLITE_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$OUT" --keychain-profile "$CLIPLITE_NOTARY_PROFILE" --wait
    NOTARIZED=1
  fi
fi
if [ "$NOTARIZED" = "1" ]; then
  xcrun stapler staple "$OUT"
  xcrun stapler validate "$OUT" >/dev/null
  echo "  ✔ 已公证并装订（stapled）"
else
  echo "  ⚠ 跳过公证（未配置 Developer ID/凭证）。产物仍可本地使用。"
fi

SHA="$(shasum -a 256 "$OUT" | awk '{print $1}')"
echo
echo "✔ $OUT  ($(du -h "$OUT" | awk '{print $1}'))"
echo "  sha256: $SHA"
echo "$SHA" > "$OUT.sha256"
