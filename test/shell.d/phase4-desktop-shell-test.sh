#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command python3

jq -e '.id == "omarchy.quick-settings" and (.kinds | index("bar-widget"))' \
  "$ROOT/shell/plugins/ultimate-quick-settings/manifest.json" >/dev/null \
  || fail "Quick Settings is a first-party bar-widget plugin"
pass "Quick Settings plugin exists"

jq -e '.id == "omarchy.notifications" and (.kinds | index("service")) and (.kinds | index("bar-widget"))' \
  "$ROOT/shell/plugins/notifications/manifest.json" >/dev/null \
  || fail "notifications plugin hosts both the daemon and the Notification Center widget"
pass "Notification Center is a bar-widget on the notifications plugin"

jq -e '.features.quickSettings == true and .features.notificationCenter == true' \
  "$ROOT/default/ultimate/profiles/desktop.json" >/dev/null \
  || fail "desktop profile claims Quick Settings and Notification Center"
pass "desktop profile flags match the shipped surfaces"

python3 - "$ROOT" <<'PY' || fail "Desktop Mode overlay is Quick Settings, Notification Center, agents, tray, clock"
from pathlib import Path
import re
import sys

text = (Path(sys.argv[1]) / "shell/shell.qml").read_text(encoding="utf-8")
match = re.search(r"function overlayShellConfig\(config\) \{.*?\n  \}", text, re.S)
if not match:
    raise SystemExit("overlayShellConfig missing")
body = match.group(0)
for needle in (
    'id: "omarchy.quick-settings"',
    'id: "omarchy.notifications"',
    'id: "omarchy.agents"',
    'id: "omarchy.tray"',
    'id: "omarchy.clock"',
):
    if needle not in body:
        raise SystemExit(f"overlay missing {needle}")
for leftover in (
    'id: "omarchy.bluetooth"',
    'id: "omarchy.network"',
    'id: "omarchy.audio"',
    'id: "omarchy.monitor"',
    'id: "omarchy.power"',
):
    if leftover in body:
        raise SystemExit(f"overlay still pins {leftover} as a Superbar icon")
PY
pass "Desktop Mode overlay composes Quick Settings instead of five panel icons"

grep -Fq 'text: "Agent Center"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start exposes Agent Center as a destination"
grep -Fq 'org.omarchy.Files' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start exposes Files as a destination"
grep -Fq 'org.omarchy.Settings' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start exposes Settings as a destination"
pass "Start has Files, Settings, and Agent Center destinations"

grep -Fq 'launchAgentCenter' "$ROOT/shell/plugins/agents/Panel.qml" \
  || fail "agents panel can open Agent Center"
grep -Fq 'Open Agent Center' "$ROOT/shell/plugins/agents/Panel.qml" \
  || fail "agents panel shows Open Agent Center"
pass "agents panel is a launch shim to Agent Center"

jq -e '.pins[-1].desktopId == "org.omarchy.AgentCenter"' \
  "$ROOT/default/ultimate/taskbar-pins.json" >/dev/null \
  || fail "shipped Superbar pins include Agent Center"
pass "Agent Center is a shipped Superbar pin"

grep -Fq 'userName' "$ROOT/shell/plugins/lock/LockView.qml" \
  || fail "lock shows the session user"
grep -Fq 'SystemClock' "$ROOT/shell/plugins/lock/LockView.qml" \
  || fail "lock shows a clock"
pass "lock shows clock and user"

grep -Fq 'text: "Calendar"' "$ROOT/shell/plugins/panels/clock/Panel.qml" \
  || fail "clock panel names itself Calendar"
pass "calendar surface is the clock panel"

grep -Fq 'function jumpListFor' "$ROOT/shell/services/AppLibrary.qml" \
  || fail "AppLibrary exposes jump lists"
grep -Fq 'Open new window' "$ROOT/shell/services/JumpList.js" \
  || fail "Superbar jump lists include Open new window"
grep -Fq 'previewRows' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "Superbar peek uses the structured preview model"
grep -Fq 'badgeCount' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "Superbar task buttons show notification badges"
pass "Superbar has jump lists, structured previews, and badges"

run_node_test <<'JS'
const JumpList = requireFromRoot('shell/services/JumpList.js')
const Preview = requireFromRoot('shell/services/WindowPreview.js')
const notifications = requireFromRoot('shell/plugins/notifications/NotificationLogic.js')
const qs = requireFromRoot('shell/plugins/ultimate-quick-settings/Model.js')

const empty = JumpList.jumpListFor(null, 'org.omarchy.Files')
assertEqual(empty.length, 1, 'jump list always has Open new window')
assertEqual(empty[0].kind, 'open-new', 'default jump list row is open-new')
assertEqual(empty[0].name, 'Open new window', 'default jump list label is Open new window')

