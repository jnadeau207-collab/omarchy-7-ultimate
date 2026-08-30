#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command python3

resolver="$ROOT/bin/omarchy-theme-resolve-tokens"
schema="$ROOT/default/ultimate/design-system/tokens-v0.schema.json"
defaults="$ROOT/default/ultimate/design-system/defaults-v0.json"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

export OMARCHY_PATH="$ROOT"

[[ -x $resolver ]] || fail "semantic token resolver is executable"
grep -Fq '# omarchy:hidden=true' "$resolver" || fail "semantic token resolver is hidden internal plumbing"
python3 -m json.tool "$schema" >/dev/null || fail "semantic token schema is valid JSON"
python3 -m json.tool "$defaults" >/dev/null || fail "semantic token defaults are valid JSON"
python3 - "$defaults" <<'PY'
import json
import sys

defaults = json.load(open(sys.argv[1], encoding="utf-8"))
assert defaults["accessibility"] == {"largeText": False, "textScale": 1.25}
PY
pass "semantic token contract sources are valid and routed as hidden plumbing"

dark="$tmpdir/dark.json"
dark_adapter="$tmpdir/dark-chrome.json"
light="$tmpdir/light.json"
light_adapter="$tmpdir/light-chrome.json"

dark_status=$(
  "$resolver" --colors "$ROOT/themes/ultimate-dark/colors.toml" --corner-radius 0 \
    --output "$dark" --chrome-output "$dark_adapter"
) || fail "ultimate-dark semantic tokens resolve"
[[ $dark_status == "changed" ]] || fail "first semantic token publication reports changed"

dark_hash=$(sha256sum "$dark" | cut -d' ' -f1)
adapter_hash=$(sha256sum "$dark_adapter" | cut -d' ' -f1)
dark_status=$(
  "$resolver" --colors "$ROOT/themes/ultimate-dark/colors.toml" --corner-radius 0 \
    --output "$dark" --chrome-output "$dark_adapter"
) || fail "ultimate-dark semantic tokens resolve twice"
[[ $dark_status == "unchanged" ]] || fail "identical semantic token publication reports unchanged"
[[ $(sha256sum "$dark" | cut -d' ' -f1) == "$dark_hash" ]] || fail "resolved payload is deterministic"
[[ $(sha256sum "$dark_adapter" | cut -d' ' -f1) == "$adapter_hash" ]] || fail "chrome adapter is deterministic"
pass "semantic token publication is deterministic and idempotent"

active_home="$tmpdir/active-home"
mkdir -p "$active_home/.local/state/omarchy/current/theme" "$active_home/.config/omarchy"
cp "$ROOT/themes/ultimate-light/colors.toml" "$active_home/.local/state/omarchy/current/theme/colors.toml"
printf '%s\n' '[font]' 'base-size = 14' >"$active_home/.config/omarchy/shell.toml"
HOME="$active_home" "$resolver" --active --corner-radius 3 --stdout >"$tmpdir/active-stdout.json" \
  || fail "active theme resolves to stdout"
[[ ! -e $active_home/.local/state/omarchy/current/design-tokens-v0.json ]] \
  || fail "active --stdout is read-only unless an output is explicit"
HOME="$active_home" "$resolver" --active --corner-radius 3 >/dev/null \
  || fail "active theme publishes to standard state paths"
[[ -f $active_home/.local/state/omarchy/current/design-tokens-v0.json ]] \
  || fail "active resolver publishes canonical payload"
[[ -f $active_home/.local/state/omarchy/current/chrome-tokens-v0.json ]] \
  || fail "active resolver publishes generated chrome adapter"
cmp -s "$tmpdir/active-stdout.json" "$active_home/.local/state/omarchy/current/design-tokens-v0.json" \
  || fail "active stdout and published payload are identical"
pass "active resolution is read-only on stdout and atomically publishes both standard outputs otherwise"

