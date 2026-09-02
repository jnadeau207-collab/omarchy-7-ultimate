---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# 04 — Windows 7 Ultimate Control Panel (ground research)

**Doc:** 04-CONTROL-PANEL
**SKU:** Windows 7 Ultimate (x86/x64), English UI as reference
**Generated for:** Phase 5 Settings / Phase 6 Files / Phase 9 Administration implementers
**Authority:** docs/project-ultimate.md Phase 5, 6, 9, docs/WINDOWS_7_ULTIMATE_PARITY.md

> Synthesized from `04-CONTROL-PANEL.json` + fleet-catalog when MD writer stalled. Prefer JSON for machine fields.

## Citations
- Canonical Names of Control Panel Items: https://learn.microsoft.com/en-us/windows/win32/shell/controlpanel-canonical-names
- Executing Control Panel Items: https://learn.microsoft.com/en-us/windows/win32/shell/executing-control-panel-items
- Assigning Control Panel Categories: https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/cc144183(v=vs.85)
- IOpenControlPanel::GetCurrentView: https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iopencontrolpanel-getcurrentview
- Creating Searchable Task Links for a Control Panel Item: https://learn.microsoft.com/en-us/windows/win32/shell/creating-searchable-task-links
- How to Register Executable Control Panel Items: https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/hh127450(v=vs.85)
- How to Register DLL Control Panel Items: https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/hh127454(v=vs.85)
- Guided Help: Customize the notification area in Windows 7: https://support.microsoft.com/en-us/topic/guided-help-customize-the-notification-area-in-windows-7-508f3b7d-435d-2aea-d189-0d4b2d6eca13
- Where is the old style control panel with 30+ small icons…: https://learn.microsoft.com/en-us/answers/questions/2430492/where-is-the-old-style-control-panel-with-30-small
- bitlocker for Windows 7 Home Premium: https://learn.microsoft.com/en-us/answers/questions/2641345/bitlocker-for-windows-7-home-premium

## Shell / views
```json
{
  "host": "control.exe / Explorer shell namespace Control Panel",
  "views": {
    "category": {
      "api": "CPVIEW_CATEGORY / CPVIEW_HOME (0x1)",
      "ui": "Eight category groups with task links under items; View by: Category",
      "address_bar_example": "Control Panel"
    },
    "large_icons": {
      "api": "CPVIEW_CLASSIC / CPVIEW_ALLITEMS (0x0) with Large icons presentation",
      "ui": "All Control Panel Items, large icons; View by: Large icons",
      "address_bar_example": "Control Panel\\All Control Panel Items"
    },
    "small_icons": {
      "api": "Same All Items view with Small icons",
      "ui": "All Control Panel Items, small icons; View by: Small icons",
      "address_bar_example": "Control Panel\\All Control Panel Items"
    }
  },
  "chrome": {
    "address_bar": "Explorer-style breadcrumb; type Control Panel paths; navigate categories and All Items",
    "search": "Upper-right Search Control Panel box; matches item names, task-link titles, and keywords (prefix match); results show tasks and applets",
    "view_by": "Top-right dropdown: Category | Large icons | Small icons; persists per user last session unless policy ForceClassicControlPanel / Always open All Control Panel Items",
    "navigation": "Back/Forward, Up to parent category, green Go arrow legacy behavior as Explorer"
  },
  "launch_mechanisms": {
    "canonical": "control.exe /name Microsoft.<Item> [/page <pageName>]",
    "cpl": "control.exe foo.cpl  OR  control.exe foo.cpl,,<tabIndex>  OR  rundll32 shell32.dll,Control_RunDLL foo.cpl,@n,i",
    "msc": "mmc snap-ins e.g. devmgmt.msc, services.msc, firewall.cpl\u2192WF.msc advanced",
    "rundll": "rundll32.exe shell32.dll,Options_RunDLL <n> (Folder Options); rundll32 shell32.dll,Control_RunDLL \u2026",
    "exe": "Dedicated exes e.g. SystemPropertiesAdvanced.exe, DpiScaling.exe, OptionalFeatures.exe, mblctr.exe, colorcpl.exe, sdclt.exe",
    "shell_guid": "explorer shell:::{CLSID} God Mode / direct item CLSID",
    "api": "IOpenControlPanel::Open / WinExec control.exe"
  },
  "category_ids": [
    {
      "id": 5,
      "name": "System and Security",
      "notes": "Was System and Maintenance on Vista."
    },
    {
      "id": 3,
      "name": "Network and Internet",
      "notes": null
    },
    {
      "id": 2,
      "name": "Hardware and Sound",
      "notes": null
    },
    {
      "id": 8,
      "name": "Programs",
      "notes": null
    },
    {
      "id": 9,
      "name": "User Accounts and Family Safety",
      "notes": "On domain: User Accounts (no Family Safety)."
    },
    {
      "id": 1,
      "name": "Appearance and Personalization",
      "notes": null
    },
    {
      "id": 6,
      "name": "Clock, Language, and Region",
      "notes": null
    },
    {
      "id": 7,
      "name": "Ease of Access",
      "notes": null
    }
  ]
}
```

