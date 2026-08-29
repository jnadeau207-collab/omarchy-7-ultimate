# Project Ultimate — product plan

This is the working plan for the fork. It is not a theme plan. It is not a “move the bar to the bottom” plan. The locked identity is:

> **Windows 7 Ultimate's complete, obvious, mouse-native desktop model rebuilt for 2026, with an agent-native operating fabric underneath every system capability.**

Not: Windows-like Omarchy with AI tools.

Current execution authority is [`ultimate-product-completion-program-2026-08-26.md`](ultimate-product-completion-program-2026-08-26.md). `HANDOFF_NEW_BOX_2026-08-23.md` remains immutable historical evidence, but its dated next-work ordering and status no longer control execution.

Read this file together with:

- `plans/ultimate-product-completion-program-2026-08-26.md` — current execution program and dependency waves
- `HANDOFF_NEW_BOX_2026-08-23.md` — immutable historical lock and evidence from the prior program
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
- Peek thumbnails, jump lists, Agent Center UI, Settings app.

## Preserved W0 outcome and packaging debt

The four product-windowing debts from 2026-08-22 are **closed** on metal. Left for later packaging, not as an excuse to reopen W0:

- Plugins compile in the update transaction; they are still not versioned distro packages in the Hyprland release. Do not put `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`. Overlay chrome is gone. `WaylandWindowDecorations` stays enabled.

## Taskbar / Start / Settings honesty (known defects, not features)

- Superbar is a prototype, not the masterpiece. Notification-area cluster is driven from `barConfig.layout.right` + `BarWidgetRegistry` (`TrayCluster.qml`). Desktop Mode overlay includes `omarchy.agents` without rewriting `shell.json`. Chrome hexes include `#1b1b1b` `#333333` `#3a3a3a` `#4a4a4a` `#e8943a` `#9cbc0d` `#55ffffff`. hyprbars `bar_color` is `rgba(1a1a1acc)`. `Variants` already draws a bar per `Quickshell.screens` — missing is multi-monitor **policy**, not rendering.
- Start is a 440×560 glass launcher (search + pins + app list + Power User footer toggle), not Windows 7 Start. Outside-click, orb re-toggle, the shared transient coordinator, and compositor-delivered click-through are landed and proved. Remaining infrastructure work is monitor/seat/anchor-aware ownership and a focus-restoration stack without regressing click-through.
- Settings (`omarchy.ultimate-settings`) is a stub: five buttons (Display, Sound, Network, Bluetooth, Power) that toggle existing panels.
- Peek is a title list. Right-click is pin/unpin and **Close group** / **Close window** (label follows `windows.length`). Peek × closes one.
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

Do not create `cursor/*`, `ultimate/*`, or any other slice branches. Do not turn `main` into the experimental line. Phase work happens as commits on `work`. Do not merge `work` into `main` as the OS.

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

## Current position (2026-08-26)

**Historical freeze at `1334ba30`.** Do not read this section as the live Git or product position. After the 2026-08-29 Quattro rebase, `main` tracks live `upstream/quattro` and `work` is Ultimate rebased onto it. Execution is [`ultimate-continue-2026-08-29.md`](ultimate-continue-2026-08-29.md). Recovery refs retain the pre-rebase tips.

The reconciled baseline **at the time this paragraph was written** was `work`/GitHub/metal `1334ba30`, with `main`/origin/upstream `quattro` at `0ae16948` and exactly two branch heads. Chrome CSD float, restore, native maximize, snap, F11, and focus have independent source review plus direct metal geometry, pointer, pixel, health, and visual proof. The physical right edge and caption controls are no longer clipped.

The product remains **REJECTED**. The shell contains real windowing, tray, notification, lock, panel, wallpaper, usage, and update/recovery machinery, but Settings is still a five-button stub; Start, Superbar, and Task View are functional prototypes; Quick Settings, Notification Center, desktop icons, Agent Center, full typed system services, Files/This PC, Software Center, Compatibility Center, consumer administration, graphical OOBE, and product ISO are incomplete or absent.

The current program is the large, dependency-managed [`ultimate-product-completion-program-2026-08-26.md`](ultimate-product-completion-program-2026-08-26.md). It spans the remaining Fabric control plane, design system, shell, Settings, Files/defaults, Software, Compatibility, Administration/Recovery, OOBE/migration, and release certification work. It replaces the dated next-work ordering.

