#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PYTHONDONTWRITEBYTECODE=1

if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  runtime="${XDG_RUNTIME_DIR:-/run/user/$UID}"
  for d in $(ls -1dt "$runtime"/hypr/* 2>/dev/null); do
    sig=$(basename "$d")
    if HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl version >/dev/null 2>&1; then
      export HYPRLAND_INSTANCE_SIGNATURE=$sig
      break
    fi
  done
fi

if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  fail "Win7 visual leftover requires a live Hyprland session"
fi

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  runtime="${XDG_RUNTIME_DIR:-/run/user/$UID}"
  socket=$(ls -t "$runtime"/wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | head -n1 || true)
  [[ -n $socket ]] && export WAYLAND_DISPLAY=${socket##*/}
fi

out="${WIN7_VISUAL_LEFTOVER_DIR:-$ROOT/test/acceptance.d/leftovers/win7-visual}"
mkdir -p "$out"

python3 "$ROOT/test/acceptance.d/win7-visual-leftover.py" "$out"
status=$?
[[ -f $out/leftover.json ]] || fail "Win7 visual leftover.json was not written"
sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["sha"])' "$out/leftover.json")
state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["win7VisualLeftover"])' "$out/leftover.json")
echo "win7-visual leftover sha=$sha state=$state exit=$status"
if [[ $state == "CLOSED" ]]; then
  fail "Win7 visual leftover must stay OPEN (hex-grep is not pixel proof)"
fi
if (( status == 0 )) && [[ $state == "OPEN" ]]; then
  pass "Win7 visual leftover OPEN on $sha (measured grim, not hex-grep)"
  exit 0
fi
fail "Win7 visual leftover harness failed (exit $status, state $state)"
