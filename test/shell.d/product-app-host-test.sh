#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

normalizer="$ROOT/shell/apps/shared/normalize_launch.py"
settings_catalog="$ROOT/shell/apps/ultimate-settings/routes-v1.json"
agent_catalog="$ROOT/shell/apps/ultimate-agent-center/routes-v1.json"

normalize() {
  python "$normalizer" "$@"
}

expect_normalized() {
  local description="$1"
  local application="$2"
  local expected_route="$3"
  shift 3
  local envelope

  if envelope=$(normalize "$application" "$@"); then
    :
  else
    fail "$description" "normalizer rejected a valid launch"
  fi
  python - "$expected_route" "$envelope" <<'PY' || fail "$description" "$envelope"
import json
import sys

expected = sys.argv[1]
envelope = json.loads(sys.argv[2])
assert envelope["schemaVersion"] == "omarchy.product-launch/v1"
assert envelope["routeId"] == expected
assert set(envelope) == {"schemaVersion", "application", "routeId", "arguments", "context"}
assert set(envelope["context"]) == {"screen", "anchor", "seat", "focusReturn", "source"}
PY
  pass "$description"
}

expect_rejected() {
  local description="$1"
  shift
  local output

  if output=$(normalize "$@" 2>&1); then
    fail "$description" "$output"
  fi
  [[ $output == Launch\ rejected:* ]] || fail "$description" "$output"
  pass "$description"
}

expect_normalized "Settings defaults to its registered home route" settings settings.overview
expect_normalized "Settings accepts a typed domain deep link" settings settings.network.overview \
  'omarchy-settings://network/overview?resourceId=network.radio.wifi' \
  --screen HDMI-A-1 --anchor=-20,30,420,48 --seat seat0 --focus-return 0xabc --source shell
expect_normalized "Agent Center maps operation links to activity" agent-center agent.activity \
  omarchy-agent://operation/00000000-0000-0000-0000-000000000001 --source notification
expect_normalized "Agent Center maps provider links to provider inventory" agent-center agent.providers \
  omarchy-agent://provider/network.provider

expect_rejected "Unknown Settings routes fail closed" settings settings.not-real
expect_rejected "Unknown route arguments fail closed" settings settings.display.overview --args-json '{"password":"secret"}'
expect_rejected "Deep links reject authority credentials" settings 'omarchy-settings://user@example/display/overview'
expect_rejected "Deep links reject duplicate typed arguments" settings 'omarchy-settings://network/overview?resourceId=one&resourceId=two'
expect_rejected "Deep links reject free-form query text" settings 'omarchy-settings://network/overview?search=coffee'
expect_rejected "Entity deep links reject extra path segments" agent-center omarchy-agent://task/task.one/private
expect_rejected "Entity deep links reject query strings" agent-center 'omarchy-agent://task/task.one?token=secret'
expect_rejected "Route and positional targets cannot be ambiguous" settings --route settings.display.overview settings.audio.overview
expect_rejected "Invocation options cannot be repeated" settings --source cli --source shell
expect_rejected "Monitor anchors require a positive size" settings --anchor 0,0,0,100
expect_rejected "Invocation sources are enumerated" settings --source browser

run_node_test <<'JS'
const fs = require('fs')
const protocol = requireFromRoot('shell/apps/shared/ProductProtocol.js')

const settings = JSON.parse(fs.readFileSync(path.join(root, 'shell/apps/ultimate-settings/routes-v1.json'), 'utf8'))
const agent = JSON.parse(fs.readFileSync(path.join(root, 'shell/apps/ultimate-agent-center/routes-v1.json'), 'utf8'))

const settingsValidation = protocol.validateCatalog(settings, 'settings', 'org.omarchy.Settings')
assert(settingsValidation.ok, 'QML-side protocol accepts the canonical Settings catalog')
assertEqual(settings.routes.length, 13, 'Settings catalog spans home and all twelve provider domains')

const agentValidation = protocol.validateCatalog(agent, 'agent-center', 'org.omarchy.AgentCenter')
assert(agentValidation.ok, 'QML-side protocol accepts the canonical Agent Center catalog')
assertEqual(agent.routes.length, 12, 'Agent Center catalog spans its complete product navigation')

const validEnvelope = {
  schemaVersion: 'omarchy.product-launch/v1',
  application: 'settings',
  routeId: 'settings.network.overview',
  arguments: { resourceId: 'network.radio.wifi' },
  context: { screen: 'HDMI-A-1', anchor: { x: 1, y: 2, width: 3, height: 4 }, seat: 'seat0', focusReturn: '0xabc', source: 'shell' }
}
assert(protocol.validateEnvelope(validEnvelope, settings).ok, 'QML-side protocol accepts a typed valid envelope')

