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
  fail "python-jsonschema is required to certify the capability catalog lock"
fi

valid_output=$(OMARCHY_PATH="$ROOT" bash "$checker" --root "$ROOT")
[[ $valid_output == *"129 capabilities"* ]] || fail "capability checker reports the complete catalog" "$valid_output"
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
readers_path, readers = load("default/ultimate/capabilities/catalog-provider-readers-v0.json")
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
elif mutation == "unregistered-builtin-reader":
    readers["capabilities"] = [
        item for item in readers["capabilities"] if item["id"] != "files.inspect"
    ]
    save(readers_path, readers)
elif mutation == "phantom-inspect-reader":
    capability = next(item for item in readers["capabilities"] if item["id"] == "packages.catalog.inspect")
    capability["id"] = "packages.inspect"
    save(readers_path, readers)
elif mutation == "reader-agent-available":
    readers["capabilities"][0]["availability"]["agent"] = "present"
    save(readers_path, readers)
elif mutation == "reader-empty-redaction":
    readers["capabilities"][0]["redaction"]["fields"] = []
    save(readers_path, readers)
elif mutation == "window-agent-without-entry":
    window_path, window = load("default/ultimate/capabilities/catalog-window-v0.json")
    capability = next(item for item in window["capabilities"] if item["id"] == "window.maximize")
    capability["source"]["brokerVerb"] = ""
    save(window_path, window)
elif mutation == "window-agent-claim-present":
    window_path, window = load("default/ultimate/capabilities/catalog-window-v0.json")
    capability = next(item for item in window["capabilities"] if item["id"] == "window.maximize")
    capability["availability"]["claim"] = "present"
    save(window_path, window)
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
assert_rejected "unregistered-builtin-reader" "unregistered builtin provider readers: files.provider"
assert_rejected "phantom-inspect-reader" "capability packages.inspect is not on the packages.provider manifest"
assert_rejected "reader-agent-available" "must keep availability.agent unavailable"
assert_rejected "reader-empty-redaction" "has empty redaction.fields"
assert_rejected "window-agent-without-entry" "window capability window.maximize has availability.agent present without a CapabilityBroker verb"
assert_rejected "window-agent-claim-present" "window capability window.maximize claims present while the broker is an actor-label allowlist"

python3 - "$ROOT" <<'PY' || fail "leftover catalog routes stay honest after Settings inspect hosting"
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
readers = json.loads((root / "default/ultimate/capabilities/catalog-provider-readers-v0.json").read_text(encoding="utf-8"))
writers = json.loads((root / "default/ultimate/capabilities/catalog-system-jobs-v0.json").read_text(encoding="utf-8"))
by_id = {row["id"]: row for row in readers["capabilities"] + writers["capabilities"]}

inspect_routes = {
    "audio.inspect": ("Settings", "Settings > Sound"),
    "bluetooth.inspect": ("Settings", "Settings > Bluetooth"),
    "display.inspect": ("Settings", "Settings > Display"),
    "input.inspect": ("Settings", "Settings > Input"),
    "network.inspect": ("Settings", "Settings > Network"),
    "power.inspect": ("Settings", "Settings > Power"),
    "defaults.inspect": ("Settings", "Settings > Apps"),
    "update.inspect": ("Settings", "Settings > Update"),
    "recovery.inspect": ("Settings", "Settings > Recovery"),
}
for capability_id, (surface, path) in inspect_routes.items():
    route = by_id[capability_id]["humanRoute"]
    if route.get("surface") != surface or route.get("path") != path:
        raise SystemExit(f"{capability_id} inspect route is {route}")

writer_routes = {
    "audio.output.manage": ("Quick Settings", "Superbar > Quick Settings > Sound"),
    "audio.volume.set": ("Quick Settings", "Superbar > Quick Settings > Sound"),
    "bluetooth.audio.pair": ("Quick Settings", "Superbar > Quick Settings > Bluetooth"),
    "display.configure": ("Quick Settings", "Superbar > Quick Settings > Display"),
    "network.manage": ("Quick Settings", "Superbar > Quick Settings > Network"),
    "network.wifi.connect": ("Quick Settings", "Superbar > Quick Settings > Wi-Fi"),
    "power.profile.set": ("Quick Settings", "Superbar > Quick Settings > Power"),
}
for capability_id, (surface, path) in writer_routes.items():
    route = by_id[capability_id]["humanRoute"]
    if route.get("surface") != surface or route.get("path") != path:
        raise SystemExit(f"{capability_id} writer route is {route}")

locale = by_id["locale.configure"]["humanRoute"]
if locale.get("status") != "planned" or locale.get("path"):
    raise SystemExit(f"locale.configure invents a Settings page: {locale}")

system_info = by_id["system.info.read"]["humanRoute"]
if (
    system_info.get("status") != "missing"
    or system_info.get("path") != "Settings jump list > System information"
):
    raise SystemExit(f"system.info.read route is {system_info}")
accessibility = by_id["accessibility.configure"]["humanRoute"]
if (
    accessibility.get("status") != "missing"
    or accessibility.get("path") != "Settings jump list > Accessibility"
):
    raise SystemExit(f"accessibility.configure invents or underclaims Accessibility: {accessibility}")
jobs_a11y = json.loads(Path(root, "default", "ultimate", "parity", "jobs.json").read_text(encoding="utf-8"))
parity_a11y = next(job for job in jobs_a11y["jobs"] if job["id"] == "parity.accessibility")
if parity_a11y.get("claim") == "present" or parity_a11y["humanRoute"].get("path") != "Settings jump list > Accessibility":
    raise SystemExit(f"parity.accessibility invents a present Accessibility engine: {parity_a11y}")
