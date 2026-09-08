#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

computer="$ROOT/shell/apps/ultimate-files/ExplorerComputerView.qml"
cheat="$ROOT/plans/win7-ultimate-ground-truth/03-explorer-dialogs.json"
leftover="$ROOT/test/acceptance.d/leftovers/win7-visual/leftover.json"

python3 - "$computer" "$cheat" "$leftover" << 'PY'
import json
import re
import sys
from pathlib import Path

computer = Path(sys.argv[1]).read_text(encoding="utf-8")
cheat = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
leftover = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))

track = re.search(
    r"id:\s*capacityTrack\b(?:(?!\n\s*Rectangle\s*\{).)*?\n\s*width:\s*(\d+)\s*\n\s*height:\s*(\d+)\s*$",
    computer,
    re.S | re.M,
)
if not track:
    raise SystemExit("capacityTrack width/height missing")
width = int(track.group(1))
height = int(track.group(2))

sheet = cheat["pixelCheatSheet96Dpi"]["capacityBarApprox"]
width_lo, width_hi = sheet["widthPx"]
height_lo, height_hi = sheet["heightPx"]
if [width_lo, width_hi] != [60, 120] or [height_lo, height_hi] != [6, 8]:
    raise SystemExit(f"cheat sheet capacityBarApprox drifted: {sheet}")
if not (width_lo <= width <= width_hi):
    raise SystemExit(f"capacity bar width {width} outside cheat sheet {width_lo}-{width_hi}")
if not (height_lo <= height <= height_hi):
    raise SystemExit(f"capacity bar height {height} outside cheat sheet {height_lo}-{height_hi}")
if width == 168 or height == 11:
    raise SystemExit(f"capacity bar still the out-of-range 168x11 ({width}x{height})")

tile = re.search(
    r"delegate:\s*Item\s*\{\s*id:\s*drive\b.*?width:\s*(\d+)\s*\n\s*height:\s*(\d+)\s*$",
    computer,
    re.S | re.M,
)
if not tile:
    raise SystemExit("drive tile width/height missing")
if (int(tile.group(1)), int(tile.group(2))) != (292, 62):
    raise SystemExit(f"drive tile changed from 292x62 to {tile.group(1)}x{tile.group(2)}")

icon = re.search(
    r"id:\s*driveIcon\b.*?width:\s*(\d+)\s*\n\s*height:\s*(\d+)\s*$",
    computer,
    re.S | re.M,
)
if not icon:
    raise SystemExit("drive icon width/height missing")
if (int(icon.group(1)), int(icon.group(2))) != (44, 44):
    raise SystemExit(f"drive icon changed from 44x44 to {icon.group(1)}x{icon.group(2)}")

if leftover.get("win7VisualLeftover") != "OPEN":
    raise SystemExit("win7VisualLeftover must stay OPEN")
if leftover.get("hexGrepIsNotPixelProof") is not True:
    raise SystemExit("leftover must keep hexGrepIsNotPixelProof")
status = leftover.get("statusAfterPr112") or {}
if status.get("win7VisualLeftover") != "OPEN":
    raise SystemExit("statusAfterPr112 win7VisualLeftover must stay OPEN")
if status.get("metalClosed") is not False or status.get("productClosed") is not False:
    raise SystemExit("leftover must not claim metal CLOSED or product CLOSED")
still = status.get("stillOpen") or []
if "Computer tile metrics" not in still:
    raise SystemExit("Computer tile metrics visual leftover must stay listed OPEN")
PY

grep -Fq 'id: capacityTrack' "$computer" \
  || fail "Computer view still paints the drive capacity track"
grep -Fq 'width: 120' "$computer" \
  || fail "capacity bar width is the documented in-range 120"
grep -Fq 'height: 8' "$computer" \
  || fail "capacity bar height is the documented in-range 8"
grep -Fq 'width: 292' "$computer" \
  || fail "drive tile width stays 292"
grep -Fq 'height: 62' "$computer" \
  || fail "drive tile height stays 62"
grep -Fq 'width: 44' "$computer" \
  || fail "drive icon stays 44"

pass "Computer capacity bar is inside cheat-sheet 60-120 x 6-8 (source metric only, not pixel proof)"
pass "drive tile 292x62 and icon 44 unchanged"
pass "win7VisualLeftover stays OPEN (not CLOSED, not metal CLOSED, not product CLOSED)"
