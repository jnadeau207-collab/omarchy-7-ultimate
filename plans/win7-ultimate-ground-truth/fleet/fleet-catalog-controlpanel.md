---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# Win7 Ultimate Control Panel / Default Programs / Settings analogs → Omarchy catalog map

**Author:** Review Catalog (fleet research for Lead)  
**Date:** 2026-09-02  
**Repo snapshot:** `omarchy-7-ultimate` `work` (jobs/readers/routes as of this write)  
**Scope:** Complete applet inventory for **Windows 7 Ultimate** Control Panel (category view + All Items), plus Default Programs depth and Settings analogs; each row maps to Omarchy product surface(s) and catalog/provider jobs.  
**Not:** W0–W5 close, OS ship verdict, or a claim that Omarchy has closed any row.

Sources: Microsoft Learn Control Panel canonical names (Vista/7 family), Win7 Administrator’s Reference Control Panel categories, Omarchy `WINDOWS_7_ULTIMATE_PARITY.md`, `default/ultimate/parity/jobs.json`, `catalog-provider-readers-v0.json`, `catalog-system-jobs-v0.json`, Settings/Administration `routes-v1.json`.

**Product honesty after #35–#39:** Administration inspect readers are **visible** on live Administration titles after #36; `availability.claim` stays **missing**; Phase 9 exit still open; inspect ≠ MMC product present. `process.inspect` is **visible** on `Administration > Processes`; claim **missing**; honest-unavailable as Task Manager product; End Task unauthorized (`terminationAuthorized=false`); do not invent Task Manager present / End Task LIVE. Writers (`firewall.manage`, `backup.manage`, start/stop, …) stay planned/unavailable. Default Programs writer is `defaults.protocol.set` (browser LIVE only); `defaults.mime.set` write plane is reachable; Settings does not offer MIME LIVE CONTROL; `files.associations.set` stays missing/planned MIME. Catalog humanRoutes already published visible; residual = product MMC / mutation / Task Manager present still missing, not catalog planned-empty. Catalog caught up for Admin inspect visibility (#35–#36). Product remains **REJECTED**. Do not invent Accessibility panel. Software Center missing as product. Settings Power LIVE refused. Settings coverage-badge PIXEL leftover CLOSED on `d3f4841a`. QS Power METAL_HEAD OPEN (metal FAIL on tip `20484de6`; leftover was unverified on metal after PR #31). Do not claim the heritage QS Power panel works on this metal.

---

## 1. How Win7 Control Panel is organized

| View | What the user sees |
| --- | --- |
| **Category** (default) | Eight top categories with featured tasks |
| **All Control Panel Items** (Large/Small icons) | Flat icon list (God Mode / `All Control Panel Items` is the same set) |
| **Search** | Filters applets and deep links |

**Ultimate SKU notes (vs Home Premium):** BitLocker Drive Encryption is present; Parental Controls / Family Safety present; Windows Anytime Upgrade present; Media Center-related bits may appear by media; HomeGroup present. Hardware-gated applets (Biometric Devices, Infrared, Pen and Touch, Tablet PC, Mobility Center) appear only when hardware warrants.

**Omarchy product analogs (not 1:1 Control Panel):**

