# Agent Fabric packaging and lifecycle

Fabric currently ships through one immutable, version-locked Ultimate development package pair. `omarchy-dev` owns the fixed command entry points and depends on the exact full version and package release of `omarchy-settings-dev`, which owns `default/fabric/**` and `omarchy-fabric.service`. Both archives are built from the same pinned Ultimate Git commit. The `omarchy.fabric.package/v0` marker is checked before either daemon or diagnostic code imports the packaged Python modules. On the production `/usr/share/omarchy` path, the lifecycle check also requires the installed runtime and settings packages to have the same complete pacman version, including package release. A mixed package pair stops before it can open durable state and reports that both packages must be updated together.

The lifecycle verifier already recognizes the future stable names `omarchy` and `omarchy-settings`, but the upstream stable package definitions do not yet contain Ultimate Fabric assets and make no Fabric claim. Stable activation remains dormant until an Ultimate-sourced stable pair is cut from one immutable release revision and passes the same archive inspection. Development package releases never follow a moving branch tip.

The runtime package declares `python`, `python-jsonschema`, and `bubblewrap` as hard dependencies. Fabric never substitutes a partial JSON Schema implementation or an unsandboxed managed-agent path when either dependency is unavailable.

## User service boundary

`omarchy-fabric.service` is a systemd user service wanted by `graphical-session.target`. Waiting for that target is intentional: the UWSM session is the authoritative source of `OMARCHY_PATH`, and Fabric must not derive a checkout or package path from `HOME`. The service is `PartOf` the graphical session, runs with no privilege escalation, and launches the fixed `/usr/bin/omarchy-fabricd` argv without a shell.

Systemd creates `$XDG_RUNTIME_DIR/omarchy` and `${XDG_STATE_HOME:-~/.local/state}/omarchy/fabric` with mode `0700`; the service umask is `0077`. Before every start, `omarchy-fabric-service prepare-start` rejects symbolic-link, non-directory, or wrong-owner state and runtime paths, normalizes their modes, and verifies any database, WAL, shared-memory, pre-migration backup, or temporary backup artifact is a current-user-owned regular file with mode `0600`.

The daemon remains the sole schema migration authority. On a supported old schema it creates a `0600` SQLite backup before its transactional migration; migration failure rolls back the schema and retains that backup. Newer, too-old, unversioned non-empty, and corrupt databases fail closed. The packaging pre-start hook validates ownership and permissions but never guesses, edits, or bypasses database schema state.

## Lifecycle

Fresh users enable the service with the other shipped user units. Migration `1787794139.sh` uses the same lifecycle helper to enable existing users and starts it only when their graphical target is active. If their user manager is unavailable during an update, the helper writes only the exact package-unit wants symlink and defers startup to the next graphical login.

Pacman scriptlets do not impersonate logged-in users, reach into arbitrary home directories, or purge per-user state. Fabric lifecycle transitions run in the owning user session through first-run, the repository migration, the update restart phase, or an explicit `omarchy-fabric-service` command.

Every later `omarchy update` refreshes an enabled Fabric service. Refresh stops the old process before checking the new package marker and dependencies, so incompatible updated assets cannot leave stale code serving. A valid enabled service is started again only in an active graphical session. When no user manager and no runtime socket exist, refresh verifies the package and safely defers startup to the next graphical login. A package refusal leaves Fabric stopped and makes the update restart phase fail visibly; an unavailable manager with a remaining or unobservable socket reports the process state as unknown.

`omarchy-fabric-service uninstall` stops and disables the service and removes only an owner-validated stale socket after the user manager confirms the stop. If the manager is unavailable while a socket remains, uninstall removes next-login enablement but reports the live-process state as unknown and leaves the socket untouched. It deliberately preserves the database and all migration backups. There is no implicit purge operation; durable Fabric state may be removed only by a future explicit, separately confirmed data-reset workflow.
