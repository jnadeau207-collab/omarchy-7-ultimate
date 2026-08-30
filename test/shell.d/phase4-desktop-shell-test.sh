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
    'format: "HH:mm\\nddd M/d"',
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

grep -Fq 'import "." as Files' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "Files application registers FilesRecordCard from its directory"
grep -Fq 'Files.FilesRecordCard' "$ROOT/shell/apps/ultimate-files/FilesApplication.qml" \
  || fail "This PC records use the Files record card type"
grep -Fq 'actionId: "ThisPC"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start Computer opens the Files This PC action"
grep -Fq 'actionId: "Pictures"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start Pictures opens the Files Pictures action"
if grep -Fq 'xdg-open' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start places must not fall through to xdg-open / Nautilus"
fi
grep -Fq 'icon: "system-file-manager"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start Files place uses the Files desktop icon, not a Settings gear"
python3 - "$ROOT" <<'PY' || fail "Files, Software, and Compatibility launchers are executable for uwsm-app"
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
wanted = {
    "bin/omarchy-launch-files",
    "bin/omarchy-launch-software",
    "bin/omarchy-launch-compatibility",
}
staged = subprocess.check_output(["git", "-C", str(root), "ls-files", "--stage", *sorted(wanted)], text=True)
modes = {}
for line in staged.splitlines():
    mode, _sha, rest = line.split(None, 2)
    path = rest.split("\t", 1)[-1]
    modes[path] = mode
missing = [path for path in wanted if modes.get(path) != "100755"]
if missing:
    raise SystemExit(f"not executable in git: {missing} {modes}")
PY
grep -Fq 'function placeAction' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start places reuse published desktop actions"
grep -Fq 'name: "Agent Center"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start exposes Agent Center as a destination"
grep -Fq 'org.omarchy.Files' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start exposes Files as a destination"
grep -Fq 'org.omarchy.Settings' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start exposes Settings as a destination"
grep -Fq 'Ui.SettingsHostedPanel' "$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml" \
  || fail "Settings window hosts existing panel pages"
grep -Fq 'function hostedPanel' "$ROOT/shell/apps/ultimate-settings/SettingsModel.js" \
  || fail "Settings maps Network/Bluetooth/Power onto existing panels"
if grep -Fq 'plugins/panels/monitor/Panel.qml' "$ROOT/shell/apps/ultimate-settings/SettingsModel.js"; then
  fail "Settings Display does not host the Process/hyprctl monitor panel"
fi
if grep -Fq 'plugins/panels/audio/Panel.qml' "$ROOT/shell/apps/ultimate-settings/SettingsModel.js"; then
  fail "Settings Sound does not host the Process/pactl audio panel"
fi
grep -Fq 'display.inspect' "$ROOT/shell/apps/ultimate-settings/SettingsModel.js" \
  || fail "Settings Display reads the existing Fabric display.inspect inventory"
grep -Fq 'audio.inspect' "$ROOT/shell/apps/ultimate-settings/SettingsModel.js" \
  || fail "Settings Sound reads the existing Fabric audio.inspect inventory"
grep -Fq 'Ui/SettingsPersonalizationHost.qml' "$ROOT/shell/apps/ultimate-settings/SettingsModel.js" \
  || fail "Settings Personalization hosts the existing image picker"
grep -Fq 'property bool embedMode: false' "$ROOT/shell/plugins/image-picker/ImagePicker.qml" \
  || fail "image picker can embed inside Settings chrome"
if grep -Fq 'id: "omarchy.monitor"' "$ROOT/shell/plugins/ultimate-settings/Settings.qml"; then
  fail "Settings is not a five-button overlay that dismisses into floating panels"
fi
python3 - "$ROOT" <<'PY' || fail "hosted Settings pages keep KeyboardPanel out of the Settings process"
from pathlib import Path
import sys

