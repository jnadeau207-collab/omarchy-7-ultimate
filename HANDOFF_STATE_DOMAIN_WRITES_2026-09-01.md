# State-domain writes — what landed and what blocks

SHA `f6248d3d` on `work`. Shell gates: 13 of 247 files fail, the identical list that fails at `e3ec490b` before this work. No regression.

The audio write path is proven again on the live daemon this session: 40 → 55 → 40 through preflight, approve, start, and the durable coordinator.

## What landed

`files.directory.create` is wired end to end and **executes**. On a workspace that satisfies the mutation precondition, the operation plane creates a real directory on a real filesystem through the code-owned helper.

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

### 2. The mutation precondition is unreachable on a populated machine

`StateDomainProvider` enforces `operation_available ⇒ availability == "available"`, and `available` may carry no degradation reasons. The files inventory is bounded by `MAX_REAL_STATE_BYTES = 36 * 1024` and appends a `files.inventory-truncated` reason whenever it trims to fit.

On the metal box — 79 entries in Pictures, 40 in home — the cap always bites, so there is always a reason, so `available` never holds, so mutations are refused. The gate is correct; it is simply unsatisfiable against a real home directory.

Proving execution required a workspace sparse enough to fit under the cap. Raising the cap only moves the threshold and does not address finding 3.

### 3. Whole-state equality cannot validate a real filesystem mutation

`coordinator._validate_executor_state` compares observed state to `plan.preflight["proposedState"]["value"]` with strict equality, excluding only `revision`. The provider must therefore predict the entire post-mutation workspace exactly.

`_create_directory` is a state transformer: it deep-copies current state, appends one entry, and re-sorts. That is correct for a backend that **stores** its state and replays it. The real files backend **derives** state by scanning the filesystem. The two cannot agree, for reasons that are structural rather than incidental:

- **The projection appends one entry; the scan produces two.** Verified on metal: creating `Documents/ProbeDir` yields an entry under `files.location.documents` with relativePath `ProbeDir` **and** one under `files.location.home` with relativePath `Documents/ProbeDir`, because home and Documents are both scanned locations and one nests inside the other. Any create inside a nested location has this property.
- **The projected id can never be reproduced.** It is `stable_resource_id(DOMAIN, "entry", f"created\0{location}\0{parent_identity}\0{relative}")`, and `identity` is `state_revision({"created": entry_id, ...})`. Both are synthetic tokens meaningful only to a backend that keeps them. A rescan derives ids from the actual path. Entries are sorted by id, so a mismatched id also reorders the list and cascades through every later index.
- **Two values are unpredictable in principle.** `modifiedNs` is null in the projection and a real mtime on disk, and the parent location's `rootDigest` shifts because creating a child changes the directory mtime.

So the operation applies correctly and then fails validation with `executor.invalid-result`. The directory exists on disk; the plane reports failure.

This is not a matter of correcting a few fields. The state-domain operation model assumes stored state, and the real files backend is derived state. Closing it needs one of: an overlay the real backend stores and replays, a resource scoped to the target parent rather than the whole workspace, or validation by predicate — the named directory now exists under the named parent — instead of whole-state equality. The last also removes a second defect: today any unrelated file change anywhere in the workspace invalidates a pending plan. This is a contract change shared with `defaults` and should not be rushed.

## A UI defect found with pixels

Settings Sound renders the live control correctly. After an external operation moved the sink 40 → 55, the open window was byte-identical: slider unmoved, channels still 40, `observed` timestamp unchanged. Relaunching the app showed 55 with the slider moved and a new timestamp.

Rendering is right. The page reads once at load and never re-reads, so any change made outside it — by another client, or by hardware keys — leaves Settings stale.

## Deploying a schema rename

The `rootToken` rename is a wire-contract change, and the shell validates provider state against a closed contract. Deploying the provider without restarting both sides puts Files into `files.invalid-response` — "Fabric returned data outside the closed Files read contract" — with a red FAILED card and no inventory. That happened on metal during this work.

Restart `omarchy-fabric-checkout.service` and the shell together for any field rename. Restarting only one leaves the two sides disagreeing, and the failure looks like a provider fault rather than a version skew.

## Do not reopen

Do not weaken `operation_available ⇒ available` to make a proof pass. Do not add a name to the sensitive-key allowlist; rename the field instead. Do not widen `session_operable` to a domain with no code-owned helper action.
