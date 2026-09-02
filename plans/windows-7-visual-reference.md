# Windows 7 Ultimate visual reference

This document exists because the shell was being built from memory of Windows 7 rather than from Windows 7. Every section below states what the component *is* in Windows 7 Ultimate, what it *measures and colours*, and which Omarchy file owns it. Build against this, not against a recollection.

`plans/project-ultimate.md` owns the phase order and the capability taxonomy. This document owns the appearance. A phase is not finished when its capability works; it is finished when its capability works and the surface matches the anatomy here.

## How to use this

- Numbers written as `12px` are at 96 DPI / 100% scale, which is what the reference screenshots are.
- A value marked **measured** comes from a source listed below. A value marked **derived** is computed from a measured one. A value marked **inferred** is a judgement call and may be wrong — challenge it before copying it.
- When a section says a thing is absent from Windows 7, absent is the specification. Do not add it back because it seems useful. `Trash`, iOS-style count badges, and a centred window title in Explorer were all invented on this project and all had to be removed.
- When you change a surface, capture it on metal and put the capture next to the reference. Do not reason about appearance from source.

## Sources

| Source | What it is good for |
| --- | --- |
| `khang-nd/7.css` (`gui/_variables.scss`, `gui/_window.scss`, `gui/_listview.scss`, `gui/_menu.scss`, `gui/_searchbox.scss`, `gui/_typography.scss`) | Faithful CSS recreation. The single best source of exact colours, gradients, radii, and control metrics. Most measured values below come from here. |
| `B00merang-Project/Windows-7` (GTK 3 theme) | Corroborates the surface and selection palette on a Linux stack. |
| Microsoft Windows UX Interaction Guidelines (Windows 7 edition) | Principles and behaviour, not pixels. Useful for what a component is *for*. |
| istartedsomething, "Measuring up Windows 7's new super taskbar" | Taskbar item widths and the Start orb delta from Vista. |
| `aeroshell-desktop/aerothemeplasma` (`plasma/desktoptheme/Seven-Black/widgets/*.svg`, `plasmoids/io.gitgud.wackyideas.seventasks/contents/ui/svgs/*`) | Vector assets carrying Windows 7's own gradients. Read the stops out of the SVG; **do not ship the files.** The project is AGPL but its README states the resources belong to Microsoft, so they are reference for redrawing, not artwork to vendor. |

## 0. Global

### Typography

| Role | Value | Status |
| --- | --- | --- |
| UI font | Segoe UI, 9pt = **12px** | measured |
| Body colour | `#000000` | measured |
| Disabled text | `#838383` | measured |
| Link | `#0066cc`, hover `#3399ff` | measured |
| Heading / group title | `#003399` | measured |
| Section heading ("Documents library") | 11pt ≈ **14.7px**, `#003399` | measured |
| Page instruction ("Adjust your computer's settings") | 12pt = **16px**, `#003399` | measured |
| Document heading | Calibri 17pt | measured |

Segoe UI is not redistributable. **Selawik** is Microsoft's metric-compatible open substitute and is what this project ships (`install/omarchy-base.packages`). Bind text to Selawik, never to a generic sans.

### Surfaces and controls

| Token | Value | Status |
| --- | --- | --- |
| Dialog / chrome surface | `#f0f0f0` | measured |
| Control face gradient | `linear-gradient(#f2f2f2 45%, #ebebeb 45%, #cfcfcf)` | measured |
| Control hover gradient | `linear-gradient(#eaf6fd 45%, #bee6fd 45%, #a7d9f5)` | measured |
| Control pressed gradient | `linear-gradient(#e5f4fc, #c4e5f6 30% 50%, #98d1ef 50%, #68b3db)` | measured |
| Control border | `#8e8f8f`; hover `#3c7fb1`; pressed `#6d91ab`; disabled `#adb2b5` | measured |
| Control radius | `3px` | measured |
| Control inner highlight | `inset 0 0 0 1px #ffffffcc` | measured |
| List row selection border | `#aaddfa` | measured |
| List row selection fill | `linear-gradient(#ffffff99, #e6ecf5cc 90%, #ffffffcc)` | measured |

