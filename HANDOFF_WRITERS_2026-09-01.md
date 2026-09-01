# Writers and the root executor — 2026-09-01

SHA `be7385ea` on `work`, rebased onto `upstream/quattro` at `b71dcad9`. Shell gates: 109 of 264 files fail on a Windows checkout, the identical list that fails at `db8d9c60` before this work, plus four new files that pass. No regression.

Nothing here has run on metal. The Python fabric suite calls `os.getuid` and cannot execute off Linux, so every claim below is reviewed code and passing unit tests, not a demonstrated change to a machine.

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

`files-entry-trash` and `files-trash-restore` are implemented and proven against a real temporary tree, including both security guards failing the test when removed. They are not reachable because the operation definitions cannot get what the helper needs.

The helper wants `locationId` and `entryRelativePath`. `_normalize_entry` returns `{entryId}` alone, so `preflight["normalizedArguments"]` does not carry them. The lambda can read `preflight["currentState"]`, which for a scoped operation is the scope's `current` document — so the work is:

1. Write an `_entry_scope` alongside `_directory_scope` whose `current` document carries `locationId` and `relativePath`.
2. Give the backend an entry read action equivalent to `directory.inspect`, so the daemon's validation reader recomputes the scoped state from disk rather than from the bounded inventory. This is the same fix the state-domain handoff made for `directory.create`, and for the same reason: whole-state equality cannot validate a real filesystem mutation.
3. Dispatch on resource id kind in `daemon._operation_state`.
4. Add the two `IntentDefinition`s and `OperationDefinition`s.
5. Surface Trash and Restore in the Files app, and widen nothing — the allowlist already carries the four operation methods.

Do not shortcut step 2. The state-domain handoff records three separate contract conflicts that surfaced only when that path first executed.

## What still blocks Software Center

Not the executor. The shipped catalog carries `assurance: contract-seed`, and `PackageProvider` deliberately refuses live mutation for an unattested seed. That gate is correct and was left closed. Opening it is a release-attestation decision.

`RELEASE_PLAN_ONLY_DETAIL` in both the packages and compatibility providers still says live mutation "waits for the privileged system executor". For packages that sentence is now stale, but the accurate replacement depends on whether the provider's `_require_live_execution` sits on the operation path at all, which needs a running daemon to determine. Left alone rather than guessed at.

## Remaining leaf work

`bluetooth` is the last leaf domain without a writer. Its operation is `audio.pair`, a multi-step interactive flow rather than a single verb, so it does not follow the five-step recipe.

`defaults` is a `StateDomainProvider` like `files` and needs the same scoped-resource treatment.

## Debt paid

`input.keyboard-layout.set` left the `legacy.domain.direct-providers` debt, which drops from 36 capabilities to 35. Its removal gate is a typed provider with structured state, preflight, results and recovery, which is what landed. The Superbar widget still assembles `hyprctl switchxkblayout` as a shell string. It is not redundant -- it cycles from the bar, which the Settings control does not replace -- so retiring it means routing that cycle through the typed verb, not deleting it.

Neither the `parity.language-locale` nor the `windows-native.33` row moves off `prototype`. Switching between configured layouts is not the whole job, and forty-task row 33 stays unproven until it runs on metal.