root = Path(sys.argv[1])
panels = [
    "shell/plugins/panels/monitor/Panel.qml",
    "shell/plugins/panels/audio/Panel.qml",
    "shell/plugins/panels/network/Panel.qml",
    "shell/plugins/panels/bluetooth/Panel.qml",
    "shell/plugins/panels/power/Panel.qml",
]
for rel in panels:
    text = (root / rel).read_text(encoding="utf-8")
    if "id: embedHost" not in text:
        raise SystemExit(f"{rel} missing embedHost")
    if "property bool embedMode" not in text:
        raise SystemExit(f"{rel} missing embedMode")
    if "id: overlayLoader" not in text:
        raise SystemExit(f"{rel} missing overlayLoader")
    if "overlayReady" not in text:
        raise SystemExit(f"{rel} arms KeyboardPanel only after Settings inject")
    if "function adoptOverlayPage" not in text:
        raise SystemExit(f"{rel} missing overlay adopt")
keyboard = (root / "shell/Ui/KeyboardPanel.qml").read_text(encoding="utf-8")
if "pageHost" not in keyboard:
    raise SystemExit("KeyboardPanel does not expose pageHost for Superbar overlay adopt")
PY
pass "Settings embeds panel pages without constructing a layer-shell KeyboardPanel"
grep -Fq 'All programs' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start keeps an All programs list"
grep -Fq 'Pictures' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start keeps a Pictures place"
grep -Fq 'Computer' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start keeps a Computer place"
grep -Fq 'userInitial' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start shows the session account"
pass "Start has Files, Settings, Agent Center, places, and All programs"

grep -Fq 'launchAgentCenter' "$ROOT/shell/plugins/agents/Panel.qml" \
  || fail "agents panel can open Agent Center"
grep -Fq 'Open Agent Center' "$ROOT/shell/plugins/agents/Panel.qml" \
  || fail "agents panel shows Open Agent Center"
pass "agents panel is a launch shim to Agent Center"

jq -e '.pins[-1].desktopId == "org.omarchy.AgentCenter" and .pins[-1].icon == "org.omarchy.AgentCenter"' \
  "$ROOT/default/ultimate/taskbar-pins.json" >/dev/null \
  || fail "shipped Superbar pins include Agent Center with its own mark"
pass "Agent Center is a shipped Superbar pin"

grep -Fq 'Icon=org.omarchy.AgentCenter' "$ROOT/applications/org.omarchy.AgentCenter.desktop" \
  || fail "Agent Center desktop entry uses a distinct icon"
grep -Fq 'Icon=system-run' "$ROOT/applications/org.omarchy.Agent.desktop" \
  || fail "Agent keeps system-run so the two marks stay different"
[[ -f $ROOT/default/icons/hicolor/scalable/apps/org.omarchy.AgentCenter.svg ]] \
  || fail "Agent Center ships a scalable mark"
pass "Agent Center icon is distinct from Agent"

jq -e '.id == "omarchy.desktop-icons" and (.kinds | index("service"))' \
  "$ROOT/shell/plugins/desktop-icons/manifest.json" >/dev/null \
  || fail "desktop icons are a first-party service plugin"
grep -Fq 'desktopIcons' "$ROOT/shell/plugins/desktop-icons/DesktopIcons.qml" \
  || fail "desktop icon surface is gated by the profile flag"
grep -Fq 'omarchy-desktop-icons' "$ROOT/shell/plugins/desktop-icons/DesktopIcons.qml" \
  || fail "desktop icon surface uses its own layer namespace"
pass "desktop icon surface exists"

python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["cardWidth"], json.load(open(sys.argv[1]))["cardHeight"])' \
  "$ROOT/default/ultimate/start-chrome.json" | grep -Fx '720 640' >/dev/null \
  || fail "Start chrome is the two-pane 720x640 card"
[[ -f $ROOT/default/systemd/user/omarchy-fabric-checkout.service ]] \
  || fail "checkout Fabric unit exists for machines without /usr/bin/omarchy-fabricd"
if grep -Fx 'ProtectKernelTunables=yes' "$ROOT/default/systemd/user/omarchy-fabric-checkout.service" >/dev/null; then
  fail "checkout Fabric unit ProtectKernelTunables prevents bubblewrap from mounting /proc"
fi
if grep -Fx 'ProtectKernelLogs=yes' "$ROOT/default/systemd/user/omarchy-fabric-checkout.service" >/dev/null; then
  fail "checkout Fabric unit ProtectKernelLogs prevents bubblewrap from mounting /proc"
