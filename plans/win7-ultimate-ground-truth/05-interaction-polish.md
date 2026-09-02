---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# 05 — Windows 7 Ultimate Interaction Grammar + Brutal Polish

**Audience:** Omarchy Project Ultimate Phase 11 / global rules implementers  
**Edition target:** Windows 7 Ultimate (Aero capable; Rule 3 muscle memory)  
**Status:** Research bible — implement from this; do not guess hover timing, button order, or Win+ hotkeys  
**Companion:** `05-INTERACTION-POLISH.json`

---

## How to use this document

1. **Normative timings and metrics** come from Win32 system metrics / SPI defaults and the Windows 7 UX Guidelines (Microsoft Learn previous-versions / Win32 UX guide, written for Windows 7).
2. **Ultimate-specific** rows assume Aero is available (Home Premium / Professional / Ultimate / Enterprise). Starter/Home Basic lack Aero Peek/Shake/Flip 3D glass; Snap still exists on all SKUs.
3. **Win10+ must not leak in.** Especially: Win+X is Mobility Center (not Quick Link); Win+Tab is Flip 3D (not Task View); Action Center is Win7's security/maintenance pane (not Win10 notification center).
4. The **MASTER interaction table** at the end is the implementer's checklist.

---

## 1. Global mouse grammar

### 1.1 Click conventions

| Gesture | Typical effect | Notes |
|--------|----------------|-------|
| Point (no click) | Hover state + dynamic affordances | Immediate visual; no tooltip yet |
| Hover (≥ ~1 s UX guideline; **system default 400 ms** via `SPI_GETMOUSEHOVERTIME`) | Tooltip / infotip | Stay inside hover rect (`SPI_GETMOUSEHOVERWIDTH/HEIGHT`, same as double-click rect by default) |
| Single left-click | Activate non-selectable; select selectable; set caret in text | Takes effect on **button up** |
| Double left-click | Select + perform **default command** (bold in context menu); text: select word; 3rd click: sentence/paragraph | Use system double-click time (`GetDoubleClickTime`) and `SM_CX/YDOUBLECLK` |
| Single right-click | Select + show context menu | Never require for basic tasks |
| Double right-click | Same as single right-click | Do not invent a double-right action |
| Middle-click | App-defined; common: open link in new tab; taskbar: close window (Win7 explorer/taskbar behavior varies by app) | Not required for core chrome |
| Shift + left-click | Contiguous extend selection | |
| Ctrl + left-click | Toggle item in discontinuous selection | |
| Shift/Ctrl + right-click | Same selection rules as left, then context menu | |
| Wheel rotate | Vertical scroll under pointer (no focus steal) | `SPI` wheel lines/chars |
| Ctrl + wheel | Zoom where supported | |
| Wheel tilt | Horizontal scroll | |

