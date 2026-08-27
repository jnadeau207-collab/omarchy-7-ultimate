# Managed work plane

The managed-work plane is the durable, read-only backend contract for Agent Center. It owns context snapshots, task and run history, automation definitions and firings, provider and operation projections, permissions, usage, artifacts, diagnostics, and twelve bounded query views under `default/fabric/omarchy_fabric/managed_work/`.

## Account and session identity

The daemon derives the durable account owner as `account.uid.<uid>` from authenticated Unix peer credentials and the daemon's operating-system ownership. A client label, RPC field, argument, environment value, or reconnect token cannot select that owner. The account owner survives endpoint reconnects and daemon restarts.

Each accepted endpoint also receives a separate `session.<uuid>` identity with a bounded lifetime. Session identity is used only where live endpoint provenance matters. Session-scoped context is deleted when the endpoint closes and during restart recovery; its idempotency replay record is deleted atomically. Durable tasks accept only principal-scoped context, so reconnect cannot strand a task behind an expired session. Task-scoped context remains bound to its existing task and cannot be rebound.

The database is an owner-only per-user store. Compatibility rows projected from legacy `principal.<uuid>` reference-operation history are visible only to the authenticated stable account owner and retain their original session provenance. They are read-only history: reconnecting as the stable owner does not acquire authority to approve, start, cancel, or replay an operation created by a different legacy session. Those mutations continue to require the exact authoritative reference-operation principal/session contract or an already-defined recovery token path.

## RPC and authority boundary

The daemon exposes one managed-work RPC method: `managed-work.query`.

Its versioned `v0` parameters are closed and route-aware. The daemon binds the query to the authenticated account owner and active endpoint session; callers cannot send an actor or owner. Entity type and entity ID must appear together, entity lookups are accepted only by the owning view, and entity lookups cannot also carry a cursor. Query validation completes before provider or operation projection refresh, so malformed requests cannot mutate projection revisions, rows, events, or cursors.

No managed-work mutation or execution RPC exists. The plane cannot launch a process, accept an executable or argument vector, evaluate code, read a secret store, authorize a consequential operation, or claim a sandbox exists. Task, run, automation, and troubleshooting responses report execution unavailable. The trust plane remains authoritative for grants and approvals, the reference-operation ledger remains authoritative for consequential operation lifecycle and recovery, and the typed provider registry remains authoritative for provider readiness.

## Twelve Agent Center views

| View | Durable read model |
|---|---|
| `agent.overview` | Owner-scoped task, approval, automation, unavailable-firing, and live-context counts with explicit execution readiness. |
| `agent.tasks` | Bounded task pages, latest owned run and immutable steps, plus task/run entity lookup. |
| `agent.approvals` | Unexpired approval projections from authoritative operation/trust state. |
| `agent.automations` | Definitions, policies, durable cursors, and at most five latest firings per item. |
| `agent.activity` | Exact-set reference-operation projections, change state, recovery eligibility, artifacts, and operation lookup. |
| `agent.history` | Bounded lifecycle events with explicit pruning evidence and expiring cursors. |
| `agent.context` | Visible redacted context; another endpoint's session context is omitted. |
| `agent.permissions` | Monotonic permission projections; persistent high-risk automation grants are refused. |
| `agent.usage` | Provider metrics and owner-scoped aggregate records and cost. |
| `agent.providers` | Monotonic real-registry projections, registration order, and honest `available`, `degraded`, `unavailable`, `incompatible`, or `not-registered` state. |
| `agent.artifacts` | Opaque task-owned handles, media type, size, hash, scope, and run provenance; no filesystem path. |
| `agent.troubleshooting` | Schema, integrity, restart state, owner counts, configured capacity, recovery actions, and execution readiness. |

Every result is bound to the view-specific definitions in `default/fabric/schema/managed-work-v0.json`, and `managed-work.query` is bound in `default/fabric/schema/rpc-v0.json`. Top-level and nested record objects are closed. Cursors bind version, view, account owner, and ordering identity. Provider cursors additionally bind registration order and provider identity. A cursor cannot cross an owner or view.

One query response is capped at 56 KiB so it fits below the Fabric RPC frame limit. Persist and startup checks prove that every emitted single item, its required summary or composite, and a worst-case valid pagination cursor fit before a transaction commits or the socket is published. Page size remains bounded and an oversized historical row causes typed startup refusal rather than a permanently failing query. Restart recovery and its complete post-recovery query validation share one transaction, so a failed projection check rolls back every recovery mutation.