fi
pass "Start chrome and checkout Fabric unit are shipped"

python3 - "$ROOT" <<'PY' || fail "desktop-actions parser reads Chrome-style Actions"
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
desktop = """[Desktop Entry]
Name=Chrome
Exec=google-chrome %U
Actions=NewWindow;NewIncognitoWindow;

[Desktop Action NewWindow]
Name=New Window
Exec=google-chrome

[Desktop Action NewIncognitoWindow]
Name=New Incognito Window
Exec=google-chrome --incognito
"""
with tempfile.TemporaryDirectory() as tmp:
    apps = Path(tmp) / ".local" / "share" / "applications"
    apps.mkdir(parents=True)
    (apps / "google-chrome.desktop").write_text(desktop, encoding="utf-8")
    env = os.environ.copy()
    env["HOME"] = tmp
    env["XDG_DATA_DIRS"] = tmp
    out = subprocess.check_output(["python3", str(root / "shell/services/desktop-actions.py")], env=env, text=True)
    data = json.loads(out)
    assert data["google-chrome"][1]["name"] == "New Incognito Window"
    assert "--incognito" in data["google-chrome"][1]["command"]
PY
pass "desktop-actions parser reads Chrome-style Actions"

python3 - "$ROOT" <<'PY' || fail "desktop icon lister reads the real Desktop directory"
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    desktop = Path(tmp) / "Desktop"
    desktop.mkdir()
    (desktop / "notes.txt").write_text("hello\n", encoding="utf-8")
    (desktop / "Computer.desktop").write_text(
        "[Desktop Entry]\nName=Computer\nExec=omarchy-launch-files --source desktop files.this-pc\nIcon=computer\n",
        encoding="utf-8",
    )
    env = os.environ.copy()
    env["HOME"] = tmp
    env["XDG_DESKTOP_DIR"] = str(desktop)
    out = subprocess.check_output(["python3", str(root / "shell/plugins/desktop-icons/list-desktop.py")], env=env, text=True)
    data = json.loads(out)
    assert data["directory"] == str(desktop)
    by_name = {item["name"]: item for item in data["items"]}
    assert by_name["notes.txt"]["kind"] == "file"
    assert by_name["Computer"]["kind"] == "application"
    assert by_name["Computer"]["command"] == "omarchy-launch-files --source desktop files.this-pc"
    env["XDG_DESKTOP_DIR"] = tmp
    out = subprocess.check_output(["python3", str(root / "shell/plugins/desktop-icons/list-desktop.py")], env=env, text=True)
    data = json.loads(out)
    assert data["directory"] == str(Path(tmp) / "Desktop"), data
    assert data["directory"] != tmp
    names = [item["name"] for item in data["items"]]
    assert "notes.txt" in names
    assert "Computer" in names
PY
pass "desktop icon lister reads the real Desktop directory"

[[ -f $ROOT/default/ultimate/desktop/Files.desktop ]] \
  || fail "Desktop Mode ships a Files desktop shortcut"
[[ -f $ROOT/default/ultimate/desktop/Computer.desktop ]] \
  || fail "Desktop Mode ships a Computer desktop shortcut"
grep -Fq 'files.this-pc' "$ROOT/default/ultimate/desktop/Computer.desktop" \
  || fail "Desktop Computer shortcut opens Files This PC"
grep -Fq 'launchCommand' "$ROOT/shell/plugins/desktop-icons/DesktopIcons.qml" \
  || fail "Desktop shortcuts launch through the same AppLibrary path as Start"
grep -Fq 'JumpList.actionCommand(root.entryByDesktopId(id))' "$ROOT/shell/services/AppLibrary.qml" \
  || fail "Superbar pin launch reads the desktop Exec before gtk-launch"
grep -Fq 'root.omarchyPath + "/bin/omarchy-"' "$ROOT/shell/services/AppLibrary.qml" \
  || fail "Superbar pin launch quotes omarchy-* from OMARCHY_PATH"
grep -Fq 'uwsm-app --' "$ROOT/shell/plugins/desktop-icons/DesktopIcons.qml" \
  || fail "Desktop shortcuts use the uwsm session graph"
