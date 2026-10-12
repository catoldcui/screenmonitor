#!/bin/sh
# Builds build/ScreenMonitor.app so notifications, launch at login and StoreKit
# behave like a real app. Usage: scripts/bundle.sh [debug|release]
set -eu
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/ScreenMonitor.app"
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

swift build -c "$CONFIG" --product ScreenMonitorApp
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ScreenMonitorApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ScreenMonitor"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"   # regenerate with: swift scripts/make-icon.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.chenhuicui.screenmonitor</string>
    <key>CFBundleName</key><string>ScreenMonitor</string>
    <key>CFBundleDisplayName</key><string>ScreenMonitor</string>
    <key>CFBundleExecutable</key><string>ScreenMonitor</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
