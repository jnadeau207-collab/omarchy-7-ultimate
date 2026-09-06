#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsAppsStartup.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionStartup.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
settings_api="$ROOT/docs/settings-service-api.md"
admin_app="$ROOT/shell/apps/ultimate-administration/AdministrationApplication.qml"
defaults_provider="$ROOT/default/fabric/omarchy_fabric/providers/defaults/provider.py"
defaults_manifest="$ROOT/default/fabric/omarchy_fabric/providers/defaults/manifest-v0.json"

[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_session ]] || fail "Settings hosts a session startup plane"
[[ -f $settings_card ]] || fail "Settings ships an Apps startup card"

grep -Fq '"apps-startup-list": apply_apps_startup_list' "$helper" ||
  fail "session apply owns apps-startup-list"
grep -Fq '"apps-startup-set": apply_apps_startup_set' "$helper" ||
  fail "session apply owns apps-startup-set"
grep -Fq 'apps-startup-list' "$settings_session" || fail "session startup QML calls apps-startup-list"
grep -Fq 'apps-startup-set' "$settings_session" || fail "session startup QML calls apps-startup-set"
grep -Fq 'omarchy-fabric-session-apply' "$settings_session" ||
  fail "session startup QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$settings_session" || fail "session startup QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$settings_session" ||
  fail "session startup QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$settings_session"; then
  fail "session startup QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Apps startup must not mint Fabric durable operations"
fi
if grep -A20 'SettingsComponents.SettingsAppsStartup' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings Apps startup host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo' "$settings_session" "$settings_card"; then
  fail "Settings Apps startup QML must not spawn privilege"
fi
if grep -Eq 'pkexec|sudo' <(sed -n '/^MAX_STARTUP_FILES = 64$/,/^ACTIONS = {$/p' "$helper"); then
  fail "session startup verbs must not spawn privilege"
fi
if grep -Eq '/etc/xdg/autostart' "$settings_session" "$settings_card"; then
  fail "Settings Apps startup QML must not write system autostart"
fi
if grep -Eq 'autostart\.lua|launch_on_start' "$settings_session" "$settings_card" "$helper"; then
  fail "Settings Apps startup must not invent a Hyprland autostart.lua rewriter"
fi
if grep -Eq 'provider: "apps.provider"|action: "startup' "$settings_session" "$settings_card"; then
  fail "Settings Apps startup must not invent a Fabric startup writer"
fi
grep -Fq 'SettingsComponents.SettingsAppsStartup' "$settings_app" ||
  fail "Settings Apps hosts the session startup card"
grep -Fq 'settings.apps.overview' "$settings_app" || fail "Settings still owns the Apps route"
grep -Fq 'this session' "$settings_card" || fail "Settings Apps startup names the session principal"
grep -Fq 'XDG' "$settings_card" || fail "Settings Apps startup names the XDG autostart plane"
grep -Fq 'Fabric' "$settings_card" || fail "Settings Apps startup keeps Fabric inspect honest"
if grep -Eqi 'claim=present' "$settings_card" "$settings_app"; then
  fail "Settings Apps startup must not invent claim=present"
fi
if grep -Eqi 'Task Manager Startup|present as Task Manager|Task Manager is present' "$settings_card" "$settings_app"; then
  fail "Settings Apps startup must not invent Task Manager present"
fi
grep -Fq 'does not invent Task Manager present' "$settings_card" ||
  fail "Settings Apps startup must refuse Task Manager present"
if grep -Eqi 'Settings Power LIVE' "$settings_card"; then
  fail "Settings Apps startup must not invent Settings Power LIVE"
fi
if grep -Eq 'LIVE CONTROL' "$settings_card"; then
  fail "Settings Apps startup must not invent Task Manager LIVE CONTROL"
fi
if grep -Fq 'Settings cannot enable, disable, or remove them.' "$settings_app"; then
  fail "Settings Apps still refuses startup mutation on the host"
fi
if grep -Eq 'startup.*operation\.preflight|operation\.preflight.*startup' "$settings_app"; then
  fail "Settings must not wire a Fabric startup mutation"
