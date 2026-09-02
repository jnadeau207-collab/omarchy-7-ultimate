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
[[ $valid_output == *"130 capabilities"* ]] || fail "capability checker reports the complete catalog" "$valid_output"
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
if system_info.get("status") != "missing" or system_info.get("path"):
    raise SystemExit(f"system.info.read invents a System information route: {system_info}")
accessibility = by_id["accessibility.configure"]["humanRoute"]
if accessibility.get("status") != "missing" or accessibility.get("path"):
    raise SystemExit(f"accessibility.configure invents an Accessibility route: {accessibility}")
jobs_a11y = json.loads(Path(root, "default", "ultimate", "parity", "jobs.json").read_text(encoding="utf-8"))
parity_a11y = next(job for job in jobs_a11y["jobs"] if job["id"] == "parity.accessibility")
if parity_a11y.get("claim") == "present" or parity_a11y["humanRoute"].get("path"):
    raise SystemExit(f"parity.accessibility invents a present Accessibility engine: {parity_a11y}")
files_inspect = by_id["files.inspect"]["humanRoute"]
if files_inspect.get("path") != "Start > Files; Superbar > Files > Home":
    raise SystemExit(f"files.inspect invents or underclaims Files Home: {files_inspect}")
if by_id["files.inspect"].get("availability", {}).get("claim") == "present":
    raise SystemExit("files.inspect must not mark Files Home AVAILABLE")
this_pc = by_id["files.this-pc.open"]["humanRoute"]
if this_pc.get("path") != "Start > Computer; Superbar > Files > Computer":
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
if "processes.inspect" in by_id:
    raise SystemExit("processes.inspect remains as a catalog invent")
for row in readers["capabilities"] + writers["capabilities"]:
    provider = row.get("provider") or {}
    if provider.get("id") == "processes.provider":
        raise SystemExit(f"{row.get('id')} invents processes.provider: {provider}")
    if provider.get("id") == "process.provider" and row.get("id") not in {"process.inspect", "process.termination.plan"}:
        raise SystemExit(f"{row.get('id')} invents a process.provider leftover: {row}")
parity_task_manager = next(job for job in jobs_lock["jobs"] if job["id"] == "parity.task-manager")
if parity_task_manager.get("claim") == "present" or parity_task_manager["humanRoute"].get("path"):
    raise SystemExit(f"parity.task-manager invents a Superbar Task Manager: {parity_task_manager}")
if "processes.inspect" in (parity_task_manager.get("capabilityIds") or []):
    raise SystemExit("parity.task-manager still names processes.inspect")
if "process.inspect" not in (parity_task_manager.get("capabilityIds") or []):
    raise SystemExit("parity.task-manager does not name process.inspect")
native26 = next(job for job in jobs_lock["jobs"] if job["id"] == "windows-native.26")
if native26["humanRoute"].get("path"):
    raise SystemExit(f"windows-native.26 invents a Superbar Task Manager: {native26['humanRoute']}")
if native26.get("claim") == "present":
    raise SystemExit(f"windows-native.26 was flipped to present: {native26}")
if native26.get("capabilityIds") != ["process.inspect"]:
    raise SystemExit(f"windows-native.26 capabilityIds are {native26.get('capabilityIds')}")
desktop_icons = by_id["desktop.icons.manage"]["humanRoute"]
if desktop_icons.get("status") != "missing" or desktop_icons.get("path"):
    raise SystemExit(f"desktop.icons.manage invents a desktop destination: {desktop_icons}")
desktop_menu = by_id["desktop.context-menu.open"]["humanRoute"]
if desktop_menu.get("status") != "missing" or desktop_menu.get("path"):
    raise SystemExit(f"desktop.context-menu.open invents a desktop context-menu API: {desktop_menu}")
if "process.inspect" not in by_id:
    raise SystemExit("absent honest process reader invent: process.inspect missing from catalog")
process_inspect = by_id["process.inspect"]
if process_inspect.get("provider", {}).get("id") != "process.provider":
    raise SystemExit(f"process.inspect provider is {process_inspect.get('provider')}")
if process_inspect.get("provider", {}).get("state") != "present":
    raise SystemExit(f"process.inspect provider state is {process_inspect.get('provider')}")
