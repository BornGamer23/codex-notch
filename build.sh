#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$(pwd)/Codex Notch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexNotch</string>
<key>CFBundleIdentifier</key><string>local.codexnotch.app</string>
<key>CFBundleName</key><string>Codex Notch</string>
<key>CFBundleDisplayName</key><string>Codex Notch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
TASK_CACHE="${TMPDIR:-/tmp}/codex-notch-module-cache"
mkdir -p "$TASK_CACHE"
xcrun swiftc -module-cache-path "$TASK_CACHE" -O -swift-version 5 -target arm64-apple-macosx13.0 -framework AppKit Sources/Activity.swift Sources/HUD.swift Sources/Tests.swift Sources/main.swift -o "$APP/Contents/MacOS/CodexNotch"
codesign --force --sign - "$APP"
xcrun swiftc -module-cache-path "$TASK_CACHE" -parse-as-library -O -swift-version 5 -target arm64-apple-macosx13.0 -framework AppKit Sources/AutoStart.swift -o CodexNotchAutoStart
codesign --force --sign - CodexNotchAutoStart
"$APP/Contents/MacOS/CodexNotch" --self-test
echo "Built: $APP"
