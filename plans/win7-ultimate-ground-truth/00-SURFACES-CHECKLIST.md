---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# 00 — Surfaces Checklist (Win7 Ultimate behavioral / pixel specs needed)

**Companion:** `/workspace/w7-specs/out/00-DOC-INVENTORY.md`  
**Sources:** `/workspace/w7-specs/docs/` doctrine/plans + `/workspace/w7-specs/research/` packs (`fleet-*`, `01`–`06`).  
**Mark:** `[ ]` = needs full Win7 Ultimate behavioral+pixel book · `[~]` = partial prose/tokens/geometry in tree · `[x]` = out of product scope / N/A

Each surface needs: exact colors or token refs, px sizes, hit targets, L/R-click matrices, menus, hierarchy, stacking, empty/error states.

---

## A. Window chrome / Aero

- [~] SSD caption bar (hyprbars) — height/buttons/colors exist as Omarchy freeze; Win7 Aero formulas in research
- [ ] Caption button glyphs (min/max/restore/close) — normal/hot/pressed/disabled inactive
- [ ] Active vs inactive frame gradients / glass / border highlight
- [ ] Resize edge/corner hit targets
- [ ] Title-bar drag / double-click maximize exclusion vs buttons
- [ ] System (Control) menu — Restore/Move/Size/Min/Max/Close
- [~] Snap halves / quarters / maximize-hover chooser (W0 prose + research grammar)
- [ ] Aero Shake
- [~] Aero Peek / Show Desktop strip
- [~] CSD one-row fusion (Chromium/GTK exclusion list)
- [ ] Maximized vs restored shadow / border rules
- [ ] Multi-monitor maximize / snap-to-monitor edges
- [~] Reopen memory / cascade / clamp (product prose)

## B. Superbar (taskbar)

- [~] Start orb states (normal/hot/pressed/open)
- [ ] Taskbar empty-space right-click menu (Toolbars / Cascade / Show windows stacked / Show desktop / Lock / Properties)
- [~] Task button L/M/R-click matrix (activate, minimize toggle, middle-click, Jump List)
- [~] Pin / unpin / running-group grouping
- [~] Live Peek thumbnails (size, delay, offset, title-only rules)
- [~] Jump Lists structure (pinned / frequent / tasks / Close window|group)
- [ ] Jump List row height / width / separators / pin glyphs
- [~] Notification area / tray cluster order
- [ ] Notification Area Icons applet behaviors (show/hide/only notifications)
- [ ] System icons on/off (Clock, Volume, Network, Power, Action Center)
- [~] Clock + calendar flyout
- [~] Quick Settings host (tiles → writers still Phase 5)
- [~] Notification Center vs Action Center gap
- [~] Badges / progress on task buttons
- [~] Multi-monitor bar ownership (prose exists)
- [ ] Taskbar Properties tabs (Taskbar / Start Menu / Toolbars)
- [ ] Auto-hide / lock / button combine modes

## C. Start menu

- [~] Two-pane card geometry (720×640 / bar 48 / margin 8 locked)
- [ ] Left pane: pins, Recent, All programs letter groups — tile/gap/font metrics
- [ ] Search box word-wheel categories (Programs / Control Panel / Documents / Other)
- [ ] Right-pane places inventory (User / Documents / Pictures / Music / Games / Computer / Network / Connect To / Control Panel / Devices and Printers / Default Programs / Help / Run — map to Omarchy)
- [~] Power cluster (Shut down / switch / Lock / Log off / Restart / Sleep / Hibernate rules)
- [ ] Start orb right-click (Properties / Explorer / etc.)
- [~] Dismiss / click-through / owner output
- [ ] Customize Start Menu options dialog
- [~] Cross-surface Pin to Start / Pin to Taskbar consistency

## D. Desktop

