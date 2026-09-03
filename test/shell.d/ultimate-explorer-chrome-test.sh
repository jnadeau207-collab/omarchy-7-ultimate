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

grep -Fq 'var headerHeight = 22' "$theme" \
  || fail "Explorer header is the measured height"
grep -Fq 'var rowHeight = 18' "$theme" \
  || fail "Explorer details rows are the measured height"
pass "Explorer header and rows are the measured heights"

grep -Fq 'var headerTop = "#ffffff"' "$theme" \
  || fail "Explorer header fill starts white"
grep -Fq 'var headerMid = "#fafafa"' "$theme" \
  || fail "Explorer header fill inflects at forty-five percent"
grep -Fq 'var headerBottom = "#f0f0f0"' "$theme" \
  || fail "Explorer header fill ends in the pale grey"
grep -Fq 'var headerBorder = "#d7d7d7"' "$theme" \
  || fail "Explorer header border is the measured grey"
grep -Fq 'var headerSeparator = "#eeeeee"' "$theme" \
  || fail "Explorer column separators are the measured grey"
pass "Explorer header fill, border, and separators are the measured values"

grep -Fq 'var sortedHeaderTop = "#f3f9fc"' "$theme" \
  || fail "Explorer sorted header starts near-white blue"
grep -Fq 'var sortedHeaderMid = "#e4f0f8"' "$theme" \
  || fail "Explorer sorted header inflects at forty-five percent"
grep -Fq 'var sortedHeaderBottom = "#d9eaf5"' "$theme" \
  || fail "Explorer sorted header ends in the pale blue"
grep -Fq 'var sortedHeaderBorder = "#a7d8f5"' "$theme" \
  || fail "Explorer sorted header border is the measured blue"
pass "Explorer sorted header carries its own measured wash"

grep -Fq 'position: 0.45; color: Aero.headerMid' "$view" \
  || fail "Explorer header gradient inflects at forty-five percent"
grep -Fq 'visible: root.sortColumn === modelData.key' "$view" \
  || fail "Explorer sorted column shows the sorted wash"
grep -Fq 'font.weight: Font.Normal' "$view" \
  || fail "Explorer header text is regular weight, not bold"
pass "Explorer header paints the sorted wash and regular-weight labels"