## SKU notes
```json
{
  "ultimate_vs_home_premium_control_panel": [
    {
      "item": "BitLocker Drive Encryption",
      "ultimate": "Present (Microsoft.BitLockerDriveEncryption)",
      "home_premium": "Absent \u2014 BitLocker ships only with Ultimate and Enterprise",
      "citation": "ms-bitlocker-sku"
    },
    {
      "item": "Region and Language \u2014 display languages (MUI)",
      "ultimate": "Can install Multilingual User Interface language packs",
      "home_premium": "Limited language pack capability vs Ultimate/Enterprise MUI",
      "citation": "ms-canonical"
    },
    {
      "item": "System Properties \u2014 Computer Name domain join",
      "ultimate": "Can join a domain (with Professional/Enterprise feature set)",
      "home_premium": "Workgroup only; domain join UI unavailable",
      "citation": "ms-executing"
    },
    {
      "item": "System Properties \u2014 Remote tab Remote Desktop host",
      "ultimate": "Can enable Remote Desktop host",
      "home_premium": "Remote Assistance only; RDP host not available",
      "citation": "ms-executing"
    },
    {
      "item": "Parental Controls",
      "ultimate": "Available when not domain-joined; domain join hides Family Safety path",
      "home_premium": "Available (typical home use)",
      "citation": "ms-categories"
    },
    {
      "item": "HomeGroup",
      "ultimate": "Create or join",
      "home_premium": "Create or join (same for Home Premium+)",
      "citation": "ms-canonical"
    },
    {
      "item": "Personalization / Aero",
      "ultimate": "Full Personalization + Aero glass",
      "home_premium": "Also full Personalization + Aero (Starter/Basic lack Personalization)",
      "citation": "ms-executing"
    },
    {
      "item": "Windows Anytime Upgrade",
      "ultimate": "Applet may appear but SKU already highest retail",
      "home_premium": "Primary upgrade path to Professional/Ultimate",
      "citation": "ms-canonical"
    }
  ],
  "hardware_conditional": [
    "Windows Mobility Center (mobile PCs)",
    "Pen and Touch / Tablet PC Settings",
    "Biometric Devices",
    "Infrared",
    "Phone and Modem (modems)",
    "Scanners and Cameras when WIA devices present"
  ],
  "not_invented": [
    "No Windows 8+ only items as Win7 applets: File History, Storage Spaces, Work Folders, Windows To Go, Location Settings, Language (split), Taskbar (Win8 rename)",
    "No third-party vendor CPLs as inbox inventory"
  ]
}
```

## Complete applet inventory

