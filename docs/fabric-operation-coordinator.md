# Fabric durable operation coordinator

The operation coordinator is the single provisional mutation path between a typed Fabric provider preflight and an executor. It generalizes the earlier hermetic reference operation without exposing a daemon route or admitting privileged host mutation. The foundation is deliberately broad enough to prove lifecycle, authority, durability, recovery, and executor invariants before a production system executor exists.

## Authority binding

An immutable `OperationPlan` binds all of the following before approval:

- the stable account owner derived from the daemon-verified peer UID, never a caller-owned actor or owner field;
- the originating daemon-issued principal, endpoint, active session, and optional task;
- the exact provider ID, semantic version, manifest/schema fingerprint, and lifecycle generation;
- the exact provider action, capability, risk, effects, normalized arguments, and complete typed preflight digest;
- the stable resource kind and opaque resource identity plus its preflight state revision;
- the current code-owned policy revision;
- a SHA-256 digest of the bounded idempotency key, while the key itself stays out of plans, events, errors, and projections;
- the code-owned executor intent ID, typed payload, immutable fixed-argv template fingerprint, and intent digest; and
- a lowercase UUID operation identity and timezone-aware creation time.

`OperationPlan.security_request()` places the owner, provider generation and fingerprint, policy revision, idempotency digest, preflight digest, normalized-argument digest, and executor-intent digest inside the existing `OperationRequest.arguments` binding. The plan's `bindingDigest` covers the complete canonical `OperationRequest.approval_payload()`, not only those extension arguments. `ApprovalAuthority` therefore signs and checks the principal, session, capability, resource, provider version, state revision, risk, operation, task, normalized arguments, and every coordinator extension as one exact envelope. `PolicyEngine` still decides deny, grant, or exact approval. The coordinator separately requires an approval even when a low-risk grant would otherwise be enough, because every call through this path is a mutation.

Approval and initial execution require the exact originating session. A different active session for the same UID cannot replay preflight, obtain approval for the frozen request, or start it. After a process restart has durably marked work interrupted, a replacement active session for the same stable owner may inspect, cancel, or explicitly reconcile it. A different UID cannot access the operation. A forged `EndpointPrincipal` fails through the daemon-owned `SessionBindingStore` resolver before owner comparison.

The current session, provider tuple, policy revision, latest resource intent, executor template, grants, and approval envelope are checked before approval presentation, before the durable approval checkpoint, and again immediately after that checkpoint before approval consumption. The executor independently performs resource-revision compare-and-swap immediately before mutation. This division matters: registry lifecycle validation prevents a known stale provider plan, while resource CAS closes the final state-drift window without pretending that a read-only registry catalog lookup is a global transaction.

## Durable journal

`OperationStore` uses a separate private SQLite database so this tranche does not change the shared Fabric database schema or daemon migration path. Its immediate directory is created mode `0700` and the database mode `0600` on Linux. The store holds no-follow directory and database descriptors for its lifetime, rejects a relative path, symlink, non-regular or multiply linked database, wrong ownership, and any directory or database inode swap. On Linux it snapshots matching descriptors before connect and requires SQLite to open exactly one new main-database descriptor for the held inode; every later use boundary proves that live descriptor and the exact `main` attachment again.

Opening an existing versioned database is read-only until trust closure completes. The store proves the live SQLite descriptor first, then checks the version, compares every table/index/trigger SQL definition and `table_xinfo`/`table_list` flag against an in-memory golden schema, rejects extra objects or changed columns, uniqueness, foreign keys, generated columns, collation/check SQL, `STRICT`, or `WITHOUT ROWID`, runs SQLite integrity checks, and verifies bounded plans, scalar indexes, approval relations, and event chains. Only after that closure does it configure the bounded timeout, trusted-schema setting, full synchronous commits, foreign keys, and require existing `DELETE` journal mode. A new empty database is created only after the same path, descriptor, version, emptiness, and integrity proof.

Rollback journals are held through no-follow descriptors and compared with both their directory entry and a live SQLite descriptor at transaction boundaries. WAL and shared-memory sidecars are rejected because this store requires `DELETE` mode. Boundary failure or any arbitrary durability-hook exception always rolls back an open transaction; if rollback or the post-rollback identity proof fails, the connection closes fail-safe. Close attempts the SQLite connection and every held descriptor even when an earlier close raises, clears all lease state, and then surfaces the first failure.