**Sources:** [Windows 7 Mouse and Pointers UX](https://learn.microsoft.com/en-us/windows/win32/uxguide/inter-mouse); [GetSystemMetrics](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetrics); [TRACKMOUSEEVENT](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-trackmouseevent).

### 1.2 Drag thresholds (normative numbers)

| Metric | Symbol | Default (typical stock Win7) | Meaning |
|--------|--------|------------------------------|---------|
| Drag insensitivity X | `SM_CXDRAG` (68) | **4 px** each side of mouse-down | Drag starts only when pointer leaves inflated rect |
| Drag insensitivity Y | `SM_CYDRAG` (69) | **4 px** | Same |
| Double-click width | `SM_CXDOUBLECLK` (36) | **4 px** | Second click must be inside |
| Double-click height | `SM_CYDOUBLECLK` (37) | **4 px** | Second click must be inside |
| Hover time | `SPI_GETMOUSEHOVERTIME` | **400 ms** (`HOVER_DEFAULT`) | Initially equals menu dropdown time |
| Hover width/height | `SPI_GETMOUSEHOVERWIDTH/HEIGHT` | Same as double-click rect | Pointer must stay inside |

**Algorithm (Raymond Chen / system):** inflate start point by `SM_CXDRAG`/`SM_CYDRAG`; if current point is **inside or on** the rect, do **not** start drag. Equality with the metric does **not** start a drag.

```
ShouldStartDragging(ptStart, ptCur):
  rc = InflateRect(ptStart, SM_CXDRAG, SM_CYDRAG)
  return !PtInRect(rc, ptCur)
```

**Spatial forgiveness on click release:** UX guide recommends ~**3 px** slop when releasing so slight movement does not miss the target.

**Marquee (rubber-band) selection:** press on empty client/desktop area, drag beyond threshold → dashed/marquee rectangle; items intersecting (Explorer: typically intersecting) become selected; release commits. Esc cancels compound mouse ops (move/resize/split/drag).

**Sources:** [Old New Thing — SM_CXDRAG](https://devblogs.microsoft.com/oldnewthing/20100304-00/?p=14733); LearnWin32 other mouse operations; UX Mouse guide.

### 1.3 Hover tooltips timing

| Phase | Timing | Behavior |
|-------|--------|----------|
| Initial delay | **400 ms** system default (`SPI_GETMOUSEHOVERTIME`) | UX prose says “at least a second” as design intent for *reading*; implementers **must** use SPI, defaulting to 400 ms |
| Reshow | Shorter when moving between sibling tips in same app (common COMCTL32 behavior ~**100–300 ms**; follow host tooltip control) | Do not invent multi-second delays |
| Autopop | Typically **5 s** (`TTDT_AUTOPOP` class of defaults) then hide | User can dismiss by move/click |
| Kill on leave | Immediate on `WM_MOUSELEAVE` / leave hot zone | |

**Rules:** Hover is **redundant** — never require hover to discover primary UI. Tooltips for icons/buttons; infotips for richer Explorer/taskbar peeks.

### 1.4 Focus rectangles

- Always show keyboard focus when window is active and user is keyboard-navigating.
- `DrawFocusRect` / theme focus cue; width/height from `SPI_GETFOCUSBORDERWIDTH` / `SPI_GETFOCUSBORDERHEIGHT` (also `SM_CX/YFOCUSBORDER`).
- **Keyboard cues:** Underlines and focus rects may be **hidden until first Alt/F10/keyboard nav** (`SPI_GETKEYBOARDCUES` / `SPI_GETMENUUNDERLINES`). Default Win7: hide until keyboard use.
- Notify accessibility via MSAA/UI Automation or caret placement.

**Sources:** [Keyboard UI design guidelines](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/dnacc/guidelines-for-keyboard-user-interface-design).

---

## 2. Menu grammar

### 2.1 Surfaces

| Surface | Invocation | Persistence | Notes |
|---------|------------|-------------|-------|
| **Menu bar** | Click top-level; Alt / F10; Alt+mnemonic | Stays until dismiss | Standard app chrome |
| **Drop-down (popup from menu bar)** | Open from menu bar item | Hierarchical | Cascades to right (LTR) |
| **Context (shortcut) menu** | Right-click or Shift+F10 / App key; `WM_CONTEXTMENU` | At pointer / focused item | Prefer `TrackPopupMenuEx` |
| **System menu** | Alt+Space; title-bar icon click | Restore/Move/Size/Min/Max/Close | |
| **Jump List** (Win7) | Right-click taskbar button; Alt+Win+number | Tasks + recent/frequent | Not a classic HMENU but same muscle memory |

### 2.2 Cascade rules

- Open submenu on hover after brief delay **or** on click; keyboard: Right opens, Left closes (LTR).
- Cascade direction: prefer right; flip left if insufficient monitor space (`TPM_*` flags).
- Only one open branch; moving to sibling closes previous cascade.
- Do not open cascade on disabled parent.

### 2.3 Separator rules

- Use `MF_SEPARATOR` / `-` between **logical groups** (e.g. Open / Save | Print | Close).
- Never start or end a menu with a separator; never double separators.
- Separators are non-focusable / non-mnemonic.

### 2.4 Check / radio / disabled

| Kind | Visual | Behavior |
|------|--------|----------|
| Check item | Checkmark column | Toggle; independent |
| Radio item | Bullet in check column | Exclusive within group; groups separated by separators |
| Disabled | Gray text; no hilite activation | Still visible for discoverability; mouse click no-ops; skip in effective commands |
| Default command | **Bold** label | Double-click target; first item often |

### 2.5 Keyboard mnemonics (underlines)

- Mark with `&` before letter (`&File` → F̲ile).
- Alt+letter opens; within open menu, letter invokes.
- Unique within sibling scope; if duplicate, cycle.
- **Do not** assign mnemonics to OK/Cancel/Close (Enter/Esc).
- Underlines respect `SPI_GETKEYBOARDCUES`: hidden until Alt unless user enabled “Underline keyboard shortcuts always” in Ease of Access / Keyboard.
- Owner-draw must honor `ODS_NOACCEL` and `WM_MENUCHAR`.

**Sources:** [Using Menus](https://learn.microsoft.com/en-us/windows/win32/menurc/using-menus); Keyboard UI guidelines.

---

## 3. Dialog grammar

### 3.1 Commit button order and alignment (normative)

**Right-align** commit buttons in a single row at the bottom (above footnotes), even for a single OK.

**Order (LTR, left → right):**

1. OK / \[Do it\] / Yes  
2. \[Don't do it\] / No  
3. Cancel  
4. Apply (if present)  
5. Help (if present)

Examples: `OK | Cancel` · `Yes | No | Cancel` · `Save | Don't Save | Cancel` · `OK | Cancel | Apply`

**Default button:** One default (Enter). Prefer safest/most secure; else most likely. Never make destructive default unless easily undoable. Enter = default; **Esc = Cancel/Close always**.

**Access keys:** Do not assign to OK/Cancel/Close. Yes=`Y`, No=`N`.

### 3.2 Modality

| Type | Commit model | Chrome |
|------|--------------|--------|
| **Modal** | Delayed commit until OK/Yes | Blocks owner; center on owner |
| **Modeless** | Immediate commit | Close (not Cancel); may Minimize; on taskbar if primary-like |
| **Property sheet** | OK/Cancel/Apply | Apply commits without closing |

Title-bar Close ≡ Cancel (or Close if irreversible). Never ≡ OK.

### 3.3 Message box icon types and button sets

| Icon | Flags | Visual | Use |
|------|-------|--------|-----|
| Error | `MB_ICONERROR` / `STOP` / `HAND` | White X / stop | Failures |
| Warning | `MB_ICONWARNING` / `EXCLAMATION` | Exclamation | Risk / caution |
| Information | `MB_ICONINFORMATION` / `ASTERISK` | “i” | FYI / success info |
| Question | `MB_ICONQUESTION` | “?” | **Deprecated** in UX; keep only for legacy parity |

**Button sets (`uType`):**

| Set | Buttons |
|-----|---------|
| `MB_OK` | OK |
| `MB_OKCANCEL` | OK, Cancel |
| `MB_YESNO` | Yes, No |
| `MB_YESNOCANCEL` | Yes, No, Cancel |
| `MB_RETRYCANCEL` | Retry, Cancel |
| `MB_ABORTRETRYIGNORE` | Abort, Retry, Ignore (legacy) |
| `MB_CANCELTRYCONTINUE` | Cancel, Try Again, Continue (prefer over Abort/Retry/Ignore) |

Default button: `MB_DEFBUTTON1..4`. Esc maps to Cancel when present.

**UX polish:** Prefer task dialogs (Vista+) with main instruction; prefer specific verbs over OK/Yes when clear; use Close not OK on pure errors.

**Sources:** [Dialog Boxes UX](https://learn.microsoft.com/en-us/windows/win32/uxguide/win-dialog-box); [MessageBoxW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-messageboxw).

---

## 4. Progress / wait

### 4.1 Determinate vs indeterminate (marquee)

| Mode | When | Visual |
|------|------|--------|
| **Determinate** | Bounded work (even if estimate noisy) | Fill L→R; must reach 100% only when done; never restart/back up |
| **Indeterminate / marquee** | Unknown bound (`PBS_MARQUEE`) | Continuous pulse/cycle L→R |
| **Busy pointer** | Wait >1 s, UI frozen | `IDC_WAIT` / `aero_busy.ani` — no hot spot |
| **Working in background** | Wait >1 s, UI still interactive | `IDC_APPSTARTING` / `aero_working.ani` |
| **Activity indicator** | ≤ ~5 s | Prefer over progress bar for short ops |

**Rules:** Don't combine progress bar + busy pointer. Horizontal only. Red = recoverable block; yellow = paused/impeded; green/normal = running. Label above: verb + ellipsis (“Copying…”). Cancel if reversible; **Stop** if partial results remain.

**Timing gates:** >~2 s → some feedback; >5 s → progress UI; >30 s consider modeless; >2 min background → notification on completion (optional sound).

### 4.2 Copy dialog (Win7 Explorer style)

Win7 copy/move dialog hallmarks for polish parity:

- Title: operation context (e.g. item name / “Copying…”); modeless enough that closing Explorer owner can leave copy running.
- Primary determinate bar for overall bytes/files; filename and path details meaningful to user.
- Speed / time remaining when estimable (`Time remaining: m minutes, s seconds` patterns from UX guide).
- **Pause** / **Cancel**; on conflict: per-file choices (replace/skip/keep both — Win7 “Copy File” conflict UI).
- Error mid-stream: bar can go red; offer Skip / Retry / Cancel without abandoning all when recoverable.
- Animation/illustration optional; don't entertain without purpose.

**Sources:** [Progress Bars UX](https://learn.microsoft.com/en-us/windows/win32/uxguide/progress-bars); Dialog progress patterns.

---

## 5. Notifications (Win7)

### 5.1 Balloon tips vs Action Center

| Mechanism | What it is | Criticality | Lifetime |
|-----------|------------|-------------|----------|
| **Balloon tip** from notification area icon | `Shell_NotifyIcon` + `NIF_INFO` | Useful, **not** critical; asynchronous | OS-clamped ~**10–30 s**; idle time doesn't count; one balloon at a time |
| **Notification Area flyout / icons** | Persistent tray icons | Click for status | User can hide icons (“Only show notifications”) |
| **Action Center** (Win7) | Flag icon → security & maintenance messages | Important system health | Pane, not toast; different from Win10 Action Center |

**Do not confuse:** Win7 Action Center ≠ Win10 notification center. Win7 balloons are the primary toast-like surface.

### 5.2 Tray / balloon behaviors

- Only **one** balloon visible; queueing rules: other-app balloons wait min timeout; same-app often replaces.
- Click balloon → `NIN_BALLOONUSERCLICK`; timeout/X → `NIN_BALLOONTIMEOUT`.
- Hover icon → ordinary tooltip (`NIF_TIP`), not balloon.
- Quiet / fullscreen etiquette: respect presentation settings; don't steal focus.
- Win+B focuses notification area; Ctrl+Win+B switches to app that raised a message.

**Sources:** [Notifications UX](https://learn.microsoft.com/en-us/windows/win32/uxguide/mess-notif); [Notification Area](https://learn.microsoft.com/en-us/windows/win32/shell/notification-area); NotifyIcon timeout docs.

---

## 6. Alt+Tab / Win+Tab (Flip 3D) — Ultimate Aero behavior

### 6.1 Alt+Tab (Windows Flip)

- Hold Alt, press Tab: **flat** live thumbnails (Aero) or icons (Basic) of open windows.
- Repeated Tab / Shift+Tab cycle; release Alt to activate selected.
- **Ctrl+Alt+Tab**: persistent Flip UI; arrow keys + Enter; Esc cancel.
- Includes open top-level windows; desktop as target in some modes; order ≈ Z-order / MRU.

### 6.2 Win+Tab (Aero Flip 3D) — Ultimate / Aero only

- **Win+Tab**: 3D stacked carousel of live windows; Tab/Shift+Tab or wheel/click cycles while Win held; release Win to commit.
- **Ctrl+Win+Tab**: sticky Flip 3D; arrows to select; Esc cancel.
- Requires DWM composition (Aero). On Basic/Classic: no Flip 3D (degrade: do not invent Win10 Task View).
- **Not** virtual desktops.

### 6.3 Related

| Shortcut | Behavior |
|----------|----------|
| Alt+Esc | Cycle windows in open order (no UI chrome) |
| Win+T | Focus taskbar buttons; arrows cycle |

---

## 7. Aero desktop enhancements (complete gesture list)

Available on Aero-capable SKUs (Ultimate included). Snap also on non-Aero SKUs.

| Feature | Gesture / shortcut | Result |
|---------|-------------------|--------|
| **Aero Snap — side** | Drag title bar to left/right edge until reveal cue; or **Win+Left / Win+Right** | Fill half work area |
| **Aero Snap — maximize** | Drag title to top edge; or **Win+Up** | Maximize |
| **Aero Snap — restore/minimize** | Drag maximized off top; or **Win+Down** | Restore then minimize on second |
| **Aero Snap — vertical stretch** | Drag top or bottom edge to monitor edge; or **Win+Shift+Up** | Full height, keep width |
| **Aero Snap — cross-monitor** | **Win+Shift+Left/Right** | Move window to adjacent monitor |
| **Aero Shake** | Grab title bar, shake left-right rapidly; or **Win+Home** | Minimize all others; repeat to restore |
| **Aero Peek — desktop** | Hover **Show desktop** scrubber (far right of taskbar); or hold **Win+Space** | Glass outlines / transparent windows; click scrubber = show desktop (like Win+D) |
| **Aero Peek — window** | Hover taskbar thumbnail | That window opaque; others glass |
| **Aero Flip 3D** | Win+Tab / Ctrl+Win+Tab | See §6 |
| **Live taskbar thumbnails** | Hover running taskbar button | Thumbnail(s); grouped apps show multiple |
| **Jump Lists** | Right-click taskbar button / drag up | Tasks + destinations |
| **Show Desktop** | Click scrubber; Win+D toggle; Win+M minimize-all | Win+D restores; Win+M needs Win+Shift+M |

**Not Win7:** Snap Assist lists, Corner snap quarters (Win10+), Timeline, virtual desktop Win+Ctrl+D.

**Sources:** TechNet Aero Peek wiki; Petri Aero Snap/Shake/Peek; Wikipedia Windows Aero; Microsoft keyboard shortcut lists mirrored in Win7 Help / 4sysops.

---

## 8. High DPI / font scaling (Win7)

### 8.1 Presets

| UI label | Scale | DPI | Notes |
|----------|-------|-----|-------|
| Smaller | **100%** | **96** | Baseline design unit |
| Medium | **125%** | **120** | Common on large high-res panels |
| Larger | **150%** | **144** | |
| Custom | 100–500% | variable | “Set custom text size (DPI)” |

Logoff usually required to apply system DPI.

### 8.2 Effects on chrome

- **DPI-aware** apps: metrics, non-client caption, menus, dialogs scale; fonts request larger px sizes.
- **Unaware** apps: bitmap-stretched by Win7 → blurry; mitigation checkbox **“Use Windows XP style DPI scaling”** (system DPI virtualization off for cleaner XP-style fonts at cost of tiny UI).
- At **>144 DPI** with Aero, Microsoft warned of blur in non–high-DPI programs.
- Chrome implications for Omarchy: caption buttons, menu bar height, dialog button **75×23** px baselines scale with DPI; hit targets must track scaled metrics; icons prefer multi-res.
- Win7 DPI is **system-wide** (not per-monitor like Win8.1+).

**Sources:** Windows 7 Display / DPI help; community DPI writeups citing Microsoft Display CPL.

---

## 9. Themes: Aero vs Basic vs Classic

| Theme family | DWM glass | Default on Ultimate? | Colorization |
|--------------|-----------|----------------------|--------------|
| **Windows 7 Aero** (e.g. “Windows 7”, regional Aero themes) | Yes — transparency, Peek, Flip 3D, live thumbs | **Yes**, when hardware/driver passes Aero | Window Color + Intensity |
| **Windows 7 Basic** | No glass; opaque | Fallback if Aero fails / disabled | Limited |
| **Windows Classic** | No | Opt-in / high contrast adjacent | Classic metrics colors |
| High Contrast | Accessibility | Opt-in | Forced HC palette |

### Colorization intensity slider

- Path: Personalize → Window Color and Appearance.
- **Enable transparency** checkbox toggles glass alpha path.
- **Color intensity** slider: move **right** → bolder / less see-through tint; **left** → softer / more transparent. Maps into DWM colorization alpha (`CColorizationColor`); Control Panel clamps intensity roughly **13–217** (`0x0D–0xD9`) before packing ARGB for `DwmSetColorizationParameters`.
- Optional **color mixer**: Hue / Saturation / Brightness (HSB) then converted to DWM parameters.
- Affects glass frame, taskbar, Start orb glow regions consistently.

**Sources:** Win7 Personalization tutorials; DWM colorization calculator notes (ALTaleX531) documenting CPL mapping.

---

## 10. Sounds — scheme names commonly expected

**Always present:**

- **Windows Default** — stock Win7 sounds  
- **No Sounds** — mute program events (startup may still play)

**Extra themed schemes (Win7 feature pack / inbox themes; 13 names):**

Afternoon · Calligraphy · Characters · Cityscape · Delta · Festival · Garden · Heritage · Landscape · Quirky · Raga · Savanna · Sonata

Common **event** names implementers map (Windows Default): Asterisk, Critical Battery Alarm, Critical Stop, Default Beep, Device Connect/Disconnect, Exclamation, Exit Windows, Fatal App Exit, Information Bar, Logoff/Logon, Low Battery Alarm, Mail Beep, Menu Command/Popup, New Fax/Mail, Open/Close Program, Print Complete, Program Error, Question, Restore/Maximize/Minimize/Open/Close (windows), Start Navigation, System Asterisk/Exclamation/Exit/Hand/Notification/Question, Windows Logon/Logoff/Notify/Startup, etc. (exact set under `AppEvents\Schemes\Apps\.Default`).

**Sources:** Windows Blog / personalization docs listing schemes; mswintheme fandom scheme list.

---

## 11. Cursors — standard Aero set

Scheme display name: **Windows Aero**. Files under `%SystemRoot%\Cursors\`:

| Role | Registry / IDC | File |
|------|----------------|------|
| Normal select | Arrow | `aero_arrow.cur` |
| Help select | Help | `aero_helpsel.cur` |
| Working in background | AppStarting | `aero_working.ani` |
| Busy | Wait | `aero_busy.ani` |
| Precision | Crosshair | `aero_precision.cur` / `aero_prec.cur` / `aero_select.cur` (precision) |
| Text select | IBeam | `aero_select.cur` (text) — verify role split in theme |
| Handwriting | NWPen | `aero_pen.cur` |
| Unavailable | No | `aero_unavail.cur` |
| NS resize | SizeNS | `aero_ns.cur` |
| EW resize | SizeWE | `aero_ew.cur` |
| NW–SE resize | SizeNWSE | `aero_nwse.cur` |
| NE–SW resize | SizeNESW | `aero_nesw.cur` |
| Move | SizeAll | `aero_move.cur` |
| Alternate select | UpArrow | `aero_up.cur` |
| Link select | Hand | `aero_link.cur` |

**UX rules:** Hand pointer **only** for links. Busy = no clicking. Show busy if wait >1 s without other progress UI.

---

## 12. Win+ hotkeys — Windows 7 exact list (Rule 3)

> **Omarchy Desktop Mode must honor Win7 meanings.** Do not implement Win10/11 bindings for these chords.

### 12.1 Core Rule-3 set (explicitly called out)

| Hotkey | Win7 Ultimate behavior | NOT (Win10+) |
|--------|------------------------|--------------|
| **Win** | Toggle Start menu | |
| **Win+D** | Show/hide desktop (toggle) | |
| **Win+E** | Open Explorer at **Computer** | |
| **Win+R** | Run dialog | |
| **Win+L** | Lock / switch user | |
| **Win+Up** | Maximize | |
| **Win+Down** | Restore / minimize | |
| **Win+Left** | Snap left half | |
| **Win+Right** | Snap right half | |
| **Win+Home** | Shake-equivalent: minimize all but active | |
| **Win+P** | Presentation / projector mode (`DisplaySwitch`) | |
| **Win+X** | **Windows Mobility Center** | ≠ Win10 Quick Link menu |
| **Win+Tab** | **Aero Flip 3D** | ≠ Task View |
| **Win+Space** | **Aero Peek** desktop (hold) | ≠ language change (Win10) |

### 12.2 Full Win+ inventory (Win7 Help)

| Hotkey | Action |
|--------|--------|
| Win | Start menu |
| Win+Pause/Break | System Properties |
| Win+D | Show desktop (toggle) |
| Win+M | Minimize all |
| Win+Shift+M | Restore after Win+M |
| Win+E | Computer (Explorer) |
| Win+F | Search files/folders |
| Ctrl+Win+F | Search computers (domain) |
| Win+L | Lock |
| Win+R | Run |
| Win+T | Cycle taskbar programs |
| Win+number (1–9,0) | Start/switch pinned taskbar item by position |
| Shift+Win+number | New instance of pinned item |
| Ctrl+Win+number | Switch to last active window of pinned item |
| Alt+Win+number | Open Jump List for pinned item |
| Win+Tab | Flip 3D |
| Shift+Win+Tab | Flip 3D reverse |
| Ctrl+Win+Tab | Sticky Flip 3D |
| Ctrl+Win+B | Focus app that showed notification |
| Win+Space | Peek desktop |
| Win+Up / Down / Left / Right | Maximize / restore-min / snap L / snap R |
| Win+Home | Minimize others |
| Win+Shift+Up | Vertical stretch |
| Win+Shift+Left/Right | Move window across monitors |
| Win+P | Presentation display mode |
| Win+G | Cycle Desktop Gadgets |
| Win+U | Ease of Access Center |
| Win+X | Mobility Center |
| Win++ / Win+- | Magnifier zoom in/out |
| Win+U | Ease of Access (listed above) |

**Absent in Win7 (do not honor as Win7 muscle memory):** Win+A (Action Center Win10), Win+I (Settings), Win+K (Connect), Win+S (Search Cortana — OneNote owned Win+S on some installs), Win+Ctrl+D (virtual desktop), Win+. (emoji).

**Taskbar modifiers:** Shift+click = new instance; Ctrl+Shift+click = elevated; Ctrl+click grouped = cycle windows.

**Sources:** Windows 7 Help keyboard shortcuts (via 4sysops mirror of TechNet/Help); MSDN archive `bb545461`; Hongkiat Win7 shortcuts.

---

## MASTER interaction table

Surface | Control | Gesture | Result | Notes | Source
-------|---------|---------|--------|-------|--------
Desktop | Icon | Single left-click | Select | Win7 default single-click select when configured; classic double-click open | UX Mouse
Desktop | Icon | Double left-click | Open default command | Bold item in context menu | UX Mouse
Desktop | Empty | Left drag | Marquee select | After SM_CX/YDRAG | Win32 DragDetect
Desktop | Empty | Right-click | Desktop context menu | View / Sort / Refresh / Paste / Personalize… | Shell
Desktop | Icon | Right-click | Icon context menu | Open bold = default | Shell
Any | Object | Hover 400ms | Tooltip | SPI_GETMOUSEHOVERTIME | TRACKMOUSEEVENT
Any | Focusable | Keyboard nav | Focus rectangle | May hide until cues | SPI_GETKEYBOARDCUES
Window | Title bar | Drag to left/right edge | Snap half | Aero Snap | Win7 Help
Window | Title bar | Drag to top | Maximize | Snap | Win7 Help
Window | Title bar | Shake | Minimize others | Aero Shake; Win+Home | Petri/TechNet
Window | Caption buttons | Left-click Min/Max/Close | Standard NC actions | Hot on button-up | Win32
Taskbar | Show desktop scrubber | Hover | Peek desktop | Aero Peek | TechNet Wiki
Taskbar | Show desktop scrubber | Click | Show desktop | Like Win+D | TechNet Wiki
Taskbar | App button | Hover | Thumbnail + peek | Live preview | Aero
Taskbar | App button | Right-click | Jump List | Win7 | Shell
Taskbar | App button | Shift+click | New instance | | Win7 Help
Taskbar | Notification area | Hover icon | Icon tooltip | NIF_TIP | Shell_NotifyIcon
Taskbar | Notification area | Balloon | Async notice | 10–30s clamp | NotifyIcon docs
Taskbar | Action Center flag | Click | Win7 Action Center | Security/maintenance | Win7 shell
Menu bar | Top-level | Click / Alt+mnemonic | Open drop-down | Underlines per cues | Menus API
Menu | Item | Click | Command | Disabled gray no-op | UX
Menu | Item with submenu | Hover/Click/Right | Cascade | Flip if no space | TrackPopupMenuEx
Menu | Separator | — | Visual group | No ends/doubles | Convention
Menu | Check/Radio | Click | Toggle/exclusive | Check column | Menus
Context menu | Target | Right-click / Shift+F10 | Shortcut menu | Default bold | WM_CONTEXTMENU
Dialog | Commit row | Visual layout | OK…Help right-aligned | Order §3.1 | Dialog UX
Dialog | Default button | Enter | Invoke default | Safest preferred | Dialog UX
Dialog | Any | Esc | Cancel/Close | Always | Dialog UX
Dialog | Modal | Display | Block owner | Center on owner | Dialog UX
MessageBox | Error | MB_ICONERROR + buttons | Stop glyph | Prefer Close over OK for pure errors | MessageBoxW
MessageBox | Warning | MB_ICONWARNING | Exclamation | | MessageBoxW
MessageBox | Info | MB_ICONINFORMATION | Info glyph | | MessageBoxW
MessageBox | Question | MB_ICONQUESTION | Deprecated UX | Legacy only | MessageBoxW
Progress | Determinate bar | Operation | Fill % | No restart | Progress UX
Progress | Marquee bar | Unknown duration | PBS_MARQUEE | Convert to determinate when possible | Progress UX
Progress | Copy dialog | File copy/move | Win7 copy UI | Pause/Cancel; conflicts | Explorer + Progress UX
Wait | Cursor | >1s block | aero_busy.ani | No hotspot | UX Mouse
Wait | Cursor | >1s background | aero_working.ani | Clickable | UX Mouse
Switcher | Alt+Tab | Hold Alt+Tab | Flip thumbnails | Ctrl+Alt+Tab sticky | Win7 Help
Switcher | Win+Tab | Hold Win+Tab | Flip 3D | Aero only | Win7 Help
System | Win+D | Key | Toggle desktop | Rule 3 | Win7 Help
System | Win+E | Key | Explorer Computer | Rule 3 | Win7 Help
System | Win+R | Key | Run | Rule 3 | Win7 Help
System | Win+L | Key | Lock | Rule 3 | Win7 Help
System | Win+X | Key | Mobility Center | **Not** Win10 menu | Win7 Help
System | Win+P | Key | Project/display mode | | Win7 Help
System | Win+Home | Key | Minimize others | Shake kbd | Win7 Help
System | Win+Space | Key hold | Peek desktop | | Win7 Help
System | Win+Left/Right/Up/Down | Key | Snap/max/restore | | Win7 Help
Personalize | Color intensity | Slider | Glass boldness/alpha | ~13–217 CPL clamp | DWM notes
Personalize | Theme | Select Aero/Basic/Classic | Chrome family | Ultimate defaults Aero | Personalize CPL
Display | DPI | 100/125/150% | 96/120/144 DPI | Logoff apply | Display CPL
Sound | Scheme | Windows Default / No Sounds / 13 themes | Event WAV map | Afternoon…Sonata | Personalize sounds
Cursor | Scheme | Windows Aero files | Role→.cur/.ani | Hand=links only | Theme [Cursors]

---

## Implementation non-negotiables (Phase 11)

1. Read **SPI/SM** at runtime where possible; fall back to defaults in this doc (400 ms hover, 4 px drag/double-click).  
2. Dialog commit order is **OK → No → Cancel → Apply → Help**, right-aligned — never macOS/GTK Cancel→OK by default in Desktop Mode.  
3. Esc always cancels; Enter fires default.  
4. Win+X / Win+Tab / Win+Space mean **Win7** things.  
5. Balloons ≠ Action Center ≠ Win10 toast center.  
6. Hover never required for primary commands.  
7. Hand cursor only for hyperlinks.  
8. Progress: determinate preferred; marquee only when bound unknown; copy dialog matches Win7 forgiveness (Pause/Cancel/conflict).

---

## Citation index

1. Microsoft — *Windows 7 Mouse and Pointers* — https://learn.microsoft.com/en-us/windows/win32/uxguide/inter-mouse  
2. Microsoft — *Dialog Boxes (Windows 7 design guide)* — https://learn.microsoft.com/en-us/windows/win32/uxguide/win-dialog-box  
3. Microsoft — *Progress Bars* — https://learn.microsoft.com/en-us/windows/win32/uxguide/progress-bars  
4. Microsoft — *Notifications* — https://learn.microsoft.com/en-us/windows/win32/uxguide/mess-notif  
5. Microsoft — *MessageBoxW* — https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-messageboxw  
6. Microsoft — *GetSystemMetrics* — https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetrics  
7. Microsoft — *TRACKMOUSEEVENT* — https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-trackmouseevent  
8. Microsoft — *Using Menus* — https://learn.microsoft.com/en-us/windows/win32/menurc/using-menus  
9. Microsoft — *Guidelines for Keyboard User Interface Design* — https://learn.microsoft.com/en-us/previous-versions/windows/desktop/dnacc/guidelines-for-keyboard-user-interface-design  
10. Microsoft — *Notification Area* — https://learn.microsoft.com/en-us/windows/win32/shell/notification-area  
11. Raymond Chen — *SM_CXDRAG equality* — https://devblogs.microsoft.com/oldnewthing/20100304-00/?p=14733  
12. TechNet Wiki — *Windows 7 Aero Peek* — https://learn.microsoft.com/en-us/archive/technet-wiki/2783.windows-7-aero-peek-feature  
13. Petri — *Aero Peek, Shake & Snap* — https://petri.com/new-aero-features-in-windows-7/  
14. Wikipedia — *Windows Aero* — https://en.wikipedia.org/wiki/Windows_Aero  
15. 4sysops — *Windows 7 keyboard shortcuts complete list* (from Win7 Help) — https://4sysops.com/archives/windows-7-keyboard-shortcuts-the-complete-list/  
16. MSDN archive — *Windows Keyboard Shortcut Keys* — https://web.archive.org/web/20120424082851/msdn.microsoft.com/en-us/library/bb545461.aspx  
17. Windows personalization — sound schemes listing (Windows Default, No Sounds, 13 themes)  
18. Aero cursor theme mapping — Windows 7 theme `[Control Panel\Cursors]` → `aero_*.cur/.ani`  
19. DWM colorization intensity mapping notes — https://github.com/ALTaleX531/dwm_colorization_calculator  

---

*End of 05-INTERACTION-POLISH.md — Phase 11 polish bible.*
