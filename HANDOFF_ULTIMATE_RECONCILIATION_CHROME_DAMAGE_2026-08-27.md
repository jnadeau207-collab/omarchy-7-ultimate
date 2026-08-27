# Omarchy Ultimate reconciliation and Chrome damage handoff — 2026-08-27

## Goal

Reconcile the recent Omarchy Ultimate work across the main checkout, GitHub, the package and ISO checkouts, and the physical metal machine; finish the live Chromium/Chrome compositor defect; preserve the large landed tranche; and leave a durable resume point for the next session.

## State of world

- Main checkout: `C:\dev\omarchy7ultimate`, branch `work`, clean, `HEAD fb0d4b35cf12c2844c889ae6b5553c4494c5f4ad` (documentation handoff commit; code parent `9932c62b40bd32ab31989547bbe818da4b0235d8`), and `origin/work` is the same commit.
- Main repository has one worktree only. There are no stashes or tracked/untracked product diffs. Ignored entries are generated Python `__pycache__` directories plus `.aider.chat.history.md` and `.aider.input.history`; these are not Git work and were not deleted because the history files are user data.
- GitHub `origin/work` is exactly `fb0d4b35cf12c2844c889ae6b5553c4494c5f4ad`.
- Package checkout `C:\dev\omarchy-pkgs` and `/home/jesse/omarchy-pkgs` are clean at `e902923c2b2f48948bbd95571186c045fac4b8b6`, with local `work` tracking `ultimate/work`.
- ISO checkout `C:\dev\omarchy-iso` and `/home/jesse/omarchy-iso` are clean at `268bac16d351a21d867e37565738f458b11cb06c`, with `quattro` tracking `origin/quattro`.
- Metal is `jesse@192.168.1.171`; `/home/jesse/omarchy7ultimate` is clean at `fb0d4b35cf12c2844c889ae6b5553c4494c5f4ad`.
- Metal compositor service `wayland-wm@hyprland.desktop.service` is active. Current Hyprland PID is `1414672`; current plugin mapping is inode `67821` from the checkout, with no `(deleted)` mapping. `omarchy-minimize` and `hyprbars` are loaded. Animations are enabled.
- A coredump from PID `1401272` exists at `08:10:41`, during the old-to-new compositor restart boundary. There are no coredumps after `08:11:00`; the current compositor PID is `1414672`.
- The fresh real Google Chrome proof window remains centered on metal: address `0x558ec87c6df0`, position `[388,142]`, size `[1004,764]`, floating, non-fullscreen, class `google-chrome`, title `about:blank - Google Chrome`.

## Done and verified

### Chrome compositor defect

The root cause was the deliberate Chromium native-CSD texture overhang: the visible Chrome frame is expanded by `CHROMIUM_FRAME_INSET` (12 px), but ordinary compositor damage only covered the nominal window box. Moving or resizing could therefore leave the old perimeter in the damage ring, producing the flashing ghost outline and making the right caption edge look clipped.

The landed fix keeps old and new overhang boxes in the damage path for all motion classes:

- `5e449598` clears old overhang during animation.
- `8e4c9876` covers interactive pointer drags.
- `52532945` detects direct non-animated moves/resizes by comparing boxes.
- `9932c62b` invokes the same comparison from Hyprland `render.pre`, before each scheduled frame snapshots damage, covering settled/direct jumps that do not emit animation ticks.
- `0a803c9c` and `b4e96183` are the underlying native-CSD texture expansion and right-corner geometry repairs.

The metal proof used a fresh real Google Chrome process with direct moves and an absolute-pointer title-bar drag. Six direct-motion frames reported `outside_pixels=0` outside the current window plus the 20 px perimeter; the physical drag also settled without stale perimeter pixels. The centered screenshot shows both top corners rounded and the complete right close glyph. Evidence retained locally:

- `C:\dev\omarchy-vm\chrome-render-pre-centered-final.png`
- `C:\dev\omarchy-vm\chrome-render-pre-direct-contact.png`
- `C:\dev\omarchy-vm\chrome-render-pre-drag-after.png`

The temporary remote proof directory and log were removed. The visible proof Chrome profile is intentionally left running for continuity; it is under `/tmp/chrome-render-pre-profile` on metal.

### Tests and checks

- `bash test/shell.d/ultimate-desktop-plugin-test.sh` passed, including the render-pre assertion.
- `bash test/shell.d/omarchy-minimize-csd-test.sh` passed.
- `bash test/shell.d/window-service-test.sh` passed.
- `git diff --check` passed.
- `bash test/all` ran the complete 233-file aggregate but is not an environment-clean pass. The Fabric core, managed-work, provider, software, compatibility, packaging, Settings, Agent Center, product, and Chrome-related tests that ran with their dependencies passed. The aggregate reported 18 files failing primarily because this Windows/WSL runner lacks `rg`, `python`, `xkbcli`, `hyprctl`, `update-desktop-database`, and related host commands; one Files fixture is host-path-sensitive. Do not call the aggregate green until it is rerun in the supported metal/VM environment with those dependencies.
- Metal service/plugin/runtime checks passed after the final build and full compositor restart.

## Catalog of landed work

The recent work is a large convergent tranche, not a small slice:

