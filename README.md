# ASUS VG32VQ1B — Display Setup Notes

Generated: 2026-11-04
Updated: 2026-11-08 — login/wake agent hardened (see §5)
Computer: MacBook Pro 16" (MacBookPro18,2), Apple M1 Max, macOS 26.0
Connection: built-in HDMI (internal path DP → HDMI downstream)

## Folder contents

- `README.md` — this document
- `font-smoothing.md` — the font-smoothing setting, the 0–3 scale, how to
  change it and how to revert it
- `verify.sh` — print the live state and whether it matches the desired values
- `settings.conf` — the desired values (mode, brightness, font smoothing)
- `apply-settings.sh` — restore those values now; safe to run any time
- `install.sh` — build the helpers and install the login/wake restore agent
- `uninstall.sh` — remove the restore agent
- `display-mode.swift`, `watch-display.swift` — helper sources (compiled into
  `build/` by `install.sh`)

---

## 1. The key fact

**This monitor is NOT 4K.**

| | |
|---|---|
| Model | ASUS TUF Gaming VG32VQ1B |
| Panel | 31.5", 1500R curved, VA |
| Native resolution | **2560 × 1440 (QHD)** |
| Pixel density | ~93 PPI |
| Max refresh over HDMI | **144 Hz** |
| Max refresh over DisplayPort | 165 Hz |
| Ports | HDMI 2.0 × 2, DisplayPort 1.2 × 1 |

Selecting **3840 × 2160** in macOS does not give you 4K. macOS renders a
fake 4K desktop and then squeezes it onto the 2560 × 1440 panel:

- everything becomes ~33% smaller (4K desktop on a 1440p panel)
- the image is resampled 1.5× (3840 → 2560) → blur / pixelation

That combination is the "tiny and pixelated" symptom. It cannot be fixed
at that setting — the panel physically cannot display 4K.

---

## 2. What was applied (verified on this machine)

| Setting | Value | How |
|---|---|---|
| Resolution | 2560 × 1440, native 1:1, scale 1 | `build/display-mode` (CoreGraphics) |
| Refresh rate | 144 Hz (HDMI maximum) | `build/display-mode` (CoreGraphics) |
| Color depth | 8-bit | negotiated |
| Brightness | 50 (≈125 nits, correct for SDR office use) | DDC via `m1ddc` |
| Font smoothing | 0 (off, crispest) | `defaults` global + per-host |
| Color profile | factory `VG32VQ1B` ICC | default |
| HDR / VRR | not engaged | — |
| Persistence | re-applied on login, wake and reconnect | LaunchAgent, see §5 |

Verified state:

```
VG32VQ1B
  Resolution:     2560 × 1440 (QHD/WQHD)
  UI Looks like:  2560 × 1440 @ 144.00 Hz
  Main Display:   Yes
  Mirror:         Off
```

### Tools used

`m1ddc` (Homebrew) — DDC/CI control on Apple Silicon:
`brew install m1ddc`

The display mode is applied by `build/display-mode`, a small Swift/CoreGraphics
helper compiled from `display-mode.swift`. It matches the monitor by its EDID
vendor/product (`1715` / `13024`), not by the macOS display UUID, because the
UUID can change when the monitor is reconnected.

DDC test results on this monitor:
- **brightness** — works
- **contrast** — writes are ignored by the monitor (firmware limitation)
- VividPixel / Sharpness / GameVisual / ELMB / Shadow Boost / ASCR / OverScan
  have **no standard DDC code** and cannot be set by any Mac software.
  They exist only in the monitor's own OSD menu.

---

## 3. Monitor OSD settings (must be done with the joystick)

The joystick is on the back-right of the monitor. Press it to open the
menu, push **left/right** to change menu page, **up/down** to move,
press to select.

### Image menu

