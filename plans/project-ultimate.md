# Project Ultimate — product plan

This is the working plan for the fork. It is not a theme plan. It is not a “move the bar to the bottom” plan. The locked identity is:

> **Windows 7 Ultimate's complete, obvious, mouse-native desktop model rebuilt for 2026, with an agent-native operating fabric underneath every system capability.**

Not: Windows-like Omarchy with AI tools.

This file and `PRODUCT_DOCTRINE.md` are the founding execution authority. The eleven phases below are the product taxonomy. Phase 1 is Windowing Gate W0; its evidence checklist is `W0_GATE.md`. Later overlay programs that replaced this taxonomy are not authority.

`HANDOFF_NEW_BOX_2026-08-23.md` is the first post-W0 lock and remains immutable historical evidence. Dated next-work items in that file that are already in the tree stay done; they do not reopen W0.

Read this file together with:

- `W0_GATE.md` — Phase 1 windowing gate definition and evidence checklist
- `HANDOFF_NEW_BOX_2026-08-23.md` — first post-W0 lock (historical)
- `PRODUCT_DOCTRINE.md` — eight rules (the original seven plus Agent-Native)
- `WINDOWS_NATIVE_ACCEPTANCE.md` — forty-task smoke test (necessary, not sufficient; six numbered rows automated, plus unnumbered harness proofs)
- `WINDOWS_7_ULTIMATE_PARITY.md` — job matrix
- `AGENT_NATIVE_ACCEPTANCE.md` — same-path agent matrix
- `docs/mode-profiles.md` — Desktop Mode vs Power User Mode as flags, one platform
- `docs/settings-service-api.md` — UI and agents → typed service → Omarchy/system tooling
- `docs/design-tokens.md` — one token pipeline for Superbar and hyprbars; no new private palettes
- `plans/desktop-mode-handoff.md` — historical live Hyprland windowing evidence

If those documents and this plan disagree, the doctrine wins. If this plan and a PR description disagree, this plan wins. Do not take PR #1’s old “Windowing go/no-go — GO” as an OS go; that writeup was rejected.

## Preserved W0 evidence and invariants (2026-08-22)

Keep `4ea1dcf3` through `c1ae994f`. Those SHAs stay. Do not amend them. Do not squash them. Do not restore `--disable-features=WaylandWindowDecorations`.

The product call is still **REJECTED**. Do not merge `work` into `main` as the OS.

## W0 product-windowing (2026-08-23 metal)

Windowing Gate W0 is **architecture GO** (Hyprland stays) and now **product-windowing GO** on HDMI-A-1 1920×1080. That is not an OS go.

Live this session (`windows-native-test.sh` exit 0 including numbered 20–25 and unnumbered proofs; `hyprbars-pointer-proof.py` exit 0 including maximize-hover snap chooser and unfocused addressed close):

- Three caption buttons, visible min / max / close. Snap is maximize hover (`hover_action` → `snapChooser 0x{:x}`), drag-to-edge, and Super+Z. No `▦` button.
- CSD classes from `default/ultimate/csd-clients.json` (Lua `hyprbars:no_bar` + WindowModel). Chromium one CSD row; Files/Nautilus GTK CSD only (no hyprbars two-row). `WaylandWindowDecorations` still on.
- Per-app reopen memory in `~/.local/state/omarchy/ultimate/window-placements.json` via WindowService. 880×560 remains the Hyprland fallback only. Cascade when there is no memory; clamp to the window's monitor; do not reopen a snap as the saved size.
- `omarchy-update` rebuilds hyprbars + omarchy-minimize after `omarchy-update-system-pkgs` (`omarchy-apply-hyprland-plugins`). A failed rebuild fails the update. Still **not** AUR `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`. Versioned distro packages remain the durable end state.
- Superbar group menu: **Close group** when `windows.length > 1`, else **Close window**. Peek × still one window.

Scope not delivered by W0 and now owned by the current program:

- hyprbars is still not an ISO-mirror pacman package.
- Tokyo Night seed, nvim-as-txt, TTY first-boot, no product ISO.
- Chrome install-as-product, games, and “install any Windows app” are later phases.
- Jump lists and Agent Center UI are on the Superbar/Start path. Peek captures live window thumbnails. Live Settings writers are Sound volume, Network Wi-Fi radio, Display brightness, Input layout, and Apps default browser; Power stays inspect-only because polkit cannot authorize profile.set from app.slice; other domains stay inspect-only or host the existing Personalization picker. The Settings window already hosts those existing panels.

## Preserved W0 outcome and packaging debt

The four product-windowing debts from 2026-08-22 are **closed** on metal. Left for later packaging, not as an excuse to reopen W0:

