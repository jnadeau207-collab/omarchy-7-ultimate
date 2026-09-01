#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

write_plugin() {
  local name="$1" kinds="$2" entry_points="$3" bar_widget="${4:-null}"
  local dir="$TMPDIR/$name"
  local entry

  mkdir -p "$dir"
  cat >"$dir/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "acme.$name",
  "name": "Acme $name",
  "version": "1.0.0",
  "kinds": $kinds,
  "entryPoints": $entry_points,
  "barWidget": $bar_widget
}
JSON

  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    touch "$dir/$entry"
  done < <(jq -r '.[]' <<<"$entry_points")

  printf '%s\n' "$dir"
}

validate() {
  OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$1" 2>&1
}

while IFS=: read -r kind entry_point; do
  dir=$(write_plugin "wants-$kind" "[\"$kind\"]" "{\"$entry_point\": \"Entry.qml\"}")
  validate "$dir" >/dev/null || fail "validate accepts $kind with its $entry_point entry point"
  pass "validate accepts $kind with its $entry_point entry point"

  other_key="service"
  [[ $entry_point == "service" ]] && other_key="panel"
  dir=$(write_plugin "missing-$kind" "[\"$kind\"]" "{\"$other_key\": \"Entry.qml\"}")
  output=$(validate "$dir") && fail "validate refuses $kind without its $entry_point entry point" "$output"
  grep -qF "kind '$kind' requires an 'entryPoints.$entry_point' to load" <<<"$output" \
    || fail "validate names the entry point $kind is missing" "$output"
  pass "validate refuses $kind without its $entry_point entry point"
done <<'KINDS'
bar:bar
bar-widget:barWidget
menu:menu
overlay:overlay
panel:panel
service:service
KINDS

dir=$(write_plugin "both" '["bar","bar-widget"]' '{"bar": "Bar.qml", "barWidget": "Widget.qml"}')
validate "$dir" >/dev/null || fail "validate accepts a plugin that satisfies every kind it declares"
pass "validate accepts a plugin that satisfies every kind it declares"

dir=$(write_plugin "half" '["bar","bar-widget"]' '{"bar": "Bar.qml"}')
output=$(validate "$dir") && fail "validate refuses a plugin that satisfies only one of its kinds" "$output"
grep -qF "kind 'bar-widget' requires" <<<"$output" \
  || fail "validate names the unsatisfied kind" "$output"
pass "validate refuses a plugin that satisfies only one of its kinds"

for section in left center right; do
  dir=$(write_plugin "defaults-$section" '["bar-widget"]' '{"barWidget": "Widget.qml"}' "{\"defaultSection\": \"$section\"}")
  validate "$dir" >/dev/null || fail "validate accepts $section as a default bar widget section"
  pass "validate accepts $section as a default bar widget section"
done

dir=$(write_plugin "defaults-bottom" '["bar-widget"]' '{"barWidget": "Widget.qml"}' '{"defaultSection": "bottom"}')
output=$(validate "$dir") && fail "validate refuses an invalid default bar widget section" "$output"
grep -qF "'barWidget.defaultSection' must be left, center, or right" <<<"$output" \
  || fail "validate explains the default bar widget section contract" "$output"
pass "validate refuses an invalid default bar widget section"

dir=$(write_plugin "unknown" '["future-thing"]' '{"service": "Entry.qml"}')
validate "$dir" >/dev/null || fail "validate leaves a kind it does not know alone"
pass "validate leaves a kind it does not know alone"

dir="$TMPDIR/ghost"
mkdir -p "$dir"
cat >"$dir/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.ghost",
  "name": "Acme Ghost",
  "version": "1.0.0",
  "kinds": ["bar"],
  "entryPoints": { "bar": "Missing.qml" }
}
JSON
output=$(validate "$dir") && fail "validate refuses an entry point file that is not there" "$output"
grep -qF "entry point file not found" <<<"$output" \
  || fail "validate reports a missing file as a missing file" "$output"
pass "validate refuses an entry point file that is not there"
