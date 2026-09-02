#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const Launch = requireFromRoot('shell/Commons/Launch.js')

const cursorArgv = ['/usr/bin/cursor', '--password-store=gnome-libsecret']
assertEqual(
  String(cursorArgv),
  '/usr/bin/cursor,--password-store=gnome-libsecret',
  'JS Array.toString comma-joins argv (the metal uwsm check_path failure mode)'
)
assertEqual(
  Launch.argvFrom(cursorArgv).join(' '),
  '/usr/bin/cursor --password-store=gnome-libsecret',
  'argvFrom space-joins cursor argv instead of comma-joining'
)

const uwsmArgv = ['uwsm-app', '--', '/home/jesse/.local/bin/cursor-wayland']
assertEqual(
  String(uwsmArgv),
  'uwsm-app,--,/home/jesse/.local/bin/cursor-wayland',
  'JS Array.toString comma-joins uwsm argv (the nested bash -lc failure mode)'
)
assertDeepEqual(
  Launch.argvFrom(uwsmArgv),
  ['uwsm-app', '--', '/home/jesse/.local/bin/cursor-wayland'],
  'argvFrom keeps uwsm argv as separate tokens'
)

const qvector = { length: 3, 0: '/usr/bin/cursor', 1: '--password-store=gnome-libsecret', 2: '%F' }
assert(Launch.isArgvList(qvector), 'QML length-list is an argv list')
assert(!Launch.isArgvList('/usr/bin/cursor --password-store=gnome-libsecret'), 'strings are not argv lists')
assert(!Launch.isArgvList(null), 'null is not an argv list')
assertDeepEqual(
  Launch.argvFrom(qvector),
  ['/usr/bin/cursor', '--password-store=gnome-libsecret'],
  'argvFrom copies a QML length-list and drops %F-style fields'
)
assertEqual(
  Launch.argvFrom(qvector).join(' ').indexOf(','),
  -1,
  'space-joined length-list launch line has no comma-joined path'
)

assertDeepEqual(
  Launch.argvFrom('omarchy-launch-files --source desktop files.this-pc %F'),
  ['omarchy-launch-files', '--source', 'desktop', 'files.this-pc'],
  'argvFrom splits an Exec string and drops trailing field codes'
)
assertDeepEqual(
  Launch.resolveLaunchArgv(['omarchy-launch-files', '--source', 'desktop', 'files.this-pc'], '/opt/omarchy'),
  ['/opt/omarchy/bin/omarchy-launch-files', '--source', 'desktop', 'files.this-pc'],
  'resolveLaunchArgv prefixes omarchy-* from OMARCHY_PATH'
)
assertDeepEqual(
  Launch.copyArgv(qvector),
  ['/usr/bin/cursor', '--password-store=gnome-libsecret', '%F'],
  'copyArgv flattens a length-list without treating it as one -lc string'
)

const utilQml = fs.readFileSync(path.join(root, 'shell/Commons/Util.qml'), 'utf8')
assert(
  /function execDetached\(command\) \{[\s\S]*?Launch\.isArgvList\(command\)[\s\S]*?root\.execArgv\(command\)[\s\S]*?Quickshell\.execDetached\(\["bash", "-lc", command\]\)/.test(utilQml),
  'Util.execDetached routes argv lists through execArgv and keeps string bash -lc'
)
assert(
  utilQml.includes('Launch.copyArgv(argv)'),
  'Util.execArgv copies length-lists before concat so bash -lc never receives a nested array'
)

const appLibraryQml = fs.readFileSync(path.join(root, 'shell/services/AppLibrary.qml'), 'utf8')
assert(
  /function launchCommand\(command\) \{[\s\S]*?Util\.isArgvList\(command\)[\s\S]*?Util\.argvFrom\(command\)\.join\(" "\)/.test(appLibraryQml),
  'AppLibrary.launchCommand space-joins argv lists instead of String(array)'
)
assert(
  appLibraryQml.indexOf('Util.isArgvList(command)') < appLibraryQml.indexOf('raw = String(command || "")'),
  'AppLibrary.launchCommand checks argv lists before String()'
)

const desktopQml = fs.readFileSync(path.join(root, 'shell/plugins/desktop-icons/DesktopIcons.qml'), 'utf8')
assert(
  desktopQml.includes('Util.execArgv(["uwsm-app", "--"].concat(argv))'),
  'DesktopIcons launches Exec through uwsm argv'
)
assert(
  !desktopQml.includes('Util.execDetached("uwsm-app -- "'),
  'DesktopIcons does not string-concat Exec into bash -lc'
)

const fromExec = Launch.resolveLaunchArgv(cursorArgv, '')
const desktopLaunch = ['uwsm-app', '--'].concat(fromExec)
assertDeepEqual(
  desktopLaunch,
  ['uwsm-app', '--', '/usr/bin/cursor', '--password-store=gnome-libsecret'],
  'DesktopIcons uwsm execArgv keeps cursor tokens separate'
)
assertEqual(
  String(desktopLaunch),
  'uwsm-app,--,/usr/bin/cursor,--password-store=gnome-libsecret',
  'stringifying that execArgv is the comma-join path DesktopIcons must not take'
)
JS

python3 - "$ROOT" <<'PY' || fail "desktop icon lister emits Exec as argv, not a joined string"
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
    (desktop / "Cursor.desktop").write_text(
        "[Desktop Entry]\nName=Cursor\nExec=/usr/bin/cursor --password-store=gnome-libsecret %F\n",
        encoding="utf-8",
    )
    env = os.environ.copy()
    env["HOME"] = tmp
    env["XDG_DESKTOP_DIR"] = str(desktop)
    out = subprocess.check_output(["python3", str(root / "shell/plugins/desktop-icons/list-desktop.py")], env=env, text=True)
    data = json.loads(out)
    item = next(row for row in data["items"] if row["name"] == "Cursor")
    assert item["command"] == ["/usr/bin/cursor", "--password-store=gnome-libsecret"], item
    joined = ",".join(item["command"])
    assert joined == "/usr/bin/cursor,--password-store=gnome-libsecret"
    assert " " not in joined
PY

pass "launch argv helpers reject comma-joined uwsm paths"
