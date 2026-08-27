# Accessibility and performance baseline

The provisional `quality-v0` contracts under `default/ultimate/quality/` establish an honest starting line for accessibility, state coverage, reference hardware, performance budgets, and reliability incidents. They are release evidence, not declarations that unfinished surfaces pass.

## Accessible state gallery

The dev gallery includes a deterministic executable quality matrix. It renders all eight consequential-operation outcomes through the shared `OperationStatus` primitive: success, no-op, progress, denial, failure, cancel, restart, and recovery. Separate `SemanticFixture` instances mount the real shared Button, TextField, Checkbox, ToggleSwitch, and ProgressBar controls under opt-in profiles covering dark and light themes, compact, comfortable, and touch density, 1× through 2× scale, standard and high contrast, full and reduced motion, regular and large text, English, pseudo-localized, and long strings, left-to-right and right-to-left layout, and pointer and keyboard focus. This is pairwise presentation coverage rather than a misleading full Cartesian product, and the matrix contains no rectangle-only mock delegates.

The gallery fixtures attach semantic names, roles, descriptions, and actions. State is carried by a visible label and standard Unicode symbol as well as color. Automated checks enforce 4.5:1 normal-text contrast in both fixture palettes, a 24 px global pointer floor, a 44 px touch floor, finite layout estimates under long and pseudo-localized copy, zero-duration nonessential motion, placeholder-preserving pseudo-localization, actual RTL layout direction, and cancel-first destructive dialogs. The metal Qt `Accessible` attached type has no `value` property, so numeric state is carried in the accessible description as an explicit fallback while the required AT-SPI value interface remains blocked. The source contract records that distinction; it does not claim that the production shell or assistive-client path has passed.

Shared controls preserve their existing visual defaults until a caller passes `semanticProfile`. This keeps the tranche safe to land independently of product-surface rollout while allowing the gallery and runtime fixture to exercise the full system today. Central surface owners still need to pass profiles, define focus-modality ownership, and complete disposable-VM assistive-client proof before accessibility can be a release claim.

## AT-SPI feasibility

AT-SPI tooling is installed and the Python GI bridge initializes on the metal reference. A fresh `2026-08-27T00:13:56-04:00` traversal ran with the executable semantic gallery open. It exposed `xdg-desktop-portal-gtk`, `udiskie`, and `quickshell` applications, but all three reported zero children. The result is still blocked: the new QML name, role, description, and action attachments do not cross the Quickshell/Wayland export boundary into an assistive-client tree, and the shell still lacks a working numeric value interface. The shell, secure lock, and Polkit surfaces therefore have no assistive-client proof. Graphical OOBE is honestly recorded as missing because the current provisioning experience is terminal based.

`test/acceptance.d/ultimate-accessibility-performance-test.sh` is a disposable-VM release gate. Missing tools, missing surface records, missing semantics, blocked feasibility, and absent surfaces are failures, never skips. Do not run it in an active development session.

## Performance budgets and provenance

Every metric has a numeric provisional threshold and a typed observation. A measured observation includes its method and sample count. A blocked or unsupported observation has a null value and an explicit blocker, so a product target cannot be mistaken for fabricated measurement.

The current metal reference is an AMD Ryzen 7 5800X3D desktop with 64 GiB-class memory, an RTX 3070, and a Samsung 970 EVO Plus NVMe drive. Read-only evidence was collected over strict-host-key SSH. The failed first-paint sequence ran at 1920×1080@60. After the compositor incident, Hyprland restarted in safe mode at 3840×2160@30; only idle process, search-model, and IPC observations were collected in that state, and it is not treated as valid first-paint or animation evidence. Battery idle power is unsupported on this desktop. Actual animation presentation feedback is still blocked. Start, Settings, and Files first-paint measurements remain blocked until clean post-fix samples are captured in a disposable graphical VM; no failed-sequence partial result is reused.

## Resolved compositor reliability incident

At `2026-08-26 21:08:27.715503 -04:00`, a repeated Start and Settings surface-mapping measurement followed by a Files launch crashed Hyprland. The crash report says Hyprland received signal 11 (`SEGV`); the systemd coredump record is PID 58291 with `SIGABRT` at `2026-08-26 21:08:28 EDT`, reflecting the crash reporter's terminal abort. The portal coredump is PID 58816 with `SIGSEGV` at the same timestamp. The preserved report is `/home/jesse/.cache/hyprland/hyprlandCrashReport58291.txt`, SHA-256 `447edeb63352ef69ab550406043b5849d038653f849cffc495df7ff570080e2a`. Its signature crosses `omarchy-minimize.so` into Hyprland's resize path.

The root cause was a detached layout-target lifetime boundary. An `omarchy-minimize` idle restore could retain a mapped `CWindow` after Hyprland detached its layout target from `CSpace`; `dispatchCompositorBox` then called `Config::Actions::resize`, whose Hyprland 0.56.2 path dereferences `target->space()` without a null guard. Commits `c2822ff996900cd2fbb8344412666da2f05369b3` and `2863e6fc9602aa38c19566d2ebf5c88010c135c6` now fail closed unless the window, layout target, and target space are all live immediately before the synchronous compositor action.

The rebuilt plugin SHA-256 is `807757eadef905f9c0e1e04dff882fad02ae4d4741a8db96f5bc570c2224c856`. On metal, Hyprland PID 213829 survived the exact ten-cycle Start sequence, the exact ten-cycle Settings sequence, a Files launch, 30 adversarial maximize/restore/immediate-close cycles, and a Chromium campaign covering fresh float, maximize, three restores, left snap, fullscreen, and fullscreen exit. The newest crash report and coredump set did not change. Every Chromium state has a full-resolution screenshot hash in `reliability-incidents-v0.json`; the maximized client ended at output pixel 1919 and the full close glyph remained visible.

The exact triggering pre-fix iteration remains unknown and is not claimed. The bounded future repro stays restricted to a disposable VM, permits one mapping cycle per surface, records the compositor PID and coredump set before the first action, and aborts on any compositor PID change or new coredump before another surface is attempted. That policy preserves the incident as a regression gate even though the known defect is resolved.

## Commands

Run the static contract and gallery checker with:

```bash
omarchy-dev-quality-baseline check
```

Run the bounded surface probe only inside a disposable VM:

```bash
OMARCHY_QUALITY_DISPOSABLE_VM=1 omarchy-dev-quality-baseline probe-surfaces-once
```

The normal aggregate test runner does not execute graphical acceptance tests.

Run the hermetic semantic matrix contract with:

```bash
./test/shell.d/semantic-ui-contract-test.sh
```

When a reachable compositor and Quickshell are present, that test also instantiates the shared controls and operation/dialog primitives and verifies live implicit geometry, target sizes, reduced motion, placeholder safety, RTL logical edges, state coverage, and the destructive default. Without a compositor it still runs every pure contract and source-structure check and reports the runtime skip explicitly.
