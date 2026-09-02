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
[[ $valid_output == *"132 capabilities"* ]] || fail "capability checker reports the complete catalog" "$valid_output"
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
    "bluetooth.audio.pair": ("Quick Settings", "Superbar > Quick Settings > Bluetooth"),
    "display.configure": ("Quick Settings", "Superbar > Quick Settings > Display"),
    "display.night-light.set": ("Quick Settings", "Superbar > Quick Settings > Night light"),
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
if process_inspect_route.get("status") != "visible":
    raise SystemExit(f"process.inspect underclaims a visible Administration Processes host: {process_inspect_route}")
if process_inspect_route.get("surface") != "Administration" or process_inspect_route.get("path") != "Administration > Processes":
    raise SystemExit(f"process.inspect invents or underclaims a Task Manager destination: {process_inspect_route}")
if not str(process_inspect_route.get("path") or "").strip():
    raise SystemExit(f"process.inspect underclaims with an empty Administration path: {process_inspect_route}")
if "Task Manager" in str(process_inspect_route.get("surface") or "") or "Task Manager" in str(process_inspect_route.get("path") or ""):
    raise SystemExit(f"process.inspect invents a Task Manager surface: {process_inspect_route}")
if "Superbar" in str(process_inspect_route.get("path") or "") or "Superbar" in str(process_inspect_route.get("surface") or ""):
    raise SystemExit(f"process.inspect invents a Superbar Task Manager: {process_inspect_route}")
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
if termination_route.get("status") != "visible":
    raise SystemExit(f"process.termination.plan underclaims a visible Administration End Task host: {termination_route}")
if termination_route.get("surface") != "Administration" or termination_route.get("path") != "Administration > Processes":
    raise SystemExit(f"process.termination.plan invents or underclaims an End Task destination: {termination_route}")
if not str(termination_route.get("path") or "").strip():
    raise SystemExit(f"process.termination.plan underclaims with an empty Administration path: {termination_route}")
if "Task Manager" in str(termination_route.get("surface") or "") or "Task Manager" in str(termination_route.get("path") or ""):
    raise SystemExit(f"process.termination.plan invents a Task Manager surface: {termination_route}")
if "Superbar" in str(termination_route.get("path") or "") or "Superbar" in str(termination_route.get("surface") or ""):
    raise SystemExit(f"process.termination.plan invents a Superbar Task Manager: {termination_route}")
if termination.get("source", {}).get("file") != "shell/apps/ultimate-administration/AdministrationApplication.qml":
    raise SystemExit(f"process.termination.plan source is {termination.get('source')}")
if termination.get("source", {}).get("symbol") != "endTask":
    raise SystemExit(f"process.termination.plan source is {termination.get('source')}")
if "process.termination.plan" not in (parity_task_manager.get("capabilityIds") or []):
    raise SystemExit("parity.task-manager does not name process.termination.plan")
admin_coverage = (root / "shell/apps/ultimate-administration/AdministrationModel.js").read_text(encoding="utf-8")
if "Ending a task is wired through the durable operation service but is declared consequential, which the shell principal cannot authorize." not in admin_coverage:
    raise SystemExit("Administration Processes coverage must keep End Task unauthorized")
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
    "account.inspect": "Administration > User accounts",
    "backup.inspect": "Administration > Backup",
    "device.inspect": "Administration > Device Manager",
    "diagnostics.inspect": "Administration > Troubleshooting",
    "firewall.inspect": "Administration > Firewall",
    "printer.inspect": "Administration > Printers and scanners",
    "schedule.inspect": "Administration > Scheduled tasks",
    "service.inspect": "Administration > Services",
    "storage.inspect": "Administration > Storage",
}
for capability_id, path in admin_readers.items():
    row = by_id[capability_id]
    route = row["humanRoute"]
    if row.get("availability", {}).get("claim") != "missing":
        raise SystemExit(f"{capability_id} availability.claim is {row.get('availability')}, expected missing")
    if row.get("availability", {}).get("human") == "present":
        raise SystemExit(f"{capability_id} invents a present Administration page: {row.get('availability')}")
    if route.get("status") != "visible":
        raise SystemExit(f"{capability_id} underclaims a visible Administration host: {route}")
    if route.get("surface") != "Administration" or route.get("path") != path:
        raise SystemExit(f"{capability_id} invents or underclaims an Administration destination: {route}")
    if not str(route.get("path") or "").strip():
        raise SystemExit(f"{capability_id} underclaims with an empty Administration path: {route}")
    if "Task Manager" in str(route.get("surface") or "") or "Task Manager" in str(route.get("path") or ""):
        raise SystemExit(f"{capability_id} invents a Superbar Task Manager: {route}")
    if "Superbar" in str(route.get("path") or "") or "Superbar" in str(route.get("surface") or ""):
        raise SystemExit(f"{capability_id} invents a Superbar Task Manager: {route}")
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
if agent_center.get("claim") != "prototype":
    raise SystemExit(f"parity.agent-center.claim is {agent_center.get('claim')!r}, expected prototype")
if agent_center.get("sourceStatus") != "prototype":
    raise SystemExit(f"parity.agent-center sourceStatus is {agent_center.get('sourceStatus')}")
agent_center_route = agent_center.get("humanRoute") or {}
if agent_center_route.get("status") != "visible":
    raise SystemExit(f"parity.agent-center underclaims a visible Superbar host: {agent_center_route}")
if agent_center_route.get("path") != "Superbar > Agent Center":
    raise SystemExit(f"parity.agent-center invents or underclaims Agent Center route: {agent_center_route}")
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
mime_set = by_id["defaults.mime.set"]
if mime_set.get("provider", {}).get("id") != "defaults.provider":
    raise SystemExit(f"defaults.mime.set provider is {mime_set.get('provider')}")
if mime_set.get("provider", {}).get("state") != "present":
    raise SystemExit(f"defaults.mime.set provider state is {mime_set.get('provider')}")
if mime_set.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"defaults.mime.set claim is {mime_set.get('availability')}")
if mime_set.get("availability", {}).get("claim") == "present":
    raise SystemExit("defaults.mime.set must not claim present")
if mime_set["humanRoute"].get("status") != "planned":
    raise SystemExit(f"defaults.mime.set invents a Settings MIME setter route: {mime_set.get('humanRoute')}")
if mime_set["humanRoute"].get("path"):
    raise SystemExit(f"defaults.mime.set invents a Settings MIME setter path: {mime_set.get('humanRoute')}")
if mime_set.get("source", {}).get("file") != "default/fabric/omarchy_fabric/helpers/session_apply.py":
    raise SystemExit(f"defaults.mime.set source is {mime_set.get('source')}")
if mime_set.get("source", {}).get("symbol") != "apply_defaults_mime_set":
    raise SystemExit(f"defaults.mime.set source is {mime_set.get('source')}")
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
if "defaults.mime.set" not in (parity_file_associations.get("capabilityIds") or []):
    raise SystemExit("parity.file-associations does not name defaults.mime.set")
if parity_file_associations.get("humanRoute", {}).get("status") != "planned":
    raise SystemExit(f"parity.file-associations walked off planned: {parity_file_associations.get('humanRoute')}")
native19 = next(job for job in jobs["jobs"] if job["id"] == "windows-native.19")
if native19.get("claim") == "present":
    raise SystemExit(f"windows-native.19 was flipped to present: {native19}")
if native19.get("capabilityIds") != ["defaults.protocol.set"]:
    raise SystemExit(f"windows-native.19 capabilityIds are {native19.get('capabilityIds')}")

volume_set = by_id["audio.volume.set"]
if volume_set.get("provider", {}).get("id") != "audio.provider":
    raise SystemExit(f"audio.volume.set provider is {volume_set.get('provider')}")
if volume_set.get("provider", {}).get("state") != "present":
    raise SystemExit(f"audio.volume.set provider state is {volume_set.get('provider')}")