| Win7 surface | Omarchy analog |
| --- | --- |
| Control Panel home | `org.omarchy.Settings` home + Start search Settings hits |
| Control Panel icon applets | Settings routes, Superbar/QS panels, Administration, Files, Start places |
| Administrative Tools folder | `org.omarchy.Administration` (+ MMC-class tools still missing as product; inspect hosts visible, claim missing) |
| Default Programs | Settings → Apps (`defaults.provider`); `defaults.protocol.set` browser LIVE only; `defaults.mime.set` write plane is reachable; Settings does not offer MIME LIVE CONTROL; MIME associations still missing/planned; MIME / Default Programs association UI residual OPEN after PR #62 |
| Recycle Bin | Files Trash routes / `files.trash.*` plane; `files.trash.restore` write plane is reachable (claim=partial; humanRoute planned empty); `files.trash.manage` write plane is reachable (claim=partial; humanRoute planned empty; `emptyBinAuthorized=false`); Recycle Bin / Empty Bin LIVE residual OPEN after PR #63 |
| Explorer Open | Files Open / `files.entry.open` launch plane is reachable (claim=partial; risk low; SHELL-grantable; visible `Files > Open`); no Open With / MIME association UI |
| Explorer Rename | Files Rename / `files.entry.rename` write plane is reachable (claim=partial; risk low; SHELL-grantable; visible `Files > Rename`; `renameAuthorized=true`); same-directory only |
| Explorer Copy and Paste | Files Copy and Paste / `files.entry.copy` write plane is reachable (claim=partial; risk low; SHELL-grantable; visible `Files > Copy and Paste`; `copyAuthorized=true`); regular files and directories; folder copy CLOSED; in-app staging; OS clipboard residual OPEN after PR #60; OS clipboard residual OPEN after PR #64 |
| Explorer Cut and Paste | Files cut/move / `files.entry.move` write plane is reachable (claim=partial; risk consequential; SHELL refused at `grant.shell-consequential`; humanRoute planned empty; `cutAuthorized=false`); regular files; dest-scoped identity; no LIVE Cut or OS clipboard; folder copy CLOSED via `files.entry.copy` |
| Explorer Permanent Delete | Files permanent delete / `files.entry.delete` write plane is reachable (claim=partial; risk consequential; SHELL refused at `grant.shell-consequential`; humanRoute planned empty; `deleteAuthorized=false`); regular files and empty directories; identity-bound; permanent delete write plane exists but is not shell-authorizable; no LIVE Delete or Empty Bin LIVE; Recycle Bin / Empty Bin LIVE residual OPEN after PR #63 |

---

## 2. Category view → Omarchy map

### 2.1 System and Security

| Win7 item | Canonical / notes | Omarchy surface | Catalog / jobs | Provider truth |
| --- | --- | --- | --- | --- |
| Action Center | `Microsoft.ActionCenter` | Partial: Notification Center + Superbar update/security cues; **no** Action Center applet | `parity.event-history` prototype (`events.history.read`); no `action-center.*` | No Action Center provider |
| Windows Firewall | `Microsoft.WindowsFirewall` | Administration > Firewall (visible inspect host); Settings network firewall path empty | `parity.firewall` plumbing; `firewall.inspect` visible; claim missing; honest-unavailable as Firewall Settings product; `firewall.manage` stays planned/unavailable | `firewall.provider` |
| System | `Microsoft.System` | Settings jump **System information** dropped; Admin/system info missing | `system.info.read` missing; `windows-native.38` jump-list leftover vs empty catalog path | No `system-information.provider` product page |
| Windows Update | `Microsoft.WindowsUpdate` | Settings → Update | `parity.update` prototype; `update.inspect` partial; `update.install` / history writers Phase-5/pending | `update.provider` |
| Power Options | `Microsoft.PowerOptions` | Settings → Power; Superbar/QS Power leftover | `parity.power-options` prototype; `power.inspect`; `power.profile.set` write plane not Settings LIVE (fabric polkit `app.slice`); QS Process leftover FAIL on this metal (pkcheck Not authorized / session-5103; !batteryPresent; amd_pstate EINVAL); leftover was unverified on metal after PR #31; QS Power METAL_HEAD OPEN | `power.provider` (session_operable=False) |
| Backup and Restore | `Microsoft.BackupAndRestore` | Administration > Backup (visible inspect); Settings Recovery | `parity.backup-restore` / `parity.system-restore` plumbing; `backup.inspect` visible; claim missing; honest-unavailable as Backup and Restore product; `backup.manage` stays planned/unavailable | `backup.provider` / `recovery.provider` |
| BitLocker Drive Encryption | `Microsoft.BitLockerDriveEncryption` (**Ultimate**) | **Missing** product | `parity.drive-encryption` missing; `storage.encryption.manage` | No encryption writer surface |
| Administrative Tools | `Microsoft.AdministrativeTools` (folder) | Administration app (partial stand-in; inspect hosts visible, claim missing) | See §4 | Mix of leaf inspect providers |

**Administrative Tools (folder contents) — Ultimate:**

