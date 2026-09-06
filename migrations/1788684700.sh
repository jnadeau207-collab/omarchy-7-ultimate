echo "Publish the Settings System information jump so Superbar opens the session System information page"

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
