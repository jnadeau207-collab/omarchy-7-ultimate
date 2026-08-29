# Phase 3 design-system close — 2026-08-29

Locked SHA: `119439b2971524b9502a85534f5db2a734954743` on `work`.

This is a design-system GO, not an OS ship. Windowing Gate W0 is already closed (`HANDOFF_PHASE12_W0_CLOSE_2026-08-29.md`, accepted tree `a7eb6dd1`). The product / OS is still REJECTED. AT-SPI value export remains blocked (`docs/accessibility-performance.md`); the gallery states that on metal.

## What closed

One resolver (`omarchy-theme-resolve-tokens`) publishes `design-tokens-v0.json` and `chrome-tokens-v0.json`. `omarchy-theme-set` publishes both after the theme swap. Superbar and Start read `Tokens.*`. hyprbars and Hyprland borders read the generated adapter and fail if it is missing or mode-mismatched. Consumer chrome no longer ships Nerd Font private-use glyphs.

## Metal proof on 192.168.1.171

Checkout fast-forwarded to `119439b2`. Hermetic suites that passed on the box: `design-token-contract-test.sh`, `design-system-consumer-test.sh`, `semantic-ui-contract-test.sh` including the live Quickshell QualityMatrix fixture, `osd-test.sh`, `power-test.sh`, `weather-test.sh`, `audio-test.sh`, `network-test.sh`.

`omarchy-theme-resolve-tokens --active` published tokyo-night as `omarchy.design-tokens.v0` dark with taskbar height 48. Theme-set `ultimate-dark` then `ultimate-light` then restore `tokyo-night` republished distinct adapters without Quickshell being the only publisher.

`omarchy-hyprland-monitor-apply --emit-lua` ranked `HDMI-A-1 1920x1080@60.00` and disabled DP-1/2/3. No `preferred`.

After reload, `hyprctl getoption general:col.active_border` / `inactive_border` were `ff45485b` / `ff2f3140`, matching the published adapter. `plugin:hyprbars:bar_color` was `0x9e1c1c1e`, matching `chrome.glass` for the restored tokyo-night payload.

Start summoned as a glass card with search, pins, app list, and unicode power controls. The quality-matrix gallery ran real OperationStatus / SemanticFixture controls, including compact/high-contrast/pseudo-locale. AT-SPI numeric export is still absent and is labeled as such.

## First metal failure and fix

`c40a6352` could not load the shell: `Tokens.qml` nested a `SemanticProfile` on a singleton `QtObject` (`Cannot assign to non-existent default property`). `119439b2` keeps Tokens childless; Start and Settings own the product profile.

## Do not reopen

Do not add a static `chrome-tokens-light.json` runtime fallback. Do not put children on the Tokens singleton. Do not treat JetBrainsMono Nerd Font as the typeface family as a Phase 3 miss; the ban is private-use salad in consumer chrome, which the consumer contract test now rejects.