"$resolver" --colors "$ROOT/themes/ultimate-light/colors.toml" --corner-radius 0 \
  --output "$light" --chrome-output "$light_adapter" >/dev/null \
  || fail "ultimate-light semantic tokens resolve"

cmp -s "$dark_adapter" "$ROOT/default/ultimate/chrome-tokens.json" \
  || fail "dark default chrome adapter is generated from the canonical payload"
cmp -s "$dark_adapter" "$ROOT/themes/ultimate-dark/chrome-tokens.json" \
  || fail "ultimate-dark compatibility adapter matches the canonical payload"
cmp -s "$light_adapter" "$ROOT/default/ultimate/chrome-tokens-light.json" \
  || fail "light default chrome adapter is generated from the canonical payload"
cmp -s "$light_adapter" "$ROOT/themes/ultimate-light/chrome-tokens.json" \
  || fail "ultimate-light compatibility adapter matches the canonical payload"
pass "all four legacy chrome files are exact generated compatibility projections"

python3 - "$dark" "$light" "$schema" <<'PY' || exit 1
import json
import sys

dark = json.load(open(sys.argv[1], encoding="utf-8"))
light = json.load(open(sys.argv[2], encoding="utf-8"))
schema = json.load(open(sys.argv[3], encoding="utf-8"))

groups = {
    "surface", "text", "accent", "selection", "state", "focus", "border", "chrome", "caption",
    "typography", "icons", "hitTargets", "density", "radii", "elevation", "effects", "motion",
    "accessibility", "components",
}
for payload in (dark, light):
    assert payload["schemaVersion"] == "omarchy.design-tokens.v0"
    assert groups <= payload.keys()
    assert payload["density"] == {"mode": "comfortable", "scale": 1.0}
    assert payload["motion"]["fastMs"] == 100
    assert payload["motion"]["normalMs"] == 200
    assert payload["components"]["taskbarHeight"] == 48
    assert payload["components"]["captionHeight"] == 32
    assert payload["accessibility"]["largeText"] is False
    assert payload["accessibility"]["textScale"] == 1.0
    assert payload["accessibility"]["contrast"]["primaryText"] >= 4.5

assert dark["chrome"] == {
    "glass": "#9e1c1c1e", "menu": "#e01c1c1e", "hover": "#1affffff", "active": "#29ffffff",
    "pressed": "#38ffffff", "glow": "#e8943a", "start": "#9cbc0d", "edge": "#55ffffff",
}
assert dark["caption"]["close"] == {"background": "#c42b1c", "foreground": "#ffffff"}
assert dark["caption"]["maximize"] == {"background": "#c8c8c8", "foreground": "#1a1a1a"}
assert light["chrome"]["glass"] == "#c7e8ecf0"
assert light["caption"]["close"] == {"background": "#b85750", "foreground": "#ffffff"}
assert light["caption"]["maximize"] == {"background": "#5c6873", "foreground": "#ffffff"}
assert schema["properties"]["schemaVersion"]["const"] == "omarchy.design-tokens.v0"
print("ok - resolved dark/light payloads cover every contract group and retain locked chrome values")
PY

