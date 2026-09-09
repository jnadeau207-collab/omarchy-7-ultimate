#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
command_bar="$ROOT/shell/apps/ultimate-files/ExplorerCommandBar.qml"
caption="$ROOT/shell/apps/ultimate-files/ExplorerGlassCaption.qml"
address="$ROOT/shell/apps/ultimate-files/ExplorerAddressBar.qml"
windows="$ROOT/default/hypr/desktop-windows.lua"
theme="$ROOT/shell/apps/ultimate-files/ExplorerTheme.js"
leftover="$ROOT/test/acceptance.d/leftovers/win7-visual/leftover.json"

[[ -f $caption ]] || fail "Files paints one glass caption"
grep -Fq 'readonly property bool paintsOwnTitleBar: true' "$files_app" ||
  fail "Files must own a single glass caption"
grep -Fq 'readonly property string sharedCaptionPath: "files-glass"' "$files_app" ||
  fail "Files caption path is the glass caption, not hyprbars"
grep -Fq 'Files.ExplorerGlassCaption' "$files_app" ||
  fail "Files window paints the glass caption"
if grep -Fq 'sharedCaptionPath: "hyprbars"' "$files_app"; then
  fail "Files still names hyprbars as a second caption"
fi
if grep -Fq 'text: root.routeTitle' "$files_app"; then
  fail "Files must not paint a second place-title row"
fi
if grep -Fq 'horizontalAlignment: Text.AlignHCenter' "$caption"; then
  fail "caption title must not be a centered title row"
fi
grep -Fq 'horizontalAlignment: Text.AlignLeft' "$caption" ||
  fail "caption title is left aligned"
grep -Fq 'id: captionButtons' "$caption" ||
  fail "caption owns the min/max/close cluster"

python3 - "$address" "$files_app" << 'PY'
import sys
from pathlib import Path
address = Path(sys.argv[1]).read_text(encoding="utf-8")
files_app = Path(sys.argv[2]).read_text(encoding="utf-8")
if "paintsCaptionClusterOnAddress: false" not in files_app:
    raise SystemExit("address row is not locked against a second caption cluster")
for glyph in ("×", "□", "–"):
    if glyph in address:
        raise SystemExit("address row paints a caption button")
if "direction: \"back\"" not in address or "direction: \"forward\"" not in address:
    raise SystemExit("address row is missing back/forward")
if "Search " not in files_app:
    raise SystemExit("address search is missing")
PY

python3 - "$windows" << 'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
line = next((row for row in text.splitlines() if 'o.window("org.omarchy.Files"' in row), "")
if not line:
    raise SystemExit("Files window rule is missing")
if "hyprbars:no_bar" not in line or "true" not in line:
    raise SystemExit("Files still attaches the hyprbars caption")
if "decorate = false" not in line:
    raise SystemExit("Files decorate flag does not stop the compositor caption paint")
for banned in ("bar_height", "bar_aero", "bar_text_align", "bar_color", "title_color"):
    if banned in line:
        raise SystemExit(f"Files window rule restyles hyprbars: {banned}")
PY

grep -Fq 'id: commandButtonFrame' "$command_bar" || fail "command bar keeps the frame id off the paint path"
grep -Fq 'visible: false' "$command_bar" || fail "chip frames must stay unpainted"
if grep -Fq 'visible: commandItem.commandButton' "$command_bar"; then
  fail "chip frames came back on the command bar"
fi
grep -Fq 'var captionGlass = "#74b8fc"' "$theme" || fail "caption reuses captionGlassHex"
grep -Fq 'var captionCloseBg = "#b85750"' "$caption" && true
grep -Fq 'var captionCloseBg = "#b85750"' "$theme" || fail "close reuses captionCloseBgHex"
grep -Fq 'var captionText = "#20262c"' "$theme" || fail "caption text reuses hyprbarsTextHex"

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
libraries = actions.split("if (root.librariesRoute)", 1)[1].split("if (root.computerRoute)", 1)[0]
computer = actions.split("if (root.computerRoute)", 1)[1].split("var folderSelected", 1)[0]
lib_labels = re.findall(r'label: "([^"]+)"', libraries)
comp_labels = re.findall(r'label: "([^"]+)"', computer)
if lib_labels != ["Organize", "Open", "Share with", "New library"]:
    raise SystemExit(f"Libraries command strip is {lib_labels}")
if comp_labels != ["Organize", "System properties", "Uninstall or change a program", "Map network drive"]:
    raise SystemExit(f"Computer command strip is {comp_labels}")
if "Connect to Server" in libraries or "Connect to Server" in computer:
    raise SystemExit("Connect to Server is on a shot command strip")
if "SESSION CONTROL" in libraries or "SESSION CONTROL" in computer:
    raise SystemExit("SESSION CONTROL is on a shot command strip")
if leftover.get("win7VisualLeftover") != "OPEN":
    raise SystemExit("win7VisualLeftover must stay OPEN")
PY

if git -C "$ROOT" diff --name-only -- shell/apps/ultimate-settings | grep -q .; then
  fail "Settings must stay untouched"
fi
if git -C "$ROOT" diff --name-only | grep -Eq 'win7-baseline|\.png$'; then
  fail "PNG baseline must stay untouched"
fi
if git -C "$ROOT" diff --name-only | grep -Fq 'default/hypr/plugins/hyprbars/'; then
  fail "hyprbars global theme must stay untouched"
fi

pass "Explorer window shell is one glass caption, address back/forward, and the shot command strips; leftover stays OPEN; not pixel proof; not metal CLOSED"