- Plugins compile in the update transaction; they are still not versioned distro packages in the Hyprland release. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`. Overlay chrome is gone. `WaylandWindowDecorations` stays enabled.

## Taskbar / Start / Settings honesty (known defects, not features)

- Desktop Computer is the shipped `Computer.desktop` shortcut. Double-click runs the same `files.this-pc` launch as Start Computer, through `AppLibrary.launchCommand` and `uwsm-app`, not `xdg-open` of the desktop file.
- Superbar is still job-incomplete as a finished Windows taskbar (no Recycle, no Task Manager, no full context-menu API). Catalog `process.inspect` is visible on Administration > Processes; claim stays missing; honest-unavailable as Task Manager product — do not invent Superbar > Task Manager. Leftover `processes.inspect` (`processes.provider` / `legacy-direct` / `claim=partial` / Task Manager surface / btop source) is closed. Desktop icon manage and desktop context-menu stay unpublished empty routes. Administration inspect readers (accounts, devices, firewall, printers, services, schedules, storage, plus Processes, Backup, and Troubleshooting) are visible on live Administration titles after #36; claim stays missing; Phase 9 exit criteria still open; inspect ≠ MMC product present. End Task stays unauthorized (`terminationAuthorized=false`); do not invent present Settings, Start, or Superbar Administration pages. Presentation now includes the Start orb, stacked-window Task View mark, drawn Quick Settings and Notification Center marks, two-line clock, live peeks, jump lists, badges, and hover tooltips. Multi-monitor policy is landed: the primary output (Hyprland id 0, else leftmost) owns the notification cluster; every bar shows pins; a secondary bar also shows running groups that have a window on that output; Start and Task View open on the Superbar that summoned them. Jump list Close window closes the active window; Close group still closes every window in the group. Peek × closes one. Notification-area cluster is driven from `barConfig.layout.right` + `BarWidgetRegistry` (`TrayCluster.qml`). Desktop Mode overlay includes Quick Settings, Notification Center, agents, the existing `omarchy.system-update` and `omarchy.keyboard-layout` widgets, tray, and clock without rewriting `shell.json`. Chrome hexes include `#1b1b1b` `#333333` `#3a3a3a` `#4a4a4a` `#e8943a` `#9cbc0d` `#55ffffff`. Caption min/max/close colors are `Tokens.caption` via the generated chrome adapter — not a second private file and not a hard-coded `rgba(1a1a1acc)`. `Variants` still draws a bar per `Quickshell.screens`.
- Start is a two-pane 720×640 launcher (search + pins + letter-grouped All programs on the left; account, iconed Files/Pictures/Computer/Settings/Agent Center, and power on the right). Search ranks installed apps plus existing Settings pages, Agent Center sections, and Start places; Display/Sound/Network/Bluetooth/Power/Personalization/Apps/Input/Update/Recovery/Pictures/Computer/Desktop/Documents/Downloads/Recent and Agent Center Tasks/Approvals/Automations/Activity/History/Context/Usage/Permissions/Providers/Artifacts/Troubleshooting reuse the published jump actions. The Agent Center jump list also publishes Overview; Start search still opens Agent Center itself rather than inventing a second Overview destination. Idle All programs stays apps-only. Not file-content search. Recent is the last launched programs that are not already pinned, persisted in `start-recents.json` from `AppLibrary.launch`. Right-click on pins, Recent, All programs, and Start places with a desktop id opens the same Superbar verbs: desktop-entry jump list plus Pin to taskbar / Unpin from taskbar. Files jump lists include Home, This PC, Desktop, Documents, Downloads, Pictures, Recent, Trash, and Search after the product launcher is published. Start search still opens Files itself rather than inventing a second Home destination. Files Home stays degraded. Computer uses that This PC action; Pictures uses the Pictures action. Both open product Files, not Nautilus. The power flyout (Lock / Restart / Log off / Shut down) lives on the Start card like the pin menu, so click-through cannot steal the caret click. Outside-click, orb re-toggle, the shared transient coordinator, and compositor-delivered click-through are landed and proved. Start owns the output named by the clicked orb (`PanelWindow.screen` + `start-owner.json` for the click-through hit test). Closing the same orb restores the previously focused window; wallpaper/window click-through does not.
- Settings (`org.omarchy.Settings`) is a snappable window with caption and nav. Personalization hosts the existing image picker inside that chrome. Display, Sound, Network, Bluetooth, Power, Apps, Update, and Recovery read Fabric `display.inspect` / `audio.inspect` / `network.inspect` / `bluetooth.inspect` / `power.inspect` / `defaults.inspect` / `update.inspect` / `recovery.inspect` instead of embedding Process panels. Input layout is settable from Settings when a keyboard carries more than one layout (`input.provider` `keyboard-layout.set`); Accessibility stays an honest missing Fabric page because no `accessibility.provider` is registered. The Settings jump list publishes Settings home plus the inspect pages and keeps Accessibility and System information as those missing pages; Start search still opens Settings itself rather than inventing a second home destination. Start search does not invent Accessibility or System information. System stays a Fabric page because no aggregate system-information provider is registered. Live Settings writers are listed in Current position; remaining domain verbs stay unavailable and jobs stay prototype/pending. The overlay plugin launches this window instead of toggling floating panels.
- Peek captures a live grim thumbnail of each mapped window's compositor rectangle on the active desktop. Minimized, off-desktop, occluded, or zero-area windows stay title-only; the peek does not grim another desktop's stale rectangle or another window's pixels. The peek stays held while the pointer is on the task button or the peek card. Lock preview and session lock hide Superbar peeks, jump menus, Start, and Task View so those PopupWindows do not stack above the lock overlay. Superbar running groups include every non-special window so an app on Desktop 2 still lights its pin. Unpinned `org.omarchy.terminal` uses the foot icon; reverse-DNS compositor ids do not themed-fallback onto the Settings gear. Settings is not a shipped Superbar pin; its jump list follows the desktop entry, including when the running group id is lowercased. Right-click is pin/unpin and **Close group** / **Close window** (label follows `windows.length`). Peek × closes one.
- `feature()` is only consulted in `shell.qml` (`taskbar`/`topBar`) and `Start.qml` (`developerToolsInStart`).

