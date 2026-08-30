#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

tool="$ROOT/bin/omarchy-dev-visual-regression"
contract="$ROOT/default/ultimate/quality/visual-regression-v0.json"

[[ -x $tool ]] || fail "omarchy-dev-visual-regression is executable"
pass "omarchy-dev-visual-regression is executable"

grep -Fq 'omarchy:hidden=true' "$tool" || fail "visual regression tool stays hidden"
pass "visual regression tool is hidden"

jq -e '.galleryId == "ultimate-visual-regression-v0" and .algorithm == "sha256-png-bytes" and (.surfaces | length) >= 10' \
  "$contract" >/dev/null \
  || fail "visual regression contract names the Phase 0 gallery"
pass "visual regression contract names the Phase 0 gallery"

python3 - "$contract" <<'PY'
import json
import sys

contract = json.load(open(sys.argv[1], encoding="utf-8"))
ids = [row["id"] for row in contract["surfaces"]]
required = [
    "start",
    "superbar",
    "agent-center-overview",
    "lock-preview",
    "quick-settings",
    "notification-center",
    "dark-comfortable-pointer",
    "light-compact-keyboard-pseudo",
    "dark-touch-rtl-long",
    "light-comfortable-rtl-two-x",
]
missing = [name for name in required if name not in ids]
assert not missing, missing
assert all(row["kind"] in {"desktop-chrome", "state-gallery"} for row in contract["surfaces"])
gallery = [row["sha256"] for row in contract["surfaces"] if row["kind"] == "state-gallery"]
assert len(gallery) == len(set(gallery)), gallery
PY
pass "visual regression gallery includes chrome and state-gallery cases"

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

python3 - "$tmp" <<'PY'
import pathlib
import struct
import sys
import zlib

def png(path, rgb):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"\x00" + bytes(rgb)
    body = zlib.compress(raw, 9)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", body)
        + chunk(b"IEND", b"")
    )

root = pathlib.Path(sys.argv[1])
png(root / "a.png", (10, 20, 30))
png(root / "b.png", (10, 20, 30))
png(root / "c.png", (30, 20, 10))
PY

OMARCHY_PATH="$ROOT" "$tool" compare "$tmp/a.png" "$tmp/b.png" >/dev/null \
  || fail "identical PNGs compare equal"
pass "identical PNGs compare equal"

if OMARCHY_PATH="$ROOT" "$tool" compare "$tmp/a.png" "$tmp/c.png" >/dev/null; then
  fail "mutated PNGs must not compare equal"
fi
pass "mutated PNGs compare unequal"

left_hash=$(OMARCHY_PATH="$ROOT" "$tool" hash "$tmp/a.png")
right_hash=$(OMARCHY_PATH="$ROOT" "$tool" hash "$tmp/b.png")
[[ $left_hash == "$right_hash" && ${#left_hash} == 64 ]] || fail "hash is a stable sha256 of PNG bytes"
pass "hash is a stable sha256 of PNG bytes"

if [[ -d $ROOT/default/ultimate/quality/visual-goldens ]]; then
  check_output=$(OMARCHY_PATH="$ROOT" "$tool" check) \
    || fail "committed visual goldens match the gallery contract" "$check_output"
  [[ $check_output == "visual regression gallery valid: 10 surfaces" ]] \
    || fail "visual regression check reports the ten-surface gallery" "$check_output"
  pass "committed visual goldens match the gallery contract"
else
  fail "visual-goldens directory is part of the Phase 0 gallery"
fi
