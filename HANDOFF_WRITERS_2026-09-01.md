# Writers and the root executor — 2026-09-01

SHA `6e01615d` on `work`, rebased onto `upstream/quattro` at `b71dcad9`.

## Verified on metal

Everything below runs green on the Arch box.

| Suite | Result |
|-------|--------|
| `test/all` (264 files) | **exit 0**, 4369 assertions, zero failures |
| every suite under `test/fabric` | **OK** |

The baseline before this work was 13 of 247 shell files failing and four failures in the administration fabric suite. All of them are closed. Nine shell files and one fabric suite were fixed here; none of the failures were caused by this work, and each one is described in its own commit.

Two of those were real defects rather than stale tests:

- Forty-one `Text` elements relied on `Text.AutoText`, so anything rendering data from outside the shell could have had markup interpreted. They now declare `Text.PlainText`.
- My own comment sweep collapsed a blank line inside a heredoc, silently editing a tmux config fixture that a test compares byte for byte. Auditing every heredoc in that commit found seven files touched; six were embedded code where it changes nothing, one was data. `AGENTS.md` now forbids a sweep from changing a byte inside a heredoc.

A third is a contract nuance worth keeping: a scoped leaf provider reports a projected resource from preflight, and that projection is lossy, so provider-side `apply`, `validate` and `rollback` cannot round-trip it. The coordinator and the code-owned executor own mutation for those operations. The administration lifecycle tests had been driving that unsupported path against `process` since End Task shipped.

Local, `origin`, and metal hold the same commit and the same tree.
## The rebase

`work` was replayed with `git rebase --onto`, not merged, so `upstream/quattro` is a true ancestor. 367 commits replayed, one dropped as empty because upstream independently reworked the same theme-guard test and its version supersedes ours. Recovery ref `pre-rebase-20260901` holds the old tip.

`work` now reads 487 ahead / 367 behind `origin/work`. Publishing it needs a force-push, which the plan forbids. That call is still open.

`main` carries 218 Ultimate commits and sits 120 behind upstream, against a plan that defines it as clean upstream tracking. Pre-existing, not caused by the rebase, and restoring it is another history rewrite.

## What landed

**The root executor exists.** `SystemCommandExecutor` was wired into the daemon and invoked `/usr/libexec/omarchy-fabric-system-executor`, which was not in the repository. It is now, for `packages.install` and `packages.remove`, with a Polkit policy. Polkit binds one action id to one program path, so each verb has its own program under `/usr/libexec/omarchy-fabric/` and its own admin rule; the dispatcher maps a verb to a literal path through a fixed `case` and execs `pkexec`, so request data never reaches the argv. The root half re-validates the typed request from scratch and resolves package ids through the signed catalog.

**The write plane went from four actions to nine, and from two reachable to seven.**

| Action | Surface | State |
|--------|---------|-------|
| `audio-output-volume-set` | Settings › Sound | pre-existing |
| `process-terminate` | Administration › End task | pre-existing |
| `power-profile-set` | Settings › Power | surfaced here |
| `files-directory-create` | Files › New folder | surfaced here |
| `display-brightness-set` | Settings › Display | new here |
| `input-keyboard-layout-set` | Settings › Input | new here |
| `network-wifi-enabled-set` | Settings › Network | new here |
| `files-entry-trash` | none yet | helper only |
| `files-trash-restore` | none yet | helper only |

Each device-scoped writer resolves its opaque resource id by recomputing the provider's own digest over the live device list, so a payload can never name a monitor, keyboard or sink directly.

**`session_apply.py` moved out of `operations/`.** `fabric-operation-coordinator-test.sh` refuses any subprocess or privilege escape under `operations/`, and the helper had been sitting there calling `subprocess.run` four times since the write plane shipped. It now lives in `omarchy_fabric.helpers`.

## Three defects this surfaced

1. **`require_resource_id` is audio-specific.** It demands an `audio.sink.` prefix and a 64-hex digest. The display, input and network branches all called it, so each would have refused its own resource id at runtime. The QML and model tests could not see this because they never exercised the helper. Any new branch needs its own prefix check.

2. **A missing command escaped as `FileNotFoundError`.** `main()` caught `ApplyError` and `TimeoutExpired` but not `OSError`, so a machine without `pactl` would have crashed the helper instead of refusing. Predates this work.

