# Files and default-application providers

The Files and Defaults providers are typed Fabric backend foundations for consumer surfaces that need Files, This PC, Desktop, Trash, removable and SMB mounts, recent items, bounded search, and default MIME or protocol applications. They fit the central provider registry without granting the provisional daemon an untracked host mutation path.

## Provider surfaces

`files.provider` exposes these read actions:

- `inspect` returns one revisioned workspace containing locations, entries, mounts, and recent-item ordering.
- `browse` returns bounded children of one canonical location-relative directory.
- `search` performs a deterministic bounded search over the trusted inventory snapshot.
- `recent` resolves recent-item identities back to the same typed entry records used by browse and search.

It also exposes complete preflight, execute, validate, and undo hooks for `directory.create`, `entry.rename`, `entry.trash`, `trash.restore`, `mount.connect`, and `mount.disconnect`. The central registry names the runtime hooks `apply` and `rollback`; the provider keeps those as exact aliases of execute and undo so the lifecycle vocabulary remains explicit to future durable-operation consumers.

`defaults.provider` exposes `inspect`, `mime.query`, `protocol.query`, and `association.inspect`, plus complete lifecycle hooks for `mime.set`, `protocol.set`, and `association.clear`. `association.inspect` is the scoped reader durable apply uses to re-read `{kind, key, defaultAppId}` — the same class as Files `directory.inspect`. Its preflight includes the association revision, selected application revision, whole-database revision, and a closed execution-plan descriptor naming the typed helper as `defaults.apply-v0` with `shell: false`.

## Identity and revision rules

Provider resource identities are deterministic SHA-256-derived stable IDs. Native paths, device selectors, and desktop-file paths are not used as Fabric resource IDs. Whole-domain revisions and per-entry, per-location, per-application, and per-association identities use canonical finite JSON fingerprints. Fake inputs are canonicalized by stable ID before admission, so backend enumeration order cannot change a consumer-visible revision.

The Files workspace is the single rollback unit. This makes a preflight freeze every location, entry, mount, and recent-item relationship that can affect a safe mutation. The Defaults database is likewise one rollback unit so a change cannot validate against a different application or association inventory than the one the user approved.

## Files path boundary

All caller-supplied Files paths are location-relative UTF-8 values. The provider normalizes Unicode to NFC and rejects absolute paths, backslashes, empty segments, `.` or `..`, control characters, NUL, overlong segments, and overlong paths. Mutations reject symlink targets and any symlink in the selected ancestry.

Real inventory opens every component of roots and descendant directories with `O_DIRECTORY` and `O_NOFOLLOW`, and performs descendant metadata reads through directory file descriptors. Configuration, XDG user-directory, recent-file, desktop-file, and fake restart documents are opened through the same no-follow component boundary, must be regular files, are byte-bounded, and are rejected if device, inode, size, mode, ctime, or mtime changes during the read. A race that changes an opened identity is skipped or reported as typed degradation rather than trusted. Preflight records the whole-workspace revision plus root and entry identity anchors; execute performs an atomic compare-and-swap on the same revision, which closes the time-of-check/time-of-use gap at the provider seam.

The real adapter never reads user file contents. It inventories bounded metadata only. Startup traversal is capped by entry count, depth, and a 36 KiB state budget. Byte-budget trimming removes leaves before ancestors, and semantic admission independently rejects slash-containing orphan roots, inconsistent parents, symlink ancestors, and spoofed mount/location relationships. It parses `/proc/self/mountinfo` directly under a byte bound, classifies SMB only from the kernel filesystem type, strips authority credentials, returns only a bounded host and first share component, and does not traverse removable or network roots during startup. Recent-file XML is byte-bounded, refuses DTD or entity declarations, accepts only local `file:` URIs, and resolves only paths already present in the trusted inventory.

Trash is recoverable, not permanent deletion. `entry.trash` preserves the original location, parent identity, and relative path in typed recovery metadata. The scoped `files-directory-{preflight,result,state}-v1` family was widened in place — `action` is an enum of `directory.create` and `entry.trash` (and still lists `trash.restore`) rather than a parallel Trash family — because trashing an entry is a name disappearing from the same `{locationId, parentRelativePath, names}` listing `directory.create` already validates from disk. v0 workspace schemas were not edited. Shared family is not shared risk: `directory.create` stays `low`; `entry.trash` stays `consequential`. SHELL cannot hold a standing grant for trash.

`trash.restore` is write-plane reachable. Real preflight reads the trashed entry's `.trashinfo` and scopes the original destination directory, the listing-diff inverse of `entry.trash`. Risk stays `consequential`. SHELL cannot hold a standing grant. Inspect inventory still stores `entry.trash` as null. Files does not offer a Restore control. No permanent-delete capability exists in this tranche. Recycle Bin is not product-complete.

## Default-application boundary

