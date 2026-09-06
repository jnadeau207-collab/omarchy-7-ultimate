# Settings Service API Convention

Settings becomes a first-class application, and it must not be a pile of shell commands. This document defines the stable internal capability layer between shell UI, Agent Fabric, and the underlying Omarchy/system tooling.

```text
Human UI  ──┐
            │
Agent Fabric│  (runtime, broker, permissions, ledger, undo)
            │
            ▼
Capability services / API
 ├─ window          (WindowService — first real provider)
 ├─ display
 ├─ audio
 ├─ network
 ├─ bluetooth
 ├─ power
 ├─ package management
 ├─ updates
 ├─ firmware
 ├─ themes
 ├─ input
 ├─ accounts
 ├─ recovery
 └─ …same graph as WINDOWS_7_ULTIMATE_PARITY.md
            ▼
existing Omarchy / system tooling
```

## The rule

The UI and the agent ask:

```text
setDisplayScale(displayId, 1.25)
```

not:

```text
exec("sed -i ... && hyprctl ...")
```

Pixel scraping and assembling random shell strings are not the primary agent interface. Humans and agents share this graph: same validators, state transitions, errors, rollback, and audit (`PRODUCT_DOCTRINE.md` Rule 8).

## What this buys

- validation before anything executes
- testability without a graphical session
- rollback for every consequential operation
- permissions checks in one place
- consistent, human errors (see PRODUCT_DOCTRINE.md — never `Process exited with status 1`)
- compositor flexibility behind one window capability
- **agent control through the same typed APIs** — not a later bolt-on, not raw shell access, not a chat panel that types commands

## Service contract

Each capability domain is a QML singleton under `shell/services/` (or a broker-registered provider with the same shape):

- **Readers** return structured state (typed properties or JSON), never raw command output for UI formatting.
- **Writers** are intent-named verbs (`setBrightness`, `connectWifi`, `createRestorePoint`, `minimize`) that validate first and report a structured result: `{ changed: bool, error: { title, explanation, detail } }`.
- **Operations with consequences** expose preflight information (`what will change`, estimated duration, destructive flag) so UI and agents can honor the no-bullshit installation rule before starting.
- Services own process invocation; QML components never spawn shell commands directly.
- Agent calls hit the same writers. Do not add a parallel "agent shell" path.

## What exists today