The selection fill is the single most-mistaken value on this project. Windows 7's list selection is a **near-white, barely-blue wash with a pale blue border** — it is not a saturated blue gradient. Build it from `#e6ecf5` and `#aaddfa`, not from a "selection blue".

Every Windows 7 gradient has its inflection at **45%**, not 50%. The upper 45% is the lighter half, the lower 55% the darker. Reproduce that ratio; it is what makes a control read as Windows 7 rather than as generic glossy.

**Omarchy owner:** `shell/Commons/Tokens.qml` for the shared token layer, `shell/apps/ultimate-files/ExplorerTheme.js` for the Explorer palette. These two must not drift. Phase 3 requires one pipeline driving both Superbar and hyprbars.

## 1. Window frame and caption

### Anatomy

A Windows 7 Aero window is five layers, outside in:

1. A drop shadow: `2px 2px 10px 1px #000000b3`. **measured**
2. A 1px outer border, `#000000b3` — near-black at 70% alpha, *not* an opaque dark slate. **measured**
3. A 1px white inner highlight just inside it, `inset 0 0 0 1px #ffffffaa`. **measured**
4. The glass frame itself: **6px** on the left, right, and bottom; the caption on top. Corner radius **6px**. **measured**
5. The client area, itself bordered 1px and offset by the 6px frame margin. **measured**

The glass is a **blue** base — `#4580c4` — carrying `linear-gradient(to right, #ffffff66, #0000001a, #ffffff33)`, drawn at **0.6 opacity** over a `blur(4px)` backdrop. **measured**

Across the caption runs a single bright band: `linear-gradient(transparent 20%, #ffffffb3 40%, transparent 41%)` — a hard-edged white highlight at 40% of the caption height. **measured** This band is the defining feature of Aero. A smooth top-to-bottom gradient is not Aero.

### Caption text

Explorer's caption in Windows 7 is **blank**. There is no window title. Other applications (Notepad, Calculator) do show a title, in **black**, `line-height: 15px`, with a heavy white glow behind it (`text-shadow` repeated eight times at `0 0 10px #fff`) so black text stays legible on any glass hue. **measured**

Do not centre a title in Explorer. Do not colour caption text from a theme foreground token; it is black with a white halo, always.

### Caption buttons

They are a **group**, not three separate buttons: a container that hangs from the top edge of the frame with no top border, `border-radius: 0 0 5px 5px`, background `#ffffff33`, border `1px solid #0000004d`, and an outer glow `0 1px 0 #fffa, 1px 0 0 #fffa, -1px 0 0 #fffa`. **measured**

| Button | Width | Height | Status |
| --- | --- | --- | --- |
| Minimize | 29px | 19px | measured |
| Maximize / Restore | 29px | 19px | measured |
| Close | **48px** | 19px | measured |

They are separated by a 1px `#0000004d` rule, not by padding. The first button rounds its bottom-left corner, the last its bottom-right.

Face: `linear-gradient(#ffffff80, #ffffff4d 45%, #0000001a 50%, #0000001a 75%, #ffffff80)`. **measured**

Close adds, beneath that: `radial-gradient(circle at -60% 50%, #0007 5% 10%, #0000 50%), radial-gradient(circle at 160% 50%, #0007 5% 10%, #0000 50%), linear-gradient(#e0a197e5, #cf796a 25% 50%, #d54f36 50%)`. **measured** The two radial gradients are the dark shading at the left and right ends — a flat red rectangle is wrong.

