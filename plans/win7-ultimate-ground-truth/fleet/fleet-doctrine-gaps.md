---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# Fleet doctrine gaps — Win7 Ultimate behavioral requirements

Source tip: `686c66c0105e` (`PRODUCT_DOCTRINE.md`, `WINDOWS_7_ULTIMATE_PARITY.md`, `default/ultimate/parity/jobs.json`, `plans/project-ultimate.md`).

## 0. Purpose

Phase plans keep inviting invent (LIVE CONTROL, present claims, mutation UI) when requirements are named as product nouns (“Settings”, “Task Manager”, “MIME defaults”) instead of **observable Win7-Ultimate behaviors**. This map ties doctrine rules and each parity/forty-task job to a precise behavioral requirement and names the invent failure mode so fleets cannot greenwash plane wiring or partial writers into OS-present claims. Product remains **REJECTED**; do not merge `work`→`main` as the OS.

## 1. Non-negotiable doctrine rules (PRODUCT_DOCTRINE)

| Rule | Behavioral force | Invent it blocks |
|------|------------------|------------------|
| Identity | Win7 Ultimate complete mouse-native desktop + agent fabric under the same jobs — not Aero theme / not Omarchy+chat | Shipping keyboard-first ownership as Desktop Mode |
| REJECTED | Not a shippable OS; W0 is Phase 1 only; “15–20%” is slogan not KPI | Declaring victory from Superbar screenshots |
| Rule 1 zero-terminal | Normal ownership jobs never require terminal | “Just run this in terminal” phase exits |
| Rule 2 zero-hotkey | Mouse can do everything; shortcuts are accelerators | Hotkey-only discovery of Files/Settings |
| Rule 3 muscle memory | Start/taskbar/captions/Alt+Tab/Win+*/clipboard behave as Windows expects | Linux-substitute choreography without cause |
| Rule 4 visible before memorable | Affordance visible before chord | Hidden power behind Super+menus only |
| Rule 5 progressive disclosure | Settings path first; raw Hyprland/config is Advanced | Config file masquerading as Settings |
| Rule 6 consequential state | current→proposed→progress→result→recovery | Surprise terminal scroll / silent mutation |
| Rule 7 recoverability | Restore points users understand | Btrfs lectures as UX |
| Rule 8 agent-native | Same capability graph for human and agent | Pixel scrape / random shell as primary agent API |
| Naming/errors | Translate plumbing; structured errors with recovery | `Process exited with status 1` as UI |
| No-bullshit install | Warn before long/destructive/privileged work | Friendly UI that hides consequential cost |
| Not a clone ≠ skip jobs | Refuse ads/telemetry/forced accounts; still must do install/Chrome/files/games/settings/printers/Wi-Fi with mouse | Using “not a clone” to ship developer-box defaults |
| Mode profiles | Desktop vs Power User over one platform; unimplemented flags stay false | Dual-OS forks; flags true for vapor |
| Architecture | UI → typed service → system tooling; never QML→Bash string | Consumer chrome assembling shell strings |
| Acceptance triple | Forty-task smoke + PARITY jobs + AGENT_NATIVE; six automated rows ≠ ship | Green 20–25 as OS go |
| Release | Do not merge work→main as OS | ISO/go from doctrine or W0 alone |

**Catalog honesty addenda (fleet review locks):** `provider.state=present` ≠ `availability.claim=present`. Do not walk a parity `claim` up without a capability symbol. Inspect-backed pages must say changes unavailable until writers exist. Shell principal cannot hold standing consequential grants.

## 2. Parity / forty-task job → precise Win7 behavioral requirement

Jobs in `jobs.json`: **82** (claims: missing=36, partial=1, plumbing=4, present=5, prototype=36).

