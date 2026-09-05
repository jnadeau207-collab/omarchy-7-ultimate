# Writers and the root executor — 2026-09-01

SHA `6e01615d` on `work` (session that landed the root executor and write-plane expansion), rebased onto `upstream/quattro` at `b71dcad9`. Honesty addendum 2026-09-02 vs tip `c192afea`: `entry.trash` write-plane reachability after PR #8 v1 directory family widen is KEEP. The helper-only / schema-blocker paragraphs below are rewritten to residual. Honesty addendum 2026-09-02 vs tip `c1490f82`: Files Trash controls stay gated `trashAuthorized=false` for the shell principal (same invent class as LIVE End Task). Write plane remains reachable at `consequential`; SHELL still refused at `grant.shell-consequential`. Honesty addendum 2026-09-02: `files.trash.restore` write plane is reachable the same way. Real preflight reads `.trashinfo` to derive the restore destination. Risk stays `consequential`. SHELL still refused at `grant.shell-consequential`. Catalog claim=partial; humanRoute planned empty. Files does not offer Restore LIVE. Do not invent Restore LIVE, `files.trash.manage`, Empty Recycle, Recycle Bin product-complete, or LIVE Trash under SHELL. Product REJECTED.

Honesty addendum 2026-09-02: `files.entry.open` launch plane is reachable (`files-entry-open` helper). Real preflight binds entry identity and location scope. Risk is `low`. SHELL grant is allowed. Catalog claim=partial; humanRoute visible `Files > Open`. Agent stays unavailable. Files Open / double-click is LIVE for regular files. File contents are never read. Do not invent Open With / MIME association UI, Restore LIVE, Empty Bin, or Explorer product-complete. Recycle and MIME residuals stay OPEN. Product REJECTED.

Honesty addendum 2026-09-03: `files.entry.rename` write plane is reachable (`files-entry-rename` helper). Real preflight binds entry identity inside the scoped directory listing and keeps the rename in the same directory. Collision, drift, traversal, symlink, and Trash refuse. Risk is `low` (same class as `directory.create`: a reversible same-directory name change, not a Trash relocation). SHELL grant is allowed. Catalog claim=partial; humanRoute visible `Files > Rename`. Agent stays unavailable. Files Rename is LIVE (`renameAuthorized=true`). Do not invent cut/move, Open With / MIME UI, Restore LIVE, Empty Bin, or Explorer product-complete. Recycle and MIME residuals stay OPEN. Product REJECTED.

Honesty addendum 2026-09-03: `files.entry.copy` write plane is reachable (`files-entry-copy` helper). Real preflight binds source identity inside the destination directory listing. Copy writes a scoped regular-file or directory replica into a Files location. Collision, drift, traversal, symlink loops, nest-inside-source, and Trash refuse. Copy maps `EXDEV` errno from `mkdir`/`open` only; overlay or bind-mount children may copy. Risk is `low` (additive replica, same class as `directory.create`, not a cut/move). SHELL grant is allowed. Catalog claim=partial; humanRoute visible `Files > Copy and Paste`. Agent stays unavailable. Files Copy and Paste are LIVE (`copyAuthorized=true`) with in-app staging only. The OS clipboard, thumbnails, Open With / MIME UI, Restore LIVE, Empty Bin, and Explorer product-complete stay leftovers. Recycle and MIME residuals stay OPEN. Product REJECTED.

Honesty addendum 2026-09-03: `files.entry.move` write plane is reachable (`files-entry-move` helper). Real preflight binds source identity inside the destination directory listing. Move relocates a regular file with `os.rename`. Collision, drift, traversal, symlink, directory, Trash, same-directory rename, and cross-device `EXDEV` refuse. Risk is `consequential` (source name leaves its original listing, same class as `entry.trash`, not an additive replica). SHELL grant is refused at `grant.shell-consequential`. Catalog claim=partial; humanRoute planned empty. Agent stays unavailable. Files pins `cutAuthorized=false` and does not offer Cut. Folder copy CLOSED via `files.entry.copy` directories; move still refuses directories. Do not invent LIVE Cut under SHELL, an OS clipboard, Restore LIVE, Empty Bin, or Explorer product-complete. Recycle and MIME residuals stay OPEN. Product REJECTED.

