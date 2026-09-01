# State-domain writes — what landed and what blocks

SHA `6ac3b401` on `work`. Shell gates: 13 of 247 files fail, the identical list that fails at `e3ec490b` before this work. No regression.

The audio write path is proven again on the live daemon this session: 40 → 55 → 40 through preflight, approve, start, and the durable coordinator.

## What landed

`files.directory.create` is wired end to end and **succeeds**. On a workspace that satisfies the mutation precondition, the operation plane creates a real directory on a real filesystem through the code-owned helper and passes validation, reaching `status: succeeded`.

- `providers/files/provider.py` takes `session_operable`, and `provider_builtins` opts files in. The provider still never mutates.
- `operations/session_apply.py` grew a second action, selected by argv so request data still cannot choose a command. It resolves `locationId` through the code-owned catalog and XDG user-dirs, rejects traversal, absolute paths, unsafe names, and non-writable locations, then creates the directory with a single `mkdir` that fails closed if the name is taken.
- `bin/omarchy-fabric-session-apply` now forwards `"$@"`. It did not before, so every action selected the audio branch.
- `daemon._build_operations` carries the `files.directory.create` intent and definition, and the state reader dispatches on resource id.
- The coordinator tolerates `guards`, which every `StateDomainProvider` preflight emits and no leaf provider does. Its `optional` set was never optional: the check was an exact match against `required | optional`, so a field named there was mandatory. It is now a genuine subset range and the durable plan matches.

Helper bounds were tested directly: a real directory is created, and traversal, absolute parent, slash in name, `..`, non-writable location, malformed location id, and duplicate name are all rejected.

## Three findings that block the rest

These are not wiring gaps. Each is a contract conflict that surfaced only because the path finally executed.

### 1. `rootToken` tripped the durable secret guard

Every files location carries a `rootToken`, which is a `state_revision` digest of the location identity. `_is_sensitive_key` matches any key containing `token`, so `scan_for_secrets` flagged fourteen paths and the coordinator refused to persist any plan with `operation.secret-rejected`. No state-domain operation could ever have been stored.

Fixed by renaming the field to `rootDigest` across the provider, the schema, `FilesModel.js`, and two tests. The field is a digest, so the name is more accurate, and the heuristic keeps its full strength.

### 2. The mutation precondition is unreachable on a populated machine — FIXED

`StateDomainProvider` enforces `operation_available ⇒ availability == "available"`, and `available` may carry no degradation reasons. The files inventory is bounded by `MAX_REAL_STATE_BYTES = 36 * 1024` and appends a `files.inventory-truncated` reason whenever it trims to fit.

On the metal box — 79 entries in Pictures, 40 in home — the cap always bites, so there is always a reason, so `available` never holds, so mutations are refused. The gate is correct; it is simply unsatisfiable against a real home directory.

**Resolved.** `files.directory.create` now succeeds against the real home on metal, with `files.inventory-truncated` still present. Proven end to end: `operation available: True`, `status: succeeded`, and the created folder visible in the Files app's Documents view.

Two changes, in this order, because the second is only defensible after the first:

1. **The scope reads the target directory from disk.** `RealFilesBackend.directory_listing(location_id, parent)` does a bounded `scandir` of the one directory, and a new `directory.inspect` read action exposes it through the typed seam so the daemon's validation reader uses the same source. The scoped state no longer derives from the bounded inventory at all, so truncation cannot make it wrong. The fake backend keeps the state-derived path.
2. **The gate distinguishes read-completeness from mutation-safety.** `StateDomainProvider` takes `read_completeness_codes`; files declares `files.inventory-truncated` and `files.mount-inventory-truncated`. A degraded snapshot whose reasons are all in that set may still be operable. Any other reason still refuses, and `available`-with-reasons is still forbidden.

This is a narrowing, not a weakening: before the first change, truncation genuinely could have corrupted the scoped listing, and the blanket refusal was correct. After it, truncation has no bearing on the operation, and refusing on it was over-broad — it blocked a create in an untruncated Documents because Pictures had been trimmed.

The original analysis below stands for why the blanket gate was right until the scope stopped depending on the inventory.

### 3. Whole-state equality cannot validate a real filesystem mutation — FIXED

**Resolved.** `files.directory.create` now completes the full plane on metal: preflight, approve, start, apply, validate, `status: succeeded`, with a real directory on disk. The fix is option 1 below — the scoped resource — which weakens nothing.

What shipped:

- `files-directory-state-v1.json`, `files-directory-preflight-v1.json`, `files-directory-result-v1.json`, minted as new files. The v0 schemas are untouched, so nothing already speaking v0 changed.
- `OperationSpec` takes an optional `scope`. When present, preflight binds `resource` to `files.directory.<sha256>` and reports `currentState` / `proposedState` as that one directory's listing — `{locationId, parentRelativePath, names}` — which is genuinely predictable. mtime-derived values stay out of it, so equality holds honestly.
- `guards.snapshotRevision` anchors to the scoped revision, keeping the plan's own invariant.
- Recovery deliberately stays on the **workspace**: `recovery.priorState` is the full prior state and `recoveryFromRevision` is the workspace revision after the change, so `undo` still restores everything and its result is reported against the workspace result contract. Validation is scoped; recovery is not.
- The helper recomputes `files.directory.<sha256(files.directory\0location\0parent)>` from the payload and refuses any mismatch, so a payload cannot target a directory other than the one its resource names.