## Doctrine (do not weaken)

1. Zero-terminal ownership. The terminal is an application, not a prerequisite for owning the computer.
2. Zero-hotkey-required. The mouse can do everything. Shortcuts are accelerators.
3. Windows muscle memory is an API. Start, Superbar, captions (min/max/close), Alt+Tab, Win+D/E/R/I/L/Arrows, Delete/F2/clipboard behave as a Windows user expects.
4. Visible before memorable. See the affordance before learning the chord.
5. Progressive disclosure. Settings → Display → Resolution is the normal path. Generated Hyprland config is Advanced.
6. Consequential operations have state. Current → proposed → progress → result → recovery. No surprise terminal scroll.
7. Recoverability is a flagship feature. Restore points, not Btrfs lectures.
8. Agent-native. Every meaningful human-desktop capability has a structured agent-callable equivalent. Same validators, transitions, errors, rollback, audit. No pixel scraping or random shell strings as the primary agent interface.

Overlay rule: Desktop Mode must not rewrite `~/.config/omarchy/shell.json`. `shell.qml` computes effective `bar.id` / `bar.position`.

Service rule: QML never assembles shell strings for windowing or settings. UI and agents call typed verbs.

Agent Center belongs in Desktop Mode as native as Start. `omarchy.agents` (usage/limits/cost/activity) stays visible until Agent Center exists. Preserve the Quattro plugin model under Windows-quality Superbar presentation.

## What this product is not

Not a Windows clone. Not Aero. Not “Arch for Windows users.” Not a nicer Omarchy theme. Not Omarchy-with-a-chat-panel. Upstream Omarchy is a keyboard-first tiling distro on purpose. This fork keeps that plumbing and replaces the default product experience.

“Not a clone” refuses Windows ads, telemetry, and forced accounts. It does not license shipping a Linux developer box. Desktop Mode is Windows 7 Ultimate’s information architecture: Start, Superbar, files, Chrome, install apps, games, settings, printers, Wi-Fi — with a mouse — and an agent fabric under those same jobs. The terminal is an application. Power User Mode is where Linux tools stay first class.

Do not initially write a compositor, file manager, browser, package manager, audio stack, or installer. Use KDE as a component mine (Dolphin, Kate, Okular, Ark), not as the desktop. Study Zorin as the Windows-migration competitor, then go deeper than “layout that looks like Windows.”

## Branch strategy

Hard rule: this fork has two branches only.

```text
upstream/quattro
      │
      ▼
main                       Clean tracking of upstream (default)
      │
      ▼
work                       All Ultimate product work
```

Do not create `cursor/*`, `ultimate/*`, or any other slice branches. Do not turn `main` into the experimental line. Phase work happens as commits on `work`. Do not merge `work` into `main` as the OS. `AGENTS.md` holds the absolute branch rules and overrides anything here that disagrees with it.

## Historical branch reconciliation evidence (2026-08-22)

This section is a dated forensic snapshot, not current branch or tag truth. The reconciled 2026-08-26 baseline in Current position supersedes its SHAs and counts while retaining the evidence ledger.

Do not re-audit this from memory. The ledger is **outside the product repo** — do not commit the bundle or copy ~240 MB into git:

- Bundle: `C:\dev\omarchy-vm\omarchy-all-refs-2026-08-22.bundle` (251209890 bytes, 145 refs, `git bundle verify` okay)
- Ledger: `C:\dev\omarchy-vm\branch-reconciliation-ledger-2026-08-22.md`

**Heads PASS.** GitHub / Windows / box `refs/heads/*` are only `main` and `work`. `main` == `2c247e39` == live `basecamp/omarchy` **`quattro`** (not `master`; `master` is `f4378f0d`). At ledger time `work` was `c4c6ce29`, **35 ahead / 0 behind** `main`, merge-base is `main`. Docs commits after the ledger (`e03f777e`, then `25b6e6de` and later) moved `work` — do not reset. All named Ultimate SHAs and the 16 locked W0 SHAs are ancestors of `work`. `.cursor/environment.json` and `.cursor/install.sh` are on `work`.

**Claim 6 content PASS.** 73 deleted origin/local tip names vs `work`: 240 unique commits (almost all upstream DHH/Omabot), 386 unique blobs (upstream, not Jesse). **Jesse unique blobs: 0.** No Jesse-looking file is present on a deleted tip and missing from the `work` tree.

**Claim 6 strict unique-commit SHA FAIL — one exception.** `30aac92fccb2a03118e4c7bb461cdd54d7b29050` “Merge branch 'basecamp:quattro' into cursor/cloud-agent-dev-environment-a448” by jnadeau207-collab. Parents `28a8bdfb` and `2c247e39` are **both** already ancestors of `work`. Unique blobs on that tip: 0. `git diff --diff-filter=A work 30aac92f` is empty. No file content lost; only that merge SHA is absent from `work` ancestry. 72/73 deleted names have zero unique Jesse commit or blob.

