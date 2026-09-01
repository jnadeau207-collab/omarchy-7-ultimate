#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq
require_command python3

migration="$ROOT/migrations/1786643346.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
profile_root="$home/.config/chromium"
preferences="$profile_root/Default/Preferences"
mkdir -p "$(dirname "$preferences")"

ghost_id="ikkebdkaanlebnifjnbeiaklodhbjcci"
pinned_id="bgpiichlckmfanooecilcjemknkcpngb"

write_stale_preferences() {
  jq -n --arg ghost "$ghost_id" --arg pinned "$pinned_id" '{extensions: {commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {($ghost): {commands: {"copy-url": {suggested_key: "Alt+Shift+L", was_assigned: true}}}, ($pinned): {commands: {"copy-url": {suggested_key: "Alt+Shift+L"}}}}}}' >"$preferences"
}

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
exit 127
STUB
chmod +x "$stub_bin/python3"

REAL_PYTHON=$(PATH="$stub_bin:$PATH" command -p -v python3)
[[ $REAL_PYTHON != "$stub_bin/python3" ]] || fail "real Python resolution bypasses user shims"
export REAL_PYTHON
rm -f "$stub_bin/python3"

run_migration() {
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1
}

open_browser() {
  mkdir -p "$profile_root"
  ln -sfn "test-host-1234" "$profile_root/SingletonLock"
}
close_browser() {
  rm -f "$profile_root/SingletonLock"
}

printf '#!/bin/bash\nexit 1\n' >"$stub_bin/gum"
chmod +x "$stub_bin/gum"
write_stale_preferences
open_browser

before_hash=$(sha256sum "$preferences" | cut -d' ' -f1)

run_migration && fail "migration defers while the affected profile is open"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$before_hash" ]] ||
  fail "migration leaves preferences alone while the affected profile is open"
pass "migration defers the repair while the affected profile is open"

cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
echo "gum-prompt-painted" >&2
exit 1
STUB
prompt_stderr="$test_dir/prompt-stderr"
HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>"$prompt_stderr" &&
  fail "migration defers when the browser prompt is declined"
grep -q "gum-prompt-painted" "$prompt_stderr" || fail "migration keeps the browser prompt visible"
pass "migration keeps the browser prompt visible"

close_browser
mkdir -p "$home/.config/google-chrome"
ln -sfn "test-host-1234" "$home/.config/google-chrome/SingletonLock"
write_stale_preferences
run_migration || fail "migration repairs while a different profile root is open"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration repairs the shortcut while a different profile root is open"
pass "migration ignores a browser on a different profile root"
rm -f "$home/.config/google-chrome/SingletonLock" "$preferences.omarchy-copy-url-repair.bak"

write_stale_preferences
open_browser
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
"$CLOSE_BROWSER"
touch "${GUM_CALLED:?}"
exit 0
STUB
cat >"$stub_bin/close-browser" <<'STUB'
#!/bin/bash
rm -f "$HOME/.config/chromium/SingletonLock"
STUB
chmod +x "$stub_bin/gum" "$stub_bin/close-browser"
GUM_CALLED="$test_dir/gum-called" CLOSE_BROWSER="$stub_bin/close-browser" \
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1 ||
  fail "migration proceeds once the profile is closed and the prompt confirmed"
[[ -e $test_dir/gum-called ]] || fail "migration asks before repairing under a running browser"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration repairs after the browser prompt is confirmed"
pass "migration asks to close the browser and repairs on confirmation"
rm -f "$preferences.omarchy-copy-url-repair.bak"

printf '#!/bin/bash\nexit 1\n' >"$stub_bin/gum"
close_browser
write_stale_preferences
run_migration || fail "migration repairs the shortcut when no browser is running"

jq -e --arg ghost "$ghost_id" --arg pinned "$pinned_id" '
  .extensions.commands["linux:Alt+Shift+L"].extension == $pinned and
  (.extensions.settings | has($ghost) | not) and
  .extensions.settings[$pinned].commands["copy-url"].was_assigned == true
' "$preferences" >/dev/null || fail "migration rebinds the Copy URL shortcut to the pinned extension id"
[[ -f $preferences.omarchy-copy-url-repair.bak ]] ||
  fail "migration backs up preferences before the repair"
