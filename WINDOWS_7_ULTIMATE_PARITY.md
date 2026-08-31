# Windows 7 Ultimate Parity Matrix

Job completeness for Project Ultimate. Names are **jobs**, not a requirement to copy Microsoft's labels. A Windows 7 Ultimate user should recognize every row and complete it with a mouse.

This matrix is the product bar. `WINDOWS_NATIVE_ACCEPTANCE.md` is the forty-task smoke test (necessary, not sufficient; six numbered rows automated, plus unnumbered harness proofs). `AGENT_NATIVE_ACCEPTANCE.md` is the same jobs on the agent path.

Status (tree audited at `1334ba30` on 2026-08-26; metal windowing baseline HDMI-A-1 1920×1080):

- `missing` — no product surface for the job
- `plumbing` — Omarchy/system machinery exists; no consumer mouse path that hides the plumbing
- `prototype` — a Desktop Mode surface exists and is not job-complete
- `present` — a usable mouse path exists for the job (still not a quality claim)

Do not mark a row `present` because a panel or hotkey exists for power users.

## Desktop jobs

| Job | Status | Tree notes |
|-----|--------|------------|
| Desktop (icons, wallpaper, context menu, Recycle) | prototype | Wallpaper picker (`omarchy.image-picker`) exists. Desktop Mode shows real XDG Desktop icons (`omarchy.desktop-icons`, `desktopIcons` true). Computer.desktop launches Files This PC through the same `uwsm-app` / `OMARCHY_PATH` path as Start Computer. Recycle and a full desktop context menu are still Phase 6. |
| Superbar (taskbar) | prototype | `omarchy.ultimate-taskbar`: Start orb, stacked-window Task View mark, running groups, Show Desktop. Notification cluster from `barConfig` + `BarWidgetRegistry` (Desktop Mode overlay includes Quick Settings, Notification Center, agents, tray, and a two-line clock; does not rewrite `shell.json`). Peek captures a live grim thumbnail of each mapped window and keeps title-only rows for minimized or uncapturable clients. Right-click jump lists include desktop Actions plus pin/unpin and "Close group" / "Close window"; the Settings pin publishes Display, Sound, Network, Bluetooth, Power, Personalization, Apps, Input, Update, Recovery, and Accessibility. Group close still kills the entire group (`TaskButton.qml`). Peek × closes one. Superbar glass and hyprbars caption chrome read `Tokens.caption` / `Tokens.chrome` through the generated `chrome-tokens-v0.json` adapter. Multi-monitor policy: primary output owns the notification cluster; pins on every bar; secondary bars show running groups that own a window there; Start/Task View open on the clicked bar. |
| Start | prototype | `omarchy.ultimate-start` is a two-pane 720×640 Start: search, pinned, Recent from real launches, and letter-grouped All programs on the left; account plus iconed Files, Pictures, Computer, Settings, Agent Center, and power on the right. Idle list hides Terminal/Vim. Right-click reuses Superbar jump lists and pin/unpin; Files exposes This PC / Pictures / Recent / Trash once the product launcher is published. Pictures uses that action instead of `xdg-open`. The power flyout (Lock / Restart / Log off / Shut down) is an in-card menu so click-through cannot steal the caret. Outside-click and orb re-toggle: `e3bf9385`. Click-through (compositor delivers the outside click; no full-screen swallow): `6a548ba9` + `66805cdc`, proved by `start-dismiss-proof.py`. |
| Search | prototype | Start `SearchBox` filters installed apps plus existing Settings pages and Start places (Display, Sound, Network, Bluetooth, Power, Personalization, Apps, Input, Update, Recovery, Files, Pictures, Computer/This PC, Agent Center, Settings). Those hits reuse the published Settings/Files desktop Actions. Not file-content search. Accessibility is not invented as a toggle destination. |
| Explorer / This PC | prototype | `org.omarchy.Files` is a snappable product window with Home, This PC, Desktop, Documents, Downloads, Pictures, Recent, Search, Trash, and Network routes over `files.provider`. Start Computer uses the published This PC desktop action; Start Pictures uses the Pictures action. Pictures browse reports the location's own availability; an absent optional Trash does not paint Pictures DEGRADED. This PC reports the virtual this-pc location instead of inheriting workspace inspect degradation. Byte-bound eviction keeps a floor of Home/Desktop/Documents/Downloads/Pictures records instead of emptying Home. Workspace inspect / Files Home stays degraded (read-only inventory, optional truncation). Desktop Mode `SUPER + E` launches product Files (`default/hypr/bindings/desktop.lua`). This is not Dolphin and not a full Explorer; Power User `SUPER + SHIFT + F` still opens Nautilus. Recycle is Phase 6. |
| Network | prototype | Settings → Network reads Fabric `network.inspect` (Wi-Fi radio, interfaces, connection status). Typed Network writers remain Phase 5. Superbar still hosts the heritage `omarchy.network` panel. |
| Personalization | prototype | Settings → Personalization hosts the existing image picker for theme packs and wallpapers. Typed Personalization service is Phase 5. Superbar glass, Superbar tooltips, Start, and hyprbars captions read the same resolved `Tokens.chrome` / `Tokens.caption` payload; `omarchy-theme-set` republishes `chrome-tokens-v0.json` for dark and light packs. |
| Devices & Printers | missing / prototype | Settings → Bluetooth reads Fabric `bluetooth.inspect` (controller power, paired/connected devices). Typed pair/connect writers remain Phase 5. Superbar still hosts the heritage `omarchy.bluetooth` panel. Printer add is forty-task pending. |
| Device Manager | missing | |
| Programs and Features | missing | No Software Center; no Programs and Features. |
| Default Programs | prototype | Settings → Apps reads Fabric `defaults.inspect` (MIME/protocol associations and default applications). Typed default writers remain Phase 5. Forty-task "Change the default browser" is pending. |
| User Accounts | missing | |
| Credential Manager | missing | |
| Power Options | prototype | Settings → Power reads Fabric `power.inspect` (AC/battery source, active profile, available profiles, battery). Typed profile/sleep writers remain Phase 5. Superbar still hosts the heritage `omarchy.power` panel. |
| Sound | prototype | Settings → Sound reads Fabric `audio.inspect` (sinks, default, mute, channel volume). Typed Audio writers remain Phase 5. Superbar still hosts the heritage `omarchy.audio` panel. |
| Display | prototype | Settings → Display reads Fabric `display.inspect` (connector, mode, scale, position). Typed Display writers remain Phase 5. |
| Firewall | plumbing | `install/config/firewall.sh` / ufw on by default (`manual/35-networking.md`). No Firewall Settings surface. |
| Update | plumbing / prototype | Settings → Update reads Fabric `update.inspect` (available count, phase, checkpoint, reboot). Heritage `omarchy.system-update` widget; Superbar does not load it. Typed download/apply writers remain Phase 5. Forty-task rows 28–29 pending. |
| Backup & Restore | plumbing | Snapper via `omarchy-snapshot`. No Backup and Restore UI. |
| System Restore | plumbing | Settings → Recovery reads Fabric `recovery.inspect` (restore-point inventory). Same snapshot/rollback path. Typed restore writers remain Phase 5. Forty-task rows 30–31 pending. |
| Disk Management | missing | |
| Task Manager | missing as product | `btop` is the Activity TUI (`manual/21-tuis.md`). Not Task Manager. |
| Resource Monitor | missing | |
| Services | missing | |
| Task Scheduler | missing | |
| Event / history | prototype (toasts + window ledger) | Notification history directory + `showHistory` replay as toasts. Window capability calls append `capability-ledger.json`. Not Event Viewer. |
| Remote desktop | missing as product | |
| Drive encryption | missing as product | |
| Sharing | missing as product | Forty-task SMB row pending. |
| Language / locale | prototype | Heritage `omarchy.keyboard-layout`; Superbar cluster does not load it. Forty-task "Change keyboard layout" pending. |
| Accessibility | missing as product | Reduced motion called out in tokens; no Accessibility Settings. |
| File associations | missing as product | |
| Properties | missing as product | |
| Context menus | prototype | Superbar jump lists, Start pin/jump menus, and peek menus exist. Not "right-click everywhere" as the Windows API. Recycle and a full desktop context menu stay Phase 6. |