Do **not** claim mathematical zero unique Jesse *commits*. Claim zero unique Jesse *content*, plus one orphan merge SHA with an empty tree diff.

**Caveats (not branches):** 65 version tags remain; `refs/pull/1/head` and `refs/pull/2/head` remain. If someone reads “GitHub has no refs except main and work,” that reading fails. The two-branch **head** claim passes.

## Current position

After the Quattro rebase, `main` is `upstream/quattro` byte for byte and `work` is Ultimate rebased onto it. No recovery refs are kept; the rebase is verified instead. Local, `origin`, and metal hold the same commit. Do not merge `work` into `main` as the OS.

The product remains **REJECTED**. Windowing Gate W0 is Phase 1 only (`W0_GATE.md`). The shell contains real windowing, tray, notification, lock, panel, wallpaper, usage, and update/recovery machinery. Desktop Mode now ships two-pane Start, desktop icons on the real XDG Desktop directory, Quick Settings, Notification Center, calendar, lock, and Agent Center as a Superbar pin and Start destination. Superbar presentation is an orb, stacked clock, drawn Quick Settings and Notification Center marks, live peeks, jump lists, and badges over the plugin cluster. Settings is a snappable window that hosts the existing Personalization picker; Display, Sound, Network, Bluetooth, Power, Apps, Update, and Recovery read Fabric `display.inspect` / `audio.inspect` / `network.inspect` / `bluetooth.inspect` / `power.inspect` / `defaults.inspect` / `update.inspect` / `recovery.inspect` instead of Process panels. Files/This PC exist as a product window prototype (location availability is honest; workspace inspect stays degraded). Software Center, Compatibility Center, graphical OOBE, and product ISO are incomplete or absent. Consumer administration product (Task Manager / Device Manager / Services MMC) is incomplete; Phase 9 exit criteria still open; live inspect hosts exist and stay honest-unavailable as product.

Settings and Files writer honesty — LIVE means a typed Settings/Files control exists today. Do **not** mark any `parity.*` or `windows-native.*` `claim` `present`. Forty-task rows stay pending.

| Domain | Inspect | LIVE writer | Still unavailable / pending |
|--------|---------|-------------|-----------------------------|
| Sound | `audio.inspect` | `output-volume.set` | mute, routing, ports; `parity.sound` prototype; `windows-native.6` pending |
| Network | `network.inspect` | `wifi.set-enabled` | join / per-connection; `parity.network` prototype; `windows-native.2` pending |
| Power | `power.inspect` | none (polkit / app.slice) | `profile.set` write plane kept, not Settings LIVE; Superbar QS Process leftover was unverified on metal after PR #31; QS Power METAL_HEAD OPEN after metal FAIL on tip `20484de6` (pkcheck Not authorized / session-5103; !batteryPresent; amd_pstate EINVAL); KEEP OPEN; Settings Power LIVE refused; sleep / lock / lid; `parity.power-options` prototype; `windows-native.35` pending |
| Display | `display.inspect` | `brightness.set` | resolution / scale / arrangement; `parity.display` prototype; `windows-native.3` pending |
| Input / Language | `input.inspect` | `keyboard-layout.set` (multi-layout) | pointer / repeat / locale; `parity.language-locale` prototype; `windows-native.33` pending |
| Apps | `defaults.inspect` | `protocol.set` (default browser) | other associations / startup / Default Programs applet; `parity.default-programs` prototype; `windows-native.19` pending |
| Bluetooth | `bluetooth.inspect` | none | pair / connect / discover |
| Update | `update.inspect` | none | download / apply; `windows-native.28–29` pending |
| Recovery | `recovery.inspect` | none | restore plan / exec; `windows-native.30–31` pending |
| Personalization | hosted Process picker | no typed service | typed Personalization writers |
| Accessibility | none | none | no `accessibility.provider` |
| System information | none | none | no aggregate provider; `windows-native.38` pending |
| Files | `files.browse` | `directory.create` (New folder LIVE); `entry.trash` and `trash.restore` write planes, CHANGES UNAVAILABLE under SHELL | Restore UI (do not invent Restore LIVE), empty Recycle Bin, permanent delete, desktop Recycle icon, desktop context menu; `files.trash.manage` missing; Recycle Bin is not product-complete |

The named phases below are the live program. After W0: Phase 2 leftover fabric (persistent tasks, context broker, sandboxed runtime), then Phases 3–11 in order. Overlay programs written after this taxonomy do not replace it.

The first execution fleet builds three independent foundations in parallel: Fabric Core, the machine-readable capability/parity graph, and the trust/sandbox plane. Subsequent fleets perform WindowService reference cutover, context/runtime/tasks, semantic UI and provider engines, then whole product surfaces and packaged certification.

Locked invariants remain: keep the accepted W0 history, do not restore disabled Wayland decorations or overlay chrome, do not put the AUR hyprbars package in the install list, preserve Desktop Mode's non-mutating `shell.json` overlay, never hot-unload/reload hyprbars, stay on `work`, and never merge `work` into `main` as the OS. Publishing a rebase requires a force-push; that is expected, not a violation.

## Audit vs tree (do not rubber-stamp)

Claims from the 2026-08-22 course-correction that this turn **verified in the tree and on metal**:

- Superbar cluster from bar-widget registry; Desktop Mode overlay includes `omarchy.agents`; disk `shell.json` not rewritten — true (`overlayShellConfig`, `TrayCluster.qml`, live disk `bar.id` unset / `position: top`).
- Start is a launcher — true (`Start.qml`).
- Settings window hosts the existing Personalization picker. Display, Sound, Network, Bluetooth, Power, Apps, Update, and Recovery read Fabric `display.inspect` / `audio.inspect` / `network.inspect` / `bluetooth.inspect` / `power.inspect` / `defaults.inspect` / `update.inspect` / `recovery.inspect`. Live writers vs unavailable verbs are the Current position table; jobs stay prototype/pending.
- Peek captures live window thumbnails for mapped clients — true. Group close label is **Close group** / **Close window**; the action still closes every window in the group; peek × closes one.
- Three caption buttons (visible min / max / close); maximize hover summons snap chooser; `formatWindowCmd` lives in `barDeco.cpp` — true. 880×560 is fallback only; `window-placements.json` remembers per-app floats — true live (foot 1000×620 at `[120,80]` reopened). `omarchy-update` rebuilds plugins after system packages — true. `--disable-features=WaylandWindowDecorations` must not return — true. `hyprland-plugin-hyprbars` is not in `install/omarchy-other.packages` — true.
- Six numbered forty-task rows automated (20–25) — true. The same harness also runs unnumbered proofs after the loop — true, live exit 0 this session. Pointer proof includes maximize hover and unfocused addressed close — true.
- WindowService is the first fabric provider with `{ changed, error }`, broker, ledger, and invertible restore tokens — true. The leftover catalog and checkout Fabric unit are live; most catalog claims stay missing. Agent Center is a Superbar/Start destination; `parity.agent-center` stays missing. Settings Display/Audio/Network inspect readers are live; writers are the Current position table, not a Phase 5 blanket.

**Nuance / disagreement:**

- `snapLayouts` / `taskView` are not unimplemented; they are prototypes. Flags stay true.
- `omarchy.notifications` exists as a toast/history daemon. That is not Notification Center. Flag is false without claiming notifications are absent.
- Superbar **does** load a tray (`Tray.qml`) and now loads the registry cluster including `omarchy.agents`.
- Files two-row chrome is **gone** on metal (GTK CSD only).
- ~20% is a product estimate, not a test metric.
- Branch/bundle uniqueness: see the locked ledger section above. Zero unique Jesse **content**; one orphan merge SHA (`30aac92f`) with an empty diff. Do not restate “unverified.”

## Phases (vertical product capability)

The named phases below are the product taxonomy and the execution order. Do not skip Phase 1. Do not treat a later overlay document as a replacement for this list.

### Phase 0 — Foundation

Done enough to build on: doctrine, acceptance manifests, profiles, token layer, service convention, test/acceptance harness skeleton. That foundation is on `work`.

Visual regression gallery is on `work`: `default/ultimate/quality/visual-regression-v0.json`, committed PNG goldens, and `omarchy-dev-visual-regression`.

### Win7 Ultimate binding specs

- Index all Win7 surfaces via `plans/WIN7_SPEC_INDEX.md`; goldens may prove Omarchy chrome but must cite Win7 binding docs when claiming muscle-memory parity.
- Document intentional deltas (e.g. Segoe UI vs Liberation Sans; barHeight 48 vs Win7 40) — do not silent-invent.
- Gallery / tokens: Ultimate 2026 language is allowed; do not redefine Win7 geometry from Omarchy tokens (`plans/win7-ultimate-ground-truth/01-window-chrome.md` § Omarchy freeze).
- **Anti-invent / vagueness fix:** Foundation does not invent product GO; “15–20%” remains slogan not KPI (`fleet-doctrine-gaps` Rule REJECTED).
- Links: `plans/WIN7_SPEC_INDEX.md`, `plans/win7-ultimate-ground-truth/05-interaction-polish.md` (global metrics), `plans/win7-ultimate-ground-truth/01-window-chrome.md`

### Phase 1 — Windowing Gate W0

Architecture GO and product-windowing GO on metal (HDMI-A-1 1920×1080, stack through `c1ae994f`). Keep Hyprland. Do not reopen LTRB / hyprbars / CSD / `setHidden` / three-button captions / Files chrome / reopen memory / update-transaction plugin rebuild as if they were still dirty.

The forty-task harness rows 20–25 were necessary and not sufficient for the OS; with the unnumbered proofs they were sufficient as architecture **and** product-windowing evidence for this gate.

### Win7 Ultimate binding specs

- **Caption LOCK:** restored visual top **30**; `SM_CYCAPTION` **22** metric only; L/R/B border **8**; radius **8**; buttons **29 / 27 / 49 × 20**; order min→max→close; cluster **~105**.
- Three-button SSD (hyprbars); one-row CSD exclusion; maximize = **work area** not exclusive fullscreen.
- Snap: pointer-at-edge, **release-commit**, halves 50% work area; Win+Arrows; **no** Win10 Snap Layouts on maximize hover as Win7 truth (product snap chooser is delta — document).
- Shake / Win+Home; Show Desktop strip ~8–15 px; Peek delay 1000 ms; Alt+Tab (Flip); Win+Tab = Flip 3D if claiming Win7 chord (Task View = product delta).
- System menu order Restore/Move/Size/Min/Max/sep/Close; Alt+Space; double-click caption; click-to-raise.
- Links: `plans/win7-ultimate-ground-truth/01-window-chrome.md`, `plans/win7-ultimate-ground-truth/02-start-superbar.md` (Show Desktop/peeks), `plans/win7-ultimate-ground-truth/05-interaction-polish.md` (Aero + hotkeys)
- **Vagueness fix:** W0 closed ≠ OS go; do not reopen LTRB/hyprbars as dirty without metal proof (`fleet-chrome-win7` freeze).

