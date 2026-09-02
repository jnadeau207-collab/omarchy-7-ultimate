---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# Fleet research pack — Win7 Ultimate shell surfaces

**Audience:** Lead / plan synthesizers (not Jesse-facing).
**Scope:** Windows 7 Ultimate (retail US English) ground truth for:
Start menu, Superbar/taskbar, Jump Lists, notification area (tray), Show Desktop / Aero Peek strip, Explorer command bar.
**Authority:** Win7 Ultimate muscle-memory / IA / interaction grammar for Omarchy Desktop Mode binding specs. Not an Omarchy implementation status report.
**Locale:** Labels below are **en-US** as shipped on Windows 7 Ultimate. Other languages use the same IA with localized strings.
**Sources:** Microsoft Learn / MSDN taskbar & Jump List APIs; Win7 Taskbar and Start Menu Properties UI; Explorer `CommandStore` / FolderTypes task strings; contemporary Win7 how-tos that quote stock verbs. Flag any contested label as `(verify on metal)`.

---

## 0. Global mouse grammar (shell)

| Action | Result (default) |
|---|---|
| Left-click | Activate / open / select primary verb |
| Left-click + drag | Reorder taskbar buttons (when unlocked); drag Start/taskbar items to pin |
| Double left-click | Open (desktop icons, Explorer items) |
| Right-click | Context / Jump List / properties menu for that chrome piece |
| Middle-click (taskbar button) | Open a **new** instance of the app (if the app supports it) |
| Hover (taskbar button, Aero on) | Live thumbnail preview(s); may show thumbnail toolbar |
| Hover (Show Desktop strip) | Aero Peek: glass all windows to reveal desktop (if enabled) |
| Win key | Toggle Start |
| Win+T | Focus taskbar buttons; arrows cycle; Enter activates |
| Win+B | Focus notification area |
| Win+Space (hold) | Peek desktop (Win7) |
| Win+D | Show Desktop (minimize/restore all) |
| Win+M / Win+Shift+M | Minimize all / undo |
| Ctrl+Shift+Esc | Task Manager |
| Win+Pause | System properties |

---

## 1. Start menu

### 1.1 Layout (two-pane)

| Region | Contents |
|---|---|
| **Left pane — pinned** | User-pinned programs (top of left column, above separator) |
| **Left pane — recent / MFU** | Most frequently used programs (count configurable) |
| **All Programs** | Link at bottom of left pane; replaces left list with hierarchical All Programs tree; **Back** returns |
| **Search box** | Bottom of left pane; word-wheel search (programs, Control Panel items, files, libraries as indexed) |
| **Right pane — places** | User profile header + configurable place links (see 1.3) |
| **Power cluster** | Primary power button + chevron flyout (see 1.4) |

Default approximate size: tall two-column menu; Exact pixel chrome is theme-dependent — match **IA and hit targets**, not Aero glass.

### 1.2 Left-pane item — click matrix

| Target | Left-click | Right-click (typical Jump List / shortcut menu) |
|---|---|---|
| Pinned or MFU program | Launch | Jump List if the app publishes one; else classic shortcut menu |
| Program with Jump List caret | Left on row = launch; left on caret = open destinations | Same Jump List as taskbar (destinations + tasks + pin/unpin) |
| **All Programs** | Enter All Programs view | — |
| Folder under All Programs | Expand / navigate | Open / Explore / Search / … (shell folder menu) |
| Search result — program | Launch | Pin to Taskbar / Pin to Start Menu / Run as administrator / … |
| Search result — Control Panel | Open applet | Open |
| Search result — document | Open with registered handler | Open / Open with / … |

**Stock right-click verbs on a Start program entry** (when Jump List not used / classic):

- **Open**
- **Run as administrator** (executables; UAC)
- **Pin to Taskbar** / **Unpin from Taskbar**
- **Pin to Start Menu** / **Unpin from Start Menu**
- **Remove from this list** (MFU only — clears frequency)
- **Properties**

### 1.3 Right-pane places (Customize Start Menu inventory)

