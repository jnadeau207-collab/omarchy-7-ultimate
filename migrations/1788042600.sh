echo "Publish Files and Settings launchers so Start jump lists see This PC, Trash, and Settings pages"

dest_dir="$HOME/.local/share/applications"
mkdir -p "$dest_dir"

for id in org.omarchy.Files org.omarchy.Settings; do
  src="$OMARCHY_PATH/applications/$id.desktop"
  dest="$dest_dir/$id.desktop"
  if [[ -f $src ]]; then
    cp "$src" "$dest"
  fi
done

PATH="$OMARCHY_PATH/bin:$PATH"
if omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$dest_dir"
fi
