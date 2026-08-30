echo "Allow Fabric user units to spawn bubblewrap by dropping ProtectKernelTunables and ProtectKernelLogs"

packaged_src="$OMARCHY_PATH/default/systemd/user/omarchy-fabric.service"
packaged_dest="$HOME/.config/systemd/user/omarchy-fabric.service"
checkout_src="$OMARCHY_PATH/default/systemd/user/omarchy-fabric-checkout.service"
checkout_dest="$HOME/.config/systemd/user/omarchy-fabric-checkout.service"

if [[ -f $packaged_src && -f $packaged_dest ]]; then
  cp "$packaged_src" "$packaged_dest"
fi
if [[ -f $checkout_src && -f $checkout_dest ]]; then
  cp "$checkout_src" "$checkout_dest"
fi

systemctl --user daemon-reload || exit 0

if [[ ! -x /usr/bin/omarchy-fabricd ]] && systemctl --user is-active --quiet omarchy-fabric-checkout.service; then
  systemctl --user restart omarchy-fabric-checkout.service || true
fi
