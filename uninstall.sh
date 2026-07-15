#!/bin/bash
set -e

APP_DEST="/Applications/Clippy.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.clippy.app.plist"

echo "Stopping Clippy..."
launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true

echo "Removing LaunchAgent..."
rm -f "$LAUNCH_AGENT"

echo "Removing app..."
rm -rf "$APP_DEST"

echo "Killing running process if any..."
pkill -x Clippy 2>/dev/null || true

echo "Uninstalled."