if volume_set.get("availability", {}).get("claim") == "present":
    raise SystemExit("audio.volume.set must not claim present")
if volume_set["humanRoute"].get("path") != "Settings > Sound":
    raise SystemExit(f"audio.volume.set route is {volume_set.get('humanRoute')}")
if volume_set.get("source", {}).get("file") != "shell/apps/ultimate-settings/SettingsApplication.qml":
    raise SystemExit(f"audio.volume.set source is {volume_set.get('source')}")
if volume_set.get("source", {}).get("symbol") != "applyAudioVolume":
    raise SystemExit(f"audio.volume.set source is {volume_set.get('source')}")
named_volume = f"{volume_set.get('source', {}).get('file') or ''} {volume_set.get('source', {}).get('symbol') or ''}".lower()
if "omarchy-audio-output-volume" in named_volume:
    raise SystemExit(f"audio.volume.set still names the leftover volume command: {volume_set.get('source')}")
native6 = next(job for job in jobs["jobs"] if job["id"] == "windows-native.6")
if native6.get("claim") == "present":
    raise SystemExit(f"windows-native.6 was flipped to present: {native6}")
if native6.get("capabilityIds") != ["audio.volume.set"]:
    raise SystemExit(f"windows-native.6 capabilityIds are {native6.get('capabilityIds')}")
if native6["humanRoute"].get("path") != "Settings > Sound":
    raise SystemExit(f"windows-native.6 still names Superbar Sound: {native6['humanRoute']}")

layout_set = by_id["input.keyboard-layout.set"]
if layout_set.get("provider", {}).get("id") != "input.provider":
    raise SystemExit(f"input.keyboard-layout.set provider is {layout_set.get('provider')}")
if layout_set.get("provider", {}).get("state") != "present":
    raise SystemExit(f"input.keyboard-layout.set provider state is {layout_set.get('provider')}")
if layout_set.get("availability", {}).get("claim") == "present":
    raise SystemExit("input.keyboard-layout.set must not claim present")
if layout_set["humanRoute"].get("path") != "Settings > Input":
    raise SystemExit(f"input.keyboard-layout.set route is {layout_set.get('humanRoute')}")
if layout_set.get("source", {}).get("file") != "shell/apps/ultimate-settings/SettingsApplication.qml":
    raise SystemExit(f"input.keyboard-layout.set source is {layout_set.get('source')}")
if layout_set.get("source", {}).get("symbol") != "applyKeyboardLayout":
    raise SystemExit(f"input.keyboard-layout.set source is {layout_set.get('source')}")
named_layout = f"{layout_set.get('source', {}).get('file') or ''} {layout_set.get('source', {}).get('symbol') or ''}".lower()
if "keyboardlayout.qml" in named_layout:
    raise SystemExit(f"input.keyboard-layout.set still names the bar widget: {layout_set.get('source')}")

wifi_radio = by_id["network.manage"]
if wifi_radio.get("provider", {}).get("id") != "network.provider":
    raise SystemExit(f"network.manage provider is {wifi_radio.get('provider')}")
if wifi_radio.get("provider", {}).get("state") != "present":
    raise SystemExit(f"network.manage provider state is {wifi_radio.get('provider')}")
if wifi_radio.get("availability", {}).get("claim") == "present":
    raise SystemExit("network.manage must not claim present")
if wifi_radio["humanRoute"].get("path") != "Settings > Network":
    raise SystemExit(f"network.manage route is {wifi_radio.get('humanRoute')}")
if wifi_radio.get("source", {}).get("file") != "shell/apps/ultimate-settings/SettingsApplication.qml":
    raise SystemExit(f"network.manage source is {wifi_radio.get('source')}")
if wifi_radio.get("source", {}).get("symbol") != "applyWifiEnabled":
    raise SystemExit(f"network.manage source is {wifi_radio.get('source')}")
if "connect" in str(wifi_radio.get("humanRoute", {}).get("label") or "").lower():
    raise SystemExit(f"network.manage invents join-network as Settings LIVE: {wifi_radio.get('humanRoute')}")
named_wifi = f"{wifi_radio.get('source', {}).get('file') or ''} {wifi_radio.get('source', {}).get('symbol') or ''}".lower()
if "panel.qml" in named_wifi:
    raise SystemExit(f"network.manage still names the QS network panel: {wifi_radio.get('source')}")
wifi_connect = by_id["network.wifi.connect"]
if wifi_connect["humanRoute"].get("surface") != "Quick Settings" or wifi_connect["humanRoute"].get("path") != "Superbar > Quick Settings > Wi-Fi":
    raise SystemExit(f"network.wifi.connect invents a Settings join-network route: {wifi_connect.get('humanRoute')}")
if wifi_connect.get("availability", {}).get("claim") == "present":
    raise SystemExit("network.wifi.connect must not claim present")
if wifi_connect.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"network.wifi.connect was raised off leftover: {wifi_connect.get('provider')}")
native2 = next(job for job in jobs["jobs"] if job["id"] == "windows-native.2")
if native2.get("claim") == "present":
    raise SystemExit(f"windows-native.2 was flipped to present: {native2}")
if native2.get("capabilityIds") != ["network.wifi.connect"]:
    raise SystemExit(f"windows-native.2 capabilityIds are {native2.get('capabilityIds')}")
if "Settings" in str(native2["humanRoute"].get("path") or ""):
    raise SystemExit(f"windows-native.2 invents Settings Connect Wi-Fi: {native2['humanRoute']}")

if "display.brightness.set" not in by_id:
    raise SystemExit("absent live brightness writer invent: display.brightness.set missing from catalog")
brightness_set = by_id["display.brightness.set"]
if brightness_set.get("provider", {}).get("id") != "display.provider":
    raise SystemExit(f"display.brightness.set provider is {brightness_set.get('provider')}")
if brightness_set.get("provider", {}).get("state") != "present":
    raise SystemExit(f"display.brightness.set provider state is {brightness_set.get('provider')}")
if brightness_set.get("availability", {}).get("claim") == "present":
    raise SystemExit("display.brightness.set must not claim present")
if brightness_set["humanRoute"].get("path") != "Settings > Display":
    raise SystemExit(f"display.brightness.set route is {brightness_set.get('humanRoute')}")
if brightness_set.get("source", {}).get("file") != "shell/apps/ultimate-settings/SettingsApplication.qml":
    raise SystemExit(f"display.brightness.set source is {brightness_set.get('source')}")
if brightness_set.get("source", {}).get("symbol") != "applyBrightness":
    raise SystemExit(f"display.brightness.set source is {brightness_set.get('source')}")
display_configure = by_id["display.configure"]
if display_configure["humanRoute"].get("surface") != "Quick Settings" or display_configure["humanRoute"].get("path") != "Superbar > Quick Settings > Display":
    raise SystemExit(f"display.configure invents a Settings full-configure route: {display_configure.get('humanRoute')}")
if display_configure.get("availability", {}).get("claim") == "present":
    raise SystemExit("display.configure must not claim present")
if display_configure.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"display.configure was raised off leftover: {display_configure.get('provider')}")
if display_configure.get("source", {}).get("file") != "shell/plugins/panels/monitor/Panel.qml":
    raise SystemExit(f"display.configure source is {display_configure.get('source')}")
native3 = next(job for job in jobs["jobs"] if job["id"] == "windows-native.3")
if native3.get("claim") == "present":
    raise SystemExit(f"windows-native.3 was flipped to present: {native3}")
if native3.get("capabilityIds") != ["display.configure"]:
    raise SystemExit(f"windows-native.3 capabilityIds are {native3.get('capabilityIds')}")
if "Settings" in str(native3["humanRoute"].get("path") or ""):
    raise SystemExit(f"windows-native.3 invents Settings display scaling: {native3['humanRoute']}")