Hover is a **cyan glow**, `0 0 7px 3px #5dc4f0`, over `radial-gradient(circle at bottom, #2aceda, transparent 65%), linear-gradient(#b6d9ee 50%, #1a6ca1 50%)`. Close hovers orange-red instead: glow `#e68e75` over `linear-gradient(#fb9d8b, #ee6d56 25% 50%, #d42809 50%)`. **measured**

### Omarchy mapping

| Windows 7 | Omarchy |
| --- | --- |
| DWM composition, blur, colorization | Hyprland `decoration.blur`, `default/hypr/desktop-windows.lua` |
| Frame border, radius, shadow | `general.border_size`, `general.col.*`, `decoration.rounding`, `decoration.shadow` in the same file |
| Caption bar and buttons | vendored `default/hypr/plugins/hyprbars/` — `barDeco.cpp` renders, `main.cpp` registers config and buttons, `globals.hpp` holds `SHyprButton` |
| Caption colour source | `chrome-tokens-v0.json` adapter → `chrome_aero_*` helpers in `desktop-windows.lua` |

**Known gaps as of this writing:** the caption glass is neutral-grey rather than blue; the bright band is approximated with stacked bands instead of one hard-edged highlight at 40%; the buttons are separate rounded rects rather than a hanging bordered group; the close button carries no radial end-shading; hover has no glow; Explorer still draws a centred title.

The plugin is vendored precisely so these can be fixed in C++. Adding a config key and a render pass to `barDeco.cpp` is the expected way to close them. Never hot-reload the plugin to test (program invariant 5): rebuild, then restart the compositor.

## 2. Superbar (taskbar)

### Anatomy

The panel gradient, extracted from AeroThemePlasma's `Seven-Black/widgets/panel-background.svg`, which carries Windows 7's own asset geometry:

| Stop | Colour |
| --- | --- |
| 0.000 | `#000000` |
| 0.186 | `#001520` |
| 0.494 | `#001b29` |
| 0.670 | `#001f2e` |
| 1.000 | `#000000` |

**measured.** The bar is near-black with a faint blue-teal centre and darkens at both edges. It is not a grey or charcoal strip, and it is not colourised by the Aero caption colour.

Taskbar button overlays from the same source (`tasks.svg`) are consistently three stops at 0 / 0.21 / 1.0, light greys between 46% and 91% alpha over that dark ground — for example `#e5e5e5 @0.49`, `#e5e5e5 @0.46`, `#f2f2f2 @0.70`. **measured**

| Property | Value | Status |
| --- | --- | --- |
| Height, large icons (default) | **40px** | measured |
| Height, small icons | **30px** | measured |
| Pinned item width, small icons | 44px | measured |
| Start orb | ~8px narrower than Vista's; overhangs the bar's top edge | measured |
| Icon size, large | 32px | inferred |

The bar is **dark** translucent glass — Windows 7's default taskbar is not light. It carries the same structure as the caption: a bright 1px top edge, a lighter upper region, a seam, and a deeper lower region.

Running applications show a **bordered glass tile** behind the icon. The tile is the Windows 7 idiom for "running"; a coloured underline is not. Multiple windows of one application show as a stacked tile edge. Hover raises a **colour-sampled** highlight — the tile tints toward the dominant colour of the application's icon — and a live thumbnail appears above.

The notification area is at the right: an overflow chevron, then the visible tray icons, then the clock (two lines: time above, date below), then the Show Desktop strip at the far right edge.

### Windows 7 has no count badges

There is no numeric badge on a Windows 7 taskbar button. Progress is shown as a **green fill sweeping the button's background**; attention is shown by the button **flashing orange**. A red circular count is an iOS idiom and does not belong on this surface.

### Jump lists

Right-click on a taskbar button opens a **jump list**: a dark translucent panel that rises from the button, with the application's pinned destinations and recent items grouped under headings, and Unpin / Close at the bottom. It is anchored to the button, it is modal to the pointer, and only one may be open. Two overlapping menus is a defect, not a layering question.

### Omarchy mapping

