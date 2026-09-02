---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# 06 — Settings, Administration, Default Programs, Media (Windows 7 Ultimate)

**Scope:** Exhaustive Win7 Ultimate UI/interaction reference for Omarchy Project Ultimate Desktop Mode muscle memory. Covers Personalization/Settings analogs, Default Programs, Administration (MMC), and Media (Sound / Volume Mixer / WMP 12).

**Authority:** `docs/project-ultimate.md` phases + `docs/WINDOWS_7_ULTIMATE_PARITY.md` jobs. Implementers must not invent Win10/11 Settings, redesigned Task Manager, or Win11 Default apps UX.

**Edition:** Windows 7 Ultimate (Aero available; Local Users and Groups present; Local Security Policy / Group Policy present; BitLocker present as product feature — not required for these surfaces).

**Contamination ban:** No Windows 10/11 Start Settings pages, no Win8/10 Task Manager Process/App grouping redesign, no “Default apps” modern Settings, no Win11 volume flyout as the primary model. Win7 Control Panel / MMC / tray chrome only.

---

## Phase mapping (Omarchy)

| Win7 area | Plan phase | Parity jobs | Fabric / product notes |
|-----------|------------|-------------|------------------------|
| Personalization (theme, wallpaper, color, sounds, screensaver, pointers) | **Phase 5 — Settings** | Personalization, Sound (scheme), Desktop (wallpaper) | Phase 5 exit criteria still open. Live host today: Settings → Personalization image picker prototype. Typed Personalization writers remain unavailable. |
| Display / Sound / Power / Input / Accessibility / System | **Phase 5 — Settings** | Display, Sound, Power Options, Language/locale, Accessibility, System | Phase 5 exit criteria still open. Live Settings writers today: volume (`audio.volume.set`), Wi-Fi radio (`network.manage`), brightness (`display.brightness.set`), input layout (`input.keyboard-layout.set`). Settings Power LIVE refused (inspect only). Accessibility panel missing as product. System information aggregate missing. |
| Default Programs + file/protocol associations | **Phase 5** Apps/defaults + **Phase 6** MIME defaults | Default Programs, File associations | Phase 5/6 exit criteria still open. Live host today: Settings → Apps `defaults.inspect` + `defaults.protocol.set` (browser LIVE only). `files.associations.set` stays missing/planned MIME. Do not invent MIME UI. |
| AutoPlay / removable media handlers | **Phase 6** Files and defaults | Removable media (Files phase); Default Programs | AutoPlay is a Default Programs child in Win7 |
| Administration MMC / Task Manager / Device Manager / Disk / Services / Scheduler / Event Viewer | **Phase 9 — Administration** | Task Manager, Device Manager, Disk Management, Services, Task Scheduler, Event/history, User Accounts | Phase 9 exit criteria still open. Live Administration inspect hosts today: Processes (`process.inspect` + unauthorized End Task path), Services, Device Manager, Storage, Printers and scanners, Backup, Scheduled tasks, Troubleshooting, Firewall, User accounts. Inspect inventory ≠ product MMC present. No start/stop service LIVE, no Device Manager present, no Task Manager present, no Event Viewer present, no `firewall.manage` / `backup.manage` LIVE. Win7 MMC tables below stay reference. Do not invent Settings pages for these. |
| Volume Mixer + Sound applet | **Phase 5 — Settings** (Sound) + Superbar tray | Sound | Phase 5 exit criteria still open. Live host today: Settings → Sound `audio.inspect` + `audio.volume.set`. Per-app mixer remains tray muscle memory, not a product mixer present. |
| Windows Media Player 12 chrome (parity behaviors) | **Phase 5** defaults + **Phase 7** Software surface (media player as product app) | Default Programs (media player), Context menus / Superbar peeks | WMP is the Win7 default media chrome reference — not a clone mandate. Software Center missing as product. |

User brief cited phases 5/7/8/9; plan ownership above is authoritative. Phase 8 (Compatibility Center) is out of scope except that Default Programs / AutoPlay must remain the human path for “which program opens this,” not Wine framing.

**Product honesty (not Win7 reference):** Phase 5 and Phase 9 exit criteria still open. Live hosts today are the Settings writers and Administration inspect routes named in the table. Inspect inventory ≠ product MMC present. Do not treat Win7 MMC / Default Programs / Task Manager tables below as product-present. Product remains REJECTED.

---