if process_inspect.get("availability", {}).get("claim") == "present":
    raise SystemExit("process.inspect must not claim present")
if process_inspect.get("availability", {}).get("human") == "present":
    raise SystemExit("process.inspect must not claim human present / Task Manager present")
if process_inspect.get("provider", {}).get("state") == "legacy-direct":
    raise SystemExit("process.inspect leftover legacy-direct invent")
process_inspect_route = process_inspect["humanRoute"]
if process_inspect_route.get("status") != "planned" or process_inspect_route.get("path"):
    raise SystemExit(f"process.inspect invents an Administration Task Manager: {process_inspect_route}")
if "Task Manager" in str(process_inspect_route.get("surface") or ""):
    raise SystemExit(f"process.inspect invents a Task Manager surface: {process_inspect_route}")
if process_inspect.get("source", {}).get("file") != "default/fabric/omarchy_fabric/providers/process/provider.py":
    raise SystemExit(f"process.inspect source is {process_inspect.get('source')}")
if process_inspect.get("source", {}).get("symbol") != "build_provider":
    raise SystemExit(f"process.inspect source is {process_inspect.get('source')}")
named_process = f"{process_inspect.get('source', {}).get('file') or ''} {process_inspect.get('source', {}).get('symbol') or ''}".lower()
if "btop" in named_process:
    raise SystemExit(f"process.inspect still names btop: {process_inspect.get('source')}")
if "process.termination.plan" not in by_id:
    raise SystemExit("absent live End Task writer invent: process.termination.plan missing from catalog")
termination = by_id["process.termination.plan"]
if termination.get("provider", {}).get("id") != "process.provider":
    raise SystemExit(f"process.termination.plan provider is {termination.get('provider')}")
if termination.get("provider", {}).get("state") != "present":
    raise SystemExit(f"process.termination.plan provider state is {termination.get('provider')}")
if termination.get("availability", {}).get("claim") == "present":
    raise SystemExit("process.termination.plan must not claim present")
if termination.get("availability", {}).get("human") == "present":
    raise SystemExit("process.termination.plan must not claim human present / LIVE CONTROL")
if termination.get("consent", {}).get("mode") != "high-risk":
    raise SystemExit(f"process.termination.plan consent is not consequential: {termination.get('consent')}")
termination_route = termination["humanRoute"]
if termination_route.get("status") != "planned" or termination_route.get("path"):
    raise SystemExit(f"process.termination.plan invents an End Task destination: {termination_route}")
if "Task Manager" in str(termination_route.get("surface") or ""):
    raise SystemExit(f"process.termination.plan invents a Task Manager surface: {termination_route}")
if termination.get("source", {}).get("file") != "shell/apps/ultimate-administration/AdministrationApplication.qml":
    raise SystemExit(f"process.termination.plan source is {termination.get('source')}")
if termination.get("source", {}).get("symbol") != "endTask":
    raise SystemExit(f"process.termination.plan source is {termination.get('source')}")
if "process.termination.plan" not in (parity_task_manager.get("capabilityIds") or []):
    raise SystemExit("parity.task-manager does not name process.termination.plan")
startup = by_id["apps.startup.disable"]["humanRoute"]
if startup.get("status") != "missing" or startup.get("path"):
    raise SystemExit(f"apps.startup.disable invents a Task Manager Startup page: {startup}")
native27 = next(job for job in jobs_lock["jobs"] if job["id"] == "windows-native.27")
if native27["humanRoute"].get("path"):
    raise SystemExit(f"windows-native.27 invents a Task Manager Startup page: {native27['humanRoute']}")
resources = by_id["resources.inspect"]["humanRoute"]
if resources.get("status") != "missing" or resources.get("path"):
    raise SystemExit(f"resources.inspect invents a Resource Monitor destination: {resources}")
parity_resources = next(job for job in jobs_lock["jobs"] if job["id"] == "parity.resource-monitor")
if parity_resources.get("claim") == "present" or parity_resources["humanRoute"].get("path"):
    raise SystemExit(f"parity.resource-monitor invents a Task Manager Resource Monitor: {parity_resources}")
