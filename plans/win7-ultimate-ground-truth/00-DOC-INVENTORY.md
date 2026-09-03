---
authority: Windows 7 Ultimate ground truth (not Omarchy product tokens)
sku: Windows 7 Ultimate
dpi_baseline: 96 DPI / 100%
product_status: REJECTED
caption_binding_lock: "visual restored top NC = 30 = SM_CYFRAME(4)+SM_CYCAPTION(22)+SM_CXPADDEDBORDER(4); SM_CYCAPTION=22 is metric band only — never ship a 22px title bar; buttons 29×20/27×20/49×20; cluster ~105"
---

# 00 — Doc Inventory & Pixel-Spec Gap Map

**Repo:** `jnadeau207-collab/omarchy-7-ultimate` · **ref:** `work`  
**Research date:** 2026-09-02 (America/New_York)  
**Authority (doctrine wins):** `PRODUCT_DOCTRINE.md` + `plans/project-ultimate.md`  
**Product status:** still **REJECTED** as an OS. Phases 0–4 closed as gates (adversarial `152bd844`); Phases 5–11 incomplete.  
**Purpose of this file:** inventory every planning/doctrine/parity doc gathered under `/workspace/w7-specs/docs/`, summarize Phases 0–11, and map **where phase plans lack pixel-level Windows 7 Ultimate specs** an implementer needs (exact colors, px sizes, hit targets, menus, click behaviors, hierarchy, stacking, Control Panel applets).

---

## 1. Complete file list (1-line purpose each)

Paths are under `/workspace/w7-specs/docs/` unless noted. Sizes are approximate.

### Founding doctrine / acceptance (repo root copies)

| File | Purpose |
|------|---------|
| `PRODUCT_DOCTRINE.md` | Locked identity + 8 non-negotiable rules; founding execution authority with project-ultimate. |
| `project-ultimate.md` | Local copy of `plans/project-ultimate.md` — eleven-phase product taxonomy and program invariants. |
| `WINDOWS_7_ULTIMATE_PARITY.md` | Job-completeness matrix (Desktop → Admin jobs + 2026 layers); status `missing`/`plumbing`/`prototype`/`present`. |
| `WINDOWS_NATIVE_ACCEPTANCE.md` | Forty-task human smoke test (necessary ≠ sufficient); only rows 20–25 automated. |
| `AGENT_NATIVE_ACCEPTANCE.md` | Agent-side same-path matrix (historical freeze note; OS pass bar still applies). |
| `W0_GATE.md` | Single authority on Windowing Gate W0 definition + evidence checklist (Phase 1 only). |
| `AGENTS.md` | Repo agent/task guides, branch rules (`main`/`work` only), style, tests. |
| `CLAUDE.md` | Tiny pointer stub (11 bytes). |
| `desktop-mode-handoff.md` | Historical live Hyprland windowing evidence (snap/SSD/minimize/pointer numbers); not product go. |
| `chrome-tokens.json` | Generated dark `omarchy.chrome-adapter.v0` projection (glass/caption/border hexes). |
| `chrome-tokens-light.json` | Generated light chrome adapter projection. |
| `plans-listing.txt` | Snapshot listing of `plans/*` names on the branch. |

### Phase / program handoffs (fetched)

| File | Purpose |
|------|---------|
| `HANDOFF_PHASE3_2026-08-29.md` | Phase 3 design-system GO lock (`119439b2`): one token resolver, Superbar+hyprbars, no Nerd Font salad. |
| `HANDOFF_PHASE4_2026-08-29.md` | Phase 4 desktop-shell GO lock (`c03b2cb4`): Start/QS/NC/lock/Agent Center host; OS still rejected. |
| `HANDOFF_PHASE04_ADVERSARIAL_2026-08-31.md` | Phase 0–4 adversarial close (`152bd844`): 20/20 gates; command-injection fix; typography/pseudo-locale/RTL; pixels-only defects. |
| `HANDOFF_PHASE12_2026-08-29.md` | Phase 1/2 honesty close: dirty-tree maximize-state + fabric leftover; **Accepted W0 tree not written** in that file. |

### W0 tranche plans (fetched `plans/`)

