echo "Install herdr from the Omarchy package repo and seed its config"

omarchy-pkg-drop omarchy-herdr
omarchy-pkg-add herdr

rm -f "$HOME/.local/bin/herdr"
if mise ls herdr 2>/dev/null | grep -q herdr; then
  mise unuse -g herdr &>/dev/null || true
  mise uninstall -a herdr &>/dev/null || true
fi
rm -rf "$HOME/.local/share/mise/installs/herdr" "$HOME/.local/share/mise/shims/herdr"

[[ -f "$HOME/.config/herdr/config.toml" ]] || omarchy-refresh-config herdr/config.toml
