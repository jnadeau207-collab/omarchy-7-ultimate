echo "Enable the checkout Fabric user unit when the packaged daemon is absent"

src="$OMARCHY_PATH/default/systemd/user/omarchy-fabric-checkout.service"
dest="$HOME/.config/systemd/user/omarchy-fabric-checkout.service"
[[ -f $src ]] || exit 0
mkdir -p "$HOME/.config/systemd/user"
cp "$src" "$dest"

if [[ -x /usr/bin/omarchy-fabricd ]]; then
  exit 0
fi

if ! systemctl --user daemon-reload; then
  exit 0
fi

systemctl --user enable omarchy-fabric-checkout.service
if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-fabric-checkout.service || true
fi