- `shell/services/WindowService.qml` is the first real capability provider: pin/unpin, minimize/restore (`omarchy-minimize` `setHidden`), snap, maximize, activate, desktops, Show Desktop, layout save/restore, per-app reopen placement. UI and `omarchy-shell window …` IPC call those verbs via `Hyprland.dispatch`.
- Writers return `{ changed, error: { title, explanation, detail } }`. IPC serializes that object (`ping` stays `"ok"`). `CapabilityBroker` catalogs window verbs, permits local-session actors, appends `capability-ledger.json`, and `undoLast` for recorded invertibles.
- Display, audio, network, bluetooth, and power still live as Superbar/heritage **panels** that run `Process` / `execDetached` / `hyprctl` / `bash -c` (see `shell/plugins/panels/`). That heritage-panel path is not a claim that Settings writers are untyped, and it is not metal leftover for Superbar Power. Settings window durable typed writers are listed in the next bullet.
- `org.omarchy.Settings` hosts the image picker on Personalization. That hosted surface still runs `Process` / `execDetached` / `hyprctl` / `bash -c`. Wallpaper apply is tip-true `ImagePicker.applyEmbedded` → `omarchy-theme-bg-set` (set-only; recovery mode=none; no prior-wallpaper undo / no compensating fingerprint invent). Catalog `desktop.wallpaper.set` stays leftover `legacy-direct` / claim=partial with visible `Settings > Personalization`. session leftover recorded: soft leftover-attach ACC `windows-native.4` to tip-true Settings > Personalization wallpaper plane (not product CLOSED / not metal CLOSED / not claim=present); `windows-native.4` stays prototype/pending; Cloud mocks do not close windows-native.4; never claim=present; do not invent wallpaper product-complete from hex-grep. Display, Sound, Network, Bluetooth, Power, Input, Apps, Update, and Recovery read the existing Fabric `display.inspect` / `audio.inspect` / `network.inspect` / `bluetooth.inspect` / `power.inspect` / `input.inspect` / `defaults.inspect` / `update.inspect` / `recovery.inspect` inventories instead of embedding Process panels. Live typed writers are Sound volume, Network Wi-Fi radio, Display brightness, Default Programs default browser (http+https via `defaults.protocol.set` / `applyDefaultBrowser`), Default Programs default email, and Default Programs per-MIME defaults; they run through durable operations on those providers. session leftover recorded: soft leftover-attach ACC `windows-native.19` to tip-true Settings > Default Programs browser plane (not product CLOSED / not metal CLOSED / not claim=present); `windows-native.19` stays prototype/pending; Cloud mocks do not close windows-native.19; do not invent MIME association UI / AutoPlay / SPAD / `files.associations.set` product-complete. Output mute and default sink apply through this session's `omarchy-fabric-session-apply` `audio-output-mute-set` / `audio-output-default-set` path (`/usr/bin/pactl`, tip-true `audio.sink.*` identities). Settings does not invent an `audio.provider` mute or default-sink durable writer. Settings does not invent Fabric durable mute/default LIVE / claim=present. Soft leftover-attach of catalog `audio.output.manage` leftover `legacy-direct` / claim=partial with visible `Settings > Sound; Superbar > Quick Settings > Sound`. Audio troubleshoot restart applies through this session's `omarchy-fabric-session-apply` `audio-troubleshoot-restart` path (absolute tip-true `omarchy-restart-audio` FixedArgv). Settings does not invent a `troubleshooting.provider` or `audio.provider` troubleshoot durable writer. Soft leftover-attach of catalog `troubleshooting.audio.run` leftover `legacy-direct` / claim=partial with visible `Settings > Sound`. session leftover recorded: Settings Sound mute, default output, and audio restart session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present). Settings → Printers hosts this session's `omarchy-fabric-session-apply` `printer-status` / `printer-default-set` / `printer-pause` / `printer-resume` / `printer-test-page` path (absolute `/usr/bin/lpstat`, `/usr/bin/lpoptions`, `/usr/sbin/cupsdisable`, `/usr/sbin/cupsenable`, `/usr/bin/lp`; tip-true `printer.*` identities; credentialed URIs refused). Settings does not invent a `printers.provider` durable writer or Fabric SHELL LIVE queue mutation. Soft leftover-attach of catalog `printers.manage` leftover `legacy-direct` / claim=partial with visible `Settings > Printers`. session leftover recorded: Settings Printers inventory and queue session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present). Network Add / driver wizard remains OPEN leftover. `windows-native.32` stays pending. Cloud EXIT 0 is not metal leftover CLOSED. Cloud EXIT 0 is not metal leftover CLOSED. Port changes and the full troubleshoot wizard remain OPEN leftover. `windows-native.6` stays pending. `windows-native.39` stays prototype/pending. Settings Network also joins open or password-protected networks through this session's NetworkManager access; the passphrase never enters Fabric. That join is not a typed Fabric writer (`network.wifi.connect` stays leftover `legacy-direct`). Enterprise, VPN, and per-connection DNS stay unavailable. Settings Bluetooth pairs and connects through this session's BlueZ adapter; pairing secrets never enter Fabric. That pair path is not a typed Fabric writer (`bluetooth.audio.pair` stays leftover `legacy-direct`). Audio routing, PIN-entry UI, and adapter rfkill stay unavailable. Settings Update checks and installs through this session's `omarchy-fabric-session-apply` `system-update` path (`omarchy-update -y`); elevated auth never enters Fabric. That apply path is not a typed Fabric writer (`update.install` stays leftover `legacy-direct`). Fabric `system.update` stays inspect-only / not LIVE. Update history reads this session's Omarchy update transcript through `omarchy-fabric-session-apply` `system-update-history` (`SettingsSessionUpdate.qml` `readHistory`). Catalog `update.history.read` stays leftover `legacy-direct` / claim=partial with visible `Settings > Update`. session leftover recorded: soft leftover-attach ACC `windows-native.29` to tip-true Settings > Update history plane (not product CLOSED / not metal CLOSED / not claim=present); `windows-native.29` stays prototype/pending; Cloud mocks do not close windows-native.29; never claim=present. Restart and reboot writers stay unavailable. `windows-native.28` stays pending. Power profile stays inspect-only because polkit cannot authorize `org.freedesktop.UPower.PowerProfiles.switch-profile` from the fabric daemon under `app.slice`. The Superbar / Quick Settings Power leftover (`Panel.qml` Process/`omarchy-powerprofiles-set`, Hyprland `session.slice` child, not `session-N.scope`) was unverified on metal after PR #31; QS Power METAL_HEAD OPEN after metal FAIL on tip `20484de6` (pkcheck Not authorized / session-5103; !batteryPresent; amd_pstate EINVAL); KEEP OPEN; Settings Power LIVE refused; do not claim the heritage QS Power panel works on this metal. Open Settings pages re-read when shown and after local writers (`refreshWhenSurfaceVisible` / `refreshAfterSuccessfulWriter`); that close is surface-visible / local-writer only. Focused out-of-band stale inspect residual OPEN: hardware-key or other out-of-band mutations while Settings stays focused and already visible stay stale until F5 or Retry. Settings `authorityFooter()` names it. Fabric bus has no hardware-key resource-change topic; Settings allowlist forbids `events.*`. Do not invent a polling daemon or LIVE hardware-key subscription. Settings Apps lists and enables or disables XDG autostart through this session's `omarchy-fabric-session-apply` `apps-startup-list` / `apps-startup-set` path. Fabric `defaults.inspect` stays readable. Settings does not invent a Fabric `apps.startup.disable` durable writer. Catalog `apps.startup.disable` stays leftover `legacy-direct` / claim=partial with visible `Settings > Apps`. session leftover recorded: soft leftover-attach ACC `windows-native.27` to tip-true Settings > Apps startup plane via `SettingsSessionStartup.setEnabled` → `apps-startup-set` (not product CLOSED / not metal CLOSED / not claim=present); `windows-native.27` stays prototype/pending; Cloud mocks do not close windows-native.27; never claim=present. Settings does not invent Task Manager present. Night light uses the same NightlightService session/heritage plane as Superbar / Quick Settings; Settings Display hosts that control and does not invent a display.provider night-light durable writer. Settings does not invent Fabric durable night-light LIVE / claim=present. Catalog `display.night-light.set` humanRoute is visible `Settings > Display; Superbar > Quick Settings > Night light`. `windows-native.34` stays pending. Night light remains a Superbar leftover tile on that same NightlightService plane. Scale applies through this session's `omarchy-fabric-session-apply` `display-monitor-scale` path (`omarchy-hyprland-monitor-scaling` whitelist 1 / 1.25 / 1.6 / 2 / 3 / 4). Settings does not invent a display.provider scale durable writer. Settings does not invent Fabric durable scale LIVE / claim=present. Catalog `display.scale.set` stays leftover `legacy-direct` / claim=partial with visible `Settings > Display`. `windows-native.3` stays pending. session leftover recorded: Settings Display scaling session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present). Cloud EXIT 0 is not metal leftover CLOSED. HDR, arrangement, and multi-monitor policy stay unavailable. Other domains stay inspect-only or host the Personalization picker. Keyboard layout applies through tip-true `SettingsSessionKeyboardLayout.setLayout` → `input-keyboard-layout` (`/usr/bin/hyprctl switchxkblayout`, configured layout identities only). Settings does not invent an `input.provider` keyboard-layout durable writer. Settings does not invent Fabric durable keyboard-layout LIVE / claim=present. Catalog `input.keyboard-layout.set` stays leftover `legacy-direct` / claim=partial with visible `Settings > Input`. session leftover recorded: soft leftover-attach ACC `windows-native.33` to tip-true Settings > Input plane via `SettingsSessionKeyboardLayout.setLayout` → `input-keyboard-layout` (not product CLOSED / not metal CLOSED / not claim=present); `windows-native.33` stays prototype/pending; Cloud mocks do not close windows-native.33; never claim=present. Cloud EXIT 0 is not metal leftover CLOSED. Pointer, repeat rate, IME, and full locale/region stay unavailable. Layout alone is not locale complete. Input layout is the Settings Input session control when multiple layouts exist, plus honest empty and single-layout states. System information reads OS, product, hardware, and root storage through this session's `omarchy-fabric-session-apply` `system-information-inspect` path. Settings does not invent a `system-information.provider` durable writer. Settings does not invent Fabric durable `system.info.read` LIVE / claim=present. Catalog `system.info.read` stays leftover `legacy-direct` / claim=partial with visible `Settings > System information`. `windows-native.38` stays prototype/pending. session leftover recorded: Settings System information session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present). Cloud EXIT 0 is not metal leftover CLOSED. Agent Center bubblewrap `system.info.read` stays separate. Encryption, firmware flash, Device Manager, and storage mutation stay unavailable. Accessibility has no hostable panel. The overlay plugin launches this window instead of dismissing into floating panels.

## Placement

Domain services land in `shell/services/` as they ship (Window first; then Display, Audio, Network, Bluetooth, Power, Packages, Updates, Recovery). `WINDOWS_NATIVE_ACCEPTANCE.md` is the human smoke test. `WINDOWS_7_ULTIMATE_PARITY.md` is the job matrix. `AGENT_NATIVE_ACCEPTANCE.md` is the same-path agent matrix. Every job in those files must be satisfiable through services alone.
