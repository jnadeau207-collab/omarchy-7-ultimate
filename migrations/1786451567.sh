echo "Repair theme symlinks the state-move migration left dangling"

relink_if_dangling() {
  local link="$1"
  local expected_target="$2"
  local target

  [[ -L $link ]] || return 0

  target=$(readlink "$link") || return 0

  [[ $target == "$expected_target" ]] && return 0

  [[ -e $link ]] && return 0

  case "$target" in
    "~/"*/omarchy/current/theme/"${expected_target##*/}") ;;
    *) return 0 ;;
  esac

  ln -sfn "$expected_target" "$link"
}

current_state_dir="$HOME/.local/state/omarchy/current"

relink_if_dangling "$HOME/.config/btop/themes/current.theme" \
  "$current_state_dir/theme/btop.theme"
relink_if_dangling "$HOME/.config/helix/themes/omarchy.toml" \
  "$current_state_dir/theme/helix.toml"

for vscode_dir in "$HOME/.vscode" "$HOME/.vscode-insiders" "$HOME/.vscode-oss" "$HOME/.cursor"; do
  relink_if_dangling "$vscode_dir/extensions/omarchy-theme/themes/omarchy-color-theme.json" \
    "$current_state_dir/theme/vscode-theme.json"
done