3. **The power provider was never opted into session-operable mutation.** It had an intent, an operation definition and a helper branch, and `ReadOnlyProbeBackend` defaulted `session_operable` to `False`, so the Settings control would have been a dead button. Check this first for any new domain.

## The next piece, precisely

`files-entry-trash` and `files-trash-restore` are implemented and proven against a real temporary tree, including both security guards failing the test when removed. They are not reachable, and the reason is narrower than it first looks.

Scoping `entry.trash` needs no new read action and no new daemon dispatch. The scope is the entry's **parent directory**, reusing the existing `files.directory.<digest>` resource that `directory.create` already uses, because trashing an entry removes exactly one name from that directory's listing and `directory.inspect` already reads that listing from disk. The helper's `locationId` and `entryRelativePath` come from the diff between the scope's current and proposed names — no argument-schema change either. Both halves were written and verified this session:

- `_entry_trash_scope` resolves the entry, derives its parent, and proposes the listing minus that name.
- A payload deriver returns the right path for root-level and nested entries, and refuses any plan that does not remove exactly one name.

**The actual blocker is the schema family.** `files-operation-preflight-v0`, which `entry.trash` uses, pins `resource.kind` to `const: "files.workspace"`. The scoped family `files-directory-{preflight,result,state}-v1` allows `files.directory`, but pins `action` to `const: "directory.create"` and lists only `files.directory.create` in its capability enum. So a second scoped operation requires either widening those three `const`s to enums in a published v1 family, or minting a parallel family for Trash. That is a contract revision and should be a deliberate decision, not a side effect.

Three tests catch the mismatch immediately, which is how it was found:

- `test_trash_restore_has_exact_recovery_metadata_and_undo`
- `test_all_safe_representative_operations_execute_validate_and_undo`
- `test_trashing_a_directory_removes_its_whole_subtree_from_recent`

The scope function and payload deriver were reverted rather than left half-applied. Reinstate them once the schema decision is made; nothing else in the path needs to change.

`trash.restore` is harder and was not attempted. Its natural scope is the destination directory, which is only known from the `.trashinfo` record the provider does not read at preflight.

## Why entry.rename is not scoped

Scoping `entry.rename` to its parent directory looks identical to the other three and is wrong. The directory scope derives its revision from the listing, which is names only. Renaming changes a name, so the scope tracks the effect correctly, but it stops seeing anything else about the entry.

`test_compare_and_swap_contains_concurrent_execution_and_toctou_drift` proves it: it drifts the target entry's `identity` between preflight and execute and requires `files.state-stale`. Against the whole-workspace revision that fires. Against a directory listing it does not, because the names did not move. Scoping rename would silently drop the provider-level TOCTOU check on the exact operation that resolves an entry by id and then moves it.

Create, trash and restore are safe under this scope because their observable effect *is* a name appearing or disappearing, and an entry that drifted underneath still fails the helper's inode check. Rename needs a scope carrying the entry identity as well as the listing. That is a different document shape and a different schema family; it was attempted, caught by that test, and reverted rather than shipped weakened.
## What still blocks Software Center

Not the executor. The shipped catalog carries `assurance: contract-seed`, and `PackageProvider` deliberately refuses live mutation for an unattested seed. That gate is correct and was left closed. Opening it is a release-attestation decision.

`RELEASE_PLAN_ONLY_DETAIL` in both the packages and compatibility providers still says live mutation "waits for the privileged system executor". For packages that sentence is now stale, but the accurate replacement depends on whether the provider's `_require_live_execution` sits on the operation path at all, which needs a running daemon to determine. Left alone rather than guessed at.

## Remaining leaf work

`bluetooth` is the last leaf domain without a writer. Its operation is `audio.pair`, a multi-step interactive flow rather than a single verb, so it does not follow the five-step recipe.

`defaults` is a `StateDomainProvider` like `files` and needs the same scoped-resource treatment.

## Debt paid

`input.keyboard-layout.set` left the `legacy.domain.direct-providers` debt, which drops from 36 capabilities to 35. Its removal gate is a typed provider with structured state, preflight, results and recovery, which is what landed. The Superbar widget still assembles `hyprctl switchxkblayout` as a shell string. It is not redundant -- it cycles from the bar, which the Settings control does not replace -- so retiring it means routing that cycle through the typed verb, not deleting it.

Neither the `parity.language-locale` nor the `windows-native.33` row moves off `prototype`. Switching between configured layouts is not the whole job, and forty-task row 33 stays unproven until it runs on metal.