The remaining gate for the default workspace is finding 2, not this. The scope reads `state["entries"]`, so a truncated inventory could yield an incomplete listing — which is exactly why the availability gate should keep refusing while truncated. Making this reachable on a populated home means having the scope read the target directory directly rather than deriving it from the bounded inventory.

### 3a. The original diagnosis, kept for the record

`coordinator._validate_executor_state` compares observed state to `plan.preflight["proposedState"]["value"]` with strict equality, excluding only `revision`. The provider must therefore predict the entire post-mutation workspace exactly.

`_create_directory` is a state transformer: it deep-copies current state, appends one entry, and re-sorts. That is correct for a backend that **stores** its state and replays it. The real files backend **derives** state by scanning the filesystem. The two cannot agree, for reasons that are structural rather than incidental:

- **The projection appends one entry; the scan produces two.** Verified on metal: creating `Documents/ProbeDir` yields an entry under `files.location.documents` with relativePath `ProbeDir` **and** one under `files.location.home` with relativePath `Documents/ProbeDir`, because home and Documents are both scanned locations and one nests inside the other. Any create inside a nested location has this property.
- **The projected id can never be reproduced.** It is `stable_resource_id(DOMAIN, "entry", f"created\0{location}\0{parent_identity}\0{relative}")`, and `identity` is `state_revision({"created": entry_id, ...})`. Both are synthetic tokens meaningful only to a backend that keeps them. A rescan derives ids from the actual path. Entries are sorted by id, so a mismatched id also reorders the list and cascades through every later index.
- **Two values are unpredictable in principle.** `modifiedNs` is null in the projection and a real mtime on disk, and the parent location's `rootDigest` shifts because creating a child changes the directory mtime.

So the operation applies correctly and then fails validation with `executor.invalid-result`. The directory exists on disk; the plane reports failure.

This is not a matter of correcting a few fields, and it is not one check to relax. The equality assumption is present at all three layers:

- `coordinator._validate_executor_state` compares observed to target
- `SessionCommandExecutor.validate` compares observed value to expected
- `StateDomainProvider.validate` (`providers/files/_engine.py:659`) raises `validation-failed` unless `actual == self._state(expected_value)`

The state-domain operation model assumes stored state throughout. The real files backend is derived state. Three ways out, and they are not equivalent:

1. **Scoped resource — this is what shipped.** Bind the operation to the target parent directory rather than the whole workspace. Its state is a listing of that directory — current names plus the new one — which is genuinely predictable, and mtime-derived values stay out of it. Whole-state equality still holds, so **nothing is weakened**. Costs a new resource kind, id derivation, and a read action on the provider. This is the right answer.
2. **Stored overlay.** The real backend records applied mutations and replays them over the derived scan. Preserves equality, but the overlay can drift from the filesystem and becomes a second source of truth.
3. **Predicate validation.** Assert only that the fields the operation claimed to change actually changed. Cheapest, and it **weakens the contract**: it stops verifying that nothing else changed. Do not choose this one to make a proof go green.

Whichever is chosen also removes a second defect: today any unrelated file change anywhere in the workspace invalidates a pending plan.

### It was a v1, not an edit

Option 1 cannot be done inside the current schemas. They pin the binding exactly:

```
files-operation-preflight-v0.json  resource.kind → const "files.workspace"
                                   resource.id   → const "files.workspace.primary"
files-operation-state-v0.json      value         → $ref #/$defs/workspace
```

A scoped resource needs a second resource kind and a directory-listing state value, so both files change shape. Editing them in place silently redefines `v0` for every client already speaking it, and the provider manifest, the durable plans in `operations.db`, and the shell's closed read contract all reference these ids. The form this took was `files-operation-state-v1.json` plus `files-operation-preflight-v1.json`, a manifest version bump, and a migration path for stored plans.

That is a product decision about contract versioning, shared with `defaults` and `process.termination.plan`. It is not a change to slip in to make a proof pass, which is the only reason an agent would be tempted to edit v0 in place.

## A UI defect found with pixels

Settings Sound renders the live control correctly. After an external operation moved the sink 40 → 55, the open window was byte-identical: slider unmoved, channels still 40, `observed` timestamp unchanged. Relaunching the app showed 55 with the slider moved and a new timestamp.

Rendering is right. The page reads once at load and never re-reads, so any change made outside it — by another client, or by hardware keys — leaves Settings stale.

## Why the other domains cannot be closed

Two separate walls, and it is worth knowing which one you are hitting.

### Wall one: the proposed state is synthetic

