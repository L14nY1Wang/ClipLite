#!/bin/bash
# 构建可分发 DMG。产物：dist/ClipLite-<version>.dmg，并打印 sha256。
#
# 签名策略（显式选择）：
#   - 设了 CLIPLITE_SIGN_IDENTITY（形如 "Developer ID Application: 名字 (TEAMID)"）
#       → 用该 Developer ID + Hardened Runtime + 时间戳签名（可公证）。
#   - 否则固定使用 ad-hoc，不读取本地开发证书。
# 公证（可选）：需 Developer ID 签名 + 下列任一凭证：
#   A) App Store Connect API Key： APPLE_KEY_ID / APPLE_ISSUER_ID / APPLE_API_KEY_P8 (或 _B64)
#   B) notarytool 已存钥匙串配置：  CLIPLITE_NOTARY_PROFILE=<profile 名>
# 未配置凭证则跳过公证，仅本地/开发用。
set -euo pipefail
cd "$(dirname "$0")/.."

VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
BUNDLE_ID="com.lianyi.cliplite"
APP="build/release/ClipLite.app"
ENT="Resources/ClipLite.entitlements"
STAGE="build/dmg-staging"
OUT="dist/ClipLite-${VER}.dmg"

echo "1/4 编译 release（v${VER}）…"
echo "2/4 组装并签名 .app…"
# 发布身份与开发版隔离；即使本机有 SnapLite Dev，也只使用显式指定的签名。
make app APP="$APP" BUNDLE_ID="$BUNDLE_ID" APP_NAME=ClipLite IDENTITY=- SWIFT_FLAGS="-Xswiftc -DRELEASE_BUILD"

if [ -n "${CLIPLITE_SIGN_IDENTITY:-}" ]; then
  echo "  → Developer ID 签名（Hardened Runtime + 时间戳）：${CLIPLITE_SIGN_IDENTITY}"
  codesign --force --options runtime --timestamp \
           --entitlements "$ENT" --sign "$CLIPLITE_SIGN_IDENTITY" \
           --identifier "$BUNDLE_ID" "$APP"
else
  echo "  → ad-hoc 签名（未配置 Developer ID）"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

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

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'notarized=%s\n' "$NOTARIZED" >> "$GITHUB_OUTPUT"
fi

SHA="$(shasum -a 256 "$OUT" | awk '{print $1}')"
echo
echo "✔ $OUT  ($(du -h "$OUT" | awk '{print $1}'))"
echo "  sha256: $SHA"
echo "$SHA" > "$OUT.sha256"
