# 05 — Control Panel (Win7 Ultimate)
**Repo path:** `plans/win7-ultimate-ground-truth/05-control-panel.md`  **Research sources:** `research/04-CONTROL-PANEL.md` + `.json`, `fleet-catalog-controlpanel.md`  **Target phases:** Phase 5 (Settings analogs), Phase 9 (Admin Tools)  **DPI baseline:** **96 DPI / 100%**
---
## Purpose
Exhaustive Win7 Ultimate Control Panel IA: Category vs All Items views, eight categories, **55** applets with canonical names, and Omarchy surface mapping so implementers never invent applet lists or mark missing pages `present`.
---
## Binding metrics / chrome
| Property | BINDING |
|----------|---------|
| Host | `control.exe` / Explorer Control Panel namespace |
| Views | **Category** (default) · **Large icons** · **Small icons** |
| View by | Top-right dropdown; persists per user |
| Search | Upper-right; matches names, task links, keywords |
| Address | Explorer breadcrumbs (`Control Panel`, `…\All Control Panel Items`) |
| Launch | `control.exe /name Microsoft.<Item> [/page …]` |
| Window chrome | SSD — visual top **30**; `SM_CYCAPTION` **22** metric only |

### Eight categories

- **System and Security** (id 5) — Was System and Maintenance on Vista.
- **Network and Internet** (id 3)
- **Hardware and Sound** (id 2)
- **Programs** (id 8)
- **User Accounts and Family Safety** (id 9) — On domain: User Accounts (no Family Safety).
- **Appearance and Personalization** (id 1)
- **Clock, Language, and Region** (id 6)
- **Ease of Access** (id 7)

---

## Interaction matrix

| Gesture | Result |
|---------|--------|
| Open from Start → Control Panel | Category home |
| View by change | Switch Category / Large / Small icons |
| Search box type | Filter applets + task links |
| Click category / task link | Navigate / open applet |
| Click applet (All Items) | Open applet |
| Back / Forward / Up | Explorer navigation |

---

## All Control Panel Items (55) — BINDING inventory

| # | Display | Canonical |
|---|---------|----------|
| 1 | Action Center | `Microsoft.ActionCenter` |
| 2 | Administrative Tools | `Microsoft.AdministrativeTools` |
| 3 | AutoPlay | `Microsoft.AutoPlay` |
| 4 | Backup and Restore | `Microsoft.BackupAndRestore` |
| 5 | Biometric Devices | `Microsoft.BiometricDevices` |
| 6 | BitLocker Drive Encryption | `Microsoft.BitLockerDriveEncryption` |
| 7 | Color Management | `Microsoft.ColorManagement` |
| 8 | Credential Manager | `Microsoft.CredentialManager` |
| 9 | Date and Time | `Microsoft.DateAndTime` |
| 10 | Default Programs | `Microsoft.DefaultPrograms` |
| 11 | Desktop Gadgets | `Microsoft.DesktopGadgets` |
| 12 | Device Manager | `Microsoft.DeviceManager` |
| 13 | Devices and Printers | `Microsoft.DevicesAndPrinters` |
| 14 | Display | `Microsoft.Display` |
| 15 | Ease of Access Center | `Microsoft.EaseOfAccessCenter` |
| 16 | Folder Options | `Microsoft.FolderOptions` |
| 17 | Fonts | `Microsoft.Fonts` |
| 18 | Game Controllers | `—` |
| 19 | Getting Started | `Microsoft.GettingStarted` |
| 20 | HomeGroup | `Microsoft.HomeGroup` |
| 21 | Indexing Options | `Microsoft.IndexingOptions` |
| 22 | Infrared | `Microsoft.Infrared` |
| 23 | Internet Options | `Microsoft.InternetOptions` |
| 24 | iSCSI Initiator | `Microsoft.iSCSIInitiator` |
| 25 | Keyboard | `Microsoft.Keyboard` |
| 26 | Mouse | `Microsoft.Mouse` |
| 27 | Network and Sharing Center | `Microsoft.NetworkAndSharingCenter` |
| 28 | Notification Area Icons | `Microsoft.NotificationAreaIcons` |
| 29 | Parental Controls | `Microsoft.ParentalControls` |
| 30 | Pen and Touch | `Microsoft.PenAndTouch` |
| 31 | People Near Me | `Microsoft.PeopleNearMe` |
| 32 | Performance Information and Tools | `Microsoft.PerformanceInformationAndTools` |
| 33 | Personalization | `Microsoft.Personalization` |
| 34 | Phone and Modem | `Microsoft.PhoneAndModem` |
| 35 | Power Options | `Microsoft.PowerOptions` |
| 36 | Programs and Features | `Microsoft.ProgramsAndFeatures` |
| 37 | Recovery | `Microsoft.Recovery` |
| 38 | Region and Language | `Microsoft.RegionAndLanguage` |
| 39 | RemoteApp and Desktop Connections | `Microsoft.RemoteAppAndDesktopConnections` |
| 40 | Scanners and Cameras | `—` |
| 41 | Sound | `Microsoft.Sound` |
| 42 | Speech Recognition | `Microsoft.SpeechRecognition` |
| 43 | Sync Center | `Microsoft.SyncCenter` |
| 44 | System | `Microsoft.System` |
| 45 | Tablet PC Settings | `Microsoft.TabletPCSettings` |
| 46 | Taskbar and Start Menu | `Microsoft.TaskbarAndStartMenu` |
| 47 | Troubleshooting | `Microsoft.Troubleshooting` |
| 48 | User Accounts | `Microsoft.UserAccounts` |
| 49 | Windows Anytime Upgrade | `Microsoft.WindowsAnytimeUpgrade` |
| 50 | Windows CardSpace | `Microsoft.CardSpace` |
| 51 | Windows Defender | `Microsoft.WindowsDefender` |
| 52 | Windows Firewall | `Microsoft.WindowsFirewall` |
| 53 | Windows Mobility Center | `Microsoft.MobilityCenter` |
| 54 | Windows SideShow | `Microsoft.WindowsSideShow` |
| 55 | Windows Update | `Microsoft.WindowsUpdate` |

