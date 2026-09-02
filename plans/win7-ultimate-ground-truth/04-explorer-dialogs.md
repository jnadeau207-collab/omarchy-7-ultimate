# 04 — Explorer & Common Dialogs (Win7 Ultimate)

**Repo path:** `plans/win7-ultimate-ground-truth/04-explorer-dialogs.md`  
**Research sources:** `research/03-EXPLORER-DIALOGS.md` + `.json`, `fleet-shell-win7.md` §6  
**Target phases:** Phase 6 (Files), Phase 4 (desktop context), Phase 11  
**DPI baseline:** **96 DPI / 100%**

---

## Purpose

Binding Windows 7 Ultimate Explorer chrome (command bar — **not** ribbon), navigation pane, Libraries, address/search, views, Computer/Recycle, context menus, drag-drop/delete grammar, and common dialogs so Files implementers never guess menu trees.

---

## Binding metrics (96 DPI)

| Region | Default | Approx size |
|--------|---------|-------------|
| Caption | On | See `01-window-chrome.md` — visual top **30**, `SM_CYCAPTION` **22** metric only |
| Nav: Back/Forward + Address + Search | On | — |
| Command bar (Folder Band) | On | Single horizontal strip |
| Classic Menu bar | **Off** (Alt temporary) | — |
| Navigation pane | **On** | ~**180–220 px** wide |
| Details pane | **On** | ~**48–72 px** tall |
| Preview pane | **Off** | ~**200–320 px** when enabled |
| Status bar | **Off** | — |

### View icon sizes

| View | Icon px |
|------|--------:|
| Extra Large Icons | **256** |
| Large Icons | **128** |
| Medium Icons | **64** |
| Small Icons | **16** |
| List / Details | **16** |
| Tiles | ~48–64 |
| Content | ~32–48 (default for search) |

---

## Chrome stack (top → bottom)

1. Caption  
2. Back / Forward / history chevron  
3. Address bar (breadcrumbs) + Search box  
4. **Command bar**  
5. Optional Menu bar  
6. Nav pane | Items | optional Preview  
7. Details pane  
8. Status bar (if on)

**Hard rule:** No Win8+ ribbon.

### Command bar constants (trailing)

Views (cycle + chevron/slider) · Show the preview pane · Help (?)

**Organize** leftmost. Organize dropdown: Cut, Copy, Paste, Undo, Redo | Select all | Layout ▶ | Folder and search options… | Delete, Rename, Remove properties, Properties | Close. **New folder** often separate button.

### Location matrix (no selection → typical left→right)

| Location | Commands |
|----------|----------|
| Generic folder | Organize · Include in library · Share with · Burn · New folder · Views · Preview · Help |
| Documents library | + Arrange by |
| Music | + Play all |
| Pictures | + Slide show |
| Videos | + Play all |
| Libraries root | + New library |
| **Computer** | Organize · System properties · Uninstall or change a program · Map network drive · Open Control Panel · Views · Preview · Help |
| Search results | + Save search |
| Recycle Bin | Empty the Recycle Bin · Restore… |

---

## Navigation pane (top → bottom)

1. Favorites (Desktop, Downloads, Recent Places defaults)  
2. Libraries  
3. Homegroup  
4. Computer  
5. Network  

Single-click label navigates; chevron expands. Libraries: Documents/Music/Pictures/Videos with Public+user includes; max ~50 folders; default save location.

---

## Interaction matrix

| Gesture | Result |
|---------|--------|
| Single left-click item | Select |
| Double left-click | Default verb (Open) |
| Marquee drag | Select intersecting |
| Ctrl/Shift+click | Multi-select |
| Ctrl+A | Select all |
| Same-volume drag | **Move** |
| Cross-volume drag | **Copy** (+) |
| Ctrl / Shift / Alt(+Ctrl) drag | Force Copy / Move / Shortcut |
| Right-drag release | Copy here / Move here / Create shortcuts / Cancel |
| Delete | Recycle Bin (if enabled) |
| Shift+Delete | Permanent |
| Alt+D / Ctrl+L | Address edit |
| Ctrl+E / Ctrl+F / F3 | Focus search |
| Alt+P | Toggle Preview |
| Alt+Up / Backspace | Up |
| Click crumb / ▶ sibling | Navigate / sibling dropdown |
| Ctrl+wheel | Live icon size |

### Desktop context menu (stock order)

1. View ▶  
2. Sort by ▶  
3. Refresh  
4. *sep* Paste / Paste shortcut  
5. *sep* New ▶  
6. *sep* Screen resolution  
7. Gadgets  
8. Personalize  

### File context menu (typical static order)

Open (bold) · Open with ▶ · app verbs · Share with ▶ · *sep* · Send to ▶ · Cut · Copy · *sep* · Create shortcut · Delete · Rename · *sep* · Properties  

---

## Common dialogs (summary)

- Copy/Move: determinate progress; Pause/Cancel; conflict Replace/Skip/Keep both  
- Properties: multi-tab (General / Sharing / Security / Previous Versions / Customize) — General minimum for parity prototype  
- Open/Save common dialogs: nav + views + filename + type filter  
- Commit button order: see `07-interaction-grammar.md`

---

## Win7 vs Omarchy notes

| Win7 | Omarchy Files today |
|------|---------------------|
| Command bar + Libraries + Homegroup | Prototype nav; Libraries partial |
| Rename / cut / copy / paste / column resize / open handler | Honest absences in parity — must implement per Phase 6 bindings |
| Full Properties sheets | General stub |
| Recycle Bin first-class | Phase 6; trash/restore must match UI/banner honesty |

**Anti-invent:** Do not claim Explorer `present` while workspace inspect degraded; do not invent full NTFS Security Properties; banner must not underclaim trash/restore if UI offers them.

---

## Citations

- Thurrott Explorer Feature Focus; TechNet Browse and Organize / Libraries / Search  
- AskVG command bar / desktop shell; MSDN shortcut menu handlers  
- `03-EXPLORER-DIALOGS.md/.json`, `fleet-shell-win7.md`

---

## Open metal-verify items

1. Exact Organize SubCommands separators on SP1 Ultimate.  
2. Computer command-bar labels vs localized Ultimate.  
3. Desktop Gadgets / Screen resolution presence without OEM shellex.  
4. Conflict dialog button set on SP1 vs Vista.