parity_display = next(job for job in jobs["jobs"] if job["id"] == "parity.display")
if parity_display.get("claim") == "present":
    raise SystemExit(f"parity.display was flipped to present: {parity_display}")
if "display.brightness.set" not in (parity_display.get("capabilityIds") or []):
    raise SystemExit("parity.display does not name display.brightness.set")
if "display.configure" not in (parity_display.get("capabilityIds") or []):
    raise SystemExit("parity.display dropped display.configure")
if "display.night-light.set" not in (parity_display.get("capabilityIds") or []):
    raise SystemExit("parity.display dropped display.night-light.set")

night_light = by_id["display.night-light.set"]
if night_light["humanRoute"].get("status") != "visible":
    raise SystemExit(f"display.night-light.set underclaims a visible QS tile: {night_light.get('humanRoute')}")
if night_light["humanRoute"].get("surface") != "Quick Settings" or night_light["humanRoute"].get("path") != "Superbar > Quick Settings > Night light":
    raise SystemExit(f"display.night-light.set invents a Settings night-light route: {night_light.get('humanRoute')}")
if night_light.get("availability", {}).get("claim") == "present":
    raise SystemExit("display.night-light.set must not claim present")
if night_light.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"display.night-light.set was raised off leftover: {night_light.get('provider')}")
if night_light.get("source", {}).get("file") != "shell/plugins/services/nightlight/Service.qml":
    raise SystemExit(f"display.night-light.set source is {night_light.get('source')}")
if night_light.get("source", {}).get("symbol") != "NightlightService":
    raise SystemExit(f"display.night-light.set source is {night_light.get('source')}")
night_light_path = str(night_light["humanRoute"].get("path") or "")
if night_light_path.startswith("Settings") or "Start > Settings" in night_light_path:
    raise SystemExit(f"display.night-light.set invents Settings night-light LIVE: {night_light.get('humanRoute')}")
settings_app = (root / "shell/apps/ultimate-settings/SettingsApplication.qml").read_text(encoding="utf-8")
if "nightlight" in settings_app.lower() or "night-light" in settings_app.lower() or "night light" in settings_app.lower():
    raise SystemExit("Settings invents night-light LIVE")
settings_coverage = (root / "shell/apps/ultimate-settings/SettingsModel.js").read_text(encoding="utf-8")
if "Night light remains a Superbar leftover, not a Settings LIVE writer." not in settings_coverage:
    raise SystemExit("Settings Display coverage must refuse night-light LIVE")
native34 = next(job for job in jobs["jobs"] if job["id"] == "windows-native.34")
if native34.get("claim") == "present":
    raise SystemExit(f"windows-native.34 was flipped to present: {native34}")
if native34.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.34 sourceStatus is {native34.get('sourceStatus')}")
if native34.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.34 proofStatus is {native34.get('proofStatus')}")
if native34.get("capabilityIds") != ["display.night-light.set"]:
    raise SystemExit(f"windows-native.34 capabilityIds are {native34.get('capabilityIds')}")
if native34["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.34 underclaims a visible QS tile: {native34.get('humanRoute')}")
if native34["humanRoute"].get("path") != "Superbar > Quick Settings > Night light":
    raise SystemExit(f"windows-native.34 invents Settings night-light LIVE: {native34['humanRoute']}")
native34_path = str(native34["humanRoute"].get("path") or "")
if native34_path.startswith("Settings") or "Start > Settings" in native34_path:
    raise SystemExit(f"windows-native.34 invents Settings night-light LIVE: {native34['humanRoute']}")
parity_modern = next(job for job in jobs["jobs"] if job["id"] == "parity.modern-display-scaling-hdr-night-light")
if parity_modern.get("claim") == "present":
    raise SystemExit(f"parity.modern-display-scaling-hdr-night-light was flipped to present: {parity_modern}")
if "display.night-light.set" not in (parity_modern.get("capabilityIds") or []):
    raise SystemExit("parity.modern-display-scaling-hdr-night-light dropped display.night-light.set")

power_set = by_id["power.profile.set"]
if power_set["humanRoute"].get("surface") != "Quick Settings" or power_set["humanRoute"].get("path") != "Superbar > Quick Settings > Power":
    raise SystemExit(f"power.profile.set invents Settings Power LIVE: {power_set.get('humanRoute')}")
if power_set.get("availability", {}).get("claim") == "present":
    raise SystemExit("power.profile.set must not claim present")
if power_set.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"power.profile.set was raised off leftover: {power_set.get('provider')}")
if power_set.get("source", {}).get("file") != "shell/plugins/panels/power/Panel.qml":
    raise SystemExit(f"power.profile.set source is {power_set.get('source')}")
native35 = next(job for job in jobs["jobs"] if job["id"] == "windows-native.35")
if native35.get("claim") == "present":
    raise SystemExit(f"windows-native.35 was flipped to present: {native35}")
if native35.get("capabilityIds") != ["power.profile.set"]:
    raise SystemExit(f"windows-native.35 capabilityIds are {native35.get('capabilityIds')}")
if "Settings" in str(native35["humanRoute"].get("path") or ""):
    raise SystemExit(f"windows-native.35 invents Settings Power LIVE: {native35['humanRoute']}")
gaps = (root / "plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md").read_text(encoding="utf-8")
if "unverified on metal" not in gaps or "power.profile.set" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep power.profile.set as a Superbar leftover that was unverified on metal")
if "20484de6" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite METAL_HEAD tip 20484de6 for the QS Power leftover")
if "Not authorized" not in gaps or "session-5103" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite QS Power metal FAIL pkcheck Not authorized / session-5103")
if "batteryPresent" not in gaps or "amd_pstate" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite QS Power metal FAIL batteryPresent and amd_pstate")
if "heritage QS Power works on metal" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented heritage QS Power works on metal")
if "KEEP OPEN" not in gaps or "honesty-gated" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep QS Power leftover OPEN / honesty-gated")
if "Settings Power LIVE stays refused" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep Settings Power LIVE refused")
if "display.night-light.set" not in gaps or "Settings does not invent night-light LIVE" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep the QS night-light leftover visible without Settings LIVE")
if "process.termination.plan" not in gaps or "Administration > Processes" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must name the visible Administration End Task host without LIVE")
if "shell principal cannot authorize" not in gaps or "UI stays unauthorized" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep End Task write plane unauthorized")
if "process.inspect" not in gaps or "administration.processes.overview" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must name the visible Administration process.inspect host")
if "honest-unavailable as Task Manager product" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep process.inspect honest-unavailable as Task Manager product")
parity_md = (root / "WINDOWS_7_ULTIMATE_PARITY.md").read_text(encoding="utf-8")
if "planned Administration empty path" in parity_md:
    raise SystemExit("PARITY Task Manager row still underclaims process.inspect as planned empty path")
if "service.inspect" not in gaps or "Administration > Services" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must name the visible Administration inspect leftover batch")
if "honest-unavailable as Device Manager / Services / product" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep Administration inspect readers honest-unavailable as product")
if "planned as Administration > Devices" in parity_md or "planned as Administration > Accounts" in parity_md:
    raise SystemExit("PARITY still underclaims Administration inspect readers as planned Admin paths")
if "No Firewall Settings surface" in parity_md:
    raise SystemExit("PARITY Firewall row still underclaims Administration > Firewall as absent")
if "No Backup and Restore UI" in parity_md:
    raise SystemExit("PARITY Backup & Restore row still underclaims Administration > Backup as absent")