Honesty addendum 2026-09-03: `files.entry.delete` write plane is reachable (`files-entry-delete` helper). Real preflight binds entry identity inside the scoped directory listing. Delete unlinks a regular file or rmdirs an empty directory. Drift, traversal, symlink, non-empty directory, and Trash refuse. No recursive `rm -rf`. Risk is `consequential` (same class as `entry.trash` / `entry.move`). SHELL grant is refused at `grant.shell-consequential`. Catalog claim=partial; humanRoute planned empty. Agent stays unavailable. Files pins `deleteAuthorized=false` and does not offer LIVE Delete. Do not invent LIVE Delete under SHELL, Empty Bin, `files.trash.manage`, or Recycle product-complete. Recycle and MIME residuals stay OPEN. Product REJECTED.

Honesty addendum 2026-09-03 vs tip after PR #60 (`c1886b423c11`): Files residuals still named after #60 stay OPEN. Copy/Paste stay in-app only; OS clipboard residual OPEN after PR #60. Recycle Bin / `files.trash.manage` residual OPEN (`availability.claim=missing`). Files pins `deleteAuthorized=false`, `cutAuthorized=false`, `trashAuthorized=false`. Folder copy CLOSED via `files.entry.copy` directories. The permanent delete write plane exists but is not shell-authorizable. Do not invent an OS clipboard, a LIVE Empty Bin, Restore LIVE under SHELL, or Recycle product-complete. Product REJECTED.

Honesty addendum 2026-09-03 vs tip after PR #62 (`ad4a68e1b225`): MIME / Default Programs association UI residual OPEN after PR #62. `defaults.mime.set` write plane is reachable (`defaults-mime-set` helper; preflight OK; risk low). `association.inspect` is published so durable apply can re-read scoped association state. Settings Apps reads MIME inventory via `defaults.inspect`. partial MIME rows LIVE on Settings > Apps; Default Programs applet still missing. Catalog `defaults.mime.set` keeps claim=partial and humanRoute visible `Settings > Apps`. `files.associations.set` stays missing/planned MIME. `parity.file-associations` stays missing as product. Browser and mailto writers stay `defaults.protocol.set`. Do not invent a present MIME association UI, a LIVE association manager, or claim=present Default Programs product. Product REJECTED.

Honesty addendum 2026-09-03 vs tip after PR #63 (`73ec97959174`): `files.trash.manage` write plane is reachable (`files-trash-manage` helper). Real preflight binds the Trash location listing and empties regular files and empty directories plus their `.trashinfo`. Drift, traversal, symlink, non-empty trash trees, and any location other than Trash refuse. No recursive `rm -rf`. Risk is `consequential` (same class as `entry.trash` / `entry.delete`). SHELL grant is refused at `grant.shell-consequential`. Catalog claim=partial; humanRoute planned empty. Agent stays unavailable. Files pins `emptyBinAuthorized=false` and does not offer Empty Bin LIVE. Recycle Bin / Empty Bin LIVE residual OPEN after PR #63. Desktop Recycle icon, Recycle Properties, Restore UI, and Recycle product-complete stay leftovers. Do not invent Empty Bin LIVE, Restore LIVE under SHELL, `files.trash.manage` claim=present, or Recycle product-complete. Product REJECTED.

Honesty addendum 2026-09-03 vs tip after PR #64 (`40212d204a1c`): OS clipboard residual OPEN after PR #64. After #64 files.trash.manage plane, the leftover named after #60 stays OPEN. Files Copy and Paste stay in-app staging (`files.entry.copy`; claim=partial; risk low; SHELL-grantable; visible `Files > Copy and Paste`; `copyAuthorized=true`; regular files and directories; folder copy CLOSED). Files does not offer an OS clipboard. There is no Files `wl-copy` / `wl-paste` / `Qt.application.clipboard` bridge. Copy/Paste stay in-app only. Do not invent an OS clipboard LIVE, Explorer claim=present, LIVE Cut under SHELL, a LIVE Empty Bin, a LIVE Restore, or a product-complete Recycle Bin. Product REJECTED.

Honesty addendum 2026-09-03: MIME defaults apply through defaults.provider mime.set. `defaults.mime.set` write plane was already reachable (`defaults-mime-set` helper; preflight OK; risk low); Settings Apps now offers MIME LIVE CONTROL for writable associations with more than one installed candidate (`mimeRows`, `applyMimeDefault`; same preflight/approve/start plane as the browser writer). Refusals stay: already-default and non-candidate selections never reach preflight. Catalog `defaults.mime.set` keeps claim=partial; humanRoute visible `Settings > Apps`. `files.associations.set` stays missing/planned MIME. `parity.file-associations` stays missing as product. Do not invent a present Default Programs product, protocol defaults beyond the browser, or claim=present file associations. Product REJECTED.

