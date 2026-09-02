# Writers and the root executor — 2026-09-01

SHA `6e01615d` on `work` (session that landed the root executor and write-plane expansion), rebased onto `upstream/quattro` at `b71dcad9`. Honesty addendum 2026-09-02 vs tip `c192afea`: `entry.trash` write-plane reachability after PR #8 v1 directory family widen is KEEP. The helper-only / schema-blocker paragraphs below are rewritten to residual. Honesty addendum 2026-09-02 vs tip `c1490f82`: Files Trash controls stay gated `trashAuthorized=false` for the shell principal (same invent class as LIVE End Task). Write plane remains reachable at `consequential`; SHELL still refused at `grant.shell-consequential`. Do not invent Restore LIVE, `files.trash.manage`, Empty Recycle, Recycle Bin product-complete, or LIVE Trash under SHELL. Product REJECTED.

Honesty addendum 2026-09-02 vs tip after PR #31 (`62372edf9e62`): Settings Power LIVE stays refused. Heritage Superbar / Quick Settings Power remains the catalog leftover (`power.profile.set` / `legacy-direct` / Process/`omarchy-powerprofiles-set`). Distinct from fabric `app.slice`: shell launch is Hyprland `exec_cmd`, compositor documented in `session.slice`. Not a `session-N.scope` leftover. Whether that Process path satisfies polkit `allow_active` is unverified on metal. Do not honesty-gate the heritage panel; do not invent Settings LIVE or a broad polkit grant; do not claim METAL_HEAD. Product REJECTED.

Honesty addendum 2026-09-02 vs tip after PR #29 (`aee1d78a8cf1`): opting power into `session_operable=True` without a session-scope or polkit authorization for `org.freedesktop.UPower.PowerProfiles.switch-profile` was a LIVE invent (Settings Power buttons that cannot succeed from `app.slice`). KEEP: `session_operable=False`; Power not in `LIVE_WRITER_ROUTES`; `profileMutationAuthorized=false`; CHANGES UNAVAILABLE honesty names polkit/session. Write plane kept. Operator owns polkit/session-scope. Product REJECTED. METAL_HEAD OPEN.

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

**The write plane went from four actions to nine.** Honesty vs tip `c192afea`: `directory.create` stays `low` and SHELL-grantable. `entry.trash` is write-plane reachable at `consequential` (not helper-only); SHELL approve fails `grant.shell-consequential`. `trash.restore` stays honest-unavailable.

| Action | Surface | State |
|--------|---------|-------|
| `audio-output-volume-set` | Settings › Sound | pre-existing |
| `process-terminate` | Administration › End task | pre-existing |
| `power-profile-set` | Settings › Power | surfaced here |
| `files-directory-create` | Files › New folder | LIVE (`directory.create`, risk `low`; SHELL grant OK) |
| `display-brightness-set` | Settings › Display | new here |
| `input-keyboard-layout-set` | Settings › Input | new here |
| `network-wifi-enabled-set` | Settings › Network | new here |
| `files-entry-trash` | Files › Trash | write plane reachable (`entry.trash`, risk `consequential`; SHELL refused at `grant.shell-consequential`; Files Trash controls gated `trashAuthorized=false`, not LIVE) |
| `files-trash-restore` | none | honest-unavailable (no Restore UI; write plane `operation.definition-unavailable`; helper/lifecycle remain) |

Each device-scoped writer resolves its opaque resource id by recomputing the provider's own digest over the live device list, so a payload can never name a monitor, keyboard or sink directly.

**`session_apply.py` moved out of `operations/`.** `fabric-operation-coordinator-test.sh` refuses any subprocess or privilege escape under `operations/`, and the helper had been sitting there calling `subprocess.run` four times since the write plane shipped. It now lives in `omarchy_fabric.helpers`.

## Three defects this surfaced

1. **`require_resource_id` is audio-specific.** It demands an `audio.sink.` prefix and a 64-hex digest. The display, input and network branches all called it, so each would have refused its own resource id at runtime. The QML and model tests could not see this because they never exercised the helper. Any new branch needs its own prefix check.

2. **A missing command escaped as `FileNotFoundError`.** `main()` caught `ApplyError` and `TimeoutExpired` but not `OSError`, so a machine without `pactl` would have crashed the helper instead of refusing. Predates this work.

3. **The power provider was never opted into session-operable mutation.** It had an intent, an operation definition and a helper branch, and `ReadOnlyProbeBackend` defaulted `session_operable` to `False`, so the Settings control would have been a dead button. Check this first for any new domain.

