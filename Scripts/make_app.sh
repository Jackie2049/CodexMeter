#!/bin/bash
# Builds release binary and assembles CodexMeter.app (ad-hoc signed).
# Usage: ./Scripts/make_app.sh [output_dir]   (default: ./build)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${1:-build}"
APP_NAME="CodexMeter"
BUNDLE_ID="com.jackie.CodexMeter"
APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> swift build -c release"
swift build -c release --product CodexMeter
BIN="$(swift build -c release --show-bin-path)/CodexMeter"

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
PLIST

cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"

echo "==> ad-hoc signing"
codesign --force --sign - --timestamp=none "$APP_DIR"

echo "==> done: $APP_DIR"
echo "    install with: cp -R \"$APP_DIR\" /Applications/"