## Projections

Provider projection accepts only the closed real registry catalog. Registration order is durable, revisions increase only when projected truth changes, missing providers become `not-registered`, and `degraded` means usable for reads and preflight while still carrying an honest degraded code and explanation. Raw registry detail is reduced to a digest and never persisted or returned.

Reference activity is read through the public, bounded `ReferenceOperationManager.projection_sources` seam. It verifies the tamper-evident ledger, returns plain secret-free copies, and excludes recovery tokens, authorization codes, request arguments, and raw error or result payloads. The managed projection reconciles the exact operation set for the explicit stable owner and source capability, including an empty snapshot. It cannot delete another owner or capability family, and an incoming operation ID cannot replace a row owned by another source family.

Projection rows store canonical payloads alongside query scalars. Startup requires byte-canonical, type-exact payload/scalar coherence, legal source revisions, same-owner task, run, artifact, approval relationships, non-dangling JSON context links, and legal context scope and binding. Valid JSON or a recomputed content hash does not bypass those checks.

## Context privacy

Context capture normalizes finite JSON with bounded encoded size, node count, depth, key size, and string size. Lock-screen, password-field, Polkit, browser-credential, keyring, and private-notification sources are excluded. Private notification text is removed. Exact secret-shaped keys are redacted before hashing.

Free text detects and irreversibly redacts authorization material, private keys, URL credentials, GitHub and AWS tokens, OpenAI `sk-` families, Slack `xox*` and `xapp` families, GitLab `glpat`, npm tokens, and bare JWTs. Findings retain only a JSON pointer and secret kind, never token fragments. Token-shaped object keys are refused with a synthetic non-secret path because retaining the key would itself persist the token. Safe structural keys such as `tokenizer` are not treated as secrets. Stable IDs and every query-exposed scalar are checked before a transaction, so token-shaped sources, capabilities, resources, providers, metrics, handles, or IDs cannot poison live state. Non-context durable inputs reject secret-shaped data rather than redacting it.

Startup scans readable older schemas for unredacted durable secrets before backup or migration, so refusal does not create an additional secret-bearing backup. Current-schema JSON and scalar text receive the same check before any query is published.

## Database and daemon lifecycle

Managed work uses schema version 4, SQLite strict tables, foreign keys, WAL mode, `synchronous=FULL`, exact schema objects, and bounded per-owner capacities. Startup refuses malformed JSON, broken hashes, projection drift, cross-owner links, dangling relationships, unexpected tables, indexes, views, triggers, columns, missing indexes, foreign-key failures, active or live rows above configured capacity, and query items that cannot fit. Recovery changes executor-owned `running`, `waiting`, and `retrying` task and run states to `interrupted`; it never guesses success. Pending idempotency claims become interrupted.

Daemon startup orders authority acquisition as follows:

1. Secure the state directories and prepare only a stale socket the daemon can prove it owns.
2. Bind and listen on a manually created Unix socket, capture its inode, and never let asyncio auto-unlink it.
3. Acquire nonblocking leases for both Fabric and managed-work databases in deterministic canonical-path order.
4. Open SQLite through the held database inode, prove exactly one new SQLite descriptor matches it before any PRAGMA, migration, WAL creation, chmod, or recovery, and validate journal, WAL, and SHM sidecars at their use boundary.
5. Recheck database, lease, and socket identities before publishing the listener.

The daemon holds actual database-inode leases until shutdown, so hard-link aliases contend on the same lease. Path locks serialize first creation and are never unlinked. A losing daemon removes only the socket inode it captured and does not mutate the winner's database or recovery state.

These dependency-free checks defend against foreign ownership, symbolic links, hard-link aliases, and path or inode swaps observable through the held and opened descriptors. They do not claim integrity against arbitrary code already executing as the same UID. No APSW or custom SQLite VFS is part of this tranche.

The configured SQLite page limit bounds logical main-database pages. It is not an absolute physical-disk quota for WAL bytes while another reader pins WAL history. Operators must still monitor the private state filesystem. Typed `SQLITE_FULL`, I/O, corruption, and lock failures preserve the primary error and roll back without leaving partial rows or idempotency claims.

## Future mutation seam

Future task creation, automation mutation, executor transitions, usage submission, and artifact registration require separate capability-specific RPCs and policy review. They must not be added to `managed-work.query` or a generic root helper. A future executor must prove its sandbox, resource controls, scoped Fabric proxy, cancellation, restart, and reconciliation behavior before any unavailable execution state can become available.
