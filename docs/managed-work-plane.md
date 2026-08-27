# Managed work plane

The provisional managed-work plane is the durable backend contract for Agent Center context, tasks, runs, automations, projections, and bounded query views. It lives under `default/fabric/omarchy_fabric/managed_work/` and deliberately has no daemon RPC registration or execution authority yet.

## Authority boundary

`ManagedWorkPlane` owns one per-user SQLite database selected by its future daemon integration. The database is private managed-work state rather than a second copy of the main Fabric ledger. It owns context snapshots, task and run plans, immutable step plans, automation definitions and trigger firings, Agent Center projections, usage records, artifact ownership metadata, idempotency records, and a compact managed-work event history.

The module never launches a process, accepts an executable, evaluates code, reads a secret store, opens a general filesystem path, grants authorization, or claims a sandbox exists. Every task, run, automation, firing, overview, provider-readiness view, and troubleshooting view reports `managed-execution.not-integrated` with `available: false`. Existing interactive terminal agents are explicitly outside this contract. A future executor must fail closed when bubblewrap, the systemd transient scope, scoped Fabric proxy, or resource controls are unavailable; this store is not an unsandboxed fallback.

The trust plane remains authoritative for principals, permissions, grants, approvals, and operation policy. Managed work stores read-only monotonic projections for Agent Center. The main Fabric operation ledger remains authoritative for mutations and recovery. Provider inventory remains authoritative in the central typed-provider registry. Projection APIs reject stale revisions, conflicting data at the same revision, and links to tasks, runs, or artifacts owned by another principal.

## Database lifecycle

`ManagedWorkStore` uses SQLite WAL mode, `synchronous=FULL`, foreign keys, strict tables, and schema version 2. Open performs a path and owner check, refuses symbolic links and non-regular files, runs `quick_check`, refuses corrupt, unversioned non-empty, obsolete, and future-schema databases, and applies each migration in `BEGIN IMMEDIATE`. An existing readable database is copied through the SQLite backup API before migration.

Opening the database reconciles executor-owned `running`, `waiting`, and `retrying` task/run states to `interrupted`; it never guesses that work succeeded or that a consequential change was absent. Pending idempotency claims also become `interrupted`. Queued plans remain queued because no execution was asserted. The diagnostics query exposes the exact number of restart recoveries, schema version, integrity state, foreign-key violations, per-principal record counts, and configured capacity bounds without exposing the database path.

Every write uses a bounded immediate transaction. Creates use principal-, action-, and key-scoped idempotency records whose request hash binds normalized content. Concurrent callers with the same request converge on the same durable result; reusing a key for different content fails. Updates use expected revisions. Active and total task, run, automation, context, projection, artifact, usage, firing, and idempotency capacities prevent unbounded durable state. Capacity failures and schedule reconciliation failures roll back both new records and cursor movement. Compact lifecycle history uses bounded retention, records the exact row through which it pruned, and expires pagination cursors that crossed that boundary.

## Context snapshots

Context capture creates an immutable, content-hashed snapshot with source, capture and expiry times, sensitivity, owner principal and endpoint session, access scope, revision, and explicit redaction paths. Access scopes are `session`, `task`, or `principal`. Session context is unavailable to another endpoint session. Task context is bound to one existing owned task. Principal context can be retained by an automation.

Lock screen, password field, Polkit prompt, browser credential, keyring, and private-notification sources are refused. Secret-shaped object keys, including camel-case access/API token forms, and caller-specified keys are replaced before hashing and persistence. Content from an object marked as a private notification has its title, body, preview, message, and content redacted. Context is finite JSON with bounded depth, node count, string size, and encoded size. Task intent, automation intent, run transition detail, and event payload reject secret-shaped fields instead of storing them. Revocation is revision-checked and retained as evidence; expired or revoked snapshots cannot be attached to new work.

## Tasks, runs, and steps

Tasks persist normalized intent, immutable context identity lists, budgets, state, retry count, owner, and revisions. The implemented lifecycle guards the program states `draft`, `awaiting-approval`, `queued`, `running`, `waiting`, `retrying`, `succeeded`, `failed`, `cancelled`, and `interrupted`. The managed-work plane refuses a transition to `running` because only the future sandboxed executor may attest that state.

Run planning accepts a closed immutable manifest: provider and model identities, capability IDs, context IDs, opaque workspace and artifact handles, time/output/cost/network budgets, a mandatory sandbox requirement, and bounded step descriptions. It accepts no command, executable, argument vector, environment, home path, socket, or secret. A networked plan additionally requires an active, unexpired `managed.network` permission projection, but the plan still remains unavailable for execution. Step projections begin as `blocked-unavailable`, making the missing executor visible rather than manufacturing progress.

