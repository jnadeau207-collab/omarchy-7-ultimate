echo "Re-stage the current theme so an installed theme's code is dropped"

theme_name_path="$HOME/.local/state/omarchy/current/theme.name"

[[ -s $theme_name_path ]] || exit 0

theme_name=$(<"$theme_name_path")

if [[ ! -d $OMARCHY_PATH/themes/$theme_name && ! -d $HOME/.config/omarchy/themes/$theme_name ]]; then
  echo "Theme '$theme_name' no longer exists; applying the default instead"
  omarchy-theme-set "Tokyo Night"
  exit 0
fi

omarchy-theme-refresh