## 2026 layers

| Job | Status | Tree notes |
|-----|--------|------------|
| Software Center | missing | Phase 7 in the plan. Pacman/AUR/Flatpak are CLI/menu today. |
| Compatibility Center | missing | Phase 8. No "install one known-compatible .exe" path. |
| Snapshot recovery | plumbing | `omarchy-snapshot`, Limine snapper restore. Consumer "restore point" UI missing. |
| Modern display (scaling, HDR, night light) | prototype / plumbing | Monitor panel + `omarchy.nightlight` service. Forty-task scaling and night light pending. |
| Proton / gaming | missing | Steam install is forty-task pending; no Gaming / Proton surface. |
| Privacy | missing | Doctrine refuses telemetry; no Privacy Settings. |
| Agent Fabric | prototype (window) | See `AGENT_NATIVE_ACCEPTANCE.md`. WindowService + `CapabilityBroker` (results, permit, ledger, window undo). Settings Display, Sound, Network, Bluetooth, Power, Apps, Update, and Recovery read `display.inspect` / `audio.inspect` / `network.inspect` / `bluetooth.inspect` / `power.inspect` / `defaults.inspect` / `update.inspect` / `recovery.inspect`. Superbar still hosts audio/network/bluetooth/power panels. Typed writers remain Phase 5. |
| Agent Center | prototype | `org.omarchy.AgentCenter` is a snappable Superbar pin and Start destination. Overview reads owner-scoped managed-work counts from Fabric. Inspect tasks can be created, run, cancelled, and recovered for `system.info.read`. Context capture covers the five desktop sources. Consent and provider operations stay outside Agent Center. Usage stays one section. `omarchy.agents` remains a launch shim. |

## Caption / windowing (not a substitute for the jobs above)

Windowing Gate W0 is Phase 1 of `plans/project-ultimate.md` and is certified only by `W0_GATE.md` (Hyprland stays; three-button SSD, one-row CSD, min/max/restore, LTRB snap, Alt+Tab, Show Desktop, reopen memory, click-to-raise, Start click-through). The OS remains rejected because the product jobs above are incomplete. Founding execution authority is `PRODUCT_DOCTRINE.md` and `plans/project-ultimate.md`.
