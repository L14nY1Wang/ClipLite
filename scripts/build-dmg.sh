#!/bin/bash
# 构建可分发 DMG。产物：dist/ClipLite-<version>.dmg，并打印 sha256。
#
# 签名策略（自动选择）：
#   - 设了 CLIPITE_SIGN_IDENTITY（形如 "Developer ID Application: 名字 (TEAMID)"）
#       → 用该 Developer ID + Hardened Runtime + 时间戳签名（可公证）。
#   - 否则回退本地稳定身份 "SnapLite Dev"，再退 ad-hoc（仅自测/自用）。
# 公证（可选）：需 Developer ID 签名 + 下列任一凭证：
#   A) App Store Connect API Key： APPLE_KEY_ID / APPLE_ISSUER_ID / APPLE_API_KEY_P8 (或 _B64)
#   B) notarytool 已存钥匙串配置：  CLIPITE_NOTARY_PROFILE=<profile 名>
# 未配置凭证则跳过公证，仅本地/开发用。
set -e
cd "$(dirname "$0")/.."

VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
BUNDLE_ID="com.lianyi.cliplite"
BIN=".build/release/ClipLite"
APP="build/ClipLite.app"
ENT="Resources/ClipLite.entitlements"
STAGE="build/dmg-staging"
OUT="dist/ClipLite-${VER}.dmg"

echo "1/4 编译 release（v${VER}）…"
swift build -c release --product ClipLite

echo "2/4 组装并签名 .app…"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClipLite"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -n "${CLIPITE_SIGN_IDENTITY:-}" ]; then
  echo "  → Developer ID 签名（Hardened Runtime + 时间戳）：${CLIPITE_SIGN_IDENTITY}"
  codesign --force --options runtime --timestamp \
           --entitlements "$ENT" --sign "$CLIPITE_SIGN_IDENTITY" \
           --identifier "$BUNDLE_ID" "$APP"
else
  LOCAL_ID="$(security find-identity -v -p codesigning ~/Library/Keychains/login.keychain-db 2>/dev/null \
             | grep -m1 '"SnapLite Dev"' | sed -E 's/.*"([^"]+)".*/\1/')"
  SIGN="${LOCAL_ID:--}"
  echo "  → 本地/回退签名：${LOCAL_ID:-ad-hoc}"
  codesign --force --sign "$SIGN" --identifier "$BUNDLE_ID" "$APP"
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
if [ -n "${CLIPITE_SIGN_IDENTITY:-}" ]; then
  if [ -n "${APPLE_KEY_ID:-}" ] && [ -n "${APPLE_ISSUER_ID:-}" ] && { [ -n "${APPLE_API_KEY_P8:-}" ] || [ -n "${APPLE_API_KEY_P8_B64:-}" ]; }; then
    KEY="${TMPDIR:-/tmp}/appkey.p8"
    if [ -n "${APPLE_API_KEY_P8:-}" ]; then printf '%s' "$APPLE_API_KEY_P8" > "$KEY"
    else printf '%s' "$APPLE_API_KEY_P8_B64" | base64 --decode > "$KEY"; fi
    chmod 600 "$KEY"
    xcrun notarytool submit "$OUT" --key "$KEY" --key-id "$APPLE_KEY_ID" --issuer "$APPLE_ISSUER_ID" --wait
    rm -f "$KEY"
    NOTARIZED=1
  elif [ -n "${CLIPITE_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$OUT" --keychain-profile "$CLIPITE_NOTARY_PROFILE" --wait
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
