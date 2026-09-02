---
authority: Windows 7 Ultimate ground truth (FULL CORPUS)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30; SM_CYCAPTION=22 metric only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# WIN7 Spec Index — FULL CORPUS

**Authority:** PRODUCT_DOCTRINE.md (wins conflicts) → `plans/project-ultimate.md` → `WINDOWS_7_ULTIMATE_PARITY.md` → **`plans/win7-ultimate-ground-truth/` full packs**.

Digests are gone. The numbered `0N-*.md` + `.json` twins and `fleet/` packs are the corpus.

**Caption BINDING LOCK:** visual restored top NC = **30** = `SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4)`. `SM_CYCAPTION` **22** is metric band only.

| Surface | Full pack | JSON twin | Fleet / notes | Phases |
|---------|-----------|-----------|---------------|--------|
| Window chrome | [01-window-chrome.md](win7-ultimate-ground-truth/01-window-chrome.md) | [json](win7-ultimate-ground-truth/01-window-chrome.json) | [fleet-aero](win7-ultimate-ground-truth/fleet/fleet-aero-win7.md), [fleet-chrome](win7-ultimate-ground-truth/fleet/fleet-chrome-win7.md) | 1, 3, 11 |
| Start + Superbar | [02-start-superbar.md](win7-ultimate-ground-truth/02-start-superbar.md) | [json](win7-ultimate-ground-truth/02-start-superbar.json) | [fleet-shell](win7-ultimate-ground-truth/fleet/fleet-shell-win7.md) | 4, 1, 11 |
| Explorer / dialogs | [03-explorer-dialogs.md](win7-ultimate-ground-truth/03-explorer-dialogs.md) | [json](win7-ultimate-ground-truth/03-explorer-dialogs.json) | fleet-shell §Explorer | 6, 4, 11 |
| Control Panel | [04-control-panel.md](win7-ultimate-ground-truth/04-control-panel.md) | [json](win7-ultimate-ground-truth/04-control-panel.json) | [fleet-catalog](win7-ultimate-ground-truth/fleet/fleet-catalog-controlpanel.md) | 5, 9 |
| Interaction grammar | [05-interaction-polish.md](win7-ultimate-ground-truth/05-interaction-polish.md) | [json](win7-ultimate-ground-truth/05-interaction-polish.json) | [fleet-doctrine-gaps](win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md) | 11, all |
| Settings / Admin / Media | [06-settings-admin-media.md](win7-ultimate-ground-truth/06-settings-admin-media.md) | [json](win7-ultimate-ground-truth/06-settings-admin-media.json) | fleet-catalog | 5, 6, 7, 9 |

Also: [README](win7-ultimate-ground-truth/README.md) · [00-DOC-INVENTORY](win7-ultimate-ground-truth/00-DOC-INVENTORY.md) · [00-SURFACES-CHECKLIST](win7-ultimate-ground-truth/00-SURFACES-CHECKLIST.md) · [_PHASE_BINDINGS](win7-ultimate-ground-truth/_PHASE_BINDINGS.md) · [_PARITY_ACCEPTANCE_POINTERS](win7-ultimate-ground-truth/_PARITY_ACCEPTANCE_POINTERS.md)

## Anti-invent checklist
1. Job id + mouse behavior. 2. Typed verbs + principal. 3. Human UI route. 4. Banner matches controls. 5. Honest claim/proofStatus. 6. Hide undrivable controls. 7. No mutation on inspect-only. 8. `test/all` ≠ forty-task ≠ OS. 9. Product REJECTED; no `work`→`main` as OS.

Omarchy deltas (barHeight 48, multi-mon bars, Start places, tokens) are labeled inside packs — they are not Win7 truth.
