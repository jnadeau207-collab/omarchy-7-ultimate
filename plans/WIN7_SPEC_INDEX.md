# WIN7 Spec Index — Omarchy Project Ultimate

**Authority:** PRODUCT_DOCTRINE.md (wins conflicts) → plans/project-ultimate.md → WINDOWS_7_ULTIMATE_PARITY.md → these ground-truth specs.  
**Product status:** **REJECTED** as an OS. Do not merge `work`→`main` as the OS. Do not claim product GO.  
**DPI baseline:** 96 DPI / 100%. **Caption BINDING LOCK:** visual top NC = **30**; `SM_CYCAPTION` = **22** (metric band only — never ship a 22 px title bar).

Repo tree for commit: `plans/win7-ultimate-ground-truth/` + `plans/WIN7_SPEC_INDEX.md` (this file) + Phase bindings spliced into `plans/project-ultimate.md`.

## Surface → research → phase → repo path

| Surface | Ground-truth file | Research sources | Target phase(s) | Repo path |
|---------|-------------------|------------------|-----------------|-----------|
| Window chrome / Aero SSD | [01-window-chrome.md](win7-ultimate-ground-truth/01-window-chrome.md) | `01-WINDOW-CHROME`, fleet-aero, fleet-chrome | 1, 3, 11 | `plans/win7-ultimate-ground-truth/01-window-chrome.md` |
| Start menu | [02-start-menu.md](win7-ultimate-ground-truth/02-start-menu.md) | `02-START-SUPERBAR`, fleet-shell | 4, 11 | `plans/win7-ultimate-ground-truth/02-start-menu.md` |
| Superbar / taskbar | [03-superbar-taskbar.md](win7-ultimate-ground-truth/03-superbar-taskbar.md) | `02-START-SUPERBAR`, fleet-shell | 4, 1, 11 | `plans/win7-ultimate-ground-truth/03-superbar-taskbar.md` |
| Explorer / dialogs | [04-explorer-dialogs.md](win7-ultimate-ground-truth/04-explorer-dialogs.md) | `03-EXPLORER-DIALOGS`, fleet-shell | 6, 4, 11 | `plans/win7-ultimate-ground-truth/04-explorer-dialogs.md` |
| Control Panel | [05-control-panel.md](win7-ultimate-ground-truth/05-control-panel.md) | `04-CONTROL-PANEL`, fleet-catalog | 5, 9 | `plans/win7-ultimate-ground-truth/05-control-panel.md` |
| Settings / defaults / admin / media | [06-settings-defaults-admin-media.md](win7-ultimate-ground-truth/06-settings-defaults-admin-media.md) | `06-SETTINGS-ADMIN-MEDIA`, catalog | 5, 6, 7, 9 | `plans/win7-ultimate-ground-truth/06-settings-defaults-admin-media.md` |
| Interaction grammar | [07-interaction-grammar.md](win7-ultimate-ground-truth/07-interaction-grammar.md) | `05-INTERACTION-POLISH`, aero, fleet-doctrine-gaps | 11, all | `plans/win7-ultimate-ground-truth/07-interaction-grammar.md` |

**Companion:** `_PHASE_BINDINGS.md` (splice source) + `_PARITY_ACCEPTANCE_POINTERS.md` under `plans/win7-ultimate-ground-truth/`.

## Doctrine nuance
- Rule 3: Windows muscle memory is an API.
- “Not Aero” refuses ads/telemetry — not vague chrome.

## Anti-invent checklist
1. Name job id + mouse behavior. 2. Typed verbs + principal. 3. Human UI route. 4. Banner matches controls. 5. Honest claim/proofStatus. 6. Hide undrivable controls. 7. No mutation on inspect-only. 8. test/all ≠ forty-task ≠ OS. 9. Product REJECTED; no work→main as OS.
