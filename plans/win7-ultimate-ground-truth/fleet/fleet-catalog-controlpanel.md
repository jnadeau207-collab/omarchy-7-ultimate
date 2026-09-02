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
| Administrative Tools folder | `org.omarchy.Administration` (+ MMC-class tools still missing as product) |
| Default Programs | Settings → Apps (`defaults.provider`); MIME associations still under-claimed |
| Recycle Bin | Files Trash routes / `files.trash.*` plane (catalog `files.trash.manage` still missing) |

---

## 2. Category view → Omarchy map

### 2.1 System and Security

| Win7 item | Canonical / notes | Omarchy surface | Catalog / jobs | Provider truth |
| --- | --- | --- | --- | --- |
| Action Center | `Microsoft.ActionCenter` | Partial: Notification Center + Superbar update/security cues; **no** Action Center applet | `parity.event-history` prototype (`events.history.read`); no `action-center.*` | No Action Center provider |
| Windows Firewall | `Microsoft.WindowsFirewall` | Administration → Firewall (planned host); Settings network firewall path empty | `parity.firewall` plumbing; `firewall.manage` partial/legacy-direct; reader `firewall.inspect` missing→Admin | `firewall.provider` |
| System | `Microsoft.System` | Settings jump **System information** dropped; Admin/system info missing | `system.info.read` missing; `windows-native.38` jump-list leftover vs empty catalog path | No `system-information.provider` product page |
| Windows Update | `Microsoft.WindowsUpdate` | Settings → Update | `parity.update` prototype; `update.inspect` partial; `update.install` / history writers Phase-5/pending | `update.provider` |
| Power Options | `Microsoft.PowerOptions` | Settings → Power; Superbar/QS Power leftover | `parity.power-options` prototype; `power.inspect`; `power.profile.set` write plane not Settings LIVE (fabric polkit `app.slice`); QS Process leftover unverified on metal | `power.provider` (session_operable=False) |
| Backup and Restore | `Microsoft.BackupAndRestore` | Administration → Backup (planned); Settings Recovery | `parity.backup-restore` / `parity.system-restore` plumbing; `backup.inspect` missing | `backup.provider` / `recovery.provider` |
| BitLocker Drive Encryption | `Microsoft.BitLockerDriveEncryption` (**Ultimate**) | **Missing** product | `parity.drive-encryption` missing; `storage.encryption.manage` | No encryption writer surface |
| Administrative Tools | `Microsoft.AdministrativeTools` (folder) | Administration app (partial stand-in) | See §4 | Mix of leaf inspect providers |

**Administrative Tools (folder contents) — Ultimate:**

| Tool | Omarchy map | Catalog / jobs |
| --- | --- | --- |
| Event Viewer | Notification history / capability ledger only | `parity.event-history` prototype — **not** Event Viewer |
| Task Scheduler | Administration → Scheduled tasks (planned) | `parity.task-scheduler` missing; `schedule.inspect` planned Admin |
| Services | Administration → Services | `parity.services` missing; `service.inspect` planned |
| Computer Management / Disk Management | Administration → Storage (planned) | `parity.disk-management` missing; `storage.inspect` planned |
| Performance / Resource Monitor | **Missing** (btop TUI only) | `parity.resource-monitor` missing; `resources.inspect` missing |
| Task Manager (often reached via Ctrl+Shift+Esc, not only Admin Tools) | Administration → Processes named Task Manager | **MUST_FIX:** invent vs `parity.task-manager` missing / `process.inspect` planned empty path |
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
| Devices and Printers | Administration → Printers; Bluetooth in Settings | `parity.devices-printers` missing/prototype; `printer.inspect` planned Admin; `printers.manage` missing | `printer.provider` / `bluetooth.provider` |
| Device Manager | Administration → Device Manager | `parity.device-manager` missing; `device.inspect` planned Admin | `device.provider` |
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
| Programs and Features | Settings → Apps (read defaults); Software Center **missing** as product | `parity.programs-and-features` missing; `software.*` / packages inspect claim Software Center paths | `packages.provider` plan_only; `apps.provider` **invented** on `apps.defaults.set` |
| Default Programs | Settings → Apps | See **§3** | `defaults.provider` (real); catalog still names `apps.defaults.set` |
| Desktop Gadgets | N/A (Win7 feature; removed later) | No Omarchy gadget surface | — |

### 2.5 User Accounts and Family Safety

