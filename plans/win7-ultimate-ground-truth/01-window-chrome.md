# 01 — Window Chrome (Win7 Ultimate Aero SSD)

**Repo path:** `plans/win7-ultimate-ground-truth/01-window-chrome.md`  
**Research sources:** `research/01-WINDOW-CHROME.md` + `.json`, `fleet-aero-win7.md`, `fleet-chrome-win7.md`  
**Target phases:** Phase 1 (W0), Phase 3 (tokens), Phase 11 (polish)  
**DPI baseline:** **96 DPI / 100% scaling** (primary monitor). Scale px linearly with DPI.  
**Theme baseline:** Aero Glass (DWM ON). Aero Basic / Classic out of scope for Ultimate muscle memory.

---

## Purpose

Define **binding** Windows 7 Ultimate Aero server-side decoration (SSD) metrics, caption buttons, glass, shadows, resize hits, system menu, and Aero Snap/Shake/Peek grammar so Omarchy hyprbars implementers never guess caption height, button widths, or snap commit rules.

**Doctrine:** PRODUCT_DOCTRINE Rule 3 (muscle memory is an API). “Not Aero” refuses ads/telemetry/clone-as-product — **not** vague chrome. Match sizes, hit targets, menus, Snap/Shake/Peek. Literal glass texture may approximate; geometry and grammar must not.

---

## Binding metrics (96 DPI)


### BINDING LOCK (Review Aero vs Chrome — do not violate)

| Symbol | BINDING | Forbidden misread |
|--------|---------|-------------------|
| `SM_CYCAPTION` | **22** | Metric **band only** — never ship a **22 px title bar** as implementable height |
| Restored visual top NC chrome | **30** = `SM_CYFRAME(4) + SM_CYCAPTION(22) + SM_CXPADDEDBORDER(4)` | Do not treat SM_CYCAPTION alone as the bar |
| Caption button cluster width | **105** (aero pack measurement) | Prefer live `DWMWA_CAPTION_BUTTON_BOUNDS` for metal proof |
| Theme close true size | **28×17** (`GetThemePartSize`) | Painted theme part — not the visual hit table |
| Visual button targets | **29×20 / 27×20 / 49×20** | From `01-WINDOW-CHROME` — remain the SSD visual targets |


### Caption / border conflicts → BINDING defaults

| Layer | Value | Notes |
|-------|------:|-------|
| **BINDING restored visual caption (top NC)** | **30 px** | `SM_CYFRAME(4) + SM_CYCAPTION(22) + SM_CXPADDEDBORDER(4)`. Screenshot / SO / Aero fleet consensus. |
| Alternate if `SM_CYCAPTION=23` | **31 px** | Documented conflict — verify on metal; prefer **30** until metal says otherwise. |
| `SM_CYCAPTION` alone | **22** (sometimes **23**) | **Not** full visual title-bar height — understates Aero. |
| **BINDING L/R/B border** | **8 px** | `SM_CXSIZEFRAME(4) + SM_CXPADDEDBORDER(4)` |
| Corner radius (Aero DWM ON) | **8 px** | No public GetSystemMetrics; theme-baked. Use 8 @ 96 DPI. |
| Maximized on-screen caption approx | **~22–23 px** | Top border hangs off-screen; buttons flush to work-area top. |
| Maximized border hang | **8 px/side** in window rect | Raymond Chen / Old New Thing. |

**Rationale for BINDING 30 / 8:** Prefer Aero fleet + GetSystemMetrics chain (`CYFRAME + CYCAPTION + PADDEDBORDER`) and measured Win7 Aero screenshots over equal-box Classic metrics or Omarchy `bar_height` 32 product freeze.

### Caption buttons (asymmetric Aero — BINDING)

| Button | Width × Height @ cySize=21 | Order (LTR) |
|--------|---------------------------:|-------------|
| Minimize | **29 × 20** | 1 (leftmost of trio) |
| Maximize / Restore | **27 × 20** | 2 |
| Close | **49 × 20** | 3 (rightmost, wider, red hover) |
| Three-button cluster width | **~105 px** | DWMWA_CAPTION_BUTTON_BOUNDS measurement |
| Gap between buttons | **0** | Flush Aero style |
| Spacing close → right outer edge | **~8 px** | ≈ border |
| Theme part close (GetThemePartSize) | **28 × 17** | Painted part; visual cluster still 29/27/49 model |
| Lone Close | **49 × 20** | Same close ratio |

**Do not** use equal `SM_CXSIZE` squares (Basic/Classic look).

### Title text

| Property | BINDING |
|----------|---------|
| Font | **Segoe UI**, **9 pt**, weight **400** |
| Fill | Near-black `#000000` + glow (`DrawThemeTextEx` glow size **15**) |
| Icon | **16×16** (`SM_CXSMICON`) |
| Icon left inset | **~8 px** |
| Gap icon → title | **~4–5 px** |
| Ellipsis | `DT_LEFT \| DT_WORD_ELLIPSIS` |

### Glass / colorization (factory sample — user-overridable)