| Tool | Omarchy map | Catalog / jobs |
| --- | --- | --- |
| Event Viewer | Notification history / capability ledger only | `parity.event-history` prototype — **not** Event Viewer; no Event Viewer present |
| Task Scheduler | Administration > Scheduled tasks (visible inspect) | `parity.task-scheduler` missing; `schedule.inspect` visible; claim missing; honest-unavailable as Task Scheduler product; schedule create/disable stays planned/unavailable |
| Services | Administration > Services (visible inspect) | `parity.services` missing; `service.inspect` visible; claim missing; honest-unavailable as Services product; no start/stop service LIVE |
| Computer Management / Disk Management | Administration > Storage (visible inspect) | `parity.disk-management` missing; `storage.inspect` visible; claim missing; honest-unavailable as Disk Management product; format/mount/eject stays planned/unavailable |
| Performance / Resource Monitor | **Missing** (btop TUI only) | `parity.resource-monitor` missing; `resources.inspect` missing |
| Task Manager (often reached via Ctrl+Shift+Esc, not only Admin Tools) | Administration > Processes (visible inspect; do not invent Task Manager present) | `process.inspect` **visible** on `Administration > Processes`; claim **missing**; honest-unavailable as Task Manager product; End Task unauthorized (`terminationAuthorized=false`); do not invent Task Manager present / End Task LIVE; `parity.task-manager` stays missing as product |
| System Configuration / iSCSI / etc. | **Missing** | No catalog rows |

### 2.2 Network and Internet

| Win7 item | Omarchy surface | Catalog / jobs | Provider |
| --- | --- | --- | --- |
| Network and Sharing Center | Settings → Network; Superbar/QS Network | `parity.network` prototype; `network.inspect`; Settings Wi-Fi radio `network.manage`; join leftover `network.wifi.connect` | `network.provider` |
| HomeGroup | **Missing** (no Homegroup product) | No dedicated job; sharing SMB missing | — |
| Internet Options | **Missing** as Control Panel; browser-owned | No `internet.options.*` | — |

### 2.3 Hardware and Sound

| Win7 item | Omarchy surface | Catalog / jobs | Provider |
| --- | --- | --- | --- |
| Devices and Printers | Administration > Printers and scanners (visible inspect); Bluetooth in Settings | `parity.devices-printers` missing/prototype; `printer.inspect` visible; claim missing; honest-unavailable as Devices and Printers product; `printers.manage` / add stays planned/unavailable | `printer.provider` / `bluetooth.provider` |
| Device Manager | Administration > Device Manager (visible inspect) | `parity.device-manager` missing; `device.inspect` visible; claim missing; honest-unavailable as Device Manager product; no driver mutation | `device.provider` |
| AutoPlay | **Missing** | No catalog row | — |
| Sound | Settings → Sound; Superbar/QS | `parity.sound` prototype; `audio.inspect`; Settings volume `audio.volume.set` | `audio.provider` |
| Display | Settings → Display | `parity.display` + modern display prototype; `display.inspect`; Settings brightness `display.brightness.set`; QS leftover `display.configure` / night-light | `display.provider` |
| Windows Mobility Center | **Missing** (laptop hub) | No row | — |
| Biometric Devices | Hardware-gated; **Missing** | No row | — |
| Mouse / Keyboard (main.cpl) | Settings → Input (keyboard layout writer); mouse **Missing** as applet | `parity.language-locale` / `input.keyboard-layout.set` prototype; mouse not catalogued | `input.provider` |
| Pen and Touch / Tablet PC | Hardware-gated; **Missing** | No row | — |

### 2.4 Programs

| Win7 item | Omarchy surface | Catalog / jobs | Provider |
| --- | --- | --- | --- |
| Programs and Features | Settings → Apps (read defaults); Software Center **missing** as product | `parity.programs-and-features` missing; `software.*` / packages inspect claim Software Center paths | `packages.provider` plan_only; do not invent `apps.provider` present |
| Default Programs | Settings → Apps | See **§3** | `defaults.provider` (real); writer is `defaults.protocol.set` (browser LIVE only) |
| Desktop Gadgets | N/A (Win7 feature; removed later) | No Omarchy gadget surface | — |

### 2.5 User Accounts and Family Safety

| Win7 item | Omarchy surface | Catalog / jobs | Provider |
| --- | --- | --- | --- |
| User Accounts | Administration > User accounts (visible inspect) | `parity.user-accounts` missing; `account.inspect` visible; claim missing; honest-unavailable as User Accounts product; create/password stays planned/unavailable | `account.provider` |
| Parental Controls / Family Safety | **Missing** | No row | — |
| Credential Manager | **Missing** | `parity.credential-manager` missing; `credentials.manage` | No product |
| Mail (profile) | **Missing** | No row | — |
| Windows CardSpace | Deprecated / N/A | No row | — |

### 2.6 Appearance and Personalization

