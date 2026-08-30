echo "Give Desktop Mode a real Desktop directory and the default desktop shortcuts"

desktop="$HOME/Desktop"
mkdir -p "$desktop"

if omarchy-cmd-present xdg-user-dirs-update; then
  xdg-user-dirs-update --set DESKTOP "$desktop" || true
fi

src="$OMARCHY_PATH/default/ultimate/desktop"
if [[ -d $src ]]; then
  for file in "$src"/*.desktop; do
    [[ -f $file ]] || continue
    dest="$desktop/$(basename "$file")"
    if [[ ! -e $dest ]]; then
      cp "$file" "$dest"
    fi
  done
fi