theme_count=0
for colors in "$ROOT"/themes/*/colors.toml; do
  "$resolver" --colors "$colors" --stdout >/dev/null \
    || fail "every existing theme resolves through the semantic contract" "$colors"
  (( theme_count += 1 ))
done
(( theme_count > 0 )) || fail "theme contract test found themes"
pass "all $theme_count existing themes resolve without a private chrome palette"

cat >"$tmpdir/theme-shell.toml" <<'TOML'
[font]
base-size = 15

[spacing]
scale = 1.25
scale-with-font = false

[tokens-density]
mode = "touch"
scale = 1.25

[tokens-accessibility]
reduced-motion = true
large-text = true
text-scale = 1.4

[tokens-chrome]
glow = "#123456"

[tokens-radii]
small = "5px"
medium = 9
large = 13

[tokens-components]
taskbar-height = "64px"
TOML

cat >"$tmpdir/user-shell.toml" <<'TOML'
[font]
base-size = 18

[tokens-chrome]
glow = "#654321"
TOML

custom="$tmpdir/custom.json"
"$resolver" --colors "$ROOT/themes/ultimate-dark/colors.toml" \
  --shell "$tmpdir/theme-shell.toml" --shell "$tmpdir/user-shell.toml" \
  --corner-radius 7 --output "$custom" >/dev/null \
  || fail "shell token overrides resolve"

python3 - "$custom" <<'PY' || exit 1
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["typography"]["sizesPx"]["body"] == 18
assert payload["components"]["controlGap"] == 10
assert payload["components"]["taskbarHeight"] == 64
assert payload["density"] == {"mode": "touch", "scale": 1.25}
assert payload["motion"]["reduced"] is True
assert payload["motion"]["fastMs"] == payload["motion"]["normalMs"] == payload["motion"]["slowMs"] == 0
assert payload["accessibility"]["largeText"] is True
assert payload["accessibility"]["textScale"] == 1.4
assert payload["chrome"]["glow"] == "#654321"
assert payload["radii"] == {"small": 5, "medium": 9, "large": 13}
print("ok - layered shell overrides resolve typography, density, accessibility, radii, color, and component metrics")
PY

sentinel="$tmpdir/last-known-good.json"
sentinel_adapter="$tmpdir/last-known-good-chrome.json"
"$resolver" --colors "$ROOT/themes/ultimate-dark/colors.toml" \
  --output "$sentinel" --chrome-output "$sentinel_adapter" >/dev/null \
  || fail "last-known-good fixture resolves"
sentinel_hash=$(sha256sum "$sentinel" | cut -d' ' -f1)
sentinel_adapter_hash=$(sha256sum "$sentinel_adapter" | cut -d' ' -f1)

printf '%s\n' 'mode = "dark"' 'background = "broken"' >"$tmpdir/bad-colors.toml"
if "$resolver" --colors "$tmpdir/bad-colors.toml" \
  --output "$sentinel" --chrome-output "$sentinel_adapter" >"$tmpdir/stdout" 2>"$tmpdir/stderr"; then
  fail "malformed colors fail honestly"
fi
grep -Fq 'must be #rrggbb or Qt #aarrggbb' "$tmpdir/stderr" \
  || fail "malformed color error is actionable"
[[ $(sha256sum "$sentinel" | cut -d' ' -f1) == "$sentinel_hash" ]] \
  || fail "malformed colors retain the last known good payload"
[[ $(sha256sum "$sentinel_adapter" | cut -d' ' -f1) == "$sentinel_adapter_hash" ]] \
  || fail "malformed colors retain the last known good adapter"

cat >"$tmpdir/bad-shell.toml" <<'TOML'
[tokens-focus]
ring-width = "2rem"
TOML
if "$resolver" --colors "$ROOT/themes/ultimate-dark/colors.toml" --shell "$tmpdir/bad-shell.toml" \
  --output "$sentinel" --chrome-output "$sentinel_adapter" >/dev/null 2>"$tmpdir/stderr"; then
  fail "invalid token units fail honestly"
fi
grep -Fq 'must be a number' "$tmpdir/stderr" || fail "invalid unit error is actionable"

cat >"$tmpdir/low-contrast.toml" <<'TOML'
[tokens-text]
primary = "background"
TOML
if "$resolver" --colors "$ROOT/themes/ultimate-dark/colors.toml" --shell "$tmpdir/low-contrast.toml" \
  --output "$sentinel" --chrome-output "$sentinel_adapter" >/dev/null 2>"$tmpdir/stderr"; then
  fail "invalid primary text contrast fails honestly"
fi
grep -Fq 'primaryText contrast' "$tmpdir/stderr" || fail "contrast failure reports its measured role"

if find "$tmpdir" -maxdepth 1 -name '.*.tmp' -print -quit | grep -q .; then
  fail "atomic publication leaves no temporary debris"
fi
[[ $(sha256sum "$sentinel" | cut -d' ' -f1) == "$sentinel_hash" ]] \
  || fail "all invalid inputs retain the last known good payload"
[[ $(sha256sum "$sentinel_adapter" | cut -d' ' -f1) == "$sentinel_adapter_hash" ]] \
  || fail "all invalid inputs retain the last known good adapter"
pass "malformed colors, units, and contrast fail honestly with atomic last-known-good retention"

grep -Fq 'design-tokens-v0.json' "$ROOT/shell/Commons/Tokens.qml" \
  || fail "QML Tokens consumes the canonical resolved payload"
grep -Fq 'Tokens.chrome.glass' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar consumes resolved semantic chrome"
grep -Fq 'Tokens.chrome.menu' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar tooltips consume resolved chrome tokens"
if grep -Fq 'Color.tooltip' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml"; then
  fail "Superbar tooltip is not a second Color.tooltip palette"
fi
if grep -Fq 'Color.tooltip' "$ROOT/shell/Ui/PanelToolTip.qml" "$ROOT/shell/Ui/Button.qml"; then
  fail "shared tooltips are not a second Color.tooltip palette"
fi
grep -Fq 'Tokens.chrome.menu' "$ROOT/shell/Ui/PanelToolTip.qml" \
  || fail "shared PanelToolTip consumes resolved chrome tokens"
grep -Fq 'Tokens.surface.canvas' "$ROOT/shell/plugins/lock/LockView.qml" \
  || fail "lock fill consumes resolved surface tokens"
if grep -Fq 'Color.background' "$ROOT/shell/plugins/lock/LockView.qml" "$ROOT/shell/plugins/lock/Service.qml"; then
  fail "lock fill is not a private Color.background"
fi
if grep -Fq 'Color.urgent' "$ROOT/shell/Ui/ConfirmDialog.qml"; then
  fail "ConfirmDialog danger is not Color.urgent"
fi
if grep -Fq 'Color.notifications' "$ROOT/shell/plugins/notifications/components/NotificationCard.qml"; then
  fail "NC card is not a second Color.notifications palette"
fi
grep -Fq 'chrome-tokens-v0.json' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars consumes the generated canonical adapter"
if grep -Eq '^[[:space:]]*(readonly[[:space:]]+)?property color chrome[A-Za-z]*:.*(Qt\.rgba|"#)' \
  "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml"; then
  fail "Superbar has no private chrome color"
fi
if grep -Eq 'or (28|30|62)|chrome_hex_rgb\([^)]*,[^)]*,' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "hyprbars adapter has no silent color fallback"
fi
grep -Fq 'omarchy-theme-resolve-tokens --active' "$ROOT/bin/omarchy-theme-set" \
  || fail "theme-set publishes design tokens after the theme swap"
if grep -Fq 'chrome-tokens-light.json' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "hyprbars does not fall back to a static light chrome adapter"
fi
if grep -Fq 'default/ultimate/chrome-tokens.json' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "hyprbars does not fall back to a static bundled chrome adapter"
fi
grep -Fq 'Tokens.surface.base' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start consumes resolved semantic chrome"
grep -Fq 'Tokens.typography.family' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start consumes resolved typography tokens"
if grep -Eq 'Qt\.rgba\(' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start has no private glass color"
fi
python3 - "$dark_adapter" "$light_adapter" <<'PY' || exit 1
import json
import sys

for path in sys.argv[1:]:
    adapter = json.load(open(path, encoding="utf-8"))
    for key in ("borderActiveHex", "borderInactiveHex"):
        value = adapter.get(key, "")
        assert isinstance(value, str) and value.startswith("#") and len(value) == 7, f"{path} missing {key}"
    assert adapter["borderActiveHex"] != adapter["borderInactiveHex"], f"{path} active and inactive borders collapsed"
PY
pass "QML and Lua chrome share the resolved contract without private runtime palettes"
