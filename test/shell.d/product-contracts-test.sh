#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PYTHONDONTWRITEBYTECODE=1

checker="$ROOT/bin/omarchy-dev-product-contract-check"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

require_command python

fake_bin="$scratch/missing-dependency-bin"
mkdir -p "$fake_bin"
printf '#!/bin/bash\nexit 1\n' >"$fake_bin/python"
chmod +x "$fake_bin/python"

set +e
dependency_output=$(PATH="$fake_bin:$PATH" OMARCHY_PATH="$ROOT" bash "$checker" --root "$ROOT" 2>&1)
dependency_status=$?
set -e

(( dependency_status == 2 )) || fail "product-contract checker has a dedicated dependency failure" "$dependency_output"
[[ $dependency_output == *"python-jsonschema is required"* ]] || fail "product-contract checker names the missing python-jsonschema dependency" "$dependency_output"
pass "product-contract checker fails clearly without python-jsonschema"

if ! python -c 'import jsonschema' >/dev/null 2>&1; then
  fail "python-jsonschema is required to certify product-contract inventory"
fi

valid_output=$(OMARCHY_PATH="$ROOT" bash "$checker" --root "$ROOT")
[[ $valid_output == *"45 plugins; 27 surface routes"* ]] || fail "product-contract checker reports every first-party plugin and invocable surface" "$valid_output"
[[ $valid_output == *"31 IPC endpoints/"* ]] || fail "product-contract checker reports every live shell and standalone-app IPC target" "$valid_output"
[[ $valid_output == *"27 applications (25 first-party launchers, 4 shipped pins, 0 planned absent)"* ]] || fail "product-contract checker reports launcher, pin, and standalone-app identities" "$valid_output"
[[ $valid_output == *"8 search providers (3 legacy, 5 absent)"* ]] || fail "product-contract checker reports current and absent normalized-search sources" "$valid_output"
[[ $valid_output == *"38 process invocation components; 10 debt groups"* ]] || fail "product-contract checker reports the exhaustive process inventory and debt" "$valid_output"
pass "product contracts validate against the live plugin, IPC, application, search, and process sources"

make_fixture() {
  local name="$1"
  local fixture="$scratch/$name"

  mkdir -p "$fixture"
  cp -R "$ROOT/default/ultimate/product-contracts/." "$fixture/"
  printf '%s\n' "$fixture"
}

mutate_fixture() {
  local fixture="$1"
  local mutation="$2"

  python - "$fixture" "$mutation" <<'PY'
import copy
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
mutation = sys.argv[2]

def load(name):
    path = root / name
    return path, json.loads(path.read_text(encoding="utf-8"))

def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")

surfaces_path, surfaces = load("surfaces-v0.json")
invocations_path, invocations = load("invocations-v0.json")
ipc_path, ipc = load("ipc-v0.json")
applications_path, applications = load("applications-v0.json")
search_path, search = load("search-v0.json")
processes_path, processes = load("processes-v0.json")

if mutation == "duplicate-route":
    invocations["routes"].append(copy.deepcopy(invocations["routes"][0]))
    save(invocations_path, invocations)
elif mutation == "missing-monitor-semantics":
    del invocations["routes"][0]["monitorSemanticsId"]
    save(invocations_path, invocations)
elif mutation == "missing-focus-semantics":
    del invocations["routes"][0]["focusSemanticsId"]
    save(invocations_path, invocations)
elif mutation == "fake-application-presence":
    app = next(item for item in applications["applications"] if item["id"] == "app.omarchy.basecamp")
    app["availability"] = "present-contract"
    save(applications_path, applications)
elif mutation == "mutating-search-without-authority":
    provider = next(item for item in search["providers"] if item["id"] == "search.run-apps-and-command")
    provider["availability"] = "present-contract"
    provider["normalizedResult"] = True
    provider["provenance"] = "complete"
    action = next(item for item in provider["actions"] if item["id"] == "action.run.execute-command")
    action["eligibleForNormalizedSearch"] = True
    action["capabilityIds"] = []
    action["humanRoutes"] = []
    save(search_path, search)
elif mutation == "consumer-claims-process":
    component = next(item for item in processes["invocationComponents"] if item["id"] == "component.ultimate-run")
    component["claimsProcessOwnership"] = True
    save(processes_path, processes)
elif mutation == "broken-manifest-path":
    surfaces["plugins"][0]["manifestPath"] = "shell/plugins/agents/not-real.json"
    save(surfaces_path, surfaces)
elif mutation == "unregistered-plugin":
    surfaces["plugins"] = [item for item in surfaces["plugins"] if item["pluginId"] != "omarchy.agents"]
    save(surfaces_path, surfaces)
elif mutation == "stale-ipc-methods":
    endpoint = next(item for item in ipc["endpoints"] if item["target"] == "shell")
    endpoint["methods"] = [item for item in endpoint["methods"] if item != "summon"]
    save(ipc_path, ipc)
elif mutation == "duplicate-desktop-id":
    applications["applications"][1]["desktopIds"] = [applications["applications"][0]["desktopIds"][0]]
    save(applications_path, applications)
elif mutation == "absent-provider-fake-implementation":
    provider = next(item for item in search["providers"] if item["id"] == "search.settings")
    provider["implementationPaths"] = ["shell/plugins/ultimate-settings/Settings.qml"]
    save(search_path, search)
else:
    raise SystemExit(f"unknown mutation: {mutation}")
PY
}

assert_rejected() {
  local mutation="$1"
  local expected="$2"
  local fixture
  local output
  local status

  fixture=$(make_fixture "$mutation")
  mutate_fixture "$fixture" "$mutation"

  set +e
  output=$(OMARCHY_PATH="$ROOT" bash "$checker" --root "$ROOT" --contracts-dir "$fixture" 2>&1)
  status=$?
  set -e

  (( status == 1 )) || fail "product-contract checker rejects $mutation" "$output"
  [[ $output == *"$expected"* ]] || fail "product-contract checker explains $mutation" "$output"
  pass "product-contract checker rejects $mutation"
}

assert_rejected "duplicate-route" "duplicate surface route id: route.surface.omarchy.agents"
assert_rejected "missing-monitor-semantics" "is missing valid monitor semantics"
assert_rejected "missing-focus-semantics" "is missing valid focus semantics"
assert_rejected "fake-application-presence" "application app.omarchy.basecamp falsely claims stable presence"
assert_rejected "mutating-search-without-authority" "mutating search action action.run.execute-command has no capability id"
assert_rejected "consumer-claims-process" "consumer UI component.ultimate-run falsely claims process ownership"
assert_rejected "broken-manifest-path" "plugin omarchy.agents manifest names a missing path"
assert_rejected "unregistered-plugin" "unregistered first-party plugins: omarchy.agents"
assert_rejected "stale-ipc-methods" "IPC target shell methods changed"
assert_rejected "duplicate-desktop-id" "duplicate normalized desktop id: basecamp"
assert_rejected "absent-provider-fake-implementation" "absent search provider search.settings falsely claims implementation"

if find "$ROOT/default/ultimate/product-contracts" "$ROOT/test/shell.d" -type d -name __pycache__ -print -quit | grep -q .; then
  fail "product-contract checks leave no Python bytecode caches"
fi
if find "$ROOT/default/ultimate/product-contracts" "$ROOT/test/shell.d" -type f -name '*.pyc' -print -quit | grep -q .; then
  fail "product-contract checks leave no compiled Python bytecode"
fi
pass "product-contract checks leave no Python bytecode artifacts"
