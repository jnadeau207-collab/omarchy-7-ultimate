# Fabric domain providers

The provisional Fabric domain-provider layer gives Display, Audio, Network, Bluetooth, Input, and Power one typed inventory path and one representative operation lifecycle each. It is a leaf layer: the central provider registry owns admission and read dispatch, while the durable operation coordinator owns authorization, approval, idempotency, cancellation, evidence, and recovery policy.

## Entry points

Each package exposes a code-owned factory. Registry wiring must import these exact paths from a hard-coded builtin list; provider or module names never come from RPC data.

- `omarchy_fabric.providers.display.build_provider`
- `omarchy_fabric.providers.audio.build_provider`
- `omarchy_fabric.providers.network.build_provider`
- `omarchy_fabric.providers.bluetooth.build_provider`
- `omarchy_fabric.providers.input.build_provider`
- `omarchy_fabric.providers.power.build_provider`

Every factory returns an object with deeply immutable `manifest` and `schemas` mappings plus asynchronous `read`, `preflight`, `apply`, `validate`, and `rollback` methods. The standalone schemas use JSON Schema Draft 2020-12, carry exact `$id` and `x-omarchy-version` values, close every object, bound every collection and string, and use no external references.

## Leaf contracts

| Provider | Read capability and action | Operation capability and action | Risk and effects | Real read-only probes |
| --- | --- | --- | --- | --- |
| `display.provider` | `display.inspect` / `inspect` | `display.configure` / `brightness.set` | low / `mutating` | `/usr/bin/hyprctl -j monitors all` |
| `audio.provider` | `audio.inspect` / `inspect` | `audio.volume.set` / `output-volume.set` | low / `mutating` | `/usr/bin/pactl --format=json list sinks`; `/usr/bin/pactl get-default-sink` |
| `network.provider` | `network.inspect` / `inspect` | `network.manage` / `wifi.set-enabled` | consequential / `mutating`, `network` | fixed `nmcli` general-radio and device-status queries |
| `bluetooth.provider` | `bluetooth.inspect` / `inspect` | `bluetooth.audio.pair` / `audio.pair` | consequential / `mutating`, `network` | fixed `bluetoothctl show` and device-state queries |
| `input.provider` | `input.inspect` / `inspect` | `input.keyboard-layout.set` / `keyboard-layout.set` | low / `mutating` | `/usr/bin/hyprctl -j devices` |
| `power.provider` | `power.inspect` / `inspect` | `power.profile.set` / `profile.set` | low / `mutating` | fixed power-profile, UPower source, and battery-status queries |

Read actions have `risk=read-only`, no effects, no preflight or state contract, and no rollback or cancellation. Operation actions require a non-null preflight and state contract, include `mutating`, support exact rollback, and do not claim cancellation because no leaf backend currently owns a cancellable process group.

## Identity and state

Native connector, sink, interface, MAC, and keyboard names are labels and probe-local selectors, never mutation arguments. Non-singleton resource IDs have the form `<domain>.<kind>.<sha256(domain + NUL + native-key)>`; the full lowercase digest makes the ID stable without exposing a command selector. The fixed singleton IDs are `network.radio.wifi` and `power.profile.current`.

Inventories are sorted by opaque resource ID before hashing or returning. Reordering a backend list and changing an ignored transient numeric index therefore do not change resource IDs or the inventory revision. Duplicate identities fail the whole snapshot closed. State fingerprints use `sha256.<64 lowercase hex>` over canonical finite JSON, and apply and rollback compare the exact expected fingerprint immediately before replacement.

## Availability and errors

Real backends run only absolute, code-owned, fixed argument vectors with `shell=False`, no stdin, a fixed C locale, a five-second deadline, and a 256 KiB combined output ceiling. JSON probes reject duplicate keys and non-finite numbers. Missing dependencies, timeouts, nonzero exits, malformed output, duplicate native identities, excessive inventories, and schema mismatches become bounded structured errors.

An inventory result always includes separate `availability.read` and `availability.operation` values plus a structured reason. Real `build_provider()` backends make trusted reads available but keep operations unavailable with `<domain>.operation-read-only`; their `replace` method always fails closed and cannot mutate the host. A provider whose probe cannot establish trusted state returns an empty, explicitly unavailable inventory rather than stale or guessed state.

## Durable-operation handoff

`preflight` accepts only a daemon-issued `EndpointPrincipal`, re-reads the current typed resource, normalizes the closed arguments, captures current and proposed state, and returns risk, effects, summary, recovery state, and the exact state revision. `apply` rejects state drift, writes once through its backend, and validates the returned state. `validate` detects post-apply drift. `rollback` requires the exact current revision and restores the exact prior state.

The production backends intentionally do not implement host mutation. Central integration must route an admitted action through the Fabric durable operation coordinator before substituting an authorized real mutation backend. The leaf interface does not replace central idempotency records, approval scope, event delivery, ledger evidence, cancellation policy, or daemon-restart reconciliation.

Network Wi-Fi connection is deliberately absent: credentials cannot enter generic JSON arguments or durable evidence. A future connection action requires a non-persisted secret handle or inherited file descriptor. Display scaling is also absent because the current helper selects the focused monitor at execution time and cannot honor an exact approved resource identity.

## Hermetic lifecycle backend

`build_fake_provider(resources, state_path=...)` exposes the same schemas and lifecycle methods without invoking a system command. The fake backend performs optimistic revision checks, supports deterministic snapshot and apply failures, writes atomically when a test supplies a state path, and reloads that bounded state after provider reconstruction. It exists for lifecycle and recovery verification; production registration uses `build_provider()`.

Focused coverage lives in `test/fabric/providers/test_leaf_providers.py` with provider-specific fixtures under `test/fabric/providers/fixtures/`. The suite admits every leaf through the central registry, exercises real-parser inventories without host mutation, proves fixed probe vectors and opaque IDs, and runs preflight, apply, validation, no-op replay, stale-state containment, exact rollback, deterministic failure, and restart recovery across all six domains.
