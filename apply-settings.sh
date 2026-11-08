#!/bin/zsh
# apply-settings.sh
#
# Restores the documented VG32VQ1B state:
#   - 2560 x 1440 @ 144 Hz, native 1:1, mirroring off
#   - DDC brightness 50
#   - AppleFontSmoothing 0 (global + per-host)
#
# Safe to run at any time: each step checks first and only writes on a
# mismatch. Called by the login/wake agent (watch-display) and usable by hand.
#
# Exit codes:
#   0  display found (brightness/smoothing applied or already correct)
#   2  the display is not enumerable yet; the caller may retry
#   3  requested mode not offered by the display (final)
#   4  the system refused the mode (final)
#   1  setup problem (helper not built)

set -u

BASE="${0:A:h}"
source "$BASE/settings.conf"

BIN="$BASE/build/display-mode"

# Stamp every line at write time. A single prefix computed once per run made
# multi-minute retry loops look instantaneous in the log.
log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" }

if [[ ! -x "$BIN" ]]; then
  log "ERROR: $BIN is missing - run ./install.sh first"
  exit 1
fi

# ---------------------------------------------------------------- display mode

apply_display_mode() {
  local attempt output rc

  # The display can take a few seconds to appear after wake or reconnect.
  # Kept short on purpose: watch-display retries this script with backoff
  # while it exits 2, so a display that shows up late still gets restored.
  DISPLAY_RC=2
  for attempt in {1..10}; do
    output=$("$BIN" \
      --width "$DISPLAY_WIDTH" \
      --height "$DISPLAY_HEIGHT" \
      --refresh "$DISPLAY_REFRESH" \
      --vendor "$DISPLAY_VENDOR" \
      --model "$DISPLAY_MODEL" 2>&1)
    rc=$?
    DISPLAY_RC=$rc

    case $rc in
      0)
        log "display: $output"
        return 0
        ;;
      2)
        # Not online yet (clamshell boot, wake, cable reconnect).
        sleep 1
        ;;
      *)
        log "display: $output"
        sleep 1
        ;;
    esac
  done

  log "display: ${DISPLAY_NAME} not available or mode could not be set"
  return 1
}

# -------------------------------------------------------------------- brightness

m1ddc_index() {
  local line index

  line=$(m1ddc display list 2>/dev/null | grep -F "$DISPLAY_NAME" | head -1)
  [[ -n "$line" ]] || return 1

  index=$(print -r -- "$line" | sed -E 's/^\[([0-9]+)\].*/\1/')
  [[ "$index" == <-> ]] || return 1
  print -r -- "$index"
}

apply_brightness() {
  local index current attempt

  if ! command -v m1ddc >/dev/null 2>&1; then
    log "brightness: m1ddc not installed, skipping"
    return 0
  fi

  for attempt in {1..5}; do
    index=$(m1ddc_index) && break
    sleep 2
  done

  if [[ -z "${index:-}" ]]; then
    log "brightness: ${DISPLAY_NAME} not found by m1ddc, skipping"
    return 0
  fi

  for attempt in {1..3}; do
    current=$(m1ddc display "$index" get luminance 2>/dev/null)
    [[ "$current" == <-> ]] && break
    sleep 1
  done

  if [[ "${current:-}" == "$BRIGHTNESS" ]]; then
    log "brightness: already $BRIGHTNESS"
    return 0
  fi

  m1ddc display "$index" set luminance "$BRIGHTNESS" >/dev/null 2>&1

  # DDC reads over built-in HDMI are intermittent; report but do not fail.
  sleep 1
  current=$(m1ddc display "$index" get luminance 2>/dev/null)
  if [[ "$current" == "$BRIGHTNESS" ]]; then
    log "brightness: set $BRIGHTNESS"
  else
    log "brightness: requested $BRIGHTNESS (readback: ${current:-failed}, DDC over HDMI is flaky)"
  fi
  return 0
}

# ---------------------------------------------------------------- font smoothing

apply_font_smoothing() {
  local current

  current=$(defaults read -g AppleFontSmoothing 2>/dev/null)
  if [[ "$current" != "$FONT_SMOOTHING" ]]; then
    defaults write -g AppleFontSmoothing -int "$FONT_SMOOTHING"
    log "font smoothing: global ${current:-unset} -> $FONT_SMOOTHING"
  else
    log "font smoothing: global already $FONT_SMOOTHING"
  fi

  current=$(defaults -currentHost read -g AppleFontSmoothing 2>/dev/null)
  if [[ "$current" != "$FONT_SMOOTHING" ]]; then
    defaults -currentHost write -g AppleFontSmoothing -int "$FONT_SMOOTHING"
    log "font smoothing: per-host ${current:-unset} -> $FONT_SMOOTHING"
  else
    log "font smoothing: per-host already $FONT_SMOOTHING"
  fi
}

display_ok=0
apply_display_mode && display_ok=1

if (( display_ok )); then
  apply_brightness
else
  # m1ddc would just spend 10 s failing to find a display that is not there.
  log "brightness: skipped (${DISPLAY_NAME} not available)"
fi

apply_font_smoothing

# Let watch-display know the display never showed up so it can retry later.
# Exit 2 only when the display was simply not enumerable; an unsupported mode
# (3) or a refused configuration (4) is final and must not be retried in a loop.
(( display_ok )) || exit "${DISPLAY_RC:-2}"
exit 0