### Shell

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `parity.superbar-taskbar` | prototype/prototype | visible: Bottom taskbar | Bottom Superbar shows pinned and running apps; click focuses/minimizes/restores; live peeks; jump lists; badges; multi-monitor policy as documented. | Claiming finished Windows taskbar while Task Manager/Recycle jump routes missing; inventing Close group as Close window. |
| `parity.start` | prototype/prototype | visible: Superbar > Start | Start orb opens two-pane launcher; mouse can launch apps, open places, power actions; search finds apps and published Settings/Agent places. | Inventing file-content search; inventing Overview destinations; teaching Super+K as ownership. |
| `parity.search` | prototype/prototype | visible: Start > Search | Start Search finds installed apps and published Settings/Agent/Start places with the mouse; not a web/file-content search product. | Inventing Spotlight/file-content search as present. |
| `parity.event-history` | prototype/prototype (toasts + window ledger) | visible: Superbar > Notifications | User can review recent notifications/events from Notification Center/history. | Claiming Event Viewer product from toast history. |

### Files/Desktop

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `parity.desktop-icons-wallpaper-context-menu-recycle` | prototype/prototype | visible: Desktop; Start > Settings > Personalization | Desktop shows icons for user files; wallpaper changeable; right-click desktop for context actions; Recycle Bin on desktop opens Trash and supports restore/empty as a first-class place. | Inventing wallpaper-only Personalization as 'desktop done'; inventing Recycle as a label without trash/restore; inventing desktop context menus that shell-exec. |
| `parity.explorer-this-pc` | prototype/prototype | visible: Start > Computer; Superbar > Files > This PC | This PC / Computer opens product Files to a PC inventory the user can browse with the mouse (drives/locations), not Nautilus-by-accident. | Claiming Explorer present while workspace inspect degraded; inventing full NTFS Properties. |
| `parity.properties` | missing/missing as product | visible: Files > right-click > Properties | Right-click Properties shows size/type/location/attributes for files/folders. | Inventing Properties sheet. |
| `parity.context-menus` | prototype/prototype | visible: Right-click taskbar item or Start item | Right-click yields contextual actions on Superbar/Start/desktop/files as Windows users expect. | Claiming complete context-menu API while desktop manage routes unpublished. |

### Settings

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `parity.network` | prototype/prototype | visible: Start > Settings > Network | User can view network state and toggle Wi-Fi radio from Settings/Superbar without terminal; joining networks is a separate requirement. | Claiming Network complete from radio toggle alone; inventing VPN/join UI. |
| `parity.personalization` | prototype/prototype | visible: Start > Settings > Personalization | User can change wallpaper/theme-related personalization from Settings Personalization with the mouse. | Equating Personalization picker with full theme/density/cursor product. |
| `parity.power-options` | prototype/prototype | visible: Start > Settings > Power | User can view power source/profile and set power profile from Settings/Superbar without terminal; sleep/lid remain separate if missing. | Claiming Power Options complete from profile.set alone. |
| `parity.sound` | prototype/prototype | visible: Start > Settings > Sound | User can view outputs and set output volume from Settings/Superbar without terminal; mute/routing may remain unavailable if stated. | Inventing full mixer/port UI from volume writer. |
| `parity.display` | prototype/prototype | visible: Start > Settings > Display | User can view displays and change brightness when hardware allows; resolution/scale/arrangement are separate requirements if missing. | Claiming Display complete from brightness-only; inventing arrangement UI. |
| `parity.modern-display-scaling-hdr-night-light` | prototype/prototype / plumbing | visible: Superbar > Display | User can set scaling (e.g. 125%), HDR if available, night light from Display/Quick Settings. | Claiming modern display complete from one of scaling/night-light alone. |

### Defaults

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `parity.language-locale` | prototype/prototype | visible: Settings > Input | User can switch keyboard layout when multiple layouts exist; full locale/language pack job is broader. | Moving language-locale to present from layout switch alone. |
| `parity.file-associations` | missing/missing as product | planned: Settings | User can assign apps to MIME/file types from product UI (broader than browser protocol). | Claiming associations present from protocol.set browser control or mime.set plane without Settings associations UI. |

