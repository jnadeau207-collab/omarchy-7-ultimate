echo "Move this install to the opt-in docker group default (the group is root-equivalent)"

if id -nG "$USER" | grep -qw docker; then
  OMARCHY_DEFER_REBOOT=1 omarchy-remove-security-sudoless-docker
fi

dest="$HOME/.local/share/applications/Docker.desktop"
if [[ -f $dest ]]; then
  cp "$OMARCHY_PATH/applications/Docker.desktop" "$dest"
fi
