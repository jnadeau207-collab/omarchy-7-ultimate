echo "Remove the obsolete Voxtype Hyprland toggle"

rm -f "$HOME/.local/state/omarchy/toggles/hypr/voxtype.lua"

if [[ ${OMARCHY_UPGRADE_TO_QUATTRO_LIVE:-0} != "1" ]]; then
  hyprctl reload >/dev/null 2>&1 || true
fi