### Update/Recovery

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `parity.update` | prototype/plumbing / prototype | visible: Start > Settings > Update | User can see update availability and install updates from Settings Update with restore-point semantics; history is separate. | Claiming Update present from system.update plane without Settings apply UI / metal row 28. |
| `parity.backup-restore` | plumbing/plumbing | planned: Backup and Restore | User can configure backups and restore from Backup & Restore product surface. | Collapsing Backup into snapshot plumbing. |
| `parity.system-restore` | plumbing/plumbing | visible: Start > Settings > Recovery | User can create/select restore points and roll back through Recovery UI without knowing Btrfs. | Claiming System Restore from recovery.inspect alone. |
| `parity.snapshot-recovery` | plumbing/plumbing | planned: System Restore | Snapshot recovery is exposed as restore points the user can pick. | Equating omarchy-snapshot with product Recovery UX. |

### Software/Compat

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `parity.programs-and-features` | missing/missing | planned: Start > Settings > Apps | User can list installed programs and uninstall from a Software/Apps surface without terminal. | Claiming Programs and Features from Apps inspect without uninstall path. |
| `parity.default-programs` | prototype/missing | visible: Settings > Apps | User can set default apps for protocols and common file types from Settings (Win7 Default Programs). Browser https handler is a subset, not the whole job. | Walking claim to present because browser LIVE CONTROL exists; inventing MIME UI from mime.set plane. |
| `parity.software-center` | missing/missing | planned: Software Center | One Software Center to find/install/remove software without terminal; backends are badges not product names. | Inventing Software Center from packages plane/attestation. |
| `parity.compatibility-center` | missing/missing | planned: Compatibility Center | Compatibility Center routes Windows apps (native/PWA/recipe/game/isolated/VM) without saying Wine to users. | Claiming Compatibility Center present from measured-host/plan-only providers. |
| `parity.proton-gaming` | missing/missing | planned: Settings | User can install/run games via supported Proton path through product UI. | Inventing Steam/Proton Center. |

### Administration

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `parity.devices-printers` | missing/missing / prototype | planned: Settings | User can see printers/devices and add/manage a printer without terminal (Win7 Devices and Printers job). | Inventing Settings Devices page from planned admin readers. |
| `parity.device-manager` | missing/missing | planned: Settings | User can inspect device/driver status and perform allowed device actions without terminal. | Inventing Device Manager tree UI from device.inspect alone. |
| `parity.user-accounts` | missing/missing | planned: Settings | User can view/create/manage local accounts and basic user settings without terminal. | Inventing Accounts Settings from planned Phase 9 reader. |
| `parity.credential-manager` | missing/missing | planned: Settings | User can view/manage stored credentials without terminal. | Inventing Credential Manager UI. |
| `parity.firewall` | plumbing/plumbing | planned: Settings | User can view firewall state and change rules through product UI with consequential state (not terminal). | Inventing Firewall Settings from plumbing inspect. |
| `parity.disk-management` | missing/missing | planned: Settings | User can view disks/partitions and perform allowed volume actions without terminal. | Inventing Disk Management from storage.inspect. |
| `parity.task-manager` | missing/missing as product | planned: Task Manager | User can open Task Manager, see processes ranked by resource use, and end a task through an authorized path (not shell-principal consequential without elevation). | Inventing LIVE End Task while terminationAuthorized=false; claiming Task Manager present from Admin process inspect. |
| `parity.resource-monitor` | missing/missing | planned: Resource Monitor | User can inspect per-resource usage beyond Task Manager summary. | Inventing Resource Monitor from process CPU fields. |
| `parity.services` | missing/missing | planned: Services | User can view services and start/stop/enable/disable through product UI with consequential state. | Inventing Services MMC from service.inspect. |
| `parity.task-scheduler` | missing/missing | planned: Task Scheduler | User can view/create scheduled tasks through product UI. | Inventing Task Scheduler from schedule.inspect. |
| `parity.remote-desktop` | missing/missing as product | planned: Settings | User can connect to remote desktops via product UI. | Inventing RDP client. |
| `parity.drive-encryption` | missing/missing as product | planned: Settings | User can enable/manage drive encryption via product UI with clear consequential warnings. | Inventing BitLocker-like UI. |
| `parity.sharing` | missing/missing as product | planned: Files and Settings | User can share folders/printers via product UI. | Inventing Sharing wizard. |