- [~] Wallpaper / Personalization entry
- [ ] Icon sizes / grid / snap-to-grid / auto-arrange / align
- [ ] Label wrap / selection marquee / multi-select
- [ ] Full desktop context menu (View / Sort by / Refresh / Paste / Paste shortcut / Graphics / Personalize / …)
- [ ] New → Folder / Shortcut / … submenu
- [ ] Recycle Bin empty/full icons + Properties
- [ ] Computer / User Files desktop shortcuts
- [ ] Drag to Superbar / Start / Explorer

## E. Explorer / Files

- [~] Window chrome + nav (back/forward) — prototype
- [ ] Up button / history menu
- [~] Address bar / breadcrumb segments
- [~] Search box (in-app; not Start content search)
- [~] Command bar contextual verbs (Organize / Include in library / Share with / Burn / New folder / … by folder type)
- [ ] Organize / Share with / Include in library submenus
- [~] Navigation pane (Favorites / Libraries / Homegroup / Computer / Network)
- [ ] Libraries definitions & manage
- [~] Views: Extra large / Large / Medium / Small / List / Details / Tiles / Content
- [ ] Column chooser / resize / sort glyphs
- [ ] Details pane / Preview pane / status bar
- [~] Computer / This PC drive groups + capacity bars
- [ ] Recycle Bin folder view + restore/empty
- [ ] Network places / map network drive
- [ ] File context menu (Open / Open with / … / Properties)
- [ ] Folder background context menu
- [ ] Properties sheets (General / Sharing / Security / Previous Versions / Customize)
- [ ] Copy/Move/Delete progress + conflict/replace dialogs
- [ ] Rename in-place
- [ ] Cut / Copy / Paste / Undo
- [ ] Removable media / AutoPlay / Eject
- [ ] SMB connect / disconnect
- [ ] Folder Options applet
- [ ] Common File Open / Save dialogs
- [ ] Print dialogs

## F. Control Panel — category hubs

- [ ] Control Panel home (Category vs Large/Small icons)
- [ ] System and Security
- [ ] Network and Internet
- [ ] Hardware and Sound
- [ ] Programs
- [ ] User Accounts and Family Safety
- [ ] Appearance and Personalization
- [ ] Clock, Language, and Region
- [ ] Ease of Access
- [ ] CP search / deep task links

## G. Control Panel — All Items applets (Ultimate)

- [ ] Action Center
- [ ] Administrative Tools (folder)
- [ ] AutoPlay
- [ ] Backup and Restore
- [ ] Biometric Devices (HW)
- [ ] BitLocker Drive Encryption (Ultimate)
- [ ] Color Management
- [ ] Credential Manager
- [ ] Date and Time
- [ ] Default Programs (SPAD / associations / AutoPlay / set program access)
- [ ] Device Manager
- [ ] Devices and Printers
- [ ] Display
- [ ] Ease of Access Center
- [ ] Folder Options
- [ ] Fonts
- [ ] Getting Started / Welcome Center
- [ ] HomeGroup
- [ ] Indexing Options
- [ ] Infrared (HW)
- [ ] Internet Options
- [ ] iSCSI Initiator
- [ ] Keyboard
- [ ] Mouse
- [ ] Network and Sharing Center
- [ ] Notification Area Icons
- [ ] Parental Controls / Family Safety
- [ ] Pen and Touch (HW)
- [ ] Performance Information and Tools
- [ ] Personalization (Aero color / wallpaper / screensaver / sounds / pointers / theme)
- [ ] Phone and Modem
- [ ] Power Options (+ Advanced)
- [ ] Programs and Features
- [ ] Recovery / System Restore UI
- [ ] Region and Language
- [ ] RemoteApp and Desktop Connections
- [ ] Sound (+ Volume Mixer)
- [ ] Speech Recognition
- [ ] Sync Center
- [ ] System (Computer Name / Hardware / Advanced / System Protection / Remote)
- [ ] Tablet PC Settings (HW)
- [ ] Taskbar and Start Menu
- [ ] Troubleshooting
- [ ] User Accounts
- [ ] Windows Defender
- [ ] Windows Firewall
- [ ] Windows Mobility Center (laptop)
- [ ] Windows Update
- [x] Desktop Gadgets (deprecated — N/A)
- [x] Windows Anytime Upgrade / CardSpace (N/A)

