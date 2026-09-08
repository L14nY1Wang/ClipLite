APP      ?= build/ClipLite.app
BINARY   := .build/release/ClipLite
PLIST    := Resources/Info.plist
BUNDLE_ID ?= com.lianyi.cliplite.dev
APP_NAME  ?= ClipLite Dev

.PHONY: all build app run clean selftest sign dmg

all: app

# dev 构建不传 SWIFT_FLAGS（保留诊断代码）；发布构建传 SWIFT_FLAGS="-Xswiftc -DRELEASE_BUILD" 剥离
build:
	swift build -c release --product ClipLite $(SWIFT_FLAGS)

# 优先使用稳定的本地签名身份（存在则授权可跨重编译保留），否则回退 ad-hoc
IDENTITY  ?= $(shell security find-identity -v -p codesigning ~/Library/Keychains/login.keychain-db 2>/dev/null | grep -m1 '"SnapLite Dev"' | sed -E 's/.*"([^"]+)".*/\1/')
SIGN      := $(if $(IDENTITY),$(IDENTITY),-)

# 组装 .app bundle
app: build
	@rm -rf "$(APP)" /tmp/ClipLite.iconset
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" /tmp/ClipLite.iconset
	@for size in 16 32 128 256 512; do \
		sips -s format png -z $$size $$size Resources/ClipLiteIcon.svg --out /tmp/ClipLite.iconset/icon_$${size}x$${size}.png >/dev/null || exit 1; \
		double=$$((size * 2)); \
		sips -s format png -z $$double $$double Resources/ClipLiteIcon.svg --out /tmp/ClipLite.iconset/icon_$${size}x$${size}@2x.png >/dev/null || exit 1; \
	done
	@iconutil -c icns /tmp/ClipLite.iconset -o "$(APP)/Contents/Resources/ClipLiteIcon.icns"
	@cp Resources/ClipLiteMenuBar.svg "$(APP)/Contents/Resources/ClipLiteMenuBar.svg"
	@cp "$(BINARY)" "$(APP)/Contents/MacOS/ClipLite"
	@cp "$(PLIST)" "$(APP)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier $(BUNDLE_ID)' "$(APP)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c 'Set :CFBundleName $(APP_NAME)' "$(APP)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName $(APP_NAME)' "$(APP)/Contents/Info.plist"
	@printf 'APPL????' > "$(APP)/Contents/PkgInfo"
	@codesign --force --deep --sign "$(SIGN)" --identifier "$(BUNDLE_ID)" "$(APP)"
	@codesign --verify --deep --strict "$(APP)"
	@echo "✔ 构建完成：$(APP)  [签名: $(if $(IDENTITY),$(IDENTITY),ad-hoc 临时——如需免重复授权请运行 scripts/make-identity.sh)]"

run: app
	@open "$(APP)"

# 打开"录屏与系统录音"授权页面，方便勾选 ClipLite
grant:
	@open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

# 清除屏幕录制授权记录（授权错乱/反复弹窗时使用），之后重启 App 会重新干净授权
reset-perm:
	@tccutil reset ScreenCapture "$(BUNDLE_ID)" 2>/dev/null || true
	@echo "已清除 $(BUNDLE_ID) 的屏幕录制授权记录，请重启 ClipLite 后按提示重新授权"

# 构建可分发 DMG（dist/ClipLite-<ver>.dmg）并打印 sha256
dmg:
	@bash scripts/build-dmg.sh

# 端到端自测：截屏 → 裁剪中心 300x150 → 写 PNG 到 /tmp → 打印内存
selftest: app
	@"$(APP)/Contents/MacOS/ClipLite" --selftest

clean:
	@rm -rf build .build