| File | Purpose |
|------|---------|
| `plans/w0-tranche.md` | Tranche B — work-area truth, hyprbars SSD, remembered float; live px geometry evidence. |
| `plans/w0-tranche-c.md` | Tranche C — real pointer proof requirements/evidence. |
| `plans/w0-tranche-d.md` | Tranche D — native minimize (`setHidden`) vs `special:minimized`. |
| `plans/w0-tranche-e.md` | Tranche E — hyprbars off hyprpm cache into `/usr/lib/hyprland-plugins`. |
| `plans/w0-tranche-f.md` | Tranche F — Alt+Tab address-change correctness. |
| `plans/w0-tranche-g.md` | Tranche G — quarters, Aero peek affordances, snap chooser, layouts. |

### Other plans (fetched; mostly non–Win7-chrome)

| File | Purpose |
|------|---------|
| `plans/ultimate-capability-engines-product-ownership-convergence-2026-08-27.md` | Fleet ownership / capability engines convergence (fabric+product owners); not pixel IA. |
| `plans/backup.md` | Backup/restore product plan (plumbing → consumer UI). |
| `plans/dots.md` | Dotfiles / config ownership plan. |
| `plans/remote.md` | Remote access product plan. |
| `plans/server.md` | Server/login/menu/update imagery plan. |

### Design system / contracts (fetched)

| File | Purpose |
|------|---------|
| `default/ultimate/design-system/defaults-v0.json` | Non-palette defaults: density scales, chromeProfiles, motion, effects, hitTargetsPx, captionMetricsPx. |
| `default/ultimate/start-chrome.json` | Start card + bar chrome numbers: 720×640 card, barHeight 48, cardLeftMargin 8. |
| `default/ultimate/product-contracts/surfaces-v0.json` | Provisional plugin/surface inventory (45 plugins: availability, roles — **not** Win7 layout specs). |
| `default/ultimate/capabilities/window-surface-v0.json` | WindowService method/IPC surface contract (verbs, not pixels). |
| `default/ultimate/administration/provider-catalog-v0.json` | Phase 9 admin providers (account/device/firewall/printer/process/…); plan-only, no UI layouts. |
| `default/ultimate/quality/gallery-matrix-v0.json` | Accessible state-gallery axes (theme/density/scale/contrast/motion/locale/RTL) + automated contrast/hit-target checks. |
| `repo-docs/design-tokens.md` | Token pipeline contract: groups, resolver, SemanticProfile, chrome adapter lock values. |
| `repo-docs/theming.md` | Theme packs / `omarchy-theme-set` reference. |
| `repo-docs/omarchy-shell.md` | Quickshell shell architecture reference. |
| `repo-docs/mode-profiles.md` | Desktop vs Power User profile flags. |
| `repo-docs/menu.md` | Omarchy menu system (heritage; not Win7 Start IA). |
| `repo-docs/notifications.md` | Notification daemon / history plumbing. |
| `repo-docs/settings-service-api.md` | UI → typed service → system tooling convention. |
| `repo-docs/standalone-product-apps.md` | Product app host (Settings/Files/Agent Center process model). |
| `repo-docs/product-contracts.md` | Product-contracts schema overview. |

### Notable repo docs **not** fully mirrored here (exist on `work`; listed for completeness)

Also on branch and relevant to later pixel/behavioral work but not required for this inventory’s core:  
`docs/accessibility-performance.md`, `docs/capability-graph.md`, `docs/fabric-*`, `docs/files-defaults-provider.md`, `docs/software-compatibility-providers.md`, `docs/administration-recovery-providers.md`, `docs/testing.md`, `default/ultimate/parity/jobs.json`, `default/ultimate/product-contracts/applications-v0.json`, visual goldens under `default/ultimate/quality/visual-goldens/`, additional `HANDOFF_W0_*` / write-plane handoffs.

---

## 2. Phase 0–11 summary (from `project-ultimate.md`)

Locked identity: **Windows 7 Ultimate’s complete, obvious, mouse-native desktop model rebuilt for 2026, with an agent-native operating fabric underneath every system capability.**