| Key | Sample default |
|-----|----------------|
| `ColorizationColor` | `0x6B74B8FC` → RGB `#74B8FC`, A≈107 |
| ColorBalance / Afterglow / Blur | 8 / 43 / 49 |
| OpaqueBlend | 0 (transparent) |
| Active vs inactive | Stronger shadow + fuller colorization when active; **no** classic Active/Inactive solid title colors when glass ON |

### Shadow (approximation — no public API)

| State | Hint |
|-------|------|
| Restored active | Soft blur extent **~15–25 px**; match screenshots |
| Inactive | ~60–70% opacity of active |
| Maximized | **No** visible outer shadow |

### Resize hit targets

| Region | Hit | Thickness |
|--------|-----|----------:|
| L/R/B edges | HTLEFT/RIGHT/BOTTOM | **8 px** |
| Corners | HTTOPLEFT… | **8×8** |
| Top | upper strip resize; remainder `HTCAPTION` | border subset |
| Maximized | resize **disabled** | — |

### Omarchy product freeze (NOT Win7 truth — intentional delta)

| Constant | Omarchy | Win7 BINDING |
|----------|--------:|-------------:|
| hyprbars `bar_height` | 32 | caption visual **30** |
| Superbar height | 48 | taskbar **40** (large) |
| Caption text token | `#eeeeee` (dark theme) | dark text on glass |

Parity work maps layout/metrics to Win7 first; tokens are a separate Personalize layer.

---

## Interaction matrix

| Gesture | Result |
|---------|--------|
| Left-drag `HTCAPTION` | Move window |
| Double-click caption | Maximize ↔ Restore |
| Left-click Minimize / Maximize / Restore / Close | Minimize / Maximize / Restore / Close |
| Left-click caption icon | System menu |
| Double-click caption icon | Close |
| Right-click caption / icon | System menu |
| Alt+Space | System menu |
| Alt+F4 | Close |
| Drag caption to left/right edge | Snap L/R **50%** work area (**pointer** at edge; commit on **release**) |
| Drag caption to top edge | Maximize |
| Drag top/bottom edge to screen edge | Vertical maximize (keep width) |
| Win+Left / Right | Side snap (cycle left↔right↔restore) |
| Win+Up | Maximize |
| Win+Down | Restore if maximized else Minimize |
| Win+Shift+Up / Down | Vertical maximize / undo |
| Win+Home | Minimize all except active (toggle) |
| Shake caption | Same as Win+Home (Aero Shake) |
| Win+Shift+Left / Right | Move to adjacent monitor |
| Maximize hover Snap Layouts flyout | **ABSENT on Win7** — click-only maximize |

### System menu order (LTR)

1. Restore (`SC_RESTORE` 0xF120)  
2. Move (`SC_MOVE` 0xF010)  
3. Size (`SC_SIZE` 0xF000)  
4. Minimize (`SC_MINIMIZE` 0xF020)  
5. Maximize (`SC_MAXIMIZE` 0xF030)  
6. *separator*  
7. Close (`SC_CLOSE` 0xF060) — default when restored  

---

## Win7 vs Omarchy notes

- Product default: **SSD via hyprbars** for normal windows; **CSD exclusion** for Chromium-family / listed classes (`csd-clients.json`) — one-row client caption, no double bar.
- Maximize = **work-area** fill (taskbar reserved), not exclusive fullscreen.
- Ghost-perimeter / Chromium `CHROMIUM_FRAME_INSET` 12 px is Omarchy damage debt — Win7 analogy is Aero shadow vs `DWMWA_EXTENDED_FRAME_BOUNDS`.
- Win7 has **no per-monitor DPI**; Omarchy may need modern DPI policy (product, not Win7 truth).

---

## Citations

1. Microsoft Learn — GetSystemMetrics, NONCLIENTMETRICS, DwmGetColorizationColor, Custom Window Frame Using DWM, WM_SYSCOMMAND, WM_NCHITTEST  
2. Engineering Windows 7 — Designing Aero Snap (Hoefnagels / Sinofsky)  
3. Raymond Chen — maximized borders hang off-screen  
4. OpenGlass CaptionMetricsTweaker (Win7 button ratios); DWMBlurGlass CustomButton (29/27/49)  
5. Stack Overflow / Google Groups — SM_CXPADDEDBORDER=4, visual caption 30 / border 8  
6. Petri — Aero Snap / Shake / Peek  
7. Research packs: `01-WINDOW-CHROME.md/.json`, `fleet-aero-win7.md`, `fleet-chrome-win7.md`

---

## Open metal-verify items

1. Confirm `SM_CYCAPTION` **22 vs 23** on clean Win7 Ultimate EN-US Aero @ 96 DPI (subsystem ≥6.0).  
2. Capture `DWMWA_CAPTION_BUTTON_BOUNDS` + `WM_GETTITLEBARINFOEX` per-button rects.  
3. Measure Show Desktop strip width without Tablet PC components (~8 vs ~16).  
4. Lock Omarchy Shake detector thresholds in acceptance tests (patent examples are not SPI).  
5. Glass blur: visual token match only — no claimed Microsoft blur-radius constant.  
6. Close hover red: measure from real Win7 Ultimate Aero atlas (~`#C75050`–`#E81123` family).