| Win7 item | Omarchy surface | Catalog / jobs | Provider |
| --- | --- | --- | --- |
| User Accounts | Administration → Accounts (planned) | `parity.user-accounts` missing; `account.inspect` planned Admin | `account.provider` |
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
| Change default browser (protocol http/https) | Settings → Apps drives `defaults.provider` `protocol.set` (typed plane) | `windows-native.19` claim **prototype** (not present); `parity.default-programs` claim **prototype** but `sourceStatus` still **missing**; PARITY.md prose still “cannot set” — **stale** |
| MIME / file associations | Plane: `defaults.mime.set` exists; Settings MIME UI not a full Default Programs | `files.associations.set` **missing**; File associations parity **missing as product** — do **not** invent MIME Default Programs LIVE |
| AutoPlay | **Missing** | No catalog |
| SPAD / program access | **Missing** | No catalog |
| Catalog ID used by jobs | Jobs still list `apps.defaults.set` | **MUST_FIX:** retarget to `defaults.provider` / `defaults.protocol.set` (or rename); stop inventing `apps.provider` **present** |

---

## 4. All Control Panel Items (flat inventory)

Complete Win7-family applet set relevant to **Ultimate client** (excluding Server-only iSNS/MPIO). Status = Omarchy product honesty vs catalog.

| # | Applet | Ultimate? | Omarchy analog | Primary jobs / caps | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Action Center | Yes | NC / Superbar cues only | `parity.event-history` | Gap |
| 2 | Administrative Tools | Yes | Administration app (partial) | Admin readers planned | Partial / invent risk on Task Manager naming |
| 3 | AutoPlay | Yes | — | — | Gap |
| 4 | Backup and Restore | Yes | Admin Backup / Recovery | `parity.backup-restore` plumbing | Gap |
| 5 | Biometric Devices | HW | — | — | Gap / HW |
| 6 | BitLocker Drive Encryption | **Ultimate** | — | `parity.drive-encryption` missing | Gap |
| 7 | Color Management | Yes | — | — | Gap |
| 8 | Credential Manager | Yes | — | `parity.credential-manager` missing | Gap |
| 9 | Date and Time | Yes | Superbar clock | — | Partial chrome |
| 10 | Default Programs | Yes | Settings → Apps | `parity.default-programs` / `windows-native.19` | Prototype browser only; MIME not LIVE |
| 11 | Device Manager | Yes | Admin → Devices | `parity.device-manager` / `device.inspect` | Planned Admin |
| 12 | Devices and Printers | Yes | Admin Printers + Settings Bluetooth | `parity.devices-printers` | Gap / partial BT |
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
| 33 | Power Options | Yes | Settings → Power | `parity.power-options` | Prototype |
| 34 | Programs and Features | Yes | Software Center missing; Apps inspect | `parity.programs-and-features` / packages.* | Gap / plan_only packages |
| 35 | Recovery | Yes | Settings → Recovery | `recovery.inspect` | Partial inspect |
| 36 | Region and Language | Yes | Settings → Input | `parity.language-locale` | Prototype layout; locale planned |
| 37 | RemoteApp and Desktop Connections | Yes | — | `parity.remote-desktop` missing | Gap |
| 38 | Sound | Yes | Settings → Sound | `parity.sound` | Prototype |
| 39 | Speech Recognition | Yes | — | — | Gap |
| 40 | Sync Center | Yes | — | — | Gap |
| 41 | System | Yes | System information missing page | `system.info.read` missing | Gap |
| 42 | Tablet PC Settings | HW | — | — | Gap / HW |
| 43 | Taskbar and Start Menu | Yes | Superbar + Start | `parity.superbar-taskbar` / `parity.start` | Prototype |
| 44 | Troubleshooting | Yes | Admin → Troubleshooting | `diagnostics.inspect` planned | Planned |
| 45 | User Accounts | Yes | Admin → Accounts | `parity.user-accounts` | Planned |
| 46 | Windows Anytime Upgrade | Ultimate | N/A (SKU) | — | N/A |
| 47 | Windows CardSpace | Yes (legacy) | — | — | N/A / removed later |
| 48 | Windows Defender | Yes | — | — | Gap |
| 49 | Windows Firewall | Yes | Admin Firewall | `parity.firewall` | Plumbing |
| 50 | Windows Mobility Center | Laptop | — | — | Gap / HW |
| 51 | Windows Update | Yes | Settings → Update | `parity.update` | Prototype inspect |
| 52 | Desktop Gadgets | Yes | — | — | N/A / removed later |

**Related non-CP but Win7 “settings” destinations often confused with CP:**

