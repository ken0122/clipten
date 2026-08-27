#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/ClipTen.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp ".build/release/ClipTen" "$CONTENTS_DIR/MacOS/ClipTen"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$CONTENTS_DIR/MacOS/ClipTen"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
