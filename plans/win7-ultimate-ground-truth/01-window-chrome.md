---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

> **Caption BINDING LOCK (all chrome consumers):** Restored visual top NC = **30** px (`SM_CYFRAME` 4 + `SM_CYCAPTION` **22** + `SM_CXPADDEDBORDER` 4). `SM_CYCAPTION` alone is **not** the title-bar height. Visual buttons **29×20 / 27×20 / 49×20**; cluster **~105**; theme close part **28×17**. Prefer live `DWMWA_CAPTION_BUTTON_BOUNDS` for metal proof.

# 01 — Windows 7 Ultimate Aero Window Chrome (Ground Truth)

**Product:** Omarchy Project Ultimate  
**Scope:** System-drawn SSD window frame (caption, borders, caption buttons, shadows, interactions) matching **Windows 7 Ultimate + Aero Glass** muscle memory **exactly**.  
**DPI baseline:** 96 DPI (100% scaling), primary monitor. Scale all px linearly with DPI unless noted.  
**Theme baseline:** Aero (DWM composition ON). Aero Basic / Classic are out of scope for “Ultimate muscle memory.”

> **Do not invent Omarchy token colors as Win7 truth.**  
> Section 9 separates **Win7 Ultimate ground truth** from **current Omarchy tokens**.

---

## 0. How to read sizes (API vs eyeball)

Windows intentionally “lies” about Aero frame sizes for appcompat. Visual (what the eye sees) ≠ raw `GetSystemMetrics` for older (pre-Vista) subsystem apps.

| Layer | What it means | How to obtain |
|-------|---------------|---------------|
| **Visual frame** | What users measure from screenshots | `DwmGetWindowAttribute(..., DWMWA_EXTENDED_FRAME_BOUNDS)` or screen ruler |
| **Logical metrics** | Vista+ (`_WIN32_WINNT ≥ 0x0600`) | `SM_CXSIZEFRAME` + `SM_CXPADDEDBORDER`, `SM_CYCAPTION`, etc. |
| **Compat lie** | Pre-6.0 apps | Inflated `SM_CXFRAME` / no padded border |

**Canonical visual restored Aero frame at 96 DPI** (widely measured on Win7 Aero):

- **Caption (title bar) height including top glass strip:** **30 px**
- **Left / right / bottom border width:** **8 px** each

Sources:

- Screenshot measurement of Win7 Aero: title **30 px**, border **8 px** — [Stack Overflow: non-client size in WPF](https://stackoverflow.com/questions/6032032/how-do-i-compute-the-non-client-window-size-in-wpf)
- Formula used by Firefox / Chromium-class code:  
  `captionHeight = SM_CYFRAME + SM_CYCAPTION + SM_CXPADDEDBORDER` — [ExchangeTuts / SO caption height](https://www.exchangetuts.com/index.php/how-to-get-the-default-caption-bar-height-of-a-window-in-windows-1641624483764321)
- Vista+ padded border default **4 px**; size frame **4 px** → visual **8 px** — [Google Groups: SM_CXPADDEDBORDER](https://groups.google.com/g/comp.lang.clipper.visual-objects/c/IakwBqOvJr4), [MSDN NONCLIENTMETRICS](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-nonclientmetricsw)
- Autodesk notes: Aero `SM_CXFRAME` must add `SM_CXPADDEDBORDER` for true thickness — [3ds Max DLGetSystemMetrics](https://help.autodesk.com/cloudhelp/2027/ENU/MAXDEV-CPP-API-REF/3dsmaxdlport_8h.html)
- Maximized: borders still “exist” but hang off-screen (~**8 px** per side → window rect larger than work area by **16×16**) — [SO: 1920 DIP](https://stackoverflow.com/questions/36182487/why-is-1920-device-independent-units-not-1920-pixel-with-96-dpi), [Raymond Chen / Old New Thing](https://devblogs.microsoft.com/oldnewthing/20120326-00/?p=8003)

**Typical Vista+ 96 DPI metric values (Aero):**

| Metric | Index | Typical value | Role |
|--------|-------|---------------|------|
| `SM_CYCAPTION` | 4 | 21–22 | Caption text band (not full visual top) |
| `SM_CYSIZE` / `iCaptionHeight` | 31 | 21 | Caption **button** height metric |
| `SM_CXSIZE` / `iCaptionWidth` | 30 | ~35 | Legacy **equal** button-width metric (Aero **overrides** visually) |
| `SM_CXSIZEFRAME` / `SM_CYSIZEFRAME` | 32/33 | 4 | Sizing border (Vista+ apps) |
| `SM_CXPADDEDBORDER` | 92 | 4 | Padded border (default) |
| **Visual L/R/B border** | — | **8** | `SIZEFRAME + PADDEDBORDER` |
| **Visual top chrome** | — | **30** | `CYCAPTION + CYFRAME + PADDEDBORDER` (≈21+4+4 or 22+4+4) |

---

## 1. Aero Glass caption bar

### 1.1 Heights

| State | Visual caption / top chrome height (96 DPI) | Notes |
|-------|---------------------------------------------|-------|
| **Restored** | **30 px** | Includes glass above client; measured Win7 Aero |
| **Maximized** | **~22–23 px** effective on-screen | Top resize border is off-screen; caption buttons sit flush with top of work area; glass side borders also off-screen |

Implementers should treat **restored caption content row ≈ 20–22 px** inside the **30 px** top chrome, with **~8 px** of top glass/border above the client edge contributing to the 30.

Query helpers:

- `WM_GETTITLEBARINFOEX` → `TITLEBARINFOEX.rcTitleBar` and per-button `rgrect[]` — [SO / Cody Gray](https://stackoverflow.com/questions/6032032/how-do-i-compute-the-non-client-window-size-in-wpf)
- `DwmGetWindowAttribute(DWMWA_CAPTION_BUTTON_BOUNDS)` for button strip bounds
- `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` for true outer rect

### 1.2 Blur / tint behavior

- Glass is composited by **DWM** (`dwmapi.dll`). Blur of desktop content behind the frame + colorization tint.
- User base color + intensity from Personalize → Window Color.
- Documented query: **`DwmGetColorizationColor`** → `0xAARRGGBB` + opaque-blend flag — [MSDN](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmgetcolorizationcolor)
- Registry (undocumented but stable on NT 6.1): `HKCU\Software\Microsoft\Windows\DWM`

| Value | Meaning | Default example (factory sky blue theme) |
|-------|---------|------------------------------------------|
| `ColorizationColor` | Base / blend color `0xAARRGGBB` | `0x6B74B8FC` (A≈107, RGB `#74B8FC`) — [ServerFault default DWM keys](https://serverfault.com/questions/612485/set-default-wallpaper-for-all-users-in-win7) |
| `ColorizationAfterglow` | Afterglow | often same as color |
| `ColorizationColorBalance` | Color intensity 0–100 | `8` (default sample) |
| `ColorizationAfterglowBalance` | Afterglow balance | `43` |
| `ColorizationBlurBalance` | Blur vs color | `49` |
| `ColorizationGlassReflectionIntensity` | Top-edge reflection streak | `0`–`50` typical; sample default `0` or `50` depending on image |
| `ColorizationOpaqueBlend` | Opaque glass (no transparency) | `0` = transparent |

Sources: [tweaks.com DWM keys](https://tweaks.com/windows/39465/windows-7-dwm-registry-keys/), [Quppa on colorization](https://www.quppa.net/blog/2011/03/21/wm_dwmcolorizationcolorchanged-doesnt-give-the-aero-glass-base-colour/), [SO glass color](https://stackoverflow.com/questions/3560890/vista-7-how-to-get-glass-color).

**Active vs inactive chrome:**

- Aero does **not** use classic “Active Title Bar / Inactive Title Bar” solid colors when glass is on — [SuperUser](https://superuser.com/questions/403642/distinction-between-active-inactive-windows-titlebars-with-windows-7-aero).
- Focus is communicated by: **stronger drop shadow** on active, **fuller colorization** on active caption buttons / frame, **desaturated / dimmer** glass on inactive.
- Inactive ≈ reduced color intensity over the same glass recipe (exact shader is internal to DWM; do not hardcode a second arbitrary hex as “Win7 inactive color” unless measured from a specific Personalize preset).

### 1.3 Glass margin / reflection

- Frame glass wraps L/T/R/B of the window. Client content is opaque (unless app calls `DwmExtendFrameIntoClientArea`).
- Top of glass often shows a **specular / reflection strip** controlled by `ColorizationGlassReflectionIntensity`.
- MSDN custom-frame sample uses top extend **27**, sides **8**, bottom **20** as *example* margins when drawing into glass — [Custom Window Frame Using DWM](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe). Those are **sample** numbers for CSD tutorials, not a claim that SSD chrome is 27 px tall (visual SSD top is **30**).

### 1.4 Borders (LTRB) and corner radius

| Edge | Restored visual width | Maximized visual |
|------|----------------------|------------------|
| Left | **8 px** | Off-screen (~8 px still in window rect) |
| Top | part of **30 px** caption chrome | Off-screen strip; caption flush to work-area top |
| Right | **8 px** | Off-screen |
| Bottom | **8 px** | Off-screen |

**Corner radius (Aero DWM ON):** approximately **6–8 px** on all four corners (commonly cited **8** with composition on; **6** top-only when DWM off / Basic). — [SO themed corner radius](https://stackoverflow.com/questions/5385605/how-to-correctly-detect-the-corner-radius-for-themed-window)

There is **no public GetSystemMetrics for radius**; themes bake it into `aero.msstyles` / DWM atlas. For pixel-perfect Omarchy SSD, use **8 px** outer radius at 96 DPI unless atlas extraction says otherwise.

### 1.5 Shadow / glow

- Soft DWM drop shadow around restored windows; **stronger on active**, weaker on inactive — [SuperUser focus cues](https://superuser.com/questions/403642/distinction-between-active-inactive-windows-titlebars-with-windows-7-aero).
- Shadow is **not** a public px API. It is drawn by DWM tied to NC rendering (`DWMWA_NCRENDERING_POLICY`). Custom frames keep it by retaining `WS_THICKFRAME|WS_CAPTION` + composition — [SO NC paint / shadow](https://stackoverflow.com/questions/9775185/possible-to-use-wm-ncpaint-and-still-get-the-shadow-behind-a-window-on-aero).
- Practical recreation target (measured approximations used by themers; **not** an MSDN constant): soft blur ~**15–25 px** extent, offset slightly down/right, alpha falloff; inactive ~60–70% of active opacity. Prefer screenshot matching over inventing constants.

**Maximized:** no visible outer shadow (window flush / borders off-screen).

---

## 2. Caption buttons (min / max|restore / close)

### 2.1 Order and hit layout (LTR, SSD)

Right-aligned strip, **flush to each other** (Aero style — no Classic gaps):

1. **Minimize** (leftmost of the three)  
2. **Maximize** or **Restore** (middle)  
3. **Close** (rightmost, **wider**, **red** hover/press)

Order matches system menu semantics and `WM_SYSCOMMAND` handling — [MSDN WM_SYSCOMMAND](https://learn.microsoft.com/en-us/windows/win32/menurc/wm-syscommand).

### 2.2 Exact sizes (Win7 Aero visual, 96 DPI)

DWM draws **asymmetric** buttons. Reverse-engineered Win7 ratios (OpenGlass `CaptionMetricsTweaker`, default `CaptionButtons::Windows7`) relative to `cySize` (typically **21**):

| Button | Width ratio × cySize | Height ratio × cySize | **px @ cySize=21** |
|--------|----------------------|-----------------------|--------------------|
| Minimize | 1.3809524 | 0.95238096 | **29 × 20** |
| Maximize / Restore | 1.2857143 | 0.95238096 | **27 × 20** |
| Close | 2.3333333 | 0.95238096 | **49 × 20** |
| Lone Close (no min/max) | 2.3333333 | 0.95238096 | **49 × 20** |

Sources:

- [OpenGlass CaptionMetricsTweaker.cpp](https://github.com/ALTaleX531/OpenGlass/blob/2117abf4/OpenGlass/Architecture/MILComp/CaptionMetricsTweaker.cpp)
- Matching constants in DWMBlurGlass Win7 button path (`29` / `27` / `49`) — [CustomButton.cpp](https://github.com/Maplespe/DWMBlurGlass/blob/7262fcf7/DWMBlurGlassExt/Section/CustomButton.cpp), [Discussion #282](https://github.com/Maplespe/DWMBlurGlass/discussions/282)

**Do not** use equal `SM_CXSIZE` rectangles for Aero Ultimate look (that equal-box look is Aero Basic / Classic). — [SuperUser button styles](https://superuser.com/questions/272343/windows-7-minimize-maximize-close-button-styles)

### 2.3 Spacing from right edge

- Gap from **close button’s right edge** to **window’s right outer edge** ≈ **border width** for restored windows → **~8 px** (often equals `titlebtnOffsetX` / padded frame). — [DWMBlurGlass discussion](https://github.com/Maplespe/DWMBlurGlass/discussions/282)
- Buttons sit near the **top** of the caption (small top inset inside the 30 px chrome); when maximized they are **flush with the top** of the visible work area.

### 2.4 States, colors, glyphs, hit targets

| State | Min / Max / Restore | Close |
|-------|---------------------|-------|
| Normal (active) | Light glass button chrome; dark glyph | Same chrome; dark **×**; slight warm tint possible |
| Hover | Bright glow / highlight (bitmap atlas glow) | **Strong red** glow fill |
| Pressed | Darker inset / pressed atlas state | Darker red pressed |
| Disabled | Dimmed glyph + muted chrome | Dimmed |
| Inactive window | Buttons desaturated / translucent; less glow | Same |

- Glyphs are **theme-atlas bitmaps**, not Segoe MDL2. Stroke weight is thin/light for Aero.
- Glyph optical size roughly **~9–11 px** inside the 20 px button height (eyeball from atlas; not a public constant).
- **Hit targets** = full button rectangles (29/27/49 × 20), not just the glyph. Query with `WM_GETTITLEBARINFOEX` / `DWMWA_CAPTION_BUTTON_BOUNDS`.
- Hover “peek” of Snap layouts on the maximize button is a **Windows 10+** feature — **absent on Win7**. Win7 maximize is click-only maximize/restore.

Close special red is part of the DWM / `aero.msstyles` button atlas (hover/press). Recreate as saturated red hover (~`#C75050`–`#E81123` family) with soft glow; exact atlas pixels vary by theme pack — measure from real Win7 Ultimate Aero screenshots for pixel match.

API metrics still useful:

- `GetSystemMetrics(SM_CXSIZE)`, `SM_CYSIZE` — [MSDN GetSystemMetrics](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetrics)
- `NONCLIENTMETRICS.iCaptionWidth/Height` — [MSDN](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-nonclientmetricsw)

---

## 3. Title text

### 3.1 Font

| Property | Win7 Aero default |
|----------|-------------------|
| Family | **Segoe UI** |
| Size | **9 pt** (LOGFONT from caption font; ~12 px at 96 DPI) |
| Weight | **Normal** (400), not bold |
| Source | `SPI_GETNONCLIENTMETRICS` → `lfCaptionFont`; also `GetThemeSysFont(..., TMT_CAPTIONFONT)` |

Sources: [Quppa theme fonts](https://www.quppa.net/blog/2011/04/30/windows-theme-fonts/), [VFPX NONCLIENTMETRICS sample](https://github.com/VFPX/Win32API/blob/master/samples/sample_556.md) (“Vista: Segoe UI, 9, N”).

### 3.2 Color active / inactive

- Drawn with **`DrawThemeTextEx`** on glass with **`DTT_COMPOSITED | DTT_GLOWSIZE`**. MSDN sample uses **`iGlowSize = 15`**. — [Custom Window Frame Using DWM, Appendix B](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe)
- Text fill is near-**black** (`#000000` / very dark gray) with a **light glow** for contrast on glass.
- Inactive: same recipe with reduced glow / contrast (theme state), not a bright gray classic inactive caption.

### 3.3 Icon + title layout

| Element | Size / padding |
|---------|----------------|
| App icon | **16×16** (`SM_CXSMICON` / `SM_CYSMICON`) — [MSDN icons](https://learn.microsoft.com/en-us/windows/win32/menurc/about-icons) |
| Icon left inset | ~**8 px** from inner client-left / glass (MSDN paint sample uses `left += 8`) |
| Gap icon → title | ~**4–5 px** typical |
| Title left | After icon; if no icon, ~8 px from left |
| Title right clip | Before caption buttons (MSDN sample subtracts **~125 px** from right for button strip — order-of-magnitude for 29+27+49+margins) |
| Vertical | Vertically centered in caption band; sample uses `top += 8` |

### 3.4 Ellipsis

- Flags: **`DT_LEFT | DT_WORD_ELLIPSIS`** (MSDN Appendix B). Single-line caption; truncate with **…** when text would collide with buttons.

Double-click on **icon** = close (system menu default item / `SC_CLOSE` via `SC_DEFAULT` behavior historically). Single left-click icon or Alt+Space = system menu.

---

## 4. Resize grips

### 4.1 Hit-target widths

For Aero SSD, resize hit testing covers the **visual border** (and often slightly into the frame):

| Region | Hit code | Typical hit thickness (96 DPI) |
|--------|----------|--------------------------------|
| Left / Right edge | `HTLEFT` / `HTRIGHT` | **8 px** (full visual border) |
| Top edge (above caption drag) | `HTTOP` | Top **~few px** of the 30 px chrome (rest is `HTCAPTION`) |
| Bottom edge | `HTBOTTOM` | **8 px** |
| Corners | `HTTOPLEFT` … `HTBOTTOMRIGHT` | **8×8** (or border×border) corner squares |

MSDN custom-frame `HitTestNCA` treats the top strip specially: upper pixels → resize, below → caption drag — [Appendix C](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe).

`WM_NCHITTEST` return codes — [MSDN](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-nchittest).

**Maximized:** edge resize hits disabled (no sizing); borders off-screen.

### 4.2 Cursors

| Hit | Cursor |
|-----|--------|
| `HTLEFT` / `HTRIGHT` | `IDC_SIZEWE` |
| `HTTOP` / `HTBOTTOM` | `IDC_SIZENS` |
| `HTTOPLEFT` / `HTBOTTOMRIGHT` | `IDC_SIZENWSE` |
| `HTTOPRIGHT` / `HTBOTTOMLEFT` | `IDC_SIZENESW` |
| `HTCAPTION` | `IDC_ARROW` (drag move) |
| Caption buttons | `IDC_ARROW` |

There is **no separate bottom-right sizegrip control** on standard Aero top-level frames (unlike status-bar `SBS_SIZEGRIP` in some dialogs). Corners of the border are enough.

---

## 5. Interactions (cited)

### 5.1 Title bar / chrome basics

| Action | Behavior | Source |
|--------|----------|--------|
| Left-drag on caption (`HTCAPTION`) | Move window | DefWindowProc / DWM |
| Double-click caption | Maximize ↔ Restore | Petri Aero Snap guide (also notes double-click top) — [Petri](https://petri.com/new-aero-features-in-windows-7/) |
| Alt+F4 | Close active window | [MSDN keyboard shortcuts archive](https://web.archive.org/web/20120424082851/msdn.microsoft.com/en-us/library/bb545461.aspx) |
| Alt+Space | System (window) menu | Same MSDN table |
| Left-click caption icon | System menu | Win32 system menu behavior |
| Double-click caption icon | Close | System menu default = Close |

### 5.2 System menu — exact items and order

Standard overlapped window menu (GetSystemMenu):

1. **Restore** (`SC_RESTORE` `0xF120`) — enabled iff maximized or minimized  
2. **Move** (`SC_MOVE` `0xF010`) — disabled if maximized  
3. **Size** (`SC_SIZE` `0xF000`) — disabled if maximized / non-resizable  
4. **Minimize** (`SC_MINIMIZE` `0xF020`)  
5. **Maximize** (`SC_MAXIMIZE` `0xF030`) — disabled if already maximized  
6. *separator*  
7. **Close** (`SC_CLOSE` `0xF060`) — bold / default when restored  

Sources: [MSDN WM_SYSCOMMAND](https://learn.microsoft.com/en-us/windows/win32/menurc/wm-syscommand); reconstructed menu order in [Experts Exchange system menu sample](https://www.experts-exchange.com/questions/20369015/Retriving-the-System-Menu-from-a-window-handle.html).

Right-click **title bar** or **caption icon** → same menu. Keyboard: Alt+Space.

### 5.3 Caption button clicks

| Button | Left-click |
|--------|------------|
| Minimize | Minimize to taskbar |
| Maximize | Maximize |
| Restore | Restore previous bounds |
| Close | Close (`WM_SYSCOMMAND`/`SC_CLOSE` / `WM_CLOSE`) |

No Win7 hover flyout on Maximize. Hover only changes button chrome/glow.

### 5.4 Aero Snap / Shake / Home

| Input | Behavior | Source |
|-------|----------|--------|
| Drag to **left** screen edge | Snap to left **50%** of monitor work area | [Petri](https://petri.com/new-aero-features-in-windows-7/) |
| Drag to **right** edge | Snap right 50% | Petri |
| Drag to **top** edge | Maximize | Petri |
| Drag bottom edge stretch (optional gesture) | Vertical maximize (height fill, keep width) | Petri |
| **Win+Left** | Dock left half | [MSDN shortcuts](https://web.archive.org/web/20120424082851/msdn.microsoft.com/en-us/library/bb545461.aspx) |
| **Win+Right** | Dock right half | MSDN |
| **Win+Up** | Maximize | MSDN |
| **Win+Down** | Restore if maximized; else Minimize | MSDN (“Restore/minimize”) |
| Repeat Win+Left/Right | Cycle snap left ↔ right ↔ restore | [TheWindowsClub](https://www.thewindowsclub.com/aero-snap-feature-in-windows-7) |
| **Win+Shift+Up** | Vertical maximize (keep width) | MSDN |
| **Win+Shift+Down** | Undo vertical maximize | MSDN |
| **Win+Home** | Minimize all **except** active; toggle restore | MSDN / Petri (keyboard twin of Shake) |
| **Aero Shake** | Shake caption → minimize others; shake again restore | Petri (Home Premium+) |
| **Win+Shift+Left/Right** | Move window to adjacent monitor | MSDN |

**Not Win7:** Snap Assist thumbnail picker, Snap Layouts flyout, quarter-corner snap (those are Win10/11).

---

## 6. CSD vs SSD

| Mode | Who draws chrome | Win7 examples |
|------|------------------|---------------|
| **SSD** (Server-Side Decoration) | DWM / uxtheme standard NC frame | Notepad, Explorer, most Win32 apps |
| **CSD** (Client-Side Decorations) | App draws caption / extends glass | Office 2007+ (Office button in frame), IE7+ nav in frame, later Chrome |

Microsoft’s supported CSD path: `DwmExtendFrameIntoClientArea` + `WM_NCCALCSIZE` + `DwmDefWindowProc` for button hit-testing — [Custom Window Frame Using DWM](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe). Office keeps **system** min/max/close while customizing the left caption.

Chromium historically used custom NC calc + glass margins for tabs-in-titlebar — [browser_frame.cc (historical)](https://chromium.googlesource.com/chromium/src/+/df9fd0d0bfef305243b90b193a6211ae64193fd5/chrome/browser/views/frame/browser_frame.cc).

### Omarchy product rule

- Product uses **SSD via hyprbars** for normal windows → implement **this document’s** sizes/behaviors.
- **CSD exclusion applies when:**
  - App sets client-side decorations / draws its own title bar (e.g. some Electron/Chrome, games, fullscreen toolkits).
  - Window is borderless / `fullscreen` / special workspace.
  - Explicit app exception list (if product maintains one).
- Do **not** double-draw hyprbars on true CSD clients; do **not** expect Office-style partial CSD unless a specific client implements it.

---

## 7. Maximized vs restored geometry

| Property | Restored | Maximized |
|----------|----------|-----------|
| Outer shadow | Yes (active stronger) | None visible |
| L/R/B border visible | 8 px glass | Hidden off-screen (still in WINDOWPLACEMENT math) |
| Caption visual height | 30 px | Shorter on-screen (~caption only); buttons flush top |
| Caption buttons | Inset ~8 px from right | Flush to top-right of work area |
| Corner radius | ~8 px visible | Effectively square flush to monitor |
| Resize | Enabled | Disabled |
| Drag move | Yes | Drag down unsnaps / restores then moves (Aero) |
| Double-click caption | Maximize | Restore |

Raymond Chen: maximized window rectangle is **larger than the screen** so borders hang off — [Old New Thing](https://devblogs.microsoft.com/oldnewthing/20120326-00/?p=8003). Multi-monitor: that “sliver” of border can appear on the adjacent monitor unless mitigated.

---

## 8. Multi-monitor edge cases

| Case | Win7 behavior |
|------|---------------|
| Snap left/right | Uses **that monitor’s** work area (50% of current monitor) |
| Maximize | Fills **current** monitor work area (taskbar excluded) |
| Win+Shift+Left/Right | Move window to next/prev monitor (preserve relative state where possible) | [MSDN](https://web.archive.org/web/20120424082851/msdn.microsoft.com/en-us/library/bb545461.aspx) |
| Drag maximize across monitors | Top-edge maximize applies to the monitor under the cursor |
| Taskbar on secondary | Work area per monitor differs; snap/maximize must respect per-monitor work rect |
| Maximized border sliver | May show ~8 px on adjacent monitor (historical); DWM/Win7 still exhibits this class of issue — Chen |
| Different DPI per monitor | **Win7 has no per-monitor DPI**; entire session shares one DPI. (Omarchy may need modern DPI policy — that is **product**, not Win7 truth.) |

---

## 9. Win7 ground truth vs current Omarchy tokens

### 9.1 Win7 Ultimate ground truth (this file)

- Glass colorization is **user-chosen**; factory sample `#74B8FC` @ alpha `0x6B`.
- Caption text is **dark on light glass glow**, Segoe UI 9.
- Close hover is **red atlas glow**; min/max are **neutral glass**.
- Borders **8 px**; caption **30 px** restored; buttons **29 / 27 / 49 × 20**.

### 9.2 Current Omarchy tokens (NOT Win7 truth)

From `/workspace/w7-specs/docs/chrome-tokens.json` (dark adapter — illustrative only):

| Token | Example value | Note |
|-------|---------------|------|
| `glassRed/Green/Blue` | 28/28/30 | Dark glass — **not** Aero sky blue |
| `hyprbarsTextHex` | `#eeeeee` | Light text — **opposite** of Win7 dark caption text |
| `captionCloseBgHex` | `#c42b1c` | Product close chrome |
| `chromeGlowHex` | `#e8943a` | Omarchy accent — **not** DWM colorization |

**Parity work** must map hyprbars SSD layout/metrics to §1–§5 first; token colors are a separate Personalize/theme layer and must not redefine Win7 geometry.

---

## 10. Implementation checklist (no guessing)

1. Restored frame: top **30**, L/R/B **8**, radius **8**.  
2. Buttons: **min 29 × 20**, **max/restore 27 × 20**, **close 49 × 20**, gap to right **8**, order min→max→close.  
3. Title: Segoe UI 9 regular, dark + glow 15, ellipsis, 16×16 icon + paddings.  
4. Resize: 8 px edges/corners; top strip split resize vs drag.  
5. Menus/shortcuts: §5 exactly.  
6. Snap/Shake/Home: §5.4; no Win10 layouts.  
7. Maximized: flush buttons, hide borders/shadow, hang borders off-screen in layout math if matching Win32.  
8. SSD hyprbars for normal apps; skip CSD clients.  
9. Colors from DWM colorization model or measured screenshots — **never** from inventing Omarchy tokens as Aero.

---

## Sources (primary + measured)

1. https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-nonclientmetricsw  
2. https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetrics  
3. https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmgetcolorizationcolor  
4. https://learn.microsoft.com/en-us/windows/win32/dwm/customframe  
5. https://learn.microsoft.com/en-us/windows/win32/menurc/wm-syscommand  
6. https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-nchittest  
7. https://learn.microsoft.com/en-us/windows/win32/menurc/about-icons  
8. https://web.archive.org/web/20120424082851/msdn.microsoft.com/en-us/library/bb545461.aspx  
9. https://devblogs.microsoft.com/oldnewthing/20120326-00/?p=8003  
10. https://stackoverflow.com/questions/6032032/how-do-i-compute-the-non-client-window-size-in-wpf  
11. https://groups.google.com/g/comp.lang.clipper.visual-objects/c/IakwBqOvJr4  
12. https://petri.com/new-aero-features-in-windows-7/  
13. https://github.com/ALTaleX531/OpenGlass/blob/2117abf4/OpenGlass/Architecture/MILComp/CaptionMetricsTweaker.cpp  
14. https://github.com/Maplespe/DWMBlurGlass/blob/7262fcf7/DWMBlurGlassExt/Section/CustomButton.cpp  
15. https://www.quppa.net/blog/2011/04/30/windows-theme-fonts/  
16. https://serverfault.com/questions/612485/set-default-wallpaper-for-all-users-in-win7  
17. https://stackoverflow.com/questions/5385605/how-to-correctly-detect-the-corner-radius-for-themed-window  
18. https://superuser.com/questions/403642/distinction-between-active-inactive-windows-titlebars-with-windows-7-aero  

---

*Document version: 2026-09-02 — research for Omarchy Project Ultimate SSD hyprbars parity.*
