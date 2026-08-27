# Agent Fabric

Agent Fabric is Omarchy Ultimate's durable, per-user control plane. The provisional foundation supplies a real owner-scoped daemon, a bounded versioned RPC transport, SQLite state, durable events, fake provider contracts, and diagnostics. It does not yet claim the security grants, operation ledger, managed-agent runtime, system executor, production provider discovery, QML bridge, or packaging integration assigned to later program owners.

## Authority boundary

`omarchy-fabricd` owns user-scoped Fabric transport and state. It listens only on `$XDG_RUNTIME_DIR/omarchy/fabric.sock`, creates its socket with mode `0600`, and requires Linux `SO_PEERCRED` to prove that every peer has the daemon owner's UID. A missing socket handle, unavailable credential facility, malformed credential record, or credential read failure is denied rather than treated as trusted. State lives at `${XDG_STATE_HOME:-~/.local/state}/omarchy/fabric/fabric.db`. The socket and state directories are mode `0700`; symbolic-link, wrong-owner, non-socket, and ambiguous stale-socket paths are refused.

Socket ownership identifies only the operating-system UID. It does not make a client a trusted UI, provider, agent, administrator, or undo authority. Endpoint-bound principals, grants, approvals, task-scoped proxies, secret handling, and sandbox boundaries are separate Trust Plane contracts and are not simulated here.

The daemon exposes no general process execution method. The provisional provider registry accepts only declarative `fake.*` or `test.*` providers with in-process `echo`, `constant`, `counter`, `delay-echo`, and structured `error` behavior. No request field is interpreted as an executable, helper path, command line, or shell string.

Provider implementations that eventually require a process must use a code-owned `FixedArgvCommand`: an absolute executable and immutable argument tuple established by provider code. Typed request values may enter through a validated stdin payload or another provider-owned channel, never by extending argv. `run_fixed_argv` always invokes the exact vector with `shell=False`; neither helper is reachable from provisional RPC.

## Transport contract

The socket carries one UTF-8 JSON object per newline. A frame may contain at most 65,536 bytes before its newline terminator. Invalid UTF-8, duplicate JSON object keys, non-finite numbers, non-object envelopes, and malformed JSON receive structured errors. Oversized and truncated frames are fatal to that connection; a malformed but bounded complete line does not poison the next line.

Every request contains exactly `protocol`, `id`, `method`, and `params`. `protocol` is `omarchy.fabric.rpc/v0`; `id` is a non-empty client-generated string no longer than 128 UTF-8 bytes and cannot be reused on the same connection. Responses echo the ID and contain exactly one `result` or structured `error`. Push events contain `protocol` and `event` but no request ID. The machine-readable envelope is `default/fabric/schema/rpc-v0.json`, which consumes the root-owned `common-v0.json` error and identity vocabulary.

The first request on each connection must be `hello`. The client declares an inclusive minimum and maximum integer protocol version; the daemon refuses ranges that do not overlap its supported range. The v0 methods are:

- `hello` — negotiate the protocol and create a connection identity.
- `version` — report protocol and readable database schema versions.
- `health` — report daemon, SQLite, socket, provider, and subscription health.
- `provider.register` — register an explicitly fake declarative provider, durably and idempotently when its definition is unchanged. Provisional v0 registrations are immutable; changing a registered version or definition is a conflict until a later provider-lifecycle contract defines safe replacement.
- `provider.list` — list registered fake providers and their named actions.
- `provider.invoke` — invoke a fake action with a required idempotency key and normalized JSON arguments.
- `events.subscribe` — subscribe to up to 32 named topics or `*`, with bounded durable replay.
- `events.unsubscribe` — remove a connection-owned subscription.

Unknown fields and unknown methods fail closed. A client reconnects with a new hello handshake. Reusing an invocation idempotency key with the same provider version, action, and normalized arguments replays the durable outcome; using it with different arguments is a conflict. A daemon restart marks a pending invocation interrupted, and a later retry reports unknown change state and requires reconciliation instead of guessing or running it again.

## Durable state and events

SQLite operates in WAL mode with `synchronous=FULL`, foreign keys enabled, and an owner-only database file. `PRAGMA user_version` and `schema_metadata` record the database contract. The daemon declares explicit minimum and maximum readable schema versions and refuses newer, too-old, unversioned non-empty, or corrupt databases without attempting a guessed repair.

Each schema migration runs in its own `BEGIN IMMEDIATE` transaction. Before migrating an existing supported database, Fabric creates an owner-only SQLite backup beside the database with a `pre-migrate` suffix. A failed migration rolls back its schema and version together.

Events receive a UUID, monotonic SQLite sequence, stable topic, finite-JSON payload, and creation time. Publication is durable before live fan-out. The default history retains 512 events; each subscription may replay at most 128 events, and each connection may own at most 32 live subscriptions. Replay envelopes are size-checked before the live subscription is installed, so an oversized reply cannot leak a server-side subscription. A cursor older than pruned history fails with `events.cursor-expired`, and a replay larger than the declared limit fails with `events.replay-limit`. Server and client live-event queues are both bounded. Server overflow produces an explicit `fabric.subscription-overflow` event and ends that subscription; client overflow closes the connection with `events.client-overflow`. Both paths require reconnect and durable replay rather than silently losing state or growing memory without bound.

## Diagnostics

The provisional commands remain hidden from normal Omarchy command listings until packaging and product routing are integrated:

```bash
omarchy-fabricctl health
omarchy-fabricctl doctor
omarchy-fabricctl --json health
```

`health` checks the live daemon through the same hello and RPC path as every other client. `doctor` additionally evaluates database integrity, WAL mode, and owner-only socket permissions. If the daemon is unavailable, diagnostics fail honestly and recommend restart or reconnect; they do not inspect a stale database and call it healthy.

## Service packaging boundary

`test/fabric/core/fixtures/omarchy-fabric.service` is a hermetic contract fixture for the eventual user service: fixed `/usr/bin/omarchy-fabricd` argv, systemd restart, an owner runtime directory, and a restrictive umask. It is intentionally not installed or enabled by this foundation. The packaging integrator owns the real unit, package dependency lock, existing-user enablement, migrations, and coordination with `omarchy-pkgs`.

## Verification

`test/shell.d/fabric-core-test.sh` runs the stdlib Python suite and static command/service/schema contracts. Coverage includes framing and malformed input, duplicate request IDs, fixed argv, hello/version negotiation, owner-only socket permissions, concurrent clients, fake provider registration and invocation, durable idempotency across reconnect and restart, bounded event replay, WAL and schema metadata, migration backup and rollback, future-schema and corrupt-database refusal, graceful shutdown, stale-socket recovery, and CLI health/doctor behavior.