**Ultimate SKU highlights:** BitLocker present; Parental Controls present; Anytime Upgrade present; HW-gated: Biometric, Infrared, Pen and Touch, Tablet PC, Mobility Center.

### Category → featured items (implementer map)

**System and Security:** Action Center, Windows Firewall, System, Windows Update, Power Options, Backup and Restore, BitLocker, Administrative Tools  
**Network and Internet:** Network and Sharing Center, Homegroup, Internet Options  
**Hardware and Sound:** Devices and Printers, AutoPlay, Sound, Power Options, Display, Mobility Center  
**Programs:** Programs and Features, Default Programs, Desktop Gadgets  
**User Accounts and Family Safety:** User Accounts, Parental Controls, CardSpace, Credential Manager  
**Appearance and Personalization:** Personalization, Display, Desktop Gadgets, Taskbar and Start Menu, Ease of Access, Folder Options, Fonts  
**Clock, Language, and Region:** Date and Time, Region and Language  
**Ease of Access:** Ease of Access Center, Speech Recognition  

---

## Win7 vs Omarchy notes

| Win7 | Omarchy analog |
|------|----------------|
| Control Panel home | `org.omarchy.Settings` |
| Applets | Settings routes / Admin / Superbar panels |
| Administrative Tools | Administration app (planned) |
| Default Programs | Settings → Apps (`defaults.provider`) |
| BitLocker / Parental / many applets | **Missing** — do not invent UI from inspect alone |

**Anti-invent (fleet-doctrine-gaps):** Jump list must omit provider-less Accessibility/System information; Task Manager not inventable as LIVE End Task under shell consequential; `apps.defaults.set` retarget to `defaults.provider`.

---

## Citations

- Microsoft Learn Control Panel canonical names / executing items / categories  
- `04-CONTROL-PANEL.md/.json`, `fleet-catalog-controlpanel.md`

---

## Open metal-verify items

1. Confirm 55-item flat list vs clean Ultimate SP1 EN-US All Items (HW-gated may hide).  
2. Domain vs non-domain User Accounts category title.  
3. Deep_specs page names for Display / Personalization / Sound / Network on metal.  
4. God Mode CLSID completeness vs All Items.