if "57726ecc40d8" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #36 Administration inspect catalog tip for this PARITY batch")
if "honest-unavailable as product" not in gaps or "do not flip system-job writers to visible" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep this PARITY Admin inspect batch honest-unavailable as product")
if "85281460af3d" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #37 tip parent for the 06 Settings/Admin media honesty scrub")
if "06-settings-admin-media" not in gaps or "defaults.protocol.set" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the 06 Settings/Admin media honesty close")
if "Phase 5/9 exit criteria still open" not in gaps or "inspect inventory ≠ product MMC present" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep Phase 5/9 exit open and inspect inventory not product MMC")
if "apps.defaults.set" not in gaps or "leftover `apps.defaults.set`" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must name leftover apps.defaults.set as closed invent")
if "3b0b8b39b35e" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #38 tip parent for the project-ultimate honesty scrub")
if "plans/project-ultimate.md" not in gaps or "planned with an empty path" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the project-ultimate Superbar process.inspect underclaim close")
if "23b7f41be69c" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #39 tip parent for the fleet-catalog-controlpanel honesty scrub")
if "fleet-catalog-controlpanel.md" not in gaps or "planned empty path" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the fleet-catalog-controlpanel process.inspect underclaim close")
if "a1b0e5029997" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #40 tip parent for the agent-center claim honesty scrub")
if "consent/provider ops stay outside Agent Center" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the agent-center claim=prototype honesty close")
if "Agent Center claim present" in gaps and "no Agent Center claim present" not in gaps:
    raise SystemExit("fleet-doctrine-gaps invented Agent Center claim present")
if "d3f4841a496ea5fd9618b269ca268d922516434a" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the metal tip SHA for Settings coverage-badge PIXEL leftover CLOSED")
if "254e23636ef3" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #43 tip parent for the PARITY QS Power metal FAIL honesty twin")
if "not a metal proof" not in gaps or "WINDOWS_7_ULTIMATE_PARITY.md" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the PARITY Power Options not-a-metal-proof underclaim close")
if "plans/project-ultimate.md" not in gaps or "PARITY / project-ultimate QS Power leftover after PR #43" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the project-ultimate QS Power unverified-without-FAIL underclaim close")
if "cabc8e042cc1" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #44 tip parent for the product-docs QS Power metal FAIL honesty twin")
if "HANDOFF_WRITERS_2026-09-01.md" not in gaps or "HANDOFF_STATE_DOMAIN_WRITES_2026-09-01.md" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the writers/state-domain handoff QS Power underclaim close")
if "settings-service-api.md" not in gaps or "ultimate-settings-writers-test.sh" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the settings-api / writers-test QS Power underclaim close")
if "Settings badge METAL_HEAD residual OPEN" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the Settings badge METAL_HEAD residual OPEN underclaim close")
if "Product docs / handoffs QS Power leftover after PR #44" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the product-docs QS Power unverified-without-FAIL underclaim close")
if "62c95ebae058" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #45 tip parent for the powerprofiles-set-test QS Power honesty twin")
if "Process-test QS Power leftover after PR #45" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the powerprofiles-set-test QS Power underclaim close")
if "2804e464daa9" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #46 tip parent for the focused-stale inspect residual")
if "Focused out-of-band stale inspect residual OPEN" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry Focused out-of-band stale inspect residual OPEN")
if "Focused out-of-band stale inspect residual OPEN after PR #46" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the focused-stale leftover after PR #46")
if "authorityFooter()" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must name Settings authorityFooter() for the focused-stale residual")
if "No `events.subscribe`" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep No `events.subscribe` on the focused-stale residual")
if "surface-visible / local-writer only" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep surface-visible / local-writer refresh as those paths only")
if "closed focused stale" in gaps:
    raise SystemExit("fleet-doctrine-gaps still claims focused stale was closed")
if "events.subscribe present" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented events.subscribe present")
if "hardware-key subscription LIVE" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented hardware-key subscription LIVE")
if "bb2e71d9625f" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #47 tip parent for the Task Manager present / End Task LIVE residual")
if "Task Manager present / End Task LIVE residual OPEN" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry Task Manager present / End Task LIVE residual OPEN")
if "Task Manager present / End Task LIVE residual OPEN after PR #47" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the Task Manager leftover after PR #47")
if "Superbar > Task Manager present" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented Superbar > Task Manager present")
if "Task Manager product-complete" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented Task Manager product-complete")
if "Task Manager leftover CLOSED" in gaps:
    raise SystemExit("fleet-doctrine-gaps closed the Task Manager present / End Task LIVE residual")
if "End Task LIVE residual CLOSED" in gaps:
    raise SystemExit("fleet-doctrine-gaps closed the End Task LIVE residual")
if "End Task LIVE CONTROL" in gaps and "no End Task LIVE CONTROL" not in gaps:
    raise SystemExit("fleet-doctrine-gaps invented End Task LIVE CONTROL")
if "0352cd3087ec" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #48 tip parent for the Recycle Bin / files.trash.manage residual")
if "Recycle Bin / files.trash.manage residual OPEN" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry Recycle Bin / files.trash.manage residual OPEN")
if "Recycle Bin / files.trash.manage residual OPEN after PR #48" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the Recycle leftover after PR #48")
if "Empty Bin LIVE" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented Empty Bin LIVE")
if "files.trash.manage present" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented files.trash.manage present")
if "Recycle product-complete" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented Recycle product-complete")
if "Recycle leftover CLOSED" in gaps:
    raise SystemExit("fleet-doctrine-gaps closed the Recycle Bin / files.trash.manage residual")
if "files.trash.manage residual CLOSED" in gaps:
    raise SystemExit("fleet-doctrine-gaps closed the files.trash.manage residual")
if "Recycle Bin leftover CLOSED" in gaps:
    raise SystemExit("fleet-doctrine-gaps closed the Recycle Bin leftover")
if "Restore LIVE" in gaps and "Do not invent Restore LIVE" not in gaps and "Do not invent a LIVE Restore" not in gaps:
    raise SystemExit("fleet-doctrine-gaps invented Restore LIVE")
if "13ca963b08f74a" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the PR #49 tip parent for the MIME / Default Programs association UI residual")
if "MIME / Default Programs association UI residual OPEN" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry MIME / Default Programs association UI residual OPEN")
if "MIME / Default Programs association UI residual OPEN after PR #49" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must carry the MIME leftover after PR #49")
if "MIME UI present" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented MIME UI present")
if "MIME association UI present" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented MIME association UI present")
if "full Default Programs LIVE" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented full Default Programs LIVE")
if "association manager LIVE" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented association manager LIVE")
if "Default Programs product-complete" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented Default Programs product-complete")
if "MIME leftover CLOSED" in gaps:
    raise SystemExit("fleet-doctrine-gaps closed the MIME / Default Programs association UI residual")
if "MIME association UI residual CLOSED" in gaps:
    raise SystemExit("fleet-doctrine-gaps closed the MIME association UI residual")
if "Default Programs leftover CLOSED" in gaps:
    raise SystemExit("fleet-doctrine-gaps closed the Default Programs leftover")
if "`defaults.mime.set` write plane is reachable" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the reachable defaults.mime.set write plane")
if "association.inspect" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite published association.inspect apply re-read")
if "Settings does not offer MIME LIVE CONTROL" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep Settings MIME LIVE CONTROL refused")
if "defaults.inspect" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must name MIME inspect via defaults.inspect")

def parity_notes(label):
    prefix = f"| {label} |"
    for line in parity_md.splitlines():
        if line.startswith(prefix):
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) < 3:
                raise SystemExit(f"PARITY {label} row is malformed: {line}")
            return cells[1], cells[2]
    raise SystemExit(f"PARITY missing {label} row")

