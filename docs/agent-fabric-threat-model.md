# Agent Fabric trust and sandbox model

This document defines the first enforceable trust-plane boundary for Agent Fabric. It covers endpoint identity, capability grants, consequential consent, approval binding, redaction, the typed system-executor seam, and managed-task sandbox construction. It does not claim that the Fabric daemon, root system executor, Polkit policies, task proxy, packaged agent runner, or plugin isolation are installed yet.

## Security objectives

The trust plane protects the user's desktop authority, durable Fabric records, secrets, privileged system state, and resources explicitly delegated to a managed task. Its invariants are:

- Peer credentials establish a Unix UID and nothing more. A caller cannot become the shell, a provider, a task, an undo actor, or an administrator by supplying an actor string.
- Endpoint roles come from daemon-owned admission and are bound to an opaque, expiring, revocable session credential. Every operation carries the bound principal and session identity.
- Policy denies by default. A grant names one principal, one capability, one exact resource identity, a maximum risk, explicit constraints, an expiry, and, for a managed agent, one task.
- The current shell principal receives no standing consequential or high-risk grant. Every consequential request from that whole principal requires fresh consent bound to one exact operation. High-risk requests from every principal require exact operation approval.
- High-risk grants are never persistent. The implementation rejects such a grant at construction, before it can enter policy storage.
- Approval binds principal, session, operation, capability, exact resource identity, normalized arguments, provider version, state revision, risk, task identity, and expiry. Provider, argument, target, or state drift invalidates approval and requires a new preflight and consent decision.
- Secrets do not enter ordinary arguments, argv, environment, logs, errors, or operation records. Redaction is recursive, supports explicit schema paths, scans common credential forms, and reports only finding type and location.
- Privileged execution accepts fixed typed verbs only. It accepts no command, shell, executable, argv, environment, helper, checkout path, or arbitrary filesystem path.
- Managed execution fails closed when bubblewrap or another required isolation primitive is unavailable. There is no unsandboxed fallback.

## Principal and session boundary

`SessionBindingStore` stores only a digest of the random session token. Resolution compares the token in constant time, verifies the peer UID, checks revocation and expiry, and returns an immutable `EndpointPrincipal`. Role metadata originates in an `EndpointAdmission` passed by daemon authority; it is not inferred from UID or parsed from an operation request.

The daemon must keep endpoint admission and the raw session token outside caller-controlled operation data. A provider endpoint is admitted with one provider identity. A managed-task endpoint is admitted with one task identity. The policy engine independently rejects a request whose principal, session, or task does not match that endpoint.

`hello` on `fabric.owner-rpc` always issues `PrincipalKind.SHELL`. It does not read a caller `kind` or `taskId`. A connection becomes `PrincipalKind.TASK` only when `TaskAdmissionAuthority` already holds a daemon-registered sandbox binding for that peer: the task socket inode, `SO_PEERCRED` pid and uid, the sandbox cgroup and unit, and the digest of a grant token the daemon placed only in that sandbox. Same-UID code that merely reaches a socket, including the owner socket, is not a task principal.

Unix socket ownership and `SO_PEERCRED` are still required at the transport seam. A mode-0600 user socket prevents other UIDs from connecting, but it does not distinguish two processes already running as the same UID. Task admission is what distinguishes the sandbox from the rest of that account.

## Honest same-UID and in-process QML boundary

This design does not pretend to defend a user from arbitrary malware already running with the same UID and unrestricted access to the user's process memory, files, session bus, or input devices. Same-UID malware may steal an endpoint token, manipulate an approval UI, read data the user can read, or attack the Fabric process. Session binding limits accidental and protocol-level actor spoofing; it is not a kernel isolation boundary between unrestricted same-UID processes.

Third-party QML currently executes inside `omarchy-shell` with access to the shared process and shell object. Therefore all current shell code, including installed third-party QML, is one principal. The trust plane cannot identify which QML component initiated a request and does not issue standing consequential or high-risk authority to that principal. Consequential shell-origin operations require consent for every operation. Same-process QML can still call direct in-process services that have not been migrated, so third-party plugin isolation or a declarative out-of-process widget host remains mandatory before the final Fabric security gate.

The consent surface must display the normalized operation and consequence summary from trusted Fabric state, not caller-provided prose. A compromised shell can still counterfeit pixels in its own windows; high-value authentication must use the dedicated Polkit flow and the system executor must independently validate the exact operation and current state.

## Grants, approvals, and decisions

