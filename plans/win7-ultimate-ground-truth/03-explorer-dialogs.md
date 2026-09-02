---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# 03 — Windows 7 Ultimate Explorer + Common Dialogs

**Scope:** Windows 7 Ultimate (Aero, command bar — **not** Win8/10/11 ribbon).  
**Audience:** Omarchy Project Ultimate Files app implementers.  
**Success criterion:** Match Win7 Explorer without guessing structure, chrome, menus, or interaction rules.  
**Companion:** `03-EXPLORER-DIALOGS.json` (machine-readable twin).

---

## 0. Chrome overview (Aero Explorer)

A stock Windows 7 Explorer window (Aero theme) stacks vertically:

| Band | Default | Notes |
|------|---------|-------|
| Caption (Aero glass + icon + title + min/max/close) | On | Title is folder/library/Computer name; optional full path via Folder Options → View → “Display the full path in the title bar” |
| Navigation row | On | Circular **Back** / **Forward**, then **Address bar** (breadcrumbs), then **Search box** |
| **Command bar** (Folder Band) | On | Context-sensitive tasks — **not** a classic toolbar of Cut/Copy/Paste by default; **not** a ribbon |
| Optional classic **Menu bar** (File Edit View Tools Help) | **Off** | Reveal with **Alt** (temporary) or Organize → Layout → Menu bar (sticky) |
| Body: **Navigation pane** \| Items view \| optional **Preview pane** | Nav on; Preview **off** | Splitters are draggable; sizes persist |
| **Details pane** | **On** | Bottom band; selection metadata |
| **Status bar** | **Off** | Toggle via View → Status bar when Menu bar is visible |

**Hard rule for Ultimate parity:** Do **not** implement a Win8+ ribbon. The command bar is a single horizontal strip of text buttons + trailing Views / Preview / Help controls.

**Sources:** Thurrott *Windows 7 Feature Focus: Windows Explorer* (archive); Microsoft TechNet *Windows Browse and Organize Features* (Win7); AskVG command-bar docs.

---

## 1. Command bar — exact items by location

Constant trailing controls (almost every view):

1. **Views** (split button: click cycles most modes; chevron opens full list + size slider)  
2. **Show the preview pane** (toggle; pressed = Preview pane visible)  
3. **Help** (`?` → Windows Help and Support; also **F1**)

**Organize** is always leftmost (except Recycle Bin / some specialty folders which still keep Organize).

### 1.1 Organize dropdown (stock SubCommands)

Typical order (separators as `|`):

| # | Item |
|---|------|
| 1 | Cut |
| 2 | Copy |
| 3 | Paste |
| 4 | Undo |
| 5 | Redo |
| — | separator |
| 6 | Select all |
| — | separator |
| 7 | **Layout** ▶ (Menu bar, Details pane, Preview pane, Navigation pane) |
| 8 | Folder and search options… |
| — | separator |
| 9 | Delete |
| 10 | Rename |
| 11 | Remove properties |
| 12 | Properties |
| — | separator |
| 13 | Close |

**Layout** checkmarks reflect current pane/menu visibility. **New folder** is often a separate command-bar button pinned at the right of the task group (CommandStore `Windows.newfolder` with Position), not inside Organize.

**Source:** AskVG Organize/Layout SubCommands; NirSoft CustomExplorerToolbar FolderTypes notes.

### 1.2 Location matrix (no selection vs selection)

