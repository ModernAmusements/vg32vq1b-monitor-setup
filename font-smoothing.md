# Font Smoothing — macOS 26 / external 1× display

Applied: 2026-11-04
Last changed: 2026-11-08 (set to 3)
Display: ASUS VG32VQ1B, 2560 × 1440 native, ~93 PPI (1× / non-Retina)

---

## What is applied

```sh
defaults write -g AppleFontSmoothing -int 3            # global domain
defaults -currentHost write -g AppleFontSmoothing -int 3   # per-host domain
```

Verified values:

```
global domain:      3
per-host domain:    3
```

Value **3** is the current setting, chosen by eye on this panel. History:

- 2026-11-04: set to 2 (medium).
- 2026-11-06: lowered to 1, then 0, because text edges looked soft.
- 2026-11-08: set to 3 on purpose. `settings.conf` notes that 2 was too soft.

**This requires a full logout / login to take effect.** Restarting Finder is
not enough; each app must be relaunched.

> This value is enforced by `apply-settings.sh`, which the login agent runs
> (see README §5). It reads `FONT_SMOOTHING` from `settings.conf`, so change
> the value there and run `./install.sh`, not the `defaults` commands alone.

---

## The 0–3 scale

macOS renders text on a 1× display with grayscale antialiasing. The
`AppleFontSmoothing` key controls how much:

| Value | Effect |
|---|---|
| **0** | No smoothing — thinnest strokes, crispest edges, most aliasing |
| **1** | Light smoothing |
| **2** | Medium smoothing (too soft on this panel) |
| **3** | Strong smoothing — heaviest strokes, smoothest edges ← **currently set** |

Higher values blend the edges into the background, which can read as blur.
Lower values give thinner, sharper strokes but more aliasing.

- text looks too thin / faint → go **up** (toward 3)
- text looks soft / smudged → go **down** (toward 0)

---

## Decide after you log back in

| What you see | Action |
|---|---|
| Text looks good | Leave at **3** — done |
| Too heavy / blurry | Step down to **2**, then **1** |
| Too thin / faint | Step up toward **3** (already the maximum) |

To change the value, edit `FONT_SMOOTHING` in `settings.conf`, then:

```sh
./install.sh
```

Then log out and back in again.

---

## Revert to system default

```sh
defaults delete -g AppleFontSmoothing
defaults -currentHost delete -g AppleFontSmoothing
```

Log out and back in.

If the restore agent is installed it will set the `settings.conf` value again
at the next login. To make the revert stick, either run `./uninstall.sh` first
or change `FONT_SMOOTHING` in `settings.conf` to the value you want.

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