### Accessibility/Privacy

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `parity.accessibility` | missing/missing as product | planned: Settings | User can configure accessibility preferences from Settings Accessibility without terminal. | Inventing Accessibility page while claim missing; jump-list invent. |
| `parity.privacy` | missing/missing | planned: Settings | User can review privacy-related toggles without dark patterns. | Inventing Privacy hub. |

### Agent

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `parity.agent-fabric` | prototype/prototype (window) | visible: Superbar window controls; agent capability invocation | Human and agent share one typed capability graph for meaningful desktop jobs; not pixel-scraping primary. | Claiming Agent Fabric complete from WindowService alone. |
| `parity.agent-center` | missing/prototype | visible: Superbar > Agent Center | Agent Center is a Superbar/Start destination for tasks/approvals/automations/history; usage widget is one section. claim must not be present until product matches. | Marking parity.agent-center present while prototype/inspect-only. |

### Forty-task smoke

| Job | claim / sourceStatus | Route | Precise Win7 Ultimate behavior | Invent risk if under-specified |
|-----|----------------------|-------|--------------------------------|--------------------------------|
| `windows-native.1` | missing/pending | planned: Boot installer | **Install the OS.** Complete OS install with mouse-guided installer (no terminal ownership). | Inventing install-complete from ISO packaging slogans. |
| `windows-native.2` | prototype/pending | visible: Superbar > Network | **Connect Wi-Fi.** Connect to Wi-Fi from Network UI with mouse. | Claiming from radio toggle without join. |
| `windows-native.3` | prototype/pending | visible: Superbar > Display | **Set display scaling to 125%.** Set display scaling to 125% from Display UI. | Claiming scaling present without control. |
| `windows-native.4` | prototype/pending | visible: Personalization > Background | **Change the wallpaper.** Change wallpaper from Personalization. | Equating any background change API without UI. |
| `windows-native.5` | prototype/pending | visible: Superbar > Bluetooth | **Pair Bluetooth headphones.** Pair Bluetooth headphones from Bluetooth UI. | Claiming from inspect-only. |
| `windows-native.6` | prototype/pending | visible: Superbar > Sound | **Adjust output volume.** Adjust output volume from Sound UI/Superbar. | OK if volume writer+UI; not full Sound job. |
| `windows-native.7` | missing/pending | planned: Software Center | **Install Firefox or Chrome.** Install Firefox or Chrome from Software surface without terminal. | Inventing install from package plane. |
| `windows-native.8` | missing/pending | planned: Software Center | **Install Steam.** Install Steam from Software/Compatibility without terminal. | Inventing Steam install. |
| `windows-native.9` | prototype/pending | visible: Start > Downloads; Superbar > Files > Downloads | **Open Downloads.** Open Downloads folder from Start/Files with mouse. | OK if Files Downloads place works. |
| `windows-native.10` | prototype/pending | visible: Files > New Folder | **Create a folder.** Create a folder in Files with mouse. | Banner/handoff must not say create unavailable while New folder exists. |
| `windows-native.11` | prototype/pending | visible: Files > Rename | **Rename it.** Rename a file/folder in Files with mouse. | Claiming rename present without UI/writer. |
| `windows-native.12` | prototype/pending | visible: Files > Copy and Paste | **Copy files.** Copy files in Files with mouse. | Inventing clipboard file ops. |
| `windows-native.13` | prototype/pending | visible: Files > Compress | **Zip them.** Zip files from Files with mouse. | Inventing compress UI. |
| `windows-native.14` | prototype/pending | visible: Files > Devices | **Connect a USB drive.** Connect USB drive and see it in Files Devices. | Inventing from mount inspect. |
| `windows-native.15` | prototype/pending | visible: Files > Devices > Eject | **Eject it.** Eject USB from Files Devices with mouse. | Inventing eject. |
| `windows-native.16` | missing/pending | planned: Files > Connect to Server | **Connect to an SMB share.** Connect to SMB share from Files UI. | Inventing Connect to Server. |
| `windows-native.17` | prototype/pending | visible: Files > PDF | **Open a PDF.** Open a PDF with default/associated viewer from Files. | Depends on associations+viewer. |
| `windows-native.18` | prototype/pending | visible: Files > text file | **Edit a text file.** Edit a .txt in graphical editor (not Neovim-as-default). | Reverting to terminal editor. |
| `windows-native.19` | prototype/pending | visible: Settings > Apps | **Change the default browser.** Change default browser from Settings > Apps (https handler). | Claiming present/automated without complete capability/proof; Default Programs still prototype. |
| `windows-native.20` | present/automated | visible: Right-click app > Pin | **Pin an app.** Pin an app to Superbar from UI. | Already automated present. |
| `windows-native.21` | present/automated | visible: Right-click app > Unpin | **Unpin an app.** Unpin an app from Superbar. | Already automated present. |
| `windows-native.22` | present/automated | visible: Caption > Minimize | **Minimize three windows.** Minimize three windows via caption. | Already automated present. |
| `windows-native.23` | present/automated | visible: Click the desired taskbar button | **Restore the one they want.** Restore chosen window from Superbar. | Already automated present. |
| `windows-native.24` | present/automated | visible: Drag to edge or open Snap chooser | **Snap two windows.** Snap two windows via edge/snap chooser. | Already automated present. |
| `windows-native.25` | partial/automated | visible: Alt+Tab or Superbar > Task View | **Use Alt+Tab.** Switch windows with Alt+Tab / Task View. | partial automated — do not claim full Task View product. |
| `windows-native.26` | missing/pending | planned: Task Manager | **Find an application that is consuming CPU.** Find which app consumes CPU (Task Manager-class UI). | Inventing from process list without End Task/authorization honesty. |
| `windows-native.27` | missing/pending | planned: Task Manager | **Disable a startup application.** Disable a startup application from Settings/Apps startup UI. | Inventing startup manager. |
| `windows-native.28` | missing/pending | planned: Start > Settings > Update | **Install system updates.** Install system updates from Settings Update with consequential state/restore point. | Claiming present from system.update plane; row must stay pending until human/metal proof. |
| `windows-native.29` | missing/pending | planned: Settings | **Inspect update history.** Inspect update history from product UI. | Inventing history from ledger. |
| `windows-native.30` | missing/pending | planned: System Restore | **Create a restore point.** Create a restore point from Recovery UI. | Inventing from snapshot helper. |
| `windows-native.31` | missing/pending | planned: System Restore | **Roll back a deliberately broken update.** Roll back a broken update via restore point UI. | Inventing rollback wizard. |
| `windows-native.32` | missing/pending | planned: Settings | **Add a printer.** Add a printer from Devices/Printers UI. | Inventing add-printer. |
| `windows-native.33` | prototype/pending | visible: Settings > Input | **Change keyboard layout.** Change keyboard layout from Settings Input when multiple layouts exist. | Claiming complete locale job. |
| `windows-native.34` | prototype/pending | planned: Superbar > Quick Settings > Night light | **Enable night light.** Enable night light from Quick Settings/Display. | Claiming without control. |
| `windows-native.35` | prototype/pending | visible: Superbar > Power | **Change power mode.** Change power mode from Superbar/Settings Power. | OK if profile UI; not full Power Options. |
| `windows-native.36` | missing/pending | planned: Compatibility Center | **Install one known-compatible `.exe`.** Install one known-compatible .exe via Compatibility Center. | Inventing from plan-only compat. |
| `windows-native.37` | missing/pending | planned: Compatibility Center > Installed | **Uninstall it.** Uninstall that app from Compatibility Center Installed. | Inventing uninstall. |
| `windows-native.38` | missing/pending | planned: Settings jump list > System information | **Find system/storage information.** Find system/storage information from a real System information page (not empty jump). | Re-adding jump that opens missing page. |
| `windows-native.39` | missing/pending | planned: Troubleshooting | **Troubleshoot intentionally broken audio.** Troubleshoot broken audio from product Troubleshooting flow. | Inventing troubleshooter. |
| `windows-native.40` | prototype/pending | visible: Start > Shut down | **Shut down.** Shut down from Start power flyout with mouse. | OK if Start power works. |

