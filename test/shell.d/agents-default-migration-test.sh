#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq

migration="$ROOT/migrations/1785344985.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash

echo restart >>"$SHELL_RESTARTS"
STUB

chmod +x "$test_dir/bin/"*

export SHELL_RESTARTS="$test_dir/shell-restarts"

home="$test_dir/home"
config="$home/.config/omarchy/shell.json"

run_migration() {
  : >"$SHELL_RESTARTS"
  HOME="$home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

write_config() {
  rm -rf "$home"
  mkdir -p "$home/.config/omarchy"
  jq "${1:-.}" "$ROOT/config/omarchy/shell.json" >"$config"
}

without_widget='del(.bar.layout[][] | select((if type == "object" then .id else . end) == "omarchy.agents"))'

ids() {
  jq -c --arg section "$1" '[.bar.layout[$section][]? | if type == "object" then .id else . end]' "$config"
}

jq -e '[.bar.layout.right[].id] | index("omarchy.agents")' "$ROOT/config/omarchy/shell.json" >/dev/null ||
  fail "shipped config puts the agents widget in the bar"
pass "shipped config puts the agents widget in the bar"

write_config "$without_widget"
run_migration

[[ $(ids right) == '["omarchy.tray","omarchy.agents","omarchy.bluetooth","omarchy.network","omarchy.audio","omarchy.monitor","omarchy.power"]' ]] ||
  fail "migration inserts the agents widget after the tray" "$(ids right)"
pass "migration inserts the agents widget after the tray"

(($(wc -l <"$SHELL_RESTARTS") == 0)) || fail "migration leaves the shell restart to omarchy update"
pass "migration leaves the shell restart to omarchy update"

before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent" "$(ids right)"
pass "migration is idempotent"

write_config "$without_widget | .bar.layout.center += [{ id: \"omarchy.agents\" }]"
run_migration

[[ $(ids center) == *'"omarchy.agents"'* ]] || fail "migration leaves a user-placed widget alone" "$(ids center)"
[[ $(ids right) != *'"omarchy.agents"'* ]] || fail "migration does not add a second copy" "$(ids right)"
pass "migration respects a widget the user already placed"

write_config "$without_widget | .bar.layout.right = [\"omarchy.tray\", \"omarchy.agents\", \"omarchy.power\"]"
run_migration

[[ $(ids right) == '["omarchy.tray","omarchy.agents","omarchy.power"]' ]] ||
  fail "migration reads string-form entries" "$(ids right)"
pass "migration reads string-form entries"

write_config "$without_widget | del(.bar.layout.right[] | select(.id == \"omarchy.tray\"))"
run_migration

[[ $(ids right) == '["omarchy.agents",'* ]] || fail "migration places the widget without a tray" "$(ids right)"
pass "migration places the widget without a tray"

write_config "$without_widget"
cp "$config" "$test_dir/before.json"
run_migration

diff <(jq -S 'del(.bar.layout.right)' "$test_dir/before.json") <(jq -S 'del(.bar.layout.right)' "$config") >/dev/null ||
  fail "migration touches nothing but the right section" "$(diff <(jq -S . "$test_dir/before.json") <(jq -S . "$config"))"
pass "migration touches nothing but the right section"

rm -rf "$home"
mkdir -p "$home/.config/omarchy"
printf '{ not json' >"$config"
run_migration

[[ $(cat "$config") == '{ not json' ]] || fail "migration leaves an unparsable config untouched" "$(cat "$config")"
pass "migration leaves an unparsable config untouched"
