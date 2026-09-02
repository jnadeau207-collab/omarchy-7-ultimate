---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# 02 — Windows 7 Ultimate Start Menu + Superbar (Taskbar)

**SKU target:** Windows 7 Ultimate (x86/x64), Aero Glass enabled, 96 DPI (100%), SP1 behavior unless noted.  
**Not:** Windows 10/11 Start, Classic Shell approximations, or third-party multi-monitor taskbars.  
**Goal:** Implementers never guess Start or taskbar behavior.

---

## Sources (cite by id)

| Id | Source |
|----|--------|
| MS-TB | [Taskbar Extensions (Win32)](https://learn.microsoft.com/en-us/windows/win32/shell/taskbar-extensions) — Jump Lists, Show Desktop, peeks, notification area policy |
| MS-API | [Windows 7 Taskbar APIs — MSDN Magazine, July 2009](https://learn.microsoft.com/en-us/archive/msdn-magazine/2009/july/windows-7-taskbar-apis) |
| MS-SRCH | [Windows Search Features (Win7 IT Pro)](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-7/dd744686(v=ws.10)) — Start search categories/scopes |
| MS-NA | [Customize the notification area in Windows 7](https://support.microsoft.com/en-us/topic/guided-help-customize-the-notification-area-in-windows-7-508f3b7d-435d-2aea-d189-0d4b2d6eca13) |
| MS-MM | [Extending Win7 taskbar across multiple displays](https://learn.microsoft.com/en-us/answers/questions/2409590/extending-windows-7-task-bar-across-multiple-displ) — **no native multi-monitor taskbar** |
| SF-CUST | [Start Menu – Customize (Seven Forums / Brink)](https://www.sevenforums.com/threads/start-menu-customize.265/) — right-pane items + registry DWORDs |
| SF-ORB | [Start Menu Button – Change (Seven Forums)](https://www.sevenforums.com/threads/start-menu-button-change.23024/) — orb bitmap 54×162 / 54×54 states |
| SF-PEEK | [Aero Peek – Change Delay (Seven Forums)](https://www.sevenforums.com/threads/aero-peek-change-delay-time-to-preview-desktop.20337/) — default 1000 ms |
| MSFN-H | [Taskbar Height – Windows 7 (MSFN)](https://msfn.org/board/topic/138900-taskbar-height/) — 40 px large / 30 px small @ 96 DPI |
| WDN | [Decrease size of icons in Windows 7 taskbar](https://www.webdevelopersnotes.com/decrease-size-of-icons-in-windows-7-taskbar) — default height 40 px |
| DUMMIES | [Getting to Know the Windows 7 Start Menu (Rathbone)](https://www.dummies.com/article/getting-to-know-the-windows-7-start-menu-195481) — right-pane order + power flyout |
| GAV | [Parts of the Windows 7 Start Menu (Gavilan CSIS)](https://hhh.gavilan.edu/jmaringer/PDFFiles/Win7_StartMenu.pdf) |
| PETRI | [The New Windows 7 Start Menu](https://petri.com/windows-7-start-menu/) — MFU count default 10, max ~30 |
| ITW | [What happens when you click a Windows 7 taskbar icon](https://www.itwriting.com/blog/1157-what-happens-when-you-click-a-windows-7-taskbar-icon.html) |
| HOTKEYS | Common Win7 taskbar hotkey matrices (aggregated community + Microsoft keyboard shortcuts docs) |
| MDL | [Win7 taskbar button MinWidth](https://www.mydigitallife.net/how-to-change-the-windows-7-taskbar-button-length-or-width-size/) — ~56 large / ~40 small when labels shown |
| TWC | [W7 Taskbar Tweaker](https://www.thewindowsclub.com/tweak-taskbar-button-thumbnail-sizes-with-w7-taskbar-tweaker) — default thumbnail ~96 px |
| ASKVG-AP | [Cascading All Programs is *not* native Win7](https://www.askvg.com/enable-windows-xp-style-cascading-all-programs-list-in-windows-vista-and-7-start-menu/) |
| SU-MM | [Win7 taskbar per-monitor — not native](https://superuser.com/questions/48617/can-windows-7-place-a-task-bar-on-each-monitor-which-only-shows-applications-ru) |
| SU-SD | [Show Desktop button width](https://superuser.com/questions/638754/how-can-i-increase-the-width-of-the-show-desktop-button-in-windows-7-8-8-1-10) — ~8–15 px strip |
| VSB | [VistaStyleBuilder / door2windows orb sizing](https://www.door2windows.com/how-to-create-a-windows-7-start-orb/) — 54×162 strip |

All pixel figures below are **@ 96 DPI (100%)** unless noted. Scale linearly with DPI (125% → ×1.25, etc.).

---

## 1. Start Menu — geometry

### 1.1 Overall

| Property | Win7 Ultimate behavior | Citation |
|----------|------------------------|----------|
| Layout | Fixed **two-pane** menu; left = programs; right = places + power | DUMMIES, GAV |
| Edge resize | **Not user-resizable by drag.** Unlike Win10 Start. Height grows/shrinks only by changing “Number of recent programs to display” (and to a lesser extent Jump List item count / large vs small MFU icons). | PETRI, SF-CUST |
| Width | **Fixed by shell metrics** (not exposed as a user setting). Microsoft does not publish an official pixel width. Skinning / measured community values cluster around **~380–406 px total** with left pane wider than right (~230 / ~150 as a Vista-era skinning rule of thumb that remains visually accurate for Win7). Do **not** invent registry DWORDs for native width. | Skinning community; MS Q&A notes native keys do not exist |
| Height | Determined by MFU slot count + pinned count + chrome (search row + All Programs row). Default MFU = **10** (`Start_MinMFU` = 0xA). Practical UI max reported **~30**. | PETRI, SF-CUST (`Start_MinMFU`) |
| Glass | Aero Glass (DWM) frosted glass on both panes when Aero is on; solid fallback when Aero off / Basic theme | MS-TB (Aero required for peeks; glass is DWM) |
| Anchor | Opens above Start orb (bottom taskbar) or adjacent to orb for left/right/top taskbar | Visual behavior |

### 1.2 Two-pane measurements (implementer targets @ 96 DPI)

Use these as **parity targets** (measured/community consensus; label as such in code comments):

| Region | Target (px) | Notes |
|--------|-------------|-------|
| Total width | **400** (±10) | Inclusive of glass border |
| Left pane width | **244** (±8) | Pinned + MFU + All Programs + search |
| Right pane width | **156** (±8) | User tile + places + Shut down |
| Row height (large MFU icons) | **36–40** | Icon 32×32 + padding |
| Row height (small MFU icons) | **22–24** | Icon 16×16 + padding |
| Search box height | **28–32** | Bottom of left pane |
| User tile height | **48–56** | Picture (~32–48) + label |
| Shut down button height | **24–28** | Bottom of right pane |

> Implementers: prefer matching **proportions and layout**, then fine-tune against a Win7 Ultimate screenshot at 1920×1080 / 96 DPI.

---

## 2. Start Menu — left pane

### 2.1 Structure (top → bottom)

1. **Pinned programs** (user-controlled; above horizontal separator)  
2. **Separator**  
3. **Recent / MFU programs** (Most Frequently Used; below separator; default 10 slots)  
4. **All Programs** link (with ▸ / folder glyph)  
5. **Search box** — placeholder text: **“Search programs and files”**

Pinned items stay until unpinned. MFU list is recomputed by shell usage ranking; newly installed programs may be highlighted (yellow) when `Start_NotifyNewApps` = 1 (default on).

### 2.2 All Programs hierarchy & animation

| Fact | Exact Win7 behavior |
|------|---------------------|
| Presentation | **In-place replacement** of the left pane (pinned+MFU hidden). **Not** an XP-style cascading flyout. Cascading requires third-party (Classic Shell). | ASKVG-AP |
| Back | Top of list becomes **Back** (with ◂) to restore pinned+MFU view |
| Folders | Click to expand **in the same scrollable list** (tree-style). Hover alone does **not** auto-expand All Programs folders (unlike right-pane “Display as a menu”). | SF-CUST thread clarification |
| Sort | Default: **Sort All Programs menu by name** (`Start_SortByName` = 1) |
| Animation | Short **slide / fade** of left-pane content when entering/leaving All Programs (DWM). Keep under ~200–250 ms for parity feel. |
| Sources | Merged from `%AppData%\Microsoft\Windows\Start Menu` and `%ProgramData%\Microsoft\Windows\Start Menu` |

### 2.3 Search box — placement, size, behavior

| Property | Behavior | Citation |
|----------|----------|----------|
| Placement | Bottom of **left** pane, full left-pane width | GAV, MS-SRCH |
| Focus | Opening Start (Win / orb click) puts caret in search box | MS-SRCH (type-to-search) |
| Filter | **Instant** (word-wheel) as user types; no Enter required to filter | MS-SRCH |
| Enter | Activates **topmost** result (mouse focus on top hit) | MS-SRCH |
| Result layout | Results **replace** left-pane program list; fill entire horizontal Start width for reading | MS-SRCH |
| Categories (groups) | **Programs**, **Control Panel**, **libraries** (Documents / others), **Files** (indexed), **e-mail** when applicable; also command-line / Run semantics | MS-SRCH |
| Per-category count | Initially top **3** matches per category; total shown in parentheses; more as query refined | MS-SRCH |
| Group header click | Opens Explorer with full result set for that group | MS-SRCH |
| “See more results” | Re-runs query in Explorer over all indexed content (default pinned link) | MS-SRCH |
| Grep scopes (phase 1) | Start Menu shortcuts, user-pinned taskbar, library names, known folders, PATH/command templates | MS-SRCH |
| Index phase (phase 2) | Full indexer after grep; MFU bias + relevance sort | MS-SRCH |
| http: | Query beginning with `http:` offered as Internet result; Enter opens default browser | MS-SRCH |

### 2.4 Left-pane Jump Lists

Pinned and MFU entries that support destinations show a **▸ jump-list chevron** on the right of the row. Hover or click chevron (or right-click the item) opens the app’s Jump List (same destinations/tasks model as taskbar). | MS-TB |

---

## 3. Start Menu — right pane

### 3.1 Default order (Ultimate, stock Customize settings)

Exact labels and top→bottom order (DUMMIES / GAV / SF-CUST defaults):

| # | Label | Opens | Kind |
|---|-------|-------|------|
| 1 | **\<User display name\>** (user tile + picture) | User profile folder (`%UserProfile%`) | Folder / Explorer |
| 2 | **Documents** | Documents **library** | Library |
| 3 | **Pictures** | Pictures **library** | Library |
| 4 | **Music** | Music **library** | Library |
| 5 | **Games** | Games Explorer | Special folder |
| 6 | **Computer** | Computer (This PC drives view) | Folder / Explorer |
| 7 | **Control Panel** | Control Panel (Category view default) | Control Panel |
| 8 | **Devices and Printers** | Devices and Printers | Control Panel shell folder |
| 9 | **Default Programs** | Default Programs | Control Panel |
| 10 | **Help and Support** | Windows Help and Support | Help app |
| — | **Shut down** button | Performs configured power action (default: Shut down) | Power |
| — | **▸** (split button) | Power options flyout | Power |

Visual separators typically group: personal folders (user→Music) | Games + Computer | Control Panel cluster | Shut down.

**Order is not user-reorderable** without binary hacks / third-party shells. Customize only shows/hides or switches link vs menu. | SuperUser / Seven Forums |

### 3.2 Optional right-pane items (Customize Start Menu)

| Label | Default | Display modes |
|-------|---------|---------------|
| Downloads | Off | Don’t display / Link / Menu |
| Recorded TV | Off | Don’t display / Link / Menu |
| Videos | Off | Don’t display / Link / Menu |
| Homegroup | Off (until joined) | Don’t display / Link |
| Network | Off | Don’t display / Link |
| Recent Items | Off | Don’t display / Link |
| Connect To | Off | On/Off |
| Run command | Off | On/Off |
| Favorites menu | Off | On/Off |
| Devices and Printers | On | On/Off |
| Default Programs | On | On/Off |
| Help | On | On/Off |
| Administrative Tools | Off | Don’t display / All Programs / All Programs + Start menu |

Registry map: SF-CUST (`Start_ShowMyDocs`, `Start_ShowControlPanel`, …; 0=hide, 1=link, 2=menu).

### 3.3 Link vs menu behavior

- **Display as a link:** single click opens Explorer / CPL window.  
- **Display as a menu:** hover/click expands a flyout of children (e.g. Documents → recent docs / library roots).  
- Auto-cascade when pausing: `Start_AutoCascade`.

### 3.4 Power button + shutdown flyout

**Main button label:** **Shut down** (default). User can change default action via Taskbar and Start Menu Properties → Start Menu tab → “Power button action” (Shut down / Switch user / Log off / Lock / Restart / Sleep / Hibernate).

**Flyout** (▸ to the right of Shut down), typical order:

1. **Switch user**  
2. **Log off**  
3. **Lock**  
4. **Restart**  
5. **Sleep**  
6. **Hibernate**  

| Variance (Ultimate) | Rule |
|---------------------|------|
| Sleep | Shown when ACPI S3 (or hybrid) supported and not disabled by policy/powercfg |
| Hibernate | Shown when hibernation **enabled** (`powercfg /hibernate on`) and disk has hiberfil.sys; Ultimate SKU supports it; often hidden on small-SSD OEM images until enabled |
| Switch user | Hidden if Fast User Switching disabled by policy |
| Domain | “Switch user” / “Log off” wording unchanged; smart-card variants possible |

Right-click on Shut down button: typically offers the same power-related context as properties path (no full Jump List).

---

## 4. Start Menu — interactions

### 4.1 Interaction table — Start

| Action | Gesture | Result |
|--------|---------|--------|
| Open Start | Left-click Start orb **or** press **Win** | Start opens; focus in search box |
| Close Start | Win again, **Esc**, click outside, launch item, or orb again | Start closes |
| Launch pinned/MFU | Left-click item | App launches; Start closes |
| Jump List (Start item) | Hover/click ▸ **or** right-click item | Jump List for that app |
| Pin to Start Menu | Right-click app (All Programs / search result) → **Pin to Start Menu** | Appears in pinned section |
| Unpin from Start Menu | Right-click pinned → **Unpin from Start Menu** | Removed from pinned |
| Pin to Taskbar | Right-click → **Pin to Taskbar** | Superbar pin |
| Drag to pin | Drag shortcut onto pinned area (when drag-drop enabled) | Pins |
| Reorder pins | Drag pinned items vertically | New order persisted |
| All Programs | Click **All Programs** | Left pane → program tree |
| Back from All Programs | Click **Back** | Restore pinned+MFU |
| Type to search | With Start open, type characters | Instant filter / categorized results |
| Run top hit | **Enter** | Opens focused (top) result |
| Clear / dismiss search | **Esc** (first clears query if non-empty in some builds; otherwise closes) | Prefer: Esc closes Start when query empty |
| Navigate list | ↑ / ↓ / Home / End | Move selection |
| Open right-pane place | Left-click label | Opens destination (table §3.1) |
| Shut down | Left-click **Shut down** | Default power action |
| Power flyout | Left-click ▸ | Menu §3.4 |
| Right-click orb | Right-click Start orb | Properties / Open Windows Explorer / Open Search / (XP Mode etc. if present) — **not** a Jump List of apps |
| Right-click empty Start chrome | Properties | Taskbar and Start Menu Properties |

### 4.2 Keyboard summary

| Key | Result |
|-----|--------|
| **Win** | Toggle Start |
| **Type** | Search filter |
| **Enter** | Launch selected / top result |
| **Esc** | Close Start (or clear) |
| **↑↓** | Move selection in active list |
| **→** | Open Jump List / submenu when chevron present |
| **←** / Backspace | Back from All Programs / close submenu |
| **Win+X** | (Win7) Windows Mobility Center — **not** modern Quick Link menu |
| **Ctrl+Esc** | Equivalent to Win (open Start) |

---

## 5. Start Menu — visuals

| Element | Spec |
|---------|------|
| Aero glass | Translucent DWM glass; left pane often lighter/opaque white list; right pane darker glass |
| Orb resource | `explorer.exe` bitmap strip **54×162** = three **54×54** states: normal / hot / pressed (SF-ORB, VSB). DPI variants: 66×198 (125%), 81×243 (150%), 106×318 (200%) |
| Orb placement | Leftmost of taskbar (bottom orientation); orb **overlaps** above the taskbar top edge slightly (circular hit extends past bar) |
| Hover | Orb brightens (hot state); Start menu item rows highlight; right-pane items highlight |
| Search glyph | Magnifying glass affordance in search box |

---

## 6. Taskbar (Superbar) — geometry & chrome

### 6.1 Height, lock, position

| Property | Value | Citation |
|----------|-------|----------|
| Default height (large icons) | **40 px** @ 96 DPI | MSFN-H, WDN |
| Height (small icons) | **30 px** @ 96 DPI | MSFN-H |
| Unlocked resize | Drag top edge; large-icon heights snap in **40 px** multiples (1 row = 40, 2 = 80, …) | Shell behavior |
| Lock the taskbar | Prevents move/resize; default often unlocked on fresh install then user-locked | Properties |
| Default edge | **Bottom** | |
| Other edges | Left / Right / Top when unlocked (drag empty area to screen edge) | |
| Auto-hide | Optional; bar slides out on edge hover | Properties |

### 6.2 Start orb size & hit target

| State | Size |
|-------|------|
| Bitmap frame | 54×54 per state |
| Visible orb | ~36–45 px diameter inside frame (asset-dependent) |
| Hit target | Full orb bitmap bounds; slightly larger than taskbar height visually |

### 6.3 Icons — small vs large

| Mode | Icon px | Typical button width (combined, icon-only) | Labels |
|------|---------|---------------------------------------------|--------|
| Large (default) | **32×32** | ~54–62 px | Hidden when “Always combine, hide labels” |
| Small | **16×16** | ~30–40 px | Same |

When **Never combine** / **Combine when full**, labeled buttons use MinWidth defaults ≈ **56** (large) / **40** (small). | MDL |

### 6.4 Grouping / stacking / combine modes

Taskbar Properties → Taskbar buttons:

| Mode | Behavior |
|------|----------|
| **Always combine, hide labels** (default) | One button per AppUserModelID; no text; multiple windows stack under one button with peek thumbnails |
| **Combine when taskbar is full** | Separate labeled buttons until crowded, then combine |
| **Never combine** | One button per window; labels shown |

Grouping key = **AppUserModelID** (process default or per-window override). | MS-API, MS-TB |

### 6.5 Live Preview (Aero Peek thumbnails)

| Property | Behavior | Citation |
|----------|----------|----------|
| Trigger | Hover taskbar button (MouseHoverTime, default **400 ms**) | Community / Mouse key |
| Content | **One thumbnail per window/tab** in the group (Win7 change vs Vista stack) | MS-TB |
| Default size | ~**96 px** (longest side / height community default before registry override) | TWC |
| Live preview | Hover a thumbnail → DWM peeks that window (others glassed/hidden) | MS-TB |
| Close | **×** on thumbnail closes that window | HOTKEYS / ITW |
| Middle-click thumbnail | Close that window | HOTKEYS |
| Fallback | If too many thumbnails, shell may fall back to icon/list representation | MS-TB |
| Requirement | Aero / DWM composition on | MS-TB |

---

## 7. Jump Lists (taskbar + Start)

### 7.1 Structure (top → bottom, categories with content only)

1. **Pinned** destinations (user-pinned nouns)  
2. **Recent** *or* **Frequent** destinations (shell default category; app may choose Frequent vs Recent)  
3. **Custom** categories (app-defined via `ICustomDestinationList`)  
4. **Tasks** (app verbs — `IShellLink` with args; should be static)  
5. **Taskbar tasks** (always present when relevant):  
   - Application name / “Open” new instance  
   - **Pin this program to taskbar** / **Unpin this program from taskbar**  
   - **Close window** / **Close all windows**  

| Distinction | Destinations | Tasks |
|-------------|--------------|-------|
| Nature | Nouns (files, URLs, shell items) | Verbs (actions) |
| API | `IShellItem` / recent docs | `IShellLink` + args |
| Pin | User can pin destination into Pinned category | N/A |

| MS-TB |

### 7.2 Opening Jump Lists

| Gesture | Result |
|---------|--------|
| Right-click taskbar button | Jump List |
| Click-drag upward on button (touch-oriented) | Jump List |
| **Shift+Right-click** | **Classic window menu** (Restore / Move / Size / Minimize / Maximize / Close) — **not** Jump List |
| **Win+Alt+N** (N = 1–9/0 position) | Jump List for that pin slot |

### 7.3 Pin / unpin

- Right-click running or Start item → Pin to Taskbar / Unpin.  
- Drag app to taskbar → pin.  
- Drag file onto pinned app → pins destination to that app’s Jump List (or opens with Shift+drag).  
- **Programmatic pinning by apps is not permitted** (policy of Win7). | MS-TB |

---

## 8. Notification area (system tray)

### 8.1 Layout (right → left toward clock)

Far right of taskbar (before Show Desktop):

1. **Show Desktop** peek strip (see §9)  
2. **Clock / date** (two-line on tall enough bar: time + date)  
3. **System icons** (order typically): **Action Center** (flag) · **Power** (batteries/laptops) · **Network** · **Volume**  
4. **User notification icons** (shown or overflow)  
5. **Overflow chevron** (▴) — “Show hidden icons”

### 8.2 Behaviors

| Topic | Win7 rule | Citation |
|-------|-----------|----------|
| Default visibility | Non-system icons **hidden** by default; only user chooses permanent visibility | MS-TB, MS-NA |
| Per-icon modes | Show icon and notifications / Only show notifications / Hide icon and notifications | MS-NA |
| Overflow | Chevron opens flyout of hidden icons; drag between flyout and tray to promote/demote | MS-NA |
| System icons on/off | Clock, Volume, Network, Power, Action Center — separate “Turn system icons on or off” | MS-NA |
| Action Center | Flag icon; white = OK; overlays for messages; opens Action Center CPL | Win7 feature |
| Volume | Speakers icon; click = volume flyout; mixer link | |
| Network | Status glyph; click = View Available Networks / Network flyout | |
| Power | Present on battery systems; click = power info / options | |
| Clock | Left-click = calendar flyout; right-click = Adjust date/time | |

---

## 9. Show Desktop (Aero Peek at far right)

| Property | Exact behavior | Citation |
|----------|----------------|----------|
| Position | Extreme right of taskbar (bottom bar); thin vertical hit strip | MS-TB |
| Default width | ~**8–15 px** (often ~8–10 without Tablet PC Components; can enlarge when pen/touch stack present) | SU-SD |
| Hover (Peek) | After delay (**default 1000 ms**, `DesktopLivePreviewHoverTime`), all windows glass → desktop visible; outlines remain | SF-PEEK, MS-TB |
| Click | **Show Desktop** — minimize/hide windows to desktop (toggle restores) | MS-TB |
| Win+Space | Peek desktop while held (Win7) | HOTKEYS |
| Win+D | Show/restore desktop | HOTKEYS |
| Disable Peek | Taskbar Properties → “Use Aero Peek to preview the desktop” unchecked; click-to-show-desktop remains | |

---

## 10. Taskbar button — mouse & keyboard

### 10.1 Interaction table — task buttons

| Action | Gesture | Result |
|--------|---------|--------|
| Activate / restore | Left-click **inactive** button | Restore/activate last active window of group (default). Multiple windows → may show peeks first depending on combine mode; default combined: click activates last, second click cycles unless `LastActiveClick` tweaked |
| Minimize | Left-click **active** foreground group | Minimizes that window |
| New instance | **Shift+Left-click** or **Middle-click** | Starts new instance |
| Elevated new instance | **Ctrl+Shift+Left-click** | Run as administrator (UAC) |
| Cycle group | **Ctrl+Left-click** on combined button | Cycles windows in group |
| Jump List | Right-click | Jump List §7 |
| Window menu | **Shift+Right-click** | Classic system menu |
| Close from peek | Thumbnail **×** or middle-click thumbnail | Close that window |
| Launch by index | **Win+1** … **Win+0** | Launch/switch pin slot 1–10 |
| New instance by index | **Shift+Win+N** | New instance of slot N |
| Cycle by index | **Ctrl+Win+N** | Cycle windows of slot N |
| Jump List by index | **Win+Alt+N** | Jump List for slot N |
| Focus taskbar | **Win+T** | Focus first button; arrows cycle |
| Focus tray | **Win+B** | Focus notification area |
| Reorder | Drag buttons | Persist order |
| Peek hold | Hover button → thumbnails; move into thumbnail | Live preview that window |

### 10.2 Default pinned apps (fresh Ultimate)

Typical OEM/Microsoft default pin set: **Internet Explorer**, **Windows Explorer**, **Windows Media Player** (order may vary slightly by image). | WDN |

---

## 11. Multi-monitor (Win7 Ultimate / SP1) — accuracy gate

| Fact | Native Win7 |
|------|-------------|
| Taskbar on secondary monitors | **No.** Taskbar exists **only on the primary display**. | MS-MM, SU-MM |
| Secondary monitors | Wallpaper + windows only; no Superbar, no tray, no Show Desktop strip | |
| Moving taskbar | Can place the **single** taskbar on any edge of the **primary** monitor, or drag to another monitor’s edge — that monitor **becomes** the one hosting the bar (still one bar) | |
| Window buttons | All windows’ buttons appear on the single primary taskbar regardless of which monitor hosts the window | |
| Per-monitor taskbars | **Third-party only** (UltraMon, DisplayFusion, Dual Monitor Taskbar, Actual Multiple Monitors, …). Not shipped in Ultimate or SP1. | |

> Omarchy may choose an enhanced multi-monitor Superbar policy, but that is a **product delta**, not Win7 parity. Document deltas explicitly.

---

## 12. Toolbars (optional)

Right-click taskbar → Toolbars:

| Toolbar | Role |
|---------|------|
| **Address** | URL/path entry on bar |
| **Links** | IE Favorites Links band |
| **Desktop** | Desktop icons as menu/band |
| **New toolbar…** | Point at any folder |
| Quick Launch | **Removed as default UI** in Win7; folder still exists for compat (`FOLDERID_QuickLaunch`) but no inbox UI | MS-TB |

Deskbands (e.g. old WMP mini mode) still possible via `IDeskBand2` + glass. | MS-TB |

---

## 13. Control Panel destinations reachable from Start right pane

### 13.1 Direct right-pane entries that are Control Panel surfaces

| Start label | Destination | CPL / shell |
|-------------|-------------|-------------|
| **Control Panel** | Control Panel home (Category view default; can be Large/Small icons) | `shell:ControlPanelFolder` / `control.exe` |
| **Devices and Printers** | Devices and Printers | `control printers` / `shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}` |
| **Default Programs** | Default Programs hub | `control /name Microsoft.DefaultPrograms` |
| **Help and Support** | Help (not CPL, but Start right pane) | `helpane.exe` / HelpPane |

### 13.2 Control Panel categories / items opened *through* Control Panel home

From **Start → Control Panel** (Category view), stock Ultimate destinations include (non-exhaustive hub map implementers must cover for parity navigation):

**System and Security**  
- Action Center · Windows Firewall · System · Windows Update · Power Options · Backup and Restore · BitLocker Drive Encryption · Administrative Tools  

**Network and Internet**  
- Network and Sharing Center · Homegroup · Internet Options  

**Hardware and Sound**  
- Devices and Printers · AutoPlay · Sound · Power Options (link) · Display · Windows Mobility Center  

**Programs**  
- Programs and Features · Default Programs · Desktop Gadgets  

**User Accounts and Family Safety**  
- User Accounts · Parental Controls · Windows CardSpace · Credential Manager  

**Appearance and Personalization**  
- Personalization · Display · Desktop Gadgets · Taskbar and Start Menu · Ease of Access Center · Folder Options · Fonts  

**Clock, Language, and Region**  
- Date and Time · Region and Language  

**Ease of Access**  
- Ease of Access Center · Speech Recognition  

**Additional / All Control Panel Items** (icon views):  
Action Center, Administrative Tools, AutoPlay, Backup and Restore, BitLocker Drive Encryption, Color Management, Credential Manager, Date and Time, Default Programs, Desktop Gadgets, Device Manager, Devices and Printers, Display, Ease of Access Center, Folder Options, Fonts, Getting Started, HomeGroup, Indexing Options, Internet Options, Keyboard, Location and Other Sensors, Mouse, Network and Sharing Center, Notification Area Icons, Parental Controls, Pen and Touch, Personalization, Phone and Modem, Power Options, Programs and Features, Recovery, Region and Language, RemoteApp and Desktop Connections, Sound, Speech Recognition, Sync Center, System, Taskbar and Start Menu, Troubleshooting, User Accounts, Windows CardSpace, Windows Defender, Windows Firewall, Windows Update, plus optional items (Tablet PC, Biometric, etc.) when features enabled.

### 13.3 Library / folder destinations (not CPL)

| Start label | Destination |
|-------------|-------------|
| User tile | `%UserProfile%` |
| Documents | Documents library |
| Pictures | Pictures library |
| Music | Music library |
| Games | Games Explorer (`shell:Games`) |
| Computer | Computer folder |

---

## 14. Registry cheat-sheet (read-only reference)

`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced`

| Value | Meaning |
|-------|---------|
| `Start_MinMFU` | Number of recent programs (default 10) |
| `Start_JumpListItems` | Jump List destination count (default 10) |
| `Start_ShowMyDocs` / `MyPics` / `MyMusic` / `MyGames` / `MyComputer` / `ControlPanel` / `User` / … | 0 hide / 1 link / 2 menu |
| `Start_ShowPrinters` | Devices and Printers |
| `Start_ShowSetProgramAccessAndDefaults` | Default Programs |
| `Start_ShowHelp` | Help |
| `Start_LargeMFUIcons` | Large icons in Start MFU |
| `TaskbarSmallIcons` | 1 = small Superbar icons |
| `TaskbarGlomming` / combine mode via Properties UI | Combine behavior |
| `DesktopLivePreviewHoverTime` | Show Desktop peek delay (ms; default 1000) |

---

## 15. Parity non-goals (explicit)

- Win10/11 Start tiles, centered taskbar, Widgets, Search highlight  
- Native secondary-monitor taskbars  
- XP cascading All Programs (unless product opts into Classic Shell–like delta)  
- Programmatic pin-by-app  
- Resizable Start width/height via drag  

---

## 16. Implementer checklist

- [ ] Two-pane Start; search bottom-left; Shut down bottom-right  
- [ ] Right-pane labels/order match §3.1  
- [ ] All Programs is **in-pane**, with Back — not flyout  
- [ ] Search categories + top-3 + See more results  
- [ ] Power flyout order + SKU/hibernate variance  
- [ ] Superbar 40/30 height; orb 54×54 states  
- [ ] Jump List structure + Shift+Right-click window menu  
- [ ] Left-click minimize-active / activate-inactive; Shift/middle new instance; Ctrl cycle  
- [ ] Notification: Action Center, volume, network, power, clock, overflow  
- [ ] Show Desktop thin strip + hover peek + click toggle  
- [ ] **Single** taskbar on primary only for strict Win7 parity  