| Display name | Canonical | Category | Opens | Top jobs |
|---|---|---|---|---|
|  | Microsoft.ActionCenter |  | `ActionCenterCPL.dll / control /name Microsoft.ActionCenter (also wscui.cpl legacy)` | Review security and maintenance messages; Change Action Center settings; Open Windows Update / Firewall / Defender / Backup / Troubleshooting / Recovery / User Account Control settings from message links; View archived messages; Open Reliability Monitor; Configure problem reporting |
|  | Microsoft.AdministrativeTools |  | `shell folder via shell32 (control admintools) — Computer Management, Event Viewer, Services, Task Scheduler, etc.` | Open Computer Management; Open Event Viewer; Open Services; Open Task Scheduler; Open Performance Monitor; Open System Configuration |
|  | Microsoft.AutoPlay |  | `autoplay.dll / control /name Microsoft.AutoPlay` | Choose default AutoPlay action per media/device type; Use AutoPlay for all media and devices on/off; Reset all defaults |
|  | Microsoft.BackupAndRestore |  | `sdclt.exe / control /name Microsoft.BackupAndRestore (GUID {B98A2BEA-7D42-4558-8BD1-832F41BAC6FD})` | Set up backup; Change backup settings / schedule; Back up now; Restore my files; Restore all users' files; Select another backup to restore files from |
|  | Microsoft.BiometricDevices |  | `biocpl.dll` | Change biometric settings; Manage fingerprint data; Enable/disable biometrics |
|  | Microsoft.BitLockerDriveEncryption |  | `fvecpl.dll / control /name Microsoft.BitLockerDriveEncryption` | Turn on BitLocker for OS drive; Turn on BitLocker for fixed data drives; Manage BitLocker (password/PIN/recovery key); Turn off BitLocker; Suspend protection; Unlock encrypted removable drives (BitLocker To Go) |
|  | Microsoft.ColorManagement |  | `colorcpl.exe` | View devices and profiles; Add/remove ICC profiles; Set default profile; Advanced color management settings |
|  | Microsoft.CredentialManager |  | `Vault.dll / control /name Microsoft.CredentialManager` | Manage Windows Credentials; Manage Certificate-Based Credentials; Add a Windows credential; Remove / edit stored credentials; Back up / restore credentials vault |
|  | Microsoft.DateAndTime |  | `timedate.cpl` | Change date and time; Change time zone; Additional Clocks; Internet Time sync settings |
|  | Microsoft.DefaultPrograms |  | `sud.dll / control /name Microsoft.DefaultPrograms` | Set your default programs; Associate a file type or protocol with a program; Change AutoPlay settings; Set program access and computer defaults |
|  | Microsoft.DesktopGadgets |  | `sidebar / gadgets platform` | Add gadgets to desktop; Get more gadgets online; Show/restore gadgets; Gadget opacity / always on top (gadget UI) |
|  | Microsoft.DeviceManager |  | `devmgmt.msc / hdwwiz.cpl / control /name Microsoft.DeviceManager` | Browse devices by type/connection; Update driver software; Disable / enable device; Uninstall device; Scan for hardware changes; View device Properties (General, Driver, Details, Events, Resources, Power Management) |
|  | Microsoft.DevicesAndPrinters |  | `DeviceCenter.dll / control printers / control /name Microsoft.DevicesAndPrinters` | Add a device; Add a printer; See what's printing; Set as default printer; Printer properties / Printing preferences; Device properties / troubleshoot |
|  | Microsoft.Display |  | `Display.dll / desk.cpl Settings / control /name Microsoft.Display` | Make text and other items larger or smaller (100/125/150%); Set custom DPI; Adjust resolution; Change orientation; Detect / Identify displays; Multiple displays mode (Duplicate / Extend / Show desktop only on…) |
|  | Microsoft.EaseOfAccessCenter |  | `accessibilitycpl.dll / Utilman / control /name Microsoft.EaseOfAccessCenter` | Start Magnifier; Start Narrator; Start On-Screen Keyboard; Set up High Contrast; Get recommendations to make your computer easier to use; Use the computer without a display |
|  | Microsoft.FolderOptions |  | `shell32 Options_RunDLL / control folders` | Browse folders in same/own window; Click items: single vs double; Restore Defaults (General); Show/hide hidden files; Hide extensions for known file types; Use Sharing Wizard |
|  | Microsoft.Fonts |  | `Fonts folder / control fonts` | Preview fonts; Install/delete fonts; Hide fonts based on language settings; Font settings (allow fonts to be installed using shortcuts etc.) |
|  |  |  | `joy.cpl` | Add/remove game controllers; Properties / calibrate; Advanced controller settings |
|  | Microsoft.GettingStarted |  | `Getting Started / Welcome Center successor` | Go online to find out what's new; Personalize Windows; Transfer files and settings; Add new users; Back up your files; Change the size of text on your screen |
|  | Microsoft.HomeGroup |  | `hgcpl.dll / control /name Microsoft.HomeGroup` | Create a homegroup; Join a homegroup; Change what you share (Pictures, Music, Videos, Documents, Printers); View/print homegroup password; Change the password; Leave the homegroup |
|  | Microsoft.IndexingOptions |  | `srchadmin.dll / control /name Microsoft.IndexingOptions` | Modify indexed locations; Pause indexing; View indexing status / count; Advanced: File Types, Index Settings, Rebuild, Troubleshoot; Index encrypted files / similar advanced toggles |
|  | Microsoft.Infrared |  | `irprops.cpl` | Enable infrared communication; Image transfer options; Hardware properties |
|  | Microsoft.InternetOptions |  | `inetcpl.cpl` | General: home page, browsing history, appearance; Security: zone levels; Privacy: cookies / Pop-up Blocker; Content: Parental Controls / certificates / AutoComplete; Connections: dial-up / LAN / proxy; Programs: default browser / add-ons / HTML editing |
|  | Microsoft.iSCSIInitiator |  | `iscsicpl.dll` | Discover targets; Connect/disconnect iSCSI targets; Configure CHAP/mutual auth; Manage favorite targets; Configure initiator name |
|  | Microsoft.Keyboard |  | `main.cpl Keyboard` | Change character repeat delay/rate; Change cursor blink rate; Open Hardware tab for device properties |
|  | Microsoft.Mouse |  | `main.cpl` | Swap primary/secondary buttons; Change double-click speed; Choose pointer scheme / individual pointers; Pointer Options (speed, Snap To, trails, Hide while typing); Wheel scroll settings; Hardware device properties |
|  | Microsoft.NetworkAndSharingCenter |  | `netcenter.dll / control /name Microsoft.NetworkAndSharingCenter` | View active networks and access type; Connect to a network; Set up a new connection or network; Troubleshoot problems; Change adapter settings (ncpa.cpl); Change advanced sharing settings |
|  | Microsoft.NotificationAreaIcons |  | `taskbarcpl.dll / control /name Microsoft.NotificationAreaIcons` | Show icon and notifications / Show notifications only / Hide icon and notifications per app; Turn system icons on or off; Always show all icons and notifications on the taskbar; Restore default icon behaviors |
|  | Microsoft.ParentalControls |  | `wpccpl.dll / control /name Microsoft.ParentalControls` | Choose a user and set up Parental Controls; Time limits; Game ratings / allow/block games; Allow/block specific programs; Activity reports (as configured) |
|  | Microsoft.PenAndTouch |  | `tabletpc.cpl` | Configure pen actions / flicks; Handwriting settings; Touch input options |
|  | Microsoft.PeopleNearMe |  | `collab.cpl / control /name Microsoft.PeopleNearMe` | Sign in / sign out of People Near Me; Allow invitations; Display name and picture; Sign me in automatically when Windows starts |
|  | Microsoft.PerformanceInformationAndTools |  | `perfcenterCPL.dll / control /name Microsoft.PerformanceInformationAndTools` | View Windows Experience Index base score; Re-run assessment; View advanced tools (Event Viewer, Disk Cleanup, Task Manager, Performance Monitor, Resource Monitor, System Health Report, Performance Options) |
|  | Microsoft.Personalization |  | `themecpl.dll / control /name Microsoft.Personalization` | Apply Aero / Basic / High Contrast / My Themes; Get more themes online; Change desktop background; Change window color (Aero tint, intensity, transparency); Change sounds; Change screen saver |
|  | Microsoft.PhoneAndModem |  | `telephon.cpl` | Set dialing rules / location; Configure modems; Advanced telephony providers |
|  | Microsoft.PowerOptions |  | `powercpl.dll / powercfg.cpl / control /name Microsoft.PowerOptions` | Choose Balanced / Power saver / High performance (or OEM plans); Change plan settings (turn off display / sleep); Change advanced power settings; Choose what the power buttons do; Choose what closing the lid does; Require a password on wakeup |
|  | Microsoft.ProgramsAndFeatures |  | `appwiz.cpl / control /name Microsoft.ProgramsAndFeatures` | Uninstall or change a program; View installed updates; Turn Windows features on or off (OptionalFeatures.exe); Install a program from the network (rare) |
|  | Microsoft.Recovery |  | `recovery.dll / control /name Microsoft.Recovery` | Open System Restore; Open Advanced recovery methods (reimage / reinstall); Create a system repair disc link; Open Backup and Restore |
|  | Microsoft.RegionAndLanguage |  | `intl.cpl / control international` | Formats: date/time/number/currency; Location (Home location); Keyboards and Languages: install/remove display languages (Ultimate MUI), Change keyboards, Language bar; Administrative: system locale / copy settings / welcome screen |
|  | Microsoft.RemoteAppAndDesktopConnections |  | `tsworkspace.dll` | Set up a new connection with RemoteApp and Desktop Connections; View properties of existing connections; Disconnect / remove connections |
|  |  |  | `wiaacmgr / Scanners and Cameras folder (sticpl.cpl legacy)` | Add device; Scan / Get pictures; Properties |
|  | Microsoft.Sound |  | `mmsys.cpl / control /name Microsoft.Sound` | Set default Playback device; Configure speakers / test; Set default Recording device; Configure microphone levels; Change sound scheme / program events; Communications ducking behavior |
|  | Microsoft.SpeechRecognition |  | `speechuxcpl.dll` | Start Speech Recognition; Set up microphone; Take Speech Tutorial; Train your computer to better understand you; Open the Speech Reference Card; Advanced speech options |
|  | Microsoft.SyncCenter |  | `SyncCenter.dll / mobsync.exe` | View sync partnerships; Sync now / Sync all; View sync conflicts; View sync results; Set up new sync partnerships; Manage Offline Files |
|  | Microsoft.System |  | `systemcpl.dll overview → SystemProperties*.exe / sysdm.cpl` | View Windows edition, System rating, processor, RAM, system type; View computer name / workgroup / domain; Open Device Manager; Open Remote settings; Open System Protection; Open Advanced system settings |
|  | Microsoft.TabletPCSettings |  | `tabletpc.cpl` | Configure handedness / calibration; Display options for tablet; Other tablet settings |
|  | Microsoft.TaskbarAndStartMenu |  | `Taskbar and Start Menu Properties (explorer / rundll)` | Lock the taskbar; Auto-hide the taskbar; Use small icons; Taskbar location on screen; Taskbar buttons combine mode; Customize notification area |
|  | Microsoft.Troubleshooting |  | `DiagCpl.dll / control /name Microsoft.Troubleshooting` | Run Programs / Hardware and Sound / Network and Internet / Appearance and Personalization / System and Security troubleshooters; View history; Change settings (including automatic maintenance participation) |
|  | Microsoft.UserAccounts |  | `usercpl.dll / control userpasswords / control /name Microsoft.UserAccounts` | Change your account picture; Change your password; Change your account name; Create a password reset disk; Manage another account; Change account type |
|  | Microsoft.WindowsAnytimeUpgrade |  | `WindowsAnytimeUpgrade UI` | Purchase/upgrade edition features; Enter upgrade key |
|  | Microsoft.CardSpace |  | `Windows CardSpace` | Create/manage information cards; Import/export cards; Delete cards |
|  | Microsoft.WindowsDefender |  | `MSASCui.exe / Windows Defender UI` | Scan (Quick/Full/Custom); View history; Change tools/options; Update definitions |
|  | Microsoft.WindowsFirewall |  | `FirewallControlPanel.dll / control /name Microsoft.WindowsFirewall` | Turn Windows Firewall on or off per network location; Allow a program or feature through Windows Firewall; Restore defaults; Open advanced settings (WF.msc); Check firewall state for Home/Work vs Public |
|  | Microsoft.MobilityCenter |  | `mblctr.exe` | Adjust brightness; Mute/volume; Battery plan; Wireless; External display; Sync Center tile |
|  | Microsoft.WindowsSideShow |  | `Windows SideShow CPL` | Add gadgets for SideShow devices; Configure connected auxiliary displays |
|  | Microsoft.WindowsUpdate |  | `wucltux.dll / control /name Microsoft.WindowsUpdate` | Check for updates; Install updates; Change settings (install automatically / download / check / never); View update history; Restore hidden updates; View installed updates (Programs and Features link) |