Honesty addendum 2026-09-02 vs tip after PR #31 (`62372edf9e62`): Settings Power LIVE stays refused. Heritage Superbar / Quick Settings Power remains the catalog leftover (`power.profile.set` / `legacy-direct` / Process/`omarchy-powerprofiles-set`). Distinct from fabric `app.slice`: shell launch is Hyprland `exec_cmd`, compositor documented in `session.slice`. Not a `session-N.scope` leftover. That leftover was unverified on metal after PR #31. Metal FAIL on tip `20484de6` (Not authorized / session-5103; !batteryPresent; amd_pstate EINVAL). QS Power METAL_HEAD OPEN / KEEP OPEN. Settings Power LIVE refused. Do not claim the heritage QS Power panel works on this metal. Do not honesty-gate the heritage panel; do not invent Settings LIVE or a broad polkit grant. Product REJECTED.

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

**The write plane went from four actions to nine.** Honesty vs tip `c192afea`: `directory.create` stays `low` and SHELL-grantable. `entry.trash` is write-plane reachable at `consequential` (not helper-only); SHELL approve fails `grant.shell-consequential`. `files.trash.restore` is write-plane reachable at `consequential` after real `.trashinfo` preflight; SHELL approve fails `grant.shell-consequential`. Catalog claim=partial; humanRoute planned empty. Restore UI stays unavailable.

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
| `files-trash-restore` | none | write plane reachable (`files.trash.restore`, risk `consequential`; SHELL refused at `grant.shell-consequential`; catalog claim=partial; humanRoute planned empty; no Restore UI; Recycle residual stays OPEN) |
| `files-entry-open` | Files › Open | launch plane reachable (`files.entry.open`, risk `low`; SHELL grant OK; catalog claim=partial; humanRoute visible; Files Open LIVE for regular files; no Open With / MIME UI) |
| `files-entry-rename` | Files › Rename | write plane reachable (`files.entry.rename`, risk `low`; SHELL grant OK; catalog claim=partial; humanRoute visible; Files Rename LIVE for same-directory names; collision refuse; no cut/move) |
| `files-entry-copy` | Files › Copy and Paste | write plane reachable (`files.entry.copy`, risk `low`; SHELL grant OK; catalog claim=partial; humanRoute visible; Files Copy/Paste LIVE for regular files and directories with in-app staging; collision refuse; no OS clipboard; OS clipboard residual OPEN after PR #64) |
| `files-entry-move` | none | write plane reachable (`files.entry.move`, risk `consequential`; SHELL refused at `grant.shell-consequential`; catalog claim=partial; humanRoute planned empty; Files `cutAuthorized=false`; no Cut UI; no OS clipboard; folder copy CLOSED via `files.entry.copy`) |
| `files-entry-delete` | none | write plane reachable (`files.entry.delete`, risk `consequential`; SHELL refused at `grant.shell-consequential`; catalog claim=partial; humanRoute planned empty; Files `deleteAuthorized=false`; no LIVE Delete) |
| `files-trash-manage` | none | write plane reachable (`files.trash.manage`, risk `consequential`; SHELL refused at `grant.shell-consequential`; catalog claim=partial; humanRoute planned empty; Files `emptyBinAuthorized=false`; no Empty Bin LIVE; Recycle Bin / Empty Bin LIVE residual OPEN after PR #63) |
| `defaults-mime-set` | Settings › Apps | write plane reachable (`defaults.mime.set`, risk `low`; catalog claim=partial; humanRoute visible; Settings MIME LIVE CONTROL for writable associations with more than one installed candidate; already-default and non-candidate refuse before preflight) |

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
- `entry.rename` — Files › Rename. Risk `low`. SHELL may hold a standing grant. Same-directory only. Collision refuses. The scoped listing carries the selected entry identity so a names-only TOCTOU cannot hide inode drift.
- `entry.copy` — Files › Copy and Paste. Risk `low`. SHELL may hold a standing grant. Regular files and directories. Destination is a writable Files location. Collision, symlink loops, and nest-inside-source refuse. Copy maps `EXDEV` errno from `mkdir`/`open` only; overlay or bind-mount children may copy. Staging is in-app only. The scoped destination listing carries the source entry identity so a names-only TOCTOU cannot hide inode drift.

**Write plane reachable, not LIVE under SHELL**

- `entry.move` — Files cut/move through `files.provider`. Write plane reachable. Scope is the destination directory plus source identity, reusing `files.directory.<digest>`. Risk `consequential`. SHELL cannot hold a standing grant (`grant.shell-consequential`). Files Cut stays hidden while `cutAuthorized=false` so the shell principal cannot start a doomed preflight. Do not invent LIVE Cut under SHELL or an OS clipboard.
- `entry.trash` — Files › Trash through `files.provider`. Write plane reachable. Scope is the entry's parent directory, reusing `files.directory.<digest>`. Risk `consequential`. SHELL cannot hold a standing grant (`grant.shell-consequential`). Same grant rule as End Task. Files Trash controls stay hidden while `trashAuthorized=false` so the shell principal cannot start a doomed preflight. Do not invent a TASK workaround or LIVE Trash under SHELL.

**Unavailable (do not invent)**

- Restore UI. The `files.trash.restore` write plane is reachable. Real preflight reads `.trashinfo` and scopes the original destination directory. Risk `consequential`. SHELL cannot hold a standing grant. Catalog claim=partial; humanRoute planned empty. Files does not offer a Restore control.
- Empty Bin LIVE. The `files.trash.manage` write plane is reachable. Real preflight binds the Trash location listing. Empties regular files and empty directories plus their `.trashinfo`. Non-empty trash trees refuse. Risk `consequential`. SHELL cannot hold a standing grant. Catalog claim=partial; humanRoute planned empty. Files pins `emptyBinAuthorized=false` and does not offer Empty Bin LIVE.
- Permanent delete UI (write plane reachable; `deleteAuthorized=false`; no SHELL LIVE Delete)
- Recycle Bin as a product-complete place

The Files banner matches: New folder runs through `files.provider`; Copy and Paste run through `entry.copy`; the cut/move write plane exists but is not shell-authorizable; the OS clipboard stays unavailable; Trash write plane exists but is not shell-authorizable (CHANGES UNAVAILABLE); Restore write plane exists but is not shell-authorizable; the permanent delete write plane exists but is not shell-authorizable; the empty Recycle Bin write plane exists but is not shell-authorizable; Restore UI, Empty Bin LIVE, and Recycle product remain unavailable.

The scope function and payload deriver shipped with the v1 widen (not left reverted). `_entry_trash_scope` resolves the entry, derives its parent, and proposes the listing minus that name. The payload deriver reads scoped `currentState.value` and refuses any plan that does not remove exactly one name.

## Why entry.rename is scoped with identity in the listing

A names-only directory listing is the wrong scope for rename. The listing revision tracks names. Renaming changes a name, so the effect is visible, but an identity drift that leaves the names in place does not move the revision. `test_compare_and_swap_contains_concurrent_execution_and_toctou_drift` requires `files.state-stale` when the target entry's `identity` changes between preflight and execute.

The scoped rename plane keeps the v1 directory family and puts `selectedEntry.{entryId,identity}` on the listing document. Resource id is `files.directory.<digest(location,parent,entryId)>` so the session reader can rehydrate that identity from live inventory. Adversarial tests stay workspace-shaped where they already inspect the whole workspace. Lifecycle rename asserts the scoped listing.

Create and trash stay names-only. Their observable effect is a name appearing or disappearing, and the helper still inode-checks. Restore write plane is reachable from `.trashinfo` at real preflight; Restore UI stays honest-unavailable. Do not invent Restore LIVE.
## What still blocks Software Center

Not the executor. The shipped catalog carries `assurance: contract-seed`, and `PackageProvider` deliberately refuses live mutation for an unattested seed. That gate is correct and was left closed. Opening it is a release-attestation decision.

`RELEASE_PLAN_ONLY_DETAIL` in both the packages and compatibility providers still says live mutation "waits for the privileged system executor". For packages that sentence is now stale, but the accurate replacement depends on whether the provider's `_require_live_execution` sits on the operation path at all, which needs a running daemon to determine. Left alone rather than guessed at.

## Remaining leaf work

`bluetooth` is the last leaf domain without a writer. Its operation is `audio.pair`, a multi-step interactive flow rather than a single verb, so it does not follow the five-step recipe.

`defaults` is a `StateDomainProvider` like `files` and needs the same scoped-resource treatment.

## Debt paid

`input.keyboard-layout.set` left the `legacy.domain.direct-providers` debt, which drops from 36 capabilities to 35. Its removal gate is a typed provider with structured state, preflight, results and recovery, which is what landed. The Superbar widget still assembles `hyprctl switchxkblayout` as a shell string. It is not redundant -- it cycles from the bar, which the Settings control does not replace -- so retiring it means routing that cycle through the typed verb, not deleting it.

Neither the `parity.language-locale` nor the `windows-native.33` row moves off `prototype`. Switching between configured layouts is not the whole job, and forty-task row 33 stays unproven until it runs on metal.