The real Defaults adapter reads `.desktop` files through no-follow directory file descriptors, accepts only stable bounded regular files with ASCII desktop IDs, rejects control-bearing display fields, and never returns an absolute icon path. User entries are scanned before local and system entries so the global bound cannot starve higher-priority intent; user entries override local entries, local entries override system entries, and a higher-priority `Hidden=true` tombstone suppresses the lower-priority application. The final database is capped at 36 KiB, and trimming rewrites candidate lists and dangling status before semantic validation.

Default queries are a code-owned catalog of immutable `FixedArgvCommand` values for `/usr/bin/xdg-mime query default`. No caller value is appended to argv, no command is interpreted by a shell, and the shipped association catalog must match the code-owned MIME and protocol tuple exactly. Empty, missing, malformed, or dangling query results remain explicit unconfigured, degraded, or dangling association states.

The real adapter deliberately does not call `xdg-mime default`. Its `compare_and_swap` stays mutation-unavailable. Production builtins set `session_operable=True`, so `mime.set` and `protocol.set` preflight are reachable. Durable apply re-reads scoped state through published `association.inspect`, then the coordinator runs the typed `defaults-mime-set` and `defaults-protocol-set` helpers. Settings offers LIVE CONTROL only for the default browser (`protocol.set`). It does not offer MIME LIVE CONTROL.

## Availability

Availability is a three-state typed value:

- `available` means reads and fake lifecycle operations are complete and no degradation reasons exist.
- `degraded` means a trusted partial or read-only snapshot exists, with one or more structured reasons.
- `unavailable` means no trusted state exists and at least one structured reason explains why.

The real Defaults backend still refuses provider-side mutation. Production preflight is session-operable; the helper owns the write. A `session_operable=False` builder stays read-only with an `operation.integration-required` recovery seam. Missing folders, unsafe roots, malformed recent XML, bounded-inventory truncation, missing `xdg-mime`, and malformed query output are reported independently instead of being hidden by mock data or fallback commands.

## Hermetic lifecycle adapters

Fake adapters exist solely for contract, operation, restart, and adversarial tests. They validate the full closed state schema on construction and after every transition, cap mutable state at 12 KiB so the three-state preflight remains within Fabric's frame budget, cap the persistence envelope at 16 KiB, reject duplicate keys and non-finite numbers on restart, and require an existing real absolute persistence parent. Persistent transitions reload under a process-shared lock and a POSIX advisory lock, write an owner-only exclusive temporary file, fsync the file and directory, and atomically replace the state document before publishing the new in-memory revision. Independent provider instances therefore share one compare-and-swap boundary instead of losing updates from stale restart snapshots.

Every recovery payload binds the prior state to the action and exact proposed-state revision. Undo verifies the prior state's semantic fingerprint before any write and refuses an old recovery payload when the current revision contains newer intent, even if the caller supplies that newer current revision as the generic compare-and-swap value. A repeated undo against an already restored exact state is a no-op; a mismatched wrapper is a typed `state-corrupt` failure with zero writes.

The tests cover central registry admission, closed schema traversal, every read and operation action, no-op writes, exact validation and guarded undo, rollback over newer intent, same-process and independent-instance concurrency, cancellation before lock admission, state drift after preflight, orphan graphs, Unicode control attacks, symlink and ancestor-symlink traversal, destination collisions, restart persistence, duplicate-key corruption, non-finite corruption, backend failures, no-follow Linux inventory, malicious and symlinked recent XML, mount authority spoofing and credential redaction, fixed argv, missing dependencies, malformed and secret-bearing probe failures, bounded priority overrides, unsupported applications, read-only associations, and unauthenticated preflight.

## Integration seams

Central integration should register `build_provider()` from `omarchy_fabric.providers.files` and `omarchy_fabric.providers.defaults` in the code-owned provider catalog. Registration is intentionally outside this tranche so the root registry, capability catalog, parity graph, packaging, and durable operation coordinator can be updated atomically by their owners.

`OMARCHY_PATH` must identify the installed Omarchy tree. The Files provider loads `default/ultimate/files/locations-v0.json`; the Defaults provider loads `default/ultimate/files/default-associations-v0.json`. Both refuse to construct when that session invariant is absent.

A future Files host executor must preserve the same location-relative contract, openat-style no-follow resolution, frozen root and entry identity checks, and atomic revision semantics. It must not accept absolute paths or shell commands. A future Defaults executor must be the named typed helper or a versioned successor, accept structured input through a non-argv channel, recheck association and application revisions, and validate the resulting database before reporting success.

`test/shell.d/fabric-files-defaults-test.sh` is a runnable shell-test entry point and must be committed with executable mode `100755`. Archive copies made on filesystems without POSIX mode support can lose that bit; integration must restore it before committing rather than weakening the wrapper requirement.