## 1. Personalization hub (Win7)

### 1.1 Entry paths

| Action | Result |
|--------|--------|
| Desktop empty area → right-click → **Personalize** | Opens Personalization Control Panel |
| Control Panel → Appearance and Personalization → **Personalization** | Same |
| Control Panel (icons) → **Personalization** | Same |
| Start search: `personalization`, `theme`, `desktop background` | Jump to Personalization or child pages |

### 1.2 Personalization chrome (layout)

Bottom row of four theme-component links (exact Win7 labels):

1. **Desktop Background**
2. **Window Color** (opens Window Color and Appearance when Aero theme active)
3. **Sounds**
4. **Screen Saver**

Left nav / related tasks (typical Ultimate):

- Change desktop icons
- Change mouse pointers
- Change your account picture
- Display (link out)
- Ease of Access Center (link out)

Theme gallery groups:

- **My Themes** (unsaved / custom / downloaded)
- **Aero Themes** (Ultimate)
- **Basic and High Contrast Themes**

Selecting a theme applies wallpaper + window color + sounds (+ optional screensaver / pointers / icons) as a pack. Saving: right-click theme → **Save theme** / **Save theme for sharing** → `.theme` / `.themepack`.

### 1.3 Window Color and Appearance (Aero path)

**When:** Current theme uses Aero visual style (`Aero.msstyles`).

**Controls:**

| Control | Behavior |
|---------|----------|
| Color swatches | Preset glass colors for window borders, Start, Taskbar |
| **Show color mixer** | Reveals Hue / Saturation / Brightness |
| **Enable transparency** | Checkbox; clear = Aero glass without translucency (“Aero sans trans”) |
| **Color intensity** | Slider; right = darker / less transparent |
| **Advanced appearance settings…** | Opens classic Window Color and Appearance dialog |

Link at bottom: **Advanced appearance settings**.

### 1.4 Advanced appearance (classic dialog)

Applies primarily to **Basic / Classic / High Contrast** themes. Under Aero, most Item colors are ignored; sizes/fonts that still apply are limited (menus, message box, etc. — theme settings trump most items).

**Dialog title:** Window Color and Appearance

**Preview:** Sample Active Window / Inactive Window / Message Box / Menu / etc. Click sample to select Item.

**Item dropdown (Win7 list — implement all):**

| Item | Typical editable fields |
|------|-------------------------|
| 3D Objects | Color |
| Active Title Bar | Size, Color 1, Color 2 (gradient), Font, Font size, Font color, Bold/Italic |
| Active Window Border | Size, Color |
| Application Background | Color |
| Border Padding | Size |
| Caption Buttons | Size |
| Desktop | Color (Basic/Classic) |
| Disabled Item | Font color |
| Hyperlink | Color |
| Icon | Size, Font, Font size, Font color |
| Icon Spacing (Horizontal) | Size |
| Icon Spacing (Vertical) | Size |
| Inactive Title Bar | Size, Color 1, Color 2, Font (shared rules with Active for font face/size bold/italic) |
| Inactive Window Border | Size, Color |
| Menu | Size, Color, Font, Font size, Font color |
| Message Box | Font, Font size, Font color |
| Palette Title | Size, Font, Font size |
| Scrollbar | Size |
| Selected Items | Size, Color, Font, Font size, Font color |
| ToolTip | Color, Font, Font size, Font color |
| Window | Color, Font color (affects “automatic” text in some apps) |

**Interaction rules:**

- Active Title Bar Color 1 → left; Color 2 → right (gradient).
- Same font/size required for Active and Inactive Title Bar; Bold/Italic apply to both.
- Color picker: Basic colors → **Other…** → custom RGB/HSL.
- OK / Cancel / Apply.

### 1.5 Desktop Background

| Control | Win7 behavior |
|---------|---------------|
| **Picture location** | Dropdown: Windows Desktop Backgrounds, Pictures Library, Top Rated Photos, Solid Colors, or Browse… |
| Thumbnail grid | Multi-select; >1 image enables slideshow |
| **Picture position** | **Fill** / **Fit** / **Stretch** / **Tile** / **Center** |
| **Change picture every** | 10 seconds … 1 day (when ≥2 pictures) |
| **Shuffle** | Checkbox |
| Battery note (laptops) | Pause slideshow on battery via power plan advanced setting |
| Buttons | **Save changes** / **Cancel** |

