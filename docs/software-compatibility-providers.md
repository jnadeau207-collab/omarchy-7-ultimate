# Software Center and Compatibility Center providers

This foundation defines two code-owned Fabric providers that turn software acquisition and non-native application routing into typed, reviewable plans. Both are registered through the explicit production builtin list in `degraded` state because their checked-in inputs are contract seeds. Their read and preflight contracts are usable, but every production apply, validation, and rollback hook refuses execution until central durable authorization and externally attested release data exist.

## Software Center domain

`packages.provider` presents four read models and four mutation lifecycles:

- `catalog.search` reads a revision-pinned catalog across curated packages, signed repositories, Flatpak, reviewed AUR snapshots, reviewed AppImages, and reviewed web apps.
- `inventory.inspect` returns adopted and optionally unmanaged installations with stable identities and a canonical inventory revision.
- `adoption.inspect` classifies exact matches as managed or adoptable, digest mismatches as conflicts, and unknown packages as unmanaged.
- `operations.inspect` exposes bounded durable operation projections.
- `install`, `remove`, `adopt`, and `recover` produce typed preflight plans and implement the complete provider lifecycle hooks for a future durable coordinator.

Catalog admission is fail-closed and assurance is explicit. The checked-in catalog is labeled `contract-seed`; each entry carries the same assurance and uses `declared` signature status, so fake seed digests and key names cannot masquerade as release verification. A future `release-verified` catalog must use channel-appropriate verified or reviewed status and its exact canonical revision must also appear in code-owned release metadata supplied to `PackageCatalog`; a document cannot self-attest. Source trust classes, HTTPS origins, channel-specific package references, keys, digests, identities, installed paths, and installed logical resources are closed and bounded. A catalog revision mismatch, unknown source, duplicate identity, signature downgrade, artifact digest mismatch, noncanonical path, unsafe origin, self-asserted release status, or unrecognized trust vocabulary prevents use.

The hermetic package operation engine persists an atomic journal containing inventory and operation checkpoints. Each operation moves through `verify-provenance`, `stage-payload`, `apply`, `validate`, and `commit`. Because inventory revision is global, only one running or reconciliation-required mutation may own it at a time. The journal uses ordered operation sequences, a process-shared advisory write lock, compare-and-swap against the exact loaded file digest, atomic replacement, file and parent-directory `fsync`, closed nested-plan semantic validation, and bounded state. The engine enforces expected inventory and catalog revisions, idempotent request binding, cancellation checks both before and after every adapter checkpoint, explicit `none`/`complete`/`unknown` mutation state, restart interruption detection, supersession-safe rollback, and reconciliation. An exact installed item is a no-op, while a digest, version, state, or adoption mismatch is recovered instead of being falsely treated as satisfied. Tests use a controllable fake adapter; no package manager is executed.

Package adapters are fixed-argv declarations. RPC values remain in a typed input document and never enter the executable, argv, environment, or a shell. The declarations identify the intended future system helpers, including a few helpers that do not exist yet. They are integration contracts, not executable fallbacks.

## Compatibility Center domain

`compatibility.provider` makes an explicit decision among six routes in stable priority order:

1. native signed package;
2. browser-isolated PWA;
3. verified known-good recipe;
4. game Proton runtime;
5. isolated portable application;
6. Windows VM.

`route.decide` normalizes permission order and returns a deterministic decision identity and revision, every considered route in canonical order with an eligibility reason, the selected route and recipe when one exists, and an honest unsupported result when no safe route satisfies the workload. Unsupported decisions never silently degrade to another transport. Route eligibility requires a compatible workload/artifact pairing, canonical HTTPS origin, pinned digest for executable and portable artifacts, matching architecture, bounded route permissions, and the necessary runtime. Known-good recipes additionally enforce their declared runtime, minimum memory, minimum disk, artifact, architecture, permission ceiling, and workload constraints. Unknown anti-cheat may route only to the VM boundary under the checked-in policy; blocked or unsupported thinner routes remain ineligible.

Known-good recipes are closed assurance-labeled documents with a pinned artifact digest, exact architecture, maximum permission set, host requirements, lifecycle actions, export policy, removal data disposition, and a code-owned key identity. The checked-in recipes are explicitly `contract-seed` with `declared` status. A `release-verified` recipe inventory needs both a trusted key and an externally admitted exact revision. Recipe actions come from a phase-specific code-owned vocabulary, installation must verify the artifact first, and step identities are unique across the lifecycle; arbitrary command lines, shell fragments, executable paths, and environment variables have no recipe representation.

`deploy`, `remove`, and `export` produce preflight plans containing the exact decision, fixed adapter, lifecycle checkpoints, permissions, recovery state, data preservation or deletion plan, and deterministic export artifact identity. Removal and export bind display identity and permissions to the installed deployment rather than trusting replacement caller metadata, and export identity derives from installed state rather than a new routing request. The hermetic compatibility engine uses the same ordered, compare-and-swap, locked, synced, semantically validated journal discipline as the package engine. It protects expected deployment and recipe revisions, binds idempotency keys, serializes global deployment-revision ownership, detects cancellation even during the final checkpoint, blocks stale or superseded rollback, marks interrupted work for reconciliation after restart, and refuses to infer export completion from deployment inventory alone. It emits no host-side changes.

## Schemas and product data

Provider action contracts live in the two provider packages and are admitted by Fabric's existing closed manifest validator. The reusable product documents are validated by these standalone Draft 2020-12 schemas:

- `default/fabric/schema/packages-catalog-v0.json`
- `default/fabric/schema/packages-operation-v0.json`
- `default/fabric/schema/packages-source-policy-v0.json`
- `default/fabric/schema/compatibility-recipes-v0.json`
- `default/fabric/schema/compatibility-decision-v0.json`
- `default/fabric/schema/compatibility-routing-policy-v0.json`

The initial inputs live under `default/ultimate/software/` and `default/ultimate/compatibility/`. Their fake artifact digests and key names are deterministic `contract-seed` data for contract development, are surfaced as such in provider results, and are not production signing assertions.

## Integration seams

The remaining integration must stay centralized:

- bind apply, validation, rollback, cancellation, and reconciliation to the central durable operation coordinator rather than exposing a direct RPC mutation route;
- translate adapter plans into existing Omarchy helpers or add reviewed privileged helpers where the declared executable does not exist;
- publish checkpoint progress and operation projections through Fabric events;
- replace seed catalog digests and recipe key names with the package build and release signing pipeline, then inject the exact externally attested catalog and recipe revisions;
- populate Compatibility Center host inputs from measured runtime, memory, disk, architecture, isolation, browser, Proton, and virtualization state rather than caller guesses;
- connect Settings, Software Center, and Compatibility Center surfaces to the read and preflight contracts.

Production construction loads the catalog, source policy, recipes, and routing policy only from paths derived from the installed code root. It does not accept environment-selected roots or caller-selected files. Builder or admission failure is isolated as an unavailable placeholder under the expected provider ID, without copying the failed provider's capabilities or leaking exception text.

Until the remaining seams are complete, the implementation is intentionally a broad typed backend foundation with hermetic execution. It does not claim that host package mutation, recipe execution, VM provisioning, or UI flows are live.