## Deep specs (high-traffic applets)

### Personalization

#### canonical
Microsoft.Personalization

#### pages
```json
[
  "pageColorization",
  "pageWallpaper"
]
```

#### ui_regions
```json
[
  "My Themes / Aero Themes / Basic and High Contrast Themes galleries",
  "Bottom links row: Desktop Background | Window Color | Sounds | Screen Saver",
  "Left/secondary: Change desktop icons, Change mouse pointers, Display"
]
```

#### common_dialogs
```json
[
  "Desktop Background: Picture location, Browse, picture fit (Fill/Fit/Stretch/Tile/Center), slideshow shuffle/change picture every\u2026",
  "Window Color and Appearance (Aero): color swatches, Enable transparency, Color intensity, Show color mixer (Hue/Sat/Brightness)",
  "Window Color and Appearance (Basic/Classic): classic element color picker Advanced",
  "Sound Scheme: Program Events list, Test, Browse .wav, Save As scheme",
  "Screen Saver Settings: screensaver dropdown, Wait, On resume display logon screen, Settings, Preview, Power management link"
]
```

#### right_click
```json
[
  "Desktop \u2192 Personalize"
]
```

#### citations
```json
[
  "ms-canonical",
  "ms-executing"
]
```

### Display

#### canonical
Microsoft.Display

