#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/InfiniteLife"
BUILD="$ROOT/build"
APP="$BUILD/InfiniteLife.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"
EXECUTABLE="InfiniteLife"

SDK="$(xcrun --show-sdk-path)"
MIN_OS="13.0"
ARCH="$(uname -m)"

echo "==> 使用するSDK: $SDK"
echo "==> 対象アーキテクチャ: $ARCH"

rm -rf "$BUILD"
mkdir -p "$MACOS_DIR" "$RES_DIR"

SOURCES=()
while IFS= read -r f; do
  SOURCES+=("$f")
done < <(find "$SRC" -name '*.swift' | sort)

echo "==> ${#SOURCES[@]}個のSwiftファイルをコンパイルしています..."

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>InfiniteLife</string>
	<key>CFBundleIdentifier</key>
	<string>com.infinitelife.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>InfiniteLife</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

swiftc \
  -sdk "$SDK" \
  -target "${ARCH}-apple-macosx${MIN_OS}" \
  -O \
  -whole-module-optimization \
  -framework AppKit \
  -framework Metal \
  -framework MetalKit \
  -framework QuartzCore \
  -framework CoreVideo \
  -framework IOKit \
  -framework ServiceManagement \
  -framework Security \
  -o "$MACOS_DIR/$EXECUTABLE" \
  "${SOURCES[@]}"

echo -n "APPL????" > "$APP/Contents/PkgInfo"

echo "==> ビルドが完了しました: $APP"
echo "    アプリを開く: open \"$APP\""
echo "    実行ファイルを直接開く: \"$MACOS_DIR/$EXECUTABLE\""
