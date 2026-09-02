# Win7 Ultimate phase bindings

Splice source for `plans/project-ultimate.md`. Under each Phase 0–11, insert a subsection titled exactly `### Win7 Ultimate binding specs` with the bullets below. Link targets are repo-relative from `plans/`. Do not dump full ground-truth bodies into the plan.

Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md). Ground-truth directory: `plans/win7-ultimate-ground-truth/`.

**Product status:** **REJECTED**. Do not merge `work`→`main` as the OS. Do not claim product GO.

## Phase 0 — Foundation

### Win7 Ultimate binding specs

- Catalog and authority chain: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).
- Interaction grammar binds every phase: [`plans/win7-ultimate-ground-truth/07-interaction-grammar.md`](07-interaction-grammar.md).
- Product remains **REJECTED**. These specs stop implementer guessing; they are not an OS go.

## Phase 1 — Windowing Gate W0

### Win7 Ultimate binding specs

- Window chrome / Aero SSD: [`plans/win7-ultimate-ground-truth/01-window-chrome.md`](01-window-chrome.md).
- Superbar / taskbar (gate-adjacent): [`plans/win7-ultimate-ground-truth/03-superbar-taskbar.md`](03-superbar-taskbar.md).
- Caption BINDING LOCK (unchanged):
  - SM_CYCAPTION = 22 → metric band only — never ship a 22 px title bar
  - Restored visual top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4)
  - Visual buttons 29×20 / 27×20 / 49×20; cluster width 105; theme close 28×17; prefer DWMWA_CAPTION_BUTTON_BOUNDS for proof
- Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).

## Phase 2 — Agent Fabric (gate)

### Win7 Ultimate binding specs

- Same-path typed verbs and principals follow [`plans/win7-ultimate-ground-truth/07-interaction-grammar.md`](07-interaction-grammar.md).
- Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).
- Do not invent Settings, Start, or Superbar pages to satisfy fabric rows.

## Phase 3 — Design system

### Win7 Ultimate binding specs

- Chrome metrics and token pipeline bind to [`plans/win7-ultimate-ground-truth/01-window-chrome.md`](01-window-chrome.md) (Caption LOCK in Phase 1; do not ship a 22 px title bar).
- Interaction / density / motion: [`plans/win7-ultimate-ground-truth/07-interaction-grammar.md`](07-interaction-grammar.md).
- Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).

## Phase 4 — Desktop shell

### Win7 Ultimate binding specs

- Start menu: [`plans/win7-ultimate-ground-truth/02-start-menu.md`](02-start-menu.md).
- Start right-pane order (lock): User→Documents→Pictures→Music→Games→Computer→Control Panel→Devices and Printers→Default Programs→Help.
- Superbar / taskbar: [`plans/win7-ultimate-ground-truth/03-superbar-taskbar.md`](03-superbar-taskbar.md).
- Explorer as a desktop-surface consumer: [`plans/win7-ultimate-ground-truth/04-explorer-dialogs.md`](04-explorer-dialogs.md).
- Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).

## Phase 5 — Settings

### Win7 Ultimate binding specs

- Control Panel: [`plans/win7-ultimate-ground-truth/05-control-panel.md`](05-control-panel.md) — 55 applets.
- Settings / defaults / admin / media: [`plans/win7-ultimate-ground-truth/06-settings-defaults-admin-media.md`](06-settings-defaults-admin-media.md).
- Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).

## Phase 6 — Files and defaults

### Win7 Ultimate binding specs

- Explorer / dialogs: [`plans/win7-ultimate-ground-truth/04-explorer-dialogs.md`](04-explorer-dialogs.md) — Explorer command-bar.
- Defaults / associations / media: [`plans/win7-ultimate-ground-truth/06-settings-defaults-admin-media.md`](06-settings-defaults-admin-media.md).
- Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).

## Phase 7 — Software

### Win7 Ultimate binding specs

- Programs / defaults surface bind to [`plans/win7-ultimate-ground-truth/06-settings-defaults-admin-media.md`](06-settings-defaults-admin-media.md).
- Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).

## Phase 8 — Windows compatibility

### Win7 Ultimate binding specs

- No dedicated ground-truth file in [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md); do not invent a Compatibility Center spec in this splice.
- Interaction grammar still binds: [`plans/win7-ultimate-ground-truth/07-interaction-grammar.md`](07-interaction-grammar.md).

## Phase 9 — Administration

### Win7 Ultimate binding specs

- Control Panel: [`plans/win7-ultimate-ground-truth/05-control-panel.md`](05-control-panel.md) — 55 applets.
- Admin / media jobs: [`plans/win7-ultimate-ground-truth/06-settings-defaults-admin-media.md`](06-settings-defaults-admin-media.md).
- Task Manager: six Windows 7 tabs.
- Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).

## Phase 10 — OOBE and migration

### Win7 Ultimate binding specs

- No dedicated ground-truth file in [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md); do not invent an OOBE chrome spec in this splice.
- Interaction grammar still binds: [`plans/win7-ultimate-ground-truth/07-interaction-grammar.md`](07-interaction-grammar.md).

## Phase 11 — Brutal polish

### Win7 Ultimate binding specs

- Full interaction grammar: [`plans/win7-ultimate-ground-truth/07-interaction-grammar.md`](07-interaction-grammar.md).
- Window chrome: [`plans/win7-ultimate-ground-truth/01-window-chrome.md`](01-window-chrome.md) (Caption LOCK remains Phase 1; visual top NC = 30).
- Start: [`plans/win7-ultimate-ground-truth/02-start-menu.md`](02-start-menu.md).
- Superbar: [`plans/win7-ultimate-ground-truth/03-superbar-taskbar.md`](03-superbar-taskbar.md).
- Explorer / dialogs: [`plans/win7-ultimate-ground-truth/04-explorer-dialogs.md`](04-explorer-dialogs.md).
- Control Panel: [`plans/win7-ultimate-ground-truth/05-control-panel.md`](05-control-panel.md).
- Settings / defaults / admin / media: [`plans/win7-ultimate-ground-truth/06-settings-defaults-admin-media.md`](06-settings-defaults-admin-media.md).
- Index: [`plans/WIN7_SPEC_INDEX.md`](../WIN7_SPEC_INDEX.md).