| Phase | Name | Intent (plan text) | Gate status (docs as of handoffs) |
|------:|------|--------------------|-----------------------------------|
| **0** | Foundation | Doctrine, acceptance manifests, profiles, token layer, service convention, harness skeleton; visual regression gallery. | Closed enough to build on; adversarial Phase 0–4 bundle green at `152bd844`. |
| **1** | Windowing Gate W0 | Hyprland stays; 3-button SSD; one-row CSD; min/max/restore; LTRB snap+chooser; Alt+Tab; Show Desktop; reopen memory; click-to-raise; Start click-through. | Product-windowing GO claimed in plan text / W0 metal campaigns; `W0_GATE.md` remains the checklist authority. Not an OS go. |
| **2** | Agent Fabric (gate) | Capability broker, ledger, undo, persistent tasks, context broker, sandboxed runtime; WindowService first provider. | Prototype leftovers advanced; Settings *inspect* readers exist; typed **writers** deferred to Phase 5. `parity.agent-center` must stay non-`present` as fabric claim. |
| **3** | Design system | Complete `shell/Ui` kit + light/dark + density + a11y + RTL + pseudo-locales + verified state gallery; one token pipeline for Superbar **and** hyprbars. | **GO** `119439b2` (HANDOFF_PHASE3). Not pixel-perfect Win7 Aero. |
| **4** | Desktop shell | Desktop surface, real Superbar (previews, jump lists, badges), masterpiece Start, tray, Quick Settings, Notification Center, calendar, lock; Agent Center as normal toplevel. | **GO** `c03b2cb4` (HANDOFF_PHASE4); adversarial close `152bd844`. Still prototype vs finished Win7 taskbar/Start. |
| **5** | Settings | First-class app over typed services: Display, Sound, Network, Bluetooth, Input, Personalization, Apps/defaults/startup, Power, Accessibility, Update/Recovery, Region/Language, System Information. | **Not closed.** Inspect pages exist; **typed writers missing**. No Win7 Control Panel applet layouts. |
| **6** | Files and defaults | Dolphin/This PC, desktop files, graphical txt editor, MIME defaults, removable media, SMB. | **Not closed.** Product Files prototype (parity: rename and in-app copy/paste landed as claim=partial; cut/OS clipboard/column resize/Explorer present absent). |
| **7** | Software | One Software Center; pacman/Flatpak/AUR/AppImage as trust-badged details. | **Missing** as product surface. |
| **8** | Windows compatibility | Compatibility Center (not “Wine”): Native / PWA / known-good / game / isolated / VM routing. | **Missing.** |
| **9** | Administration | Task Manager, Device Manager, Storage, Backup vs snapshots, Recovery, firmware, Troubleshooting Center. | Providers plan-only; **no consumer UIs**. |
| **10** | OOBE and migration | Only when product works; no package-list first boot; no Super+K tutorial. | **Missing.** |
| **11** | Brutal polish | Every hover, context menu, dialog, empty state, error, DPI, focus ring, reduced motion. | Explicitly the polish phase — **and the place where missing pixel specs hurt most**, because earlier phases never wrote Win7-accurate surface books. |

---

## 3. Per-phase: what exists today vs what is MISSING for an implementer

Legend for “exists”: **D** = doctrine/job language · **T** = tokens/metrics numbers · **G** = live geometry evidence · **U** = UI prototype description · **C** = contracts/catalogs · **P** = pixel-accurate Win7 behavioral/layout book.

### Phase 0 — Foundation

| Exists | Missing for pixel-level Win7 specs |
|--------|-------------------------------------|
| Doctrine + three acceptance matrices; profiles; token defaults; gallery matrix axes; visual goldens for a few chrome shots. | No master **surface specification book** indexed by Win7 object (orb, Jump List, Explorer command bar, etc.). No requirement that goldens match Win7 Ultimate Aero measurements — goldens prove *our* chrome. No catalog of Win7 system fonts (Segoe UI) vs shipped Liberation Sans as intentional delta. |

### Phase 1 — Windowing Gate W0

| Exists | Missing |
|--------|---------|
| Rich live geometry (**G**): bar heights historically 40 then 48; hyprbars `bar_height` 32; default float `880×560`; snap halves with 32px caption inset; caption button colors from tokens; three-button SSD; maximize-hover → snap chooser; CSD exclusion JSON; reopen memory rules; pointer proofs. Tranche B–G narrative. | **No Win7 Aero Glass title-bar pixel bible:** exact caption button glyph shapes/sizes/spacing vs Vista/7 Aero; inactive vs active gradient stops; border highlight widths; resize grip hit boxes; shadow radii matching Aero; double-click titlebar vs caption-button exclusion zones; Aero Shake / Aero Peek / Aero Snap **behavioral** matrix beyond LTRB halves/quarters; multi-monitor maximize-to-monitor edge cases as Win7 did; MDI vs toplevel stacking. `start-chrome.json` has only 4 numbers — not a window-chrome spec. |

### Phase 2 — Agent Fabric

