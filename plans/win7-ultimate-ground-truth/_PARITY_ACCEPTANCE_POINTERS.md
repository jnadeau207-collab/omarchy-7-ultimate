# PARITY Acceptance Pointers — Win7 ground-truth sections

**Purpose:** For each job row in `WINDOWS_7_ULTIMATE_PARITY.md`, point to concrete acceptance criteria in `plans/win7-ultimate-ground-truth/*`.  
**Honesty:** Do **not** rewrite status claims (`missing` / `plumbing` / `prototype` / `present`). Do not mark present. Product remains **REJECTED**.  
**Caption LOCK reminder:** visual top NC **30**; `SM_CYCAPTION` **22** metric only.

Suggested light edit to PARITY.md: add a column **GT pointer** or footnotes linking these anchors — content below is the pointer text.

---

## Desktop jobs

| Job (PARITY row) | Acceptance criteria pointers |
|------------------|------------------------------|
| Desktop (icons, wallpaper, context menu, Recycle) | `04-explorer-dialogs.md` — Desktop context menu order; Recycle Bin matrix; `06-settings-defaults-admin-media.md` — Personalization / Desktop Background; `02-start-menu.md` — user places. Anti-invent: wallpaper-only ≠ Recycle done (`fleet-doctrine-gaps` `parity.desktop-icons-…`). |
| Superbar (taskbar) | `03-superbar-taskbar.md` — height 40, combine modes, Jump Lists, click minimize-active, tray order, Show Desktop ~8–15 px / 1000 ms peek; `07-interaction-grammar.md` — Aero Peek. Forbidden: Task Manager present invent; Close group ≠ Close window confusion. |
| Start | `02-start-menu.md` — two-pane metrics; **BINDING right-pane order** (10 places + Shut down); power flyout order; All Programs in-pane; search grammar. Anti-invent: file-content search; Overview destinations. |
| Search | `02-start-menu.md` — search categories / top-3 / See more results; `07-interaction-grammar.md` — not Spotlight invent. Omarchy published Settings/Agent places = subset honesty. |
| Explorer / Computer | `04-explorer-dialogs.md` — chrome stack, command bar matrix, nav pane, Libraries, Computer groups + capacity bars, views, context menus, drag-drop/delete. |
| Network | `05-control-panel.md` — Network and Sharing Center; `06-…` Settings map; join Wi-Fi separate from radio toggle (`parity.network` invent risk). |
| Personalization | `06-settings-defaults-admin-media.md` — Personalization hub, Window Color, Background positions, Sounds, Screen Saver, pointers. |
| Devices & Printers | `05-control-panel.md` — Devices and Printers applet; `02-start-menu.md` right-pane entry. |
| Device Manager | `06-…` — Computer Management / `devmgmt.msc`; `05-control-panel.md` Device Manager row. Anti-invent from `device.inspect` alone. |
| Programs and Features | `05-control-panel.md` Programs category; Phase 7 Software Center behaviors in `PHASE_BINDINGS.md`. |
| Default Programs | `06-…` — **exact four links** + Set Associations columns + Open With + AutoPlay + SPAD. Browser https = subset only. |
| User Accounts | `05-control-panel.md` / `06-…` Admin Accounts; anti-invent from planned reader. |
| Credential Manager | `05-control-panel.md` Credential Manager row — missing product. |
| Power Options | `05-control-panel.md` Power Options; `06-…`; profile.set ≠ full Power Options. |
| Sound | `06-…` — mmsys tabs + Volume Mixer tray grammar; `07-…` sounds schemes. |
| Display | `05-control-panel.md` Display; `07-…` DPI 100/125/150; brightness-only ≠ complete. |
| Firewall | `05-control-panel.md` Windows Firewall; Admin `wf.msc` — plumbing ≠ Settings invent. |
| Update | `05-control-panel.md` Windows Update; consequential restore-point semantics — plane ≠ `windows-native.28` closed. |
| Backup & Restore | `05-control-panel.md` Backup and Restore; do not collapse into snapshot plumbing. |
| System Restore | `05-control-panel.md` Recovery; `06-…`; inspect ≠ restore UI. |
| Disk Management | `06-…` Computer Management → Storage → Disk Management. |
| Task Manager | `06-…` — Win7 tabs Applications/Processes/Services/Performance/Networking/Users; authorized End Task only. |
| Resource Monitor | `06-…` / Admin Tools Performance — missing; not process CPU fields alone. |
| Services | `06-…` — `services.msc` columns + startup types. |
| Task Scheduler | `06-…` — `taskschd.msc` / Computer Management node. |
| Event / history | `03-superbar-taskbar.md` balloons/NC; toast history ≠ Event Viewer (`06-…` eventvwr). |
| Remote desktop | `05-control-panel.md` RemoteApp and Desktop Connections — missing product. |
| Drive encryption | `05-control-panel.md` BitLocker (Ultimate) — missing product; consequential warnings required if built. |
| Sharing | `04-explorer-dialogs.md` Share with; SMB Phase 6 — missing product. |
| Language / locale | `05-control-panel.md` Region and Language; `06-…`; layout switch ≠ full locale. |
| Accessibility | `05-control-panel.md` Ease of Access Center — honest missing; no jump invent. |
| File associations | `06-…` Associate file type UI; `parity.file-associations` missing until product UI. |
| Properties | `04-explorer-dialogs.md` Properties sheets — General minimum; full Security etc. invent risk. |
| Context menus | `04-explorer-dialogs.md` file/folder/desktop; `03-…` Jump Lists; `02-…` Start RC — not “everywhere” until desktop/Explorer complete. |

## Caption / windowing

| Topic | Pointer |
|-------|---------|
| W0 / captions / snap | `01-window-chrome.md` BINDING LOCK + interaction matrix; `07-interaction-grammar.md` Aero section. Status claims unchanged — W0 is Phase 1 only, not OS go. |

## 2026 layers

| Job | Pointer |
|-----|---------|
| Software Center | `PHASE_BINDINGS.md` Phase 7; `05-control-panel.md` Programs and Features analog |
| Compatibility Center | `PHASE_BINDINGS.md` Phase 8; Default Programs remains open-with path (`06-…`) |
| Snapshot recovery | `06-…` Recovery / Backup; restore-point UX not Btrfs lecture |
| Modern display | `07-…` DPI presets; `05-…` Display; scaling/HDR/night-light separate honesty |
| Proton / gaming | Phase 8 bindings; Games Explorer place in `02-start-menu.md` is Win7 IA only |
| Privacy | Doctrine refuse telemetry; no CP Privacy hub invent without screens |
| Agent Fabric / Agent Center | `PHASE_BINDINGS.md` Phase 2/4; Start place = delta; claims stay non-present until product |

## Forty-task cross-ref (smoke necessary ≠ sufficient)

Point harness rows at the same GT files when extending acceptance text: e.g. rows 20–25 → `01`/`03`; row 19 → `06` Default Programs; rows 10–15 → `04`; row 26–27 → `06` Task Manager/startup; row 40 → `02` power flyout. Do not change automated/present claims here.