admin_readers = {
    "account.inspect": "Administration > Accounts",
    "device.inspect": "Administration > Devices",
    "firewall.inspect": "Administration > Firewall and Sharing",
    "printer.inspect": "Administration > Devices and Printers",
    "schedule.inspect": "Administration > Services and Schedules",
    "service.inspect": "Administration > Services and Schedules",
    "storage.inspect": "Administration > Storage",
}
for capability_id, path in admin_readers.items():
    row = by_id[capability_id]
    route = row["humanRoute"]
    if row.get("availability", {}).get("claim") == "present":
        raise SystemExit(f"{capability_id} invents a present Administration page: {row.get('availability')}")
    if route.get("status") != "planned" or route.get("path") != path:
        raise SystemExit(f"{capability_id} Administration route is {route}")
    if path.startswith(("Settings", "Start", "Superbar")):
        raise SystemExit(f"{capability_id} invents a Settings/Start/Superbar Administration page: {route}")

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
for row in writers["capabilities"] + readers["capabilities"] + jobs["jobs"]:
    route = row.get("humanRoute") or {}
    path = route.get("path") or ""
    if invented_settings_or_start(path):
        raise SystemExit(f"{row.get('id')} invents a Settings or Start path: {route}")
    if "Task Manager" in path:
        raise SystemExit(f"{row.get('id')} invents a Task Manager destination: {route}")

agent_center = next(job for job in jobs["jobs"] if job["id"] == "parity.agent-center")
if agent_center.get("claim") == "present" or agent_center.get("agentAvailability") == "present":
    raise SystemExit(f"parity.agent-center was flipped to present: {agent_center}")

if "apps.defaults.set" in by_id:
    raise SystemExit("apps.defaults.set remains as a catalog invent")
protocol_set = by_id["defaults.protocol.set"]
if protocol_set.get("provider", {}).get("id") != "defaults.provider":
    raise SystemExit(f"defaults.protocol.set provider is {protocol_set.get('provider')}")
if protocol_set.get("provider", {}).get("state") != "present":
    raise SystemExit(f"defaults.protocol.set provider state is {protocol_set.get('provider')}")
if protocol_set.get("availability", {}).get("claim") == "present":
    raise SystemExit("defaults.protocol.set must not claim present")
if protocol_set["humanRoute"].get("path") != "Settings > Apps":
    raise SystemExit(f"defaults.protocol.set route is {protocol_set.get('humanRoute')}")
if protocol_set.get("source", {}).get("file") != "shell/apps/ultimate-settings/SettingsApplication.qml":
    raise SystemExit(f"defaults.protocol.set source is {protocol_set.get('source')}")
for row in writers["capabilities"]:
    provider = row.get("provider") or {}
    if provider.get("id") == "apps.provider" and provider.get("state") == "present":
        raise SystemExit(f"{row.get('id')} invents apps.provider present")
parity_defaults = next(job for job in jobs["jobs"] if job["id"] == "parity.default-programs")
if parity_defaults.get("claim") == "present":
    raise SystemExit(f"parity.default-programs was flipped to present: {parity_defaults}")
if parity_defaults.get("sourceStatus") != "prototype":
    raise SystemExit(f"parity.default-programs sourceStatus is {parity_defaults.get('sourceStatus')}")
if "apps.defaults.set" in (parity_defaults.get("capabilityIds") or []):
    raise SystemExit("parity.default-programs still names apps.defaults.set")
if "defaults.protocol.set" not in (parity_defaults.get("capabilityIds") or []):
    raise SystemExit("parity.default-programs does not name defaults.protocol.set")
if by_id["files.associations.set"].get("availability", {}).get("claim") == "present":
    raise SystemExit("files.associations.set must not claim present")
parity_file_associations = next(job for job in jobs["jobs"] if job["id"] == "parity.file-associations")
if parity_file_associations.get("claim") == "present":
    raise SystemExit(f"parity.file-associations was flipped to present: {parity_file_associations}")
if "apps.defaults.set" in (parity_file_associations.get("capabilityIds") or []):
    raise SystemExit("parity.file-associations still names apps.defaults.set")
native19 = next(job for job in jobs["jobs"] if job["id"] == "windows-native.19")
if native19.get("claim") == "present":
    raise SystemExit(f"windows-native.19 was flipped to present: {native19}")
