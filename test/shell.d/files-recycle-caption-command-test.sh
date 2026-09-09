#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
command_bar="$ROOT/shell/apps/ultimate-files/ExplorerCommandBar.qml"
theme="$ROOT/shell/apps/ultimate-files/ExplorerTheme.js"
host="$ROOT/shell/apps/shared/ProductAppHost.qml"
windows="$ROOT/default/hypr/desktop-windows.lua"
csd="$ROOT/default/ultimate/csd-clients.json"
leftover="$ROOT/test/acceptance.d/leftovers/win7-visual/leftover.json"

[[ -f $files_app ]] || fail "Files application exists"
[[ -f $command_bar ]] || fail "Files command bar exists"

grep -Fq 'readonly property bool paintsOwnTitleBar: true' "$files_app" ||
  fail "Files must paint one glass caption"
grep -Fq 'readonly property string sharedCaptionPath: "files-glass"' "$files_app" ||
  fail "Files caption path is the glass caption"
if grep -Fq 'text: root.routeTitle' "$files_app"; then
  fail "Files must not paint a second place-title row"
fi
if grep -Fq 'sharedCaptionPath: "hyprbars"' "$files_app"; then
  fail "Files must not keep a hyprbars caption"
fi

if grep -Fq 'org.omarchy.Files' "$csd"; then
  fail "org.omarchy.Files must not take hyprbars:no_bar from the CSD list"
fi
python3 - "$windows" "$ROOT/default/ultimate/chrome-tokens.json" << 'PY'
import json
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
tokens = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
line = next((row for row in text.splitlines() if 'o.window("org.omarchy.Files"' in row), "")
if not line:
    raise SystemExit("Files window rule is missing")
if "hyprbars:no_bar" not in line or "true" not in line:
    raise SystemExit("Files window rule still attaches hyprbars")
if "decorate = false" not in line:
    raise SystemExit("Files decorate flag does not stop the dark caption paint")
text_hex = str(tokens.get("hyprbarsTextHex", "")).lstrip("#").lower()
if text_hex != "20262c":
    raise SystemExit("landed caption text token is not hyprbarsTextHex #20262c")
for banned in ("bar_height", "bar_aero", "bar_text_align", "bar_color", "title_color"):
    if banned in line:
        raise SystemExit(f"Files window rule restyles hyprbars: {banned}")
if "bar_height = 30" not in text or "bar_aero = true" not in text or "icon_on_hover = false" not in text:
    raise SystemExit("shared caption factory bar is missing")
if 'bg_color = "rgba(00000000)"' not in text:
    raise SystemExit("shared caption idle glyphs are missing")
if 'hover_bg_color = chrome_hex_rgb(chrome, "captionCloseBgHex")' not in text:
    raise SystemExit("shared caption close red is not hover-only")
PY

grep -Fq 'title: root.placeTitle !== "" ? root.placeTitle : root.displayName' "$host" ||
  fail "shared caption uses the place title"
grep -Fq 'host.placeTitle = title' "$files_app" ||
  fail "Recycle Bin publishes the place title to the shared caption"
grep -Fq 'root.routeTitle' "$files_app" ||
  fail "caption place title comes from the route"

grep -Fq 'GradientStop { position: 0; color: Aero.commandTop }' "$command_bar" ||
  fail "command bar uses Aero.commandTop"
grep -Fq 'GradientStop { position: 1; color: Aero.commandBottom }' "$command_bar" ||
  fail "command bar uses Aero.commandBottom"
grep -Fq 'implicitHeight: Aero.commandHeight' "$command_bar" ||
  fail "command bar uses the Aero command height"
grep -Fq 'var commandHeight = 36' "$theme" ||
  fail "command height stays 36"
grep -Fq 'id: commandButtonFrame' "$command_bar" ||
  fail "command frame id stays off the paint path"
grep -Fq 'visible: false' "$command_bar" ||
  fail "chip frames must stay unpainted"
if grep -Fq 'visible: commandItem.commandButton' "$command_bar"; then
  fail "chip frames came back"
fi
grep -Fq 'id: commandDropdownChevron' "$command_bar" ||
  fail "Organize paints a dropdown chevron"
grep -Fq 'visible: modelData.dropdown === true' "$command_bar" ||
  fail "Organize is the only chevron"

python3 - "$files_app" "$leftover" << 'PY'
import json
import re
import sys
from pathlib import Path

files_app = Path(sys.argv[1]).read_text(encoding="utf-8")
leftover = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

def strip_fn(src, name):
    start = src.find(f"function {name}()")
    if start < 0:
        raise SystemExit(f"missing {name}")
    brace = src.find("{", start)
    depth = 0
    for index in range(brace, len(src)):
        if src[index] == "{":
            depth += 1
        elif src[index] == "}":
            depth -= 1
            if depth == 0:
                return src[start:index + 1]
    raise SystemExit(f"unclosed {name}")

actions = strip_fn(files_app, "commandActions")
trash = actions.split("if (root.trashRoute)", 1)[1]
trash = trash.split("var list =", 1)[0]
labels = re.findall(r'label: "([^"]+)"', trash)
if labels != ["Organize", "Restore", "Empty Recycle Bin", "Properties"]:
    raise SystemExit(f"Recycle Bin command strip is {labels}")
if "Connect to Server" in trash:
    raise SystemExit("Connect to Server is on the Recycle Bin command strip")
organize = trash.split("Organize", 1)[1].split("},", 1)[0]
if "dropdown: true" not in organize:
    raise SystemExit("Organize is not a dropdown command")
for label in ("Restore", "Empty Recycle Bin", "Properties"):
    item = trash.split('label: "%s"' % label, 1)[1].split("}", 1)[0]
    if "dropdown: false" not in item:
        raise SystemExit(label + " is a dropdown")
    if "dropdown: true" in item:
        raise SystemExit(label + " has a chevron")
if trash.count("dropdown: true") != 1:
    raise SystemExit("Organize is not the only chevron on the Recycle Bin strip")

if leftover.get("win7VisualLeftover") != "OPEN":
    raise SystemExit("win7VisualLeftover must stay OPEN")
wash = leftover.get("surfaces", {}).get("selectionWash", {})
if wash.get("status") != "OPEN":
    raise SystemExit("selectionWash must stay OPEN")
PY

if grep -Fq 'sessionBadge: "SESSION CONTROL"' "$files_app" "$command_bar"; then
  fail "SESSION CONTROL must not be the painted command-bar badge"
fi
if grep -Fq 'text: "SESSION CONTROL"' "$files_app" "$command_bar"; then
  fail "SESSION CONTROL must not be a painted Text on the Files window"
fi

if git -C "$ROOT" diff --name-only -- shell/apps/ultimate-settings | grep -q .; then
  fail "Settings must stay untouched"
fi
if git -C "$ROOT" diff --name-only | grep -Eq 'win7-baseline|\\.png$'; then
  fail "PNG baseline must stay untouched"
fi
if git -C "$ROOT" diff --name-only | grep -Fq 'default/hypr/plugins/hyprbars/'; then
  fail "hyprbars global theme must stay untouched"
fi

pass "Recycle Bin command strip stays Organize/Restore/Empty/Properties; Files caption is one glass caption; leftover stays OPEN; not pixel proof; not metal CLOSED"
