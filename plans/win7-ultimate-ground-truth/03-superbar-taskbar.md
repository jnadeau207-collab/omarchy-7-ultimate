# 03 — Superbar / Taskbar (Win7 Ultimate)

**Repo path:** `plans/win7-ultimate-ground-truth/03-superbar-taskbar.md`  
**Research sources:** `research/02-START-SUPERBAR.md` + `.json` (taskbar sections), `fleet-shell-win7.md` §2–5, `fleet-aero-win7.md` Peek  
**Target phases:** Phase 4, Phase 1 (Show Desktop / peeks related), Phase 11  
**DPI baseline:** **96 DPI / 100%**

---

## Purpose

Binding Win7 Ultimate taskbar (Superbar) geometry, grouping, Jump Lists, notification area, Show Desktop / Aero Peek, and button click grammar.

---

## Binding metrics (96 DPI)

| Property | BINDING |
|----------|---------|
| Height (large icons, default) | **40 px** |
| Height (small icons) | **30 px** |
| Unlocked multi-row | Multiples of **40** (40 / 80 / …) |
| Default edge | **Bottom** |
| Large icon size | **32×32** |
| Small icon size | **16×16** |
| Button width (icon-only combined) | ~**54–62** large / ~**30–40** small |
| Labeled MinWidth | ~**56** large / ~**40** small |
| Thumbnail default size | ~**96 px** (longest side; community) |
| Hover → thumbnails | `MouseHoverTime` default **400 ms** |
| Show Desktop strip width | **~8–15 px** (often ~8–10 without tablet stack; ~16 with pen/touch) |
| Show Desktop peek delay | **1000 ms** (`DesktopLivePreviewHoverTime`) |
| Start orb frame | **54×54** per state |

### Regions (LTR, bottom bar)

1. Start orb  
2. Pinned + running task buttons  
3. Optional toolbars  
4. Notification area + clock  
5. Show Desktop strip (far end)

---

## Grouping / combine modes

| Mode | Behavior |
|------|----------|
| **Always combine, hide labels** (default) | One button per AppUserModelID; peeks for multiple windows |
| **Combine when taskbar is full** | Labels until crowded |
| **Never combine** | One button per window + labels |

---

## Jump List structure (top → bottom)

1. Pinned destinations  
2. Recent **or** Frequent  
3. Custom categories  
4. Tasks (app verbs)  
5. Shell tasks: Open / Pin or Unpin / Close window or Close all windows  

| Gesture | Result |
|---------|--------|
| Right-click button | Jump List |
| Shift+Right-click | **Classic window menu** (not Jump List) |
| Win+Alt+N | Jump List for pin slot N |

Apps **cannot** programmatically pin themselves (Win7 policy).

---

## Notification area (right → left toward apps)

1. Show Desktop strip  
2. Clock / date (two-line when tall enough)  
3. System icons: **Action Center** · **Power** (laptops) · **Network** · **Volume**  
4. User icons (shown or overflow)  
5. Overflow chevron ▴  

Per-icon: Show icon and notifications / Only show notifications / Hide icon and notifications. Non-system icons **hidden by default**.

---

## Interaction matrix — task buttons

| Gesture | Result |
|---------|--------|
| Left-click inactive | Activate/restore last window of group |
| Left-click active foreground | **Minimize** |
| Shift+Left-click / Middle-click | New instance |
| Ctrl+Shift+Left-click | Run as administrator |
| Ctrl+Left-click (combined) | Cycle group windows |
| Right-click | Jump List |
| Shift+Right-click | System menu |
| Thumbnail × / middle-click thumbnail | Close that window |
| Win+1…0 | Launch/switch pin 1–10 |
| Shift+Win+N | New instance slot N |
| Ctrl+Win+N | Cycle slot N |
| Win+T | Focus taskbar |
| Win+B | Focus tray |
| Hover Show Desktop | Peek desktop (if enabled) after 1000 ms |
| Click Show Desktop | Toggle show desktop |
| Win+D | Show/restore desktop |
| Win+Space (hold) | Peek desktop |
| Win+M / Win+Shift+M | Minimize all / undo |

### Empty taskbar right-click menu (en-US order)

1. Toolbars ▸ (Address, Links, Tablet PC Input Panel, Desktop, New toolbar…)  
2. Cascade windows  
3. Show windows stacked  
4. Show windows side by side  
5. Show the desktop  
6. Start Task Manager  
7. Lock the taskbar  
8. Properties  

---

## Multi-monitor (Win7 truth)

| Fact | Native Win7 |
|------|-------------|
| Taskbar on secondary | **No** — single taskbar on primary only |
| Per-monitor bars | Third-party only |

> Omarchy multi-monitor Superbar policy is a **product delta** — document explicitly; do not claim as Win7 parity.

---

## Win7 vs Omarchy notes

| Win7 | Omarchy |
|------|---------|
| Height 40 | `barHeight` **48** |
| Action Center flag | Notification Center / QS (2026) |
| Single primary bar | Multi-monitor bars (delta) |
| Jump List Close window / Close all | Close window / Close group |

**Anti-invent:** No Superbar→Task Manager as `present`; End Task not LIVE under shell consequential; do not invent Recycle jump as finished taskbar.

---

## Citations

- MS Taskbar Extensions; MSDN Magazine Win7 Taskbar APIs; MS notification area help  
- MSFN/WDN taskbar height; SuperUser Show Desktop width; Seven Forums Peek delay  
- `02-START-SUPERBAR.md/.json`, `fleet-shell-win7.md`, `fleet-aero-win7.md`

---

## Open metal-verify items

1. Show Desktop strip width on Ultimate without Tablet PC Components.  
2. Exact default thumbnail size registry vs visual.  
3. LastActiveClick / cycle behavior on combined buttons stock SP1.  
4. Empty-bar menu: Peek at desktop checkable on Show Desktop strip right-click.
