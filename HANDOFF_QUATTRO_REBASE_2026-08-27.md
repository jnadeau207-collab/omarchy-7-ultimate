# HANDOFF_QUATTRO_REBASE_2026-08-27

## Goal

Resolve every blocker preventing `work` from pulling current upstream, preserve all Ultimate work instead of choosing one side, and rebase the complete branch onto `quattro`. Reconcile the rewritten branch across the Windows checkout, GitHub, and the metal checkout, then leave evidence strong enough that a later session does not repeat or undo the work.

## State of the world

- The branch head is the documentation-only commit containing this handoff. Its code-tested parent is `a5bed4cf6e1fbdf09f0407ad1249cee17587c8fd`.
- `work` is based on current `quattro` commit `83881e979b35468c3e7d60b171e319ede61a88fd`.
- The exact pre-rebase `work` tip is protected on GitHub as `codex/work-pre-quattro-rebase-2026-08-27-1654` at `4a4cd72d38c4f38584f412a47c647ce32af05842`. Do not delete this recovery ref until Jesse explicitly asks.
- The Windows checkout `C:\dev\omarchy7ultimate`, GitHub `origin/work`, and `/home/jesse/omarchy7ultimate` on metal are clean and aligned after the handoff commit is deployed. There is only one Windows worktree for this repository.
- GitHub `main`, local `origin/main`, local `upstream/quattro`, and metal `origin/main` all resolve to `83881e979b35468c3e7d60b171e319ede61a88fd`.
- `C:\dev\omarchy-pkgs` and `/home/jesse/omarchy-pkgs` are clean at `e902923c2b2f48948bbd95571186c045fac4b8b6` on `work` tracking `ultimate/work`.
- `C:\dev\omarchy-iso` and `/home/jesse/omarchy-iso` are clean at `268bac16d351a21d867e37565738f458b11cb06c` on `quattro` tracking `origin/quattro`.
- The authoritative next-tranche plan remains `plans/ultimate-capability-engines-product-ownership-convergence-2026-08-27.md`. The prior reconciliation and Chrome evidence remains in `HANDOFF_ULTIMATE_RECONCILIATION_CHROME_DAMAGE_2026-08-27.md`; this handoff supersedes its Git/ref and aggregate-test status only.

## Done and verified

- Fetched and pruned both remotes, established merge base `f0020448ca87329199de7cb12f2015ebc4a3e5e7`, and measured 105 upstream-only commits against 229 old Ultimate-side commits.
- Pushed the exact pre-rebase tip to the protected backup branch before rewriting anything.
- Replayed the entire 229-commit Ultimate stack onto current `upstream/quattro`. Git retained 160 replayed commits and dropped 69 old backports whose patch content current Quattro already contains. The source-tested parent has 163 commits above Quattro after the three verification fixes found during this work; documentation-only handoff commits are excluded from that source-stack count.
- Resolved conflicts by comparing current Quattro, the exact protected old tip, and the replay commit. Quattro's later superset was retained for agent/Ori integration, Windows VM, clipboard, DNS, theme/plugin URL security, Docker posture, About animation, menu ordering, icon font, theme-background conversion, and related tests. No conflict was resolved by blindly discarding one side.
- `git range-diff` maps the Ultimate-specific product, Fabric, windowing, Chrome, contract, and planning commits through the rewrite. The old-to-new tree audit reports 13 added paths, 30 modified paths, and zero deleted paths. `default/fabric`, `shell/apps`, `shell/services`, `default/hypr/plugins/omarchy-minimize`, and the massive tranche plan are present. The entire `default/hypr/plugins` tree is byte-identical to the protected old tip.
- Fixed three verification defects as atomic commits: `3b000178` isolates the Files absolute-path fixture from hostile shared `/tmp` contents; `2e8449b8` makes ASCII width assertions locale-safe; `a5bed4cf` prevents the theme missing-checker test from inheriting the aggregate runner's repo `PATH`.
- Installed the already-declared metal runtime package `python-jsonschema 4.26.0-1` plus its Arch dependencies through `omarchy-pkg-add`. The package lifecycle gate now exercises `/usr/bin/python3`, not the temporary proof virtual environment.
- Final metal verification on code tip `a5bed4cf6e1fbdf09f0407ad1249cee17587c8fd`: `bash test/all` passed all 237 test files with 3,566 `ok` assertions, zero `not ok`, and exit 0 using `PATH=/home/jesse/omarchy7ultimate/bin:/usr/bin:/bin` with no virtual environment.
- `git diff --check` passes, Quattro is an ancestor of `work`, and the Windows/GitHub/metal branch heads are clean and equal after deployment.

## Done but unverified

