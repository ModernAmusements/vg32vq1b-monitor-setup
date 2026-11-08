#!/bin/zsh
# Verify current state of the ASUS VG32VQ1B display and the restore agent.
# Usage: ./verify.sh

set -u

BASE="${0:A:h}"
source "$BASE/settings.conf"

LABEL="com.modernamusmenet.vg32vq1b-restore"
PLIST="/Library/Preferences/com.apple.windowserver.displays.plist"
LOG="$HOME/Library/Logs/vg32vq1b-restore.log"

echo "=== Display ==="
system_profiler SPDisplaysDataType 2>/dev/null | grep -A6 "$DISPLAY_NAME"

echo
echo "=== Mode (expected ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} @ ${DISPLAY_REFRESH} Hz, scale 1) ==="
if [[ -x "$BASE/build/display-mode" ]]; then
  "$BASE/build/display-mode" --status 2>/dev/null | sed 's/^/  /'
  if "$BASE/build/display-mode" \
      --width "$DISPLAY_WIDTH" --height "$DISPLAY_HEIGHT" --refresh "$DISPLAY_REFRESH" \
      --vendor "$DISPLAY_VENDOR" --model "$DISPLAY_MODEL" --check >/dev/null 2>&1; then
    echo "  MATCH"
  else
    echo "  MISMATCH (run ./apply-settings.sh)"
  fi
else
  echo "  helper not built - run ./install.sh"
  /usr/bin/python3 - "$PLIST" <<'PY'
import plistlib, sys
try:
    d = plistlib.load(open(sys.argv[1], 'rb'))
except Exception as e:
    print("  could not read windowserver plist:", e); sys.exit(0)
for entry in d.get("DisplayAnyUserSets", {}).get("Configs", [{}])[0].get("DisplayConfig", []):
    ci = entry.get("CurrentInfo", {})
    print(f'  {int(ci.get("Wide", 0))} x {int(ci.get("High", 0))} @ {ci.get("Hz")} Hz   '
          f'depth={ci.get("Depth")}  scale={ci.get("Scale")}')
PY
fi

echo
echo "=== DDC brightness (expected $BRIGHTNESS) ==="
if command -v m1ddc >/dev/null 2>&1; then
  ok=0
  for i in 1 2 3; do
    out=$(m1ddc get luminance 2>&1)
    if [[ "$out" == <-> ]]; then
      if [[ "$out" == "$BRIGHTNESS" ]]; then
        echo "  brightness = $out  MATCH"
      else
        echo "  brightness = $out  MISMATCH (run ./apply-settings.sh)"
      fi
      ok=1
      break
    fi
    sleep 1
  done
  if [[ $ok -eq 0 ]]; then
    echo "  DDC read failed (HDMI DDC on this Mac is intermittent; try again)"
  fi
else
  echo "  m1ddc not installed (brew install m1ddc)"
fi

echo
echo "=== Font smoothing (expected $FONT_SMOOTHING) ==="
global=$(defaults read -g AppleFontSmoothing 2>/dev/null)
host=$(defaults -currentHost read -g AppleFontSmoothing 2>/dev/null)
echo "  global domain:   ${global:-unset}"
echo "  per-host domain: ${host:-unset}"
if [[ "$global" == "$FONT_SMOOTHING" && "$host" == "$FONT_SMOOTHING" ]]; then
  echo "  MATCH"
else
  echo "  MISMATCH (run ./apply-settings.sh)"
fi

echo
echo "=== Restore agent ==="
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  state=$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk -F' = ' '/^\tstate = /{print $2; exit}')
  pid=$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk -F' = ' '/^\tpid = /{print $2; exit}')
  echo "  loaded, state=${state:-?} pid=${pid:-?}"
  prog=$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk -F' = ' '/program = /{print $2; exit}')
  echo "  program: ${prog:-?}"
else
  echo "  not loaded - run ./install.sh"
fi

if [[ -f "$LOG" ]]; then
  echo
  echo "=== Last agent activity ==="
  tail -n 6 "$LOG" | sed 's/^/  /'
fi

exit 0
