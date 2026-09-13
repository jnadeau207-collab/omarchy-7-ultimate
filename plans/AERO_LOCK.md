# AERO LOCK — OS visual standard

**Locked 2026-09-12 on metal SHA `528cc0f4` (`cursor/explorer-win7-folder-band`).** Product remains **REJECTED**. `win7VisualLeftover` remains **OPEN** until grim pixel proof. This lock is the look, not a CLOSED leftover.

Windows 7 Ultimate Aero, as painted on Files and Settings, is the visual standard for **every product window** in this OS. That is what Windows 7 looks like. Every other surface (Superbar, Start, dialogs, Administration, Software, OOBE) is made compatible with this frame. Do not restore hyprbars as the Explorer/Settings caption. Do not invent a second chrome.

## What is locked

| Piece | Standard |
| --- | --- |
| Owner | `shell/apps/shared/AeroWindowChrome.qml` |
| Glass fill | `#4580c4` at **0.66** over Hyprland blur |
| Frame | 6px radius, 6px glass margin, 1px `#000000b3` outer + inner white highlight |
| Caption | **Blank.** No “Files”, no “Settings”, no “quickshell”. |
| Caption buttons | Hanging cluster 29 + 29 + 48 × 19, flush to the top edge |
| Compositor | `hyprbars:no_bar` on `org.omarchy.Files` and `org.omarchy.Settings`; `QT_WAYLAND_DISABLE_WINDOWDECORATION=1` |
| Move | xdg `startSystemMove` on the 30px caption hit-strip (same CSD move Chromium uses) |
| Min / max / close | Existing `omarchy-shell window {minimize,toggleMaximize,close} active` |
| Superbar | **Same Aero glass as Explorer** (`#4580c4` @ 0.66). Height **40px** @ 96 DPI. Running = bordered glass tile, not a glow underline. Not a black strip. |

## What this is not

- Not hyprbars SSD on Files/Settings.
- Not a Tokyo Night / charcoal strip.
- Not permission to skip Win7 jobs. Doctrine “not a clone” means no ads, telemetry, or forced accounts — it does not mean skip Explorer, Superbar, or Control Panel anatomy.

## Honesty

Hex-grep of this file is not pixel proof. Metal grim vs a Windows 7 Ultimate screenshot is the proof. Leftover stays OPEN.