## 3. `plans/project-ultimate.md` vagueness index

Every item below invites invent if a phase fleet treats the sentence as a done-definition.

| Location | Vague text (paraphrase) | Why it invites invent | Precise replacement (tie to jobs) |
|----------|-------------------------|----------------------|-----------------------------------|
| Current position / Audit | “Typed Settings writers remain Phase 5” / “Typed writers remain Phase 5” while live Settings already has volume, Wi-Fi, power profile, brightness, keyboard layout, default browser writers | Stale phase fence — fleets either re-invent writers or ignore honesty of partial present | Replace with: Phase 5 exit = each Settings domain lists which inspect verbs and which operation verbs are LIVE vs unavailable; map to parity.sound/network/power/display/language-locale/default-programs and windows-native.6/2/35/3/33/19 |
| Current position | “Files/This PC exist as a product window prototype… Recycle is Phase 6” while Files has New folder / Trash / Restore UI | Phase noun ‘Recycle’ vs live trash writers → handoff/banner invent or underclaim | Phase 6 exit criteria: windows-native.10–15,17–18 + parity.explorer-this-pc + Recycle Bin place with trash/restore; banner/handoff must match UI |
| Current position | “Software Center, Compatibility Center, consumer administration, graphical OOBE, and product ISO are incomplete or absent” | Bags multiple jobs; no behavioral checklist | Split into parity.software-center, compatibility-center, task-manager/device-manager/…, Phase 10 OOBE behaviors, ISO packaging gate |
| Taskbar honesty | Long Superbar paragraph mixes landed chrome with ‘job-incomplete’ | Hard to see which Task Manager/Recycle claims are forbidden | Explicit forbidden invent list: no Superbar>Task Manager present; no unpublished Accessibility/System-info jumps; End Task not LIVE under shell consequential |
| Settings honesty | “Accessibility and Input stay honest Fabric pages because no Settings panel exists (keyboard layout is a bar widget…)” vs Input writer + Settings Input coverage | Contradicts live Input layout writer — invites both invent and false missing | Refresh: Input layout settable when switchable; Accessibility still missing product page; System information still no aggregate provider |
| Settings honesty | “The Settings jump list publishes… keeps Accessibility and System information as those missing pages” | Historically invited jumps to missing pages; must stay clear | Jump list must omit provider-less actions; windows-native.38 must not regain empty System information jump |
| Phase 3 | “No Nerd Font salad… verified state gallery” | No measurable gallery acceptance tied to jobs | Gallery must prove Rules 4–5 on Start/Settings/Files empty/error states; pseudo-locale/RTL gates named |
| Phase 4 | “Masterpiece Start”, “at the end… look like a different OS” | Aesthetic exit with no job matrix | Exit = Superbar/Start/search/context-menus/event-history/agent-center route honesty per jobs.json claims; Agent Center claim stays non-present until product |
| Phase 5 | One sentence listing Display, Sound, Network, … System Information | Noun list ≠ writers; System Information/Accessibility still missing | Per-page matrix: readable inspect? operation verbs? hide when undrivable? consequential state? Map each to parity.* + windows-native rows |
| Phase 5 | “Apps/defaults/startup” bundled | Browser LIVE CONTROL ≠ Default Programs ≠ startup manager | Split: windows-native.19 prototype; parity.default-programs prototype; parity.file-associations missing; windows-native.27 startup disable missing |
| Phase 6 | “Dolphin, This PC, desktop files, graphical text editor… MIME defaults, removable media, SMB” | Implementation shopping list; MIME defaults ambiguous (plane vs UI) | Behaviors: This PC browse; New folder/rename/copy/zip; Trash/restore; USB connect/eject; SMB connect; PDF open; txt in GUI editor; MIME association UI (not only mime.set helper) |
| Phase 7 | “One Software surface; pacman/Flatpak/AUR/AppImage are implementation details with trust badges” | No install/uninstall/trust UX requirements | parity.software-center + windows-native.7/8: search/install/uninstall without terminal; attestation/trust badges; no LIVE mutation while contract-seed |
| Phase 8 | “Compatibility Center, not Wine. Native/PWA/… routing” | Routing nouns without deploy/uninstall behaviors | parity.compatibility-center + windows-native.36/37: decide route, deploy known-good/.exe, uninstall; refuse unattested live mutation |
| Phase 9 | “Task Manager, Device Manager, Storage, Backup vs snapshots, Recovery, firmware, Troubleshooting Center” | Comma list — End Task/authorization/polkit walls unstated | Each noun → job id; Task Manager requires authorized termination path; do not claim LIVE CONTROL under shell consequential refuse |
| Phase 10 | “Only when the product works. No package lists…” | No OOBE behavioral script | Mouse-only first-boot: language/network/account/update opt; never Super+K tutorial as ownership |
| Phase 11 | “Every hover, context menu…” | Unbounded polish | Bind to forty-task + PARITY residual defects list; no new capability invent in polish |
| Acceptance § | Six release conditions at one packaged candidate SHA | Easy to treat metal green test/all as substitute | Explicit: test/all green ≠ forty-task; plane mechanism ≠ pending row closed (e.g. windows-native.28) |
| Program invariants §3 | “Product surfaces consume frozen typed services… Consumer QML does not gain new process invocation” | Doesn’t say how to label partial writers | Any new writer must update coverage string + jobs claim/proofStatus honestly (prototype vs present vs automated) |

