# Product invocation, identity, search, and process contracts

The manifests under `default/ultimate/product-contracts/` are the provisional v0 convergence contract for monitor-aware surface invocation, application identity, deep links, normalized search, and process/mutation ownership. They inventory what the current tree actually does and reserve the shape that product applications and Fabric clients must converge on. They do not claim a frozen v1 protocol or mark missing applications and providers complete.

Run the checked inventory with:

```bash
OMARCHY_PATH="$PWD" omarchy-dev-product-contract-check --root "$PWD"
```

The checker requires the packaged `python-jsonschema` dependency. Missing schema support is a hard, named error; validation never falls back to a partial home-grown schema reader. `--contracts-dir PATH` validates a copied manifest set against the real source tree and exists for corruption and review fixtures.

## Inventory boundary

The v0 inventory covers:

- all 43 first-party plugin manifests under `shell/plugins/`, including adjacent bar-widget manifests;
- all 25 plugin identities that the current `shell summon`, `shell toggle`, and `shell hide` lifecycle can open;
- all 22 live Quickshell IPC targets and every method declared by their handlers, including the inherited `omarchy.audio` panel target;
- all 18 shipped first-party application launchers under `applications/`, `default/alacritty/`, and `default/applications/`;
- both external application identities shipped as default taskbar pins: Chrome and Files/Nautilus;
- the standalone Settings and Agent Center identities, endpoint principals, application processes, desktop launchers, deep links, and owner IPC targets;
- the three current search implementations (Start applications, Run applications/command fallback, and menu-tree search) plus the five required but absent Settings, Desktop, Files, Software, and Agent Center sources;
- every QML or JavaScript path under `shell/plugins/` and `shell/services/` that currently declares `Process`, calls `execDetached`, or dispatches directly to Hyprland.

Discovery is part of validation. Adding a plugin manifest, invocable surface, IPC endpoint/method, first-party launcher, search consumer, or QML process site without updating the inventory fails the focused suite. Removing an implementation without removing or downgrading its claim also fails.

## Surface invocation envelope

Every eventual product invocation carries one typed envelope with these fields:

- `invocationId`: one stable request identity for tracing, idempotency, and a typed response;
- `screen.logicalId`: the live compositor screen identity selected by the invoker;
- `screen.connector`: the physical connector name used to survive logical-id churn;
- `screen.edidHash`: a privacy-conscious stable display identity used when a monitor moves connectors;
- `anchorRect`: the invoking control or pointer rectangle in global logical coordinates;
- `seatId`: the pointer/keyboard seat responsible for the request;
- `route`: a stable product route, not a display label or source-file name;
- `focusRestoration`: the stable window/surface target and explicit restore, transfer, or no-restore policy.

Monitor resolution is deterministic: exact live logical screen plus connector/EDID, then the same EDID on its current connector, then the same connector when EDID is unavailable, and only then an explicit primary-screen fallback. The anchor is clamped to that screen's work area. A reopened surface keeps its previous owner only while the owner still matches the current invocation; otherwise it resolves the invoking screen again and records the fallback.

Focus restoration distinguishes ordinary dismissal, click-through, launching a new target, deliberate focus transfer, and disappearance of the captured target. Start's current active-window capture and proven click-through are recorded as partial, not promoted to the common contract. Other current routes remain component-specific legacy behavior.

The existing `shell` target accepts only plugin id plus opaque payload JSON. Bar-panel routing selects the first loaded matching widget instance, and loader surfaces have no caller-provided monitor, anchor, seat, or focus target. Every current route therefore remains `present-legacy`; the manifests contain the complete desired contract profile, but no current route claims to implement it.

## Application identity and deep links

An application contract id is the join key for desktop entries, compositor windows, icons, pins, recent items, notifications, badges, progress, jump lists, installed records, operations, and agent tasks. Display text and list position are never identity.

The join order is explicit packaged alias, exact desktop entry id, exact declared StartupWMClass or Wayland app id, launch activation token, and notification/installed-record identity. Ambiguous or previously unseen identifiers are quarantined for resolution; substring matching is not an identity authority.

Each application record reserves a stable per-application principal, declares current process/principal binding, lists exact desktop and compositor identifiers, records taskbar visibility and shipped-pin state, and describes single-instance activation and deep links. Current launcher records are `legacy-unjoined` because `WindowModel.js` lowercases and substring-matches compositor ids, with a special Chromium branch. The stable contract principals are therefore reserved identifiers, not claims that current windows are already authenticated as those principals.

