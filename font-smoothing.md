# Font Smoothing — macOS 26 / external 1× display

Applied: 2026-11-04
Display: ASUS VG32VQ1B, 2560 × 1440 native, ~93 PPI (1× / non-Retina)

---

## What was applied

```sh
defaults write -g AppleFontSmoothing -int 0            # global domain
defaults -currentHost write -g AppleFontSmoothing -int 0   # per-host domain
```

Verified values:

```
global domain:      0
per-host domain:    0
```

Value **0 = no smoothing** (crispest). (Originally 2 = medium, but text edges
read as soft on this 93 PPI panel; lowered to 1 and then 0 on 2026-11-06.)

**This requires a full logout / login to take effect.** Restarting Finder is
not enough; each app must be relaunched.

> This value is also enforced by `apply-settings.sh`, which the login agent
> runs (see README §5). If it drifts it is set back to 2 at the next
> login/wake.

---

## The 0–3 scale

macOS renders text on a 1× display with grayscale antialiasing. The
`AppleFontSmoothing` key controls how much:

| Value | Effect |
|---|---|
| **0** | No smoothing — thinnest strokes, crispest edges, most aliasing ← **currently set** |
| **1** | Light smoothing |
| **2** | Medium smoothing (original setting) |
| **3** | Strong smoothing — smoothest, heaviest, most "soft" |

Counter-intuitively, on non-Retina displays **lower values usually make text
look sharper**. Higher values blend the edges into the background, which can
read as blur. So:

- text looks soft / smudged → go **down** (0 is the floor)
- text looks too thin / faint → go **up** to 1, 2 or 3

---

## Decide after you log back in

| What you see | Action |
|---|---|
| Text looks good | Leave at **0** — done |
| Too thin / faint / spindly | Go back to **1** (light), then **2** if needed |
| Still soft at 0 | This is the macOS floor; the limit is now the 93 PPI panel |

To change the value:

```sh
# pick ONE: 0, 1, 2 or 3   (0 = current)
defaults write -g AppleFontSmoothing -int 0
defaults -currentHost write -g AppleFontSmoothing -int 0
```

Then log out and back in again.

---

## Revert to system default

```sh
defaults delete -g AppleFontSmoothing
defaults -currentHost delete -g AppleFontSmoothing
```

Log out and back in.

If the restore agent is installed it will set value **0** again at the next
login. To make the revert stick, either run `./uninstall.sh` first or change
`FONT_SMOOTHING` in `settings.conf` to the value you want.

---

## Notes

- This key affects **AppKit** text rendering (most native apps). Browsers,
  Electron apps, and Java apps may ignore it — they do their own text
  rendering.
- It does **not** change text *size*, only stroke weight/antialiasing.
- Setting it cannot damage anything; it is a per-user preference and fully
  reversible.
- If a future macOS update ignores the key, the fallback is the same
  `defaults` command aimed at the per-host domain, which is the one the
  window server reads.
