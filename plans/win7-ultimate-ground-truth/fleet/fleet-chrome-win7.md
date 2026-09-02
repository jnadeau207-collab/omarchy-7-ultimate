---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# Fleet chrome — Windows 7 Ultimate caption / CSD ground truth vs Omarchy Desktop Mode freeze

**Audience:** Lead + implementers expanding `plans/win7-ultimate-ground-truth/` and Phase 1 window chrome.
**Author:** Review Chrome (adversarial chrome freeze lane).
**Date:** 2026-09-02.
**Scope:** Captions, CSD exclusion, Chromium overhang, ghost-perimeter damage. Not Start/Superbar IA (other fleet packs).
**Doctrine:** PRODUCT_DOCTRINE “Not Aero” refuses ads/telemetry/clone-as-product, **not** vague chrome. Desktop Mode must match Win7 Ultimate **mouse grammar, hit targets, and one-row caption jobs**. Literal Aero glass texture is optional; sizes and interactions are not.

---

## 1. What “match Win7” means for chrome

| Win7 Ultimate job | Must match | May diverge |
|---|---|---|
| Three caption buttons (min / max-or-restore / close), right-aligned on LTR | Order, presence, clickability, hover affordance | Exact Aero glass bitmap / glow |
| One caption row | Never stack OS bar + client bar | Client may draw its own CSD when excluded |
| Title-bar drag moves the window | Absolute-pointer drag on empty caption padding | Exact glass refraction |
| Double-click caption toggles maximize | Same as Win7 overlapped windows | — |
| Edge/corner resize | Resize on visible frame / border grab | Invisible Aero resize border thickness (DWM lie) |
| Maximize fills **work area** (taskbar reserved), not exclusive fullscreen | Work-area geometry | Hyprland `fullscreen` flag semantics |
| Snap to left/right halves against work area | Visible frame vs work-area half | Exact Win7 Aero Peek preview glass |
| No ghost outline after move/resize | Zero stale perimeter pixels outside current+margin | Compositor damage implementation |

Authority pointers: `W0_GATE.md` (three-button SSD, one-row CSD, min/max/restore, LTRB snap); `WINDOWS_7_ULTIMATE_PARITY.md` Caption / windowing section; chrome damage freeze rule in `HANDOFF_ULTIMATE_RECONCILIATION_CHROME_DAMAGE_2026-08-27.md`.

---

## 2. Win7 Ultimate ground-truth metrics (100% DPI Aero)

Win7 numbers are **theme- and DPI-dependent**. Use these as the 100% DPI Aero baseline implementers calibrate against; measure live with `WM_GETTITLEBARINFOEX` / `DwmGetWindowAttribute(DWMWA_CAPTION_BUTTON_BOUNDS)` when proving parity on a real Win7 box.

### 2.1 System metrics (API authority)