Default-visible and optional links (each may be **Display as a link**, **Display as a menu**, or **Don't display** in Customize):

| Label (en-US) | Notes |
|---|---|
| **\<User name\>** | Profile root; often opens user folder |
| **Documents** | Libraries\Documents or user Documents |
| **Pictures** | |
| **Music** | |
| **Games** | Optional; Games Explorer |
| **Computer** | This PC / Computer |
| **Control Panel** | Link or menu of applets |
| **Devices and Printers** | |
| **Default Programs** | |
| **Help and Support** | |
| **Devices** / **Network** | Optional via Customize |
| **HomeGroup** | Optional |
| **Downloads** | Optional |
| **Recorded TV** | Optional (Media Center SKUs / features) |
| **Recent Items** | Optional |
| **Connect To** | Optional |
| **Run** | Optional |
| **Administrative Tools** | Optional link or menu |

**Right-click on a right-pane place link:** typically **Open**, **Explore**, **Open in new window**, **Properties** (folder places); some are fixed verbs only.

**Right-click Start orb (taskbar Start button):**

- **Open Windows Explorer** (user profile / Explorer)
- **Properties** → **Taskbar and Start Menu Properties** (Start Menu tab)

### 1.4 Power cluster

| Control | Left-click |
|---|---|
| Primary button (default label **Shut down**) | Performs configured power action |
| Chevron / arrow beside primary | Flyout menu |

**Power flyout items (en-US):**

1. **Switch user**
2. **Log off**
3. **Lock**
4. **Restart**
5. **Sleep**
6. **Hibernate** (if enabled in power policy / disk)

Primary button action is configurable: Shut down / Sleep / Hibernate / Restart / Switch user / Log off / Lock (`Taskbar and Start Menu Properties` → Start Menu → **Power button action**).

**Right-click primary Shut down button:** **Properties** (opens same Taskbar and Start Menu Properties power action control) `(verify on metal)`.

### 1.5 Search box behavior

- Filters as you type; categories include **Programs**, **Control Panel**, **Documents**, **Other** (indexed).
- Arrow keys move selection; Enter launches.
- Esc clears / closes depending on focus.
- Does **not** require separate Search UI chrome in Win7 Start (box is inline).

---

## 2. Superbar / taskbar

### 2.1 Regions (left → right, bottom bar default)

1. **Start orb**
2. **Pinned + running task buttons** (combinable)
3. **Optional toolbars** (Address, Links, Desktop, custom, Tablet PC Input, etc.)
4. **Notification area** (system tray) + clock
5. **Show Desktop** peek strip (far end)

### 2.2 Taskbar empty-space — right-click menu

Exact stock order (en-US):

1. **Toolbars** ▸
   - **Address**
   - **Links**
   - **Tablet PC Input Panel** (hardware-dependent)
   - **Desktop**
   - **New toolbar…**
2. **Cascade windows**
3. **Show windows stacked**
4. **Show windows side by side**
5. **Show the desktop**
6. **Start Task Manager**
7. **Lock the taskbar** (checkable)
8. **Properties**

### 2.3 Task button — left / middle / right

| Input | Single window | Multiple windows in group |
|---|---|---|
| Left-click | Activate / restore / minimize toggle | Cycle / show group list or last active (grouping mode dependent) |
| Middle-click | New instance | New instance |
| Hover (Aero) | Thumbnail peek; close × on thumbnail | Multiple thumbnails |
| Right-click | **Jump List** (see §3) | Jump List for the AppUserModelID |

**Taskbar button grouping modes** (`Taskbar buttons` combo):

- **Always combine, hide labels**
- **Combine when taskbar is full**
- **Never combine**

### 2.4 Taskbar Properties — Taskbar tab (labels)

- ☐ **Lock the taskbar**
- ☐ **Auto-hide the taskbar**
- ☐ **Use small icons**
- **Taskbar location on screen:** Bottom / Left / Right / Top
- **Taskbar buttons:** (combine modes above)
- **Notification area:** **Customize…**
- ☐ **Use Aero Peek to preview the desktop**
- **Restore Defaults** (where shown)

### 2.5 Pinning

| From | How |
|---|---|
| Running app | Right-click → **Pin this program to taskbar** |
| Start / All Programs | Right-click → **Pin to Taskbar** |
| Drag `.lnk` / executable onto taskbar | Pin |
| Unpin | Right-click → **Unpin this program from taskbar** |

Pinned order is user-draggable when taskbar unlocked.

### 2.6 Multi-monitor (Win7 Ultimate with Extended Desktop)

- Taskbar by default on **primary** only unless third-party; stock Win7 does **not** put a full taskbar on every monitor.
- Show Desktop / Peek act on the desktop of the focused topology; implementers must not invent Win10/11 per-monitor taskbars as Win7 truth.

---

## 3. Jump Lists

### 3.1 Structure (top → bottom, typical)

1. **Pinned destinations** (user-pinned documents)
2. **Recent** and/or **Frequent** destinations (shell-managed)
3. **Custom categories** (app-defined via `ICustomDestinationList`)
4. **Tasks** (app-defined `IShellLink` tasks; may include separators)
5. **Common chrome tasks** (shell-provided):
   - **Pin this program to taskbar** / **Unpin this program from taskbar**
   - **Close window** / **Close all windows** (wording depends on count)
6. Destination item right-click inside list: **Open**, **Pin to this list** / **Unpin from this list**, **Remove from this list**

### 3.2 Destination vs task

| Kind | Representation | Typical use |
|---|---|---|
| Destination | `IShellItem` (document/folder) | Recent files, pinned files |
| Task | `IShellLink` (+ `PKEY_Title`) | “New message”, verb launchers |
| Separator | Blank `IShellLink` + `System.AppUserModel.IsDestListSeparator` | Visual break in Tasks |

### 3.3 Explorer (Windows Explorer) Jump List specifics

- May show **Frequent** folders / libraries.
- Folders added via recent docs APIs appear for Explorer’s AppUserModelID.
- Tasks often include known Explorer entry points (e.g. open Computer) when registered `(verify on metal for exact task titles)`.

### 3.4 Start menu Jump Lists

Same destination/task model when the left-pane entry shows a cascade caret; pinning destinations works from either Start or taskbar list.

### 3.5 User removal rule

If the user **Remove from this list**, apps must honor the removed collection from `ICustomDestinationList::BeginList` or the next Jump List transaction fails. Spec implementers: do not re-add removed destinations silently.

---

## 4. Notification area (system tray)

### 4.1 Layout

- **Hidden icons** flyout: chevron / arrow (**Show hidden icons**)
- **Visible notification icons** (apps)
- **System icons** (stock set)
- **Clock** (date/time; optional day/date)

### 4.2 System icons (Turn system icons on or off)

| Icon | Default role |
|---|---|
| **Action Center** | Maintenance / security notifications |
| **Network** | Network & Sharing / Wi-Fi / status |
| **Volume** | Mixer / playback device |
| **Windows Explorer** / Power (battery) | Power Options (portables) |
| **Clock** | Date and Time |

Each: **On** / **Off**.

### 4.3 Per-icon behaviors (Customize notification icons)

For each application icon:

- **Show icon and notifications**
- **Hide icon and notifications**
- **Only show notifications**

Also: ☐ **Always show all icons and notifications on the taskbar**; **Restore default icon behaviors**.

### 4.4 Click matrix (typical)

| Target | Left-click | Right-click | Hover |
|---|---|---|---|
| Volume | Mixer / volume flyout | Playback devices / Open Volume Mixer / … | Tooltip level |
| Network | View Available Networks / Network flyer | Network and Sharing Center / Troubleshoot … | Status |
| Action Center | Open Action Center | Open / Troubleshoot … | Summary |
| Clock | Calendar flyout | Adjust date/time / Change calendar settings | Date |
| App tray icon | App-defined (often main window) | App-defined menu | Tooltip |
| Overflow chevron | Open overflow panel | — | — |
| Overflow **Customize…** | Open Notification Area Icons CPL | — | — |

### 4.5 Balloon notifications

- Appear above tray; click can activate app; **X** dismisses.
- Quiet time / NIIF flags exist for developers; users experience Action Center aggregation on Win7.

---

## 5. Show Desktop / Aero Peek strip

### 5.1 Affordance

- Narrow vertical/horizontal **hot strip** at the **far end** of the taskbar (opposite Start).
- Tooltip: **Show desktop** (en-US).

### 5.2 Interaction matrix

| Input | Aero Peek enabled | Aero Peek disabled / non-Aero |
|---|---|---|
| Hover | Temporarily glass/peek all windows to desktop | No peek (or inert hover) |
| Left-click | Toggle Show Desktop (minimize all ↔ restore) | Same Show Desktop toggle |
| Right-click | **Peek at desktop** (checkable, syncs with Properties) `(verify)`; may mirror Properties peek checkbox | Same / Properties |

Also available from taskbar empty-space menu: **Show the desktop**.

Keyboard: **Win+D** (toggle), **Win+Space** (peek while held), **Win+M**.

### 5.3 Peek vs Show Desktop

| Mode | Windows state |
|---|---|
| Peek (hover) | Temporary; release mouse restores |
| Show Desktop (click / Win+D) | Sticky minimize-all until toggled |

Live **thumbnail peek** on task buttons is separate from the Show Desktop strip (both branded Aero Peek in marketing).

---

## 6. Explorer command bar (folder band)

### 6.1 Chrome around the command bar (context)

Typical Explorer window top → bottom:

1. Caption / frame
2. **Back** / **Forward** / **Recent history** chevron
3. **Address bar** (breadcrumb)
4. **Search box** (folder-scoped)
5. **Command bar** (this section)
6. Optional **menu bar** (Alt; hidden by default)
7. **Navigation pane** | **Contents** | optional **Details** / **Preview** panes
8. **Status bar**

### 6.2 Command bar — behavior rules

- Buttons are **contextual**: depend on folder type (Generic, Library, Computer, Control Panel, Recycle Bin, Search results, …) and whether items are selected (`TasksNoItemsSelected` vs `TasksItemsSelected`).
- **New folder** commonly pinned toward the end of the bar for filesystem folders.
- Overflow: if width is insufficient, commands collapse into overflow / **Organize** menus rather than wrapping endlessly.

### 6.3 Stock command verbs (canonical names → en-US labels)

From Explorer `CommandStore` (implementers bind **behavior** to these jobs; MUIVerb may differ slightly by build):

| Canonical / store name | Typical UI label |
|---|---|
| `Windows.Organize` | **Organize** ▸ (submenu: layout, folder options, …) |
| `Windows.IncludeInLibrary` | **Include in library** ▸ |
| `Windows.Share` / Share with | **Share with** ▸ |
| `Windows.NewFolder` | **New folder** |
| `Windows.Burn` | **Burn** |
| `Windows.Print` | **Print** |
| `Windows.Email` | **E-mail** |
| `Windows.Slideshow` | **Slide show** (Pictures) |
| `Windows.Properties` | **Properties** |
| `Windows.Delete` | **Delete** |
| `Windows.Rename` | **Rename** |
| `Windows.Cut` / `Copy` / `Paste` | **Cut** / **Copy** / **Paste** (not all visible by default) |
| `Windows.SelectAll` | **Select all** |
| `Windows.Undo` / `Redo` | **Undo** / **Redo** |
| `Windows.PreviewPane` / `ReadingPane` / `NavPane` / `LibraryPane` | Pane toggles under Organize / layout |
| `Windows.FolderOptions` | **Folder options** |
| `Windows.CloseWindow` | **Close** |

### 6.4 Matrices by view (no selection → with selection)

#### Generic filesystem folder

| Selection | Typical visible commands |
|---|---|
| None | **Organize**, **Include in library**, **Share with**, **Burn**, **New folder** |
| Files selected | **Organize**, **Share with**, **Burn**, plus open/print/email as applicable; **Properties** |
| Folders selected | **Organize**, **Include in library**, **Share with**, **Burn**, **Properties** |

#### Documents / Music / Pictures / Videos **library**

| Selection | Typical visible commands |
|---|---|
| None | **Organize**, **Include in library** (manage), **Share with**, view-specific (**Slide show** in Pictures), **Burn**, **New folder** |
| Items selected | Share / Burn / Print / Preview-oriented verbs; **Properties** |

#### Computer

| Selection | Typical visible commands |
|---|---|
| None | **Organize**, system affordances (e.g. **Properties** / system tasks) `(verify exact set on Ultimate)` |
| Drive selected | **Organize**, **Properties**, **Share with** / system verbs; AutoPlay-related when applicable |

#### Recycle Bin

| Selection | Typical visible commands |
|---|---|
| None | **Organize**, **Empty the Recycle Bin**, **Restore all items** |
| Items selected | **Organize**, **Restore this item** / **Restore**, **Delete** (permanent), **Properties** |

#### Control Panel / virtual views

Command bar swaps to CPL-oriented tasks (**Organize** still present; applet-specific tasks). Do not invent filesystem **New folder** on pure CPL hubs.

### 6.5 Organize submenu (high-traffic)

Typical entries:

- **Cut** / **Copy** / **Paste** / **Undo** / **Redo** / **Select all**
- **Layout** ▸ Menu bar, Details pane, Preview pane, Navigation pane
- **Folder and search options**
- **Properties** (of current folder)

### 6.6 Share with submenu (typical)

- **Nobody**
- Homegroup read / read-write options (when Homegroup exists)
- **Specific people…**

### 6.7 Include in library submenu

- Documents / Music / Pictures / Videos / **Create new library**

### 6.8 Address bar & navigation (related, not command bar)

| Control | Left-click | Right-click |
|---|---|---|
| Breadcrumb segment | Navigate there | Open / Open in new window / Copy address |
| Empty address space / full path mode | Edit path | Paste / Copy address |
| Back / Forward | History nav | Drop-down history list |
| Up (when shown) | Parent folder | — |

### 6.9 Explorer content pane — right-click (baseline verbs)

**Empty background:** View ▸, Sort by ▸, Group by ▸, **Refresh**, **Paste**, **Paste shortcut**, **New** ▸, **Properties**.

**File:** Open, Open with ▸, Send to ▸, Cut, Copy, Delete, Rename, Properties (+ provider verbs).

**Folder:** Open, Open in new window, Include in library ▸, Share with ▸, Send to ▸, Cut, Copy, Delete, Rename, Properties.

Exact order is shell + extension-dependent; Omarchy specs should lock the **stock Microsoft set** first, then extension verbs as non-blocking.

---

## 7. Cross-surface pin / jump consistency

| Surface | Pin to Start | Pin to Taskbar | Jump List destinations |
|---|---|---|---|
| Start left pane | Unpin / Pin | Pin to Taskbar | Yes if app supports |
| Taskbar button | — | Unpin | Yes |
| Explorer `.lnk` | Available via context | Available via context | N/A |

**Close group** vs **Close window**: Jump List shows the plural form when multiple windows share the AppUserModelID.

---

## 8. Acceptance hooks for Omarchy binding specs

When expanding `plans/win7-ultimate-ground-truth/`:

1. **Start** — two-pane IA; power flyout exact six items; Customize inventory as optional display modes; search word-wheel.
2. **Superbar** — empty-space menu order (§2.2); combine modes; pin/unpin verbs; no fake per-monitor taskbars as Win7 truth.
3. **Jump Lists** — destinations vs tasks vs shell pin/close; honor Remove from this list.
4. **Tray** — Customize + system icon on/off; overflow chevron.
5. **Show Desktop strip** — hover peek vs click sticky; tooltip **Show desktop**.
6. **Explorer command bar** — contextual matrices (§6.4); Organize / Share with / Include in library / New folder as first-class jobs.

Mark every Omarchy deviation explicitly (doctrine: match jobs/menus/hit targets; glass may differ).

---

## 9. Explicit non-goals (this pack)

- Full Control Panel applet trees (separate fleet pack).
- Desktop icon canvas menus (separate pack; only referenced where taskbar Show Desktop interacts).
- Win8/10/11 Start / taskbar changes (not authority).
- Omarchy current prototype honesty (see `WINDOWS_7_ULTIMATE_PARITY.md` for product state).

---

## 10. Open verify-on-metal checklist

- [ ] Exact Show Desktop strip **right-click** menu strings on en-US Ultimate
- [ ] Explorer **Computer** command bar with no selection
- [ ] Whether **Close all windows** vs **Close window** pluralization thresholds
- [ ] Start orb right-click full menu on Ultimate vs OEM skins
- [ ] Power flyout: Hibernate visibility rules when hybrid sleep enabled

---

*Pack ID: `fleet-shell-win7` — written for Lead synthesis into `plans/win7-ultimate-ground-truth/`.*