| Win7 item | Omarchy surface | Catalog / jobs | Provider |
| --- | --- | --- | --- |
| Personalization | Settings → Personalization | `parity.personalization` prototype; wallpaper/theme caps | image picker / theme packs |
| Display (dup) | Settings → Display | See Hardware | `display.provider` |
| Taskbar and Start Menu | Superbar + Start (chrome, not CP applet) | `parity.superbar-taskbar` / `parity.start` prototype | shell plugins |
| Ease of Access Center | Settings Accessibility (**honest missing** page / empty path) | `parity.accessibility` missing; `accessibility.configure` missing | No `accessibility.provider` |
| Folder Options | **Missing** as applet; Files has partial behaviors | No `folder.options.*` | — |
| Fonts | **Missing** | No row | — |
| Desktop Gadgets (dup) | N/A | — | — |

### 2.7 Clock, Language, and Region

| Win7 item | Omarchy surface | Catalog / jobs | Provider |
| --- | --- | --- | --- |
| Date and Time | Superbar clock / calendar chrome | No dedicated parity job | clock widgets |
| Region and Language | Settings → Input (layout); full locale **planned** empty | `parity.language-locale` prototype; `locale.configure` planned; `input.keyboard-layout.set` visible Settings > Input | `input.provider`; no full locale writer |

### 2.8 Ease of Access

| Win7 item | Omarchy surface | Catalog / jobs |
| --- | --- | --- |
| Ease of Access Center | Settings Accessibility missing page | `parity.accessibility` missing |
| Speech Recognition | **Missing** | No row |

---

## 3. Default Programs (depth)

Win7 **Default Programs** (`Microsoft.DefaultPrograms`) exposes:

1. **Set your default programs** (per-app)  
2. **Associate a file type or protocol with a program**  
3. **Change AutoPlay settings**  
4. **Set program access and computer defaults** (SPAD)

| Win7 sub-job | Omarchy today | Catalog / jobs honesty |
| --- | --- | --- |
| Change default browser (protocol http/https) | Settings → Apps drives `defaults.provider` `protocol.set` (typed plane) | `windows-native.19` claim **prototype** (not present); `parity.default-programs` claim **prototype** but `sourceStatus` still **missing**; writer is `defaults.protocol.set` (browser LIVE only) |
| MIME / file associations | Plane: `defaults.mime.set` write plane is reachable (`defaults-mime-set` helper; preflight OK; risk low); `association.inspect` is published for durable apply re-read; Settings MIME UI not a full Default Programs | `files.associations.set` stays missing/planned MIME; File associations parity **missing as product** — Settings does not offer MIME LIVE CONTROL — MIME / Default Programs association UI residual OPEN after PR #62 — do **not** invent MIME Default Programs LIVE |
| AutoPlay | **Missing** | No catalog |
| SPAD / program access | **Missing** | No catalog |
| Catalog ID used by jobs | Settings → Apps `defaults.protocol.set` | Writer is `defaults.protocol.set` (browser LIVE only). Do not invent `apps.provider` present. MIME stays missing/planned. |

---

## 4. All Control Panel Items (flat inventory)

Complete Win7-family applet set relevant to **Ultimate client** (excluding Server-only iSNS/MPIO). Status = Omarchy product honesty vs catalog.

