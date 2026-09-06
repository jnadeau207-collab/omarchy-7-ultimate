#!/bin/bash
set -euo pipefail

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
export HOME=/home/jesse
export OMARCHY_PATH=/home/jesse/omarchy7ultimate
export PATH="$OMARCHY_PATH/bin:/usr/bin:/bin"
export LC_ALL=C.UTF-8

sig=""
for d in $(ls -1dt /run/user/1000/hypr/* 2>/dev/null); do
  candidate=$(basename "$d")
  if HYPRLAND_INSTANCE_SIGNATURE=$candidate hyprctl version >/dev/null 2>&1; then
    sig=$candidate
    break
  fi
done
if [[ -z $sig ]]; then
  echo "no live Hyprland signature" >&2
  exit 2
fi
export HYPRLAND_INSTANCE_SIGNATURE=$sig

echo "METAL_HEAD $(git -C "$OMARCHY_PATH" rev-parse HEAD)"
echo "HYPRLAND_INSTANCE_SIGNATURE=$HYPRLAND_INSTANCE_SIGNATURE"
hyprctl version | head -n 3
hyprctl -j monitors
echo "---clients---"
hyprctl -j clients
echo "---mime---"
xdg-mime query default text/plain || true
echo "---nvim.desktop---"
if [[ -f /usr/share/applications/nvim.desktop ]]; then
  sed -n '1,40p' /usr/share/applications/nvim.desktop
fi

out="$OMARCHY_PATH/test/acceptance.d/leftovers/files-live-metal"
mkdir -p "$out"
export FILES_LIVE_LEFTOVER_DIR=$out
bash "$OMARCHY_PATH/test/acceptance.d/files-live-metal-proof.sh"
status=$?
echo "SUITE_EXIT=$status"
if [[ -f $out/leftover.json ]]; then
  echo "---leftover.json---"
  cat "$out/leftover.json"
fi
exit $status