The audio slice works because volume is a real readable property — `pactl` reports the new value, so the provider's `proposedState` and the re-probed state agree. That is the exception, not the rule.

`process.termination.plan` proposes `lifecycle: "termination-planned"`. The real probe only ever emits `"running"` (`providers/process/provider.py:149`); `"stopped"` and `"termination-planned"` exist solely for the stored-state fake backend. So Administration's End Task hits the identical wall as files: whole-state equality can never hold. This is the same defect as finding 3, not a separate one, and it means End Task cannot be wired without the same contract change.

Of the leaf domains, `power`, `network`, `display`, and `input` all propose real readable properties and are structurally closable. `display` needs the user in the `i2c` group; `input` needs a second configured keyboard layout; `network` has no Wi-Fi device on this host.

### Wall two: polkit cannot see an Omarchy session

`power.profile.set` is fully wired — helper action, intent, operation definition, state reader — and it fails at the last step:

```
GDBus.Error:org.freedesktop.DBus.Error.AccessDenied: Not Authorized:
org.freedesktop.UPower.PowerProfiles.switch-profile
```

The policy is `allow_active=yes`, `allow_inactive=no`, and the login session reports `Active=yes`, `Remote=no`. It still fails, because the fabric daemon's cgroup is:

```
/user.slice/user-1000.slice/user@1000.service/app.slice/omarchy-fabric-checkout.service
```

There is no `session-N.scope` in that path. Processes under the systemd user manager are not attached to a login session, so polkit resolves them as inactive and `allow_active` never applies. Every Omarchy component is placed this way — the shell apps sit in the same `app.slice` — so **no part of the product can satisfy a polkit `allow_active` check as currently structured.**

`session_operable` is therefore left `False` for power: turning it on would put a control in Settings that always errors. The helper action, intent, and operation definition are kept and are correct. Closing this needs a decision that is not a code change: either ship a polkit rule under `/etc/polkit-1/rules.d/` granting these actions, or run the daemon inside a session scope. Both touch system security policy and belong to the operator, not to an agent.

## Deploying a schema rename

The `rootToken` rename is a wire-contract change, and the shell validates provider state against a closed contract. Deploying the provider without restarting both sides puts Files into `files.invalid-response` — "Fabric returned data outside the closed Files read contract" — with a red FAILED card and no inventory. That happened on metal during this work.

Restart `omarchy-fabric-checkout.service` and the shell together for any field rename. Restarting only one leaves the two sides disagreeing, and the failure looks like a provider fault rather than a version skew.

## Do not reopen

Do not weaken `operation_available ⇒ available` to make a proof pass. Do not add a name to the sensitive-key allowlist; rename the field instead. Do not widen `session_operable` to a domain with no code-owned helper action.

## The ceiling on shell-driven writes

`security/grants.py:94` refuses any `CapabilityGrant` where the principal is `SHELL` and `maximum_risk.rank >= CONSEQUENTIAL.rank`. Unconditionally — persistence is irrelevant.

That single rule explains exactly which write paths work. `audio.output-volume.set` and `files.directory.create` are declared `low`, so the shell may hold their grants; both are proven end to end. `process.termination.plan` is declared `consequential`, so `operation.approve` fails with `grant.shell-consequential` and Administration can never end a task, however completely it is wired.

So the reachable write plane from Settings and Administration is, by design, the low-risk one.

It is broader than the shell, too. `daemon.py:1883` admits exactly one endpoint:

```
EndpointAdmission(endpoint_id="fabric.owner-rpc", kind=PrincipalKind.SHELL)
```

`PrincipalKind` has `SHELL`, `PROVIDER`, and `TASK`, and the security model already carries `TASK`-specific rules — `grants.py:99` and `policy.py:46` bind a task grant to its `task_id`. No endpoint is admitted for either non-shell kind. So every RPC caller is `SHELL`, and **no consequential or high-risk operation is reachable over RPC by anyone today**, not merely from the product surfaces.

The answer is designed and unwired rather than missing: admit a `TASK` endpoint and route consequential operations through a task-bound principal. That is a security-architecture decision — it creates a privileged RPC role — and it is the same answer packages and compatibility will need on top of root.

End Task is wired and correct up to that line: scoped `process.termination.<sha256>` resource with `{present}` state, a helper that re-derives identity from `/proc` so a stale plan cannot signal a reused PID, and the Administration control plus its state machine. `terminationAuthorized` is `false` so the product does not offer a button that cannot succeed, and the page says why.

Process inventory selection also changed. It took `sorted(users, key=(uid, pid))[:48]` — the 48 oldest user processes, which is session infrastructure and nothing a person launched. It now ranks by resident memory then CPU, so the bounded 64 shows what is actually consuming the machine.

## What is left, and why

Three deliberate boundaries, none of them bugs:

- **polkit cannot see an Omarchy session.** Blocks `power.profile.set`, which is otherwise complete.
- **The shell cannot authorize consequential operations.** Blocks End Task.
- **Root.** Blocks packages and compatibility; compatibility also needs measured-host attestation.