parity_hosts = {
    "Firewall": ("plumbing", "Administration > Firewall", "firewall.inspect", "Firewall Settings"),
    "Backup & Restore": ("plumbing", "Administration > Backup", "backup.inspect", "Backup and Restore"),
    "Services": ("missing", "Administration > Services", "service.inspect", "Services"),
    "Task Scheduler": ("missing", "Administration > Scheduled tasks", "schedule.inspect", "Task Scheduler"),
    "Disk Management": ("missing", "Administration > Storage", "storage.inspect", "Disk Management"),
    "Devices & Printers": ("missing / prototype", "Administration > Printers and scanners", "printer.inspect", "Devices and Printers"),
}
for label, (status, host, capability, product) in parity_hosts.items():
    row_status, notes = parity_notes(label)
    if row_status != status:
        raise SystemExit(f"PARITY {label} status walked off {status}: {row_status}")
    if status == "present" or row_status == "present":
        raise SystemExit(f"PARITY {label} was flipped to present")
    if not notes:
        raise SystemExit(f"PARITY {label} still underclaims with an empty notes cell")
    if host not in notes:
        raise SystemExit(f"PARITY {label} does not name {host}")
    if capability not in notes:
        raise SystemExit(f"PARITY {label} does not name {capability}")
    if "honest-unavailable" not in notes:
        raise SystemExit(f"PARITY {label} does not keep inspect honest-unavailable as product")
    if f"as {product} product" not in notes:
        raise SystemExit(f"PARITY {label} does not keep {product} honest-unavailable as product")
    if "this row is not present" not in notes:
        raise SystemExit(f"PARITY {label} dropped the not-present close")
    if label == "Devices & Printers" and ("bluetooth.inspect" not in notes or "Settings → Bluetooth" not in notes):
        raise SystemExit("PARITY Devices & Printers dropped the Bluetooth Settings story")

file_assoc_status, file_assoc_notes = parity_notes("File associations")
if file_assoc_status != "missing as product":
    raise SystemExit(f"PARITY File associations status walked off missing as product: {file_assoc_status}")
if file_assoc_status == "present":
    raise SystemExit("PARITY File associations was flipped to present")
if not file_assoc_notes:
    raise SystemExit("PARITY File associations still underclaims with an empty notes cell")
if "defaults.inspect" not in file_assoc_notes:
    raise SystemExit("PARITY File associations does not name defaults.inspect MIME inventory")
if "defaults.mime.set" not in file_assoc_notes:
    raise SystemExit("PARITY File associations does not name defaults.mime.set")
if "Settings does not offer MIME LIVE CONTROL" not in file_assoc_notes:
    raise SystemExit("PARITY File associations invented or dropped MIME LIVE CONTROL honesty")
if "files.associations.set" not in file_assoc_notes or "missing/planned MIME" not in file_assoc_notes:
    raise SystemExit("PARITY File associations dropped files.associations.set missing/planned MIME")
if "this row is not present" not in file_assoc_notes:
    raise SystemExit("PARITY File associations dropped the not-present close")

event_status, event_notes = parity_notes("Event / history")
if event_status == "present":
    raise SystemExit("PARITY Event / history was flipped to Event Viewer present")
if "Not Event Viewer" not in event_notes:
    raise SystemExit("PARITY Event / history must stay Not Event Viewer")
if "Administration > Troubleshooting" in event_notes:
    raise SystemExit("PARITY Event / history invented Administration Troubleshooting as Event Viewer")

power_status, power_notes = parity_notes("Power Options")
if power_status == "present":
    raise SystemExit("PARITY Power Options was flipped to present")
if "not a metal proof" in power_notes:
    raise SystemExit("PARITY Power Options still underclaims leftover as not a metal proof")
if "QS Power METAL_HEAD OPEN" not in power_notes:
    raise SystemExit("PARITY Power Options must keep QS Power METAL_HEAD OPEN")
if "20484de6" not in power_notes:
    raise SystemExit("PARITY Power Options must cite metal FAIL tip 20484de6")
if "Not authorized" not in power_notes or "session-5103" not in power_notes:
    raise SystemExit("PARITY Power Options must cite metal FAIL pkcheck Not authorized / session-5103")
if "batteryPresent" not in power_notes or "amd_pstate" not in power_notes:
    raise SystemExit("PARITY Power Options must cite metal FAIL batteryPresent / amd_pstate")
if "Settings Power LIVE refused" not in power_notes:
    raise SystemExit("PARITY Power Options must keep Settings Power LIVE refused")
if "heritage QS Power works on metal" in power_notes:
    raise SystemExit("PARITY Power Options invented heritage QS Power works on metal")
if "unverified on metal" not in power_notes:
    raise SystemExit("PARITY Power Options must keep leftover was unverified on metal")
if "KEEP OPEN" not in power_notes:
    raise SystemExit("PARITY Power Options must KEEP OPEN the QS Power leftover")

fabric_status, fabric_notes = parity_notes("Agent Fabric")
if fabric_status == "present":
    raise SystemExit("PARITY Agent Fabric was flipped to present")
if "remains unverified on metal" in fabric_notes:
    raise SystemExit("PARITY Agent Fabric still underclaims Superbar Power leftover as unverified without metal FAIL")
if "QS Power METAL_HEAD OPEN" not in fabric_notes:
    raise SystemExit("PARITY Agent Fabric must keep QS Power METAL_HEAD OPEN")
if "20484de6" not in fabric_notes:
    raise SystemExit("PARITY Agent Fabric must cite metal FAIL tip 20484de6")
if "Not authorized" not in fabric_notes or "session-5103" not in fabric_notes:
    raise SystemExit("PARITY Agent Fabric must cite metal FAIL pkcheck Not authorized / session-5103")
if "batteryPresent" not in fabric_notes or "amd_pstate" not in fabric_notes:
    raise SystemExit("PARITY Agent Fabric must cite metal FAIL batteryPresent / amd_pstate")
if "KEEP OPEN" not in fabric_notes:
    raise SystemExit("PARITY Agent Fabric must KEEP OPEN the Superbar Power leftover")
if "Settings Power LIVE refused" not in fabric_notes:
    raise SystemExit("PARITY Agent Fabric must keep Settings Power LIVE refused")
if "heritage QS Power works on metal" in fabric_notes:
    raise SystemExit("PARITY Agent Fabric invented heritage QS Power works on metal")

job_claims = {
    "parity.firewall": "plumbing",
    "parity.backup-restore": "plumbing",
    "parity.services": "missing",
    "parity.task-scheduler": "missing",
    "parity.disk-management": "missing",
    "parity.devices-printers": "missing",
}
for job_id, expected_claim in job_claims.items():
    job = next(item for item in jobs_lock["jobs"] if item["id"] == job_id)
    if job.get("claim") != expected_claim:
        raise SystemExit(f"{job_id} claim walked off {expected_claim}: {job.get('claim')}")
    if job.get("claim") == "present":
        raise SystemExit(f"{job_id} was flipped to present")
    if job["humanRoute"].get("status") == "visible":
        raise SystemExit(f"{job_id} invents a visible product job from Admin inspect: {job.get('humanRoute')}")

writer_planned = {
    "firewall.manage": ("planned", "Settings"),
    "backup.manage": ("planned", "Backup and Restore"),
}
for writer_id, (status, surface) in writer_planned.items():
    writer = by_id[writer_id]
    route = writer["humanRoute"]
    if route.get("status") != status:
        raise SystemExit(f"{writer_id} humanRoute.status walked off {status}: {route}")
    if route.get("status") == "visible":
        raise SystemExit(f"{writer_id} was flipped to visible")
    if route.get("surface") != surface:
        raise SystemExit(f"{writer_id} invents a mutation surface: {route}")
    if writer.get("availability", {}).get("claim") == "present":
        raise SystemExit(f"{writer_id} walked claim to present")
