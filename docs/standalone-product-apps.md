# Standalone product applications

Settings, Agent Center, Files, Software Center, and Compatibility Center are ordinary taskbar-visible applications. They do not load into the long-running desktop shell process, receive a `shell` object, or load third-party shell plugins.

## Process and application identity

Each application has a separate Quickshell entrypoint with a stable `AppId`, `ShellId`, data directory, state directory, cache directory, IPC target, Fabric client label, and systemd user service:

| Application | Entrypoint | AppId | ShellId and service | IPC target | Fabric label |
| --- | --- | --- | --- | --- | --- |
| Settings | `shell/ultimate-settings.qml` | `org.omarchy.Settings` | `omarchy-ultimate-settings` | `omarchy.settings` | `omarchy-settings` |
| Agent Center | `shell/ultimate-agent-center.qml` | `org.omarchy.AgentCenter` | `omarchy-ultimate-agent-center` | `omarchy.agent-center` | `omarchy-agent-center` |
| Files | `shell/ultimate-files.qml` | `org.omarchy.Files` | `omarchy-ultimate-files` | `omarchy.files` | `omarchy-files` |
| Software Center | `shell/ultimate-software.qml` | `org.omarchy.Software` | `omarchy-ultimate-software` | `omarchy.software` | `omarchy-software` |
| Compatibility Center | `shell/ultimate-compatibility.qml` | `org.omarchy.Compatibility` | `omarchy-ultimate-compatibility` | `omarchy.compatibility` | `omarchy-compatibility` |

Quickshell's `-n` guard rejects a duplicate instance of an entrypoint. Closing or crashing one application therefore does not terminate the desktop shell or another product application.

The corresponding desktop entries live under `applications/org.omarchy.<Product>.desktop`. Their filenames, `StartupWMClass` values, and Quickshell application IDs match exactly so compositor windows, task switching, taskbar identity, desktop actions, and deep links can join on one stable identity.

## Launch protocol

Every launcher normalizes its invocation into `omarchy.product-launch/v1` before starting a process or calling IPC. A launch envelope contains exactly the application identity, registered route ID, typed non-secret route arguments, and invocation context. Invocation context can carry an exact output name, anchor rectangle, input seat, focus-restoration target, and source. Unknown fields, duplicate options, unknown routes, malformed links, unregistered arguments, control-bearing or oversized text, oversized identifiers, credentials in URI authorities, fragments, and ambiguous route-plus-link invocations are rejected.

The canonical route catalogs are:

- `shell/apps/ultimate-settings/routes-v1.json`
- `shell/apps/ultimate-agent-center/routes-v1.json`
- `shell/apps/ultimate-files/routes-v1.json`
- `shell/apps/ultimate-software/routes-v1.json`
- `shell/apps/ultimate-compatibility/routes-v1.json`

`shell/apps/shared/normalize_launch.py` validates CLI and desktop-entry input against those catalogs. `shell/apps/shared/ProductProtocol.js` independently validates the catalog and normalized envelope inside the receiving application. The launcher uses the entrypoint-specific Quickshell IPC target, waits for the route catalog to become ready, and only treats the exact `ok` response as accepted.

Settings links use `omarchy-settings://<domain>/<page>` with only the typed query keys registered for that route. Agent Center entity links use `omarchy-agent://<task|run|operation|provider>/<non-secret-id>`. Files uses `omarchy-files://`, Software Center uses `omarchy-software://`, and Compatibility Center uses `omarchy-compatibility://`; their route and entity links map to typed arguments declared in the corresponding catalog. Search text is a bounded control-free route argument, while entity selectors remain stable non-secret identifiers.

## Fabric boundary

The application host reuses the authority-free `shell/services/FabricClient.qml` transport. Each process receives a separate daemon-issued endpoint session and exposes its client label, endpoint principal ID, connection state, process ID, current route, and placement state through its own read-only IPC status method. The daemon derives the durable `account.uid.<uid>` owner from authenticated Unix peer credentials and retains the `session.<uuid>` endpoint identity separately; no product label authenticates an owner or confers mutation authority.

The method allowlists are exact:

- Settings permits `provider.catalog` and `provider.read` for its registered Settings routes.
- Agent Center permits `managed-work.query` only. All twelve views, including a deep-linked operation in the activity view, resolve through the owner-scoped managed-work query contract; Agent Center has no `provider.catalog`, `provider.read`, or reference-operation RPC authority.
- Files permits `provider.catalog` and `provider.read` for `files.provider` inventory, browse, search, and recent actions.
- Software Center permits `provider.catalog` and `provider.read` for `packages.provider` catalog, inventory, adoption, and operation-history actions.
- Compatibility Center permits `provider.catalog` and `provider.read` for deployment inventory and an explicitly user-declared `route.decide` request. It does not infer or measure missing host inputs.

Presentation files contain no `Process`, `Quickshell.execDetached`, shell command, privileged operation, direct filesystem mutation, package-manager invocation, or provider mutation. The daemon binds every Agent Center managed-work query to the peer-derived account owner and current endpoint session. Task, run, automation, and context mutation and managed execution remain unavailable.

Files reads bounded metadata and never requests file contents. Create, rename, trash, restore, mount, and disconnect remain unavailable. Software Center preserves catalog assurance and provenance exactly: the checked-in `contract-seed` catalog and `declared` signatures are never presented as release verification, and install, remove, adopt, and recover remain unavailable. Compatibility Center shows provider readiness, persisted deployment evidence, canonical six-route decisions, recipe revision and assurance, host constraints, and explicit unsupported results. Its decision form labels host values as user-declared and unmeasured; deploy, remove, export, recipe execution, and VM provisioning remain unavailable. None of the three apps exposes `provider.preflight`, `provider.invoke`, or a direct mutation route before the durable coordinator and reviewed executors are integrated.

## IPC targets

Each application registers the IPC target listed above. Every target exposes:

- `activate(envelopeJson)` to validate and apply one v1 launch envelope
- `status()` to return non-secret host, route, process, placement, and Fabric status
- `route()` to return the current route ID
- `processId()` to return the standalone Quickshell process ID
- `fabricClientIdentity()` and `fabricEndpointPrincipal()` to prove client separation

The launcher uses the exact entrypoint path when selecting a Quickshell IPC instance. It never sends a route or activation envelope to a different product identity. After accepted activation, it focuses only the compositor window whose class or initial class equals the application's exact `AppId`.
