#!/bin/bash
set -e

PROJ="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Clippy"
APP_DEST="/Applications/${APP_NAME}.app"
PLIST_LABEL="com.clippy.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

echo "Building release..."
cd "$PROJ"
swift build -c release

BINARY=".build/release/${APP_NAME}"

echo "Creating .app bundle..."
rm -rf "$APP_DEST"
mkdir -p "$APP_DEST/Contents/MacOS"
mkdir -p "$APP_DEST/Contents/Resources"

cp "$BINARY" "$APP_DEST/Contents/MacOS/${APP_NAME}"
cp "Sources/App/Info.plist" "$APP_DEST/Contents/Info.plist"
cp "Sources/App/AppIcon.icns" "$APP_DEST/Contents/Resources/AppIcon.icns"

echo "Installing LaunchAgent for login autostart..."
cat > "$LAUNCH_AGENT" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_DEST}/Contents/MacOS/${APP_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT"

echo ""
echo "Done! ClipboardManager.app installed to /Applications"
echo "Running now and will auto-start on every login."
echo ""
echo "To uninstall: bash uninstall.sh"