- No new graphical Chrome campaign was run for this history-only rebase. The protected old tip and rebased code tip have identical Chrome/windowing/plugin source, so the rebase did not change that implementation. The prior source, pointer, pixel, and motion evidence remains valid for the same blobs, but this turn did not produce a new screenshot set.
- The user's last physical report described intermittent ghost perimeter flashes during window movement as almost fixed but not completely fixed. Sparse screenshots and the prior six-frame `outside_pixels=0` proof do not disprove a transient presentation artifact. Treat the residual motion artifact as visually open and do not claim it closed from static screenshots.
- The final handoff commit changes documentation only. The complete 237-file aggregate ran on its source-identical parent `a5bed4cf`; only `git diff --check` and repository-state checks are required after adding this document.

## In flight

No rebase work remains in flight. The next deliberate release action is to repin and rebuild the paired Ultimate packages from the final `work` head, package the Fabric commands/service and both Hyprland plugins, select that paired candidate in the ISO path, and run fresh/offline/upgrade/rollback certification. Do not call the current source checkout a deployable package release before that lane closes.

For product work, resume from `plans/ultimate-capability-engines-product-ownership-convergence-2026-08-27.md` as one large coordinated tranche. Do not fragment it into tiny named slices, and do not reopen provider mutation UI that the current contracts intentionally mark unavailable.

## Open defects and known traps

- `omarchy-pkgs` still pins `5504a044d34b0c44e3b3ab57f3f6fc5e6d427719` in `pkgbuilds/omarchy-dev/PKGBUILD`, `pkgbuilds/omarchy-settings-dev/PKGBUILD`, and `bin/check-ultimate-fabric-pair`. That candidate predates the rebased final source.
- Metal still runs stable `omarchy 4.0.0-1` and `omarchy-settings 4.0.0-1`. `/usr/bin/omarchy-fabricd`, `/usr/bin/omarchy-fabricctl`, `/usr/bin/omarchy-fabric-service`, and `/usr/lib/systemd/user/omarchy-fabric.service` are absent. Installing `python-jsonschema` fixed the declared runtime dependency, not the missing package release.
- `codex-fabric-proof.service` remains a transient proof daemon started at `2026-08-27 03:52:12 EDT` from `/tmp/codex-provider-registry-20260827/venv`. It predates the final commits and is not a release artifact.
- The ISO defaults to `OMARCHY_ISO_REF=quattro` and the stable mirror. Ultimate dev/local behavior remains opt-in and no final paired package candidate is pinned into a certified ISO.
- Do not cherry-pick the 29 old unreachable candidate commits. Their useful provider/operations/managed-work content is already byte-identical to current history; wholesale cherry-picks delete newer product work.
- Do not alter the frozen Chromium compensation, CSD, work-area, caption, border, scale, snap, or maximize paths without the complete real-Chrome metal campaign. The residual ghost-perimeter report requires high-rate motion capture or direct presentation evidence; static screenshots alone are insufficient.
- A full compositor restart was intentionally not performed during this rebase because `default/hypr/plugins` is byte-identical before and after. Rebuild and fully restart Hyprland after any future native plugin source change; never hot-unload or hot-reload hyprbars.
- The protected backup branch is intentional recovery evidence, not stale clutter.

## Exact commands

Windows repository and ancestry verification:

```powershell
Set-Location C:\dev\omarchy7ultimate
git status --short --branch
git rev-parse HEAD origin/work upstream/quattro origin/main
git merge-base --is-ancestor upstream/quattro work
git rev-list --left-right --count upstream/quattro...work
git diff --check
git ls-remote origin refs/heads/work refs/heads/main refs/heads/codex/work-pre-quattro-rebase-2026-08-27-1654
```

Preservation audit against the protected old tip:

```powershell
git range-diff --no-color f0020448ca87329199de7cb12f2015ebc4a3e5e7..codex/work-pre-quattro-rebase-2026-08-27-1654 upstream/quattro..work
git diff --name-status --diff-filter=D codex/work-pre-quattro-rebase-2026-08-27-1654 work
git diff --stat codex/work-pre-quattro-rebase-2026-08-27-1654 work -- default/fabric shell/apps shell/services default/hypr/plugins plans docs test/shell.d
```

Metal state and complete supported-environment suite:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/c/dev/omarchy-vm/omarchy_known_hosts jesse@192.168.1.171
cd /home/jesse/omarchy7ultimate
git status --short --branch
git rev-parse HEAD origin/work
env PATH=/home/jesse/omarchy7ultimate/bin:/usr/bin:/bin bash test/all
pacman -Q omarchy omarchy-settings python-jsonschema
```

Release-gap inspection:

```bash
rg -n '5504a044d34b0c44e3b3ab57f3f6fc5e6d427719' /home/jesse/omarchy-pkgs
for path in /usr/bin/omarchy-fabricd /usr/bin/omarchy-fabricctl /usr/bin/omarchy-fabric-service /usr/lib/systemd/user/omarchy-fabric.service; do [[ -e $path ]] && printf 'PRESENT %s\n' "$path" || printf 'ABSENT %s\n' "$path"; done
systemctl --user show codex-fabric-proof.service -p ExecMainStartTimestamp -p ExecStart --no-pager
```