**WallpaperStyle registry / .theme mapping (do not invent):**

| UI | TileWallpaper | WallpaperStyle |
|----|---------------|----------------|
| Center | 0 | 0 |
| Tile | 1 | 0 |
| Stretch | 0 | 2 |
| Fit | 0 | 6 |
| Fill | 0 | 10 |

Supported image types: `.bmp`, `.gif`, `.jpg`/`.jpeg`, `.png`, `.tif` (and dib per themepack).

Slideshow unavailable on Starter / Home Basic — **available on Ultimate**.

### 1.6 Screen Saver Settings

Entry: Personalization → **Screen Saver**.

| Control | Behavior |
|---------|----------|
| Screen saver dropdown | None, Bubbles, Mystify, Ribbons, Photos, 3D Text, blank, OEM… |
| **Settings…** | Per-saver options |
| **Preview** | Full-screen preview; Esc / mouse ends |
| **Wait** | Minutes of idle before start |
| **On resume, display logon screen** | Checkbox (secure desktop) |
| Power management link | → Change plan settings / power options |

`.theme` `[boot]` section: `SCRNSAVE.EXE=path\to\file.scr`.

### 1.7 Sounds (from Personalization)

Opens **Sound** dialog on **Sounds** tab (same `mmsys.cpl`). See §4.

### 1.8 Mouse Pointers

Personalization → **Change mouse pointers** → Mouse Properties **Pointers** tab.

| Control | Behavior |
|---------|----------|
| Scheme | Windows Aero, Windows Standard, Magnified, Inverted, Extra Large, custom saved schemes |
| Customize list | Arrow, Help Select, Working In Background, Busy, Precision Select, Text Select, Handwriting, Unavailable, Vertical/Horizontal/Diagonal Resize, Move, Alternate Select, Link Select, etc. |
| Browse… | `.cur` / `.ani` |
| Enable pointer shadow | Checkbox |
| Use Default | Reset one entry |
| Save As… | Save scheme |

`.theme` section `[Control Panel\Cursors]` keys: Arrow, Help, AppStarting, Wait, NWPen, No, SizeNS, SizeWE, Crosshair, IBeam, SizeNWSE, SizeNESW, SizeAll, UpArrow, DefaultValue, Hand/Link.

### 1.9 Theme package structure

#### `.theme` (INI text)

**Required for gallery recognition:** `[Control Panel\Desktop]`, `[VisualStyles]`, `[MasterThemeSelector]` with `MTSM=DABJDKT`.

| Section | Purpose |
|---------|---------|
| `[Theme]` | DisplayName, BrandImage (PNG 80×240), desktop icon CLSIDs |
| `[Control Panel\Colors]` | Classic RGB triples (avoid overriding under Aero) |
| `[Control Panel\Cursors]` | Cursor paths |
| `[Control Panel\Desktop]` | Wallpaper, TileWallpaper, WallpaperStyle, Pattern, ScreenSaveActive |
| `[Slideshow]` | Interval (ms), Shuffle, ImagesRootPath **or** RSSFeed, ItemNPath |
| `[Metrics]` / WindowMetrics | Binary NONCLIENTMETRICS / ICONMETRICS |
| `[VisualStyles]` | Path to `.msstyles`, ColorStyle, Size, ColorizationColor, Transparency, Composition |
| `[Sounds]` / `[AppEvents\…]` | SchemeName or per-event `.wav` |
| `[boot]` | SCRNSAVE.EXE |
| `[MasterThemeSelector]` | MTSM=DABJDKT |

Default desktop icon CLSIDs (Win7):

- Computer `{20D04FE0-3AEA-1069-A2D8-08002B30309D}`
- Documents `{59031A47-3F72-44A7-89C5-5595FE6B30EE}`
- Network `{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}`
- Recycle Bin `{645FF040-5081-101B-9F08-00AA002F954E}` (Full/Empty)

#### `.themepack`