if native19.get("capabilityIds") != ["defaults.protocol.set"]:
    raise SystemExit(f"windows-native.19 capabilityIds are {native19.get('capabilityIds')}")

if "files.folder.create" in by_id:
    raise SystemExit("files.folder.create remains as a catalog invent")
directory_create = by_id["files.directory.create"]
if directory_create.get("provider", {}).get("id") != "files.provider":
    raise SystemExit(f"files.directory.create provider is {directory_create.get('provider')}")
if directory_create.get("provider", {}).get("state") != "present":
    raise SystemExit(f"files.directory.create provider state is {directory_create.get('provider')}")
if directory_create.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.directory.create must not claim present")
if directory_create["humanRoute"].get("path") != "Files > New Folder":
    raise SystemExit(f"files.directory.create route is {directory_create.get('humanRoute')}")
if directory_create.get("source", {}).get("file") != "shell/apps/ultimate-files/FilesApplication.qml":
    raise SystemExit(f"files.directory.create source is {directory_create.get('source')}")
if directory_create.get("source", {}).get("symbol") != "createFolder":
    raise SystemExit(f"files.directory.create source is {directory_create.get('source')}")
named_create = f"{directory_create.get('source', {}).get('file') or ''} {directory_create.get('source', {}).get('symbol') or ''}".lower()
if "nautilus" in named_create:
    raise SystemExit(f"files.directory.create still names Nautilus: {directory_create.get('source')}")
parity_explorer = next(job for job in jobs["jobs"] if job["id"] == "parity.explorer-this-pc")
if parity_explorer.get("claim") == "present":
    raise SystemExit(f"parity.explorer-this-pc was flipped to present: {parity_explorer}")