| Location | No items selected (typical left→right) | With selection (deltas) |
|----------|----------------------------------------|-------------------------|
| **Generic folder** | Organize · Include in library · Share with · Burn · New folder · Views · Preview · Help | Open (or Play / Edit for media) may appear; Share with / Burn stay; New folder remains |
| **Documents library** | Organize · Include in library · Share with · Burn · New folder · **Arrange by** · Views · Preview · Help | Same + Open; Arrange by still present |
| **Music library** | Organize · Include in library · Share with · Play all · Burn · New folder · Arrange by · … | Play / Play all emphasized |
| **Pictures library** | Organize · Include in library · Share with · Slide show · Burn · New folder · Arrange by · … | Slide show when images selected |
| **Videos library** | Organize · Include in library · Share with · Play all · Burn · New folder · Arrange by · … | Play |
| **Libraries root** | Organize · New library · … | Properties / Delete on selected library |
| **Computer** | Organize · **System properties** · **Uninstall or change a program** · **Map network drive** · **Open Control Panel** · Views · Preview · Help | Open / Eject / properties verbs for selected drive |
| **Network** | Organize · … network-oriented tasks | Open / Map network drive on selection |
| **Homegroup** | Organize · … Homegroup tasks | Share/permissions oriented |
| **Favorites** (Links folder view) | Organize · … | Open / Remove |
| **Search results** | Organize · **Save search** · … · Views · Preview · Help | Open; Content view default |
| **Recycle Bin** | Organize · **Empty the Recycle Bin** · Restore all items (when items exist) · … | **Restore this item** / Restore selected; Empty remains |

FolderType GUIDs (registry `HKLM\…\Explorer\FolderTypes`) used by the shell to pick the TasksNoItemsSelected / TasksItemsSelected command lists:

| Folder type | GUID |
|-------------|------|
| Generic | `{5c4f28b5-f869-4e84-8e60-f11db97c5cc7}` |
| Documents library | `{fbb3477e-c9e4-4b3b-a2ba-d3f5d3cd46f9}` |
| Music library | `{3f2a72a7-99fa-4ddb-a5a8-c604edf61d6b}` |
| Pictures library | `{0b2baaeb-0042-4dca-aa4d-3ee8648d03e5}` |
| Videos library | `{631958a6-ad0f-4035-a745-28ac066dc6ed}` |
| Generic library | `{5f4eab9a-6833-4f61-899d-31cf46979d49}` |

**Sources:** Stack Overflow / Experts Exchange FolderTypes; AskVG CommandStore `Windows.*` keys; Microsoft TechNet browse/organize.

---

## 2. Navigation pane

### 2.1 Top-level nodes (default order, top→bottom)

1. **Favorites** (star)  
2. **Libraries**  
3. **Homegroup** (if Homegroup feature present / joined — still shown as node on Ultimate)  
4. **Computer**  
5. **Network**

Optional: user profile folder node can appear when “Show all folders” is enabled (Folder Options → General → Navigation pane).

**CLSID references (rename/hide tutorials):**

| Node | CLSID |
|------|-------|
| Favorites | `{323CA680-C24D-4099-B94D-446DD2D7249E}` |
| Libraries | `{031E4825-7B94-4dc3-B131-E946B44C8DD5}` |
| Homegroup | `{B4FB3F98-C1EA-428d-A78A-D1F5659CBA93}` |
| Computer | `{20D04FE0-3AEA-1069-A2D8-08002B30309D}` |
| Network | `{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}` |

### 2.2 Favorites

- Backed by `%USERPROFILE%\Links` (shortcuts only surface here).  
- **Default links:** Desktop, Downloads, Recent Places.  
- **Add:** drag folder/drive/library onto Favorites, or right-click Favorites → **Add current location to Favorites**.  
- **Remove:** right-click link → **Remove** (does not delete target).  
- **Reorder:** drag within Favorites.  
- **Favorites header RC:** Collapse / Expand / Open in new window / Sort by Name / Restore favorite links / Add current location to Favorites.

### 2.3 Expand / collapse

- Chevron (▶/▼) or double-click node expands/collapses children.  
- Single-click on the **label** navigates the Items view to that location (does not auto-expand on single click — Win7 default).  
- Keyboard: Left/Right collapse/expand when tree focused; Up/Down move selection (Items view syncs on Enter/click, not always on pure arrow in tree — known Win7 quirk).

### 2.4 Right-click menus (per node type)