Queued plans can be cancelled or failed when prerequisites are unavailable. Failed and interrupted runs can produce a new queued retry linked to the immutable parent manifest; retry count and task revision update atomically. Stale revisions, cross-task parents, context scope escape, cross-principal access, and network-without-grant all fail closed.

## Automations

Automations store a closed task template, trigger, policy, state, revisions, the next due time, and the last reconciliation time. Supported triggers are bounded intervals, named events, and calendar schedules with an explicit IANA time zone, weekdays, wall time, and DST policy. Policies must declare missed-run behavior (`skip`, `run-once`, or `catch-up`), coalescing (`earliest`, `latest`, or `all`), maximum catch-up, concurrency, maximum concurrent work, retry limits and backoff, time/cost limits, and signed-out behavior.

Signed-out behavior is currently only `pause`; lingering is refused because no disclosed lingering executor is integrated. Clock rollback does not move a durable cursor backward or guess at due work. Signed-out reconciliation records the observation but retains the due cursor for the next signed-in reconciliation. Missed intervals are counted exactly, selected according to policy, and cursor advancement is transactional. Calendar scanning is bounded. Event identity is bound to its topic, timestamp, and normalized payload; replay is idempotent and conflicting reuse fails.

Trigger firings are `pending-unavailable`, `skipped`, or `cancelled`. A due schedule never creates a task or claims execution. Skipped policy writes a compact audited firing with its exact missed count. `run-once` selects the latest missed occurrence. Catch-up never exceeds its declared maximum. Firing history has a hard capacity; exhaustion leaves the due cursor unchanged.

## Agent Center projections

The module exposes a closed query for every destination in `shell/apps/ultimate-agent-center/routes-v1.json`:

| Destination | Managed-work projection |
|---|---|
| `agent.overview` | Active task, pending approval, enabled automation, unavailable firing, and live-context counts plus explicit execution readiness. |
| `agent.tasks` | Bounded task pages with the latest run and steps, plus principal-bound task/run entity lookup. |
| `agent.approvals` | Unexpired pending approval projections from the trust/operation authority. |
| `agent.automations` | Definitions, policies, durable cursors, and the five latest firings per automation. |
| `agent.activity` | Operation links, change state, recovery eligibility, artifact links, and principal-bound operation lookup. |
| `agent.history` | Bounded managed-work lifecycle events containing IDs and normalized non-secret summaries. |
| `agent.context` | Visible redacted context snapshots; session-scoped context from other endpoint sessions is omitted. |
| `agent.permissions` | Monotonic permission/grant projections. Persistent risk ceilings cannot be high. |
| `agent.usage` | Provider metrics, task/run attribution, token/cost-like quantities, and bounded aggregate cost. |
| `agent.providers` | An explicit unavailable managed-provider result until the central registry is connected; it does not duplicate or fake the registry. |
| `agent.artifacts` | Task-owned opaque handles, MIME type, size, hash, scope, and run provenance. No filesystem path is accepted. |
| `agent.troubleshooting` | Database health, restart recovery, owner-scoped counts, capacities, recovery actions, and execution readiness. |

Pagination cursors bind schema version, view, principal, and descending row identity. A cursor cannot be replayed into another view or principal. Page size is capped and the encoded response is capped at 512 KiB; an oversized response asks the caller for a smaller page rather than truncating a record. Entity lookup is allowed only on the route that owns that entity type. All top-level query fields and nested managed-work record envelopes are closed in `default/fabric/schema/managed-work-v0.json`.

## Provisional integration seam

The next integration owner should instantiate one `ManagedWorkPlane` beside the per-user Fabric database after resolving a private state path, then close it with the daemon. RPC methods must be added to the central protocol schema before registration; the module must not be exposed through a generic method dispatcher. The minimal read seam is one route-aware query method binding the endpoint-issued `principalId` and `sessionId` to an `Actor`. Caller-supplied actor labels must never be accepted.

Mutation seams should be capability-specific and preserve authority separation:

- Context capture receives content only from registered session/context providers after their source-specific privacy filter.
- The trust and operation stores publish monotonic approval, permission, and operation projections after committing authoritative state.
- Usage and artifact records arrive from an authenticated future managed executor over its task-scoped Fabric proxy, never from a general Agent Center client.
- Task and automation creation goes through future policy and approval checks before queueing consequential work.
- The managed executor attests sandbox/runtime readiness and owns transitions into running, progress, success, interruption, cancellation, and reconcile states. Until that typed seam exists, those transitions remain unavailable.
- Provider inventory is composed at query time from the central provider registry rather than persisted as a competing registry in managed work.

The schema remains `v0` and provisional. It can freeze only after the central RPC envelope, endpoint identity binding, sandbox lifecycle, operation authority, and real Agent Center client pass restart, corruption, actor-spoof, cancellation, provider-version drift, and packaged-machine tests together.
