#!/bin/zsh
# uninstall.sh
#
# Stops the login/wake agent and removes its LaunchAgent plus the staged
# runtime copies. The compiled helpers, settings and log are left in place.

set -euo pipefail

LABEL="com.modernamusmenet.vg32vq1b-restore"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT="$HOME/Library/Application Support/vg32vq1b"
UID_NUM="$(id -u)"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
rm -f "$AGENT"
rm -rf "$SUPPORT"

print "Removed $LABEL"
print "The display keeps its current settings until the next reboot."