The immediate mode-0700 same-owner directory is the stated TOCTOU trust boundary. Arbitrary same-UID code that can replace files inside that directory is outside this storage boundary, as it is for the existing per-user Fabric database and session process. The held-inode checks still reject ordinary symlink, hard-link, and path-swap mistakes. A future privileged executor must use its own root-owned journal and must not treat this user-owned journal as its only truth.

Plans, events, and consumed approvals are insert-only. SQLite triggers reject updates and deletes. Each operation event has a monotonically increasing per-operation sequence and a SHA-256 chain over the operation, event type, checkpoint, status, canonical redacted payload, previous hash, and canonical UTC timestamp. Startup verifies bounded row counts, canonical plan JSON, every scalar-to-plan identity, plan and request digests, consumed-approval-to-event bindings and times, and every complete event chain before permitting a write. Semantic corruption fails closed even when SQLite `quick_check` reports structurally valid pages.

Capacity is explicit rather than silently lossy. The store admits at most a configured number of operations and events per operation, ledger reads are paged at at most 64 entries, event payloads are at most 16 KiB, and plans are at most 256 KiB. Exhaustion stops before a new plan, approval consumption, or later mutation checkpoint is reported. A disk-full or SQLite commit failure rolls back the transaction and returns structured `operation.storage-unavailable`; it never reports a checkpoint that did not durably commit. If the executor mutated before the failed checkpoint commit, restart sees the older running checkpoint and requires reconciliation.

The idempotency table is the immutable operation row itself, unique on stable owner plus the hashed key. An exact request fingerprint replays the original operation identity. Session, provider, resource, policy, argument, preflight, or intent drift conflicts instead of running again. A nonterminal operation exclusively owns its stable resource in the store. A later terminal operation may be followed by a new plan, but an old operation cannot reopen its terminal append-only state or roll back over the later resource revision.

## Checkpoints and recovery

The finite checkpoints are `preflight`, `approval`, `authorized`, `applying`, `applied`, `validating`, `rolling-back`, `reconciling`, and `finished`. The finite statuses are `awaiting-approval`, `authorized`, `running`, `interrupted`, `reconciling`, `rolling-back`, `succeeded`, `failed`, `cancelled`, and `superseded`.

Authorization follows a failure-safe order:

1. acquire bounded coordinator capacity so backpressure cannot consume approval;
2. resolve the exact active origin session, provider tuple, policy revision, latest resource intent, and executor template;
3. validate approval and policy without consumption;
4. durably append `approval-checked`;
5. recheck durable cancellation;
6. re-resolve the exact origin session, provider tuple, policy revision, latest resource intent, executor template, grants, and unconsumed approval;
7. consume the in-memory one-use approval; and
8. durably append `authorized` and its unique consumed-approval record before calling the executor.

A crash after approval consumption but before the authorized commit loses that approval and performs no mutation; the user must approve again. A crash after the authorized commit may reconcile from durable authority without replaying the approval. Approval loss is preferable to unauthorized mutation.

Apply, validate, rollback, and reconcile each have a bounded deadline. A structured pre-apply failure with `changeState=none` terminates without guessing. A timeout, unstructured executor exception, response loss, or explicit `changeState=unknown` enters reconciliation and never retries apply. Reconciliation has only three typed outcomes:

- `before`: no mutation is present, so the operation fails or completes cancellation without applying;
- `desired`: validate the exact observed desired state, or roll it back with exact revision CAS when cancellation is durable; or
- `diverged`: refuse rollback and require manual reconciliation because overwriting unknown or newer intent would be unsafe.

Validation failure rolls back only from the exact revision returned by apply. Rollback is then validated against the restored state. Rollback response loss, failure, or revision drift becomes a terminal failure with manual reconciliation evidence. Cancellation is durable at every checkpoint. Before apply it terminates without mutation; after apply it requests exact-CAS rollback; during rollback it cannot cancel the recovery action itself. Cancellation and lifecycle hooks never grant authority.

