#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/ClipTen.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_DIR="${CLIPTEN_BUILD_DIR:-$PROJECT_DIR/.build}"
GENERATED_ASSET_DIR="$BUILD_DIR/generated-assets"
ICONSET_DIR="$GENERATED_ASSET_DIR/AppIcon.iconset"

cd "$PROJECT_DIR"
swift build -c release --scratch-path "$BUILD_DIR"
BIN_DIR="$(swift build -c release --scratch-path "$BUILD_DIR" --show-bin-path)"
mkdir -p "$ICONSET_DIR"
"$BIN_DIR/ClipTenIconGenerator" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$GENERATED_ASSET_DIR/AppIcon.icns"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp -X "$BIN_DIR/ClipTen" "$CONTENTS_DIR/MacOS/ClipTen"
cp -X "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -X "$GENERATED_ASSET_DIR/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
chmod +x "$CONTENTS_DIR/MacOS/ClipTen"

# Only our generated bundle: Finder metadata is not part of the application.
xattr -dr com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