Grants are positive, narrow statements rather than deny exceptions. There are no wildcard resource paths. Argument and context constraints use explicit dotted fields and allowed scalar values. Missing constraint data denies the request. Expired grants, resource changes, risk escalation, task mismatch, and constraint mismatch all produce structured denial codes.

The policy result is one of `allow`, `deny`, or `consent-required`, with stable code, explanation, operation identity, principal identity, and the matching grant or approval identity when applicable. It never returns the unredacted request.

Approvals live in authority-owned storage and are one-use. The correlation nonce links consent UI, user-Fabric audit, and root-executor audit. It is not a bearer credential and does not authorize privileged work. The root executor must validate the approval binding, current machine state, fixed action arguments, target identity, and dedicated Polkit authorization immediately before mutation.

## Privileged system execution

`security-system-executor-v0.json` and `validate_system_executor_request` define the provisional typed seam for package install/removal, system update, storage format, account deletion, firewall apply, firmware update, restore, and factory reset. Each verb maps to one dedicated Polkit action and a closed argument object. Targets are stable opaque identifiers; `/dev/sda`, a user-provided helper path, `bash -c`, an executable, argv, environment injection, and additional fields are rejected. Every trust-plane contract remains provisional in this foundation wave; none is frozen as a version-one public interface.

The interface is not the system executor. The future root-owned executor remains authoritative for its journal, state fingerprints, last-administrator and live-device safeguards, operation checkpoints, cancellation limits, validation, recovery, and cross-administrator visibility. User Fabric may propose and observe a system operation but never holds its only durable truth.

Repository privilege doctrine still applies outside this seam: an interactive heritage command with a visible password-capable terminal uses `sudo`; GUI and agent work cannot depend on a terminal prompt. Privileged GUI and managed-agent product paths must use the fixed system-executor verbs and dedicated Polkit actions, not a generic `pkexec` command launcher.

## Managed-task sandbox

The sandbox command builder always selects the packaged `/usr/lib/omarchy/fabric/agent-runner` and a fixed packaged bubblewrap path. Runner argv is a closed set of typed flags; task identity and a manifest file descriptor are mandatory. Prompts, secrets, shell snippets, executable selection, filesystem paths, and arbitrary environment do not travel in argv. Inputs use inherited file descriptors or explicit scoped binds.

The default bubblewrap profile uses a new session, unshares every namespace including network, clears the environment, supplies a minimal read-only runtime, creates private `/tmp` and `/home`, and exposes neither the session runtime directory nor general `/etc`. It does not expose the Wayland or X11 socket, session D-Bus, SSH agent, browser profiles, keyrings, general home directory, or main Fabric socket.

Host filesystem access is limited to explicit workspace and artifact roots mounted below `/workspace/<scope>` or `/artifacts/<scope>`. The builder resolves both source and declared source root, rejects sources outside the root, rejects any symlink component, rejects traversal and duplicate destinations, and blocks known credential, browser, keyring, and main-socket paths. A writable bind must therefore be both explicitly scoped and explicitly marked writable.

Managed tasks never share the host network namespace. Network-off is the default. An approved network scope uses a task-specific Unix proxy socket with explicit HTTPS host and port scopes; the sandbox still has no native host network. That proxy receives a task-scoped Fabric identity and must enforce the approved destination list, byte/time budgets, cancellation, DNS rebinding protection, response limits, and audit. It is not the main Fabric socket.

The sandbox is one layer, not an authorization decision. Capability policy, task-scoped proxy policy, provider validation, secret handling, resource budgets, systemd transient scope, and operation recovery remain mandatory outside bubblewrap.

## Verification

Hermetic unit tests under `test/fabric/security/` cover endpoint and actor spoofing, UID mismatch, session revocation and expiry, default denial, exact resources and constraints, task scope, expired grants, forbidden high-risk persistence, shell per-operation consent, approval replay and drift, executor verb and field injection, path-like target rejection, secret scans and redaction, schema closure, bind traversal, symlink and sensitive-source rejection, runner argv and environment injection, task-proxy scope, missing bubblewrap, and malformed profiles.

`test/acceptance.d/agent-sandbox-test.sh` is deliberately not a conditional skip. In the disposable VM it requires real bubblewrap, creates hostile ambient HOME and desktop-session variables, runs a real isolated process, proves the host network namespace differs, proves network access fails, proves home, Wayland, D-Bus, SSH agent, keyring/browser data, runtime directory, and main Fabric socket are absent, and proves only the explicit workspace and artifact mounts work. A missing or kernel-disabled bubblewrap is a failed managed-execution security gate.
