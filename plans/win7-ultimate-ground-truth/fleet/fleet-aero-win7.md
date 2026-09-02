---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# Fleet pack: Windows 7 Ultimate — Aero / CSD / window chrome ground truth

**Owner:** Review Aero (fleet)  
**Scope:** Caption geometry, glass, caption buttons, Snap / Shake / Peek, system menu  
**SKU:** Windows 7 **Ultimate** (full Aero Glass + Peek + Shake; Home Basic lacks glass; Starter is not the Ultimate bar)  
**Baseline:** 96 DPI, default Aero theme, DWM composition on, English LTR, top-level overlapped window with `WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_THICKFRAME`  
**Authority note (Omarchy):** Document Win7 Ultimate ground truth. Omarchy may approximate glass rendering, but **sizes, hit targets, menus, and Snap/Shake/Peek grammar must match**.

---

## 1. Edition / composition prerequisites

| Fact | Value | Citation |
|------|-------|----------|
| Aero Glass hardware floor | DirectX 9 class GPU, WDDM 1.0+, Pixel Shader 2.0, 32 bpp | Microsoft Answers / Aero technical requirements summary |
| Ultimate includes | Aero Glass, Aero Peek, Aero Shake, Aero Snap, Flip 3D | Product edition matrix; Petri “Using Aero Peek, Aero Shake & Aero Snap in Windows 7” |
| Snap availability | All Win7 SKUs (including Starter) | Petri (2009) |
| Peek / Shake availability | Home Premium, Professional, Ultimate (not Starter / Home Basic glass path) | Petri (2009) |
| Composition APIs | `dwmapi.dll` (`DwmExtendFrameIntoClientArea`, `DwmGetWindowAttribute`, …) | Microsoft Learn: DWM API |

---

## 2. Caption / non-client height (exact formulas)

### 2.1 System metrics (indices)

From Microsoft Learn — `GetSystemMetrics` ([learn.microsoft.com …/nf-winuser-getsystemmetrics](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetrics)):

| Metric | Index | Meaning |
|--------|------:|---------|
| `SM_CYCAPTION` | 4 | Height of a caption area, in pixels |
| `SM_CXSIZE` / `SM_CYSIZE` | 30 / 31 | Width / height of a button in a window caption |
| `SM_CXSIZEFRAME` / `SM_CYSIZEFRAME` (`SM_CXFRAME` / `SM_CYFRAME`) | 32 / 33 | Sizing border thickness |
| `SM_CXPADDEDBORDER` | 92 | Border padding for captioned windows (Vista+) |
| `SM_CXSMICON` / `SM_CYSMICON` | 49 / 50 | System small icon (caption / menus) |
| `SM_CXBORDER` / `SM_CYBORDER` | 5 / 6 | Window border |
| `SM_CXEDGE` / `SM_CYEDGE` | 45 / 46 | 3-D edge |

**All values are pixels and DPI-dependent.** Prefer runtime `GetSystemMetrics` / `GetSystemMetricsForDpi` over hard-coding when implementing on Windows; for Omarchy parity targets use the **96 DPI Aero defaults below**.

### 2.2 Vista/7 appcompat split (critical)

Microsoft window-manager behavior at **96 DPI** (subsystem version; documented by Win32 engineers on public lists):

| App mark | `iBorderWidth` | `SM_CXPADDEDBORDER` | `SM_CXFRAME` |
|----------|---------------:|--------------------:|-------------:|
| Subsystem **&lt; 6.0** (XP-era lie) | 5 | **0** | **8** |
| Subsystem **≥ 6.0** (Vista/7 truthful) | 1 | **4** | **4** |

