echo "Put Recycle Bin on the Desktop next to Computer"

desktop="$HOME/Desktop"
mkdir -p "$desktop"

src="$OMARCHY_PATH/default/ultimate/desktop/Recycle Bin.desktop"
dest="$desktop/Recycle Bin.desktop"
if [[ -f $src && ! -e $dest ]]; then
  cp "$src" "$dest"
fi