| Target | Typical verbs |
|--------|----------------|
| Favorites header | Open in new window, Expand/Collapse, Sort by Name, Restore favorite links, Add current location to Favorites |
| Favorite link | Open, Open in new window, Remove, Cut/Copy, Rename (shortcut), Properties |
| Libraries header | Open, Open in new window, Expand/Collapse, New → Library, Properties (limited) |
| Library (Documents etc.) | Open, Open in new window, Share with, Include in library N/A, Restore library defaults (via Properties), Delete, Rename, Properties |
| Computer | Open, Open in new window, Manage (compmgmt), Map network drive, Disconnect network drive, Rename, Properties (System) |
| Drive under Computer | Open, Open in new window, Share with, Include in library, Format…, Rename, Properties, Eject (removable), BitLocker verbs if Ultimate + encrypted |
| Network / Homegroup | Open, Open in new window, Properties; Homegroup-specific leave/change settings |
| Folder in tree | Same as folder context menu (§9) |

**Sources:** AskVG nav-pane rename/hide; Seven Forums Favorites; gHacks Navigation Pane; PCWorld personalize nav bar.

---

## 3. Libraries

Libraries are **virtual aggregators** (`.library-ms` under `%APPDATA%\Microsoft\Windows\Libraries`). Including a folder does **not** move files; file ops act on real paths.

### 3.1 Defaults (Windows 7)

| Library | Included locations (default) | Default save location | Optimized for |
|---------|------------------------------|----------------------|---------------|
| **Documents** | `%USERPROFILE%\Documents` (**My Documents**), `%PUBLIC%\Documents` | My Documents | Documents |
| **Music** | `%USERPROFILE%\Music`, `%PUBLIC%\Music` | My Music | Music |
| **Pictures** | `%USERPROFILE%\Pictures`, `%PUBLIC%\Pictures` | My Pictures | Pictures |
| **Videos** | `%USERPROFILE%\Videos`, `%PUBLIC%\Videos` | My Videos | Videos |

- Max ~**50** included folders per library.  
- Save/copy/drag into the library lands in the **default save location**.  
- Removing the save location auto-promotes the next included location; empty / all read-only → save fails.  
- Library pane strip above Items view: “Includes *N* locations” → Locations dialog (add/remove/set save location).  
- **Arrange by** (library-specific stacks/groups by metadata) persists per library *type*.  
- Indexing required for full Arrange by / rich search; otherwise library becomes “basic” (grep-only).

**Sources:** Microsoft TechNet *Windows Libraries* / *Libraries Walkthrough* (Win7); How-To Geek default save location.

---

## 4. Address bar (breadcrumbs)

### 4.1 Modes

| Mode | How entered | Behavior |
|------|-------------|----------|
| **Breadcrumb** (default) | Always when not editing | Path as clickable nodes separated by ▶ chevrons; leading desktop/root control |
| **Edit** (path text) | Click empty area right of crumbs; or **Alt+D** / **Ctrl+L**; or right-click → Edit address | Full path selected as editable combo (type path, `shell:` verbs, `\\server\share`, URLs handled by shell) |

### 4.2 Interactions

- **Click crumb:** navigate to that ancestor.  
- **Click ▶ after a crumb:** dropdown of **sibling** folders at that level.  
- **Back / Forward:** circular buttons left of address bar; history per window.  
- **Up:** not a dedicated button in Win7 (use **Alt+Up** or Backspace).  
- **Right-click address bar:** Copy address / Copy address as text / Edit address / etc.  
- Overflow: leftmost history dropdown (clock icon / chevron) lists recent locations.

**Sources:** Thurrott address bar; JAWS Win7 Explorer guide (Alt+D vs Tab modes); Eight Forums / community breadcrumb edit click.

---

## 5. Search box

- Right of address bar; watermark like `Search Libraries` / `Search Documents` / `Search Computer` (context-sensitive).  
- Focus: **Ctrl+E** or **Ctrl+F** (also **F3** in many builds).  
- **As-you-type** filtering; results appear in Items view without Enter.  
- Focus shows **recent searches** + **Search Builder** property filters (AQS helpers).

### 5.1 Indexed vs deep (grep) search