const extraEnvelope = JSON.parse(JSON.stringify(validEnvelope))
extraEnvelope.secret = 'nope'
assert(!protocol.validateEnvelope(extraEnvelope, settings).ok, 'QML-side protocol rejects extra envelope fields')

const unknownArgument = JSON.parse(JSON.stringify(validEnvelope))
unknownArgument.arguments.password = 'secret'
assert(!protocol.validateEnvelope(unknownArgument, settings).ok, 'QML-side protocol rejects unregistered route arguments')

const wrongIdentity = JSON.parse(JSON.stringify(validEnvelope))
wrongIdentity.application = 'agent-center'
assert(!protocol.validateEnvelope(wrongIdentity, settings).ok, 'QML-side protocol rejects cross-application envelopes')

const duplicated = JSON.parse(JSON.stringify(settings))
duplicated.routes.push(JSON.parse(JSON.stringify(duplicated.routes[0])))
assert(!protocol.validateCatalog(duplicated, 'settings', 'org.omarchy.Settings').ok, 'QML-side protocol rejects duplicate routes')

function rejectsCatalogMutation(source, application, appId, mutate, description) {
  const candidate = JSON.parse(JSON.stringify(source))
  mutate(candidate)
  assert(!protocol.validateCatalog(candidate, application, appId).ok, description)
}

rejectsCatalogMutation(settings, 'settings', 'org.omarchy.Settings', candidate => {
  candidate.routes[0].privatePayload = 'not in v1'
}, 'QML-side catalog rejects extra route fields')
rejectsCatalogMutation(settings, 'settings', 'org.omarchy.Settings', candidate => {
  candidate.routes[1].argumentSchema.resourceId.privatePayload = true
}, 'QML-side catalog rejects extra argument-contract fields')
rejectsCatalogMutation(settings, 'settings', 'org.omarchy.Settings', candidate => {
  candidate.routes[1].argumentSchema.resourceId.optional = 'true'
}, 'QML-side catalog rejects non-boolean optional flags')
rejectsCatalogMutation(agent, 'agent-center', 'org.omarchy.AgentCenter', candidate => {
  candidate.routes[1].argumentSchema.entityType.values.push('task')
}, 'QML-side catalog rejects duplicate enum values')
rejectsCatalogMutation(settings, 'settings', 'org.omarchy.Settings', candidate => {
  candidate.appId = ['org.omarchy.Settings']
}, 'QML-side catalog rejects non-scalar application IDs')
rejectsCatalogMutation(settings, 'settings', 'org.omarchy.Settings', candidate => {
  candidate.scheme = ['omarchy-settings']
}, 'QML-side catalog rejects non-scalar schemes')
rejectsCatalogMutation(settings, 'settings', 'org.omarchy.Settings', candidate => {
  candidate.routes[1].deepLink.host = ['display']
}, 'QML-side catalog rejects non-scalar deep-link hosts')
rejectsCatalogMutation(settings, 'settings', 'org.omarchy.Settings', candidate => {
  candidate.routes[1].deepLink.path = ['overview']
}, 'QML-side catalog rejects non-scalar deep-link paths')
JS