if "Settings coverage-badge PIXEL leftover CLOSED" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must name Settings coverage-badge PIXEL leftover CLOSED")
if "d3f4841a" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite metal tip d3f4841a for Settings coverage-badge PIXEL leftover CLOSED")
if "28863386cf953f4b956515c7fcc7c5d35d6bc26abd7188a3f7df4b857d102b28" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite settings-sound grim sha256")
if "876fc4c9ef73eae8cc907aa01f594ac87154313f89f963a8bd3b864787d5612b" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite settings-power grim sha256")
if "PARTIAL LIVE CONTROL" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite Sound Coverage PARTIAL LIVE CONTROL")
if "Power profile **CHANGES UNAVAILABLE**" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite Power CHANGES UNAVAILABLE")
if "Settings badge pixel leftover still open pending METAL_HEAD" in gaps:
    raise SystemExit("fleet-doctrine-gaps still carries Settings badge pixel leftover OPEN")
if "Settings badge METAL_HEAD residual stays OPEN" in gaps:
    raise SystemExit("fleet-doctrine-gaps still carries Settings badge METAL_HEAD residual OPEN")
if "QS Power METAL_HEAD OPEN" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep QS Power METAL_HEAD OPEN")
if "unverified on metal" not in gaps or "power.profile.set" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep QS Power leftover that was unverified on metal")
if "20484de6e7ce93f16273c030165ed3cbbbec6c66" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the QS Power METAL_HEAD SHA 20484de6e7ce93f16273c030165ed3cbbbec6c66")
if "Not authorized" not in gaps or "session-5103" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite QS Power metal FAIL Not authorized / session-5103")
if "batteryPresent" not in gaps or "amd_pstate" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite QS Power metal FAIL batteryPresent / amd_pstate")
if "heritage QS Power works on metal" in gaps:
    raise SystemExit("fleet-doctrine-gaps invented heritage QS Power works on metal")
if "QS Power leftover CLOSED" in gaps or "QS Power METAL_HEAD CLOSED" in gaps:
    raise SystemExit("fleet-doctrine-gaps closed the QS Power METAL_HEAD leftover")
if "No `events.subscribe`" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep events.subscribe residual open")
if "Product REJECTED" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep product REJECTED")
if "/home/jesse/omarchy7ultimate-work-tip" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must cite the tip worktree for Settings coverage-badge PIXEL leftover CLOSED")

writers_handoff = (root / "HANDOFF_WRITERS_2026-09-01.md").read_text(encoding="utf-8")
if "is unverified on metal" in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS still underclaims QS Power leftover as unverified without metal FAIL")
if "do not claim METAL_HEAD" in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS still says do not claim METAL_HEAD after metal FAIL")
if "was unverified on metal" not in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS must keep leftover was unverified on metal")
if "QS Power METAL_HEAD OPEN" not in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS must keep QS Power METAL_HEAD OPEN")
if "20484de6" not in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS must cite metal FAIL tip 20484de6")
if "Not authorized" not in writers_handoff or "session-5103" not in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS must cite metal FAIL Not authorized / session-5103")
if "batteryPresent" not in writers_handoff or "amd_pstate" not in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS must cite metal FAIL batteryPresent / amd_pstate")
if "Settings Power LIVE refused" not in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS must keep Settings Power LIVE refused")
if "heritage QS Power works on metal" in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS invented heritage QS Power works on metal")
if "KEEP OPEN" not in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS must KEEP OPEN the QS Power leftover")
if "Product REJECTED" not in writers_handoff:
    raise SystemExit("HANDOFF_WRITERS must keep product REJECTED")

state_handoff = (root / "HANDOFF_STATE_DOMAIN_WRITES_2026-09-01.md").read_text(encoding="utf-8")
if "Settings badge METAL_HEAD residual stays OPEN" in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES still carries Settings badge METAL_HEAD residual OPEN")
if "No pixel leftover or METAL_HEAD claim" in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES still underclaims Settings badge PIXEL leftover as unclosed")
if "do not claim METAL_HEAD" in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES still says do not claim METAL_HEAD after metal FAIL")
if "no metal proof" in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES still underclaims QS Power leftover as no metal proof")
if "Settings coverage-badge PIXEL leftover CLOSED" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must name Settings coverage-badge PIXEL leftover CLOSED")
if "d3f4841a" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must cite metal tip d3f4841a")
if "focused out-of-band stale" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must keep focused out-of-band stale OPEN")
if "Focused out-of-band stale inspect residual OPEN" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must keep Focused out-of-band stale inspect residual OPEN")
if "authorityFooter()" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must name Settings authorityFooter() for the focused-stale residual")
if "surface-visible / local-writer only" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must keep surface-visible / local-writer refresh as those paths only")
if "closed focused stale" in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES still claims focused stale was closed")
if "events.subscribe present" in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES invented events.subscribe present")
if "hardware-key subscription LIVE" in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES invented hardware-key subscription LIVE")
if "events.subscribe" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must keep no events.subscribe residual OPEN")
if "QS Power METAL_HEAD OPEN" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must keep QS Power METAL_HEAD OPEN")
if "20484de6" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must cite metal FAIL tip 20484de6")
if "Not authorized" not in state_handoff or "session-5103" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must cite metal FAIL Not authorized / session-5103")
if "batteryPresent" not in state_handoff or "amd_pstate" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must cite metal FAIL batteryPresent / amd_pstate")
if "Settings Power LIVE refused" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must keep Settings Power LIVE refused")
if "heritage QS Power works on metal" in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES invented heritage QS Power works on metal")
if "KEEP OPEN" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must KEEP OPEN the QS Power leftover")
if "Product REJECTED" not in state_handoff:
    raise SystemExit("HANDOFF_STATE_DOMAIN_WRITES must keep product REJECTED")

settings_api = (root / "docs/settings-service-api.md").read_text(encoding="utf-8")
if "remains unverified on metal" in settings_api:
    raise SystemExit("settings-service-api still underclaims leftover as remains unverified without metal FAIL")
if "do not claim METAL_HEAD" in settings_api:
    raise SystemExit("settings-service-api still says do not claim METAL_HEAD after metal FAIL")
if "was unverified on metal" not in settings_api:
    raise SystemExit("settings-service-api must keep leftover was unverified on metal")
if "QS Power METAL_HEAD OPEN" not in settings_api:
    raise SystemExit("settings-service-api must keep QS Power METAL_HEAD OPEN")
if "20484de6" not in settings_api:
    raise SystemExit("settings-service-api must cite metal FAIL tip 20484de6")
if "Not authorized" not in settings_api or "session-5103" not in settings_api:
    raise SystemExit("settings-service-api must cite metal FAIL Not authorized / session-5103")
if "batteryPresent" not in settings_api or "amd_pstate" not in settings_api:
    raise SystemExit("settings-service-api must cite metal FAIL batteryPresent / amd_pstate")
if "Settings Power LIVE refused" not in settings_api:
    raise SystemExit("settings-service-api must keep Settings Power LIVE refused")
if "heritage QS Power works on metal" in settings_api:
    raise SystemExit("settings-service-api invented heritage QS Power works on metal")
if "KEEP OPEN" not in settings_api:
    raise SystemExit("settings-service-api must KEEP OPEN the QS Power leftover")
if "Focused out-of-band stale inspect residual OPEN" not in settings_api:
    raise SystemExit("settings-service-api must keep Focused out-of-band stale inspect residual OPEN")
if "authorityFooter()" not in settings_api:
    raise SystemExit("settings-service-api must name Settings authorityFooter() for the focused-stale residual")
if "surface-visible / local-writer only" not in settings_api:
    raise SystemExit("settings-service-api must keep surface-visible / local-writer refresh as those paths only")
if "events.subscribe" in settings_api:
    raise SystemExit("settings-service-api invented events.subscribe")
if "hardware-key subscription LIVE" in settings_api:
    raise SystemExit("settings-service-api invented hardware-key subscription LIVE")
if "LIVE hardware-key subscription" not in settings_api:
    raise SystemExit("settings-service-api must refuse inventing LIVE hardware-key subscription")