| Metric | Typical Win7 Aero @ 100% DPI | API | Citation |
|---|---:|---|---|
| Caption height | **22 px** (`SM_CYCAPTION`) | `GetSystemMetrics` | [GetSystemMetrics](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetrics) (`SM_CYCAPTION` = 4) |
| Caption button width | **SM_CXSIZE** (~25–30 theme-dependent; uxtheme close part often **28×17**) | `GetSystemMetrics` / `GetThemePartSize(WP_CLOSEBUTTON)` | Same Learn page; theme-part reports on Win7 in [GetThemePartSize discussions](https://exchangetuts.com/how-to-retrieve-the-size-of-the-minimize-maximize-and-close-button-of-a-window-1641417424352907) |
| Caption button height | **SM_CYSIZE** | `GetSystemMetrics` | Learn `SM_CYSIZE` = 31 |
| NONCLIENTMETRICS caption | `iCaptionWidth` / `iCaptionHeight` | `SystemParametersInfo(SPI_GETNONCLIENTMETRICS)` | [NONCLIENTMETRICSW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-nonclientmetricsw) |
| Per-button screen rects | Prefer live query over SM_* | `WM_GETTITLEBARINFOEX` → `TITLEBARINFOEX.rgrect` | [TITLEBARINFOEX](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-titlebarinfoex); Chromium uses this on Windows ([minimize_button_metrics_win.cc](https://chromium.googlesource.com/chromium/src.git/+/67a57736b1cd516ff05116a5c27c4c5237f151fd/chrome/browser/ui/views/frame/minimize_button_metrics_win.cc)) |
| Combined caption-button strip | Query, don’t hard-code | `DwmGetWindowAttribute(..., DWMWA_CAPTION_BUTTON_BOUNDS)` | [DWM attributes / custom frame guidance](https://learn.microsoft.com/windows/win32/dwm/customframe); SO/DWM discussions for Win7+ |
| Visible frame vs shadow | Extended frame ≠ drop shadow | `DWMWA_EXTENDED_FRAME_BOUNDS` | [GetWindowRect remarks](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect) (Vista+ invisible resize borders / Aero lie) |

### 2.2 Win7 caption interaction grammar

| Interaction | Win7 Ultimate behavior | Desktop Mode must |
|---|---|---|
| LMB on close | Closes that window | Close only the addressed window; do not steal focus onto a maximized Chrome behind before the click lands |
| LMB on max | Toggles maximize ↔ restore | Maximize = work-area placement, not exclusive fullscreen |
| LMB on min | Minimizes to taskbar | `setHidden` / omarchy-minimize path; Superbar retains group |
| LMB drag on empty caption (not on glyphs) | Moves window | Drag padding, not title-string center |
| LMB drag to top edge | Maximize (Aero Snap) | `aeroDragEnd` / hyprbars drag to top → work-area max |
| LMB drag to left/right edge | Half snap | Visible-frame snap against work-area halves |
| Double-click caption | Maximize/restore | Same |
| Click unfocused caption button | Button fires on that window | Focus/raise **after** button press, or buttons must not miss |

RTL: caption buttons flip to the left on Win7 RTL; Desktop Mode must honor summoned RTL for shell chrome (presentation flags) without flipping Chromium CSD glyph layout incorrectly.

---

## 3. Omarchy Desktop Mode freeze constants (current lock)

These are the **frozen** compensation numbers. Changing any row requires the full real-Chrome metal proof (see §6).

### 3.1 SSD (hyprbars) — server decorations

| Constant | Value | Where |
|---|---:|---|
| `bar_height` | **32 px** | `default/hypr/desktop-windows.lua` hyprbars block |
| `bar_padding` | **12 px** | same |
| `bar_button_padding` | **8 px** | same |
| Button alignment | **right** | `bar_buttons_alignment` |
| Snap inset for SSD | **32 px** (`hyprbarsSnapInset` non-CSD) | `shell/services/WindowModel.js` |
| Default float | **880×560** | WindowModel `defaultFloatRect` / lua |
| Superbar reserved height | **48 px** (`barHeight`) | `default/ultimate/start-chrome.json` |
| Title-bar drag aim (proof) | **x + 48**, **y − 16** (empty padding, not title mid) | `test/acceptance.d/hyprbars-pointer-proof.py` |
| Caption button press order | Buttons **before** focus/raise | `barDeco.cpp` (prevents × miss onto Chrome behind) |

### 3.2 CSD — client decorations (Chromium family + listed classes)

| Constant | Value | Where |
|---|---:|---|
| CSD rule | `hyprbars:no_bar`, no shadow/blur, `border_size = 0`, `rounding = 0` | `desktop-windows.lua` + `csd-clients.json` |
| Default CSD float | **1200×740** | lua + WindowModel |
| `CHROMIUM_FRAME_INSET` | **12 px** | WindowModel `frameBox` / `frameRect` |
| Visible vs compositor | Visible = compositor box inset by 12 on Chromium | proofs wait `at+12` / `size−12` |
| Caption click Y | **compositor y + 18** | `csd-caption-pointer-proof.py` (glyphs ~y+13..y+22) |
| Caption click X (from right) | close **12** / max **44** / min **76** | same proof (float compositor ~1212×752; max ~1932×1044) |
| Snap inset for CSD | **0** | `hyprbarsSnapInset` when `usesWaylandCsd` |
| Wayland CSD feature | **enabled** (`WaylandWindowDecorations`) | `config/chromium-flags.conf` — **do not restore disable** |

### 3.3 Class patterns that get CSD exclusion (`csd-clients.json`)

| Pattern family | Examples |
|---|---|
| Chromium family | chrome / chromium / Brave / Edge / Vivaldi / helium |
| Firefox family | firefox / librewolf |
| Zen | `^zen$`, `^zen-` |
| YouTube / Zoom PWAs | class regexes for youtube.com / zoom.us PWA |
| Cursor | `^[Cc]ursor$` |
| Files (Nautilus) | `^(org\.gnome\.)?[Nn]autilus$` |

**When CSD exclusion applies:** compositor class matches a `csd-clients.json` pattern → **no hyprbars row**, client paints its own one-row caption. Non-matching clients get **SSD hyprbars** (three buttons). PWAs that drop `chromium-based-browser` must still match the explicit regexes so they do not grow a second OS bar (`desktop-mode-handoff` lesson).

**When CSD exclusion does NOT apply:** foot, generic XDG apps, anything outside the pattern list → SSD. Do not invent per-app exceptions in lua without updating `csd-clients.json` and WindowModel `usesWaylandCsd` together.

---

## 4. Overhang and ghost-perimeter

### 4.1 Mechanism (Omarchy)

Chromium native-CSD texture is expanded by `CHROMIUM_FRAME_INSET` (**12 px**) so the **visible** frame is larger than the nominal compositor box. If damage only covers the nominal box, move/resize leaves a **ghost outline** (stale perimeter) and can clip the right close glyph.

Authoritative write-up: `HANDOFF_ULTIMATE_RECONCILIATION_CHROME_DAMAGE_2026-08-27.md`.

### 4.2 Win7 analogy

Win7 Aero also separates **logical** window rects from **visible** glass/shadow (`GetWindowRect` Aero lie vs `DWMWA_EXTENDED_FRAME_BOUNDS`). Parity job: **hit-testing and snap use the visible frame**; damage must cover everything the user sees. Do not snap against the compositor inset box.

### 4.3 Freeze / reopen rule

| Item | Status as of Chrome reviews through 2026-09-01 |
|---|---|
| Compensation path (inset, snap/max, caption aims, WaylandWindowDecorations on) | **FROZEN** — any churn needs full real-Chrome metal proof |
| Ghost-perimeter | **STILL OPEN** carry-forward after geometry churn (ee6321a KEEP-WITH-FIX): no `outside_pixels=0` / damage-ring grim in later packs; grim-less markdown ≠ metal eyes |
| Damage-ring margin used in prior metal proof | Current window **+ 20 px** perimeter; require `outside_pixels=0` on settled frames |

Required metal proof after any freeze-touching change (from chrome damage handoff): centered real Google Chrome; both rounded top corners; full close glyph; direct motion; drag; snap; maximize/restore; repeated cycles; absolute-pointer title-bar drag.

---

## 5. Maximize / snap geometry (Desktop Mode must)

| Verb | Must equal | Must not equal |
|---|---|---|
| Maximize | Work-area rect (`monitors.reserved` LTRB), SSD inset by hyprbars 32, CSD via `frameBox` | Exclusive Hyprland fullscreen (F11 / `fullscreen` 2) |
| Half snap L/R | Visible frame against work-area half | Compositor box ignoring 12 px Chromium inset |
| Remember placement | Skip snapped / `coversWorkArea` / off-work-area CSD boxes | Persist maximized or overhang boxes as float |

Harness: `window_is_maximized` / `geometry_is_maximized` judge **coverage**, not `fullscreen === 1`. Chrome CSD may still report `fullscreen: 1` after caption max — that is client truth, not the maximize verb.

---

## 6. Acceptance tables (implementer checklist)

### 6.1 SSD foot (hyprbars)

| Check | Pass criterion |
|---|---|
| Three buttons | Min / max / close hittable with absolute pointer |
| Drag | Empty padding drag moves > 8 px |
| Aero top | Drag to top → work-area maximized |
| Close unfocused | × closes aimed window; no focus-steal miss |
| Snap | L/R halves match work area − 32 title inset |

### 6.2 Chromium CSD

| Check | Pass criterion |
|---|---|
| One row | No hyprbars red close pixels; tab strip fused with caption |
| Click aims | y+18; close/max/min x offsets 12/44/76 from compositor right |
| Visible place | move/resize proofs use visible 1200×740 (compositor ±12) |
| Flags | `WaylandWindowDecorations` still enabled |
| Ghost | After move/resize cycles, `outside_pixels=0` within +20 px perimeter |

### 6.3 Freeze blobs (do not touch without metal proof)

| Path | Role |
|---|---|
| `default/hypr/desktop-windows.lua` | CSD rules, hyprbars metrics, borders from chrome adapter |
| `shell/services/WindowService.qml` / `WindowModel.js` | maximize, remember, frameBox/frameRect, snap |
| `default/hypr/plugins/hyprbars/barDeco.cpp` | button-before-focus |
| `default/hypr/plugins/omarchy-minimize/main.cpp` | minimize |
| `config/chromium-flags.conf` | Wayland CSD enable |
| `default/ultimate/csd-clients.json` | exclusion list |

---

## 7. Citations

### Microsoft / Win32
- [GetSystemMetrics](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetrics) — `SM_CYCAPTION`, `SM_CXSIZE`, `SM_CYSIZE`, frame metrics.
- [NONCLIENTMETRICSW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-nonclientmetricsw) — `iCaptionWidth` / `iCaptionHeight` / padded border.
- [TITLEBARINFOEX](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-titlebarinfoex) + `WM_GETTITLEBARINFOEX` — live button rects.
- [GetWindowRect](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect) — Vista+ invisible borders; use `DWMWA_EXTENDED_FRAME_BOUNDS` for visible bounds.
- [Custom window frame with DWM](https://learn.microsoft.com/windows/win32/dwm/customframe) — extended frame / caption button bounds.

### Chromium / community measurement
- Chromium `minimize_button_metrics_win.cc` — uses `WM_GETTITLEBARINFOEX` for caption button placement on Windows.
- Stack Overflow / theme-part threads documenting Win7 Aero caption button sizing and DWM button bounds (see §2.1 links).

### Omarchy product authority (repo)
- `PRODUCT_DOCTRINE.md`, `plans/project-ultimate.md` Phase 1 / W0.
- `W0_GATE.md`, `WINDOWS_7_ULTIMATE_PARITY.md` (Caption / windowing).
- `HANDOFF_ULTIMATE_RECONCILIATION_CHROME_DAMAGE_2026-08-27.md` — overhang / ghost-perimeter / freeze rule.
- `default/ultimate/csd-clients.json`, `config/chromium-flags.conf`, `default/ultimate/start-chrome.json`.
- Pointer proofs: `test/acceptance.d/hyprbars-pointer-proof.py`, `test/acceptance.d/csd-caption-pointer-proof.py`, `test/acceptance.d/windows-native-test.sh`.
- Chrome adversarial lock: freeze held through post-ee6321a tips; **ghost-perimeter still open** until metal `outside_pixels` proof after geometry churn.

---

## 8. Non-goals / traps

- Do not restore `--disable-features=WaylandWindowDecorations`.
- Do not resurrect overlay `ultimate-window-chrome` as SSD.
- Do not treat Hyprland `fullscreen === 1` as the maximize acceptance bit for CSD Chrome.
- Do not call ghost-perimeter closed from handoff markdown alone (Jesse waived W0 eyes; grim-less writeups are not metal eyes).
- Do not widen `csd-clients.json` without paired WindowModel `usesWaylandCsd` / lua pattern load and a one-row CSD grim proof.