## H. Settings app (Omarchy Phase 5 mapping)

- [~] Settings shell chrome / nav / search
- [~] Display (inspect; writers missing)
- [~] Sound
- [~] Network
- [~] Bluetooth
- [~] Power
- [~] Personalization (image picker host)
- [~] Apps / defaults (inspect; set path thin)
- [~] Input / keyboard layout
- [ ] Accessibility (honest missing page)
- [~] Update / Recovery inspect
- [ ] System Information
- [ ] Region / full locale
- [ ] Apply / OK / Cancel / live-preview / elevation chrome for writers

## I. Administration / MMC-class (Phase 9)

- [ ] Task Manager (Applications / Processes / Services / Performance / Networking / Users)
- [ ] Resource Monitor
- [ ] Services
- [ ] Task Scheduler
- [ ] Event Viewer
- [ ] Disk Management / Storage
- [ ] Computer Management tree
- [ ] Local Users and Groups
- [ ] Device Manager (tree UI)
- [ ] Firewall advanced UI
- [ ] Backup product UI vs snapshots honesty
- [ ] Troubleshooting Center
- [ ] Firmware / recovery tools UI

## J. Dialogs / system UI / polish

- [~] Semantic Operation / Destructive dialogs (kit exists; Win7 task-dialog map thin)
- [ ] UAC / polkit elevation chrome
- [~] OSD volume / brightness
- [~] Lock / logon / unlock
- [ ] Security options (Ctrl+Alt+Del analogues)
- [ ] Balloon notifications vs toasts
- [ ] Focus rings / hover/press tables for every chrome control
- [ ] Empty states / error sheets / DPI 100/125/150/200 crop rules
- [ ] Reduced motion replacements for Aero transitions
- [ ] Cursors / sounds theme tables (research pack exists)

## K. Later product surfaces

- [ ] Software Center (install/uninstall/trust badges)
- [ ] Compatibility Center (.exe routing)
- [ ] Agent Center full IA (beyond inspect host)
- [ ] Games / Proton surface
- [ ] Remote Desktop client
- [ ] Drive encryption UX
- [ ] OOBE / first-boot screens
- [ ] Migration wizard
- [ ] Privacy settings (doctrine-shaped screens)

## L. Global interaction grammar (cross-cutting)

- [~] Mouse grammar (L/R/M, drag, wheel) — fleet-shell pack
- [ ] Right-click everywhere completeness audit
- [ ] Stacking / z-order doctrine (Start, Peek, Jump List, QS, NC, lock, OSD, snap chooser)
- [ ] Win hotkey accelerators vs visible affordances map
- [ ] Progressive disclosure Advanced paths

---

## Research pack index (already on box)

| Pack | Use for |
|------|---------|
| `research/fleet-aero-win7.md` / `01-WINDOW-CHROME.*` | Caption/glass/snap/shake/peek pixels |
| `research/fleet-chrome-win7.md` | Omarchy freeze vs Win7 chrome |
| `research/fleet-shell-win7.md` / `02-START-SUPERBAR.*` | Start, Superbar, Jump Lists, tray, command bar |
| `research/03-EXPLORER-DIALOGS.*` | Explorer/dialogs matrices |
| `research/fleet-catalog-controlpanel.md` / `04-CONTROL-PANEL.*` | Full CP applet inventory |
| `research/05-INTERACTION-POLISH.*` | Menus/dialogs/DPI/sounds/cursors |
| `research/06-SETTINGS-ADMIN-MEDIA.*` | Personalization, defaults, admin, media |
| `research/fleet-doctrine-gaps.md` | Phase vagueness → required behaviors |

