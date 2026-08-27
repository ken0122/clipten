#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/ClipTen.app"
CONTENTS_DIR="$APP_DIR/Contents"
GENERATED_ASSET_DIR="$PROJECT_DIR/.build/generated-assets"
ICONSET_DIR="$GENERATED_ASSET_DIR/AppIcon.iconset"

cd "$PROJECT_DIR"
swift build -c release
mkdir -p "$ICONSET_DIR"
".build/release/ClipTenIconGenerator" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$GENERATED_ASSET_DIR/AppIcon.icns"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp ".build/release/ClipTen" "$CONTENTS_DIR/MacOS/ClipTen"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$GENERATED_ASSET_DIR/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
chmod +x "$CONTENTS_DIR/MacOS/ClipTen"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