pass "migration rebinds the Copy URL shortcut to the pinned extension id"

rm "$preferences.omarchy-copy-url-repair.bak"
repaired_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
open_browser
run_migration || fail "migration reruns cleanly after the repair"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$repaired_hash" && ! -e $preferences.omarchy-copy-url-repair.bak ]] ||
  fail "migration is idempotent after the repair"
pass "migration is idempotent after the repair"
close_browser

jq -n --arg ghost "$ghost_id" '{extensions: {commands: {"linux:Ctrl+Alt+P": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {}}}' >"$preferences"
run_migration || fail "migration repairs remapped shortcuts"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Ctrl+Alt+P"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration keeps the remapped key while rebinding to the pinned id"
pass "migration keeps remapped shortcut keys"

jq -n --arg ghost "$ghost_id" --arg pinned "$pinned_id" '{extensions: {commands: {"linux:Ctrl+Alt+P": {command_name: "copy-url", extension: $pinned, global: false}, "linux:Alt+Shift+L": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {}}}' >"$preferences"
run_migration || fail "migration cleans ghosts alongside a manual repair"
jq -e --arg pinned "$pinned_id" '
  (.extensions.commands | has("linux:Alt+Shift+L") | not) and
  .extensions.commands["linux:Ctrl+Alt+P"].extension == $pinned
' "$preferences" >/dev/null || fail "migration drops the ghost instead of double-binding the pinned extension"
pass "migration never double-binds the pinned extension"

write_stale_preferences
close_browser
rm -f "$preferences.omarchy-copy-url-repair.bak"
cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
# Called as `python3 -c <script> <preferences> <pinned_id> <check|repair>`, and
# the check calls report a surviving ghost through their exit status.
"${REAL_PYTHON}" "$@"
status=$?
[[ ${5:-} == "repair" ]] && ln -sfn "test-host-1234" "$HOME/.config/chromium/SingletonLock"
exit $status
STUB
chmod +x "$stub_bin/python3"
if HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1; then
  fail "migration stays pending when a browser starts mid-repair"
fi
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration still repairs preferences before deferring on a late browser"
pass "migration stays pending when a browser starts mid-repair"
rm -f "$stub_bin/python3" "$preferences.omarchy-copy-url-repair.bak"
close_browser

write_stale_preferences
cp "$preferences" "$test_dir/stale-preferences"
cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
"${REAL_PYTHON}" "$@"
status=$?
[[ ${5:-} == "repair" ]] && cp "${STALE_PREFERENCES:?}" "${REPAIRED_PREFERENCES:?}"
exit $status
STUB
chmod +x "$stub_bin/python3"
if HOME="$home" PATH="$stub_bin:$PATH" STALE_PREFERENCES="$test_dir/stale-preferences" \
  REPAIRED_PREFERENCES="$preferences" bash -euo pipefail "$migration" >/dev/null 2>&1; then
  fail "migration stays pending when a briefly-lived browser undoes the repair"
fi
pass "migration stays pending when a briefly-lived browser undoes the repair"
rm -f "$stub_bin/python3"
close_browser
write_stale_preferences
run_migration || fail "migration recovers after a reverted repair"
rm -f "$preferences.omarchy-copy-url-repair.bak"

write_stale_preferences
run_migration || fail "repair run before the verification scenario"
[[ -f $preferences.omarchy-copy-url-repair.bak ]] || fail "verification scenario has a repair backup"
open_browser
run_migration && fail "migration must not complete an unverified repair while a browser runs"
pass "migration keeps an unverified repair pending while a browser runs"
close_browser
run_migration || fail "migration completes once the repair is verified with browsers closed"
pass "migration verifies an attempted repair on a browser-free rerun"
rm -f "$preferences.omarchy-copy-url-repair.bak"

jq -n '{extensions: {commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", global: false}}, settings: {aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa: {path: "/home/user/.config/some-extension", commands: {}}}}}' >"$preferences"
untouched_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration || fail "migration leaves installed third-party extensions alone"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$untouched_hash" ]] ||
  fail "migration does not steal a third-party copy-url command registration"
pass "migration leaves installed third-party extensions alone"
