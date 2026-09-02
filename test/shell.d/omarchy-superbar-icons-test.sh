#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

button="$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml"

declared=$(grep -cE '^\s*sourceSize\.(width|height):' "$button")
(( declared > 0 )) || fail "Superbar icons declare a sourceSize at all"

scaled=$(grep -cE '^\s*sourceSize\.(width|height): [0-9]+ \* Screen\.devicePixelRatio$' "$button")
if (( scaled != declared )); then
  fail "every Superbar icon sourceSize scales by the device pixel ratio so icons are not washed out" \
    "$(grep -nE '^\s*sourceSize\.(width|height):' "$button" | grep -vE '[0-9]+ \* Screen\.devicePixelRatio$')"
fi

grep -Fq 'id: icon' "$button" || fail "Superbar keeps a named app icon image"
icon_block=$(sed -n '/^\s*Image {$/,/^\s*}$/p' "$button" | awk '/id: icon$/,/^\s*}$/')
grep -qE 'sourceSize\.width: [0-9]+ \* Screen\.devicePixelRatio' <<<"$icon_block" ||
  fail "the Superbar app icon requests a device-pixel sourceSize width"
grep -qE 'sourceSize\.height: [0-9]+ \* Screen\.devicePixelRatio' <<<"$icon_block" ||
  fail "the Superbar app icon requests a device-pixel sourceSize height"

pass "every Superbar icon sourceSize is scaled by the device pixel ratio"
