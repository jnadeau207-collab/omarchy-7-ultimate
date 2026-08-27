#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command python3
python3_command=${OMARCHY_TEST_PYTHON3:-$(command -v python3)}

normalizer="$ROOT/shell/apps/shared/normalize_launch.py"

assert_normalized() {
  local label="$1" application="$2" route="$3"
  shift 3
  local output
  output=$(python3 "$normalizer" "$application" "$@") || fail "$label"
  python3 -c '
import json
import sys

value = json.load(sys.stdin)
expected_context = ["anchor", "focusReturn", "screen", "seat", "source"]
valid = (
    value.get("schemaVersion") == "omarchy.product-launch/v1"
    and value.get("application") == sys.argv[1]
    and value.get("routeId") == sys.argv[2]
    and sorted(value.get("context", {}).keys()) == expected_context
)
raise SystemExit(0 if valid else 1)
' "$application" "$route" <<<"$output" || fail "$label" "$output"
  pass "$label"
}

assert_normalized "Files normalizes bounded search text" files files.search 'omarchy-files://search/results?query=quarterly%20report'
assert_normalized "Files normalizes exact entry deep links" files files.search 'omarchy-files://entry/files.entry.readme'
assert_normalized "Software Center normalizes catalog deep links" software software.catalog 'omarchy-software://catalog?query=editor'
assert_normalized "Software Center normalizes exact operation deep links" software software.history 'omarchy-software://operation/packages.operation.install'
assert_normalized "Compatibility Center normalizes exact deployment deep links" compatibility compatibility.deployments 'omarchy-compatibility://deployment/compatibility.deployment.reader'

if python3 "$normalizer" files files.search --args-json "$(printf '{\"query\":\"%0121d\"}' 0)" >/dev/null 2>&1; then
  fail "Normalizer accepted overlong Files search text"
fi
if python3 "$normalizer" software software.catalog --args-json '{"password":"secret"}' >/dev/null 2>&1; then
  fail "Normalizer accepted an undeclared Software Center argument"
fi
if python3 "$normalizer" compatibility 'omarchy-compatibility://deployment/one/two' >/dev/null 2>&1; then
  fail "Normalizer accepted an ambiguous Compatibility entity path"
fi
pass "Domain launch normalization rejects overlong, secret-bearing, and ambiguous input"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
fake_bin="$test_root/bin"
mkdir -p "$fake_bin" "$test_root/state" "$test_root/log"
: >"$test_root/log/systemd-run"
: >"$test_root/log/qs"
: >"$test_root/log/focus"

cat >"$fake_bin/qs" <<'SH'
#!/bin/bash

if [[ $* == *" window activate "* ]]; then
  address=${!#}
  printf '%s\n' "$address" >"$OMARCHY_TEST_STATE/active"
  printf '%s\n' "$*" >>"$OMARCHY_TEST_LOG/focus"
  printf '{"changed":true,"error":null}\n'
  exit 0
fi

case $* in
  *ultimate-files.qml*) app=files ;;
  *ultimate-software.qml*) app=software ;;
  *ultimate-compatibility.qml*) app=compatibility ;;
  *) exit 1 ;;
esac

[[ -f $OMARCHY_TEST_STATE/$app.running ]] || exit 1
printf '%s\n' "$*" >>"$OMARCHY_TEST_LOG/qs"
printf 'ok\n'
SH

cat >"$fake_bin/systemd-run" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$OMARCHY_TEST_LOG/systemd-run"
case $* in
  *ultimate-files.qml*) touch "$OMARCHY_TEST_STATE/files.running" ;;
  *ultimate-software.qml*) touch "$OMARCHY_TEST_STATE/software.running" ;;
  *ultimate-compatibility.qml*) touch "$OMARCHY_TEST_STATE/compatibility.running" ;;
  *) exit 1 ;;
esac
SH

cat >"$fake_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ ${1:-} == "clients" ]]; then
  printf '[{"address":"0x11","class":"org.omarchy.Files","initialClass":"org.omarchy.Files","focusHistoryID":2},{"address":"0x12","class":"org.omarchy.Software","initialClass":"org.omarchy.Software","focusHistoryID":1},{"address":"0x13","class":"org.omarchy.Compatibility","initialClass":"org.omarchy.Compatibility","focusHistoryID":0}]\n'