| Windows 7 | Omarchy |
| --- | --- |
| Taskbar surface, glass | `shell/plugins/ultimate-taskbar/Taskbar.qml` |
| Start orb | `shell/plugins/ultimate-taskbar/StartButton.qml` |
| Running/pinned buttons | `shell/plugins/ultimate-taskbar/TaskButton.qml` |
| Tray cluster | `shell/plugins/ultimate-taskbar/TrayCluster.qml` |
| Jump lists | `shell/services/AppSearch.js` supplies desktop actions; the taskbar renders them |

**Known gaps:** count badges are rendered and must go; jump lists and context menus can overlap; left-click interactions are unreliable; the Start orb is a flat tile rather than a sphere overhanging the bar; hover does not sample icon colour; there are no live thumbnails.

## 3. Start menu

Two panes in a single glass panel. Left: search box at the bottom, pinned items above it, then recently-used, with a "All Programs" toggle that replaces the left pane with a scrolling letter-grouped tree. Right: a column of destinations — the account name and picture at the top, then Documents, Pictures, Music, Games, Computer, Control Panel, Devices and Printers, Default Programs, Help and Support — then the power button with a flyout for Lock / Log off / Restart / Sleep / Shut down.

Right-pane entries are text with a small icon, on the panel's glass. Hovering a left-pane item with sub-destinations shows an arrow that expands a jump list in place of the right pane.

**Omarchy owner:** `shell/plugins/ultimate-start/Start.qml`.

## 4. Explorer

This is the surface the reference screenshot shows, band by band from the top.

### 4.1 Frame and caption

As section 1. Explorer's caption carries **no title text**.

### 4.2 Address bar row

On the glass, continuous with the caption — no separate background.

- **Back and Forward**: two circular buttons at the far left, adjacent, in a shared recess. Back is enabled-blue when there is history. A small dropdown chevron sits to their right for recent locations.
- **Address bar**: a white field, 1px border, filling most of the row. Inside: the current location's 16px icon, then the breadcrumb — each segment a clickable button separated by a **filled black wedge** (`▸`). The wedge is itself a control: clicking it lists that segment's siblings. A trailing wedge follows the last segment.
- **Refresh**: a circular-arrow button at the right end *inside* the address field.
- **Search box**: a separate white field to the right of the address bar. Height **24px**, padding `3px 6px`, radius `2px`, `box-shadow: inset 1px 1px 0 #8e8f8f, inset -1px -1px 0 #ccc`, min-width **187px**. Its placeholder is **italic**. **measured**

### 4.3 Command bar

A light horizontal bar below the address row. Its buttons are **verb-first and contextual** — the set changes with the selection and the folder type. In the reference (Documents library, one image selected): `Organize ▾` `Open ▾` `Share with ▾` `Print` `E-mail` `Burn`, then at the right a view-mode split button and a `?` help button.

Each entry is text with a small icon before it. `▾` marks entries that open a menu.

### 4.4 Navigation pane

White background, ~200px wide, a splitter on its right edge.

Root sections, in order: **Favorites** (star), **Libraries** (library stack), **Homegroup**, **Computer** (monitor), **Network** (globe). Favorites expands to Desktop, Downloads, Recent Places plus user-pinned entries; Libraries to Documents, Music, Pictures, Videos; Computer to the drives.

Section headers are **regular weight**, not bold, each with a 16px icon and an expander triangle to its left. The triangle is hollow-outlined when collapsed and filled dark when expanded. Selected row: the pale `#e6ecf5` / `#aaddfa` wash from section 0, full width, 3px radius.

### 4.5 Content pane

White. For a **library**, a header band sits above the items: the library name at 11pt `#003399` ("Documents library"), with `Arrange by: Folder ▾` at the right and `Includes: 2 library locations` as a link. Plain folders have no such header.

View modes: Extra Large / Large / Medium / Small Icons, List, Details, Tiles, Content. Large Icons is a grid of icon-over-centred-label tiles. Details is a column table:

| Property | Value | Status |
| --- | --- | --- |
| Header height | 22px | measured |
| Header fill | `linear-gradient(#fff 45%, #fafafa 45%, #f0f0f0)` | measured |
| Header border | `1px solid #d7d7d7` | measured |
| Header weight | 400 (not bold) | measured |
| Sorted header fill | `linear-gradient(#f3f9fc 45%, #e4f0f8 45%, #d9eaf5)`, border `#a7d8f5` | measured |
| Sort indicator | a ~6×5 triangle at the **top centre** of the header, `linear-gradient(to bottom right, #667f91 45%, #90c1e2 65%, #cce3f2)` | measured |
| Row height | 14px content + 2px padding = **18px** | measured |
| Column separator | `1px solid #eee` | measured |

The sort arrow sits at the **top edge, horizontally centred** in the sorted column — not at the right end of the header text. Columns are resizable by dragging their separators, and right-clicking the header offers the column set.

Files show **thumbnails** where the shell can generate one, and a type-specific icon otherwise.

### 4.6 Details pane

A band at the bottom of the window, above the frame's bottom edge. Left: a large preview icon of the selection. Right of it: the file name in bold, then the type below it. Then columns of `Label: value` pairs — Date modified, Size, and type-specific fields (Date taken, Tags, Rating, Dimensions for an image). Editable fields render as blue links with placeholder prompts ("Add a tag", "Specify date taken"). Rating renders as five stars.

With nothing selected, it describes the folder: item count and the folder's own name.

Windows 7 Explorer has no separate status bar; the details pane is it.

### 4.7 Behaviours

Double-click opens; single-click selects; Enter opens; Backspace and Alt+Up go to the parent; Alt+Left / Alt+Right move through history; F2 renames in place; Delete moves to the Recycle Bin; Ctrl+X/C/V move and copy; type-ahead jumps to the first matching name; F5 refreshes; Ctrl+F focuses search.

### Omarchy mapping

| Windows 7 | Omarchy |
| --- | --- |
| Explorer window | `shell/apps/ultimate-files/FilesApplication.qml` |
| Address bar | `ExplorerAddressBar.qml`, `ExplorerCircleButton.qml` |
| Command bar | `ExplorerCommandBar.qml` |
| Navigation pane | `ExplorerNavigationPane.qml` |
| Details / Icons / List views | `ExplorerItemView.qml` |
| Computer window | `ExplorerComputerView.qml` |
| Details pane | `ExplorerDetailsPane.qml` |
| Properties dialog | `FilesRecordCard.qml` inside the dialog in `FilesApplication.qml` |
| Icons | `ExplorerIcon.qml` (drawn, not themed) |
| Palette | `ExplorerTheme.js` |
| Data | `files.provider` — `default/fabric/omarchy_fabric/providers/files/provider.py`, routes in `routes-v1.json`, locations in `default/ultimate/files/locations-v0.json` |

**Known gaps:** selection is too saturated; the sort indicator is at the header's right rather than top-centre; columns cannot be resized; there is no library header band; the details pane has no editable fields or rating; there are no thumbnails (the provider never reads file contents by design — decide explicitly whether to add a thumbnail capability or accept type icons permanently); no rename, no clipboard; the command bar has no icons and a shorter verb set than Windows 7's.

## 5. Control Panel

Category view is a two-column list of eight categories, each an icon plus a heading link in `#003399` and two or three task links beneath in `#0066cc`. A `View by:` dropdown at the top right switches to Large icons / Small icons — a flat alphabetical grid of every applet. The page instruction "Adjust your computer's settings" sits at 12pt `#003399` above the columns.

The left rail carries "Control Panel Home" plus related tasks. The address bar and search box are the same controls as Explorer.

**Omarchy owner:** `shell/apps/ultimate-settings/SettingsApplication.qml`. It should read as Control Panel — category headings, task links, `View by:` — rather than as a settings app with cards.