grep -Fq 'xdg-user-dirs-update --set DESKTOP "$HOME/Desktop"' "$ROOT/bin/omarchy-provision-user" \
  || fail "new users keep a real Desktop directory"
if grep -Fq 'xdg-user-dirs-update --set DESKTOP "$HOME"' "$ROOT/bin/omarchy-provision-user"; then
  fail "provision-user must not fold Desktop back into HOME"
fi
pass "Desktop Mode keeps a real Desktop directory"

grep -Fq 'userName' "$ROOT/shell/plugins/lock/LockView.qml" \
  || fail "lock shows the session user"
grep -Fq 'SystemClock' "$ROOT/shell/plugins/lock/LockView.qml" \
  || fail "lock shows a clock"
grep -Fq 'Tokens.text.primary' "$ROOT/shell/plugins/lock/LockView.qml" \
  || fail "lock reads text from the token pipeline"
grep -Fq 'Tokens.surface.canvas' "$ROOT/shell/plugins/lock/LockView.qml" \
  || fail "lock fill reads canvas from the token pipeline"
if grep -Fq 'Color.lock' "$ROOT/shell/plugins/lock/LockView.qml"; then
  fail "lock must not keep a private Color.lock palette"
fi
if grep -Fq 'Color.background' "$ROOT/shell/plugins/lock/LockView.qml"; then
  fail "lock must not keep a private Color.background fill"
fi
if grep -Fq 'Color.tooltip' "$ROOT/shell/Ui/PanelToolTip.qml" "$ROOT/shell/Ui/Button.qml"; then
  fail "Phase 4 shared tooltips must not keep Color.tooltip"
fi
if grep -Fq 'Color.notifications' "$ROOT/shell/plugins/notifications/components/NotificationCard.qml"; then
  fail "Phase 4 NC card must not keep Color.notifications"
fi
pass "lock shows clock and user"

grep -Fq 'text: "Calendar"' "$ROOT/shell/plugins/panels/clock/Panel.qml" \
  || fail "clock panel names itself Calendar"
pass "calendar surface is the clock panel"

grep -Fq 'OMARCHY_PATH' "$ROOT/shell/services/desktop-actions.py" \
  || fail "desktop-action index reads product launchers from OMARCHY_PATH"
grep -Fq 'function jumpListFor' "$ROOT/shell/services/AppLibrary.qml" \
  || fail "AppLibrary exposes jump lists"
grep -Fq 'Open new window' "$ROOT/shell/services/JumpList.js" \
  || fail "Superbar jump lists include Open new window"
grep -Fq 'previewRows' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "Superbar peek uses the structured preview model"
grep -Fq '_capturePreview' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "Superbar peek captures live window thumbnails"
grep -Fq 'capture-window-preview.sh' "$ROOT/shell/services/WindowService.qml" \
  || fail "window preview capture uses the grim helper"
[[ -f $ROOT/shell/services/capture-window-preview.sh ]] \
  || fail "window preview capture helper exists"
if bash "$ROOT/shell/services/capture-window-preview.sh" a 0 100 100 /tmp/peek.png 2>/dev/null; then
  fail "preview helper rejects non-integer geometry"
fi
if bash "$ROOT/shell/services/capture-window-preview.sh" 0 0 1 1 /tmp/peek.png 2>/dev/null; then
  fail "preview helper rejects geometry that is too small"
fi
pass "window preview helper rejects invalid geometry"
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

const fromIndex = JumpList.jumpListFor(null, 'google-chrome', {
  'google-chrome': [{ id: 'NewIncognitoWindow', name: 'New Incognito Window', command: 'google-chrome --incognito', kind: 'desktop-action' }]
})
assertEqual(fromIndex.length, 2, 'jump lists fall back to parsed desktop Actions')
assertEqual(fromIndex[1].name, 'New Incognito Window', 'Chrome extra Actions stay on the jump list')
assertDeepEqual(JumpList.desktopIdAliases('google-chrome').slice(0, 2), ['google-chrome', 'google-chrome-stable'], 'Chrome desktop ids alias')

