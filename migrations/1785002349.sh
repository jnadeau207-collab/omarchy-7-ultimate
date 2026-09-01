echo "Repair Neovim theme symlinks the earlier relink missed"

theme_link="$HOME/.config/nvim/lua/plugins/theme.lua"
current_absolute_target="$HOME/.local/state/omarchy/current/theme/neovim.lua"
current_relative_target="../../../../.local/state/omarchy/current/theme/neovim.lua"

[[ -L $theme_link ]] || exit 0

target=$(readlink "$theme_link") || exit 0

[[ $target == "$current_relative_target" || $target == "$current_absolute_target" ]] && exit 0

case "$target" in
  */omarchy/current/theme/neovim.lua) ;;
  *) exit 0 ;;
esac

ln -sfn "$current_relative_target" "$theme_link"