| Exists | Missing |
|--------|---------|
| WindowService verbs, broker/ledger/undo, managed-work, sandbox inspect; Settings **inspect** wiring notes. | Agent Fabric is **not** a visual phase — but Agent Center *UI* (Phase 4 host) still lacks Win7-analogue IA (no MMC-style console, no Action Center mapping). No pixel/behavior spec for consent dialogs, approval cards, or progress sheets beyond Semantic UI vocabulary. |

### Phase 3 — Design system

| Exists (**T**) | Missing (**P**) |
|----------------|------------------|
| `defaults-v0.json`: density 0.86/1.0/1.25; hitTargets 24/28/32/44; captionMetrics height 32 / button 22 / pad 8 / h-pad 12; motion 100/200/300 ms OutCubic; blur 8px/2 passes; shadow; focus ring 1+1; dark/light chromeProfiles (glass, glow `#e8943a`/`#3a76a8`, start `#9cbc0d`/`#55875c`, close `#c42b1c`/`#b85750`, min/max `#c8c8c8`/`#5c6873`). Semantic controls list. Gallery contrast ≥4.5:1. | **Tokens are Ultimate 2026 language, not Win7 Ultimate Aero.** Missing: Aero blue glass palette (`#A0C0E0`-class), Start orb gradients, taskbar bottom bevel, orange Start highlight, classic menu separators, Segoe UI 9pt metrics, icon grid 32/48/256, Control Panel category icon sizes, Explorer toolbar glyph sheet. No per-control **state tables** (normal/hot/pressed/disabled/default) with hex+px for every chrome control. No RTL mirroring rules for Win7-specific chrome (Start opens left vs right). Nerd Font ban ≠ Win7 iconography inventory. |

### Phase 4 — Desktop shell

