# Design tokens

Project Ultimate has one versioned semantic design-token contract. `bin/omarchy-theme-resolve-tokens` resolves an active or explicit `colors.toml`, zero or more `shell.toml` layers in precedence order, the compositor corner radius, and the checked-in v0 design defaults into `omarchy.design-tokens.v0`. The resolver is deterministic and Python-standard-library-only.

The schema is `default/ultimate/design-system/tokens-v0.schema.json`, the non-palette defaults are `default/ultimate/design-system/defaults-v0.json`, and the resolver implementation is `default/ultimate/design-system/resolve_tokens.py`. Density and large-text defaults live in that defaults contract alongside special product chrome colors; QML and Lua do not carry private copies.

The active outputs are:

- `~/.local/state/omarchy/current/design-tokens-v0.json` — canonical resolved payload consumed by `qs.Commons.Tokens`.
- `~/.local/state/omarchy/current/chrome-tokens-v0.json` — generated flat compatibility projection consumed by Desktop Mode's hyprbars Lua adapter.

`Tokens.qml` watches the active theme, the active theme name, the theme `shell.toml`, the machine-level `~/.config/omarchy/shell.toml`, and the compositor radius. It coalesces changes, runs the resolver with a fixed argv vector, loads only a complete compatible payload, and reloads Hyprland after a changed color projection so native caption chrome follows. A failed resolution reports the error and retains the prior in-memory and on-disk payload.

## Contract

The v0 payload covers all of the following groups:

| Group | Contract |
|---|---|
| `surface` | canvas, base, raised, glass, and overlay |
| `text` | primary, secondary, and disabled |
| `accent` | primary, hover, and pressed |
| `selection` | background and foreground |
| `state` | success, warning, danger, and info |
| `focus` | ring color, width, and offset |
| `border` | subtle and strong |
| `chrome` | Superbar glass/menu/interactions, glow, Start, and edge |
| `caption` | bar/text plus close, maximize, and minimize foreground/background roles |
| `typography` | family, pixel sizes, and weights |
| `icons` | family and pixel sizes |
| `hitTargets` | minimum, compact, comfortable, and touch targets |
| `density` | compact, comfortable, or touch mode plus resolved scale |
| `radii` | small, medium, and large |
| `elevation` | none, low, medium, and high |
| `effects` | blur and shadow enablement, dimensions, passes, color, and offsets |
| `motion` | fast, normal, and slow milliseconds, easing, and reduced state |
| `accessibility` | reduced motion, high contrast, large-text activation and scale, declared thresholds, and measured role contrast |
| `components` | shared control, row, panel, popup, field, taskbar, and caption metrics |

Color strings use lower-case Qt notation: opaque colors are `#rrggbb`, while translucent colors are `#aarrggbb`. Every dimensional field names its unit (`Px` or `Ms`) in the canonical JSON. Density scale is unitless.

`Tokens.radius` remains the compatibility spelling used by existing QML; `Tokens.radii` aliases the same object for new consumers. Existing `Tokens.surface`, `text`, `accent`, `border`, `state`, and `motion.fast`/`normal` bindings remain source-compatible.

## Resolution and overrides

Resolve explicit inputs without changing state:

```bash
omarchy-theme-resolve-tokens --colors /path/to/colors.toml --shell /path/to/theme-shell.toml --shell /path/to/user-shell.toml --corner-radius 6 --stdout
```

Publish explicit atomic outputs:

```bash
omarchy-theme-resolve-tokens --colors /path/to/colors.toml --output /tmp/design-tokens-v0.json --chrome-output /tmp/chrome-tokens-v0.json
```

Resolve and publish the active theme to the standard state paths:

```bash
omarchy-theme-resolve-tokens --active --corner-radius 6
```

Later `--shell` arguments win. Ordinary `[font]`, `[spacing]`, `[bar]`, and `[controls]` values feed the same typography, component, and focus calculations already used by `Color.qml` and `Style.qml`. Semantic overrides use hyphenated sections so the existing QML shell parser can safely recognize and ignore unfamiliar sections while the resolver maps them into the nested contract:

```toml
[tokens-density]
mode = "touch"
scale = 1.25

[tokens-accessibility]
reduced-motion = true
high-contrast = false
large-text = true
text-scale = 1.25

[tokens-focus]
ring = "accent"
ring-width = "2px"
ring-offset = 1

[tokens-chrome]
glow = "#e8943a"

[tokens-components]
taskbar-height = "52px"
```

Color overrides accept a canonical palette role or a Qt hex color. Pixel values accept a whole number or a quoted `px` value. Durations accept a whole number or a quoted `ms` value. Unknown `tokens-*` keys, unknown units, out-of-range values, malformed TOML, invalid colors, incompatible modes, and critical contrast failures are errors rather than ignored guesses.