if "files.folder.create" in (parity_explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc still names files.folder.create")
if "files.directory.create" not in (parity_explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc does not name files.directory.create")
native10 = next(job for job in jobs["jobs"] if job["id"] == "windows-native.10")
if native10.get("claim") == "present":
    raise SystemExit(f"windows-native.10 was flipped to present: {native10}")
if native10.get("capabilityIds") != ["files.directory.create"]:
    raise SystemExit(f"windows-native.10 capabilityIds are {native10.get('capabilityIds')}")
if by_id["files.entry.rename"].get("availability", {}).get("claim") == "present":
    raise SystemExit("files.entry.rename must not claim present")
if "files.entry.trash" not in by_id:
    raise SystemExit("absent live trash writer invent: files.entry.trash missing from catalog")
entry_trash = by_id["files.entry.trash"]
if entry_trash.get("provider", {}).get("id") != "files.provider":
    raise SystemExit(f"files.entry.trash provider is {entry_trash.get('provider')}")
if entry_trash.get("provider", {}).get("state") != "present":
    raise SystemExit(f"files.entry.trash provider state is {entry_trash.get('provider')}")
if entry_trash.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.entry.trash must not claim present")
if entry_trash.get("consent", {}).get("mode") != "high-risk":
    raise SystemExit(f"files.entry.trash consent is not consequential: {entry_trash.get('consent')}")
if entry_trash["humanRoute"].get("path") != "Files > Delete":
    raise SystemExit(f"files.entry.trash route is {entry_trash.get('humanRoute')}")
if entry_trash.get("source", {}).get("file") != "shell/apps/ultimate-files/FilesApplication.qml":
    raise SystemExit(f"files.entry.trash source is {entry_trash.get('source')}")
if entry_trash.get("source", {}).get("symbol") != "trashEntry":
    raise SystemExit(f"files.entry.trash source is {entry_trash.get('source')}")
named_trash = f"{entry_trash.get('source', {}).get('file') or ''} {entry_trash.get('source', {}).get('symbol') or ''}".lower()
if "nautilus" in named_trash:
    raise SystemExit(f"files.entry.trash still names Nautilus: {entry_trash.get('source')}")
if "files.entry.trash" not in (parity_explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc does not name files.entry.trash")
parity_recycle = next(job for job in jobs["jobs"] if job["id"] == "parity.desktop-icons-wallpaper-context-menu-recycle")
if parity_recycle.get("claim") == "present":
    raise SystemExit(f"parity.desktop-icons-wallpaper-context-menu-recycle was flipped to present: {parity_recycle}")
if "files.entry.trash" not in (parity_recycle.get("capabilityIds") or []):
    raise SystemExit("parity.desktop-icons-wallpaper-context-menu-recycle does not name files.entry.trash")
if "files.trash.manage" not in (parity_recycle.get("capabilityIds") or []):
    raise SystemExit("parity.desktop-icons-wallpaper-context-menu-recycle dropped files.trash.manage")
trash_manage = by_id["files.trash.manage"]
if trash_manage.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.trash.manage must not claim present")
if trash_manage.get("provider", {}).get("state") != "provider-missing":
    raise SystemExit(f"files.trash.manage was raised off missing: {trash_manage.get('provider')}")
restore = by_id.get("files.trash.restore")
if restore and restore.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.trash.restore invents Restore LIVE")
PY
pass "leftover catalog routes stay honest after Settings inspect hosting"

python3 - "$ROOT" <<'PY' || fail "Settings/Admin/Files catalog soft invents stay locked closed"
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
readers = json.loads((root / "default/ultimate/capabilities/catalog-provider-readers-v0.json").read_text(encoding="utf-8"))
writers = json.loads((root / "default/ultimate/capabilities/catalog-system-jobs-v0.json").read_text(encoding="utf-8"))
jobs = json.loads((root / "default/ultimate/parity/jobs.json").read_text(encoding="utf-8"))
catalog_rows = readers["capabilities"] + writers["capabilities"]
by_id = {row["id"]: row for row in catalog_rows}

leftover_invent_ids = (
    "processes.inspect",
    "files.folder.create",
    "apps.defaults.set",
)
for leftover_id in leftover_invent_ids:
    if leftover_id in by_id:
        raise SystemExit(f"{leftover_id} remains as a catalog invent")
    for job in jobs["jobs"]:
        if leftover_id in (job.get("capabilityIds") or []):
            raise SystemExit(f"{job.get('id')} still names leftover invent {leftover_id}")

for row in writers["capabilities"]:
    provider = row.get("provider") or {}
    if provider.get("id") == "apps.provider" and provider.get("state") == "present":
        raise SystemExit(f"{row.get('id')} invents apps.provider present")

for row in catalog_rows:
    provider = row.get("provider") or {}
    capability_id = row.get("id") or ""
    if not (capability_id.startswith("process.") or provider.get("id") == "process.provider"):
        continue
    route = row.get("humanRoute") or {}
    named = f"{route.get('surface') or ''} {route.get('path') or ''}"
    if "Task Manager" in named:
        raise SystemExit(f"{capability_id} invents a Task Manager surface on a process.* route: {route}")

inventory = {
    "audio.volume.set": "partial",
    "network.manage": "partial",
    "power.profile.set": "partial",
    "display.configure": "partial",
    "input.keyboard-layout.set": "partial",
    "defaults.protocol.set": "partial",
    "files.directory.create": "partial",
    "files.entry.trash": "partial",
    "process.inspect": "missing",
    "process.termination.plan": "missing",
}
for capability_id, claim in inventory.items():
    row = by_id.get(capability_id)
    if row is None:
        raise SystemExit(f"locked inventory id missing from catalog: {capability_id}")
    actual = (row.get("availability") or {}).get("claim")
    if actual != claim:
        raise SystemExit(f"{capability_id} availability.claim is {actual!r}, expected locked {claim!r}")
    if actual == "present":
        raise SystemExit(f"{capability_id} walked claim to present")
PY
pass "Settings/Admin/Files catalog soft invents stay locked closed"

if find "$ROOT/default/ultimate/capabilities" "$ROOT/default/ultimate/capability-schema" "$ROOT/default/ultimate/parity" "$ROOT/test/shell.d" -type d -name __pycache__ -print -quit | grep -q .; then
  fail "capability graph checks leave no Python bytecode caches"
fi
if find "$ROOT/default/ultimate/capabilities" "$ROOT/default/ultimate/capability-schema" "$ROOT/default/ultimate/parity" "$ROOT/test/shell.d" -type f -name '*.pyc' -print -quit | grep -q .; then
  fail "capability graph checks leave no compiled Python bytecode"
fi
pass "capability graph checks leave no Python bytecode artifacts"
