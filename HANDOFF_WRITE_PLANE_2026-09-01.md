# Write plane landed — 2026-09-01

SHA `3bd6f72f` on `work`. 23 of 23 shell gates and the 68-test operations suite pass. Metal is healthy, in tokyo-night, at 40 percent volume.

Settings can change this computer. That had never been true before.

## What existed and what did not

The mutation architecture was complete on paper and had never run. `operations/` held the coordinator, store, contracts, and executor protocol across 3,813 lines, and `daemon.py` referenced none of it. The only executor in the tree was `UnavailableProductionExecutor`, which reports `available = False` and raises `executor.production-unavailable` on every call, plus `FakeResourceExecutor` for tests. `reference_operation.py` is 2,212 wired lines bound to `REFERENCE_PROVIDER_ID = "fake.reference-settings"`; it proves the protocol against a fake and cannot touch hardware.

So every product surface read and never wrote, and the reason was a missing implementation, not missing wiring.

## The proven slice

Audio output volume, end to end through the socket:

```
operation.preflight -> provider preflight -> durable plan
operation.approve   -> approval record + capability grant
operation.start     -> coordinator -> session executor -> helper -> pactl
status: succeeded, sink 40 -> 55 -> 40
```

Pieces, each reusable:

- `operations/session_executor.py` — `SessionCommandExecutor` runs the intent catalog's fixed argv as this user with the validated payload on stdin. Keeps compare-and-set on resource revision, implements validate, rollback, reconcile. The state reader is async so it can read through the provider and hash the provider's own state value; anything else can never match the plan revision.
- `operations/session_apply.py` and `bin/omarchy-fabric-session-apply` — the code-owned helper. Fixed argv cannot carry a variable target and `pactl` reads no stdin, so one helper takes the typed payload, bounds it, and resolves the opaque `audio.sink.<sha256>` by recomputing the provider's stable id over the live sink list. A payload can never name an arbitrary device or command.
- `daemon.py` — builds the coordinator over the registry gateway, a durable store beside the fabric database, and one `OperationDefinition`. Serves `operation.preflight`, `approve`, `start`, `get`, `cancel`, `reconcile`, `ledger`. Mints a `CapabilityGrant` on approve and spends it on start. Construction is conditional on the helper existing and degrades to an unavailable method rather than taking the daemon down.
- `providers/_real.py` — `ReadOnlyProbeBackend` takes `session_operable`, default `False`. Audio is the only opt-in. The provider still never mutates: `replace` stays refused and the executor owns the change.
- Settings Sound carries the slider and calls the four operation steps; its allowlist is exactly two reads plus those four.

## Four dormant bugs this surfaced

None had ever executed.

1. Both gateway catalog reads pushed a float-bearing catalog through `normalize_json`, which rejects floats. Provider lifecycle verification could never have succeeded.
2. Every provider preflight emits `schemaVersion` and neither the coordinator field check nor the durable plan accepted it. Both bind it now, because a provider schema change is exactly the drift they exist to catch.
3. `ReadOnlyProbeBackend` reported operations unavailable for every domain.
4. No capability grant was ever minted, so `start` always failed `grant.missing`.

## Adding the next domain

For any provider built as `LeafProvider` plus `ReadOnlyProbeBackend` — `display` and `input` are, and were checked — the slice is mechanical:

1. Pass `session_operable=True` in that provider's `build_provider`.
2. Add an action branch to `session_apply.py`, selected by argv so request data still cannot choose a command, and give it its own `bin/` wrapper or argv suffix.
3. Add an `IntentDefinition` and an `OperationDefinition` in `daemon._build_operations`.
4. Add the control to that Settings page and extend the app's allowlist assertions.
5. Add the domain to `SESSION_OPERABLE_DOMAINS` in `test/fabric/providers/test_leaf_providers.py`.

`files` and `defaults` are **not** this pattern. They are `StateDomainProvider` and return `state` rather than `resources`; that is a separate integration, not enumeration.

## What this hardware cannot prove

- **Display brightness**: `ddcutil` is installed and `/dev/i2c-*` exist, but the user is not in the `i2c` group. Needs a group change.
- **Keyboard layout**: all three keyboards report a single `us` layout. `_propose` requires `switchable` with a second layout, so there is nothing to switch to until one is configured.
- **Packages, firmware, accounts, storage**: genuinely privileged. These need a root-owned executor service and a Polkit policy written and installed. `UnavailableProductionExecutor` is the correct answer for them until that exists.

## Do not reopen

Do not let a provider mutate. `replace` stays refused; the executor owns the change. Do not widen `session_operable` to a domain with no code-owned helper action. Do not put a privileged operation on the session executor. Do not restore the read-only wording on a page that now has a control.