| Scope | Mechanism | What matches |
|-------|-----------|--------------|
| **Indexed** (Libraries, user profile paths in index) | Windows Search index | Filename, properties/metadata, **file contents** (textual); ranked relevance |
| **Non-indexed** / basic library | Grep fallback | Primarily **filenames**; limited filters (Date modified, Size); slower |

Search results **default view = Content**. Sort: Search ranking then Date modified. Rank scale 0–1000 (1000 = exact full name match; 0 = not indexed).

### 5.2 Filters (Search Builder)

Click in search box → property chips depend on location:

| Location | Example filters |
|----------|-----------------|
| Computer / generic | Date modified, Size, Name, Type, Folder path |
| Documents library | Authors, Type, Date modified, Size, Name, Folder path, Tags… |
| Music | Artists, Album, Genre, Length, Year, Rating… |
| Pictures | Date taken, Tags, Rating, Dimensions… |

Selecting a filter inserts AQS (`datemodified:`, `size:`, `kind:`, etc.). “Search again” footer links: Computer, Custom…, Internet (policy-dependent), plus pinned libraries/connectors.

**Sources:** Microsoft TechNet *Windows Search Features* (Win7); vip_students Explorer tutorial; JAWS guide.

---

## 6. Views, columns, sort, group

### 6.1 Eight view modes

| View | Approx. icon px | Layout |
|------|-----------------|--------|
| Extra Large Icons | **256×256** | Grid; rich live thumbnails |
| Large Icons | **128×128** | Grid |
| Medium Icons | **64×64** | Grid |
| Small Icons | **16×16** | Wrapping grid |
| List | 16×16 | Multi-column list, names only |
| Details | 16×16 | Single column + **column headers** |
| Tiles | ~48–64 | Icon + name + 1–2 property lines |
| Content | ~32–48 | Full-width rows; type-specific properties; **default for search** |

**Access:**

- Command bar **Views** button (cycle omits Extra Large — use chevron).  
- Views chevron: radio list + **vertical slider** for intermediate sizes.  
- Right-click empty Items area → **View** ▶.  
- **Ctrl + mouse wheel** live-resizes icons.  
- Classic Menu → View when Menu bar on.

**Computer / This PC capacity bars** appear in **Tiles** or **Content** (not Details/Icons). Default Computer view is Tiles-like with bars.

### 6.2 Details columns

- Click header: sort asc/desc (arrow glyph).  
- Right-click header: checklist of columns + **More…** (Column Chooser, reorder).  
- Drag header edges to resize; drag headers to reorder.  
- Folder template (General / Documents / Pictures / Music / Videos) drives default columns via Customize tab / FolderTypes.

### 6.3 Sort by / Group by

Available from:

- Right-click empty area → **Sort by** / **Group by**  
- Classic View menu  
- Libraries: **Arrange by** on command bar (stacks)

Sort by: Name, Date modified, Type, Size, and type-specific properties + Ascending/Descending + More…  
Group by: same properties + (None) + Ascending/Descending; Expand/Collapse all groups.

View settings persist (Win7 fixed Vista “forgets views” bug). Arrange-by mode for a library type applies across libraries of that type.

**Sources:** Thurrott view styles; Microsoft Browse and Organize; geekgirls viewing files; Tips.Net columns.

---

## 7. Details pane / Preview pane / Status bar

| Pane | Default | Position | Resize | Contents |
|------|---------|----------|--------|----------|
| **Navigation pane** | **On** | Left | Horizontal splitter; width persisted | Favorites → Network tree |
| **Details pane** | **On** | Bottom | Vertical splitter; height persisted | Icon/thumbnail, name (editable), key properties/tags; multi-select shows aggregate (“N items”) |
| **Preview pane** | **Off** | Right | Horizontal splitter; width persisted | Handler preview (docs, images); WMP-hosted audio/video play |
| **Status bar** | **Off** | Very bottom | Fixed | Item count / free space hints when enabled |