| # | Setting | Value | Why |
|---|---|---|---|
| 1 | **VividPixel** | **0** | Kills fake edge-halo around text — biggest single improvement |
| 2 | **Aspect Control** | **Full** (not OverScan) | Stops edge cropping |
| 3 | **Shadow Boost** | **0** | Stops crushed / boosted blacks |
| 4 | **ELMB SYNC** | **Off** | Backlight strobing = flicker on a desktop |
| 5 | **HDR** | **Off** | This panel's HDR is weak; washes out the desktop |
| 6 | **Image → More → ASCR** | **Off** | Dynamic contrast pumping |
| 7 | **Image → More → Trace Free** | **40** | Reduces overdrive overshoot that makes scrolling text shimmer |

### Other menus

| Setting | Value | Why |
|---|---|---|
| **GameVisual** | **Racing Mode** (leave default) | Sharpness is locked in this mode, which is fine |
| **Blue Light Filter** | **Level 0** | Avoids yellow cast |
| **Contrast** | **80** | Standard |
| **Color Temp** | **User / 6500K** | Neutral white |
| **Gamma** | **2.2** | Standard SDR |
| **ECO Mode** | **Off** | No auto-dimming |
| **Saturation** | **50** | Neutral |

### Note on Sharpness

Sharpness is **not user-configurable in Racing Mode, sRGB Mode or MOBA Mode**
(confirmed in the ASUS VG32V series manual). It only unlocks in Scenery,
Cinema, RTS/RPG or FPS mode — but those are full presets that also change
color temperature and brightness. For desktop use, leaving Racing Mode and
Sharpness locked at its factory value is the better trade.

---

## 4. macOS settings

- **Resolution:** 2560 × 1440 (native) — never use a scaled/"looks like"
  option on this panel; anything except native introduces resampling blur.
- **Refresh rate:** 144 Hz
- **HDR:** off (System Settings → Displays → High Dynamic Range)
- **Night Shift:** off (for color accuracy)
- **True Tone:** N/A on external displays

### Font smoothing — APPLIED (value 0)

macOS renders text on this 1× display with grayscale antialiasing. The
system exposes a 0–3 scale:

| Value | Effect |
|---|---|
| 0 | No smoothing — thinnest, crispest edges, most aliasing |
| 1 | Light |
| 2 | Medium |
| 3 | Strong — smoothest, heaviest, most "blurry" |

**Currently set to 0** (off, crispest), in both the global and per-host domain:

```sh
defaults write -g AppleFontSmoothing -int 0
defaults -currentHost write -g AppleFontSmoothing -int 0
```

Takes effect after **logging out and back in** (not just restarting Finder).

0 is the crispest setting macOS offers on a 1× display. If text looks too
thin/faint or the aliasing is distracting, go back to **1** (light) or **2**
(medium).

Revert to the system default:

```sh
defaults delete -g AppleFontSmoothing
defaults -currentHost delete -g AppleFontSmoothing
```

See **`font-smoothing.md`** for the full decision guide (what to do if text
still looks soft, or looks too thin).

---

## 5. Persistence — the settings now survive a restart

macOS keeps display modes per connection, but it does not reliably re-apply
them. The windowserver plist still contains an old **3840 × 2160 @ 60 Hz**
(linked) configuration from the 4K attempt, and on a cold boot or after the
monitor loses power macOS can select it again. DDC brightness and the font
smoothing default can drift for the same reason.

To make the documented state stick, the project installs a per-user
LaunchAgent (`com.modernamusmenet.vg32vq1b-restore`) that runs
`apply-settings.sh`:

| Trigger | Why |
|---|---|
| login / boot | restores everything after a restart |
| system or screen wake | DDC and mode can drop on wake |
| monitor connect / disconnect | catches cable reconnects |
| mode changes within 60 s of the above | catches macOS settling on a wrong mode late |
| display still absent afterwards | retried every 15 s for 5 min, then waits for the next event |
| every 60 s | compares the set of connected external displays; catches an unplug/replug that macOS never reports |