| # | Applet | Ultimate? | Omarchy analog | Primary jobs / caps | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Action Center | Yes | NC / Superbar cues only | `parity.event-history` | Gap |
| 2 | Administrative Tools | Yes | Administration app (partial; inspect hosts visible) | Admin readers visible; claim missing; Phase 9 exit still open | Partial; invent risk is Task Manager present / MMC product, not catalog planned-empty |
| 3 | AutoPlay | Yes | — | — | Gap |
| 4 | Backup and Restore | Yes | Administration > Backup (visible inspect) / Recovery | `parity.backup-restore` plumbing; `backup.inspect` visible; claim missing | Visible inspect; product Backup and Restore still missing; `backup.manage` planned/unavailable |
| 5 | Biometric Devices | HW | — | — | Gap / HW |
| 6 | BitLocker Drive Encryption | **Ultimate** | — | `parity.drive-encryption` missing | Gap |
| 7 | Color Management | Yes | — | — | Gap |
| 8 | Credential Manager | Yes | — | `parity.credential-manager` missing | Gap |
| 9 | Date and Time | Yes | Superbar clock | — | Partial chrome |
| 10 | Default Programs | Yes | Settings → Apps | `parity.default-programs` / `windows-native.19`; `defaults.protocol.set` browser LIVE only | Prototype browser only; MIME not LIVE |
| 11 | Device Manager | Yes | Administration > Device Manager | `parity.device-manager` / `device.inspect` visible; claim missing | Visible inspect; honest-unavailable as Device Manager product |
| 12 | Devices and Printers | Yes | Administration > Printers and scanners + Settings Bluetooth | `parity.devices-printers`; `printer.inspect` visible; claim missing | Visible inspect / partial BT; honest-unavailable as Devices and Printers product |
| 13 | Display | Yes | Settings → Display | `parity.display` | Prototype |
| 14 | Ease of Access Center | Yes | Settings Accessibility missing | `parity.accessibility` | Honest missing |
| 15 | Folder Options | Yes | — | — | Gap |
| 16 | Fonts | Yes | — | — | Gap |
| 17 | Getting Started / Welcome | Yes | OOBE/setup (separate) | setup flow | Partial product ≠ CP |
| 18 | HomeGroup | Yes | — | — | Gap |
| 19 | Indexing Options | Yes | Start search ≠ content index | `parity.search` | Partial / different |
| 20 | Infrared | HW | — | — | Gap / HW |
| 21 | Internet Options | Yes | — | — | Gap |
| 22 | iSCSI Initiator | Yes | — | — | Gap |
| 23 | Keyboard | Yes | Settings → Input | `input.inspect` / layout set | Partial |
| 24 | Location / Sensors | Win7 limited | — | — | Gap |
| 25 | Mouse | Yes | — | — | Gap |
| 26 | Network and Sharing Center | Yes | Settings → Network | `parity.network` | Prototype |
| 27 | Notification Area Icons | Yes | Superbar tray | product-contracts tray | Partial |
| 28 | Parental Controls | Yes | — | — | Gap |
| 29 | Pen and Touch | HW | — | — | Gap / HW |
| 30 | Performance Information and Tools | Yes | — | — | Gap |
| 31 | Personalization | Yes | Settings → Personalization | `parity.personalization` | Prototype |
| 32 | Phone and Modem | Yes | — | — | Gap |
| 33 | Power Options | Yes | Settings → Power | `parity.power-options` | Prototype; Settings Power LIVE refused; Superbar/QS leftover FAIL on this metal; QS Power METAL_HEAD OPEN |
| 34 | Programs and Features | Yes | Software Center missing as product; Apps inspect | `parity.programs-and-features` / packages.* | Gap / plan_only packages |
| 35 | Recovery | Yes | Settings → Recovery | `recovery.inspect` | Partial inspect; do not invent Restore LIVE |
| 36 | Region and Language | Yes | Settings → Input | `parity.language-locale` | Prototype layout; locale planned |
| 37 | RemoteApp and Desktop Connections | Yes | — | `parity.remote-desktop` missing | Gap |
| 38 | Sound | Yes | Settings → Sound | `parity.sound` | Prototype |
| 39 | Speech Recognition | Yes | — | — | Gap |
| 40 | Sync Center | Yes | — | — | Gap |
| 41 | System | Yes | System information missing page | `system.info.read` missing | Gap |
| 42 | Tablet PC Settings | HW | — | — | Gap / HW |
| 43 | Taskbar and Start Menu | Yes | Superbar + Start | `parity.superbar-taskbar` / `parity.start` | Prototype |
| 44 | Troubleshooting | Yes | Administration > Troubleshooting | `diagnostics.inspect` visible; claim missing | Visible inspect; honest-unavailable as Troubleshooting product |
| 45 | User Accounts | Yes | Administration > User accounts | `parity.user-accounts`; `account.inspect` visible; claim missing | Visible inspect; honest-unavailable as User Accounts product |
| 46 | Windows Anytime Upgrade | Ultimate | N/A (SKU) | — | N/A |
| 47 | Windows CardSpace | Yes (legacy) | — | — | N/A / removed later |
| 48 | Windows Defender | Yes | — | — | Gap |
| 49 | Windows Firewall | Yes | Administration > Firewall | `parity.firewall`; `firewall.inspect` visible; claim missing | Plumbing; visible inspect; honest-unavailable as Firewall Settings product; `firewall.manage` planned/unavailable |
| 50 | Windows Mobility Center | Laptop | — | — | Gap / HW |
| 51 | Windows Update | Yes | Settings → Update | `parity.update` | Prototype inspect |
| 52 | Desktop Gadgets | Yes | — | — | N/A / removed later |