### Phase 2 — Agent Fabric (gate)

Historical prototype minimum (2026-08-23): WindowService `{ changed, error }`, caller-labeled local-session allowlist (ui/ipc/agent/undo), ledger `~/.local/state/omarchy/ultimate/capability-ledger.json`, window undo via recorded `restoreNormal` / `restoreLayout`, Superbar cluster from `BarWidgetRegistry` with `omarchy.agents` visible. Same WindowService verbs from QML and `omarchy-shell window`. This was a useful first-provider milestone, not a defensible permission/security pass.

Catalog jobs stay honest: most rows remain `claim: "missing"` and `parity.agent-center` is not present. Persistent inspect tasks, five-source context capture (`open-windows`, `focused-application`, `selection`, `virtual-desktops`, `mode-profile`), and bubblewrap `system.info.read` execution are live on the checkout Fabric unit. Settings Display, Sound, Network, Bluetooth, Power, Apps, Update, and Recovery read Fabric `display.inspect` / `audio.inspect` / `network.inspect` / `bluetooth.inspect` / `power.inspect` / `defaults.inspect` / `update.inspect` / `recovery.inspect`. Superbar still hosts Sound/Network/Bluetooth/Power panels. Live Settings writers vs unavailable verbs are the Current position table; do not mark those jobs `present`.

### Win7 Ultimate binding specs

- Not a visual Win7 phase; consent/progress sheets follow `plans/win7-ultimate-ground-truth/05-interaction-polish.md` dialog/progress grammar (OK/Cancel order, consequential state Rule 6).
- Agent Center UI chrome still obeys SSD caption LOCK when hosted as toplevel.
- **Anti-invent:** `parity.agent-fabric` / `parity.agent-center` stay non-`present` until product matches; WindowService alone ≠ fabric complete (`fleet-doctrine-gaps` Agent rows).
- Links: `plans/win7-ultimate-ground-truth/05-interaction-polish.md`, `plans/win7-ultimate-ground-truth/02-start-superbar.md` (Agent Center as Start place = 2026 delta)

### Phase 3 — Design system

Complete the running `shell/Ui` kit and light/dark pipeline with compact/comfortable/touch density, reduced motion, high contrast, accessibility semantics, RTL, pseudo-locales, and a verified state gallery. No Nerd Font salad in consumer chrome. One token/theme pipeline must drive Superbar **and** hyprbars. Not mockups.

### Win7 Ultimate binding specs

- One token pipeline for Superbar + hyprbars; caption metrics must be able to target Win7 **30** visual / button table — do not freeze “caption = SM_CYCAPTION 22” as bar height.
- Hit targets / focus rings / motion: `plans/win7-ultimate-ground-truth/05-interaction-polish.md` (hover 400 ms, drag 4 px, dialog 75×23 @ 96).
- Segoe UI 9 pt caption text (dark on glass) is Win7 truth; light-on-dark Omarchy tokens are theme adapters.
- **Vagueness fix (Phase 3 invent):** Gallery must prove Rules 4–5 on Start/Settings/Files empty/error + RTL/pseudo-locale — not “no Nerd Font” alone.
- Links: `plans/win7-ultimate-ground-truth/01-window-chrome.md`, `plans/win7-ultimate-ground-truth/05-interaction-polish.md`, `plans/win7-ultimate-ground-truth/02-start-superbar.md` (40 vs 48 height delta)

### Phase 4 — Desktop shell

Desktop surface, real Superbar (plugin-hosted widgets, previews, jump lists, badges), masterpiece Start, tray, Quick Settings, notification center, calendar, lock. **Agent Center is a normal taskbar-visible and snappable toplevel as first-class as Start** (tasks, active agents, pending actions, automations, history, context; usage widget is one section). At the end of this phase it should already look like a different OS.

### Win7 Ultimate binding specs

- **Start:** two-pane; BINDING right-pane order User→Documents→Pictures→Music→Games→Computer→Control Panel→Devices and Printers→Default Programs→Help; power flyout Switch user/Log off/Lock/Restart/Sleep/Hibernate; All Programs **in-pane** with Back; search placeholder “Search programs and files”; orb 54×54 states (`plans/win7-ultimate-ground-truth/02-start-superbar.md`). Omarchy 720×640 / Settings/Agent Center places = documented deltas.
- **Superbar:** height 40 (Win7) vs product 48; combine modes; Jump List structure; left-click minimize-active; Shift/middle new instance; tray Action Center/Volume/Network/Power/Clock; Show Desktop (`plans/win7-ultimate-ground-truth/02-start-superbar.md`).
- Desktop icons + context menu order View/Sort/Refresh/Paste/New/Screen resolution/Gadgets/Personalize (`plans/win7-ultimate-ground-truth/03-explorer-dialogs.md`).
- **Vagueness fix:** Exit ≠ “masterpiece / looks like different OS”; exit = job honesty for `parity.start`, `parity.superbar-taskbar`, `parity.search`, `parity.context-menus`, `parity.event-history`; **forbidden invent:** Superbar→Task Manager present; unpublished Accessibility/System-info jumps; Agent Center claim present while prototype.
- Links: `plans/win7-ultimate-ground-truth/02-start-superbar.md`, `plans/win7-ultimate-ground-truth/02-start-superbar.md`, `plans/win7-ultimate-ground-truth/03-explorer-dialogs.md` (desktop), `plans/win7-ultimate-ground-truth/05-interaction-polish.md`