gt06 = (root / "plans/win7-ultimate-ground-truth/06-settings-admin-media.md").read_text(encoding="utf-8")
gt06_json = json.loads((root / "plans/win7-ultimate-ground-truth/06-settings-admin-media.json").read_text(encoding="utf-8"))
gt06_json_text = json.dumps(gt06_json)
if "apps.defaults.set" in gt06 or "apps.defaults.set" in gt06_json_text:
    raise SystemExit("06-settings-admin-media still names leftover apps.defaults.set as the live Apps writer")
if "defaults.protocol.set" not in gt06 or "browser LIVE only" not in gt06:
    raise SystemExit("06-settings-admin-media does not name defaults.protocol.set as browser LIVE only")
if "files.associations.set" not in gt06 or "missing/planned MIME" not in gt06:
    raise SystemExit("06-settings-admin-media dropped files.associations.set missing/planned MIME")
if "writers Phase 5" in gt06 or "Phase 5 writers remain" in gt06 or "Phase 9 Administration not started" in gt06:
    raise SystemExit("06-settings-admin-media still blankets a Phase 5/9 fence")
if "Phase 5 exit criteria still open" not in gt06 or "Phase 9 exit criteria still open" not in gt06:
    raise SystemExit("06-settings-admin-media must keep Phase 5/9 exit criteria still open")
if "live hosts today" not in gt06.lower() and "Live Administration inspect hosts today" not in gt06:
    raise SystemExit("06-settings-admin-media must name live hosts today")
admin_hosts = (
    "Administration > Processes",
    "Administration > Services",
    "Administration > Device Manager",
    "Administration > Storage",
    "Administration > Printers and scanners",
    "Administration > Backup",
    "Administration > Scheduled tasks",
    "Administration > Troubleshooting",
    "Administration > Firewall",
    "Administration > User accounts",
)
for host in admin_hosts:
    if host not in gt06:
        raise SystemExit(f"06-settings-admin-media does not name live host {host}")
if "process.inspect" not in gt06 or "unauthorized End Task" not in gt06:
    raise SystemExit("06-settings-admin-media must name process.inspect + unauthorized End Task path")
if "inspect inventory" not in gt06.lower() or "product MMC present" not in gt06:
    raise SystemExit("06-settings-admin-media must keep inspect inventory ≠ product MMC present")
if "no Task Manager present" not in gt06:
    raise SystemExit("06-settings-admin-media must refuse Task Manager present")
if "no Device Manager present" not in gt06:
    raise SystemExit("06-settings-admin-media must refuse Device Manager present")
if "no Event Viewer present" not in gt06:
    raise SystemExit("06-settings-admin-media must refuse Event Viewer present")
if "no start/stop service LIVE" not in gt06:
    raise SystemExit("06-settings-admin-media must refuse start/stop service LIVE")
if "firewall.manage" not in gt06 or "backup.manage" not in gt06:
    raise SystemExit("06-settings-admin-media must keep firewall.manage / backup.manage not LIVE")
if "Accessibility panel missing as product" not in gt06:
    raise SystemExit("06-settings-admin-media must keep Accessibility panel missing as product")
if "System information aggregate missing" not in gt06 and "System Information remains missing as product" not in gt06:
    raise SystemExit("06-settings-admin-media must keep System information aggregate missing")
if "Software Center missing as product" not in gt06:
    raise SystemExit("06-settings-admin-media must keep Software Center missing as product")
if "Settings Power LIVE refused" not in gt06:
    raise SystemExit("06-settings-admin-media must keep Settings Power LIVE refused")
if "Restore LIVE" in gt06 and "Do not invent" not in gaps:
    raise SystemExit("06-settings-admin-media invented Restore LIVE")
if "events.subscribe" in gt06:
    raise SystemExit("06-settings-admin-media invented events.subscribe")
if "METAL_HEAD closed" in gt06:
    raise SystemExit("06-settings-admin-media invented METAL_HEAD closed")
honesty = gt06_json.get("product_honesty") or {}
if honesty.get("defaults_writer") != "defaults.protocol.set":
    raise SystemExit(f"06 JSON defaults_writer is {honesty.get('defaults_writer')}")
if honesty.get("defaults_scope") != "browser LIVE only":
    raise SystemExit(f"06 JSON defaults_scope is {honesty.get('defaults_scope')}")
if honesty.get("files_associations") != "missing/planned MIME":
    raise SystemExit(f"06 JSON files_associations is {honesty.get('files_associations')}")
if honesty.get("defaults_mime_plane") != "defaults.mime.set write-plane, no Settings LIVE":
    raise SystemExit(f"06 JSON defaults_mime_plane is {honesty.get('defaults_mime_plane')}")
if honesty.get("settings_power_live") != "refused":
    raise SystemExit(f"06 JSON settings_power_live is {honesty.get('settings_power_live')}")
if honesty.get("accessibility_panel") != "missing":
    raise SystemExit(f"06 JSON accessibility_panel is {honesty.get('accessibility_panel')}")
if honesty.get("system_information_aggregate") != "missing":
    raise SystemExit(f"06 JSON system_information_aggregate is {honesty.get('system_information_aggregate')}")
if honesty.get("software_center") != "missing":
    raise SystemExit(f"06 JSON software_center is {honesty.get('software_center')}")
if honesty.get("inspect_inventory_is_product_mmc") is not False:
    raise SystemExit("06 JSON must keep inspect inventory not product MMC")
if honesty.get("phase_5_exit") != "still open" or honesty.get("phase_9_exit") != "still open":
    raise SystemExit("06 JSON must keep Phase 5/9 exit still open")
if honesty.get("product_status") != "REJECTED":
    raise SystemExit("06 JSON product_status walked off REJECTED")
json_hosts = {row.get("path"): row.get("capability") for row in honesty.get("live_admin_inspect_hosts") or []}
expected_hosts = {
    "Administration > Processes": "process.inspect",
    "Administration > Services": "service.inspect",
    "Administration > Device Manager": "device.inspect",
    "Administration > Storage": "storage.inspect",
    "Administration > Printers and scanners": "printer.inspect",
    "Administration > Backup": "backup.inspect",
    "Administration > Scheduled tasks": "schedule.inspect",
    "Administration > Troubleshooting": "diagnostics.inspect",
    "Administration > Firewall": "firewall.inspect",
    "Administration > User accounts": "account.inspect",
}
if json_hosts != expected_hosts:
    raise SystemExit(f"06 JSON live_admin_inspect_hosts walked off: {json_hosts}")
for row in (gt06_json.get("interaction_tables") or {}).get("default_programs") or []:
    if "apps.defaults.set" in str(row.get("omarchy") or ""):
        raise SystemExit(f"06 JSON default_programs still names apps.defaults.set: {row}")
    if row.get("job") == "Change default browser" and "defaults.protocol.set" not in str(row.get("omarchy") or ""):
        raise SystemExit(f"06 JSON default browser row does not name defaults.protocol.set: {row}")
for row in (gt06_json.get("interaction_tables") or {}).get("administration") or []:
    mapped = str(row.get("omarchy") or "")
    if mapped.startswith("Phase 9") and "Administration >" not in mapped:
        raise SystemExit(f"06 JSON administration still treats Phase 9 as an empty MMC noun: {row}")

plan = (root / "plans/project-ultimate.md").read_text(encoding="utf-8")
if "planned with an empty path" in plan:
    raise SystemExit("project-ultimate still underclaims process.inspect as planned with an empty path")
if "stay planned Phase 9 destinations" in plan:
    raise SystemExit("project-ultimate still underclaims Administration readers as planned Phase 9 destinations")
if "Administration > Processes" not in plan:
    raise SystemExit("project-ultimate must name Administration > Processes visible host")
if "claim stays missing" not in plan:
    raise SystemExit("project-ultimate must keep process.inspect / Administration reader claim missing")
if "honest-unavailable as Task Manager" not in plan:
    raise SystemExit("project-ultimate must keep process.inspect honest-unavailable as Task Manager")