const rows = Preview.previewRows([
  { address: '0x1', title: 'Files', workspaceId: 2, minimized: true, at: [10, 20], size: [800, 600] },
  { address: '', title: 'ghost' }
])
assertEqual(rows.length, 1, 'preview model drops windows without an address')
assertEqual(rows[0].title, 'Files', 'preview keeps the window title')
assertEqual(rows[0].workspace, '2', 'preview keeps the workspace id')
assertEqual(rows[0].minimized, true, 'preview keeps minimized state')
assertEqual(rows[0].capturable, false, 'minimized windows do not invent a thumbnail')
assertEqual(rows[0].width, 800, 'preview keeps compositor width')

const mapped = Preview.previewRow({ address: '0x2', title: 'Chrome', at: [100, 80], size: [1280, 720], hidden: false })
assertEqual(mapped.capturable, true, 'mapped windows expose geometry for grim')
assertEqual(mapped.x, 100, 'preview keeps compositor x')
assertEqual(Preview.geometry({ size: [0, 10] }), null, 'zero-area windows have no geometry')

const qvectorWindows = {
  length: 1,
  0: { address: '0xac', title: 'Agent Center', workspaceId: 1, minimized: false }
}
const qvectorRows = Preview.previewRows(qvectorWindows)
assertEqual(qvectorRows.length, 1, 'Quickshell window lists stay previewable')
assertEqual(qvectorRows[0].title, 'Agent Center', 'QVector window title survives')
assertEqual(qvectorRows[0].workspace, '1', 'QVector workspace id survives')

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

OMARCHY_PATH="$ROOT" bash -euo pipefail "$ROOT/migrations/1788042200.sh"
[[ -f $HOME/.local/share/icons/hicolor/scalable/apps/org.omarchy.AgentCenter.svg ]] \
  || fail "Agent Center mark is published into the user icon theme"
grep -Fq 'Icon=org.omarchy.AgentCenter' "$HOME/.local/share/applications/org.omarchy.AgentCenter.desktop" \
  || fail "published Agent Center launcher uses the distinct mark"
pass "Agent Center mark is published"

OMARCHY_PATH="$ROOT" python3 "$ROOT/shell/services/desktop-actions.py" | python3 -c '
import json, sys
idx = json.load(sys.stdin)
files = idx.get("org.omarchy.Files") or []
names = [row.get("name") for row in files]
assert "This PC" in names, names
assert "Pictures" in names, names
assert "Recent" in names, names
assert "Trash" in names, names
settings = idx.get("org.omarchy.Settings") or []
assert any(row.get("name") == "Display" for row in settings), settings
assert any(row.get("name") == "Personalization" for row in settings), settings
'
pass "product desktop Actions are indexed from OMARCHY_PATH"

OMARCHY_PATH="$ROOT" bash -euo pipefail "$ROOT/migrations/1788042600.sh"
OMARCHY_PATH="$ROOT" bash -euo pipefail "$ROOT/migrations/1788042700.sh"
OMARCHY_PATH="$ROOT" bash -euo pipefail "$ROOT/migrations/1788042800.sh"
chmod +x "$ROOT/bin/omarchy-launch-files"
[[ -x $ROOT/bin/omarchy-launch-files ]] \
  || fail "Files launcher stays executable after the Superbar pin repair"
[[ -f $HOME/.local/share/applications/org.omarchy.Files.desktop ]] \
  || fail "Files launcher is published into the user applications dir"
grep -Fq 'Actions=ThisPC;Pictures;Recent;Trash;' \
  "$HOME/.local/share/applications/org.omarchy.Files.desktop" \
  || fail "published Files launcher keeps This PC, Pictures, Recent, and Trash"
grep -Fq 'Actions=Display;Network;Personalization;Accessibility;' \
  "$HOME/.local/share/applications/org.omarchy.Settings.desktop" \
  || fail "published Settings launcher keeps Display, Network, Personalization, and Accessibility"
pass "Files and Settings launchers are published for Start jump lists"

