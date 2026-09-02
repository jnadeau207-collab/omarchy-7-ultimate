---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# Win7 Ultimate ground-truth — FULL CORPUS

This directory is the **expanded** Windows 7 Ultimate truth pack for Omarchy Project Ultimate.
Digests are not authority. The numbered `0N-*.md` + `.json` twins and `fleet/` packs are.

| File | Surface |
|------|---------|
| `01-window-chrome.md` + `.json` | Aero SSD caption, borders, buttons, Snap/Shake/Peek, system menu |
| `02-start-superbar.md` + `.json` | Start menu + taskbar/Jump Lists/tray/Show Desktop (full) |
| `03-explorer-dialogs.md` + `.json` | Explorer, Libraries, Recycle, dialogs, context menus |
| `04-control-panel.md` + `.json` | Control Panel shell + applet inventory + deep specs |
| `05-interaction-polish.md` + `.json` | Global mouse/menu/dialog/Aero/hotkey grammar |
| `06-settings-admin-media.md` + `.json` | Personalization, Default Programs, Admin MMC, Task Manager, media |
| `fleet/` | Adversarial fleet packs (Aero/Chrome/Shell/Catalog/Doctrine) |
| `_PHASE_BINDINGS.md` | Splice source for `plans/project-ultimate.md` phases |
| `_PARITY_ACCEPTANCE_POINTERS.md` | Pointers into this corpus (statuses unchanged) |
| `00-DOC-INVENTORY.md` / `00-SURFACES-CHECKLIST.md` | Gap map + surface checklist |

**Omarchy product deltas** (barHeight 48, multi-mon bars, Start places, tokens) are documented as deltas inside the packs — they are not Win7 truth.

Product remains **REJECTED**. Do not merge `work`→`main` as the OS.
