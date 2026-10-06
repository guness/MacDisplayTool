#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# SwiftUI's compiler plugins ship with full Xcode. Prefer it when the active
# developer directory is the standalone Command Line Tools installation.
if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PWD/dist/MacDisplayTool.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_DIR/DisplayMenu" "$APP_DIR/Contents/MacOS/DisplayMenu"
cp "$BIN_DIR/DisplayTool" "$APP_DIR/Contents/MacOS/DisplayTool"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.guness.MacDisplayTool</string>
  <key>CFBundleName</key><string>MacDisplayTool</string>
  <key>CFBundleDisplayName</key><string>MacDisplayTool</string>
  <key>CFBundleExecutable</key><string>DisplayMenu</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>com.guness.MacDisplayTool.control</string>
    <key>CFBundleURLSchemes</key><array><string>macdisplaytool</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR/Contents/MacOS/DisplayTool"
codesign --force --sign - "$APP_DIR"
echo "Built $APP_DIR"