On startup, authorized, running, reconciling, and rolling-back operations receive one append-only `startup-interrupted` event. A cancelled coordinator task similarly records `runtime-interrupted` once whenever durable authority may already exist. Repeated recovery and cancellation-vs-terminal races are idempotent. Reconciliation never resumes apply blindly: it observes the resource through the executor, validates desired state when present, confirms before state without mutation, or stops on divergence. A replacement owner session may drive this explicit recovery, but it cannot start an awaiting operation. Coordinator concurrency and per-operation lock references are both bounded, and idle lock entries are removed so adversarial operation IDs cannot grow an unbounded lock map.

## Executor boundary

`IntentDefinition` contains one code-owned `FixedArgvCommand` and a closed set of typed stdin fields. The RPC or provider request cannot add an executable, command, argument, environment variable, helper, directory, or path. Only the intent ID, template fingerprint, and typed payload are durable; executable and argv strings are not exposed in the plan or evidence. On execution or restart, `IntentCatalog.resolve()` recomputes the template fingerprint and rejects code drift before use.

`FakeResourceExecutor` is hermetic and unprivileged. It never invokes its fixed command; it exists to prove resource CAS, postcondition validation, response-loss reconciliation, partial-state containment, rollback, supersession, cancellation, timeout, and evidence contracts. Every executor result and nested evidence value is normalized, deeply frozen, size bounded, secret checked, and semantically checked against the approved resource and expected revision before it can affect lifecycle decisions. A malformed executor `changeState` is treated as `unknown` and forces reconciliation rather than accepting the executor's claim. `UnavailableProductionExecutor` fails every method with `executor.production-unavailable`, and `OperationCoordinator.start()` checks that boundary before approval consumption. This tranche contains no generic subprocess execution and no live privileged mutation.

A future root-owned executor is an independent authority. It must accept only dedicated typed verbs, verify the exact user-Fabric approval and current state, enforce Polkit and system invariants, maintain a root-owned append-only journal, implement cross-administrator conflict handling, and return typed checkpoints. The user coordinator must never supply helper paths or argv and must never treat a correlation nonce as authorization.

## Evidence and schemas

Secret-shaped normalized arguments, preflights, and executor payloads are rejected before persistence. Preflight `observedAt` accepts only finite numeric telemetry and is discarded before the normalized snapshot is bound or persisted. Event evidence is recursively redacted. Structured executor errors omit arbitrary detail and unstructured exceptions record only their type, never `str(exception)`. Plans and public state omit the raw idempotency key and code-owned argv. Evidence sizes, counts, strings, registry catalog traversal, grants, lock references, and ledger pages are bounded.

`operation-coordinator-v0.json` closes the state and hash-chained ledger projections. `operation-executor-v0.json` closes the hermetic intent, apply result, and reconciliation result. Every object in both schemas declares `additionalProperties: false`; expansion requires a new contract revision. These schemas describe the current non-RPC foundation and do not advertise an installed daemon route.

Focused tests under `test/fabric/operations/` cover exact success, replay conflicts, provider and policy drift, wrong and replacement sessions, owner spoofing, revocation, approval replay, stale resource state, fixed-argv drift and injection, secrets, bounded redaction, unavailable production execution, crash and reboot checkpoints, disk full before and after mutation, partial apply, validation and rollback failures, newer intent, cancellation at every checkpoint, executor timeout, coordinator backpressure, event capacity and pagination, cross-instance idempotency, terminal immutability, corruption, directory/database/journal inode proofs, symlinks, hard links, close failures, permissions, offline CHECK/generated/STRICT schema tampering, and recursive schema closure.

## Integration seams intentionally not changed

This tranche does not register daemon RPC methods, alter `managed_work`, register providers, change product routes or QML, package a system service, install Polkit policy, or modify a provider family. `RegistryOperationGateway` consumes only the existing public `ProviderRegistry.preflight()` and `catalog()` contracts. Integration must later construct one coordinator from the daemon-owned session resolver, policy revision source, grants and approvals, code-owned operation definitions, private state path, and production executor proxy. Until that explicit integration lands, providers remain plan-only and the production executor remains unavailable.