if "Phase 9 exit criteria still open" not in plan:
    raise SystemExit("project-ultimate must keep Phase 9 exit still open")
if "task manager present" in plan.lower() and "no task manager present" not in plan.lower():
    raise SystemExit("project-ultimate invented Task Manager present")
if "End Task LIVE" in plan and "no End Task LIVE" not in plan:
    raise SystemExit("project-ultimate invented End Task LIVE")
if "METAL_HEAD closed" in plan:
    raise SystemExit("project-ultimate invented METAL_HEAD closed")
if "events.subscribe" in plan:
    raise SystemExit("project-ultimate invented events.subscribe")
if "Superbar QS Process leftover unverified on metal" in plan:
    raise SystemExit("project-ultimate still underclaims QS/Superbar Power leftover as unverified without metal FAIL")
if "QS Power METAL_HEAD OPEN" not in plan:
    raise SystemExit("project-ultimate must keep QS Power METAL_HEAD OPEN")
if "20484de6" not in plan:
    raise SystemExit("project-ultimate must cite metal FAIL tip 20484de6")
if "Not authorized" not in plan or "session-5103" not in plan:
    raise SystemExit("project-ultimate must cite metal FAIL pkcheck Not authorized / session-5103")
if "batteryPresent" not in plan or "amd_pstate" not in plan:
    raise SystemExit("project-ultimate must cite metal FAIL batteryPresent / amd_pstate")
if "Settings Power LIVE refused" not in plan:
    raise SystemExit("project-ultimate must keep Settings Power LIVE refused")
if "heritage QS Power works on metal" in plan:
    raise SystemExit("project-ultimate invented heritage QS Power works on metal")
if "KEEP OPEN" not in plan:
    raise SystemExit("project-ultimate must KEEP OPEN the QS Power leftover")

cp = (root / "plans/win7-ultimate-ground-truth/fleet/fleet-catalog-controlpanel.md").read_text(encoding="utf-8")
if "planned empty path" in cp:
    raise SystemExit("fleet-catalog-controlpanel still underclaims process.inspect as planned empty path")
if "planned host" in cp or "planned Admin" in cp:
    raise SystemExit("fleet-catalog-controlpanel still keeps Admin inspect rows as planned hosts after #36")
if "apps.defaults.set" in cp:
    raise SystemExit("fleet-catalog-controlpanel still names leftover apps.defaults.set as the live Apps writer")
if "defaults.protocol.set" not in cp or "browser LIVE only" not in cp:
    raise SystemExit("fleet-catalog-controlpanel does not name defaults.protocol.set as browser LIVE only")
if "files.associations.set" not in cp or "missing/planned MIME" not in cp:
    raise SystemExit("fleet-catalog-controlpanel dropped files.associations.set missing/planned MIME")
if "publish honest" in cp and "humanRoutes" in cp:
    raise SystemExit("fleet-catalog-controlpanel still says publish Administration humanRoutes")
if "product ahead of catalog" in cp:
    raise SystemExit("fleet-catalog-controlpanel still names product-ahead-of-catalog debt closed by #35–#36")
if "residual = product MMC / mutation / Task Manager present still missing, not catalog planned-empty" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must rank residual as product MMC / mutation / Task Manager present, not catalog planned-empty")
if "Administration > Processes" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must name Administration > Processes visible host")
if "process.inspect" not in cp or "terminationAuthorized=false" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must name process.inspect + unauthorized End Task path")
if "claim missing" not in cp and "claim **missing**" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must keep process.inspect / Administration reader claim missing")
if "honest-unavailable as Task Manager product" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must keep process.inspect honest-unavailable as Task Manager product")
if "Phase 9 exit still open" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must keep Phase 9 exit still open")
if "inspect ≠ MMC product present" not in cp and "inspect inventory ≠ product MMC present" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must keep inspect ≠ MMC product present")
cp_admin_hosts = (
    "Administration > Processes",
    "Administration > Services",
    "Administration > Device Manager",
    "Administration > Storage",
    "Administration > Printers and scanners",
    "Administration > Backup",
    "Administration > Scheduled tasks",
    "Administration > Troubleshooting",
    "Administration > Firewall",
    "Administration > User accounts",
)
for host in cp_admin_hosts:
    if host not in cp:
        raise SystemExit(f"fleet-catalog-controlpanel does not name live host {host}")
if "do not invent Task Manager present" not in cp and "no Task Manager present" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must refuse Task Manager present")
if "task manager present" in cp.lower() and "do not invent task manager present" not in cp.lower() and "no task manager present" not in cp.lower() and "not task manager present" not in cp.lower() and "honest-unavailable as task manager product" not in cp.lower():
    raise SystemExit("fleet-catalog-controlpanel invented Task Manager present")
if "End Task LIVE" in cp and "do not invent" not in cp:
    raise SystemExit("fleet-catalog-controlpanel invented End Task LIVE")
if "Accessibility panel" in cp and "do not invent Accessibility panel" not in cp and "Accessibility panel missing as product" not in cp:
    raise SystemExit("fleet-catalog-controlpanel invented Accessibility panel")
if "Software Center present" in cp:
    raise SystemExit("fleet-catalog-controlpanel invented Software Center present")
if "Restore LIVE" in cp and "do not invent Restore LIVE" not in cp:
    raise SystemExit("fleet-catalog-controlpanel invented Restore LIVE")
if "Settings Power LIVE" in cp and "Settings Power LIVE refused" not in cp and "not Settings LIVE" not in cp:
    raise SystemExit("fleet-catalog-controlpanel invented Settings Power LIVE")
if "events.subscribe" in cp:
    raise SystemExit("fleet-catalog-controlpanel invented events.subscribe")
if "METAL_HEAD closed" in cp:
    raise SystemExit("fleet-catalog-controlpanel invented METAL_HEAD closed")
if "QS Power METAL_HEAD OPEN" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must keep QS Power METAL_HEAD OPEN")
if "FAIL on this metal" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must name QS Power leftover FAIL on this metal")
if "heritage QS Power works on metal" in cp:
    raise SystemExit("fleet-catalog-controlpanel invented heritage QS Power works on metal")
if "Settings coverage-badge PIXEL leftover CLOSED" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must retarget Settings coverage-badge PIXEL leftover CLOSED")
if "d3f4841a" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must cite metal tip d3f4841a for Settings coverage-badge PIXEL leftover CLOSED")
if "firewall.manage" not in cp or "backup.manage" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must keep firewall.manage / backup.manage planned/unavailable")
if "claim=`missing` vs `sourceStatus=prototype`" in cp:
    raise SystemExit("fleet-catalog-controlpanel still lists parity.agent-center claim=missing as open MUST_FIX")
if "Closed: `parity.agent-center`" not in cp or "claim=`prototype`" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must close parity.agent-center claim=prototype vs sourceStatus")
if "consent/provider ops stay outside Agent Center" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must keep consent/provider ops outside Agent Center")
if "do not invent claim=`present`" not in cp:
    raise SystemExit("fleet-catalog-controlpanel must refuse Agent Center claim=present")

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
    "network.wifi.connect": "partial",
    "power.profile.set": "partial",
    "display.configure": "partial",
    "display.night-light.set": "partial",
    "display.brightness.set": "partial",
    "input.keyboard-layout.set": "partial",
    "defaults.protocol.set": "partial",
    "defaults.mime.set": "partial",
    "files.directory.create": "partial",
    "files.entry.trash": "partial",
    "account.inspect": "missing",
    "backup.inspect": "missing",
    "device.inspect": "missing",
    "diagnostics.inspect": "missing",
    "firewall.inspect": "missing",
    "printer.inspect": "missing",
    "process.inspect": "missing",
    "process.termination.plan": "missing",
    "schedule.inspect": "missing",
    "service.inspect": "missing",
    "storage.inspect": "missing",
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
