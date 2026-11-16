#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
INSTALL_DIR="$HOME/Library/Application Support/CodexNotch"
AGENT_FILE="$HOME/Library/LaunchAgents/local.codexnotch.autostart.plist"
DOMAIN="gui/$(id -u)"
mkdir -p "$INSTALL_DIR" "$(dirname "$AGENT_FILE")"
if launchctl print "$DOMAIN/local.codexnotch.autostart" >/dev/null 2>&1; then
    launchctl bootout "$DOMAIN/local.codexnotch.autostart"
fi
ditto "Codex Notch.app" "$INSTALL_DIR/Codex Notch.app"
cp CodexNotchAutoStart "$INSTALL_DIR/CodexNotchAutoStart"
chmod 755 "$INSTALL_DIR/CodexNotchAutoStart"
python3 - "$INSTALL_DIR" "$AGENT_FILE" <<'PY'
import plistlib, sys
from pathlib import Path
root, agent = map(Path, sys.argv[1:])
with agent.open('wb') as f:
    plistlib.dump({
        'Label': 'local.codexnotch.autostart',
        'ProgramArguments': [str(root / 'CodexNotchAutoStart')],
        'RunAtLoad': True,
        'KeepAlive': True,
        'LimitLoadToSessionType': 'Aqua',
        'ThrottleInterval': 10,
        'ProcessType': 'Background',
        'StandardErrorPath': str(root / 'autostart-error.log'),
    }, f)
PY
plutil -lint "$AGENT_FILE"
launchctl enable "$DOMAIN/local.codexnotch.autostart"
launchctl bootstrap "$DOMAIN" "$AGENT_FILE"
echo "Autostart installed. Codex Notch will open quietly with Codex."