## Files writers vs tip (not helper-only)

`files-entry-trash` and `files-trash-restore` remain implemented and proven against a real temporary tree, including both security guards failing the test when removed. The schema-family blocker is closed. PR #8 widened `files-directory-{preflight,result,state}-v1` in place: `action` is an enum of `directory.create` and `entry.trash` (and still lists `trash.restore`) rather than a parallel Trash family. v0 workspace schemas were not edited. Shared family is not shared risk.

**LIVE**

- `directory.create` — Files › New folder. Risk `low`. SHELL may hold a standing grant.

**Write plane reachable, not LIVE under SHELL**

- `entry.trash` — Files › Trash through `files.provider`. Write plane reachable. Scope is the entry's parent directory, reusing `files.directory.<digest>`. Risk `consequential`. SHELL cannot hold a standing grant (`grant.shell-consequential`). Same grant rule as End Task. Files Trash controls stay hidden while `trashAuthorized=false` so the shell principal cannot start a doomed preflight. Do not invent a TASK workaround or LIVE Trash under SHELL.

**Unavailable (do not invent)**

- Restore UI / `trash.restore` on the write plane. The real adapter does not read `.trashinfo` at preflight, so a restore destination cannot be derived from the directory listing. Provider lifecycle and the session helper still exist; the daemon does not register `trash.restore`; Files does not offer a Restore control (`operation.definition-unavailable`).
- `files.trash.manage`
- Empty Recycle Bin
- Permanent delete
- Recycle Bin as a product-complete place

The Files banner matches: New folder runs through `files.provider`; Trash write plane exists but is not shell-authorizable (CHANGES UNAVAILABLE); Restore, empty Recycle Bin, permanent delete, and `files.trash.manage` remain unavailable.

The scope function and payload deriver shipped with the v1 widen (not left reverted). `_entry_trash_scope` resolves the entry, derives its parent, and proposes the listing minus that name. The payload deriver reads scoped `currentState.value` and refuses any plan that does not remove exactly one name.

## Why entry.rename is not scoped

Scoping `entry.rename` to its parent directory looks identical to the other three and is wrong. The directory scope derives its revision from the listing, which is names only. Renaming changes a name, so the scope tracks the effect correctly, but it stops seeing anything else about the entry.

`test_compare_and_swap_contains_concurrent_execution_and_toctou_drift` proves it: it drifts the target entry's `identity` between preflight and execute and requires `files.state-stale`. Against the whole-workspace revision that fires. Against a directory listing it does not, because the names did not move. Scoping rename would silently drop the provider-level TOCTOU check on the exact operation that resolves an entry by id and then moves it.

Create and trash are safe under this scope because their observable effect *is* a name appearing or disappearing, and an entry that drifted underneath still fails the helper's inode check. Restore stays honest-unavailable (no `.trashinfo` at real preflight); do not invent Restore LIVE. Rename needs a scope carrying the entry identity as well as the listing. That is a different document shape and a different schema family; it was attempted, caught by that test, and reverted rather than shipped weakened.
## What still blocks Software Center

Not the executor. The shipped catalog carries `assurance: contract-seed`, and `PackageProvider` deliberately refuses live mutation for an unattested seed. That gate is correct and was left closed. Opening it is a release-attestation decision.

`RELEASE_PLAN_ONLY_DETAIL` in both the packages and compatibility providers still says live mutation "waits for the privileged system executor". For packages that sentence is now stale, but the accurate replacement depends on whether the provider's `_require_live_execution` sits on the operation path at all, which needs a running daemon to determine. Left alone rather than guessed at.

## Remaining leaf work

`bluetooth` is the last leaf domain without a writer. Its operation is `audio.pair`, a multi-step interactive flow rather than a single verb, so it does not follow the five-step recipe.

`defaults` is a `StateDomainProvider` like `files` and needs the same scoped-resource treatment.

## Debt paid

`input.keyboard-layout.set` left the `legacy.domain.direct-providers` debt, which drops from 36 capabilities to 35. Its removal gate is a typed provider with structured state, preflight, results and recovery, which is what landed. The Superbar widget still assembles `hyprctl switchxkblayout` as a shell string. It is not redundant -- it cycles from the bar, which the Settings control does not replace -- so retiring it means routing that cycle through the typed verb, not deleting it.

Neither the `parity.language-locale` nor the `windows-native.33` row moves off `prototype`. Switching between configured layouts is not the whole job, and forty-task row 33 stays unproven until it runs on metal.