| Area | Landed commits | Result |
| --- | --- | --- |
| Typed Fabric foundation | `8a1f0c37`, `a4346634`, `960db1a4` | Explicit provider registry and typed system-domain providers. |
| Standalone product hosts and UI | `196e98f0`, `723d669f`, `310ba8bd`, `ed8e642e`, `698b3f42`, `6a2804e4` | Settings, Agent Center, accessibility, focus recovery, and Ultimate baseline surfaces. |
| Durable managed work and contracts | `1bb15c88`, `88250d43`, `81356ecd`, `dd9c52b5`, `4757bce5` | Durable work plane, standalone app contracts, catalog assertions, and IPC trust classification. |
| Provider families | `36adeb38`, `6d4de2b5`, `a4278277`, `0cc7c53b` | Files/defaults, software/compatibility, and administration/recovery provider sets. |
| Ownership and coordination | `a8e18449`, `a371c01a` | Stable managed-work ownership and durable operation coordinator foundation. |
| Product surfaces and documentation | `fef56cf7`, `a173ac3e` | Standalone product application surfaces and reconciled product-contract documentation. |
| Chrome/CSD and damage | `b4e96183`, `0a803c9c`, `71f13884`, `5e449598`, `8e4c9876`, `52532945`, `9932c62b` | Native CSD geometry, full caption glyph, rounded corners, and old/new perimeter damage for animation, drag, direct move, and render-pre paths. |

The product/docs range `a371c01a..9932c62b` is 53 files, 7,442 insertions, and 485 deletions. Current inventory is 25 apps (22 legacy-unjoined/heuristic and 3 present-contract/stable), 8 processes (6 present, 1 dynamic, 1 external), 37 invocation components, 27 IPC entries, and 25 invocation routes. Ten legacy debts remain open: invocation context, first-bar instance, focus, heuristic identity, product principal, legacy search shapes, untyped mutations, direct consumer execution, shared shell principal, and IPC caller binding.

## Done but not release-complete

- `omarchy-pkgs` is clean and pushed, but its `omarchy-dev` PKGBUILDs and `bin/check-ultimate-fabric-pair` still pin Ultimate commit `5504a044d34b0c44e3b3ab57f3f6fc5e6d427719`, behind main `9932c62b`. The package candidate has not been repinned/rebuilt for this final source.
- Stable metal packages are Omarchy `4.0.0-1` and `omarchy-settings 4.0.0-1`; the packaged Fabric commands/service are absent. The active `codex-fabric-proof.service` is a transient proof daemon running stale checkout code and is not a release artifact.
- `omarchy-iso` is clean at `quattro` and defaults to the stable package channel. It has no Ultimate release pin; edge/dev/local are opt-in builder modes. Fresh/offline/upgrade/rollback ISO certification remains outstanding.
- The full graphical acceptance suite is disposable-VM work and was not claimed from the active desktop session. The Chrome proof uses exact pixel comparisons on settled `grim` frames and a physical pointer drag, not a high-speed video capture of every transient scanout interval.

## Open defects and known traps

1. Finish release convergence: repin and build the package pair from current main, install/declare both Hyprland plugins, package the Fabric commands and user service, pin the matching ISO input, and run fresh/offline/upgrade/rollback certification.
2. Rerun `bash test/all` in the supported dependency-complete metal/VM environment. Treat missing-command failures above as harness blockers, not product proof.
3. Keep the Chrome compensation path frozen. Any change to frame extents, work areas, snap/maximize rectangles, borders, scale, caption hit targets, shell layout, packaging, or restart behavior requires the complete real-Chrome metal proof, including centered geometry, both rounded top corners, the full close glyph, direct motion, drag, snap, maximize/restore, and repeated cycles.
4. Always rebuild and fully restart Hyprland after changing `omarchy-minimize`; otherwise `/proc/$PID/maps` can show a deleted old plugin even while the checkout contains the new artifact.
5. Popup surfaces are not the Chrome defect. Do not use a right-edge snap or a hidden/partially off-screen window as the corner proof; use a centered real Chrome window.
6. Do not cherry-pick the 29 unreachable main-repository candidate commits. They are old abandoned Aider/cert histories; their provider/operations trees overlap current work, while whole-history comparisons delete current product surfaces. Preserve as historical evidence unless an explicit archival policy is adopted.
7. Product mutation remains intentionally unavailable in Settings, Agent Center, Files, Software, and Compatibility; the next tranche must not invent optimistic execution controls.

## Authoritative next tranche

Resume from `plans/ultimate-capability-engines-product-ownership-convergence-2026-08-27.md`. Its dependency-complete fleet order is: provider registry/catalog convergence; stable ownership and read projections; durable coordinator/executor; full Settings and Quick Settings states; Agent Center states; Files/Software/Compatibility/Administration/Recovery applications; search/identity/shell convergence; privileged executors; cross-surface fault/accessibility/multi-monitor/Chrome campaigns; then package/ISO/migration/release reconciliation. It explicitly describes a massive continuous tranche and the exit gates; do not split it into cosmetic micro-slices.

Three planning agents were started for architecture, quality, and release coverage and then interrupted when the user explicitly said to stop. Their evidence is incorporated in this handoff and the authoritative plan; no execution fleet was launched from those interrupted runs.

## Exact resume commands

```bash
cd /mnt/c/dev/omarchy7ultimate
git status --short --branch
git log -1 --oneline
bash test/shell.d/ultimate-desktop-plugin-test.sh
bash test/shell.d/omarchy-minimize-csd-test.sh
bash test/shell.d/window-service-test.sh
git diff --check
```

```bash
ssh -o UserKnownHostsFile=C:/dev/omarchy-vm/omarchy_known_hosts jesse@192.168.1.171
cd /home/jesse/omarchy7ultimate/default/hypr/plugins/omarchy-minimize
make -B CXX=g++
systemctl --user restart wayland-wm@hyprland.desktop.service
systemctl --user is-active wayland-wm@hyprland.desktop.service
hyprctl plugin list
```

Before declaring a release candidate, compare `git rev-parse HEAD` and `git status --short --branch` in all three local and all three metal checkouts, compare GitHub refs with `git ls-remote`, and record package/ISO BOM plus the post-restart plugin inode in this handoff.