CAB containing `.theme` + assets. Supported: `.theme`, images, `.wav`, `.cur`/`.ani`, `.ico`, brand `.png`. Wallpapers extract under `DesktopBackground\`. User creates via Personalization → Save theme for sharing.

Install locations:

- System: `%WinDir%\Resources\Themes`
- User: `%LOCALAPPDATA%\Microsoft\Windows\Themes`

---

## 2. Default Programs (critical)

### 2.1 Hub — exact four links

**Title:** Default Programs  
**Subtitle (sud.dll):** *Choose which programs you want Windows to use for activities like web browsing, editing photos, sending e-mail, and playing music.*

**Exact four links + descriptions (from `sud.dll` Win7 strings):**

| # | Link label | Description |
|---|------------|-------------|
| 1 | **Set your default programs** | Make a program the default for all file types and protocols it can open. |
| 2 | **Associate a file type or protocol with a program** | Make a file type or protocol (such as .mp3 or http://) always open in a specific program. |
| 3 | **Change AutoPlay settings** | Play CDs or other media automatically. |
| 4 | **Set program access and computer defaults** | Control access to certain programs and set defaults for this computer. |

**Entry paths:** Start → Default Programs; Control Panel → Programs → Default Programs; `control /name Microsoft.DefaultPrograms`.

### 2.2 Set your default programs

**Window title:** Set Default Programs / Set your default programs.

| Region | Content |
|--------|---------|
| Left **Programs** list | Registered apps (icon + name) from `HKLM\SOFTWARE\RegisteredApplications` → Capabilities |
| Right pane | Description; status: *This program has all its defaults* **or** *This program has N out of M defaults* |
| Actions | **Set this program as default**; **Choose defaults for this program** |
| Footer | OK |

**Choose defaults for this program** → **Set associations for a program**:

- Checkbox list of extensions and protocols the program registered
- **Save** / **Cancel**
- Instruction: *Select the extensions you want this program to open by default, and then click Save.*

User-scoped (HKCU UserChoice); does not change other accounts.

### 2.3 Associate a file type or protocol with a program

**Window title:** Set Associations / Associate a file type or protocol with a specific program.

**List columns (exact):**

| Column | String |
|--------|--------|
| Name | Extension (`.mp3`) or protocol (`http`, `mailto`, …) |
| Description | File type / protocol description |
| Current Default | Current handler display name |

Extensions listed alphabetically; **Protocols** section follows extensions (http, https, ftp, mailto, …).

**Toolbar / button:** **Change program…** (enabled when a row is selected).

Instruction text: *Click on an extension to view the program that currently opens it by default. To change the default program, click Change program.*

**Cannot** clear an association to “none” — must pick another program.

### 2.4 Change program / Open With dialog

Opened from Set Associations or Explorer → Open with → Choose default program.

| Element | Behavior |
|---------|----------|
| **Recommended Programs** | Handlers registered for the type |
| **Other Programs** | Expandable list of additional apps |
| **Browse…** | Pick arbitrary `.exe` |
| **Always use the selected program to open this kind of file** | Checkbox (may be absent/greyed in some association-locked cases) |
| OK / Cancel | Commit UserChoice |

### 2.5 AutoPlay

**Global checkbox:** **Use AutoPlay for all media and devices**.

Per-type dropdowns. Common media categories (Win7):

- Audio CD, Enhanced audio CD
- DVD movie, Enhanced DVD movie, DVD audio
- Video CD movie, Super video CD movie
- Blu-ray etc. when present
- Blank CD, Blank DVD
- Software and games
- Pictures, Video files, Audio files, Mixed content
- Removable drive / Memory card / connected devices (cameras, phones) appear after connection

Universal actions often include: **Ask me every time**, **Take no action**, **Open folder to view files using Windows Explorer**, plus program-specific Play / Import / Rip handlers.

Buttons: **Save** / **Cancel**. Reset defaults link may appear.

### 2.6 Set program access and computer defaults (SPAD)

Computer-wide (requires elevation). Configurations:

| Configuration | Intent |
|---------------|--------|
| **Microsoft Windows** | Prefer Microsoft defaults (IE, WMP, Windows Mail, Windows Messenger, Microsoft Java) |
| **Non-Microsoft** | Prefer non-Microsoft registered alternatives; can remove access to Microsoft programs |
| **Custom** | Mix; per category choose default + **Enable access to this program** checkboxes |

Categories typically: Web browser, E-mail, Media player, Instant messaging, Virtual machine for Java.

Antitrust-era surface — still part of Win7 Default Programs muscle memory.

### 2.7 Omarchy interaction table — Default Programs

| User job | Win7 route | Omarchy phase / verb |
|----------|------------|----------------------|
| Make Chrome default browser | Default Programs → Set your default programs → Chrome → Set this program as default | Phase 5 exit still open; live host today is Settings → Apps `defaults.protocol.set` (browser LIVE only) |
| Open .pdf with Okular only | Associate… → `.pdf` → Change program | Phase 6 exit still open; `files.associations.set` stays missing/planned MIME. Do not invent MIME UI. |
| Stop USB AutoPlay | Change AutoPlay → Take no action / uncheck Use AutoPlay | Phase 6 removable media |
| Computer-wide media player | SPAD → Custom → Media player | Phase 5 computer defaults (admin) |

---

## 3. Administration (Win7 Ultimate)

### 3.1 Administrative Tools folder

**Paths:**

- Control Panel → System and Security → Administrative Tools
- Start → All Programs → Administrative Tools (if enabled)
- `%ProgramData%\Microsoft\Windows\Start Menu\Programs\Administrative Tools`
- Run: `control admintools`

**Typical Ultimate / Pro shortcuts (folder contents):**

| Shortcut | Launch |
|----------|--------|
| Component Services | `dcomcnfg` / `comexp.msc` |
| Computer Management | `compmgmt.msc` |
| Data Sources (ODBC) | `odbcad32.exe` |
| Event Viewer | `eventvwr.msc` |
| iSCSI Initiator | `iscsicpl.exe` |
| Local Security Policy | `secpol.msc` (Ultimate/Pro — not Home) |
| Performance Monitor | `perfmon.msc` |
| Print Management | `printmanagement.msc` |
| Services | `services.msc` |
| System Configuration | `msconfig.exe` |
| Task Scheduler | `taskschd.msc` |
| Windows Firewall with Advanced Security | `wf.msc` |
| Windows Memory Diagnostic | `mdsched.exe` |
| Windows PowerShell Modules | PowerShell console with modules |

(Exact OEM/SKU set can vary slightly; Ultimate includes Local Security Policy and BitLocker-related tooling elsewhere.)

### 3.2 Computer Management MMC tree

`compmgmt.msc` — three top categories:

```
Computer Management (Local)
├── System Tools
│   ├── Task Scheduler
│   ├── Event Viewer
│   ├── Shared Folders
│   ├── Local Users and Groups
│   ├── Performance
│   └── Device Manager
├── Storage
│   └── Disk Management
└── Services and Applications
    ├── Services
    └── WMI Control
