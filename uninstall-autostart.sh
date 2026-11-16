#!/bin/bash
set -euo pipefail
DOMAIN="gui/$(id -u)"
AGENT_FILE="$HOME/Library/LaunchAgents/local.codexnotch.autostart.plist"
if launchctl print "$DOMAIN/local.codexnotch.autostart" >/dev/null 2>&1; then
    launchctl bootout "$DOMAIN/local.codexnotch.autostart"
fi
rm -f "$AGENT_FILE"
echo "Autostart removed. The app and its preferences are preserved."
