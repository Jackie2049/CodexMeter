#!/bin/bash
# Builds release binary and assembles CodexMeter.app (ad-hoc signed).
# Usage: ./Scripts/make_app.sh [output_dir]   (default: ./build)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${1:-build}"
APP_NAME="CodexMeter"
BUNDLE_ID="com.jackie.CodexMeter"
# Version single source: the most recent v* git tag drives the app version
# (AGENTS.md §8). Pre-tag dev builds fall back to 0.1.0-dev.
APP_VERSION="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)"
APP_VERSION="${APP_VERSION:-0.1.0-dev}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> version $APP_VERSION (build $BUILD_NUMBER)"

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
    <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
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