**Related non-CP but Win7 “settings” destinations often confused with CP:**

| Destination | Omarchy | Catalog |
| --- | --- | --- |
| Recycle Bin | Files Trash | `files.trash.restore` write plane is reachable (claim=partial; humanRoute planned empty); `files.trash.manage` write plane is reachable (claim=partial; humanRoute planned empty); Empty Bin LIVE **MUST_FIX** vs product; do not invent Restore LIVE or Empty Bin LIVE |
| Task Manager | Administration > Processes | `process.inspect` visible; claim missing; honest-unavailable as Task Manager product; End Task unauthorized (`terminationAuthorized=false`); do not invent Task Manager present / End Task LIVE |
| Resource Monitor | — | missing |
| Explorer Folder Options | — | Gap |

---

## 5. Settings routes ↔ CP applets (Omarchy Settings)

| Settings route | Win7 CP nearest | Reader / writer |
| --- | --- | --- |
| `settings.overview` | Control Panel home | empty `providerId` |
| `settings.display.overview` | Display | `display.provider` |
| `settings.audio.overview` | Sound | `audio.provider` |
| `settings.network.overview` | Network and Sharing Center | `network.provider` |
| `settings.power.overview` | Power Options | `power.provider` (Settings Power LIVE refused) |
| `settings.bluetooth.overview` | Devices and Printers (BT slice) | `bluetooth.provider` |
| `settings.input.overview` | Keyboard / Region (partial) | `input.provider` |
| `settings.personalization.overview` | Personalization | personalization / wallpaper |
| `settings.apps.overview` | Default Programs / Programs and Features (partial) | `defaults.provider`; `defaults.protocol.set` browser LIVE only |
| `settings.accessibility.overview` | Ease of Access | honest missing (`accessibility.provider` absent) |
| `settings.update.overview` | Windows Update | `update.provider` |
| `settings.recovery.overview` | Recovery / Backup adjacency | `recovery.provider` |
| `settings.system.overview` | System | missing product / empty jump |

---

## 6. Administration routes ↔ Administrative Tools / MMC

Catalog humanRoutes already published **visible**. Residual = product MMC / mutation / Task Manager present still missing, not catalog planned-empty. Phase 9 exit still open; inspect ≠ MMC product present.

| Admin route | Win7 nearest | Catalog honesty |
| --- | --- | --- |
| `administration.overview` | Administrative Tools home | `providerId` `""` (correct empty) |
| `administration.processes.overview` | Task Manager | `process.inspect` **visible** on `Administration > Processes`; claim **missing**; honest-unavailable as Task Manager product; End Task unauthorized (`terminationAuthorized=false`); do not invent Task Manager present / End Task LIVE |
| `administration.services.overview` | Services | `service.inspect` visible on `Administration > Services`; claim missing; honest-unavailable as Services product; no start/stop service LIVE |
| `administration.devices.overview` | Device Manager | `device.inspect` visible on `Administration > Device Manager`; claim missing; honest-unavailable as Device Manager product |
| `administration.storage.overview` | Disk Management (partial) | `storage.inspect` visible on `Administration > Storage`; claim missing; honest-unavailable as Disk Management product |
| `administration.printers.overview` | Devices and Printers | `printer.inspect` visible on `Administration > Printers and scanners`; claim missing; honest-unavailable as Devices and Printers product |
| `administration.backup.overview` | Backup and Restore | `backup.inspect` visible on `Administration > Backup`; claim missing; honest-unavailable as Backup and Restore product; `backup.manage` planned/unavailable |
| `administration.schedule.overview` | Task Scheduler | `schedule.inspect` visible on `Administration > Scheduled tasks`; claim missing; honest-unavailable as Task Scheduler product |
| `administration.troubleshoot.overview` | Troubleshooting | `diagnostics.inspect` visible on `Administration > Troubleshooting`; claim missing; honest-unavailable as Troubleshooting product |
| `administration.firewall.overview` | Windows Firewall | `firewall.inspect` visible on `Administration > Firewall`; claim missing; honest-unavailable as Firewall Settings product; `firewall.manage` planned/unavailable |
| `administration.accounts.overview` | User Accounts | `account.inspect` visible on `Administration > User accounts`; claim missing; honest-unavailable as User Accounts product |

---

## 7. Open Catalog MUST_FIX (carry into this map)

Do not mark claim=`present` to “close” these. Residual = product MMC / mutation / Task Manager present still missing, not catalog planned-empty.

