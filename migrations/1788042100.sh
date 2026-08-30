echo "Publish the Agent Center desktop launcher"

src="$OMARCHY_PATH/applications/org.omarchy.AgentCenter.desktop"
dest="$HOME/.local/share/applications/org.omarchy.AgentCenter.desktop"
[[ -f $src ]] || exit 0
mkdir -p "$HOME/.local/share/applications"
cp "$src" "$dest"
PATH="$OMARCHY_PATH/bin:$PATH"
if omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$HOME/.local/share/applications"
fi
