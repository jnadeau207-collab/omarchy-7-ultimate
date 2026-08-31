echo "Publish the Agent Center Overview action so the jump list opens the existing landing page"

dest_dir="$HOME/.local/share/applications"
mkdir -p "$dest_dir"

src="$OMARCHY_PATH/applications/org.omarchy.AgentCenter.desktop"
dest="$dest_dir/org.omarchy.AgentCenter.desktop"
if [[ -f $src ]]; then
  cp "$src" "$dest"
fi

PATH="$OMARCHY_PATH/bin:$PATH"
if omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$dest_dir"
fi
