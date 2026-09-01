echo "Republish the Settings launcher without the two provider-less jump list actions"

dest_dir="$HOME/.local/share/applications"
mkdir -p "$dest_dir"

src="$OMARCHY_PATH/applications/org.omarchy.Settings.desktop"
dest="$dest_dir/org.omarchy.Settings.desktop"
if [[ -f $src ]]; then
  cp "$src" "$dest"
fi

PATH="$OMARCHY_PATH/bin:$PATH"
if omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$dest_dir"
fi
