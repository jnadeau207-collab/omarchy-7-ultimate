#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

theme="$ROOT/shell/apps/ultimate-files/ExplorerTheme.js"
view="$ROOT/shell/apps/ultimate-files/ExplorerItemView.qml"

grep -Fq 'var selectionTop = "#ffffff"' "$theme" \
  || fail "Explorer selection wash starts near-white"
grep -Fq 'var selectionBottom = "#e6ecf5"' "$theme" \
  || fail "Explorer selection wash ends in the pale blue wash"
grep -Fq 'var selectionBorder = "#aaddfa"' "$theme" \
  || fail "Explorer selection border is the pale blue rule"
pass "Explorer selection is the near-white wash, not a saturated blue"

if grep -Eq 'var selection(Bottom|Border) = "#(dcebfc|c1dbfc|7da2ce)"' "$theme"; then
  fail "Explorer selection keeps no saturated blue fill"
fi
pass "Explorer selection keeps no saturated blue fill"

grep -Fq 'var hoverSelectedTop = "#eef4fa"' "$theme" \
  || fail "Explorer hovered selection stays in the pale family"
grep -Fq 'var hoverSelectedBottom = "#d7e4f1"' "$theme" \
  || fail "Explorer hovered selection stays in the pale family"
grep -Fq 'var hoverSelectedBorder = "#8fb8d8"' "$theme" \
  || fail "Explorer hovered selection stays in the pale family"
pass "Explorer hovered selection stays in the pale family"

grep -Fq 'id: sortMark' "$view" || fail "Explorer header paints a sort mark"
grep -Fq 'width: 6' "$view" || fail "Explorer sort mark is the narrow triangle"
grep -Fq 'height: 5' "$view" || fail "Explorer sort mark is the narrow triangle"
grep -Fq 'anchors.horizontalCenter: parent.horizontalCenter' "$view" \
  || fail "Explorer sort mark sits top-centre of the sorted header"
grep -Fq 'anchors.top: parent.top' "$view" \
  || fail "Explorer sort mark sits top-centre of the sorted header"
pass "Explorer sort mark sits top-centre of the sorted header"

grep -Fq 'createLinearGradient(0, 0, width, height)' "$view" \
  || fail "Explorer sort mark carries the diagonal wash"
grep -Fq 'addColorStop(0.45, "#667f91")' "$view" \
  || fail "Explorer sort mark carries the diagonal wash"
grep -Fq 'addColorStop(0.65, "#90c1e2")' "$view" \
  || fail "Explorer sort mark carries the diagonal wash"
grep -Fq 'addColorStop(1, "#cce3f2")' "$view" \
  || fail "Explorer sort mark carries the diagonal wash"
if grep -Fq 'fillStyle = "#6b7b8a"' "$view"; then
  fail "Explorer sort mark keeps no flat grey fill"
fi
pass "Explorer sort mark carries the diagonal wash, not a flat fill"
