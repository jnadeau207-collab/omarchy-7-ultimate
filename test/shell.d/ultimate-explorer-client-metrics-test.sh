#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

theme="$ROOT/shell/apps/ultimate-files/ExplorerTheme.js"
command_bar="$ROOT/shell/apps/ultimate-files/ExplorerCommandBar.qml"
details="$ROOT/shell/apps/ultimate-files/ExplorerDetailsPane.qml"
cheat="$ROOT/plans/win7-ultimate-ground-truth/03-explorer-dialogs.json"
leftover="$ROOT/test/acceptance.d/leftovers/win7-visual/leftover.json"
probe="$ROOT/test/acceptance.d/win7-visual-leftover.py"

python3 - "$theme" "$cheat" "$leftover" "$probe" << 'PY'
import json
import re
import sys
from pathlib import Path

theme = Path(sys.argv[1]).read_text(encoding="utf-8")
cheat = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
leftover = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
probe = Path(sys.argv[4]).read_text(encoding="utf-8")

def token(name):
    match = re.search(rf"^var {name} = (\d+)\s*$", theme, re.M)
    if not match:
        raise SystemExit(f"missing {name}")
    return int(match.group(1))

sheet = cheat["pixelCheatSheet96Dpi"]
command = token("commandHeight")
details = token("detailsHeight")
command_lo, command_hi = sheet["commandBarHeightPx"]
details_lo, details_hi = sheet["detailsPaneDefaultHeightPx"]

if not (command_lo <= command <= command_hi):
    raise SystemExit(f"commandHeight {command} outside cheat sheet {command_lo}-{command_hi}")
if not (details_lo <= details <= details_hi):
    raise SystemExit(f"detailsHeight {details} outside cheat sheet {details_lo}-{details_hi}")
if command == 30:
    raise SystemExit("commandHeight still the out-of-range 30")
if details == 52:
    raise SystemExit("detailsHeight still the out-of-range 52")

wash = leftover["surfaces"]["selectionWash"]
if wash.get("status") != "OPEN":
    raise SystemExit("selectionWash leftover must stay OPEN")
if leftover.get("win7VisualLeftover") != "OPEN":
    raise SystemExit("win7VisualLeftover must stay OPEN")
if '"status": "CLOSED"' in json.dumps(wash):
    raise SystemExit("selectionWash leftover claims CLOSED")
if 'payload["surfaces"]["selectionWash"]' not in probe or '"status": "OPEN"' not in probe:
    raise SystemExit("selectionWash probe must keep status OPEN")
if re.search(r"selectionWash[\"']\s*:\s*\{[^}]*CLOSED", probe, re.S):
    raise SystemExit("selectionWash probe claims CLOSED")
PY

grep -Fq 'implicitHeight: Aero.commandHeight' "$command_bar" \
  || fail "Explorer command bar height comes from the theme token"
grep -Fq 'implicitHeight: Math.max(Aero.detailsHeight, boundaryBanner.visible ? boundaryBanner.implicitHeight + 8 : 0)' "$details" \
  || fail "Explorer details pane height comes from the theme token"

pass "Explorer command bar height is inside cheat-sheet 36-40 (source metric only, not pixel proof)"
pass "Explorer details pane height is inside cheat-sheet 54-72 (source metric only, not pixel proof)"
pass "selectionWash leftover stays OPEN (not CLOSED, not hex-grep proof, not metal CLOSED)"