The first execution fleet builds three independent foundations in parallel: Fabric Core, the machine-readable capability/parity graph, and the trust/sandbox plane. Subsequent fleets perform WindowService reference cutover, context/runtime/tasks, semantic UI and provider engines, then whole product surfaces and packaged certification.

Locked invariants remain: keep the accepted W0 history, do not restore disabled Wayland decorations or overlay chrome, do not put the AUR hyprbars package in the install list, preserve Desktop Mode's non-mutating `shell.json` overlay, never hot-unload/reload hyprbars, stay on `work`, never force-push, and never merge `work` into `main` as the OS.

## Audit vs tree (do not rubber-stamp)

Claims from the 2026-08-22 course-correction that this turn **verified in the tree and on metal**:

- Superbar cluster from bar-widget registry; Desktop Mode overlay includes `omarchy.agents`; disk `shell.json` not rewritten — true (`overlayShellConfig`, `TrayCluster.qml`, live disk `bar.id` unset / `position: top`).
- Start is a launcher — true (`Start.qml`).
- Settings is a stub — true (`ultimate-settings/Settings.qml` says so).
- Peek is titles — true. Group close label is **Close group** / **Close window**; the action still closes every window in the group; peek × closes one.
- Three caption buttons (visible min / max / close); maximize hover summons snap chooser; `formatWindowCmd` lives in `barDeco.cpp` — true. 880×560 is fallback only; `window-placements.json` remembers per-app floats — true live (foot 1000×620 at `[120,80]` reopened). `omarchy-update` rebuilds plugins after system packages — true. `--disable-features=WaylandWindowDecorations` must not return — true. `hyprland-plugin-hyprbars` is not in `install/omarchy-other.packages` — true.
- Six numbered forty-task rows automated (20–25) — true. The same harness also runs unnumbered proofs after the loop — true, live exit 0 this session. Pointer proof includes maximize hover and unfocused addressed close — true.
- WindowService is the first fabric provider with `{ changed, error }`, broker, ledger, and invertible restore tokens — true. Full OS capability graph, sandboxed runtime, and Agent Center UI are still missing.

**Nuance / disagreement:**

- `snapLayouts` / `taskView` are not unimplemented; they are prototypes. Flags stay true.
- `omarchy.notifications` exists as a toast/history daemon. That is not Notification Center. Flag is false without claiming notifications are absent.
- Superbar **does** load a tray (`Tray.qml`) and now loads the registry cluster including `omarchy.agents`.
- Files two-row chrome is **gone** on metal (GTK CSD only).
- ~20% is a product estimate, not a test metric.
- Branch/bundle uniqueness: see the locked ledger section above. Zero unique Jesse **content**; one orphan merge SHA (`30aac92f`) with an empty diff. Do not restate “unverified.”

## Phases (vertical product capability)

The named phases below remain the product taxonomy. Execution order now follows the dependency waves in [`ultimate-product-completion-program-2026-08-26.md`](ultimate-product-completion-program-2026-08-26.md), which deliberately builds the Fabric, design, and provider contracts before parallel product-surface assembly.

### Phase 0 — Foundation

Done enough to build on: doctrine, acceptance manifests, profiles, token layer, service convention, test/acceptance harness skeleton. That foundation is on `work`.

Still open: visual regression gallery.

### Phase 1 — Windowing Gate W0

Architecture GO and product-windowing GO on metal (HDMI-A-1 1920×1080, stack through `c1ae994f`). Keep Hyprland. Do not reopen LTRB / hyprbars / CSD / `setHidden` / three-button captions / Files chrome / reopen memory / update-transaction plugin rebuild as if they were still dirty.

The forty-task harness rows 20–25 were necessary and not sufficient for the OS; with the unnumbered proofs they were sufficient as architecture **and** product-windowing evidence for this gate.

### Phase 2 — Agent Fabric (gate)

Historical prototype minimum (2026-08-23): WindowService `{ changed, error }`, caller-labeled local-session allowlist (ui/ipc/agent/undo), ledger `~/.local/state/omarchy/ultimate/capability-ledger.json`, window undo via recorded `restoreNormal` / `restoreLayout`, Superbar cluster from `BarWidgetRegistry` with `omarchy.agents` visible. Same WindowService verbs from QML and `omarchy-shell window`. This was a useful first-provider milestone, not a defensible permission/security pass.