The resolver records source SHA-256 digests without embedding machine-specific paths or timestamps. Identical inputs produce byte-identical JSON. It fully resolves and validates both payloads before staging either file, writes temporary files in the destination directory, fsyncs them, and replaces outputs atomically. Invalid input cannot overwrite the last known good output. Legacy themes with low-contrast muted text remain representable and expose their measured secondary-text ratio; primary text and caption controls always meet their enforced thresholds, while high-contrast mode additionally enforces secondary and selection contrast.

The optional `largeText` and `textScale` fields extend the existing v0 payload without invalidating a previously published v0 file. Newly resolved payloads always emit both fields; `Tokens.qml` supplies `false` and `1.0` defaults when reading an older payload. `text-scale` accepts `1` through `2` and only changes shared typography when `large-text` is active.

## Semantic UI profiles

`qs.Commons.SemanticProfile` is the opt-in presentation seam for shared QML controls. It combines density, display scale, high contrast, reduced motion, large text, text scale, locale stress, layout direction, and semantic palette roles without mutating the process-wide theme. Passing no `semanticProfile` retains each control's historical colors and geometry. Passing a profile activates density-aware spacing, the 28 px compact, 32 px comfortable, or 44 px touch target, profile typography, visible high-contrast focus, pseudo-localized copy, bidirectional layout where the container supports it, and zero-duration nonessential motion.

`qs.Commons.Semantics` owns the canonical operation vocabulary and profile-aware helpers. The vocabulary is success, no-op, progress, denial, failure, cancel, restart, and recovery. Every definition includes a text label, explanation, tone, non-color symbol, and primary action. `qs.Ui.OperationStatus`, `OperationDialog`, and `DestructiveDialog` render that vocabulary. The destructive dialog always initializes on Cancel and includes visible consequence and recovery copy.

The first shared controls exposing this seam are Button, IconButton, Card, Checkbox, RadioButton, Toggle, ToggleSwitch, TextField, ProgressBar, ProgressRing, Toast, EmptyState, ErrorState, OperationStatus, OperationDialog, and DestructiveDialog. Interactive controls declare an accessible name and role, and invoke the same signal from the attached press action as from pointer activation. The installed Qt runtime does not expose `Accessible.value`; determinate progress therefore publishes the percentage through `Accessible.description` and labels that fallback honestly until a native value interface is feasible.

## Compatibility chrome adapter

`default/ultimate/chrome-tokens.json`, `default/ultimate/chrome-tokens-light.json`, `themes/ultimate-dark/chrome-tokens.json`, and `themes/ultimate-light/chrome-tokens.json` are generated `omarchy.chrome-adapter.v0` projections. They are retained for one compatibility window so an older installed revision can still read a theme staged by a newer checkout. They are not token inputs and must remain byte-identical to resolver output for the matching Ultimate palette.

The locked dark projection remains 28/28/30 at 62% glass alpha, `#eeeeee` caption text, `#c42b1c` close, and `#c8c8c8` minimize/maximize. The locked light projection remains 232/236/240 at 78%, `#20262c` caption text, `#b85750` close, and `#5c6873` minimize/maximize. Superbar now binds to `Tokens.chrome`; hyprbars reads only the generated adapter and has no hard-coded color fallback. No Chromium frame geometry, compositor action, caption dimensions, or native plugin lifecycle changed in this token tranche.

## Verification

Run the hermetic contract suite:

```bash
./test/shell.d/design-token-contract-test.sh
```

It proves deterministic and idempotent output, exact dark/light compatibility projections, every contract group, all shipped themes, layered density and accessibility overrides including large text, reduced motion, units/ranges, contrast measurement, malformed-input errors, atomic last-known-good retention, and shared QML/Lua consumption.

Run the semantic UI contract suite with:

```bash
./test/shell.d/semantic-ui-contract-test.sh
```

It checks the exhaustive operation vocabulary, color-independent state metadata, 4.5:1 fixture text and state contrast, pointer and touch targets, reduced-motion durations, large-text scale, RTL edge mirroring, pseudo-localization placeholder safety, finite layout estimates, shared-control accessibility declarations, cancel-first destructive behavior, executable gallery composition, and a live Quickshell geometry fixture when a compositor is available.

Because the default dark and light projections are deliberately pixel-identical and this tranche changes no geometry, metal integration should use a fresh compositor process and the locked native-chrome campaign: activate Ultimate dark, capture Superbar plus Chrome fresh float, native maximize, three restore cycles, left/right snap, F11 enter/exit, and caption close/maximize/minimize hover; repeat the same states after activating Ultimate light. Inspect each full-resolution screenshot for the exact right and bottom pixels, caption controls, glass/text/edge colors, clipping, drift, focus, and stale dark/light state. Never hot-unload or hot-reload hyprbars. Preserve the Git SHA, resolver payload and adapter hashes, compositor log, screenshots, and inspection result in the candidate evidence bundle.
