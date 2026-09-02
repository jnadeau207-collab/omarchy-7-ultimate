# 06 — Settings Analogs, Default Programs, Administration, Media (Win7 Ultimate)

**Repo path:** `plans/win7-ultimate-ground-truth/06-settings-defaults-admin-media.md`  
**Research sources:** `research/06-SETTINGS-ADMIN-MEDIA.md` + `.json`, `fleet-catalog-controlpanel.md` §3–4  
**Target phases:** Phase 5, Phase 6 (AutoPlay/MIME), Phase 7 (media player as app), Phase 9  
**DPI baseline:** **96 DPI / 100%**

---

## Purpose

Binding Win7 Ultimate Personalization, Default Programs (exact four links), Administrative Tools / MMC trees, Task Manager tabs, Volume Mixer / Sound, and WMP-12-era media chrome references — without Win10/11 Settings contamination.

---

## Binding metrics / layout anchors

| Surface | BINDING notes |
|---------|---------------|
| Personalization bottom row | **Desktop Background** · **Window Color** · **Sounds** · **Screen Saver** |
| Window Color (Aero) | Swatches + Enable transparency + Color intensity + optional HSB mixer |
| Desktop Background positions | **Fill / Fit / Stretch / Tile / Center** (WallpaperStyle 10/6/2/0+tile/0) |
| Default Programs hub | Exactly **four** links (see below) |
| Volume flyout | Tray speaker → vertical slider + mixer link |
| Admin Tools | Folder of `.msc` / exes — not Settings pages |
| Dialog chrome | Visual top NC **30**; `SM_CYCAPTION` **22** metric only |

---

## Personalization

### Entry

Desktop RC → Personalize · CP → Appearance and Personalization → Personalization · Start search.

### Theme groups

My Themes · Aero Themes · Basic and High Contrast Themes.

### Advanced appearance Item list (implement all names)

3D Objects; Active/Inactive Title Bar; Active/Inactive Window Border; Application Background; Border Padding; Caption Buttons; Desktop; Disabled Item; Hyperlink; Icon; Icon Spacing H/V; Menu; Message Box; Palette Title; Scrollbar; Selected Items; ToolTip; Window.

### Screen Saver

Dropdown + Settings… + Preview + Wait minutes + On resume display logon screen + Power management link.

### Mouse Pointers

Schemes: Windows Aero, Standard, Magnified, Inverted, Extra Large, custom. Cursor roles per `07-interaction-grammar.md` / Aero cursor table.

---

## Default Programs — BINDING four links

| # | Link | Description (sud.dll) |
|---|------|------------------------|
| 1 | **Set your default programs** | Make a program the default for all file types and protocols it can open. |
| 2 | **Associate a file type or protocol with a program** | Make a file type or protocol always open in a specific program. |
| 3 | **Change AutoPlay settings** | Play CDs or other media automatically. |
| 4 | **Set program access and computer defaults** | Control access to certain programs and set defaults for this computer. |

**Set Associations columns:** Name | Description | Current Default. Button: **Change program…**

**Open With:** Recommended Programs · Other Programs · Browse… · Always use… checkbox · OK/Cancel.

**AutoPlay:** Use AutoPlay for all media and devices + per-type dropdowns (Audio CD, DVD, Blank media, Pictures, Video, Audio, Mixed, Removable drive, …) · Ask me every time / Take no action / Open folder… · Save/Cancel.

**SPAD configurations:** Microsoft Windows · Non-Microsoft · Custom (Web browser, E-mail, Media player, IM, Java VM).

---

## Administration

### Administrative Tools (typical Ultimate)

Component Services · Computer Management · Data Sources (ODBC) · Event Viewer · iSCSI Initiator · Local Security Policy · Performance Monitor · Print Management · Services · System Configuration · Task Scheduler · Windows Firewall with Advanced Security · Windows Memory Diagnostic · PowerShell Modules.

### Computer Management tree

```
Computer Management (Local)
├── System Tools (Task Scheduler, Event Viewer, Shared Folders, Local Users and Groups, Performance, Device Manager)
├── Storage (Disk Management)
└── Services and Applications (Services, WMI Control)
```

### Services columns

Name | Description | Status | Startup Type | Log On As  
Startup: Automatic (Delayed Start) | Automatic | Manual | Disabled.

### Task Manager (Win7 tabs — BINDING)

Applications | Processes | Services | Performance | Networking | Users  

**Anti-invent:** End Task requires authorized termination path; do not claim LIVE kill under shell consequential when `terminationAuthorized=false`.

### Event Viewer / Task Scheduler / Disk Management / Device Manager

MMC snap-ins (`eventvwr.msc`, `taskschd.msc`, diskmgmt via compmgmt, `devmgmt.msc`). Toast history ≠ Event Viewer.

---

## Sound / Volume Mixer / Media

| Surface | Behavior |
|---------|----------|
| Sound CPL (`mmsys.cpl`) | Playback / Recording / Sounds / Communications tabs |
| Tray Volume | Click → flyout slider; Mixer link → per-app + device volumes |
| Sounds tab | Scheme (Windows Default, No Sounds, Afternoon…Sonata pack) + program events + Test |
| WMP 12 | Default media chrome reference for Now Playing / Library / Play/Burn/Sync — not a clone mandate |

---

## Interaction matrix

| Gesture | Result |
|---------|--------|
| Desktop RC → Personalize | Personalization hub |
| Personalization → Window Color | Aero colorization UI |
| Start → Default Programs | Four-link hub |
| Set Associations → Change program | Open With |
| Tray speaker left-click | Volume flyout |
| Tray speaker RC | Playback devices / Open Volume Mixer / … |
| Ctrl+Shift+Esc | Task Manager |
| Computer RC → Manage | Computer Management |
| CP → Administrative Tools | Admin Tools folder |

---

## Win7 vs Omarchy notes

| Win7 | Omarchy |
|------|---------|
| Personalization CPL | Settings → Personalization (picker prototype) |
| Default Programs four links | Settings → Apps; browser protocol subset only |
| MIME Associate UI | `files.associations.set` / MIME UI **missing** as product |
| AutoPlay | **Missing** |
| Task Manager tabs | **Missing** as product (btop ≠ TM) |
| Volume Mixer | Superbar audio panel / Settings Sound inspect |

**Phase ownership:** Personalization/Sound/Display/Power/Input → Phase 5; MIME/AutoPlay → Phase 6; Admin MMC → Phase 9; media player product → Phase 7.

**Anti-invent:** Browser LIVE CONTROL ≠ Default Programs complete; do not walk `parity.default-programs` to `present` from https alone; System information jump must stay omitted without provider.

---

## Citations

- `06-SETTINGS-ADMIN-MEDIA.md/.json`; sud.dll Default Programs strings; MMC docs  
- `fleet-catalog-controlpanel.md`; Microsoft Personalization / Sound / Task Manager Win7 help  

---

## Open metal-verify items

1. Exact SPAD category list on Ultimate SP1.  
2. Volume Mixer per-app row chrome @ 96 DPI.  
3. Task Manager column sets per tab on clean Ultimate.  
4. Theme pack install paths vs gallery recognition rules.