this_pc = by_id["files.this-pc.open"]["humanRoute"]
if this_pc.get("path") != "Start > Computer; Superbar > Files > This PC":
    raise SystemExit(f"files.this-pc.open invents or underclaims This PC: {this_pc}")
downloads = by_id["files.downloads.open"]
if downloads["humanRoute"].get("path") != "Start > Downloads; Superbar > Files > Downloads":
    raise SystemExit(f"files.downloads.open invents or underclaims Downloads: {downloads['humanRoute']}")
if downloads.get("source", {}).get("file") != "bin/omarchy-launch-files":
    raise SystemExit(f"files.downloads.open still names an absent Files launcher: {downloads.get('source')}")
if "nautilus" in str(downloads.get("source", {}).get("symbol") or "").lower():
    raise SystemExit(f"files.downloads.open still names Nautilus: {downloads.get('source')}")
for row in writers["capabilities"]:
    capability_id = row.get("id") or ""
    if capability_id in {"files.this-pc.open", "files.downloads.open"}:
        source = row.get("source") or {}
        named = f"{source.get('file') or ''} {source.get('symbol') or ''}".lower()
        if "nautilus" in named:
            raise SystemExit(f"{capability_id} still names Nautilus for a published Files location: {source}")
        if source.get("file") != "bin/omarchy-launch-files":
            raise SystemExit(f"{capability_id} does not name product Files: {source}")
jobs_lock = json.loads(Path(root, "default", "ultimate", "parity", "jobs.json").read_text(encoding="utf-8"))
native9 = next(job for job in jobs_lock["jobs"] if job["id"] == "windows-native.9")
if native9["humanRoute"].get("path") != "Start > Downloads; Superbar > Files > Downloads":
    raise SystemExit(f"windows-native.9 still names Superbar Files without Start Downloads: {native9['humanRoute']}")
native38 = next(job for job in jobs_lock["jobs"] if job["id"] == "windows-native.38")
if native38["humanRoute"].get("path") != "Settings jump list > System information":
    raise SystemExit(f"windows-native.38 invents a Start System page: {native38['humanRoute']}")
processes = by_id["processes.inspect"]["humanRoute"]
if processes.get("status") != "planned" or processes.get("path"):
    raise SystemExit(f"processes.inspect invents a Task Manager destination: {processes}")
parity_task_manager = next(job for job in jobs_lock["jobs"] if job["id"] == "parity.task-manager")
if parity_task_manager.get("claim") == "present" or parity_task_manager["humanRoute"].get("path"):
    raise SystemExit(f"parity.task-manager invents a Superbar Task Manager: {parity_task_manager}")
native26 = next(job for job in jobs_lock["jobs"] if job["id"] == "windows-native.26")
if native26["humanRoute"].get("path"):
    raise SystemExit(f"windows-native.26 invents a Superbar Task Manager: {native26['humanRoute']}")
desktop_icons = by_id["desktop.icons.manage"]["humanRoute"]
if desktop_icons.get("status") != "missing" or desktop_icons.get("path"):
    raise SystemExit(f"desktop.icons.manage invents a desktop destination: {desktop_icons}")
desktop_menu = by_id["desktop.context-menu.open"]["humanRoute"]
if desktop_menu.get("status") != "missing" or desktop_menu.get("path"):
    raise SystemExit(f"desktop.context-menu.open invents a desktop context-menu API: {desktop_menu}")

allowed_settings_pages = {
    "Personalization", "Network", "Sound", "Display", "Power", "Apps",
    "Update", "Recovery", "Input", "Bluetooth", "Accessibility", "System",
}
invented_start_prefixes = (
    "Start > Backup and Restore",
    "Start > Services",
    "Start > Task Scheduler",
    "Start > Software Center",
    "Start > Compatibility Center",
    "Start > System Restore",
    "Start > Troubleshooting",
    "Start > Settings > System",
)

def invented_settings_or_start(path):
    if not path:
        return False
    if any(path.startswith(prefix) or f"; {prefix}" in path for prefix in invented_start_prefixes):
        return True
    for part in (segment.strip() for segment in path.split(";")):
        if part.startswith("Start > Settings > "):
            leaf = part[len("Start > Settings > "):].strip()
        elif part.startswith("Settings > "):
            leaf = part[len("Settings > "):].strip()
        else:
            continue
        if leaf and leaf not in allowed_settings_pages:
            return True
    return False

jobs = json.loads(Path(root, "default", "ultimate", "parity", "jobs.json").read_text(encoding="utf-8"))
for row in writers["capabilities"] + jobs["jobs"]:
    route = row.get("humanRoute") or {}
    if invented_settings_or_start(route.get("path") or ""):
        raise SystemExit(f"{row.get('id')} invents a Settings or Start path: {route}")

agent_center = next(job for job in jobs["jobs"] if job["id"] == "parity.agent-center")
if agent_center.get("claim") == "present" or agent_center.get("agentAvailability") == "present":
    raise SystemExit(f"parity.agent-center was flipped to present: {agent_center}")
PY
pass "leftover catalog routes stay honest after Settings inspect hosting"

if find "$ROOT/default/ultimate/capabilities" "$ROOT/default/ultimate/capability-schema" "$ROOT/default/ultimate/parity" "$ROOT/test/shell.d" -type d -name __pycache__ -print -quit | grep -q .; then
  fail "capability graph checks leave no Python bytecode caches"
fi
if find "$ROOT/default/ultimate/capabilities" "$ROOT/default/ultimate/capability-schema" "$ROOT/default/ultimate/parity" "$ROOT/test/shell.d" -type f -name '*.pyc' -print -quit | grep -q .; then
  fail "capability graph checks leave no compiled Python bytecode"
fi
pass "capability graph checks leave no Python bytecode artifacts"
