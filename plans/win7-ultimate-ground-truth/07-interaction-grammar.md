# 07 — Interaction Grammar & Brutal Polish (Win7 Ultimate)

**Repo path:** `plans/win7-ultimate-ground-truth/07-interaction-grammar.md`  
**Research sources:** `research/05-INTERACTION-POLISH.md` + `.json`, `fleet-aero-win7.md`, `fleet-doctrine-gaps.md` anti-invent  
**Target phases:** Phase 11 (primary), Phase 0–4 (global rules), all phases for Win+ hotkeys  
**DPI baseline:** **96 DPI / 100%** (system-wide on Win7 — not per-monitor)

---

## Purpose

Normative mouse/menu/dialog/progress/notification grammar, Aero enhancement gestures, DPI presets, themes/sounds/cursors, and **Win7-exact Win+ hotkeys** (Rule 3). Prevents Win10+ chord contamination and unbounded Phase 11 invent.

---

## Binding metrics

| Metric | Default (stock Win7) |
|--------|---------------------:|
| `SM_CXDRAG` / `SM_CYDRAG` | **4 px** |
| `SM_CXDOUBLECLK` / `SM_CYDOUBLECLK` | **4 px** |
| `SPI_GETMOUSEHOVERTIME` | **400 ms** |
| Tooltip autopop | ~**5 s** |
| Click-release slop (UX) | ~**3 px** |
| Show Desktop peek delay | **1000 ms** |
| Balloon lifetime | ~**10–30 s** (OS-clamped) |
| Dialog button baseline | **75×23** px @ 96 DPI (scales with DPI) |
| Caption visual top | **30** (`SM_CYCAPTION` **22** metric only) |
| DPI presets | 100%=96 · 125%=120 · 150%=144 |

### Drag start algorithm

```
ShouldStartDragging(ptStart, ptCur):
  rc = InflateRect(ptStart, SM_CXDRAG, SM_CYDRAG)
  return !PtInRect(rc, ptCur)   # equality with metric does NOT start drag
```

---

## Interaction matrix — global mouse

| Gesture | Result |
|---------|--------|
| Point | Hover chrome (no tooltip yet) |
| Hover ≥ SPI hover time | Tooltip / infotip |
| Left-click (up) | Activate / select |
| Double left-click | Default command |
| Right-click | Context menu |
| Double right-click | Same as single right (do not invent) |
| Shift/Ctrl + click | Contiguous / discontinuous selection |
| Wheel / Ctrl+wheel / tilt | Scroll / zoom / horizontal scroll |
| Marquee on empty | Rubber-band select |
| Esc | Cancel drag/resize/compound mouse ops |

---

## Menus

| Rule | BINDING |
|------|---------|
| Cascade | Prefer right (LTR); flip if no space; Right opens / Left closes |
| Separators | Between logical groups; never start/end/double |
| Default command | **Bold** |
| Disabled | Gray; visible; no activate |
| Mnemonics | `&` letter; OK/Cancel/Close get **no** access keys |
| Keyboard cues | Hidden until Alt/F10 unless user enables always-underline |

Surfaces: Menu bar · Drop-down · Context · System menu · Jump List.

---

## Dialogs

**Commit order (LTR, right-aligned):** OK/Do it/Yes → Don't/No → Cancel → Apply → Help  

Examples: `OK|Cancel` · `Yes|No|Cancel` · `Save|Don't Save|Cancel` · `OK|Cancel|Apply`  

Enter = default; **Esc = Cancel/Close always**. Title-bar Close ≡ Cancel (never OK).

| Icon | Use |
|------|-----|
| Error / Stop | Failures |
| Warning | Risk |
| Information | FYI |
| Question | Deprecated in UX — legacy only |

Progress: determinate fill L→R; marquee if unknown; feedback >~2s; progress UI >~5s; Cancel vs Stop semantics.

---

## Notifications

