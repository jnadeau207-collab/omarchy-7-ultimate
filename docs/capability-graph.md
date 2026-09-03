# Capability and parity graph

The provisional Ultimate capability graph is the checked inventory that connects semantic operations, current providers, visible human routes, agent availability, recovery requirements, product-parity jobs, and acceptance proof identifiers. It is deliberately honest about the current migration boundary: a provider can exist while its route remains legacy-direct, and a visible human operation can exist while the same semantic operation is unavailable to agents.

This is schema version `v0`, not a frozen public `v1` contract. The root-owned shared vocabulary is `default/fabric/schema/common-v0.json`; capability graph work may reference it but must not redefine or edit it.

## Files

| Path | Authority |
|------|-----------|
| `default/ultimate/capability-schema/contract-types-v0.json` | Shared provisional input, state, result, error, preflight, progress, and undo schema fragments. |
| `default/ultimate/capability-schema/catalog-v0.schema.json` | Required fields and allowed states for every capability descriptor. |
| `default/ultimate/capability-schema/window-surface-v0.schema.json` | Shape of the live WindowService and `window` IPC inventory. |
| `default/ultimate/capability-schema/legacy-debt-v0.schema.json` | Shape of the explicitly allowed migration-debt baseline. |
| `default/ultimate/capability-schema/parity-jobs-v0.schema.json` | Shape of the parity and Windows-native task graph. |
| `default/ultimate/capabilities/catalog-window-v0.json` | All 39 current public WindowService writers, including their broker status and semantic contracts. |
| `default/ultimate/capabilities/catalog-system-jobs-v0.json` | Product and system capabilities required by the parity matrix and forty-task manifest. Missing providers remain catalogued as missing so jobs never resolve to prose-only aspirations. |
| `default/ultimate/capabilities/catalog-provider-readers-v0.json` | Typed read-only inventory capabilities for every production builtin provider. Present providers keep honest human routes (visible or planned) and managed-agent routes remain unavailable. |
| `default/ultimate/capabilities/window-surface-v0.json` | Exact source-ordered inventory of 44 public WindowService methods and all 40 functions on the `window` IPC target. |
| `default/ultimate/capabilities/legacy-debt-v0.json` | Checked coverage for `legacy-direct`, `provider-missing`, and `agent-unavailable` states. |
| `default/ultimate/parity/jobs.json` | All 42 rows from `WINDOWS_7_ULTIMATE_PARITY.md` and all 40 numbered tasks from `WINDOWS_NATIVE_ACCEPTANCE.md`. |

## Current inventory

The checked inventory contains 137 capability descriptors. WindowService contributes 39 writers: 21 names are in the prototype `CapabilityBroker.windowVerbs` catalog and 18 remain public legacy-direct writers. Five additional public WindowService methods are readers, producing an exact 44-method service inventory. Twenty-two typed leaf providers add honest read-only inventory capabilities in builtin factory order; these providers do not make the corresponding managed-agent routes available.

The `window` IPC target has 40 functions. `ping` and `cycleSnapshot` are read-only, `invoke` and `undoLast` are broker gateways, and 36 dedicated or UI routes still bypass the generic broker path. The inventory records the target WindowService methods for each direct route, so a transport change cannot quietly alter the mutation surface.

The job graph contains 82 entries: 42 parity jobs and 40 Windows-native tasks. Each entry resolves to existing capability IDs and records the source status, normalized claim, human route, agent availability, recovery expectation, and proof identifiers. Missing product work maps to an honest missing or legacy capability rather than an unresolvable placeholder.

## Availability is not one boolean

Each descriptor separates three questions:

- `provider.state` records whether a typed provider is present, a real path exists only through legacy-direct plumbing, or the provider is missing.
- `availability.human` and `humanRoute` record whether a visible path is complete, partial, or missing and where a person is expected to find it.
- `availability.agent` records whether a managed agent can invoke the same semantic capability through the catalogued route. A shell command that an agent could happen to execute does not count.

`availability.claim` is the product claim. A `present` claim is rejected unless the provider is present, the human route is complete and visible, and both acceptance and parity proof IDs exist. A job-level `present` claim is additionally rejected when any mapped capability lacks a present provider or agent route.

## Effects, preflight, and recovery

Every descriptor classifies the operation as a reader, writer, or long-running operation and declares its effect tags, resource scope, consent, idempotency, concurrency, cancellation limit, redaction, and recovery contract. Every schema slot is explicit even when its value is the shared `notApplicable` schema.

Destructive or irreversible capabilities must declare a real preflight schema, consequential consent, state-fingerprint-guarded recovery, and a recovery mode other than none or provider-missing. Long-running capabilities must declare a progress schema. Agent-callable mutations must have a visible human route.

The descriptor is the required semantic contract, not proof that a legacy provider already implements every field. Availability and debt state carry that distinction until provider conversion and acceptance proof close it.

## Checked migration debt

`legacy-debt-v0.json` is an allowlist with semantic coverage, not a note file. Every debt entry names capability IDs and exact source surfaces. The checker requires all current provider-missing and agent-unavailable capabilities to be covered exactly, requires each legacy-direct provider to be covered, and requires every bypassing WindowService or IPC route to name a valid legacy-direct debt entry.

Debt states mean:

- `legacy-direct` — real behavior exists, but it bypasses the typed provider route or generic broker gateway.
- `provider-missing` — the product graph requires the capability, but no provider implements it.
- `agent-unavailable` — the capability is not available to managed agents through the semantic graph, regardless of whether a human, command, or panel path exists.

Removing a source mutation without removing its debt is rejected as stale debt. Adding a mutation without inventory and debt coverage is rejected as unregistered debt. Provider conversion reduces the manifest; it must not relabel debt as present without the route and proof changes that make the claim true.

## Validation

Run the hidden development command from an Omarchy checkout:

```bash
omarchy dev capability check
```

The command uses the runtime-invariant `python` interpreter and requires the planned `python-jsonschema` package. If that package is absent, validation exits with a dedicated dependency error; there is no reduced fallback validator.

`--root PATH` selects the source checkout. `--data-root PATH` validates an alternate capability/schema data tree against the selected checkout, which is used by deterministic corruption tests without duplicating or mutating the live source tree.

Validation covers JSON Schema conformance, embedded schema validity, broken schema and capability references, duplicate identifiers, destructive safeguards, long-running progress, false present claims, agent-only mutations, exact Markdown job coverage, exact public WindowService and broker inventories, exact `window` IPC inventory and target-method routing, and complete non-stale debt coverage.

`test/shell.d/capability-catalog-test.sh` proves the valid graph and generated broken cases for every rejection family. It also proves the dependency failure and prevents Python bytecode artifacts in the owned graph and test paths.

## Changing the graph

When adding or changing a capability, update its descriptor, all affected jobs, visible route, proof IDs, and debt coverage in the same coherent change. A new WindowService public method or `window` IPC function must also be added to `window-surface-v0.json`; the checker compares source order and direct target methods so an omitted or stale entry fails.

When converting a legacy capability, land the typed provider and shared human/agent route first, change provider and agent availability honestly, add the relevant proof IDs, then remove the exact legacy debt coverage. Do not add a second generic command runner, infer agent availability from shell access, or use a product status label as a substitute for executable proof.