Still missing on purpose: full parity-graph catalog (row 1), persistent Agent Center tasks (8), rich context broker (9), sandboxed Agent Runtime (11). Display/Audio/Network stay panels until Phase 5. Agent Center UI is Phase 4.

### Phase 3 — Design system

Complete the running `shell/Ui` kit and light/dark pipeline with compact/comfortable/touch density, reduced motion, high contrast, accessibility semantics, RTL, pseudo-locales, and a verified state gallery. No Nerd Font salad in consumer chrome. One token/theme pipeline must drive Superbar **and** hyprbars. Not mockups.

### Phase 4 — Desktop shell

Desktop surface, real Superbar (plugin-hosted widgets, previews, jump lists, badges), masterpiece Start, tray, Quick Settings, notification center, calendar, lock. **Agent Center is a normal taskbar-visible and snappable toplevel as first-class as Start** (tasks, active agents, pending actions, automations, history, context; usage widget is one section). At the end of this phase it should already look like a different OS.

### Phase 5 — Settings

First-class app over typed services. Display, Sound, Network, Bluetooth, Input, Personalization, Apps/defaults/startup, Power, Accessibility, Update/Recovery, Region and Language, and System Information. Same verbs as Agent Fabric.

### Phase 6 — Files and defaults

Dolphin, This PC, desktop files, graphical text editor for ordinary `.txt`, MIME defaults, removable media, SMB.

### Phase 7 — Software

One Software surface; pacman/Flatpak/AUR/AppImage are implementation details with trust badges.

### Phase 8 — Windows compatibility

Compatibility Center, not “Wine.” Native / PWA / known-good / game / isolated / VM routing.

### Phase 9 — Administration

Task Manager, Device Manager, Storage, Backup vs snapshots, Recovery, firmware, Troubleshooting Center.

### Phase 10 — OOBE and migration

Only when the product works. No package lists. No Super+K tutorial as first boot.

### Phase 11 — Brutal polish

Every hover, context menu, dialog, empty state, error, DPI, focus ring, reduced motion.

## Program invariants

Keep `4ea1dcf3` through `c1ae994f`. Do not amend them. Do not restore `--disable-features=WaylandWindowDecorations`.

1. Execute the named major program; do not fragment it into disconnected planning or one-off visual work.
2. The first fleet owns Fabric Core, Capability Graph, and Trust Plane in the non-overlapping paths specified by the program. Root owns integration and freezes RPC/schema v1 after adversarial review.
3. Product surfaces consume frozen typed services and operation state. Consumer QML does not gain new process invocation, shell strings, raw `hyprctl`, or privileged logic.
4. Keep LTRB snap, typed compositor dispatch, `/usr/lib/hyprland-plugins` hyprbars, `omarchy-minimize` hidden state, JSON CSD exclusion, addressed captions, three-button SSD, maximize-hover snap, and the measured Chromium frame transforms.
5. Never hot-unload/reload the native plugin. Every native/chrome change gets a fresh compositor restart and the complete right-edge regression campaign.
6. Keep unimplemented profile flags false, preserve Power User Mode, do not teach terminal/hotkey ownership in Desktop Mode, stay on `work`, never create slice branches, never push `main`, and never force-push.

## Acceptance

The three matrices are the core product proofs, and all six release conditions in the current program are mandatory at one packaged candidate SHA:

1. A Windows-native tester completes all forty tasks with the mouse, without Terminal or web search.
2. Every job in `WINDOWS_7_ULTIMATE_PARITY.md` has a certified human route, typed capability mapping, structured errors, and recovery.
3. The `AGENT_NATIVE_ACCEPTANCE.md` path completes the same jobs through the same validators, operations, and recovery.
4. An Omarchy/Arch power user can still use terminal, supported package tooling, original bindings, tiling, workspaces, config editing, scripting, and plugins.
5. Fresh install, upgrade, migration, rollback, factory reset, accessibility, localization, mixed-DPI, hardware, security, recovery, and performance gates pass.
6. No open data-loss, privilege, supply-chain, update/recovery, accessibility-critical, clipping, hidden-control, phantom-success, or stale-progress defect remains.

A green `./test/all` on a machine without Hyprland does not pass W0. A green `windows-native-test.sh` that only talks to `omarchy-shell window` and checks `left.x <= right.x` does not pass W0 and does not pass the OS.