| Destination | Omarchy | Catalog |
| --- | --- | --- |
| Recycle Bin | Files Trash | `files.trash.manage` **MUST_FIX** missing vs product |
| Task Manager | Administration Processes | **MUST_FIX** invent |
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
| `settings.power.overview` | Power Options | `power.provider` |
| `settings.bluetooth.overview` | Devices and Printers (BT slice) | `bluetooth.provider` |
| `settings.input.overview` | Keyboard / Region (partial) | `input.provider` |
| `settings.personalization.overview` | Personalization | personalization / wallpaper |
| `settings.apps.overview` | Default Programs / Programs and Features (partial) | `defaults.provider` |
| `settings.accessibility.overview` | Ease of Access | honest missing (`accessibility.provider` absent) |
| `settings.update.overview` | Windows Update | `update.provider` |
| `settings.recovery.overview` | Recovery / Backup adjacency | `recovery.provider` |
| `settings.system.overview` | System | missing product / empty jump |

---

## 6. Administration routes ↔ Administrative Tools / MMC

| Admin route | Win7 nearest | Catalog honesty |
| --- | --- | --- |
| `administration.overview` | Administrative Tools home | `providerId` `""` (correct empty) |
| `administration.processes.overview` | Task Manager | **MUST_FIX** invent vs planned `process.inspect` |
| `administration.services.overview` | Services | `service.inspect` planned |
| `administration.devices.overview` | Device Manager | `device.inspect` planned |
| `administration.storage.overview` | Disk Management (partial) | `storage.inspect` planned |
| `administration.printers.overview` | Devices and Printers | `printer.inspect` planned |
| `administration.backup.overview` | Backup and Restore | `backup.inspect` missing |
| `administration.schedule.overview` | Task Scheduler | `schedule.inspect` planned |
| `administration.troubleshoot.overview` | Troubleshooting | `diagnostics.inspect` planned |
| `administration.firewall.overview` | Windows Firewall | `firewall.inspect` planned |
| `administration.accounts.overview` | User Accounts | `account.inspect` planned |

---

## 7. Open Catalog MUST_FIX (carry into this map)

Do not mark claim=`present` to “close” these.

1. **`apps.defaults.set` → invent `apps.provider` present** while Settings drives `defaults.provider` `protocol.set`. Retarget or rename; sync PARITY Default Programs; align `parity.default-programs` `sourceStatus`.  
2. **Recycle Bin product vs `files.trash.manage` missing / provider-missing.**  
3. **Administration Task Manager invent** vs `parity.task-manager` missing / `process.inspect` planned empty path.  
4. **`parity.agent-center` claim=`missing` vs `sourceStatus=prototype` / PARITY prototype.**  
5. **Do not invent MIME Default Programs LIVE** — `files.associations.set` / File associations stay missing until Settings + catalog + PARITY agree.

---

## 8. Coverage summary (Ultimate CP → Omarchy)

| Bucket | Count (approx.) | Meaning |
| --- | --- | --- |
| Prototype / partial Settings or QS | ~12–15 | Display, Sound, Network, Power, Personalization, Update inspect, Input layout, Default browser slice, etc. |
| Planned Administration inspect hosts | ~8–10 | Accounts, Devices, Printers, Storage, Services, Schedule, Firewall, Diagnostics, Backup |
| Honest missing | Accessibility page, System information jump cleared | Catalog empty paths |
| Hard gaps (no product + missing jobs) | BitLocker, Credential Manager, HomeGroup, Internet Options, AutoPlay, Fonts, Folder Options, Speech, Defender, Mobility Center, Remote Desktop, Parental Controls, … | Ultimate SKU still incomplete |
| Honesty debt (product ahead of catalog/PARITY) | Task Manager naming, Recycle Bin, Default Programs ID/provider split | Catalog MUST_FIX |

---

## 9. Suggested next catalog work (for Lead / Doctrine, not auto-executed)

1. Close **Default Programs** ID honesty (`defaults.protocol.set` / `defaults.provider`) without raising MIME to LIVE.  
2. Sync **PARITY.md** Default Programs / Language / Recycle / Update writer prose to jobs.  
3. Either publish honest **Administration** humanRoutes for real inspect hosts or stop Task Manager product naming.  
4. Raise or withhold **Recycle** catalog claim to match Files Trash.  
5. Keep **BitLocker / Credential Manager / Programs and Features** as missing until Software Center / encryption surfaces exist — do not point them at Settings Apps alone.

