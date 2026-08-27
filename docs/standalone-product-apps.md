# Standalone product applications

Settings and Agent Center are ordinary taskbar-visible applications. They do not load into the long-running desktop shell process, receive a `shell` object, or load third-party shell plugins.

## Process and application identity

`shell/ultimate-settings.qml` and `shell/ultimate-agent-center.qml` are separate Quickshell entrypoints. Each entrypoint declares a stable `AppId`, `ShellId`, data directory, state directory, and cache directory. The launchers start distinct systemd user services named `omarchy-ultimate-settings` and `omarchy-ultimate-agent-center`; Quickshell's `-n` guard rejects a duplicate instance of either entrypoint. Closing or crashing one application therefore does not terminate the desktop shell or the other application.

The desktop entries are `applications/org.omarchy.Settings.desktop` and `applications/org.omarchy.AgentCenter.desktop`. Their filenames, `StartupWMClass` values, and Quickshell application IDs match exactly so compositor windows, task switching, taskbar identity, desktop actions, and deep links can join on one stable identity.

## Launch protocol

Both launchers normalize every invocation into `omarchy.product-launch/v1` before starting a process or calling IPC. A launch envelope contains exactly the application identity, registered route ID, typed non-secret route arguments, and invocation context. Invocation context can carry an exact output name, anchor rectangle, input seat, focus-restoration target, and source. Unknown fields, duplicate options, unknown routes, malformed links, unregistered arguments, secret-shaped free text, oversized identifiers, credentials in URI authorities, fragments, and ambiguous route-plus-link invocations are rejected.

The canonical route catalogs are:

- `shell/apps/ultimate-settings/routes-v1.json`
- `shell/apps/ultimate-agent-center/routes-v1.json`

`shell/apps/shared/normalize_launch.py` validates CLI and desktop-entry input against those catalogs. `shell/apps/shared/ProductProtocol.js` independently validates the catalog and normalized envelope inside the receiving application. The launcher uses the entrypoint-specific Quickshell IPC target, waits for the route catalog to become ready, and only treats the exact `ok` response as accepted.

Settings links use `omarchy-settings://<domain>/<page>` with only the typed query keys registered for that route. Agent Center entity links use `omarchy-agent://<task|run|operation|provider>/<non-secret-id>` and map to the matching application route with typed `entityType` and `entityId` arguments.

## Fabric boundary

The application host reuses the authority-free `shell/services/FabricClient.qml` transport. Settings connects as `omarchy-settings` and permits only `provider.catalog` and `provider.read`. Agent Center connects as `omarchy-agent-center` and permits only `provider.catalog` and `reference.operation.get`. Each process receives a separate daemon-issued endpoint session and exposes its client identity, endpoint principal ID, connection state, process ID, current route, and placement state through its own read-only IPC status method.

Presentation files contain no `Process`, `Quickshell.execDetached`, shell command, privileged operation, or provider mutation. Settings reads only the live typed provider catalog and the first registered read action for the selected domain. Agent Center reads only the live provider catalog and an explicitly deep-linked reference operation. Backend families that do not yet expose a query contract remain visibly unavailable; neither application invents placeholder tasks, operations, providers, resources, counts, or state.

## IPC targets

Settings registers `omarchy.settings`; Agent Center registers `omarchy.agent-center`. Both targets expose:

- `activate(envelopeJson)` to validate and apply one v1 launch envelope
- `status()` to return non-secret host, route, process, placement, and Fabric status
- `route()` to return the current route ID
- `processId()` to return the standalone Quickshell process ID
- `fabricClientIdentity()` and `fabricEndpointPrincipal()` to prove client separation

The launcher uses the exact entrypoint path when selecting a Quickshell IPC instance. It never sends an Agent Center route to Settings or a Settings route to Agent Center.