fi
grep -Fq 'readonly property bool terminationAuthorized: false' "$admin_app" ||
  fail "End Task stays unauthorized"
if grep -Eq 'terminationAuthorized:\s*true' "$admin_app"; then
  fail "End Task LIVE must stay refused"
fi
if grep -Eqi 'startup\.set|startup.disable' "$defaults_provider" "$defaults_manifest"; then
  fail "defaults.provider invented a durable startup writer"
fi
grep -Fq 'sessionStartupIdle' "$settings_model" || fail "Settings model normalizes session startup outcomes"
grep -Fq 'XDG autostart' "$settings_model" || fail "Settings coverage names the XDG autostart plane"
if grep -Fq 'Settings cannot enable, disable, or remove startup applications' "$settings_model"; then
  fail "Settings coverage still refuses startup mutation"
fi

pass "Settings Apps hosts the session XDG startup plane instead of a Fabric LIVE writer"

cd "$ROOT/default/fabric"
PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import io
import json
import tempfile
from pathlib import Path

from omarchy_fabric.helpers import session_apply as sa

failures = []


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def run_action(handler, payload, **kwargs):
    stream = io.StringIO()
    status = handler(io.StringIO(json.dumps(payload)), stream, **kwargs)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


with tempfile.TemporaryDirectory() as directory:
    home = Path(directory) / "home"
    system = Path(directory) / "system"
    user_dir = home / ".config" / "autostart"
    user_dir.mkdir(parents=True)
    system.mkdir(parents=True)
    (user_dir / "notes.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Notes\nExec=notes --bg\n",
        encoding="utf-8",
    )
    (user_dir / "quiet.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Quiet\nHidden=true\nExec=quiet\n",
        encoding="utf-8",
    )
    (system / "mailer.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Mailer\nExec=mailer\n",
        encoding="utf-8",
    )
    (system / "notes.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=System Notes\nExec=system-notes\n",
        encoding="utf-8",
    )
    (user_dir / "not-a-desktop.txt").write_text("nothing\n", encoding="utf-8")

    status, result = run_action(sa.apply_apps_startup_list, {}, home=home, system_root=system)
    check("list succeeds", status == 0 and result.get("ok") is True, str(result))
    entries = {entry["desktopId"]: entry for entry in result.get("entries", [])}
    check("user notes is listed", "notes.desktop" in entries, str(result))
    check("user notes is enabled", entries.get("notes.desktop", {}).get("enabled") is True, str(result))
    check("user notes source is user", entries.get("notes.desktop", {}).get("source") == "user", str(result))
    check("quiet is disabled", entries.get("quiet.desktop", {}).get("enabled") is False, str(result))
    check("system mailer is listed", "mailer.desktop" in entries, str(result))
    check("system mailer source is system", entries.get("mailer.desktop", {}).get("source") == "system", str(result))
    check("user notes wins over system", entries.get("notes.desktop", {}).get("name") == "Notes", str(result))
    check("non-desktop files are skipped", "not-a-desktop.txt" not in entries, str(result))
    check("list redacts Exec", all("Exec" not in entry and "exec" not in entry for entry in result.get("entries", [])), str(result))
    check("listed entries are controllable", all(entry.get("controllable") is True for entry in result.get("entries", [])), str(result))

    status, result = run_action(
        sa.apply_apps_startup_set,
        {"desktopId": "notes.desktop", "enabled": False},
        home=home,
        system_root=system,
    )
    check("disable user entry succeeds", status == 0 and result.get("ok") is True, str(result))
    check("disable reports disabled", result.get("enabled") is False, str(result))
    check("disable keeps desktopId", result.get("desktopId") == "notes.desktop", str(result))
    notes_text = (user_dir / "notes.desktop").read_text(encoding="utf-8")
    check("disable writes Hidden=true", "Hidden=true" in notes_text, notes_text)
    check("disable does not write /etc", not (system / "notes.desktop").read_text(encoding="utf-8").count("Hidden=true"), "system file mutated")

    status, listed = run_action(sa.apply_apps_startup_list, {}, home=home, system_root=system)
    listed_entries = {entry["desktopId"]: entry for entry in listed.get("entries", [])}
    check("reread shows notes disabled", listed_entries.get("notes.desktop", {}).get("enabled") is False, str(listed))

    status, result = run_action(
        sa.apply_apps_startup_set,
        {"desktopId": "notes.desktop", "enabled": False},
        home=home,
        system_root=system,
    )
    check("disable is idempotent", status == 0 and result.get("ok") is True, str(result))

    status, result = run_action(
        sa.apply_apps_startup_set,
        {"desktopId": "notes.desktop", "enabled": True},
        home=home,
        system_root=system,
    )
    check("enable user entry succeeds", status == 0 and result.get("ok") is True, str(result))
    check("enable reports enabled", result.get("enabled") is True, str(result))
    notes_text = (user_dir / "notes.desktop").read_text(encoding="utf-8")
    check("enable clears Hidden=true", "Hidden=true" not in notes_text, notes_text)

    status, result = run_action(
        sa.apply_apps_startup_set,
        {"desktopId": "mailer.desktop", "enabled": False},
        home=home,
        system_root=system,
    )
    check("disable system entry succeeds", status == 0 and result.get("ok") is True, str(result))
    check("disable system writes a user override", (user_dir / "mailer.desktop").is_file(), "missing user override")
    override = (user_dir / "mailer.desktop").read_text(encoding="utf-8")
    check("system disable override is Hidden=true", "Hidden=true" in override, override)
    check("system file stays enabled", "Hidden=true" not in (system / "mailer.desktop").read_text(encoding="utf-8"), "system mutated")

    status, listed = run_action(sa.apply_apps_startup_list, {}, home=home, system_root=system)
    listed_entries = {entry["desktopId"]: entry for entry in listed.get("entries", [])}
    check("reread shows mailer disabled", listed_entries.get("mailer.desktop", {}).get("enabled") is False, str(listed))
    check("disabled system override source is user", listed_entries.get("mailer.desktop", {}).get("source") == "user", str(listed))

    status, result = run_action(
        sa.apply_apps_startup_set,
        {"desktopId": "mailer.desktop", "enabled": True},
        home=home,
        system_root=system,
    )
    check("enable system override succeeds", status == 0 and result.get("ok") is True, str(result))
    check("enable keeps a user override", (user_dir / "mailer.desktop").is_file(), "override missing")
    override = (user_dir / "mailer.desktop").read_text(encoding="utf-8")
    check("enable override is not Hidden=true", "Hidden=true" not in override, override)
    status, listed = run_action(sa.apply_apps_startup_list, {}, home=home, system_root=system)
    listed_entries = {entry["desktopId"]: entry for entry in listed.get("entries", [])}
    check("reread shows mailer enabled", listed_entries.get("mailer.desktop", {}).get("enabled") is True, str(listed))
    check("enabled system override source is user", listed_entries.get("mailer.desktop", {}).get("source") == "user", str(listed))

    status, result = run_action(
        sa.apply_apps_startup_set,
        {"desktopId": "../escape.desktop", "enabled": False},
        home=home,
        system_root=system,
    )
    check("path traversal is refused", status == 1 and result.get("ok") is False, str(result))
    check("path traversal uses startup.payload-invalid", result.get("code") == "startup.payload-invalid", str(result))

    status, result = run_action(
        sa.apply_apps_startup_set,
        {"desktopId": "missing.desktop", "enabled": False},
        home=home,
        system_root=system,
    )
    check("missing entry is refused", status == 1 and result.get("ok") is False, str(result))
    check("missing entry uses startup.entry-missing", result.get("code") == "startup.entry-missing", str(result))

    status, result = run_action(sa.apply_apps_startup_set, {"desktopId": "notes.desktop"}, home=home, system_root=system)
    check("missing enabled flag is refused", status == 1 and result.get("ok") is False, str(result))
    check("missing enabled uses startup.payload-invalid", result.get("code") == "startup.payload-invalid", str(result))

    symlink = user_dir / "link.desktop"
    symlink.symlink_to("notes.desktop")
    status, listed = run_action(sa.apply_apps_startup_list, {}, home=home, system_root=system)
    listed_ids = [entry["desktopId"] for entry in listed.get("entries", [])]
    check("symlinks are not listed", "link.desktop" not in listed_ids, str(listed))

    empty_home = Path(directory) / "empty-home"
    empty_home.mkdir()
    status, result = run_action(sa.apply_apps_startup_list, {}, home=empty_home, system_root=Path(directory) / "no-system")
    check("empty inventory succeeds", status == 0 and result.get("ok") is True, str(result))
    check("empty inventory is empty", result.get("entries") == [], str(result))
    check("empty inventory is honest empty", result.get("empty") is True, str(result))
    check("empty inventory names a reason", bool(result.get("reason") or result.get("explanation")), str(result))

    missing_home = Path(directory) / "missing-home"
    status, result = run_action(sa.apply_apps_startup_list, {}, home=missing_home, system_root=system)
    check("missing home is unavailable", status == 1 and result.get("ok") is False, str(result))
    check("missing home uses startup.home-unavailable", result.get("code") == "startup.home-unavailable", str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session apps-startup list/set reports success and honest refusal"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionStartupIdle()
assertEqual(idle.phase, 'idle', 'session startup starts idle')
assertDeepEqual(idle.entries, [], 'session startup starts with no rows')
assertEqual(idle.empty, false, 'session startup starts without claiming empty')
assertEqual(idle.unavailable, false, 'session startup starts without claiming unavailable')

const listed = Model.sessionStartupFinished(idle, {
  ok: true,
  empty: false,
  entries: [
    { desktopId: 'notes.desktop', name: 'Notes', enabled: true, source: 'user', controllable: true },
    { desktopId: 'mailer.desktop', name: 'Mailer', enabled: false, source: 'system', controllable: true }
  ],
  explanation: 'Startup applications from this session XDG autostart.'
})
assertEqual(listed.phase, 'succeeded', 'successful list is succeeded')
assertEqual(listed.entries.length, 2, 'successful list keeps rows')
assertEqual(listed.entries[0].desktopId, 'notes.desktop', 'successful list keeps desktopId')
assertEqual(listed.entries[0].startupEnabled, true, 'successful list keeps enabled')
assertEqual(listed.empty, false, 'a populated list is not empty')
assertEqual(listed.message, 'Startup applications from this session XDG autostart.', 'successful list keeps the helper explanation')

const empty = Model.sessionStartupFinished(idle, {
  ok: true,
  empty: true,
  entries: [],
  reason: 'startup.empty',
  explanation: 'No XDG autostart applications were found for this session.'
})
assertEqual(empty.phase, 'succeeded', 'honest empty is succeeded')
assertEqual(empty.empty, true, 'honest empty stays empty')
assertEqual(empty.unavailable, false, 'honest empty is not unavailable')
assertEqual(empty.code, 'startup.empty', 'honest empty keeps the structured reason')

const unavailable = Model.sessionStartupFinished(idle, {
  ok: false,
  code: 'startup.home-unavailable',
  explanation: 'This session has no usable home directory for XDG autostart.'
})
assertEqual(unavailable.phase, 'failed', 'helper failure is failed')
assertEqual(unavailable.unavailable, true, 'home failure is unavailable')
assertEqual(unavailable.code, 'startup.home-unavailable', 'failure keeps the helper code')

const disabled = Model.sessionStartupFinished(listed, {
  ok: true,
  desktopId: 'notes.desktop',
  enabled: false,
  explanation: 'Disabled notes.desktop for this session.'
})
assertEqual(disabled.phase, 'succeeded', 'successful disable is succeeded')
assertEqual(disabled.action, 'set', 'disable records a set action when previous had entries')

assertEqual(Model.sessionStartupCanSubmit({ desktopId: 'notes.desktop', enabled: false, controllable: true }), true, 'a controllable row can submit')
assertEqual(Model.sessionStartupCanSubmit({ desktopId: 'notes.desktop', enabled: false, controllable: false }), false, 'an uncontrollable row cannot submit')
assertEqual(Model.sessionStartupCanSubmit({ desktopId: '', enabled: false, controllable: true }), false, 'a nameless row cannot submit')

const apps = Model.queryForRoute('settings.apps.overview')
assert(apps.coverage.indexOf('XDG autostart') >= 0, 'apps coverage names the XDG autostart plane')
assert(apps.coverage.indexOf('this session') >= 0, 'apps coverage names the session principal')
assert(apps.coverage.indexOf('defaults.inspect') >= 0, 'apps coverage keeps Fabric inspect separate')
assert(apps.coverage.indexOf('does not invent a Fabric apps.startup.disable durable writer') >= 0, 'apps coverage refuses a Fabric startup writer')
assert(apps.coverage.indexOf('does not invent Task Manager present') >= 0, 'apps coverage refuses Task Manager present')
assert(apps.coverage.indexOf('Settings cannot enable, disable, or remove startup applications') < 0, 'apps coverage no longer refuses startup mutation')
assert(Model.declaredOpsHonesty('settings.apps.overview').indexOf('XDG autostart') >= 0, 'apps declared ops name the XDG autostart plane')
assert(Model.declaredOpsHonesty('settings.apps.overview').indexOf('durable coordinator') >= 0, 'apps declared ops keep browser/MIME on the durable coordinator')
assert(Model.declaredOpsHonesty('settings.apps.overview').indexOf('does not invent a Fabric apps.startup.disable durable writer') >= 0, 'apps declared ops do not invent a Fabric startup writer')
assert(Model.authorityFooter().indexOf('XDG autostart') >= 0, 'authority footer names XDG autostart')
JS

pass "Settings model maps session startup outcomes and refuses a Fabric invent"

python3 - "$catalog" "$jobs" "$debt" "$gaps" "$parity" "$settings_api" "$admin_app" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
debt = json.loads(open(sys.argv[3], encoding="utf-8").read())
gaps = open(sys.argv[4], encoding="utf-8").read()
parity = open(sys.argv[5], encoding="utf-8").read()
settings_api = open(sys.argv[6], encoding="utf-8").read()
admin_app = open(sys.argv[7], encoding="utf-8").read()
by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
startup = by_id["apps.startup.disable"]
route = startup["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"apps.startup.disable route is {route}")
if route.get("path") not in {"Settings > Apps", "Start > Settings > Apps"}:
    raise SystemExit(f"apps.startup.disable path is {route}")
if "Task Manager" in str(route.get("surface") or "") or "Task Manager" in str(route.get("path") or ""):
    raise SystemExit(f"apps.startup.disable invents a Task Manager Startup page: {route}")
if route.get("label") != "Disable startup application":
    raise SystemExit(f"apps.startup.disable label is {route}")
if startup.get("source", {}).get("file") != "shell/apps/shared/SettingsSessionStartup.qml":
    raise SystemExit(f"apps.startup.disable source is {startup.get('source')}")
if startup.get("source", {}).get("symbol") != "setEnabled":
    raise SystemExit(f"apps.startup.disable source is {startup.get('source')}")
if "SettingsAppsStartup.qml" in str(startup.get("source", {}).get("file") or ""):
    raise SystemExit("apps.startup.disable must not invent source on SettingsAppsStartup.qml")
if startup.get("availability", {}).get("claim") == "present":
    raise SystemExit("apps.startup.disable must not claim present")
if startup.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"apps.startup.disable claim is {startup.get('availability')}")
if startup.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"apps.startup.disable human availability is {startup.get('availability')}")
if startup.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"apps.startup.disable agent availability is {startup.get('availability')}")
if startup.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"apps.startup.disable was raised off leftover: {startup.get('provider')}")
if startup.get("provider", {}).get("id") != "apps.provider":
    raise SystemExit(f"apps.startup.disable provider is {startup.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
parity_task = by_job["parity.task-manager"]
if parity_task.get("claim") == "present":
    raise SystemExit("parity.task-manager must not claim present")
if "apps.startup.disable" not in (parity_task.get("capabilityIds") or []):
    raise SystemExit("parity.task-manager dropped apps.startup.disable")
if parity_task["humanRoute"].get("path"):
    raise SystemExit(f"parity.task-manager invents a Task Manager destination: {parity_task['humanRoute']}")
native27 = by_job["windows-native.27"]
if native27.get("claim") == "present":
    raise SystemExit("windows-native.27 must not claim present")
if native27.get("claim") != "missing":
    raise SystemExit(f"windows-native.27 claim is {native27.get('claim')}")
if native27.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.27 sourceStatus is {native27.get('sourceStatus')}")
if native27.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.27 proofStatus is {native27.get('proofStatus')}")
if native27.get("capabilityIds") != ["apps.startup.disable"]:
    raise SystemExit(f"windows-native.27 capabilityIds are {native27.get('capabilityIds')}")
if native27["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.27 route is {native27.get('humanRoute')}")
if native27["humanRoute"].get("path") not in {"Settings > Apps", "Start > Settings > Apps"}:
    raise SystemExit(f"windows-native.27 path is {native27.get('humanRoute')}")
if "Task Manager" in str(native27["humanRoute"].get("surface") or "") or "Task Manager" in str(native27["humanRoute"].get("path") or ""):
    raise SystemExit(f"windows-native.27 invents a Task Manager Startup page: {native27['humanRoute']}")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "apps.startup.disable" not in legacy.get("capabilityIds", []):
    raise SystemExit("apps.startup.disable is not leftover-direct debt")
if "capability:apps.startup.disable" not in legacy.get("surfaceRefs", []):
    raise SystemExit("apps.startup.disable leftover surfaceRef is missing")
missing_providers = by_debt["missing.domain.providers"]
if "apps.startup.disable" in missing_providers.get("capabilityIds", []):
    raise SystemExit("apps.startup.disable still sits in missing.domain.providers")
agent = by_debt["missing.agent.routes"]
if "apps.startup.disable" not in agent.get("capabilityIds", []):
    raise SystemExit("apps.startup.disable left missing.agent.routes")

if "Honesty addendum 2026-09-06 vs Settings Apps startup disable" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Settings Apps startup disable addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Settings Apps startup disable", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover: Settings Apps startup disable UI" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name CLOSED leftover as Settings Apps startup disable UI")
for required in (
    "Task Manager present",
    "End Task LIVE",
    "Settings Power LIVE",
    "Files LIVE metal",
    "Win7 visual",
    "Software Center present",
    "Update present",
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps startup addendum dropped OPEN leftover: {required}")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "XDG" not in addendum or "this session" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the session XDG autostart plane")
if "Do not invent Task Manager present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Task Manager present invent")
if "windows-native.27" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.27 pending")
if "Settings > Apps" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the Settings Apps host")
if "terminationAuthorized=false" not in addendum and "terminationAuthorized stays false" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep End Task unauthorized")
if "readonly property bool terminationAuthorized: false" not in admin_app:
    raise SystemExit("Administration must keep terminationAuthorized=false")
if "Startup applications stay on Settings → Apps as read-only" in parity:
    raise SystemExit("PARITY still treats startup as read-only")
if "XDG autostart" not in parity:
    raise SystemExit("PARITY must name the XDG autostart plane")
if "does not invent Task Manager present" not in parity:
    raise SystemExit("PARITY must refuse Task Manager present invent")
if "Settings > Apps" not in parity and "Settings → Apps" not in parity:
    raise SystemExit("PARITY must name the Settings Apps startup host")
if "XDG autostart" not in settings_api:
    raise SystemExit("settings-service-api must name the XDG autostart plane")
if "apps.startup.disable" not in settings_api:
    raise SystemExit("settings-service-api must name apps.startup.disable")
if "windows-native.27" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.27 pending")
if "does not invent Task Manager present" not in settings_api:
    raise SystemExit("settings-service-api must refuse Task Manager present")
if "Fabric apps.startup.disable durable writer" not in settings_api and "does not invent a Fabric" not in settings_api:
    raise SystemExit("settings-service-api must refuse a Fabric startup writer")
PY

pass "apps.startup.disable stays leftover partial with a visible Settings Apps route"
