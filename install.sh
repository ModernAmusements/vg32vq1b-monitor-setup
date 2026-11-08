#!/bin/zsh
# install.sh
#
# Builds the two small Swift helpers, installs a per-user LaunchAgent and
# applies the documented VG32VQ1B state right away.
#
#   ./install.sh     build + install + start
#   ./uninstall.sh   stop + remove the LaunchAgent

set -euo pipefail

BASE="${0:A:h}"
BUILD="$BASE/build"
LABEL="com.modernamusmenet.vg32vq1b-restore"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT="$HOME/Library/Application Support/vg32vq1b"
LOG="$HOME/Library/Logs/vg32vq1b-restore.log"
UID_NUM="$(id -u)"

mkdir -p "$BUILD" "$SUPPORT/build" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

build() {
  local source="$1" output="$2"
  if [[ ! -x "$output" || "$source" -nt "$output" ]]; then
    print "building $(basename "$output")..."
    xcrun swiftc -O "$source" -o "$output"
  fi
}

command -v xcrun >/dev/null 2>&1 || {
  print -u2 "error: Xcode command line tools are required (xcode-select --install)"
  exit 1
}

build "$BASE/display-mode.swift" "$BUILD/display-mode"
build "$BASE/watch-display.swift" "$BUILD/watch-display"

chmod +x "$BASE/apply-settings.sh" "$BASE/verify.sh"

# launchd must not exec from ~/Desktop: that folder is TCC-protected, and a
# freshly built helper was observed stuck in dyld open() for 2.5 minutes,
# which delays or loses the restore after login. Stage runtime copies in
# Application Support and point the agent there.
install -m 755 "$BUILD/watch-display" "$SUPPORT/build/watch-display"
install -m 755 "$BUILD/display-mode" "$SUPPORT/build/display-mode"
install -m 755 "$BASE/apply-settings.sh" "$SUPPORT/apply-settings.sh"
install -m 644 "$BASE/settings.conf" "$SUPPORT/settings.conf"

# Stop an older copy, if it is loaded.
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SUPPORT/build/watch-display</string>
        <string>$SUPPORT/apply-settings.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$UID_NUM" "$AGENT"

print
print "Installed $LABEL"
print "  agent:  $AGENT"
print "  files:  $SUPPORT"
print "  log:    $LOG"
print
print "Applying settings now..."
sleep 6
tail -n 12 "$LOG" 2>/dev/null || true
print
print "Check at any time with: ./verify.sh"
