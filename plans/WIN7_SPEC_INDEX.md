# WIN7 Spec Index — Omarchy Project Ultimate

**Authority:** PRODUCT_DOCTRINE.md (wins conflicts) → plans/project-ultimate.md → WINDOWS_7_ULTIMATE_PARITY.md → these ground-truth specs.  
**Product status:** **REJECTED** as an OS. Do not merge `work`→`main` as the OS. Do not claim product GO.  
**DPI baseline:** 96 DPI / 100%. **Caption BINDING LOCK:** visual top NC = **30**; `SM_CYCAPTION` = **22** (metric band only — never ship a 22 px title bar).

Repo tree for commit: `plans/win7-ultimate-ground-truth/` + `plans/WIN7_SPEC_INDEX.md` (this file) + Phase bindings spliced into `plans/project-ultimate.md`.

---

## Surface → research → phase → repo path

| Surface | Ground-truth file | Research sources | Target phase(s) | Repo path |
|---------|-------------------|------------------|-----------------|-----------|
| Window chrome / Aero SSD | [01-window-chrome.md](ground-truth/01-window-chrome.md) | `01-WINDOW-CHROME.md/.json`, `fleet-aero-win7.md`, `fleet-chrome-win7.md` | 1, 3, 11 | `plans/win7-ultimate-ground-truth/01-window-chrome.md` |
| Start menu | [02-start-menu.md](ground-truth/02-start-menu.md) | `02-START-SUPERBAR.md/.json` (Start), `fleet-shell-win7.md` §1 | 4, 11 | `plans/win7-ultimate-ground-truth/02-start-menu.md` |
| Superbar / taskbar | [03-superbar-taskbar.md](ground-truth/03-superbar-taskbar.md) | `02-START-SUPERBAR.md/.json` (taskbar), `fleet-shell-win7.md` §2–5, Peek in aero | 4, 1, 11 | `plans/win7-ultimate-ground-truth/03-superbar-taskbar.md` |
| Explorer / dialogs | [04-explorer-dialogs.md](ground-truth/04-explorer-dialogs.md) | `03-EXPLORER-DIALOGS.md/.json`, `fleet-shell-win7.md` §6 | 6, 4, 11 | `plans/win7-ultimate-ground-truth/04-explorer-dialogs.md` |
| Control Panel | [05-control-panel.md](ground-truth/05-control-panel.md) | `04-CONTROL-PANEL.md/.json`, `fleet-catalog-controlpanel.md` | 5, 9 | `plans/win7-ultimate-ground-truth/05-control-panel.md` |
| Settings / defaults / admin / media | [06-settings-defaults-admin-media.md](ground-truth/06-settings-defaults-admin-media.md) | `06-SETTINGS-ADMIN-MEDIA.md/.json`, catalog §3–4 | 5, 6, 7, 9 | `plans/win7-ultimate-ground-truth/06-settings-defaults-admin-media.md` |
| Interaction grammar | [07-interaction-grammar.md](ground-truth/07-interaction-grammar.md) | `05-INTERACTION-POLISH.md/.json`, aero, `fleet-doctrine-gaps.md` | 11, all (hotkeys) | `plans/win7-ultimate-ground-truth/07-interaction-grammar.md` |

**Companion plan splice:** [PHASE_BINDINGS.md](PHASE_BINDINGS.md) → each Phase 0–11 in `plans/project-ultimate.md`.  
**Parity pointers:** [PARITY_ACCEPTANCE_POINTERS.md](PARITY_ACCEPTANCE_POINTERS.md) → `WINDOWS_7_ULTIMATE_PARITY.md` (honesty; do not mark present).  
**Doctrine gaps:** `research/fleet-doctrine-gaps.md` — 82 jobs invent-risk + 18 vagueness flags + anti-invent checklist.

---

## Doctrine nuance (Rule 3 + Not Aero)

- **Rule 3:** Windows muscle memory is an API — Start, Superbar, captions, Alt+Tab, Win+*, clipboard.  
- **“Not Aero” / “Not a clone”:** refuses ads, telemetry, forced accounts, shipping a Linux-dev box. It does **not** license vague phase blurbs. Match IA, hit targets, menus, sizes; glass texture may approximate.

---

## Anti-invent checklist (must apply to every phase binding)

1. Name job id (`parity.*` / `windows-native.*`) + observable mouse behavior.  
2. Name typed verb(s) + principal; consequential ≠ standing shell grant.  
3. Human route exists in UI.  
4. Coverage text matches banner/controls.  
5. jobs.json claim/proofStatus honest.  
6. Hide undrivable controls.  
7. No mutation UI on inspect-only; no claim walk without capability.  
8. `test/all` green ≠ forty-task ≠ OS ship.  
9. Product REJECTED; no `work`→`main` as OS.