### Phase 5 — Settings

First-class app over typed services. Display, Sound, Network, Bluetooth, Input, Personalization, Apps/defaults/startup, Power, Accessibility, Update/Recovery, Region and Language, and System Information. Same verbs as Agent Fabric.

### Win7 Ultimate binding specs

- Map Settings pages to Win7 CP applets in `plans/win7-ultimate-ground-truth/04-control-panel.md` (55 items) + `plans/win7-ultimate-ground-truth/06-settings-admin-media.md` Personalization / Sound / Display / Power / Default Programs.
- **Per-page matrix required (vagueness fix):** each page lists inspect verbs LIVE vs unavailable operation verbs; hide undrivable controls; consequential state Rule 6.
- Default Programs = **four links** (Set defaults / Associate / AutoPlay / SPAD) — browser https alone ≠ `parity.default-programs` present; MIME associations separate (`parity.file-associations` missing until UI).
- Personalization bottom row: Desktop Background · Window Color · Sounds · Screen Saver; wallpaper positions Fill/Fit/Stretch/Tile/Center.
- Accessibility / System Information: honest missing — **omit** provider-less jump destinations (`windows-native.38`).
- Stale fence fix: do not blanket remaining writers as still-unshipped while some writers are LIVE — list domain-by-domain vs `parity.sound|network|power|display|language-locale|default-programs` + `windows-native.6/2/35/3/33/19`. See Current position table.
- Links: `plans/win7-ultimate-ground-truth/04-control-panel.md`, `plans/win7-ultimate-ground-truth/06-settings-admin-media.md`, `plans/win7-ultimate-ground-truth/05-interaction-polish.md`

### Phase 6 — Files and defaults

Dolphin, This PC, desktop files, graphical text editor for ordinary `.txt`, MIME defaults, removable media, SMB.

### Win7 Ultimate binding specs

- Explorer chrome: command bar (not ribbon); nav Favorites→Libraries→Homegroup→Computer→Network; Libraries defaults; views Extra Large…Content; Computer groups + capacity bars; Recycle Bin behaviors (`plans/win7-ultimate-ground-truth/03-explorer-dialogs.md`).
- Context menus: file/folder/desktop orders binding; drag-drop Move/Copy/Shortcut rules; Delete vs Shift+Delete.
- **Behavioral exit (vagueness fix):** `windows-native.10–15,17–18` + `parity.explorer-this-pc` + Recycle place with trash/restore; MIME **association UI** (not only `mime.set` helper); SMB connect UI; GUI txt editor; banner/handoff must match UI (no underclaim trash if offered).
- AutoPlay from Default Programs child (`plans/win7-ultimate-ground-truth/06-settings-admin-media.md`).
- Links: `plans/win7-ultimate-ground-truth/03-explorer-dialogs.md`, `plans/win7-ultimate-ground-truth/06-settings-admin-media.md`, `plans/win7-ultimate-ground-truth/04-control-panel.md` (Folder Options)

### Phase 7 — Software

One Software surface; pacman/Flatpak/AUR/AppImage are implementation details with trust badges.

### Win7 Ultimate binding specs

- Win7 analog: Programs and Features + trust-badged installers — not “pacman UI”.
- **Exit behaviors:** `parity.software-center` + `windows-native.7/8` search/install/uninstall without terminal; attestation badges; no LIVE mutation while contract-seed only.
- Media player product may reference WMP 12 chrome jobs (`plans/win7-ultimate-ground-truth/06-settings-admin-media.md`) without clone mandate.
- Links: `plans/win7-ultimate-ground-truth/04-control-panel.md` (Programs and Features), `plans/win7-ultimate-ground-truth/06-settings-admin-media.md`

### Phase 8 — Windows compatibility

Compatibility Center, not “Wine.” Native / PWA / known-good / game / isolated / VM routing.

### Win7 Ultimate binding specs

- Compatibility Center routing Native/PWA/known-good/game/isolated/VM — user-facing never “Wine”.
- **Exit behaviors:** `parity.compatibility-center` + `windows-native.36/37` deploy known-good/.exe + uninstall; refuse unattested live mutation.
- Default Programs / AutoPlay remain human path for “which program opens this” (`plans/win7-ultimate-ground-truth/06-settings-admin-media.md`).
- Links: `plans/win7-ultimate-ground-truth/06-settings-admin-media.md`, `plans/win7-ultimate-ground-truth/04-control-panel.md`

### Phase 9 — Administration

