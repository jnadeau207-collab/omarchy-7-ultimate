#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PYTHONDONTWRITEBYTECODE=1

checker="$ROOT/bin/omarchy-dev-capability-check"
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

(( dependency_status == 2 )) || fail "capability checker has a dedicated dependency failure" "$dependency_output"
[[ $dependency_output == *"python-jsonschema is required"* ]] || fail "capability checker names the missing python-jsonschema dependency" "$dependency_output"
pass "capability checker fails clearly without python-jsonschema"

if ! python -c 'import jsonschema' >/dev/null 2>&1; then
  pass "planned python-jsonschema dependency is unavailable; semantic fixture checks are deferred"
  exit 0
fi

valid_output=$(OMARCHY_PATH="$ROOT" bash "$checker" --root "$ROOT")
[[ $valid_output == *"104 capabilities"* ]] || fail "capability checker reports the complete catalog" "$valid_output"
[[ $valid_output == *"39 writers: 21 broker, 18 legacy"* ]] || fail "capability checker reports the exact WindowService writer inventory" "$valid_output"
[[ $valid_output == *"window IPC 40 paths (36 direct legacy)"* ]] || fail "capability checker reports every window IPC route" "$valid_output"
[[ $valid_output == *"42 parity jobs; 40 Windows-native tasks"* ]] || fail "capability checker reports both complete job sources" "$valid_output"
pass "capability graph validates against live source and both job manifests"

make_fixture() {
  local name="$1"
  local fixture="$scratch/$name"

  mkdir -p "$fixture/default/ultimate"
  cp -R "$ROOT/default/ultimate/capability-schema" "$fixture/default/ultimate/capability-schema"
  cp -R "$ROOT/default/ultimate/capabilities" "$fixture/default/ultimate/capabilities"
  cp -R "$ROOT/default/ultimate/parity" "$fixture/default/ultimate/parity"
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


def load(relative):
    path = root / relative
    return path, json.loads(path.read_text(encoding="utf-8"))


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


system_path, system = load("default/ultimate/capabilities/catalog-system-jobs-v0.json")
surface_path, surface = load("default/ultimate/capabilities/window-surface-v0.json")
debt_path, debt = load("default/ultimate/capabilities/legacy-debt-v0.json")
jobs_path, jobs = load("default/ultimate/parity/jobs.json")

if mutation == "duplicate-capability":
    system["capabilities"].append(copy.deepcopy(system["capabilities"][0]))
    save(system_path, system)
elif mutation == "broken-capability-ref":
    jobs["jobs"][0]["capabilityIds"][0] = "broken.capability"
    save(jobs_path, jobs)
elif mutation == "broken-schema-ref":
    system["capabilities"][0]["schemas"]["input"]["$ref"] = "urn:omarchy:ultimate:capability-schema:contract-types-v0#/$defs/not-real"
    save(system_path, system)
elif mutation == "destructive-without-safeguards":
    capability = next(item for item in system["capabilities"] if item["id"] == "os.install")
    capability["schemas"]["preflight"]["$ref"] = "urn:omarchy:ultimate:capability-schema:contract-types-v0#/$defs/notApplicable"
    capability["consent"]["mode"] = "implicit"
    capability["recovery"] = {
        "mode": "none",
        "expectation": "No recovery.",
        "stateFingerprintRequired": False,
    }
    save(system_path, system)
elif mutation == "capability-false-present":
    capability = next(item for item in system["capabilities"] if item["id"] == "desktop.icons.manage")
    capability["availability"]["claim"] = "present"
    save(system_path, system)
elif mutation == "job-false-present":
    job = next(item for item in jobs["jobs"] if item["id"] == "parity.agent-center")
    job["claim"] = "present"
    save(jobs_path, jobs)
elif mutation == "agent-only-mutation":
    capability = next(item for item in system["capabilities"] if item["id"] == "desktop.icons.manage")
    capability["availability"]["agent"] = "present"
    capability["availability"]["human"] = "missing"
    capability["humanRoute"] = {
        "status": "missing",
        "surface": "Desktop",
        "label": "Manage desktop icons",
        "path": "",
    }
    save(system_path, system)
elif mutation == "unregistered-service-mutation":
    surface["serviceMethods"] = [item for item in surface["serviceMethods"] if item["name"] != "togglePin"]
    save(surface_path, surface)
elif mutation == "unregistered-ipc-mutation":
    surface["ipcPaths"] = [item for item in surface["ipcPaths"] if item["name"] != "taskView"]
    save(surface_path, surface)
elif mutation == "missing-debt-coverage":
    entry = next(item for item in debt["entries"] if item["id"] == "legacy.window-service.public-writers")
    entry["surfaceRefs"].remove("window-service:togglePin")
    save(debt_path, debt)
elif mutation == "schema-violation":
    system["capabilities"][0]["provider"]["state"] = "optimistic"
    save(system_path, system)
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
  output=$(OMARCHY_PATH="$ROOT" bash "$checker" --root "$ROOT" --data-root "$fixture" 2>&1)
  status=$?
  set -e

  (( status == 1 )) || fail "capability checker rejects $mutation" "$output"
  [[ $output == *"$expected"* ]] || fail "capability checker explains $mutation" "$output"
  pass "capability checker rejects $mutation"
}

assert_rejected "duplicate-capability" "duplicate capability id: desktop.icons.manage"
assert_rejected "broken-capability-ref" "job parity.desktop-icons-wallpaper-context-menu-recycle has broken capability reference: broken.capability"
assert_rejected "broken-schema-ref" "broken schema reference in capability desktop.icons.manage schema input"
assert_rejected "destructive-without-safeguards" "destructive capability os.install has no preflight schema"
assert_rejected "capability-false-present" "capability desktop.icons.manage falsely claims present without a present provider"
assert_rejected "job-false-present" "job parity.agent-center falsely claims present"
assert_rejected "agent-only-mutation" "agent mutation desktop.icons.manage has no visible human route"
assert_rejected "unregistered-service-mutation" "unregistered WindowService public methods: togglePin"
assert_rejected "unregistered-ipc-mutation" "unregistered window IPC paths: taskView"
assert_rejected "missing-debt-coverage" "legacy debt legacy.window-service.public-writers does not cover surface window-service:togglePin"
assert_rejected "schema-violation" "provider.state: 'optimistic' is not one of"

if find "$ROOT/default/ultimate/capabilities" "$ROOT/default/ultimate/capability-schema" "$ROOT/default/ultimate/parity" "$ROOT/test/shell.d" -type d -name __pycache__ -print -quit | grep -q .; then
  fail "capability graph checks leave no Python bytecode caches"
fi
if find "$ROOT/default/ultimate/capabilities" "$ROOT/default/ultimate/capability-schema" "$ROOT/default/ultimate/parity" "$ROOT/test/shell.d" -type f -name '*.pyc' -print -quit | grep -q .; then
  fail "capability graph checks leave no compiled Python bytecode"
fi
pass "capability graph checks leave no Python bytecode artifacts"
