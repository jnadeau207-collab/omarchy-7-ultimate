# Phase 4 desktop-shell close — 2026-08-29

Locked SHA: `c03b2cb4e1a337a68102205c76ef1464723f6b6a` on `work`.

This is a desktop-shell GO, not an OS ship. Windowing Gate W0 is already closed (`HANDOFF_PHASE12_W0_CLOSE_2026-08-29.md`, accepted tree `a7eb6dd1`). Phase 3 is already closed (`HANDOFF_PHASE3_2026-08-29.md`, locked tree `119439b2`). The product / OS is still REJECTED. `parity.agent-center` stays `claim: "missing"`; Agent Center is a read-only `managed-work.query` client.

## What closed

Phase 4 product core lives in the existing Superbar, Start, tray, clock, lock, notifications, and Agent Center hosts. Desktop Mode `layout.right` is Quick Settings, Notification Center, agents, tray, and clock. The five control panels stay hosted inside Quick Settings, not as Superbar icons. Agent Center is a shipped Superbar pin and a Start destination, launched as `org.omarchy.AgentCenter`, and snaps through the same WindowService verbs as any other toplevel.

## Metal proof on 192.168.1.171

Checkout fast-forwarded to `c03b2cb4`. HDMI-A-1 1920×1080. Shell ping after restart: `ok`.

Hermetic suites that passed for this close: `phase4-desktop-shell-test.sh`, `window-service-test.sh`, `mode-profile-test.sh`, `design-system-consumer-test.sh`, `notifications-test.sh`, `product-contracts-test.sh`, `ultimate-desktop-plugin-test.sh`, `plugins-test.sh`, `agent-center-product-test.sh`, `product-app-host-test.sh`, `capability-catalog-test.sh`.

Summoned and captured: Start (Files / Settings / Agent Center destinations), Quick Settings (nine live tiles), Notification Center (real Wayland Diagnose history plus Clear / Focus), Calendar (clock panel with a Calendar heading), lock preview (`20:21`, user `jesse`, `Enter Password`; `isLocked` stayed false and `hidePreview` restored the session).

Agent Center launched as `org.omarchy.AgentCenter`, then `omarchy-shell window snapLeft` settled at `[0, 32] [960, 1001]`. Overview showed Fabric connected and an honest managed-work contract failure (`result summary contract is invalid`), not mock counts. Routes on the sidebar include tasks, pending approvals, automations, activity, history, context, and Usage as one section.

Superbar right cluster is the plugin widgets, not the five panel icons. Notification Center badge showed live counts (10 / 18). A Chrome-attributed notification produced a red `1` on the Chrome task button.

Absolute-pointer proof on the live seat: Agent Center hover peek showed the app name, the running window, `Desktop 1`, and a close control. Agent Center right-click jump list showed `Open new window`, `Tasks & Runs`, `Pending Approvals`, `Automations`, unpin, and close.

## First metal failures and fixes

`1e882003` shipped the surfaces. Metal then showed three product-core holes, fixed on the locked tree:

- Quickshell `DesktopAction.command` is a length-list, not a JS `Array`. `b63c0596` reads that list and `execString` so jump-list actions are not dropped.
- `org.omarchy.agent` is a prefix of `org.omarchy.agentcenter`, and the Agent pin id is hyphenated (`org.omarchy.agent-center`). `4dca3dec` matches pins on token boundaries and on `desktopId`, and publishes `applications/org.omarchy.AgentCenter.desktop` into `~/.local/share/applications` so DesktopEntries can see the Actions.
- Superbar peek used `Array.isArray(group.windows)`, which is false for Quickshell window lists, so peeks rendered the label only. `c03b2cb4` reads length-lists.

## Honest leftovers

Agent and Agent Center still share `Icon=system-run`. Chrome's extra desktop actions did not appear on the jump list in this session; the generic Open new window / pin / close rows did. Fabric managed-work query is still invalid on this box; that is a Phase 2 leftover, not a Phase 4 chrome miss.

## Do not reopen

Do not add `ultimate-start-v2` or a second widget registry. Do not claim `parity.agent-center` present. Do not add Agent Center fabric mutations or register `OperationCoordinator`. Do not write `~/.config/omarchy/shell.json` or pin HDMI. Do not put children on the Tokens singleton. Do not merge `work` into `main`.