Toggle: Organize → Layout → … or Preview button; **Alt+P** toggles Preview pane.  
Microsoft: Preview and Details sizes + window size persist across sessions.

**Approximate default sizes (Aero, 96 DPI):** Details pane ~48–72 px tall; Preview pane ~200–320 px wide when first enabled; Navigation pane ~180–220 px. Implementers should persist user drags, not hard-lock pixels.

**Sources:** PCWorld layout article; TechNet Browse and Organize; Thurrott Preview pane.

---

## 8. Computer (This PC)

Shell name in Win7: **Computer** (not “This PC”). Open via Start → Computer, Win+E, or nav pane.

### 8.1 Groups in Items view

1. **Hard Disk Drives** — fixed local volumes (C:, D:, …)  
2. **Devices with Removable Storage** — optical, USB, card readers, floppies  
3. **Network Location** — mapped drives / network places  

(Also “Other”/portable devices when present.)

### 8.2 Capacity bars

- Shown under each drive in **Tiles** / **Content**: `X GB free of Y GB` + horizontal meter (blue → red when low).  
- Missing bars ⇒ view is Icons/List/Details — switch to Tiles/Content.

### 8.3 Drive right-click (representative)

Open, Open in new window, Scan with… (AV extensions), Share with, Include in library, Pin to Start Menu / Taskbar (pin verbs), Format…, Create shortcut, Rename, Properties; BitLocker Turn on/Manage on Ultimate when applicable; Eject for removable; Disconnect for mapped network drives.

**Sources:** AskVG HDD meter; SuperUser capacity bars; product parity notes.

---

## 9. Recycle Bin

