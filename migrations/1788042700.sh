echo "Publish the Files Pictures action so Start Pictures opens product Files"

dest_dir="$HOME/.local/share/applications"
mkdir -p "$dest_dir"

src="$OMARCHY_PATH/applications/org.omarchy.Files.desktop"
dest="$dest_dir/org.omarchy.Files.desktop"
if [[ -f $src ]]; then
  cp "$src" "$dest"
fi

PATH="$OMARCHY_PATH/bin:$PATH"
if omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$dest_dir"
fi