## 4. Phase-plan anti-invent checklist

Before a phase plan or handoff may say **present**, **LIVE CONTROL**, **automated**, or “Settings can…”:

1. Name the **job id** (`parity.*` or `windows-native.*`) and the **observable mouse behavior** (section 2).
2. Name the **typed verb**(s) (`provider.read` / `operation.*`) and principal (SHELL vs TASK); consequential ⇒ not standing shell grant.
3. Show the **human route** exists in UI (not helper-only / not fabric-only).
4. Update **coverage** text: what works vs remains unavailable — must match the banner/controls.
5. Set `jobs.json` **claim/proofStatus** to what the capability checker and proof harness actually allow (no present without complete capability; no automated without proof id).
6. If hardware cannot do it, **hide** the control — do not ship a failing button.
7. Do not walk `claim` up without a capability symbol; do not invent mutation UI on inspect-only pages.
8. Metal `test/all` green is necessary hygiene, not forty-task completion and not OS ship.
9. Product stays REJECTED; no `work`→`main` merge as OS.

## 5. Open doctrine MUST_FIX carry (context)

- Files banner still underclaims trash/restore while UI offers them; `HANDOFF_WRITERS` helper-only / next-piece schema-blocker narrative stale vs Files UI.
- Catalog soft invent: `apps.defaults.set` provider.id `apps.provider` vs live `defaults.provider`.
- `HANDOFF_STATE_DOMAIN_WRITES` still carries TASK-unwired / Wall-one “cannot be wired” paragraphs after TASK admission present.
- End Task: consequential / `terminationAuthorized=false`; digest label scrape fragile; do not invent Task Manager LIVE kill.
- Semantics.text / authored English leftovers. DesktopIcons argv→execArgv landed in tree (PR #5). Metal leftover 2026-09-02T04:18:31-04:00 on omarchy: `test/shell.d/launch-argv-test.sh` EXIT 0; comma-join `uwsm-app -- /usr/bin/cursor,--password-store=...` still errors as expected; `uwsm-app -- /home/jesse/.local/bin/cursor-wayland --version` OK (3.16.29). Product REJECTED.
- Product **REJECTED**; refuse merge as OS.

---

*Doctrine fleet research for Lead Reviewer. Not an OS ship gate.*