| Aspect | Win7 Ultimate behavior |
|--------|-------------------------|
| Desktop icon | Default **on**; toggle Personalize → Change desktop icons |
| Explorer path | `shell:RecycleBinFolder` or CLSID `::{645FF040-5081-101B-9F08-00AA002F954E}`; address bar “Recycle Bin” |
| Per-volume store | `X:\$Recycle.Bin\` (hidden system) |
| Command bar | Empty the Recycle Bin; Restore items |
| Item RC | Restore, Cut, Delete (permanent), Properties |
| Bin RC (desktop) | Open, Empty Recycle Bin, Properties (size per drive, “Don’t move files to Recycle Bin”, max sizes) |
| Delete key | Sends to Bin (unless Shift or policy/bypass) |
| Shift+Delete | **Permanent** delete, no Bin |

**Sources:** SuperUser shell:RecycleBinFolder; Microsoft Recycle Bin UX (era docs).

---

## 10. Desktop context menu (exact order)

**Windows 7 Ultimate** blank-desktop right-click (stock, no third-party shellex):

| # | Item | Notes |
|---|------|-------|
| 1 | **View** ▶ | Large/Medium/Small icons; Auto arrange icons; Align icons to grid; **Show desktop icons**; **Show desktop gadgets** (independent toggles — RC change vs Beta) |
| 2 | **Sort by** ▶ | Name, Size, Item type, Date modified; Ascending/Descending |
| 3 | **Refresh** | |
| — | separator | |
| 4 | **Paste** | Enabled if clipboard has cut/copied files |
| 5 | **Paste shortcut** | |
| — | separator | |
| 6 | **New** ▶ | Folder, Shortcut, then ShellNew types (Bitmap, Contact, Journal, Rich Text, Text Document, Compressed Folder, Briefcase, … OEM/apps) |
| — | separator | |
| 7 | **Screen resolution** | Win7 addition vs Vista; `DesktopBackground\Shell\Display`, Position=Bottom |
| 8 | **Gadgets** | **Ultimate / Home Premium Desktop Gadgets** era — present on Ultimate; `Shell\Gadgets` |
| 9 | **Personalize** | Opens Personalization CPL |

**Not stock:** “Storage properties” / “Display settings” (those are Win10+ labels). Graphics driver entries (NVIDIA/ATI) may inject above New or elsewhere via shellex — ignore for pure Ultimate baseline.

**Sources:** AskVG DesktopBackground Shell; How-To Geek remove Gadgets/Screen resolution; Microsoft E7 blog (icons vs gadgets View split); learn.microsoft.com shortcut menu handlers example order Display/Gadgets/Personalize.

---

## 11. File / folder context menus

### 11.1 Typical file order (static verbs first)

1. **Open** (bold = default)  
2. **Open with** ▶ (optional host / choose default)  
3. *App-specific verbs* (Edit, Print, Play, Preview, …)  
4. **Share with** ▶ (Nobody / Homegroup / Specific people…)  
5. separator  
6. **Send to** ▶ (Compressed folder, Desktop shortcut, Documents, Fax, Mail, Removable drives, …)  
7. **Cut**  
8. **Copy**  
9. separator  
10. **Create shortcut**  
11. **Delete**  
12. **Rename**  
13. separator  
14. **Properties**

Extended verbs (Shift+right-click): e.g. **Open command window here**, **Copy as path**, etc.

### 11.2 Folder extras

- **Open in new window**  
- **Include in library** ▶  
- **Pin to Start Menu** / Taskbar (where applicable)  
- **New** ▶ (when right-clicking empty space inside folder — see below)

### 11.3 Empty-folder background menu

View ▶ · Sort by ▶ · Group by ▶ · Refresh · Paste · Paste shortcut · New ▶ · Properties (folder) · Customize this folder… (classic)

### 11.4 New submenu

Always: **Folder**, **Shortcut**, then registered `ShellNew` types under file associations. Order follows registration / MUI.

Shell extensions (`shellex\ContextMenuHandlers`) append after static verbs; alphabetical key names affect order — third-party noise is expected on real installs; baseline omits them.

**Sources:** MSDN Creating Shortcut Menu Handlers; Free Associations blog verb sort; Stack Overflow context menu order.

---

## 12. Pointer & selection interactions

### 12.1 Interaction matrix — click / select

| Input | Result |
|-------|--------|
| Single left-click item | Select only that item; Details/Preview update |
| Double left-click | Default verb (Open) |
| Click empty space | Clear selection |
| Marquee (drag empty → rubber-band) | Select all intersecting items |
| Ctrl+click | Toggle item in selection |
| Shift+click | Select contiguous range from anchor |
| Ctrl+A | Select all |
| Ctrl+marquee | Add rubber-band set to selection |
| Keyboard arrows | Move focus/selection; Shift extends; Ctrl moves focus without select (Space toggles) |

### 12.2 Drag-drop matrix

| Condition | Default drop effect | Cue |
|-----------|---------------------|-----|
| Same volume (NTFS/FAT path) | **Move** | Arrow pointer |
| Different volume / UNC / optical | **Copy** | **+** badge |
| Drop on Recycle Bin | **Move** to Bin | |
| Drop on executable / special drop targets | Target-defined | |
| Hold **Ctrl** | Force **Copy** | + |
| Hold **Shift** | Force **Move** | |
| Hold **Alt** or **Ctrl+Shift** | **Create shortcut** | shortcut arrow |
| **Right-drag** release | Menu: Copy here / Move here / Create shortcuts here / Cancel | |
| Esc while dragging | Cancel | |

Libraries: drop into library → copy/move into **default save location** (same volume rules apply to that physical path).

### 12.3 Delete matrix

| Action | Result |
|--------|--------|
| Delete / Del | Confirm (optional) → Recycle Bin if Bin enabled for that volume |
| Shift+Delete | Permanent delete confirm → bypass Bin |
| Recycle Bin Properties “Don’t move files…” | Delete always permanent |
| Too-large for Bin quota | Permanent or prompted |

**Sources:** Microsoft Win7 move/copy drag-drop help; Raymond Chen / drag-drop lore; TekRevue modifiers.

---

## 13. Keyboard matrix (Explorer)

| Key | Action |
|-----|--------|
| F2 | Rename |
| Delete | Delete → Bin |
| Shift+Delete | Permanent delete |
| Ctrl+C / Ctrl+X / Ctrl+V | Copy / Cut / Paste |
| Ctrl+A | Select all |
| Ctrl+Z / Ctrl+Y | Undo / Redo (when available) |
| Alt+Up | Parent folder |
| Backspace | Parent folder (Win7 still) |
| Alt+Left / Alt+Right | Back / Forward |
| F5 / Ctrl+R | Refresh |
| Alt+Enter | Properties |
| Alt+D / Ctrl+L | Address bar edit mode |
| Ctrl+E / Ctrl+F | Search box |
| F3 | Search (focus search UI) |
| Ctrl+Shift+N | New folder |
| Alt+P | Toggle Preview pane |
| Alt | Temporarily show Menu bar |
| F1 | Help |
| Win+E | Open Explorer at **Computer** |
| Enter | Open selected |
| App key / Shift+F10 | Context menu |

---

## 14. Properties — General tab

### 14.1 File

| Field | Editable |
|-------|----------|
| Icon + **file name** | Name via rename elsewhere; shown |
| **Type of file** | Read-only (description + extension) |
| **Opens with** + Change… | Yes — change association for type |
| **Location** | Read-only path |
| **Size** / **Size on disk** | Read-only |
| **Created** / **Modified** / **Accessed** | Read-only timestamps |
| **Attributes:** Read-only, Hidden | Checkboxes; Advanced… → Archive, Index, Compress, Encrypt (EFS — Ultimate) |
| **Unblock** | Shown for Mark-of-the-Web downloads |

Other tabs (not General): Security, Details, Previous Versions, Customize (folders), Sharing, etc.

### 14.2 Folder

| Field | Notes |
|-------|-------|
| Type | File folder |
| Location | Parent path |
| Size / Size on disk | Calculated |
| Contains | *N* files, *M* folders |
| Created | Timestamp |
| Attributes | Read-only shown as tri-state — applies to **contents**, not true folder R/O semantics (KB legacy) |

### 14.3 Drive / Computer / Library / Recycle Bin

- Drive: Used/free space pie or stats, disk cleanup, tools, hardware, sharing, security, previous versions, quota…  
- Library Properties: included locations list, Set save location, Optimize for, Show in navigation pane.  
- Recycle Bin Properties: per-drive custom size / “Don’t move files to the Recycle Bin. Remove files immediately when deleted.”

**Sources:** Herong Yang Win7 properties walkthrough; AskWoody properties; KB 326549 folder Read-only.

---

## 15. Common File Open / Save dialogs

Windows 7 uses the **Common Item Dialog** (`IFileOpenDialog` / `IFileSaveDialog`, Vista+) for modern apps; legacy `GetOpenFileName` Places Bar still appears in older apps.

### 15.1 Modern Open/Save (library-aware) structure

| Region | Contents |
|--------|----------|
| Caption | “Open” / “Save As” + close |
| Toolbar | Back/Forward, address breadcrumbs (same paradigm as Explorer), search box |
| **Navigation pane** | Favorites, Libraries, Computer, Network (aligned with Explorer) |
| Items view | Same view modes conceptually; often Details |
| Bottom | **File name** edit + **filetype filter** combo |
| Buttons | Open/Save (+ optional split verbs) · Cancel |
| Save As extras | File name prefilled; overwrite prompt; default folder / `SetSaveAsItem` |

Apps that do **not** hook/template the old dialog get Win7 UI automatically. Libraries appear as first-class browse targets; saving into a library writes to its default save location.

### 15.2 Legacy Places Bar Open/Save

Left Places: Recent Places, Desktop, Libraries/Documents, Computer, Network (customizable via GPO `ComDlg32\PlacesBar`). Not the full Explorer nav tree.

**Sources:** MSDN Common Item Dialog; Microsoft *Be Library Aware*; SuperUser Places Bar / Favorites; TechNet Explorer+Common File Dialog section.

---

## 16. Pixel / structure cheat sheet (96 DPI Aero)

| Element | Guidance |
|---------|----------|
| Command bar height | ~24–30 px content + padding (~36–40 chrome) |
| Address + search row | ~24–28 px controls |
| Back/Forward | Circular ~22–24 px diameter |
| Breadcrumb chevron hit | ~16–20 px |
| Nav pane default width | ~200 px |
| Details pane default height | ~54–72 px |
| Preview pane default width | ~256 px when enabled |
| Extra large icons | 256 |
| Large | 128 |
| Medium | 64 |
| Small / Details / List | 16 |
| Capacity bar | ~60–120 px wide × ~6–8 px thick under label in Tiles |

Exact metrics vary with DPI/theme; prefer relative layout + persisted splitter ratios.

---

## 17. Win7 Ultimate specifics (vs other SKUs / later OS)

| Topic | Ultimate |
|-------|----------|
| Desktop **Gadgets** menu item | **Yes** (Home Premium+) |
| BitLocker drive verbs | Available when feature used |
| Homegroup node | Present |
| Aero glass Explorer chrome | Default |
| Command bar (not ribbon) | **Required** |
| Libraries | Full |
| EFS “Encrypt” in Advanced attributes | Yes |
| Do **not** ship | Win8 ribbon, Quick Access, OneDrive nav root, “This PC” rename, Storage sense, modern Share charm |

---

## 18. Citations

1. Microsoft TechNet — *Windows Browse and Organize Features* (Win7): https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-7/dd744693(v=ws.10)  
2. Microsoft TechNet — *Windows Search Features* (Win7): https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-7/dd744686(v=ws.10)  
3. Microsoft TechNet — *Windows 7 Libraries: Walkthrough*: https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-7/ee449433(v=ws.10)  
4. Paul Thurrott — *Windows 7 Feature Focus: Windows Explorer* (archive): https://web.archive.org/web/20130107055320/http:/winsupersite.com/article/windows-7/windows-7-feature-focus-windows-explorer  
5. MSDN — *Common Item Dialog*: https://learn.microsoft.com/en-us/windows/win32/shell/common-file-dialog  
6. MSDN — *Creating Shortcut Menu Handlers*: https://learn.microsoft.com/en-us/windows/win32/shell/context-menu-handlers  
7. AskVG — Command bar / Organize-Layout / DesktopBackground Shell / HDD meter articles (askvg.com)  
8. How-To Geek — Desktop Gadgets/Screen resolution; library default save location  
9. Seven Forums — Favorites Links add/remove  
10. gHacks / AskVG — Navigation pane Favorites/Libraries/Homegroup/Computer/Network CLSIDs  
11. PCWorld — Explorer layout (Organize → Layout)  
12. JAWS Windows Explorer (7) Guide — address/search keyboard modes  
13. NirSoft CustomExplorerToolbar / FolderTypes GUID list  
14. SuperUser — Recycle Bin shell:RecycleBinFolder; capacity bars; Places Bar  
15. Microsoft E7 blog — desktop icons vs gadgets View options  

---

## 19. Implementer checklist (no guessing)

- [ ] Aero caption + Back/Forward + breadcrumbs + search + **command bar** (no ribbon)  
- [ ] Command bar items switch by Computer / Libraries / folder / search / Recycle Bin  
- [ ] Nav pane: Favorites, Libraries, Homegroup, Computer, Network with documented RC menus  
- [ ] Four default libraries + include folders + save location semantics  
- [ ] Breadcrumb click / sibling dropdown / edit mode (Alt+D)  
- [ ] Indexed vs grep search + Content results + filters  
- [ ] All 8 views + Details columns + sort/group + capacity bars in Tiles/Content  
- [ ] Details on, Preview off, Status off by default; sizes persist  
- [ ] Desktop RC order including **Gadgets** + Screen resolution + Personalize  
- [ ] File/folder verbs + New/ShellNew + drag-drop copy/move matrix + Delete vs Shift+Delete  
- [ ] Full keyboard matrix  
- [ ] Properties General fields  
- [ ] Common Item Open/Save with nav pane + libraries  

*End of 03-EXPLORER-DIALOGS.md*
