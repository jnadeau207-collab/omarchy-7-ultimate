echo "Store Hyprland input-device names as data instead of generated Lua"

toggles_dir="$HOME/.local/state/omarchy/toggles/hypr"

reapply=0

for kind in touchpad touchscreen; do
  state_file="$toggles_dir/$kind-disabled.lua"
  name_file="$toggles_dir/$kind-disabled-name"

  [[ -f $state_file ]] || continue

  if [[ ! -f $name_file && -r $state_file ]]; then
    old=$(<"$state_file")
    pattern='^hl\.device\(\{ name = "([^"\\[:cntrl:]]+)", enabled = false \}\)$'
    if [[ $old =~ $pattern ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}" >"$name_file"
    fi
  fi

  rm -f "$state_file"

  if [[ -f $name_file ]]; then
    reapply=1
  fi
done

if (( reapply )); then
  hyprctl reload >/dev/null 2>&1 || true
fi
