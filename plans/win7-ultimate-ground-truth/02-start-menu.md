# 02 — Start Menu (Win7 Ultimate)

**Repo path:** `plans/win7-ultimate-ground-truth/02-start-menu.md`  
**Research sources:** `research/02-START-SUPERBAR.md` + `.json` (Start sections), `fleet-shell-win7.md` §1  
**Target phases:** Phase 4 (Desktop shell), Phase 11 (polish)  
**DPI baseline:** **96 DPI / 100%**

---

## Purpose

Binding IA, geometry, right-pane order, power flyout, All Programs, and search grammar for Windows 7 Ultimate Start so implementers never invent Win10 tiles, XP cascading All Programs, or reorderable right-pane places.

---

## Binding metrics (96 DPI)

| Property | BINDING | Notes |
|----------|---------|-------|
| Layout | **Two-pane** fixed | Not user-drag-resizable |
| Total width | **400 px (±10)** | Community/skinning parity target; MS publishes no official width |
| Left pane | **244 px (±8)** | Pinned + MFU + All Programs + search |
| Right pane | **156 px (±8)** | User tile + places + Shut down |
| Row height (large MFU icons) | **36–40** | Icon **32×32** |
| Row height (small MFU icons) | **22–24** | Icon **16×16** |
| Search box height | **28–32** | Bottom of left pane |
| User tile height | **48–56** | |
| Shut down button height | **24–28** | Bottom of right pane |
| Default MFU slots | **10** (`Start_MinMFU`) | Practical max ~30 |
| Orb bitmap | **54×162** strip = 3× **54×54** (normal/hot/pressed) | Overlaps above taskbar top |
| All Programs animation | **~150–250 ms** slide/fade | In-pane replace — **not** XP cascade |

> Omarchy product today uses **720×640** Start card — intentional product delta; Win7 binding above is ground truth. Document deltas explicitly when diverging.

---

## Left pane structure (top → bottom)

1. **Pinned programs** (user reorderable)  
2. **Separator**  
3. **MFU / Recent** (default 10)  
4. **All Programs** (▸) — **in-place** replacement of left pane; **Back** returns  
5. **Search box** — placeholder **"Search programs and files"**

All Programs: click folders to expand in same list; hover does **not** auto-expand. Sort by name default. Sources: `%AppData%\…\Start Menu` + `%ProgramData%\…\Start Menu`.

---

## Right pane — BINDING default order (stock Ultimate)

| # | Label | Opens |
|---|-------|-------|
| 1 | **\<User display name\>** (tile) | `%UserProfile%` |
| 2 | **Documents** | Documents library |
| 3 | **Pictures** | Pictures library |
| 4 | **Music** | Music library |
| 5 | **Games** | Games Explorer |
| 6 | **Computer** | Computer |
| 7 | **Control Panel** | Control Panel (Category default) |
| 8 | **Devices and Printers** | Devices and Printers |
| 9 | **Default Programs** | Default Programs |
| 10 | **Help and Support** | Help |
| — | **Shut down** + ▸ | Power action / flyout |

**Not user-reorderable** without hacks. Customize only show/hide or link vs menu.

### Power flyout order (▸)

1. Switch user  
2. Log off  
3. Lock  
4. Restart  
5. Sleep (if supported)  
6. Hibernate (if enabled)

Main button default label: **Shut down** (configurable).

---

## Interaction matrix

| Gesture | Result |
|---------|--------|
| Left-click orb / Win | Open Start; focus search |
| Win / Esc / click outside / orb again | Close Start |
| Left-click pinned/MFU | Launch; Start closes |
| ▸ or right-click program | Jump List |
| Click All Programs | Left pane → program tree |
| Click Back | Restore pinned+MFU |
| Type | Instant filter; categories Programs / Control Panel / libraries / Files / e-mail |
| Enter | Activate top/focused result |
| Left-click right-pane place | Open destination |
| Left-click Shut down | Default power action |
| Left-click ▸ | Power flyout |
| Right-click orb | Properties / Open Windows Explorer (not app Jump List) |
| Pin / Unpin / Pin to Taskbar | From context menu |
| Drag pinned items | Reorder |

Search: initially top **3** matches per category; “See more results” → Explorer. **Not** file-content-only product invent for Omarchy Start search without indexer honesty.

---

## Win7 vs Omarchy notes

| Win7 | Omarchy today (delta) |
|------|------------------------|
| Right pane: User, Documents, Pictures, Music, Games, Computer, Control Panel, Devices and Printers, Default Programs, Help | Account, Files, Pictures, Computer, Settings, Agent Center |
| Control Panel home | Settings app |
| Search: programs + CP + indexed files | Apps + published Settings/Agent/places — **not** file-content |
| ~400×(MFU-driven height) | 720×640 card |
| Power: Switch user, Log off, Lock, Restart, Sleep, Hibernate | Lock / Restart / Log off / Shut down |

When expanding toward Win7 IA, prefer BINDING right-pane order; Agent Center is a 2026 addition — keep, do not replace Computer/Settings jobs.

**Anti-invent (fleet-doctrine-gaps):** Do not invent file-content search as present; do not invent Overview destinations; Agent Center claim stays non-`present` until product complete.

---

## Citations

- Dummies / Gavilan Start Menu guides; Petri Start Menu; Seven Forums Customize / orb  
- MS Windows Search Features (Win7); AskVG (cascading All Programs not native)  
- `02-START-SUPERBAR.md/.json`, `fleet-shell-win7.md`

---

## Open metal-verify items

1. Exact Start total width on clean Ultimate EN-US Aero @ 1920×1080 / 96 DPI.  
2. Power flyout right-click on Shut down → Properties path.  
3. Confirm Help and Support / Games presence on Ultimate image without Media Center OEM strip.  
4. Search category labels and “See more results” copy on SP1.