python - "$normalizer" "$settings_catalog" "$agent_catalog" <<'PY' || fail "Python catalog validator rejects closed-schema corruption"
import copy
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location("product_normalizer", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

with open(sys.argv[2], encoding="utf-8") as stream:
    settings = json.load(stream)
with open(sys.argv[3], encoding="utf-8") as stream:
    agent = json.load(stream)

module.validate_catalog(settings, "settings")
module.validate_catalog(settings, "settings")
module.validate_catalog(agent, "agent-center")

mutations = []

candidate = copy.deepcopy(settings)
candidate["routes"][0]["privatePayload"] = "not in v1"
mutations.append(candidate)

candidate = copy.deepcopy(settings)
candidate["routes"][1]["argumentSchema"]["resourceId"]["privatePayload"] = True
mutations.append(candidate)

candidate = copy.deepcopy(settings)
candidate["routes"][1]["argumentSchema"]["resourceId"]["optional"] = "true"
mutations.append(candidate)

candidate = copy.deepcopy(settings)
candidate["appId"] = ["org.omarchy.Settings"]
mutations.append(candidate)

candidate = copy.deepcopy(settings)
candidate["scheme"] = ["omarchy-settings"]
mutations.append(candidate)

candidate = copy.deepcopy(settings)
candidate["routes"][1]["deepLink"]["host"] = ["display"]
mutations.append(candidate)

candidate = copy.deepcopy(settings)
candidate["routes"][1]["deepLink"]["path"] = ["overview"]
mutations.append(candidate)

for candidate in mutations:
    try:
        module.validate_catalog(candidate, "settings")
    except module.LaunchError:
        continue
    raise AssertionError("closed Python catalog validator accepted corruption")

candidate = copy.deepcopy(agent)
candidate["routes"][1]["argumentSchema"]["entityType"]["values"].append("task")
try:
    module.validate_catalog(candidate, "agent-center")
except module.LaunchError:
    pass
else:
    raise AssertionError("closed Python catalog validator accepted duplicate enum values")
PY
pass "Python catalog validator rejects closed-schema corruption"

for domain in display audio network bluetooth input personalization apps power accessibility update recovery system; do
  python - "$settings_catalog" "$domain" <<'PY' || fail "Settings catalog registers $domain"
import json
import sys

catalog = json.load(open(sys.argv[1], encoding="utf-8"))
domain = sys.argv[2]
assert any(route["id"].startswith(f"settings.{domain}.") for route in catalog["routes"])
PY
  pass "Settings catalog registers $domain"
done

python - "$agent_catalog" <<'PY' || fail "Agent Center entity links cover task, run, operation, and provider"
import json
import sys

catalog = json.load(open(sys.argv[1], encoding="utf-8"))
assert {link["host"] for link in catalog["entityDeepLinks"]} == {"task", "run", "operation", "provider"}
PY
pass "Agent Center entity links cover task, run, operation, and provider"

grep -Fqx '//@ pragma AppId org.omarchy.Settings' "$ROOT/shell/ultimate-settings.qml" || fail "Settings declares its stable app ID"
grep -Fqx '//@ pragma ShellId omarchy-ultimate-settings' "$ROOT/shell/ultimate-settings.qml" || fail "Settings declares its stable shell ID"
grep -Fqx '  fabricIdentity: "omarchy-settings"' "$ROOT/shell/ultimate-settings.qml" || fail "Settings declares its Fabric client identity"
grep -Fqx '  fabricAllowedMethods: ["provider.catalog", "provider.read"]' "$ROOT/shell/ultimate-settings.qml" || fail "Settings has a read-only Fabric method allowlist"
pass "Settings entrypoint fixes process, app, and least-privilege Fabric identity"

grep -Fqx '//@ pragma AppId org.omarchy.AgentCenter' "$ROOT/shell/ultimate-agent-center.qml" || fail "Agent Center declares its stable app ID"
grep -Fqx '//@ pragma ShellId omarchy-ultimate-agent-center' "$ROOT/shell/ultimate-agent-center.qml" || fail "Agent Center declares its stable shell ID"
grep -Fqx '  fabricIdentity: "omarchy-agent-center"' "$ROOT/shell/ultimate-agent-center.qml" || fail "Agent Center declares its Fabric client identity"
grep -Fqx '  fabricAllowedMethods: ["provider.catalog", "reference.operation.get"]' "$ROOT/shell/ultimate-agent-center.qml" || fail "Agent Center has a bounded Fabric method allowlist"
pass "Agent Center entrypoint fixes process, app, and least-privilege Fabric identity"

if rg -n '(^|[^A-Za-z])(Process\s*\{|Quickshell\.execDetached|execDetached\(|pkexec|sudo|hyprctl|systemctl)' \
  "$ROOT/shell/apps/ultimate-settings" "$ROOT/shell/apps/ultimate-agent-center" --glob '*.qml'; then
  fail "Standalone presentation code contains no process or privilege path"
fi
pass "Standalone presentation code contains no process or privilege path"

if rg -n 'property var shell|shell\.toggle|shell\.summon|plugins/' \
  "$ROOT/shell/apps/shared" "$ROOT/shell/apps/ultimate-settings" "$ROOT/shell/apps/ultimate-agent-center" --glob '*.qml'; then
  fail "Standalone applications receive no shell object or plugin code"
fi
pass "Standalone applications receive no shell object or plugin code"

for desktop in org.omarchy.Settings org.omarchy.AgentCenter; do
  file="$ROOT/applications/$desktop.desktop"
  grep -Fqx "StartupWMClass=$desktop" "$file" || fail "$desktop desktop identity matches compositor identity"
  grep -Fqx 'Type=Application' "$file" || fail "$desktop is an application desktop entry"
  grep -Fq 'MimeType=x-scheme-handler/' "$file" || fail "$desktop advertises its deep-link handler"
  grep -Fq 'Actions=' "$file" || fail "$desktop exposes discoverable destination actions"
  pass "$desktop desktop entry joins identity, links, and actions"
done

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/qs" <<'SH'
#!/bin/bash

if [[ $* == *" window activate "* ]]; then
  printf '%s\n' "$*" >>"$OMARCHY_TEST_LOG/omarchy-shell"
  if [[ ! -f $OMARCHY_TEST_STATE/ipc-no-focus ]]; then
    address="${!#}"
    if [[ -f $OMARCHY_TEST_STATE/uppercase-focus ]]; then
      address="0X${address#0x}"
    fi
    printf '%s\n' "$address" >"$OMARCHY_TEST_STATE/active.address"
    rm -f "$OMARCHY_TEST_STATE/active.hidden"
  fi
  printf '{"changed":true,"error":null}\n'
  exit 0
fi

if [[ $* == *ultimate-settings.qml* ]]; then
  app=settings
else
  app=agent
fi
[[ -f $OMARCHY_TEST_STATE/$app.running ]] || exit 1
printf '%s\n' "$*" >>"$OMARCHY_TEST_LOG/$app.qs"
printf 'ok\n'
SH

cat >"$fake_bin/systemd-run" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$OMARCHY_TEST_LOG/systemd-run"
if [[ $* == *ultimate-settings.qml* ]]; then
  touch "$OMARCHY_TEST_STATE/settings.running"
else
  touch "$OMARCHY_TEST_STATE/agent.running"
fi
SH

cat >"$fake_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ ${1:-} == "clients" ]]; then
  if [[ -f $OMARCHY_TEST_STATE/clients-empty ]]; then
    printf '[]\n'
  else
    delay=$(cat "$OMARCHY_TEST_STATE/client-delay" 2>/dev/null || printf '0\n')
    if (( delay > 0 )); then
      printf '%s\n' "$((delay - 1))" >"$OMARCHY_TEST_STATE/client-delay"
      printf '[]\n'
    else
      printf '[{"address":"0x1","class":"org.omarchy.Settings","initialClass":"org.omarchy.Settings","focusHistoryID":0},{"address":"0x2","class":"org.omarchy.AgentCenter","initialClass":"org.omarchy.AgentCenter","focusHistoryID":0}]\n'
    fi
  fi
elif [[ ${1:-} == "activewindow" ]]; then
  address=$(cat "$OMARCHY_TEST_STATE/active.address" 2>/dev/null || true)
  if [[ -f $OMARCHY_TEST_STATE/active.hidden ]]; then
    hidden=true
  else
    hidden=false
  fi
  printf '{"address":"%s","hidden":%s,"mapped":true}\n' "$address" "$hidden"
else
  printf '%s\n' "$*" >>"$OMARCHY_TEST_LOG/hyprctl"
  if [[ -f $OMARCHY_TEST_STATE/fallback-focus ]]; then
    address=$(sed -n 's/.*address:\(0[xX][0-9a-fA-F]*\).*/\1/p' <<<"$*")
    printf '%s\n' "$address" >"$OMARCHY_TEST_STATE/active.address"
  fi
fi
SH

cat >"$fake_bin/sleep" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$fake_bin/qs" "$fake_bin/systemd-run" "$fake_bin/hyprctl" "$fake_bin/sleep"
mkdir -p "$test_tmp/state" "$test_tmp/log"
: >"$test_tmp/log/systemd-run"
: >"$test_tmp/log/hyprctl"
: >"$test_tmp/log/omarchy-shell"

export OMARCHY_TEST_STATE="$test_tmp/state"
export OMARCHY_TEST_LOG="$test_tmp/log"
export OMARCHY_PATH="$ROOT"
export HYPRLAND_INSTANCE_SIGNATURE=test
export PATH="$fake_bin:$PATH"
export OMARCHY_PRODUCT_IPC_TIMEOUT=0.2s

bash "$ROOT/bin/omarchy-launch-settings" settings.network.overview \
  --args-json '{"resourceId":"network.radio.wifi"}' --screen HDMI-A-1 --source shell ||
  fail "Settings launcher starts and routes a validated first instance"
[[ $(wc -l <"$test_tmp/log/systemd-run") == 1 ]] || fail "Settings launcher starts one systemd service"
grep -Fq -- '--unit=omarchy-ultimate-settings' "$test_tmp/log/systemd-run" || fail "Settings uses its isolated systemd service"
grep -Fq 'settings.network.overview' "$test_tmp/log/settings.qs" || fail "Settings sends the normalized route over its own IPC target"
grep -Fq 'network.radio.wifi' "$test_tmp/log/settings.qs" || fail "Settings preserves its validated typed argument"
pass "Settings launcher starts and routes a validated first instance"

bash "$ROOT/bin/omarchy-launch-settings" settings.display.overview || fail "Settings launcher reuses a running instance"
[[ $(wc -l <"$test_tmp/log/systemd-run") == 1 ]] || fail "Settings launcher does not start a duplicate service"
grep -Fq 'settings.display.overview' "$test_tmp/log/settings.qs" || fail "Settings routes an existing instance"
pass "Settings launcher reuses and deep-routes its existing instance"

bash "$ROOT/bin/omarchy-launch-agent-center" omarchy-agent://provider/network.provider --source desktop ||
  fail "Agent Center launcher starts and routes a validated first instance"
[[ $(wc -l <"$test_tmp/log/systemd-run") == 2 ]] || fail "Agent Center has a separate systemd service"
grep -Fq -- '--unit=omarchy-ultimate-agent-center' "$test_tmp/log/systemd-run" || fail "Agent Center uses its isolated systemd service"
grep -Fq 'agent.providers' "$test_tmp/log/agent.qs" || fail "Agent Center receives its entity route"
grep -Fq 'network.provider' "$test_tmp/log/agent.qs" || fail "Agent Center receives its typed entity identifier"
pass "Agent Center starts in a separate service and receives its own route"

starts_before=$(wc -l <"$test_tmp/log/systemd-run")
if bash "$ROOT/bin/omarchy-launch-settings" settings.display.overview --args-json '{"password":"secret"}' >/dev/null 2>&1; then
  fail "Invalid launches are rejected before process start or IPC"
fi
[[ $(wc -l <"$test_tmp/log/systemd-run") == "$starts_before" ]] || fail "Invalid launch started a service"
pass "Invalid launches are rejected before process start or IPC"

grep -Fq 'window activate 0x1' "$test_tmp/log/omarchy-shell" || fail "Settings activates its exact compositor app identity"
grep -Fq 'window activate 0x2' "$test_tmp/log/omarchy-shell" || fail "Agent Center activates its exact compositor app identity"
[[ ! -s $test_tmp/log/hyprctl ]] || fail "Verified WindowService focus avoids the compositor fallback"
pass "Launchers use verified WindowService activation for exact compositor identities"

printf '3\n' >"$test_tmp/state/client-delay"
touch "$test_tmp/state/uppercase-focus"
bash "$ROOT/bin/omarchy-launch-settings" settings.audio.overview || fail "Settings focus tolerates delayed client publication"
[[ $(cat "$test_tmp/state/client-delay") == "0" ]] || fail "Focus did not wait for delayed client publication"
grep -Fq '0X1' "$test_tmp/state/active.address" || fail "Focus comparison did not accept a case-equivalent address"
pass "Focus waits for the compositor client and compares addresses case-insensitively"

touch "$test_tmp/state/active.hidden"
bash "$ROOT/bin/omarchy-launch-settings" settings.network.overview || fail "Settings activation restores a hidden window"
[[ ! -f $test_tmp/state/active.hidden ]] || fail "Settings remained hidden after activation"
pass "Activation restores a hidden standalone application before focus verification"

rm "$test_tmp/state/uppercase-focus"
touch "$test_tmp/state/ipc-no-focus" "$test_tmp/state/fallback-focus"
: >"$test_tmp/state/active.address"
: >"$test_tmp/log/hyprctl"
bash "$ROOT/bin/omarchy-launch-settings" settings.power.overview || fail "Compositor fallback recovers an unavailable shell focus"
grep -Fq 'focus({ window = "address:0x1" })' "$test_tmp/log/hyprctl" || fail "Focus recovery did not target the exact address"
[[ $(cat "$test_tmp/state/active.address") == "0x1" ]] || fail "Focus recovery did not verify the active address"
pass "A verified compositor fallback recovers shell focus failure"

rm "$test_tmp/state/fallback-focus"
printf '0xdead\n' >"$test_tmp/state/active.address"
if bash "$ROOT/bin/omarchy-launch-settings" settings.system.overview >/dev/null 2>&1; then
  fail "Permanent focus failure was reported as success"
fi
pass "Launchers fail closed when neither focus path changes the active window"

rm "$test_tmp/state/ipc-no-focus"
touch "$test_tmp/state/clients-empty"
if bash "$ROOT/bin/omarchy-launch-settings" settings.overview >/dev/null 2>&1; then
  fail "Missing compositor client was reported as focused"
fi
pass "Launchers fail closed when the application client never appears"