```

Access also: right-click Computer → **Manage**.

### 3.3 Services (`services.msc`)

**List columns:** Name | Description | Status | Startup Type | Log On As

**Startup types:** Automatic (Delayed Start) | Automatic | Manual | Disabled

**Context / Actions:** Start, Stop, Pause, Resume, Restart, Properties, Refresh, Export List…

**Properties tabs:** General | Log On | Recovery | Dependencies

**Task Manager bridge:** Services tab → **Services…** button opens this snap-in.

### 3.4 Event Viewer (`eventvwr.msc`)

Tree:

- Custom Views
- **Windows Logs:** Application, Security, Setup, System, Forwarded Events
- Applications and Services Logs
- Subscriptions

Middle: event list (Level, Date and Time, Source, Event ID, Task Category…).  
Right: Actions (Filter Current Log, Save, Attach Task To This Event…).

**Not** Notification Center toast history — product Event Viewer job is this MMC.

### 3.5 Task Scheduler (`taskschd.msc`)

- Task Scheduler (Local)
- Task Scheduler Library (+ Microsoft\Windows\… folders)
- Active Tasks / overview pane

Task properties tabs: **General**, **Triggers**, **Actions**, **Conditions**, **Settings**, **History**.

Create Basic Task / Create Task wizards.

### 3.6 Disk Management (`diskmgmt.msc`)

- Upper: volume list (Volume, Layout, Type, File System, Status, Capacity, Free Space, % Free)
- Lower: graphical disk map (Disk 0…, partitions, unallocated)
- Actions: New Simple Volume, Extend/Shrink, Format, Change Drive Letter and Paths, Mark Partition as Active, Convert to Dynamic/GPT (where applicable), Offline/Online

### 3.7 Local Users and Groups (`lusrmgr.msc`)

**Present on Ultimate** (absent on Home editions).

- Users: New User, Set Password, Properties (General, Member Of, Profile)
- Groups: Administrators, Users, Guests, Power Users, etc.

### 3.8 Device Manager (`devmgmt.msc`)

Tree by class (Display adapters, Disk drives, Network adapters, Sound…).  
Device Properties: General, Driver, Details, Events, Resources, Power Management.  
Actions: Update Driver, Disable, Uninstall, Scan for hardware changes, Show hidden devices.

### 3.9 Task Manager — **Win7 tabs only**

`taskmgr.exe` — **six tabs** (never Win10 Processes/AppHistory/Startup/Details/Services redesign):

| Tab | Purpose | Key actions |
|-----|---------|-------------|
| **Applications** | Top-level windows; Status Running / Not Responding | End Task, Switch To, New Task… |
| **Processes** | Image Name, User Name, CPU, Memory, Description… | End Process, End Process Tree, Set Priority, Set Affinity, Show processes from all users |
| **Services** | Name, Status, Description, Group | Start/Stop; **Services…** → services.msc |
| **Performance** | CPU Usage + history (per-core option), Memory | **Resource Monitor** button |
| **Networking** | Adapter utilization graphs; Link Speed, State | View → Select Columns |
| **Users** | Logged-on users; Disconnect / Logoff / Send Message (admin / Fast User Switching) | |

Menus: File (New Task), Options (Always on Top, Minimize on Use, Hide When Minimized), View (Refresh Now, Update Speed, columns, CPU History).

**Omarchy:** Win7 six-tab IA is the reference when a product Task Manager exists. `btop` is not Task Manager. Phase 9 exit criteria still open: Administration > Processes hosts bounded `process.inspect` + unauthorized End Task path. Inspect inventory ≠ Task Manager present.

### 3.10 Omarchy interaction table — Administration

Win7 MMC / Task Manager tables above stay **reference**. Phase 9 exit criteria still open. Live Administration product routes already host bounded Fabric inspect. Inspect inventory ≠ product MMC present: no start/stop service LIVE, no Device Manager present, no Task Manager present, no Event Viewer present, no `firewall.manage` / `backup.manage` LIVE.

| User job | Win7 route | Omarchy live host today |
|----------|------------|-------------------------|
| Inspect running processes / unauthorized End Task path | Task Manager → Applications → End Task | Administration > Processes (`process.inspect` + `process.termination.plan`; End Task unauthorized; not Task Manager present) |
| See CPU/RAM | Task Manager → Performance → Resource Monitor | `resources.inspect` stays honest-missing; not Task Manager Performance; not btop |
| Inspect services (no start/stop LIVE) | services.msc or Computer Management → Services | Administration > Services (`service.inspect`; not Services product) |
| View System log | eventvwr → Windows Logs → System | No Event Viewer present. Administration > Troubleshooting hosts `diagnostics.inspect` only — not Event Viewer. Toast ledger is Event / history, not this MMC. |
| Inspect scheduled tasks (no create/disable LIVE) | taskschd.msc | Administration > Scheduled tasks (`schedule.inspect`; not Task Scheduler product) |
| Inspect disks (no format/mount/eject LIVE) | diskmgmt.msc | Administration > Storage (`storage.inspect`; not Disk Management product) |
| Inspect devices (no driver mutation) | Device Manager | Administration > Device Manager (`device.inspect`; not Device Manager present) |
| Inspect printers (no add LIVE) | Devices and Printers / Print Management | Administration > Printers and scanners (`printer.inspect`; not Devices and Printers product) |
| Inspect backup inventory (no backup.manage LIVE) | Backup and Restore | Administration > Backup (`backup.inspect`; not Backup and Restore product) |
| Inspect firewall (no firewall.manage LIVE) | wf.msc | Administration > Firewall (`firewall.inspect`; not Firewall Settings product) |
| Inspect local users (no create/password LIVE) | lusrmgr.msc | Administration > User accounts (`account.inspect`; not User Accounts product) |

---

## 4. Media

### 4.1 Sound applet (`mmsys.cpl`)

**Four tabs (Win7):**

| Tab | Contents |
|-----|----------|
| **Playback** | Output devices; green check = Default Device; Set Default; Configure; Properties (General, Levels, Enhancements, Advanced) |
| **Recording** | Inputs; level meters; Show Disabled/Disconnected Devices (context menu on empty area) |
| **Sounds** | Sound Scheme dropdown; Program Events tree; Sounds list; Test; Browse `.wav`; **Play Windows Startup sound** checkbox |
| **Communications** | When Windows detects communications activity: Mute all / Reduce 80% / Reduce 50% / Do nothing |

Tray speaker **right-click** menu (Win7):

- Open Volume Mixer
- Playback devices
- Recording devices
- Sounds
- (Volume Control Options on some builds)

Left-click tray speaker → master volume slider + **Mixer** link.

### 4.2 Volume Mixer (per-app) — Win7 behavior

**Layout:**

| Column group | Controls |
|--------------|----------|
| **Device** | Icon for default playback device; master volume slider; mute; clicking device icon → Speakers Properties / Sound |
| **Applications** | System Sounds + one slider per actively playing app session |

**Rules:**

- Lowering Device scales down application output ceilings.
- Raising an app above Device raises Device with it.
- App sliders independent below Device ceiling.
- Sessions appear/disappear as apps start/stop audio.
- Not the Win10/11 modern volume flyout as primary chrome.

### 4.3 Windows Media Player 12 — parity-relevant chrome

WMP 12 ships with Win7. Omarchy does not need a pixel clone; these behaviors are the muscle-memory reference for a default media player:

| Behavior | Win7 WMP 12 |
|----------|-------------|
| Dual modes | **Player Library** vs **Now Playing** (switch buttons lower-right / upper-right) |
| Library | Navigation tree with Music / Videos / Pictures / Recorded TV / Playlists; Play/Burn/Sync tabs |
| Now Playing | Minimal playback chrome, playlist pane, visualizations, Enhancements undocked windows |
| Taskbar | Thumbnail toolbar: previous / play-pause / next (no full mini-mode toolbar like WMP 11) |
| Jump List | Frequent/recent media + tasks (e.g. Resume previous list, Play all music) |
| Default associations | Registers extensively; managed via Default Programs / AutoPlay |

Enhancements (Now Playing → right-click): Graphic Equalizer, Video Settings, etc.

### 4.4 Omarchy interaction table — Media

| User job | Win7 route | Omarchy |
|----------|------------|---------|
| Mute one app, keep others | Tray → Mixer → app slider | Phase 5 exit still open; live host today is Settings → Sound `audio.volume.set` + tray Quick Settings honesty. Per-app mixer not product-present. |
| Change default speakers | Tray → Playback devices → Set Default | Phase 5 exit still open; mute/routing remain unavailable |
| Silence balloon sounds | Sounds tab → scheme / event → (None) | Phase 5 Personalization/Sound |
| Play DVD insert | AutoPlay → Play DVD movie using WMP | Phase 6 AutoPlay + Phase 7 player |
| Per-app default for .mp3 | Default Programs | Phase 5/6 defaults |

---

## 5. Settings analogs → Omarchy Settings IA

Win7 did **not** use a single modern Settings app. Muscle memory maps as:

| Win7 surface | Omarchy Settings destination (Phase 5) |
|--------------|----------------------------------------|
| Personalization | Personalization |
| Display (Control Panel) | Display |
| Sound / Volume Mixer | Sound (+ tray mixer) |
| Mouse / Pointers | Input (pointers subsection) |
| Power Options | Power — Settings Power inspect only; Settings Power LIVE refused |
| Default Programs | Apps (defaults) — must expose the **four-job** IA, not a single dropdown. Live host today is `defaults.protocol.set` (browser LIVE only). |
| Ease of Access | Accessibility — Phase 5 exit still open; no Accessibility panel as product (honest missing Fabric page) |
| Region and Language | Input (layout writer when switchable); full locale remains missing |
| System → Advanced / Performance | System Information remains missing as product (no aggregate provider) |
| Administrative Tools | **Not** Settings. Phase 9 exit criteria still open. Live Administration inspect hosts today: Processes, Services, Device Manager, Storage, Printers and scanners, Backup, Scheduled tasks, Troubleshooting, Firewall, User accounts. Inspect inventory ≠ product MMC present. |

Progressive disclosure doctrine: Settings → Display → Resolution is normal; generated Hyprland config is Advanced.

---

## 6. Acceptance checklist for implementers

- [ ] Personalization exposes Wallpaper position Fill/Fit/Stretch/Tile/Center + slideshow Interval/Shuffle
- [ ] Window Color has Enable transparency + Color intensity + Advanced Item list with Size/Color/Font where applicable
- [ ] Theme pack round-trip understands `.theme` required sections + `.themepack` CAB layout
- [ ] Default Programs hub shows **exactly four** links with Win7 descriptions
- [ ] Set Associations list has columns Name | Description | Current Default; Change program opens Recommended/Other/Browse
- [ ] AutoPlay master checkbox + per-media dropdowns
- [ ] SPAD Microsoft / Non-Microsoft / Custom
- [ ] Task Manager has Applications, Processes, Services, Performance, Networking, Users — **no Win10 tabs**
- [ ] Computer Management tree matches System Tools / Storage / Services and Applications
- [ ] Sound applet has Playback, Recording, Sounds, Communications
- [ ] Volume Mixer is Device + Applications per-session sliders
- [ ] No Win10/11 Default apps Settings page as the primary path

---

## Citations

1. Microsoft Learn — Theme File Format: https://learn.microsoft.com/en-us/windows/win32/controls/themesfileformat-overview  
2. Microsoft Learn — Default Programs (Win32): https://learn.microsoft.com/en-us/windows/win32/shell/default-programs  
3. Win7 `sud.dll` string table (Default Programs UI labels): https://win7dll.nirsoft.net/sud_dll.html  
4. How-To Geek — Default applications / associations (Win7 Control Panel paths): https://www.howtogeek.com/137483/beginner-geek-7-ways-you-can-change-default-applications-and-file-associations-in-windows/  
5. FileInfo — Windows 7 Default Programs walkthrough: https://fileinfo.com/help/windows_7_default_programs  
6. Microsoft Support — Desktop background slideshow (Win7): https://support.microsoft.com/en-gb/topic/guided-help-shuffle-your-desktop-backgrounds-in-windows-7-4f9cbcb6-62c4-6d2f-24b9-683da11af11a  
7. TechRepublic — Appearance and Personalization walkthrough: https://www.techrepublic.com/pictures/windows-7-walkthrough-appearance-and-personalization-control-panel/  
8. Digital Citizen / SoftPerfect-style Item lists — Advanced appearance items: https://www.digitalcitizen.life/geeky-way-personalizing-windows-themes/ ; http://softwareok.com/?faq=118&seite=faq-Windows-7  
9. TechTarget — Computer Management MMC categories / Task Manager tabs: https://www.techtarget.com/searchitchannel/feature/MMC-console-management-Adding-Windows-7-snap-ins ; https://www.techtarget.com/searchitchannel/feature/Windows-task-manager-Viewing-Windows-7-processes-and-applications  
10. Tips.Net — Task Manager six tabs: https://windows.tips.net/T012208_Understanding_the_Task_Manager.html  
11. How-To Geek — Task Manager Win7 vs later: https://www.howtogeek.com/169823/beginner-geek-what-every-windows-user-needs-to-know-about-using-the-windows-task-manager/  
12. AskWoody / LifeWire — Administrative Tools inventory: https://www.askwoody.com/newsletter/exploring-windows-administrative-tools-part-1/ ; https://www.lifewire.com/administrative-tools-2625804  
13. Utilize Windows — services.msc startup types: https://utilizewindows.com/managing-services-in-windows-7/  
14. How-To Geek / Tips.Net — Volume Mixer: https://www.howtogeek.com/5228/simple-tips-windows-7-volume-mixer-enables-quick-access-to-sound-settings/ ; https://windows.tips.net/T012207_Adjusting_Speaker_Volume.html  
15. FlexRadio / Microsoft Q&A — Sound tray menu + Playback/Recording/Sounds/Communications: https://helpdesk.flexradio.com/hc/en-us/articles/203731345-How-To-Set-The-Windows-Default-Playback-Recording-Audio-Device  
16. How-To Geek — Sounds tab / schemes: https://www.howtogeek.com/22437/beginner-geek-customize-logon-other-sound-events-in-windows-7/  
17. Ars Technica / Wikipedia — WMP 12 Library vs Now Playing, thumbnail toolbar, Jump Lists: https://arstechnica.com/information-technology/2008/10/hands-on-windows-media-player-12s-surprising-new-features/ ; https://en.wikipedia.org/wiki/Windows_Media_Player  
18. Microsoft Learn — Taskbar thumbnail toolbar / Jump Lists: https://learn.microsoft.com/en-us/windows/win32/shell/taskbar-extensions  
19. gHacks / Dell KB — AutoPlay media categories: https://www.ghacks.net/2010/02/07/configure-media-and-device-autoplay-in-windows-7/  
20. Omarchy docs — `docs/project-ultimate.md`, `docs/WINDOWS_7_ULTIMATE_PARITY.md` (local)