Source: `GetSystemMetrics and SM_CXPADDEDBORDER` discussion summarizing Microsoft behavior ([groups.google.com/g/comp.lang.clipper.visual-objects](https://groups.google.com/g/comp.lang.clipper.visual-objects/c/IakwBqOvJr4)).

**Win7 Ultimate Aero ground truth for modern (6.0+) apps at 96 DPI:**

- `SM_CXPADDEDBORDER` = **4**
- `SM_CXFRAME` / `SM_CYFRAME` = **4**
- `SM_CYCAPTION` commonly reports **22** (widely measured on Aero; some tables list **23** — always verify on metal)

### 2.3 Restored caption strip height (binding formula)

Themed / Aero top non-client height used by shell and custom chrome:

```
captionTopNcPx =
  GetSystemMetrics(SM_CYFRAME)
+ GetSystemMetrics(SM_CYCAPTION)
+ GetSystemMetrics(SM_CXPADDEDBORDER)
```

At default 96 DPI Aero (6.0+ app):

| Component | px |
|-----------|---:|
| `SM_CYFRAME` | 4 |
| `SM_CYCAPTION` | 22 |
| `SM_CXPADDEDBORDER` | 4 |
| **Total top NC** | **30** |

If `SM_CYCAPTION` reads 23 on a given image: total = **31**.  
Citations: Delphi-PRAXiS / Stack Overflow consensus on `SM_CYFRAME + SM_CYCAPTION + SM_CXPADDEDBORDER` ([en.delphipraxis.net topic 11968](https://en.delphipraxis.net/topic/11968-looking-for-some-guidance-on-wm_nccalcsize/); [stackoverflow.com/q/28524463](https://stackoverflow.com/questions/28524463/how-to-get-the-default-caption-bar-height-of-a-window-in-windows)).

**Do not** treat `SM_CYCAPTION` alone as the visible title-bar height — it understates Aero chrome.

### 2.4 Unthemed fallback (for comparison only)

Classic (unthemed) caption ≈ `SM_CYCAPTION + SM_CYSIZEFRAME + SM_CYEDGE*2` (Eric Brown / SO). Not the Ultimate Aero bar.

---

## 3. Glass (Aero Glass)

| Fact | Spec | Citation |
|------|------|----------|
| Extend glass into client | `DwmExtendFrameIntoClientArea(hwnd, &MARGINS)` | [Microsoft Learn — DwmExtendFrameIntoClientArea](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmextendframeintoclientarea) |
| Sheet-of-glass | `MARGINS = { -1, -1, -1, -1 }` (negative margins) | Same Learn doc |
| Margin units | **Physical pixels**; scale from 96 DPI baseline (`DesktopDpi/96`) | [WPF extend glass frame](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/graphics-multimedia/extend-glass-frame-into-a-wpf-application) |
| Composition toggle | Handle `WM_DWMCOMPOSITIONCHANGED`; re-call extend | Learn remarks |
| Visible vs shadow bounds | `GetWindowRect` includes DWM drop shadow; use `DwmGetWindowAttribute(..., DWMWA_EXTENDED_FRAME_BOUNDS, ...)` for frame without shadow | Learn `DWMWA_EXTENDED_FRAME_BOUNDS`; Cyotek / SO |
| Blur radius | **Not** a public fixed “Aero blur = N px” metric apps can query; blur is DWM-owned | No documented constant in DWM public API |
| Home Basic | Opaque substitute where Glass would be | Vista/7 edition docs |

**Omarchy binding:** Match glass **coverage regions** (caption + optional extended margins) and **opacity language** via tokens; do not invent a fake public blur-radius constant.

---

## 4. Caption buttons (min / max / close) — pixels

### 4.1 Metrics vs painted theme parts

| Source | What it returns | Notes |
|--------|-----------------|-------|
| `SM_CXSIZE` / `SM_CYSIZE` | Caption **button metric** | Index 30/31; theme may paint smaller than metric |
| `GetThemePartSize(WINDOW, WP_CLOSEBUTTON, CBS_NORMAL, TS_TRUE)` | Theme true size | Measured on Win7 default theme: **cx = 28, cy = 17** ([stackoverflow.com/q/14111926](https://stackoverflow.com/questions/14111926/how-to-retrieve-the-size-of-the-minimize-maximize-and-close-button-of-a-window)) |
| `DwmGetWindowAttribute(..., DWMWA_CAPTION_BUTTON_BOUNDS)` | Bounding `RECT` of **entire** caption-button cluster | Learn enum `DWMWA_CAPTION_BUTTON_BOUNDS` |
| Measured 3-button cluster width | **right − left = 105** px | Same SO thread (Win7 Aero) |
| Measured cluster height from DWM | often **29** px | Includes ~**8** px padding above visible glyphs (SO) |
| Visible button glyph height | ≈ clusterHeight − 8 ≈ **21** px | Derived from above measurement |

### 4.2 Win7 theme ratio model (OpenGlass reverse-engineering of MIL caption)

OpenGlass `CaptionMetricsTweaker.cpp` encodes **Windows 7** caption button ratios against `SM_CYSIZE` (`cySize`):

| Ratio | Win7 value |
|-------|------------|
| heightRatio | 0.95238096 |
| loneWidthRatio | 2.3333333 |
| closeWidthRatio | 2.3333333 |
| maxWidthRatio | 1.2857143 |
| minWidthRatio | 1.3809524 |

Source: [github.com/ALTaleX531/OpenGlass … CaptionMetricsTweaker.cpp](https://github.com/ALTaleX531/OpenGlass/blob/2117abf4/OpenGlass/Architecture/MILComp/CaptionMetricsTweaker.cpp).

**Parity target for Omarchy three-button SSD:** match Win7 **visual** close/min/max proportions and the **105 px** three-button cluster width at 96 DPI when all three buttons are present — not XP-era equal squares.

### 4.3 Hit-testing order (LTR)

Left → right on caption trailing edge: **Minimize | Maximize/Restore | Close**.  
Help (`WS_EX_CONTEXTHELP`) replaces min/max pair when present (classic rule).  
Close has larger painted width than min/max under Aero (see ratios / theme part sizes).

### 4.4 Maximize hover / snap affordance

Win7 maximize button + Aero Snap preview are part of the same window-management story (E7 blog). Omarchy’s maximize-hover snap must preserve **release-to-commit** grammar (below), not XP instant maximize.

---

## 5. Aero Snap (exact interaction grammar)

Primary citation: Stephan Hoefnagels / Steven Sinofsky — **“Designing Aero Snap”**, Engineering Windows 7, 16 Mar 2009  
([learn.microsoft.com/en-us/archive/blogs/e7/designing-aero-snap](https://learn.microsoft.com/en-us/archive/blogs/e7/designing-aero-snap)).

### 5.1 Trigger geometry

| Rule | Spec |
|------|------|
| What must hit the screen edge | The **mouse pointer**, not the window edge |
| Effective “snap distance” metric | **0** (window may still be inset; pointer at edge commits the *arm*) |
| Commit model | **Release** mouse to commit (not instant-commit while dragging) |
| While dragging | Show **glass-sheet preview** + light/cursor cue; moving away cancels before release |
| Accidental-trigger history | Early builds used instant commit; telemetry showed cancel ≈ 2× commit → switched to release-commit |

### 5.2 Zones / results

| Pointer zone | Result |
|--------------|--------|
| Left screen edge | Snap to **left half** of work area |
| Right screen edge | Snap to **right half** of work area |
| Top screen edge | **Maximize** |
| Resize top edge to top | **Vertical maximize** (full height, keep width) |
| Drag maximized title down then to top | Restore → move → re-maximize in one gesture |

### 5.3 Restored-state memory

Guiding statements from the E7 design post (must preserve):

1. Opposite mouse motion undoes a motion-triggered effect.  
2. Always effortless return to previous **restored** size.  
3. User-specified width preserved across state changes when it makes sense.

**Title bar off-screen (Win7 change):** if dragged partly off-screen, snap back so the **entire title bar** stays visible (Vista/XP often left only half). Same for vertically maximized states.

### 5.4 Keyboard (Win7)

| Chord | Action |
|-------|--------|
| `Win+Left` / `Win+Right` | Side snap |
| `Win+Up` | Maximize |
| `Win+Down` | Restore / minimize cascade |
| `Win+Shift+Left/Right` | Move to adjacent monitor (multi-mon) |

### 5.5 What Win7 Snap is **not**

- No corner quarter-snap (that is later Windows).  
- No sticky window-to-window magnetic threshold API (`GetSystemMetrics` has none).  
- Not “10–50 px proximity” docking (third-party invents that).

---

## 6. Aero Shake

### 6.1 User-visible grammar

| Action | Result |
|--------|--------|
| Grab **title bar**, shake window | Minimize all **other** minimizable windows |
| Shake again | Restore those windows |
| Keyboard alternate | `Win+Home` (Petri) |

Edition: Home Premium / Professional / Ultimate (Petri).

### 6.2 Patent-documented example thresholds (not a published SPI)

Microsoft patents on “Window minimization trigger” (e.g. US 8,214,760 / 8,954,881) give **example** detector parameters:

| Parameter | Example value |
|-----------|---------------|
| Single shakes required | **> 3** |
| Velocity threshold | **600 px/s** |
| Distance per leg | **1 … 2000** px |
| Time window | **250 ms** |

Patents explicitly call these “merely examples.” **Do not treat as SPI constants.** For Omarchy: implement recognizable title-bar shake → isolate window; tune to feel intentional, document chosen thresholds in product tests.

Registry kill-switch (later Windows still relevant):  
`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\DisallowShaking` = 1.

---

## 7. Aero Peek

| Mode | Behavior |
|------|----------|
| Taskbar thumbnail hover | Live (or iconic) preview; hover thumbnail → full-size peek |
| Show Desktop strip | Far **right** of taskbar; hover → all windows glass/transparent to desktop |
| Click Show Desktop | Show desktop (Win+D semantics) |
| Strip width (desktop, no tablet components) | Commonly cited **~8 px** hard-coded hit strip (community measurements; not a `GetSystemMetrics` value). Tablet/pen stacks often **~16 px** |
| App opt-out | `DWMWA_DISALLOW_PEEK`, `DWMWA_EXCLUDED_FROM_PEEK` | Learn `DWMWINDOWATTRIBUTE` |

Citations: Petri Aero Peek article; SuperUser / SevenForums on Show Desktop strip width; DWM attribute docs.

---

## 8. System menu (Control menu)

| Fact | Spec | Citation |
|------|------|----------|
| Open | Caption **icon** click; **right-click** title bar; **Alt+Space** | [About Menus](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/menurc/about-menus.md) |
| API | `GetSystemMenu` / `TrackPopupMenuEx`; commands via `WM_SYSCOMMAND` | [GetSystemMenu](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmenu) |
| Stock IDs | `SC_RESTORE`, `SC_MOVE`, `SC_SIZE`, `SC_MINIMIZE`, `SC_MAXIMIZE`, `SC_CLOSE` (all **> 0xF000**) | Same |
| Caption icon size | **16×16** at 96 DPI (`SM_CXSMICON` × `SM_CYSMICON`) | [About Icons](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/menurc/about-icons.md) |
| Double-click caption icon | **Close** | Classic Win32 grammar |
| Double-click caption | Maximize / Restore toggle | Classic Win32 grammar |
| Grayed items | System grays by state; apps may handle `WM_INITMENU` | Learn |

Default order (LTR overlapped window): Restore, Move, Size, Minimize, Maximize, separator, Close.

---

## 9. SSD vs CSD (Win7 Ultimate reality)

| Mode | Who draws caption | Typical apps |
|------|-------------------|--------------|
| **SSD** (system) | DWM + uxtheme WINDOW parts | Explorer, Notepad, most Win32 |
| **CSD** (client) | App paints into extended glass / custom NC | Office 2007/2010, some WPF custom chrome |

Ultimate users still expect **three caption buttons**, system menu, Snap/Shake on the title bar even for CSD apps that opt into DWM. Omarchy “one-row CSD” / hyprbars SSD must preserve that **grammar**, not XP Luna metrics.

---

## 10. Binding numbers cheat-sheet (96 DPI, Aero, 6.0+ app)

| Item | Exact / binding value |
|------|------------------------|
| `SM_CXPADDEDBORDER` | **4** |
| `SM_CXFRAME` / `SM_CYFRAME` | **4** |
| `SM_CYCAPTION` (typical) | **22** (verify; sometimes 23) |
| Top NC caption strip | **30** (= 4+22+4) or **31** if caption=23 |
| Theme close button true size | **28 × 17** |
| Three-button DWM cluster width | **105** |
| DWM cluster height (incl. pad) | **~29** |
| Visible button body height | **~21** |
| Caption / menu small icon | **16 × 16** |
| Snap trigger | Pointer at **screen edge**; commit on **release** |
| Snap halves | **50%** work area L/R |
| Shake | Title-bar shake → minimize others; `Win+Home` |
| Show Desktop peek strip | **~8** px (desktop); **~16** px (tablet components) |
| System menu | Alt+Space; SC_* > 0xF000 |

---

## 11. Open questions / metal verification still required

1. Confirm `SM_CYCAPTION` **22 vs 23** on a clean Win7 Ultimate EN-US Aero VM at 96 DPI (subsystem 6.0 test harness).  
2. Capture `DWMWA_CAPTION_BUTTON_BOUNDS` and per-button `WM_GETTITLEBARINFOEX` rects on the same VM (min/max/close individually).  
3. Measure Show Desktop strip width on Ultimate desktop **without** Tablet PC components.  
4. Decide Omarchy shake detector constants and lock them in acceptance tests (patent examples are not SPI).  
5. Glass blur: pick visual token matches; do not claim a Microsoft-published blur radius.

---

## 12. Citations (primary)

1. Microsoft Learn — `GetSystemMetrics`  
2. Microsoft Learn — `DwmExtendFrameIntoClientArea`, `DWMWINDOWATTRIBUTE`  
3. Engineering Windows 7 — *Designing Aero Snap* (Hoefnagels / Sinofsky, 2009-03-16)  
4. Microsoft Win32 — About Menus / About Icons / `GetSystemMenu`  
5. Petri — Aero Peek / Shake / Snap SKU notes (2009)  
6. Stack Overflow — caption button bounds / theme part sizes (Win7 Aero measurements)  
7. Google Groups — SM_CXPADDEDBORDER = 4 for 6.0+ apps @ 96 DPI  
8. OpenGlass — Win7 caption button ratio table  
9. Microsoft patents US8214760 / US8954881 — shake detector *examples*  
10. SuperUser / SevenForums — Show Desktop strip ~8 / ~16 px community measurements  

---

*Pack complete for Lead synthesis into `plans/win7-ultimate-ground-truth/` window-chrome surface.*