Task Manager, Device Manager, Storage, Backup vs snapshots, Recovery, firmware, Troubleshooting Center. Phase 9 exit criteria still open. Live Administration inspect hosts today: Processes (`process.inspect` + unauthorized End Task path), Services, Device Manager, Storage, Printers and scanners, Backup, Scheduled tasks, Troubleshooting, Firewall, User accounts. Inspect inventory ≠ product MMC present. No Task Manager present, no Device Manager present, no Services present, no End Task LIVE CONTROL (`terminationAuthorized=false`). Win7 Task Manager tabs stay reference: Applications | Processes | Services | Performance | Networking | Users.

### Win7 Ultimate binding specs

- Each noun → job id: Task Manager (`parity.task-manager`), Device Manager, Disk Management, Services, Task Scheduler, Event Viewer (≠ toast history), Firewall, User Accounts, Backup, Recovery, Troubleshooting (`plans/win7-ultimate-ground-truth/04-control-panel.md`, `plans/win7-ultimate-ground-truth/06-settings-admin-media.md` MMC trees).
- Task Manager Win7 tabs: Applications | Processes | Services | Performance | Networking | Users; End Task only on **authorized** path — do not invent LIVE CONTROL under shell consequential refuse.
- Administrative Tools folder contents binding; Computer Management tree binding.
- Links: `plans/win7-ultimate-ground-truth/06-settings-admin-media.md`, `plans/win7-ultimate-ground-truth/04-control-panel.md`, `fleet-doctrine-gaps` Administration rows

### Phase 10 — OOBE and migration

Only when the product works. No package lists. No Super+K tutorial as first boot.

### Win7 Ultimate binding specs

- Mouse-only first-boot: language / network / account / update opt-in honesty — never Super+K tutorial as ownership (`fleet-doctrine-gaps` Phase 10).
- Dialog/progress grammar from `plans/win7-ultimate-ground-truth/05-interaction-polish.md`; no-bullshit install Rule.
- Links: `plans/win7-ultimate-ground-truth/05-interaction-polish.md`, `plans/win7-ultimate-ground-truth/02-start-superbar.md` (power), `plans/win7-ultimate-ground-truth/04-control-panel.md` (Getting Started analog only)

### Phase 11 — Brutal polish

Every hover, context menu, dialog, empty state, error, DPI, focus ring, reduced motion.

### Win7 Ultimate binding specs

- Apply full `plans/win7-ultimate-ground-truth/05-interaction-polish.md`: hover/drag/menus/dialogs/progress/balloons/Aero gestures/DPI/themes/sounds/cursors/Win+ hotkeys.
- Polish against residual forty-task + PARITY defects — **no new capability invent**.
- Pixel-check caption LOCK and Start right-pane / CP applet lists / Explorer menus against ground-truth — implementers must not guess.
- Links: `plans/win7-ultimate-ground-truth/05-interaction-polish.md`, all `01`–`06` ground-truth files, `plans/WIN7_SPEC_INDEX.md`

## Program invariants

Keep `4ea1dcf3` through `c1ae994f`. Do not amend them. Do not restore `--disable-features=WaylandWindowDecorations`.

1. Execute the named major program; do not fragment it into disconnected planning or one-off visual work.
2. The first fleet owns Fabric Core, Capability Graph, and Trust Plane in the non-overlapping paths specified by the program. Root owns integration and freezes RPC/schema v1 after adversarial review.
3. Product surfaces consume frozen typed services and operation state. Consumer QML does not gain new process invocation, shell strings, raw `hyprctl`, or privileged logic.
4. Keep LTRB snap, typed compositor dispatch, `/usr/lib/hyprland-plugins` hyprbars, `omarchy-minimize` hidden state, JSON CSD exclusion, addressed captions, three-button SSD, maximize-hover snap, and the measured Chromium frame transforms.
5. Never hot-unload/reload the native plugin. Every native/chrome change gets a fresh compositor restart and the complete right-edge regression campaign.
6. Keep unimplemented profile flags false, preserve Power User Mode, do not teach terminal/hotkey ownership in Desktop Mode, stay on `work`, and never create slice branches. `main` is pushed only to keep it identical to `upstream/quattro`, and publishing a rebase of `work` requires a force-push.

## Acceptance

The three matrices are the core product proofs, and all six release conditions in the current program are mandatory at one packaged candidate SHA:

1. A Windows-native tester completes all forty tasks with the mouse, without Terminal or web search.
2. Every job in `WINDOWS_7_ULTIMATE_PARITY.md` has a certified human route, typed capability mapping, structured errors, and recovery.
3. The `AGENT_NATIVE_ACCEPTANCE.md` path completes the same jobs through the same validators, operations, and recovery.
4. An Omarchy/Arch power user can still use terminal, supported package tooling, original bindings, tiling, workspaces, config editing, scripting, and plugins.
5. Fresh install, upgrade, migration, rollback, factory reset, accessibility, localization, mixed-DPI, hardware, security, recovery, and performance gates pass.
6. No open data-loss, privilege, supply-chain, update/recovery, accessibility-critical, clipping, hidden-control, phantom-success, or stale-progress defect remains.

A green `./test/all` on a machine without Hyprland does not pass W0. A green `windows-native-test.sh` that only talks to `omarchy-shell window` and checks `left.x <= right.x` does not pass W0 and does not pass the OS.