| Exists (**U**/**G**) | Missing (**P**) |
|----------------------|-----------------|
| Start two-pane **720×640**, left margin 8, bar **48**; orb; peeks (grim); jump lists (verbs listed in parity); QS nine tiles; Notification Center; calendar; lock preview; multi-monitor bar policy prose; Agent Center snappable host. `surfaces-v0.json` lists plugins. | **No masterpiece Start pixel map:** column widths, search box height, pin tile size/gap, All-programs letter sticky header metrics, right-pane place icon size, power flyout geometry, account tile, hover/selection colors. **No Superbar pixel map:** button width rules, grouping, progress/badge placement, Peek thumbnail size/offset/delay, Jump List width/row height/separator rules, Show Desktop strip width, notification cluster icon order/spacing, tooltip delay/style. **No stacking/z-order doctrine** for Start vs Peek vs Jump List vs QS vs NC vs lock vs OSD vs snap chooser (partially in prose for lock only). **No full right-click menu trees** with every item, enablement, and keyboard accel. Desktop icons: size, grid, label wrap, selection marquee, **full desktop context menu** still Phase 6 / missing. Recycle Bin behavior unspecified at pixel/IA level. |

### Phase 5 — Settings

| Exists | Missing |
|--------|---------|
| Settings as snappable window with nav; pages listed (Display/Sound/Network/Bluetooth/Power/Personalization/Apps/Update/Recovery + honest missing Accessibility/System info); Fabric inspect; jump-list route names. | **No Control Panel / Settings applet specs:** Win7 Category vs icon view; every applet layout (Display → Resolution/Orientation/Multiple displays/Color; Sound → Playback/Recording/Sounds/Communications; Network and Sharing Center map; Devices and Printers; Power Options plans+advanced; Personalization themes/Aero/desktop icons/sounds/mouse pointers; Region and Language; Ease of Access Center). No writer UX: apply/cancel/OK, live preview, UAC elevation chrome. No pixel layouts for sidebar width, content margins, control spacing matching Win7 or a deliberate 2026 redesign **documented as such**. |

### Phase 6 — Files / Explorer

| Exists | Missing |
|--------|---------|
| Product Files prototype description: back/forward, breadcrumb, search box, command bar, nav pane (Favorites/Libraries/Computer/Network/Recycle), views Details/Large Icons/List, details pane, context menu stub, Properties General tab, Computer drive groups + capacity bars; honest absences (cut/OS clipboard, column resize, thumbnails). Rename, Open, and in-app Copy/Paste are typed planes, not Explorer-complete. | **No Explorer chrome bible:** command-bar button set vs Win7; Library definitions; Details pane field list; status bar segments; view options (Extra large/Medium/Tiles/Content); column defaults + sort glyphs; **complete context menus** (file/folder/background/Computer/Recycle); Properties sheets (General/Sharing/Security/Previous Versions/Customize); dialog geometries (Copy progress, Replace, Delete confirm); address bar path segment hit targets; search MRU. Desktop ↔ Explorer drag/drop rules. |

### Phase 7 — Software

| Exists | Missing |
|--------|---------|
| Phase one-liner; pacman/AUR/Flatpak as plumbing. | Entire **Programs and Features / Software Center** IA: browse/search/categories, trust badges layout, install progress sheet, uninstall list columns, source filters — zero pixel or behavioral specs. |

### Phase 8 — Compatibility

| Exists | Missing |
|--------|---------|
| Routing vocabulary (Native/PWA/known-good/game/isolated/VM). | Zero UI: Compatibility Center pages, .exe drop target, recipe picker, risk copy, progress — no specs. |

### Phase 9 — Administration

| Exists | Missing |
|--------|---------|
| Provider catalog IDs (account, backup, device, diagnostics, firewall, printer, process, recovery, schedule, service, storage, update) — plan-only. | Every Win7 admin surface: **Task Manager** tabs (Applications/Processes/Services/Performance/Networking/Users) column sets; **Device Manager** tree; **Disk Management**; **Services.msc**; **Task Scheduler**; **Event Viewer**; **Firewall** advanced; **Credential Manager**; **User Accounts**; Troubleshooting wizards — **no layouts, menus, or hit targets**. |

### Phase 10 — OOBE / migration

| Exists | Missing |
|--------|---------|
| “Only when product works” rule; anti-patterns named. | No OOBE screen list, sizes, copy, language picker, network, account, privacy (doctrine refuses telemetry — still needs screens), migration from Windows — zero wireframes/specs. |

### Phase 11 — Brutal polish

| Exists | Missing |
|--------|---------|
| Phase statement; gallery axes; Semantic operation vocabulary; focus/hit-target defaults. | Phase 11 assumes earlier surfaces have specs to polish against. **They do not.** Missing: exhaustive hover/press/disabled tables; empty states; error sheets; DPI@100/125/150/200 cropping rules for every chrome surface; focus ring vs Win7 dotted focus; reduced-motion replacements for Aero transitions. |

---

## 4. Explicit list of surfaces that need full Win7 Ultimate behavioral specs

Surfaces below need a **full behavioral + pixel** spec (states, hierarchy, stacking, left-click, right-click menu trees, keyboard accelerators as optional, sizes, colors or token refs, empty/error). Checked items have *some* product prose or numbers; none have a complete Win7-grade book.

### Shell chrome & windowing
1. Server-side window frame (hyprbars) — active/inactive, caption buttons, drag, double-click, edge/corner resize  
2. Client-side decorations (Chromium/GTK) — one-row fusion rules  
3. Snap: halves, quarters, maximize, restore, drag-to-edge, maximize-hover chooser, Win+Arrow  
4. Aero Peek / Show Desktop  
5. Alt+Tab / Task View analogue  
6. Window stacking, activation, click-to-raise, multi-monitor move  
7. Reopen memory / cascade / clamp rules (partially specified)

### Superbar (taskbar)
8. Start orb (normal/hot/pressed/open)  
9. Pinned vs running buttons, grouping, badges, progress  
10. Hover Peek thumbnails (size, delay, live vs title-only)  
11. Jump Lists (pin/unpin, destinations, Close window/group, separators)  
12. Notification area / tray cluster order, hide inactive, overflow  
13. Clock + calendar flyout  
14. Quick Settings (tiles, deep links, writers)  
15. Notification Center (list, clear, focus assist analogue)  
16. Show Desktop end-cap  
17. Multi-monitor Superbar ownership rules (prose exists; pixel gaps remain)  
18. Superbar context menus (toolbar lock, cascades — mostly unspecified)

### Start
19. Start menu card geometry & two-pane IA  
20. Search box + ranking (apps/settings/places — not file content)  
21. Pins / Recent / All programs letter groups  
22. Right-pane places (User/Files/Pictures/Computer/Settings/Agent Center)  
23. Power flyout (Lock/Restart/Log off/Shut down)  
24. Start right-click menus (parity with Jump Lists)  
25. Dismiss / click-through / owner-output rules (behavioral mostly done; pixels thin)

### Desktop
26. Wallpaper & Personalization entry points  
27. Desktop icons (align, auto-arrange, size, labels)  
28. Desktop context menu (View/Sort/Refresh/Paste/Personalize/…)  
29. Recycle Bin (empty/full icons, restore, Properties)  
30. Computer / User folder shortcuts  
31. Marquee selection & drag to Superbar/Start

### Explorer / Files
32. Window chrome + navigation (back/forward/up)  
33. Address bar / breadcrumb  
34. Search box (in-app)  
35. Command bar  
36. Navigation pane  
37. Folder views & columns  
38. Details / preview pane  
39. Status bar  
40. This PC / Computer view  
41. Libraries  
42. Recycle Bin folder view  
43. Network places  
44. File/folder context menus  
45. Properties multi-tab dialogs  
46. Copy/Move/Delete progress & conflict dialogs  
47. Rename in-place  
48. Clipboard cut/copy/paste  
49. Removable media & eject  
50. SMB map/disconnect

### Settings / Control Panel applets (Phase 5+9)
51. Settings shell (nav, search, apply model)  
52. Display  
53. Personalization (theme/wallpaper/screensaver/icons/pointers)  
54. Sound  
55. Network and Sharing / Wi-Fi  
56. Bluetooth / Devices and Printers  
57. Power Options  
58. Apps / Default Programs / Startup  
59. Input / Region and Language  
60. Accessibility / Ease of Access  
61. Update  
62. Recovery / System Restore UI  
63. System Information  
64. User Accounts  
65. Credential Manager  
66. Firewall  
67. Device Manager  
68. Disk Management / Storage  
69. Backup and Restore  
70. Parental/privacy (doctrine-shaped; still needs screens)

### Dialogs & system UI
71. Common File Open/Save  
72. Print dialogs  
73. UAC / polkit elevation chrome  
74. Operation / Destructive dialogs (Semantic UI exists; Win7 task-dialog mapping thin)  
75. OSD volume/brightness  
76. Lock screen / logon  
77. Ctrl+Alt+Del / security options analogue  
78. Balloon/toast vs Action Center semantics

### Apps & later phases
79. Software Center  
80. Compatibility Center  
81. Task Manager  
82. Resource Monitor  
83. Services  
84. Task Scheduler  
85. Event Viewer / history  
86. Troubleshooting Center  
87. Agent Center (full IA beyond inspect host)  
88. OOBE / first-boot  
89. Migration wizard  
90. Remote Desktop client surface  
91. Drive encryption UX  
92. Games / Proton surface  

---

## 5. Key gaps (executive)

1. **Doctrine + parity name jobs; they do not specify pixels.** An implementer can know *that* Jump Lists must exist, not *how tall a Jump List row is* or *exact menu item order matching Win7*.  
2. **Design tokens specify Ultimate 2026 chrome, not Win7 Aero.** Caption/hit-target numbers exist (`captionMetricsPx`, `hitTargetsPx`, Start 720×640, bar 48) but are product choices without a Win7 measurement baseline or a written “intentional delta” table.  
3. **Phase 4 “masterpiece Start / real Superbar” closed as engineering GO without a surface specification book** — risk of polish phase inventing aesthetics inconsistently.  
4. **Control Panel / admin applets have zero layout specs**; Phase 5/9 plans are capability-oriented.  
5. **Explorer behavioral gaps are listed (rename/clipboard/…)** but not specified as Win7 interaction sequences.  
6. **Right-click-everywhere** is doctrine Rule 3; only Superbar/Start/peek menus are described — desktop/Explorer/full shell menus are incomplete.  
7. **Stacking/z-order** partially covered for lock vs peeks; not a global compositor UI layer doctrine.  
8. **Phase 11 cannot polish what Phases 3–10 never specified** at pixel/behavior level.

**Companion file:** `/workspace/w7-specs/out/00-SURFACES-CHECKLIST.md`

---

## 6. Research packs on box (`/workspace/w7-specs/research/`)

Fleet Win7 ground-truth packs complement doctrine (not founding authority): `fleet-aero-win7.md`, `fleet-chrome-win7.md`, `fleet-shell-win7.md`, `fleet-catalog-controlpanel.md`, `fleet-doctrine-gaps.md`, plus structured `01`–`06` JSON/MD packs and `_src_*` mirrors. Use these to fill pixel/behavior gaps listed above; doctrine still wins on product identity conflicts.