The script is idempotent: it reads the current mode, brightness and font
smoothing and only writes when they differ from `settings.conf`. Mode changes
you make by hand later in a session are left alone; it only corrects the
state around login, wake and reconnect.

The display is often not enumerable for the first minute of a login or wake
(the monitor is still powering up), so `apply-settings.sh` exits **2** instead
of pretending success. The watcher retries that case every 15 s for up to
5 minutes — it stops after that, because polling a monitor that is switched
off all day is pointless. Every other failure is final and is retried only on
the next login, wake or reconnect.

macOS does not reliably report a monitor being plugged back in, so the agent
also compares the set of connected external displays every 60 s and re-applies
when it changes. That check ignores mode changes, so a refresh rate you pick
by hand stays put.

`install.sh` stages the runtime copies in
`~/Library/Application Support/vg32vq1b/` and the LaunchAgent runs those, not
the files in this folder. Launching a binary directly from `~/Desktop` cost
153 s once (TCC), which is enough to miss the restore entirely.

```sh
./install.sh          # build + install + start (already done)
./apply-settings.sh   # re-apply by hand, no agent needed
./uninstall.sh        # stop and remove the agent
```

Change a desired value in `settings.conf`, then run `./install.sh` again. If
you move or rename this folder, run `./install.sh` again so the agent picks up
the new absolute paths.

Logs: `~/Library/Logs/vg32vq1b-restore.log`

### What is restored automatically

- resolution **2560 × 1440**, native 1:1, mirroring off
- refresh rate **144 Hz**
- DDC brightness **50**
- font smoothing **0**, global and per-host

Not scriptable through public macOS APIs, so still manual if they drift:
**HDR**, **Night Shift**, **True Tone** (N/A here) and the monitor's own OSD
settings (VividPixel, ELMB, etc. — those live in the monitor, not macOS).

---

## 6. Verify current state

```sh
./verify.sh
```

It prints the live resolution/refresh, DDC brightness, font-smoothing values,
the restore agent's state and the last agent activity, and marks each one
`MATCH` or `MISMATCH`.

Raw checks if you need them:

```sh
# resolution + refresh
system_profiler SPDisplaysDataType | grep -A6 VG32VQ1B

# brightness
m1ddc get luminance

# full display config (Hz, depth, scale)
plutil -p /Library/Preferences/com.apple.windowserver.displays.plist
```

Expected:

- `UI Looks like: 2560 x 1440 @ 144.00Hz`
- `brightness = 50`
- both font-smoothing domains = `0`
- agent `state = running`

If something is `MISMATCH`, run `./apply-settings.sh`. If 144 Hz still drops
back to 60 Hz, the usual cause is a bad/unstable HDMI cable.

---

## 7. If 144 Hz looks wrong

At 1440p/144 Hz over HDMI 2.0 the link is near the bandwidth limit and the
monitor may fall back to 4:2:2/4:2:0 chroma subsampling, which shows as
colored fringing on small text.

Options, in order:
1. Drop to **120 Hz** in System Settings → Displays (still very smooth).
   If you want to keep 120 Hz permanently, set `DISPLAY_REFRESH=120` in
   `settings.conf` — otherwise the login agent restores 144 Hz after a
   restart.
2. Use a **USB-C → DisplayPort** cable instead — gives full RGB and 165 Hz.
3. Use a certified HDMI 2.0 / "Premium High Speed" cable.

---

## 8. The honest ceiling

Every setting above is the maximum this hardware can do. What remains is
physics:

- this panel: **2560 × 1440 at 31.5" ≈ 93 PPI**
- MacBook Pro built-in: **≈ 254 PPI**

Text will never look like the laptop's screen — not with any setting,
cable, or app. If sharpness matters more than size, the only real upgrade
is a 4K (or 5K) display, where macOS enables true HiDPI and text becomes
genuinely sharp. Connect such a display via **USB-C → DisplayPort**, not
HDMI, for full-quality 4K at 60 Hz.
