#!/bin/bash
# Builds build/Redpaper.app (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null; then
    echo "Swift not found. Install the Command Line Tools with: xcode-select --install" >&2
    exit 1
fi

# The macOS 27 SDK makes @State a macro whose plugin ships only with Xcode. Without Xcode,
# build against a macOS 26 SDK when one is installed (the app still runs on macOS 27).
if [[ "$(xcode-select -p)" != *Xcode.app* ]]; then
    sdk=$(ls -d "$(xcode-select -p)"/SDKs/MacOSX26*.sdk 2>/dev/null | tail -1 || true)
    if [[ -n "$sdk" ]]; then export SDKROOT="$sdk"; fi
fi

swift build -c release
APP=build/Redpaper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Redpaper "$APP/Contents/MacOS/"
cp icon/AppIcon.icns "$APP/Contents/Resources/"  # regenerate: swift icon/make_icon.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.Redpaper</string>
    <key>CFBundleName</key><string>Redpaper</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleExecutable</key><string>Redpaper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