#### pages
```json
[
  "Settings (Screen Resolution)"
]
```

#### ui_regions
```json
[
  "Make text and other items larger or smaller: Smaller 100% / Medium 125% / Larger 150%",
  "Set custom text size (DPI) \u2192 DpiScaling.exe / Custom DPI Setting",
  "Left tasks: Adjust resolution, Adjust ClearType text, Calibrate color, Change display settings",
  "Screen Resolution window: Display dropdown, Resolution slider, Orientation, Multiple displays"
]
```

#### common_dialogs
```json
[
  "Custom DPI Setting",
  "ClearType Text Tuner wizard",
  "Display Color Calibration",
  "Screen Resolution Keep/Revert countdown"
]
```

#### citations
```json
[
  "ms-canonical",
  "ms-executing"
]
```

### Sound

#### canonical
Microsoft.Sound

#### module
mmsys.cpl

#### tabs
```json
[
  "Playback",
  "Recording",
  "Sounds",
  "Communications"
]
```

#### ui_regions
```json
[
  "Device list with Default Device / Default Communication Device marks",
  "Configure / Set Default / Properties buttons",
  "Sounds: Sound Scheme + Program Events",
  "Communications: radio options for volume reduction during calls"
]
```

#### right_click
```json
[
  "Show Disabled Devices",
  "Show Disconnected Devices",
  "Test",
  "Set as Default Device",
  "Set as Default Communication Device"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### NetworkAndSharingCenter

#### canonical
Microsoft.NetworkAndSharingCenter

#### pages
```json
[
  "Advanced (advanced sharing settings)",
  "ShareMedia"
]
```

#### ui_regions
```json
[
  "View your active networks (name, Network type Home/Work/Public, Access type, Connections)",
  "Change your networking settings task list",
  "See full map",
  "Change adapter settings \u2192 Network Connections (ncpa.cpl)",
  "Adapter Status dialog: General (IPv4/IPv6 connectivity, Media State, Duration, Speed, Activity), Details, Properties, Disable, Diagnose"
]
```

#### common_dialogs
```json
[
  "Set Network Location",
  "Connect to a network",
  "Set up a connection or network wizard",
  "Network Connection Properties (clients/services/protocols)",
  "TCP/IPv4 Properties / Advanced"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### DevicesAndPrinters

#### canonical
Microsoft.DevicesAndPrinters

#### ui_regions
```json
[
  "Toolbar: Add a device, Add a printer, See what's printing, Print server properties",
  "Device icons (printers, multimedia, portable, unspecified)",
  "Preview pane / device stage for supported devices"
]
```

#### right_click
```json
[
  "Create shortcut",
  "Troubleshoot",
  "Properties",
  "Printer properties",
  "Printing preferences",
  "Set as default printer",
  "Remove device",
  "Eject"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### DeviceManager

#### canonical
Microsoft.DeviceManager

#### opens
devmgmt.msc / hdwwiz.cpl path

#### ui_regions
```json
[
  "Tree by type / connection / resources",
  "Toolbar scan for hardware changes"
]
```

#### right_click
```json
[
  "Update Driver Software",
  "Disable",
  "Enable",
  "Uninstall",
  "Scan for hardware changes",
  "Properties (General/Driver/Details/Events/Resources/Power)"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### ProgramsAndFeatures

#### canonical
Microsoft.ProgramsAndFeatures

#### pages
```json
[
  "{D450A8A1-9568-45C7-9C0E-B4F9FB4537BD} Installed Updates"
]
```

#### ui_regions
```json
[
  "List/details of installed programs",
  "Uninstall/Change/Repair command bar",
  "Turn Windows features on or off",
  "View installed updates"
]
```

#### citations
```json
[
  "ms-canonical",
  "ms-executing"
]
```

### DefaultPrograms

#### canonical
Microsoft.DefaultPrograms

#### pages
```json
[
  "pageDefaultProgram",
  "pageFileAssoc"
]
```

#### ui_regions
```json
[
  "Set your default programs",
  "Associate a file type or protocol with a program",
  "Change AutoPlay settings \u2192 Microsoft.AutoPlay",
  "Set program access and computer defaults (Computer Manufacturer / Microsoft Windows / Custom)"
]
```

#### citations
```json
[
  "ms-canonical",
  "ms-executing"
]
```

### PowerOptions

#### canonical
Microsoft.PowerOptions

#### pages
```json
[
  "pagePlanSettings",
  "pageGlobalSettings",
  "pageCreateNewPlan"
]
```

#### ui_regions
```json
[
  "Preferred plans radio list",
  "Change plan settings",
  "Change advanced power settings tree",
  "Require a password on wakeup",
  "Choose what the power buttons do",
  "Choose what closing the lid does"
]
```

#### legacy
control.exe powercfg.cpl,,3 for Advanced Settings

#### citations
```json
[
  "ms-canonical",
  "ms-executing"
]
```

### System

#### canonical
Microsoft.System

#### overview
systemcpl.dll summary page

#### properties_dialog
sysdm.cpl / SystemProperties*.exe

#### tabs
```json
[
  {
    "name": "Computer Name",
    "exe": "SystemPropertiesComputerName.exe",
    "jobs": [
      "View description",
      "Change computer name",
      "Join domain/workgroup (SKU-dependent)"
    ]
  },
  {
    "name": "Hardware",
    "exe": "SystemPropertiesHardware.exe",
    "jobs": [
      "Device Manager",
      "Device Installation Settings"
    ]
  },
  {
    "name": "Advanced",
    "exe": "SystemPropertiesAdvanced.exe",
    "jobs": [
      "Performance (Visual Effects/Advanced/Data Execution Prevention)",
      "User Profiles",
      "Startup and Recovery",
      "Environment Variables"
    ]
  },
  {
    "name": "System Protection",
    "exe": "SystemPropertiesProtection.exe",
    "jobs": [
      "Configure restore settings / disk space",
      "Create restore point",
      "System Restore"
    ]
  },
  {
    "name": "Remote",
    "exe": "SystemPropertiesRemote.exe",
    "jobs": [
      "Remote Assistance",
      "Remote Desktop host (SKU-dependent)"
    ]
  }
]
```

#### citations
```json
[
  "ms-canonical",
  "ms-executing"
]
```

### UserAccounts

#### canonical
Microsoft.UserAccounts

#### ui_regions
```json
[
  "Make changes to your user account",
  "Create password reset disk",
  "Manage another account",
  "Change User Account Control settings",
  "Manage your credentials"
]
```

#### related
```json
[
  "netplwiz / control userpasswords2 advanced users",
  "lusrmgr.msc on Pro+"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### FolderOptions

#### canonical
Microsoft.FolderOptions

#### tabs
```json
[
  "General",
  "View",
  "Search"
]
```

#### rundll
```json
{
  "General": "rundll32.exe shell32.dll,Options_RunDLL 0",
  "Search": "rundll32.exe shell32.dll,Options_RunDLL 2",
  "View": "rundll32.exe shell32.dll,Options_RunDLL 7"
}
```

#### citations
```json
[
  "ms-canonical",
  "ms-executing"
]
```

### TaskbarAndStartMenu

#### canonical
Microsoft.TaskbarAndStartMenu

#### tabs
```json
[
  "Taskbar",
  "Start Menu",
  "Toolbars"
]
```

#### taskbar_controls
```json
[
  "Lock the taskbar",
  "Auto-hide the taskbar",
  "Use small icons",
  "Taskbar location on screen",
  "Taskbar buttons",
  "Notification area Customize",
  "Use Aero Peek to preview the desktop"
]
```

#### start_menu_controls
```json
[
  "Power button action",
  "Privacy recent programs/items",
  "Customize\u2026 Start Menu settings"
]
```

#### related
```json
[
  "Microsoft.NotificationAreaIcons"
]
```

#### citations
```json
[
  "ms-canonical",
  "ms-notification"
]
```

### WindowsUpdate

#### canonical
Microsoft.WindowsUpdate

#### pages
```json
[
  "pageSettings",
  "pageUpdateHistory"
]
```

#### ui_regions
```json
[
  "Status banner (up to date / updates available)",
  "Install updates",
  "Change settings",
  "View update history",
  "Restore hidden updates",
  "Updates: optional vs important"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### BackupAndRestore

#### canonical
Microsoft.BackupAndRestore

#### ui_regions
```json
[
  "Backup section (Set up backup / Back up now / Manage space)",
  "Restore section (Restore my files)",
  "Left pane: Create a system image, Create a system repair disc, Recover system settings or your computer"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### ActionCenter

#### canonical
Microsoft.ActionCenter

#### pages
```json
[
  "MaintenanceSettings",
  "pageProblems",
  "pageReliabilityView",
  "pageResponseArchive",
  "pageSettings"
]
```

#### ui_regions
```json
[
  "Security messages",
  "Maintenance messages",
  "Change Action Center settings checklist",
  "Archived Messages",
  "Reliability Monitor link"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### EaseOfAccessCenter

#### canonical
Microsoft.EaseOfAccessCenter

#### pages
```json
[
  "pageEasierToClick",
  "pageEasierToSee",
  "pageEasierWithSounds",
  "pageFilterKeysSettings",
  "pageKeyboardEasierToUse",
  "pageNoMouseOrKeyboard",
  "pageNoVisual",
  "pageQuestionsCognitive",
  "pageQuestionsEyesight"
]
```

#### ui_regions
```json
[
  "Quick access start buttons",
  "Explore all settings task links",
  "Recommendation questionnaire"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### RegionAndLanguage

#### canonical
Microsoft.RegionAndLanguage

#### tabs
```json
[
  "Formats",
  "Location",
  "Keyboards and Languages",
  "Administrative"
]
```

#### ultimate_note
Keyboards and Languages → Install/uninstall display languages for MUI packs on Ultimate

#### citations
```json
[
  "ms-canonical",
  "ms-executing"
]
```

### SyncCenter

#### canonical
Microsoft.SyncCenter

#### ui_regions
```json
[
  "Sync partnerships list",
  "Sync conflicts",
  "Sync results",
  "Offline Files management"
]
```

#### citations
```json
[
  "ms-canonical"
]
```

### HomeGroup

#### canonical
Microsoft.HomeGroup

#### ui_regions
```json
[
  "Create/Join status",
  "Libraries and printers to share checkboxes",
  "Password view/print/change",
  "Leave the homegroup",
  "Change advanced sharing settings"
]
```

#### shipped_behavior
Requires network location Home (or compatible); create/join on Home Premium and above; password-protected share model as shipped in Win7

#### citations
```json
[
  "ms-canonical"
]
```

## Phase mapping notes

Map applets to Omarchy Phase 5 Settings / Phase 6 Files defaults / Phase 9 Administration per `plans/project-ultimate.md` and `fleet-catalog-controlpanel.md`.

## Related fleet

- `fleet-catalog-controlpanel.md` — Settings/Admin route tables + catalog MUST_FIX
- `06-SETTINGS-ADMIN-MEDIA.md` — deep Default Programs / MMC / Task Manager