## 6. Common controls

| Control | Specification | Status |
| --- | --- | --- |
| Push button | `linear-gradient(#f2f2f2 45%, #ebebeb 45%, #cfcfcf)`, 1px `#8e8f8f`, radius 3px, inner highlight `inset 0 0 0 1px #fffc` | measured |
| Button hover | `linear-gradient(#eaf6fd 45%, #bee6fd 45%, #a7d9f5)`, border `#3c7fb1` | measured |
| Button pressed | `linear-gradient(#e5f4fc, #c4e5f6 30% 50%, #98d1ef 50%, #68b3db)`, border `#6d91ab`, `inset 1px 1px 0 #0003, inset -1px 1px 0 #0001` | measured |
| Menu panel | bg `#f0f0f0`, border `1px solid #0006`, shadow `4px 4px 3px -2px #00000080`, padding 2px | measured |
| Menu gutter | a 2px vertical rule 28px from the left, `inset 1px 0 #00000026, inset -1px 0 #fff` | measured |
| Menu bar | `linear-gradient(#fff 20%, #f1f4fa 25%, #f1f4fa 43%, #d4dbee 48%, #e6eaf6)`; item hover `#3399ff` with white text | measured |
| Tree expander | 8px box, `linear-gradient(#f2f2f2 45%, #ebebeb)`, 1px `#919191`, radius 1px, glyph `#4b63a7` | measured |
| Status bar | bg `#f0f0f0`, 1px `#000000b3`, no top border | measured |

Context menus are `#f0f0f0` with a left gutter — not white panels. This project currently draws them white.

## 7. Icons

Windows 7 icons are drawn in perspective with a light source at the top left, not flat.

- **Folder**: a manila folder seen slightly from above — a back plate with a raised tab at the top left, and a front panel tilted forward so its top edge is visible as a lighter band. Warm yellow, roughly `#ffe9a0` at the top to `#f0b83e` at the bottom, outlined `#a67c1f`. Special folders carry a small emblem on the front panel rather than a different colour.
- **Drive**: a three-quarter view of a drive body with a visible top face, a slot, and an activity light.
- **File**: a white page with a folded top-right corner and a type emblem in the lower half.
- **Recycle Bin**: a translucent bin with vertical ribs; the empty and full states are different icons.

This project draws its icons procedurally in `ExplorerIcon.qml` rather than depending on a GTK icon theme, so that a folder reads as a Windows folder. Keep it that way — an icon theme will import the wrong idiom.

## 8. Desktop

Windows 7 ships exactly one desktop icon by default: the **Recycle Bin**. Computer, the user's folder, Network, and Control Panel are all available but off by default, toggled from Personalization → Change desktop icons. The user's folder icon is labelled with the **account name**.

Right-click on the desktop: View, Sort by, Refresh, Paste, Paste shortcut, New, Screen resolution, Gadgets, Personalize.

**Omarchy owner:** `shell/plugins/desktop-icons/DesktopIcons.qml`; the shipped shortcuts live in `default/ultimate/desktop/` and are installed into `~/Desktop`.

## 9. Phase mapping

| Phase in `project-ultimate.md` | Sections here that define "done looks like" |
| --- | --- |
| 3 — Design system | 0 (typography, surfaces, controls), 6 (common controls) |
| 4 — Desktop shell | 1 (frame and caption), 2 (Superbar), 3 (Start), 8 (desktop) |
| 5 — Settings | 5 (Control Panel), 6 |
| 6 — Files and defaults | 4 (Explorer, all sub-sections), 7 (icons) |
| 9 — Administration | 6; Task Manager and Device Manager anatomy still to be added here |
| 11 — Brutal polish | Every "known gaps" list above |

A row in `WINDOWS_7_ULTIMATE_PARITY.md` may not claim more than the matching section here supports. If a surface works but does not look like its section, the row is `prototype`.