elif [[ ${1:-} == "activewindow" ]]; then
  address=$(cat "$OMARCHY_TEST_STATE/active" 2>/dev/null || true)
  printf '{"address":"%s","hidden":false,"mapped":true}\n' "$address"
else
  exit 1
fi
SH

cat >"$fake_bin/sleep" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$fake_bin/python" <<'SH'
#!/bin/bash
exec "$OMARCHY_TEST_PYTHON3" "$@"
SH

chmod +x "$fake_bin/qs" "$fake_bin/systemd-run" "$fake_bin/hyprctl" "$fake_bin/sleep" "$fake_bin/python"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_STATE="$test_root/state"
export OMARCHY_TEST_LOG="$test_root/log"
export OMARCHY_TEST_PYTHON3="$python3_command"
export WAYLAND_DISPLAY=wayland-1
export HYPRLAND_INSTANCE_SIGNATURE=test
export OMARCHY_PRODUCT_IPC_TIMEOUT=0.2s
export PATH="$fake_bin:$PATH"

bash "$ROOT/bin/omarchy-launch-files" 'omarchy-files://search/results?query=report' --source desktop || fail "Files launcher starts and routes its first instance"
bash "$ROOT/bin/omarchy-launch-software" 'omarchy-software://software/software.curated.neovim' --source shell || fail "Software Center launcher starts and routes its first instance"
bash "$ROOT/bin/omarchy-launch-compatibility" compatibility.deployments --source cli || fail "Compatibility Center launcher starts and routes its first instance"

[[ $(wc -l <"$test_root/log/systemd-run") == 3 ]] || fail "Domain launchers started exactly three isolated services"
grep -Fq -- '--unit=omarchy-ultimate-files' "$test_root/log/systemd-run" || fail "Files uses its isolated service"
grep -Fq -- '--unit=omarchy-ultimate-software' "$test_root/log/systemd-run" || fail "Software Center uses its isolated service"
grep -Fq -- '--unit=omarchy-ultimate-compatibility' "$test_root/log/systemd-run" || fail "Compatibility Center uses its isolated service"
grep -Fq 'files.search' "$test_root/log/qs" || fail "Files receives its normalized search route"
grep -Fq 'software.curated.neovim' "$test_root/log/qs" || fail "Software Center receives its exact deep-linked identity"
grep -Fq 'compatibility.deployments' "$test_root/log/qs" || fail "Compatibility Center receives its normalized route"
pass "Domain launchers start distinct services and route exact envelopes"

bash "$ROOT/bin/omarchy-launch-files" files.recent || fail "Files reuses its running instance"
bash "$ROOT/bin/omarchy-launch-software" software.installed || fail "Software Center reuses its running instance"
bash "$ROOT/bin/omarchy-launch-compatibility" compatibility.overview || fail "Compatibility Center reuses its running instance"
[[ $(wc -l <"$test_root/log/systemd-run") == 3 ]] || fail "Domain launchers started duplicate services"
grep -Fq 'window activate 0x11' "$test_root/log/focus" || fail "Files focuses only its exact AppId window"
grep -Fq 'window activate 0x12' "$test_root/log/focus" || fail "Software Center focuses only its exact AppId window"
grep -Fq 'window activate 0x13' "$test_root/log/focus" || fail "Compatibility Center focuses only its exact AppId window"
pass "Domain launchers reuse and focus the exact existing application instance"

starts_before=$(wc -l <"$test_root/log/systemd-run")
if bash "$ROOT/bin/omarchy-launch-files" files.search --args-json '{"query":"ok","token":"secret"}' >/dev/null 2>&1; then
  fail "Invalid Files activation was accepted"
fi
[[ $(wc -l <"$test_root/log/systemd-run") == "$starts_before" ]] || fail "Rejected activation started a service"
pass "Invalid domain activation fails before IPC or process start"