const withActions = JumpList.jumpListFor({
  id: 'org.omarchy.Files',
  actions: [
    { id: 'Trash', name: 'Trash', exec: 'omarchy-launch-files --source desktop files.trash' },
    { id: 'Dead', name: 'Dead' }
  ]
}, 'org.omarchy.Files')
assertEqual(withActions.length, 2, 'jump list drops actions that cannot launch')
assertEqual(withActions[1].name, 'Trash', 'launchable desktop actions stay on the jump list')

const qvectorCommand = { length: 3, 0: 'omarchy-launch-agent-center', 1: '--source', 2: 'desktop' }
const fromQuickshell = JumpList.jumpListFor({
  id: 'org.omarchy.AgentCenter',
  actions: { length: 1, 0: { id: 'Tasks', name: 'Tasks & Runs', command: qvectorCommand } }
}, 'org.omarchy.AgentCenter')
assertEqual(fromQuickshell.length, 2, 'Quickshell QVector command lists stay launchable')
assertEqual(fromQuickshell[1].name, 'Tasks & Runs', 'DesktopAction name survives a QVector command')
assertEqual(
  fromQuickshell[1].command,
  'omarchy-launch-agent-center --source desktop',
  'QVector command parts join into one launch line'
)

const fromExecString = JumpList.jumpListFor({
  id: 'org.omarchy.AgentCenter',
  actions: [{ id: 'Approvals', name: 'Pending Approvals', execString: 'omarchy-launch-agent-center --source desktop agent.approvals' }]
}, 'org.omarchy.AgentCenter')
assertEqual(fromExecString[1].name, 'Pending Approvals', 'DesktopAction execString is a launchable command')

const rows = Preview.previewRows([
  { address: '0x1', title: 'Files', workspaceId: 2, minimized: true },
  { address: '', title: 'ghost' }
])
assertEqual(rows.length, 1, 'preview model drops windows without an address')
assertEqual(rows[0].title, 'Files', 'preview keeps the window title')
assertEqual(rows[0].workspace, '2', 'preview keeps the workspace id')
assertEqual(rows[0].minimized, true, 'preview keeps minimized state')

assertEqual(
  notifications.badgeCountForApp([{ app: 'Google Chrome' }, { app: 'Files' }], 'google-chrome', 'Chrome'),
  1,
  'badges count notifications for the matching app'
)
assertEqual(notifications.badgeCountForApp([{ app: 'Files' }], '', ''), 0, 'badges do not invent a match from empty ids')

assertDeepEqual(
  qs.hostedPanelIds(),
  ['omarchy.network', 'omarchy.bluetooth', 'omarchy.audio', 'omarchy.monitor', 'omarchy.power'],
  'Quick Settings hosts the existing control panels'
)
assertEqual(qs.tiles().length, 9, 'Quick Settings ships the Phase 4 tile set')
JS
pass "jump lists, previews, badges, and Quick Settings compose existing backends"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
HOME="$tmp/home"
mkdir -p "$HOME/.local/state/omarchy/ultimate"
cat >"$HOME/.local/state/omarchy/ultimate/taskbar-pins.json" <<'JSON'
{
  "pins": [
    {
      "id": "google-chrome",
      "desktopId": "google-chrome",
      "name": "Chrome",
      "icon": "google-chrome"
    }
  ]
}
JSON
bash -euo pipefail "$ROOT/migrations/1788042000.sh"
python3 - <<'PY'
import json, os, pathlib
pins = json.loads((pathlib.Path(os.environ["HOME"]) / ".local/state/omarchy/ultimate/taskbar-pins.json").read_text())["pins"]
assert pins[0]["desktopId"] == "google-chrome"
assert pins[-1]["desktopId"] == "org.omarchy.AgentCenter"
PY
pass "Agent Center pin migration is idempotent for existing Superbar pins"

bash -euo pipefail "$ROOT/migrations/1788042000.sh"
python3 - <<'PY'
import json, os, pathlib
pins = json.loads((pathlib.Path(os.environ["HOME"]) / ".local/state/omarchy/ultimate/taskbar-pins.json").read_text())["pins"]
assert sum(1 for pin in pins if pin["desktopId"] == "org.omarchy.AgentCenter") == 1
PY
pass "Agent Center pin migration does not duplicate the pin"

mkdir -p "$HOME/.local/share/applications"
OMARCHY_PATH="$ROOT" bash -euo pipefail "$ROOT/migrations/1788042100.sh"
[[ -f $HOME/.local/share/applications/org.omarchy.AgentCenter.desktop ]] \
  || fail "Agent Center launcher is published into the user applications dir"
grep -Fq 'Actions=Tasks;Approvals;Automations;' \
  "$HOME/.local/share/applications/org.omarchy.AgentCenter.desktop" \
  || fail "published Agent Center launcher keeps desktop actions"
pass "Agent Center desktop launcher is published for jump lists"