grep -Fq 'Tokens.typography.family' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar clock uses the token UI family"
grep -Fq 'Tokens.accessibility.highContrast' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar glass reads Tokens.accessibility"
grep -Fq 'Tokens.border.strong' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar HC glass uses stronger Tokens.border"
grep -Fq 'bar.highContrast' "$ROOT/shell/plugins/ultimate-taskbar/StartButton.qml" \
  || fail "Start orb HC stroke is not a private color"
grep -Fq 'bar.highContrast' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "task buttons read Superbar high-contrast chrome"
grep -Fq 'Tokens.border.strong' "$ROOT/shell/plugins/ultimate-taskbar/TrayCluster.qml" \
  || fail "tray cluster reads Tokens.border.strong"
grep -Fq 'Tokens.border.strong' "$ROOT/shell/Ui/WidgetButton.qml" \
  || fail "clock and tray marks read Tokens.border.strong"
grep -Fq 'Semantics.duration(null, 140)' "$ROOT/shell/Ui/WidgetButton.qml" \
  || fail "Superbar WidgetButton opacity follows reduced motion"
grep -Fq 'Semantics.duration(null, 160)' "$ROOT/shell/Ui/WidgetButton.qml" \
  || fail "Superbar WidgetButton color follows reduced motion"
grep -Fq 'Semantics.duration(null, 140)' "$ROOT/shell/Ui/KeyboardPanel.qml" \
  || fail "QS, NC, and calendar panel fade follows reduced motion"
grep -Fq 'Semantics.duration(null, 100)' "$ROOT/shell/plugins/notifications/components/NotificationCard.qml" \
  || fail "Notification card hover follows reduced motion"
grep -Fq 'Semantics.duration(null, 160)' "$ROOT/shell/plugins/panels/clock/Panel.qml" \
  || fail "calendar bars follow reduced motion"
grep -Fq 'hasVisualContent: true' "$ROOT/shell/plugins/ultimate-quick-settings/BarWidget.qml" \
  || fail "Quick Settings Superbar mark is drawn, not a leftover glyph"
if grep -Fq '⊞' "$ROOT/shell/plugins/ultimate-quick-settings/BarWidget.qml"; then
  fail "Quick Settings Superbar mark is not a leftover boxed-plus glyph"
fi
grep -Fq 'hasVisualContent: true' "$ROOT/shell/plugins/notifications/BarWidget.qml" \
  || fail "Notification Center Superbar mark is drawn, not a leftover glyph"
if grep -Fq '◎' "$ROOT/shell/plugins/notifications/BarWidget.qml"; then
  fail "Notification Center Superbar mark is not a leftover bullseye glyph"
fi
pass "Superbar notification-area marks are drawn chrome"

grep -Fq 'function showTooltip' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar hosts hover tooltips"
grep -Fq 'tooltipHovered' "$ROOT/shell/plugins/ultimate-taskbar/StartButton.qml" \
  || fail "Start orb reports tooltip hover"
grep -Fq 'HoverHandler' "$ROOT/shell/plugins/ultimate-taskbar/StartButton.qml" \
  || fail "Start orb hover uses the layer HoverHandler"
grep -Fq '"Shut down"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start has a labeled Shut down control"
grep -Fq 'semanticPlaceholderText: "Search programs"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start search names the job"
grep -Fq 'def _location_query_availability' "$ROOT/default/fabric/omarchy_fabric/providers/files/provider.py" \
  || fail "Files browse reports the selected location availability"
grep -Fq 'files.location-absent' "$ROOT/default/fabric/omarchy_fabric/providers/files/provider.py" \
  || fail "optional missing Files locations stay location-local"
grep -Fq 'next.phase = "available"' "$ROOT/shell/apps/ultimate-files/FilesModel.js" \
  || fail "Files Pictures can show AVAILABLE without inheriting catalog degradation"
grep -Fq 'LOCATION_ENTRY_FLOOR' "$ROOT/default/fabric/omarchy_fabric/providers/files/provider.py" \
  || fail "Files byte-bound eviction keeps a per-location record floor"
grep -Fq 'function placeEntries' "$ROOT/shell/apps/ultimate-files/FilesModel.js" \
  || fail "Files Home and This PC surface place records from the inspect inventory"