1. **Recycle Bin product vs Empty Bin LIVE / Recycle product-complete.** `files.trash.restore` write plane is reachable (claim=partial; humanRoute planned empty). `files.trash.manage` write plane is reachable (claim=partial; humanRoute planned empty; `emptyBinAuthorized=false`). Recycle Bin / Empty Bin LIVE residual OPEN after PR #63. Residual stays OPEN. Do not invent Restore LIVE or a LIVE Empty Bin. OS clipboard residual OPEN after PR #60. OS clipboard residual OPEN after PR #64. Folder copy CLOSED.  
2. **Task Manager present / End Task LIVE / product MMC still missing.** Catalog `process.inspect` is visible on `Administration > Processes`; claim missing; honest-unavailable as Task Manager product; End Task unauthorized (`terminationAuthorized=false`). Do not invent Task Manager present / End Task LIVE.  
3. **Closed: `parity.agent-center` claim=`prototype` matches `sourceStatus=prototype` / PARITY prototype.** Residual = do not invent claim=`present`; consent/provider ops stay outside Agent Center.
4. **Do not invent MIME Default Programs LIVE** — MIME / Default Programs association UI residual OPEN after PR #62. `files.associations.set` stays missing/planned MIME until Settings + catalog + PARITY agree. Browser writer is `defaults.protocol.set` (browser LIVE only). Do not invent `apps.provider` present.  
5. **Writers stay planned/unavailable** — `firewall.manage`, `backup.manage`, start/stop, printer add, schedule create/disable, format/mount/eject. Inspect visibility is not mutation LIVE.

---

## 8. Coverage summary (Ultimate CP → Omarchy)

| Bucket | Count (approx.) | Meaning |
| --- | --- | --- |
| Prototype / partial Settings or QS | ~12–15 | Display, Sound, Network, Power, Personalization, Update inspect, Input layout, Default browser slice, etc. |
| Visible Administration inspect hosts (claim missing) | ~10 | Processes, Services, Device Manager, Storage, Printers and scanners, Backup, Scheduled tasks, Troubleshooting, Firewall, User accounts — Phase 9 exit still open; inspect ≠ MMC product present |
| Honest missing | Accessibility page, System information jump cleared | Catalog empty paths; Accessibility panel missing as product |
| Hard gaps (no product + missing jobs) | BitLocker, Credential Manager, HomeGroup, Internet Options, AutoPlay, Fonts, Folder Options, Speech, Defender, Mobility Center, Remote Desktop, Parental Controls, … | Ultimate SKU still incomplete |
| Residual honesty (product MMC / mutation still missing) | Recycle Bin vs Empty Bin LIVE; Task Manager present / End Task LIVE; MIME Default Programs; writers planned/unavailable; Agent Center claim stays prototype (do not invent claim=`present`); OS clipboard residual OPEN after PR #60; OS clipboard residual OPEN after PR #64; MIME / Default Programs association UI residual OPEN after PR #62 | Catalog caught up for Admin inspect visibility (#35–#36); Default Programs writer is `defaults.protocol.set` (browser LIVE only); `defaults.mime.set` write plane is reachable; Settings does not offer MIME LIVE CONTROL; `files.trash.restore` write plane is reachable (claim=partial; humanRoute planned empty); `files.trash.manage` write plane is reachable (claim=partial; humanRoute planned empty); Recycle Bin / Empty Bin LIVE residual OPEN after PR #63; folder copy CLOSED; `parity.agent-center` claim matches sourceStatus/PARITY prototype |

---

## 9. Suggested next catalog work (for Lead / Doctrine, not auto-executed)

1. Keep **Default Programs** MIME withheld. Writer is `defaults.protocol.set` (browser LIVE only). `defaults.mime.set` write plane is reachable. Do not invent `apps.provider` present or MIME LIVE.  
2. Sync **PARITY.md** Default Programs / Language / Recycle / Update writer prose to jobs.  
3. Administration humanRoutes already published visible. Residual = product MMC / mutation / Task Manager present still missing, not catalog planned-empty. Do not invent Task Manager present / End Task LIVE / MMC product from inspect hosts.  
4. Raise or withhold **Recycle** catalog claim to match Files Trash.  
5. Keep **BitLocker / Credential Manager / Programs and Features** as missing until Software Center / encryption surfaces exist — do not point them at Settings Apps alone. Software Center missing as product.
