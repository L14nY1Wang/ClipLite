#!/bin/bash
# 构建可分发的 DMG 安装包。产物：dist/ClipLite-<version>.dmg，并打印其 sha256。
# 用法： bash scripts/build-dmg.sh   （会先执行 make app 生成 build/ClipLite.app）
set -e
cd "$(dirname "$0")/.."

VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
APP="build/ClipLite.app"
STAGE="build/dmg-staging"
OUT="dist/ClipLite-${VER}.dmg"

echo "构建 .app (release, 版本 ${VER})…"
make app >/dev/null

echo "组装 DMG…"
rm -rf "$STAGE"; mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/ClipLite.app"
ln -s /Applications "$STAGE/Applications"        # 拖拽安装快捷方式

rm -f "$OUT"
hdiutil create -quiet -volname "ClipLite" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
rm -rf "$STAGE"

SHA="$(shasum -a 256 "$OUT" | awk '{print $1}')"
SIZE="$(du -h "$OUT" | awk '{print $1}')"
echo "✔ $OUT  (${SIZE})"
echo "  sha256: $SHA"
echo "$SHA" > "$OUT.sha256"