grep -Fq 'function pageAvailability' "$ROOT/shell/apps/ultimate-files/FilesModel.js" \
  || fail "This PC reports the virtual this-pc location instead of workspace degradation"
grep -Fq 'function searchDestinations' "$ROOT/shell/services/AppSearch.js" \
  || fail "Start search injects Settings and place destinations"
grep -Fq 'AppSearch.searchDestinations(query, values)' "$ROOT/shell/services/AppLibrary.qml" \
  || fail "AppLibrary merges Start destinations into app search"
grep -Fq 'entry.kind === "destination"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start launches search destinations through place / jump actions"
python3 -c "
from pathlib import Path
text = Path(r'$ROOT/shell/plugins/ultimate-start/Start.qml').read_text()
start = text.index('function open(payloadJson)')
end = text.index('function close()')
body = text[start:end]
assert 'searchField' not in body, body
print('ok - Start open does not touch searchField before the card Loader is active')
"
if grep -Fq 'id: "omarchy.start.accessibility"' "$ROOT/shell/services/AppSearch.js"; then
  fail "Start search does not invent an Accessibility destination"
fi
grep -Fq 'productProfile.text("Recent")' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start has a Recent section for launched programs"
grep -Fq 'kind === "letter"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "All programs is letter-grouped"
grep -Fq 'start-recents.json' "$ROOT/shell/services/AppLibrary.qml" \
  || fail "launches persist Start recents"
grep -Fq 'folder-pictures' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start places keep icons"
grep -Fq 'function groupsOnScreen' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar filters task groups per output"
grep -Fq 'showsNotificationCluster' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar keeps the notification cluster on the primary output"
grep -Fq 'payload.pseudoLocale === true' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start pseudo-locale is the existing SemanticProfile summon flag"
grep -Fq 'pseudoLocale: root.summonedPseudoLocale || root.summonedLocale === "pseudo"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start pseudo-locale binds the product SemanticProfile"
grep -Fq 'productProfile.text(modelData.name)' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start places run through the existing SemanticProfile text transform"
grep -Fq 'payload.rtl === true' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start RTL is the existing SemanticProfile summon flag"
grep -Fq 'LayoutMirroring.enabled: productProfile.rtl' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start card mirrors when the product profile is RTL"
grep -Fq 'shell.summonedRtl' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start publishes RTL onto the shared shell flag"
grep -Fq 'LayoutMirroring.enabled: root.rtl' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar mirrors when Start RTL is summoned"
grep -Fq 'Qt.application.layoutDirection === Qt.RightToLeft' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar RTL keeps the Qt layoutDirection bind"
grep -Fq 'payload.screen' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start opens on the Superbar that summoned it"
grep -Fq 'restoreFocusOnClose' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start restores focus only when the same orb closes it"
grep -Fq 'start-owner.json' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Start click-through knows which output owns the card"
grep -Fq 'Pin to taskbar' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start right-click can pin to the Superbar"
grep -Fq 'Unpin from taskbar' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start right-click can unpin from the Superbar"
grep -Fq 'windowService.pin' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start pin uses the Superbar pin verb"
grep -Fq 'windowService.unpin' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start unpin uses the Superbar unpin verb"
grep -Fq 'acceptedButtons: Qt.LeftButton | Qt.RightButton' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start tiles accept a right-click"
grep -Fq 'pinMenuJumpList' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start context menu hosts the same jump list as Superbar"
grep -Fq 'id: startCard' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start pin menu lives on the Start card"
grep -Fq 'mapToItem(startCard' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start pin menu positions inside the Start card"
grep -Fq 'morePowerOpen' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start power flyout is a card-owned flag, not a PopupWindow"
grep -Fq 'function toggleMorePower' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start power flyout toggles on the Start card"
if grep -Fq 'PopupWindow' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start power flyout must live on the Start card, not a PopupWindow"
fi
if awk '
  $0 ~ /function close\(\)/ { infn = 1 }
  infn && /pinMenu\.visible/ { found = 1 }
  infn && /^  function / && $0 !~ /function close\(\)/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start close must not touch the pin menu id inside the Loader"
fi
pass "Superbar tooltips and Start power flyout are product chrome"