Settings and Agent Center are present as separately launched, ordinary taskbar applications. Settings owns `process.omarchy-ultimate-settings`, reserves `principal.app.ultimate-settings`, declares `org.omarchy.Settings`, and implements the `omarchy-settings://<domain>/<page>?<typed-query>` route shape. Agent Center owns `process.omarchy-agent-center`, reserves `principal.app.agent-center`, declares `org.omarchy.AgentCenter`, and implements the `omarchy-agent://<task|run|operation|provider>/<stable-id>` route shape. Each process has a separate read-only Fabric endpoint session and a typed single-instance activation target. The current daemon nevertheless admits all same-user clients through the shared `principal.fabric.owner-rpc` role; the caller-supplied client label is not product authority. Both this missing product-principal binding and the owner-socket-only, caller-unbound Quickshell activation IPC remain explicit debts with no mutation authority.

Their legacy shell plugin surfaces remain useful human launch shims. The application records remain `legacy-unjoined`, rather than falsely claiming `present-contract`, until taskbar identity stops using the shared heuristic application join.

## Normalized search

One result shape serves Start, Settings, Desktop, Files, Software, and Agent Center. Every result contains stable `id`, `source`, `provenance`, `title`, `subtitle`, `icon`, typed primary `action`, `secondaryActions`, `trust`, `destructive`, product `route`, and local `rank` metadata.

Providers identify their version, source record, capture revision, and whether the result is local, installed, indexed, or remote. Consumers apply a deterministic tie-break order. A remote or web result cannot replace an exact local application, route, setting, file, capability, or task match.

A mutating result is ineligible for normalized search unless it references at least one registered capability id and at least one visible human route. Trust, destructive state, preflight, and recovery metadata remain part of the typed action. The checker rejects an eligible mutating result without either authority link.

Current Start, Run, and menu search are recorded as `legacy-outside-contract`. Run's arbitrary command fallback and the menu's command-backed mutations are explicitly excluded from normalized search eligibility. Settings, Desktop, Files, Software, and Agent Center search providers are recorded as absent.

## Process and mutation ownership

The current shell is one `quickshell` process and one shared principal. Every first-party plugin and enabled third-party QML module executes inside it. A plugin or consumer component therefore cannot claim independent process ownership or receive standing consequential authority merely because it has a separate source directory or IPC target.

The process manifest separates:

- an operating-system process and its authenticated principal;
- a logical provider that owns validation and fixed process invocation for one capability domain;
- a consumer UI that asks a provider for a typed operation;
- the current direct-execution debt where consumer or combined UI/model QML still owns commands.

The checker discovers 37 current process-invocation source paths. Each has a mutation class, logical process role, capability references where a typed provider exists, visible human routes, and explicit debt. A `consumer-ui` entry with `claimsProcessOwnership: true` is always rejected. `WindowService.qml` is the sole current entry marked `typed-provider`; its listed capabilities are checked against the capability graph. The other direct invocation sites remain legacy until domain providers absorb validation, execution, operation state, errors, cancellation, and recovery.

## IPC inventory

`ipc-v0.json` is a source-checked inventory, not a new authorization boundary. It records the host targets `shell`, `window`, and `image-selector`; service targets such as `background`, `lock`, `notifications`, `idle`, `media`, `nightlight`, and `osd`; and plugin targets such as `omarchy.audio`, `omarchy.network`, and `omarchy.clock`.

The checker parses balanced `IpcHandler` blocks, resolves `root.ipcTarget` from the owning panel, and records the generic methods inherited by the audio panel. A new target or method fails until inventoried. All current endpoints remain `legacy-owner-socket-only`: target and method select code but do not establish an endpoint-bound product principal, route provenance, monitor/focus context, or approval scope.

## Checked legacy debt

`legacy-debt-v0.json` keeps unsupported behavior visible. The current ten groups cover missing invocation context, first-bar-instance monitor selection, component-specific focus, heuristic application joins, unbound product principals, private search result shapes, untyped search mutations, direct QML process execution, the shared shell principal, and caller-unbound IPC.

Debt is not a waiver for new work. Present-contract claims require real source and evidence; legacy and partial records require an open debt id; absent providers cannot name live implementation paths. Removing debt requires satisfying its exit condition and landing the corresponding runtime and acceptance proof in the owning workstream.

## Files

- `surfaces-v0.json` inventories every first-party plugin and its host/process relationship.
- `invocations-v0.json` defines the complete context contract and records every current summon/toggle/hide route against monitor and focus semantics.
- `ipc-v0.json` inventories live IPC targets and methods.
- `applications-v0.json` defines identity normalization and inventories launcher, taskbar-pin, and standalone product-app identities.
- `search-v0.json` defines the normalized result/action contract and inventories current and absent providers.
- `processes-v0.json` defines principals/processes and inventories every current QML process invocation site.
- `legacy-debt-v0.json` records the unsupported baseline and objective exit conditions.
- `schema/*.schema.json` are Draft 2020-12 schemas enforced through `python-jsonschema`.