Win7 **balloons** (tray) ≠ Win10 notification center. Action Center = security/maintenance **pane** (flag icon). One balloon at a time. Win+B focuses tray; Ctrl+Win+B → app that raised message.

---

## Aero enhancements (Ultimate)

| Feature | Gesture | Result |
|---------|---------|--------|
| Snap side | Drag to L/R edge (pointer at edge; **release-commit**) or Win+Left/Right | Half work area |
| Snap max | Drag to top / Win+Up | Maximize |
| Snap restore/min | Win+Down | Restore then minimize |
| Vertical max | Drag top/bottom edge / Win+Shift+Up | Full height |
| Cross-monitor | Win+Shift+Left/Right | Move monitor |
| Shake | Shake title / Win+Home | Minimize others (toggle) |
| Peek desktop | Hover Show Desktop / Win+Space hold | Glass to desktop |
| Peek window | Hover taskbar thumbnail | That window opaque |
| Flip 3D | Win+Tab / Ctrl+Win+Tab | 3D carousel (**not** Task View) |
| Show Desktop | Click scrubber / Win+D | Toggle |

**Not Win7:** Snap Assist, corner quarters, Timeline, Win+Ctrl+D virtual desktops, Win+X Quick Link, Win+I Settings, Win+A Action Center (Win10).

---

## Win+ hotkeys — Rule 3 BINDING (excerpt)

| Hotkey | Win7 Ultimate |
|--------|---------------|
| Win | Toggle Start |
| Win+D | Show/hide desktop |
| Win+E | Explorer → **Computer** |
| Win+R | Run |
| Win+L | Lock |
| Win+Up/Down/Left/Right | Maximize / restore-min / snap |
| Win+Home | Shake keyboard twin |
| Win+Space | Peek desktop (hold) |
| Win+T / Win+B | Focus taskbar / tray |
| Win+1…0 | Pin slots |
| Win+Pause | System Properties |
| Win+X | **Mobility Center** (not Quick Link) |
| Win+Tab | **Flip 3D** (not Task View) |
| Alt+Tab / Ctrl+Alt+Tab | Flip / sticky Flip |
| Alt+F4 | Close |
| Ctrl+Shift+Esc | Task Manager |

---

## Themes / sounds / cursors

- Theme families: Aero (default Ultimate when capable) · Basic · Classic · High Contrast  
- Color intensity: right = bolder/less transparent; CPL intensity roughly clamped **13–217** before ARGB pack  
- Sound schemes: Windows Default · No Sounds · Afternoon…Sonata pack (13)  
- Cursor scheme **Windows Aero**: `aero_arrow.cur`, `aero_busy.ani`, `aero_working.ani`, resize set, `aero_link.cur`, …

---

## Win7 vs Omarchy notes

- Omarchy may keep 2026 Notification Center / QS — document as delta; do not rename Win7 Action Center semantics.  
- Task View prototype ≠ Flip 3D; if shipping Task View, label product delta.  
- Phase 11 polish binds to forty-task + PARITY residual defects — **no new capability invent** (`fleet-doctrine-gaps` §3 Phase 11).

---

## Citations

- Win7 UX Guidelines (Mouse, Dialogs, Progress, Notifications, Keyboard)  
- GetSystemMetrics / SPI hover & drag; Old New Thing SM_CXDRAG  
- Petri / TechNet Aero Snap Shake Peek; MS keyboard shortcuts archive  
- `05-INTERACTION-POLISH.md/.json`, `fleet-aero-win7.md`, `fleet-doctrine-gaps.md`

---

## Open metal-verify items

1. Confirm SPI hover 400 ms and DesktopLivePreviewHoverTime 1000 ms on clean Ultimate.  
2. Flip 3D availability when Aero hardware gate fails (must degrade — no Task View invent as Win7).  
3. MessageBox vs TaskDialog usage on stock shell dialogs.  
4. Exact balloon timeout clamp on SP1.
