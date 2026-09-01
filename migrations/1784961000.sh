echo "Tune reclaim for swap on zram"

sudo sysctl -p /etc/sysctl.d/99-omarchy-sysctl.conf >/dev/null || true

if sudo systemctl daemon-reload; then
  zram_used=$(awk '$1 == "/dev/zram0" {print $4}' /proc/swaps)

  if [[ ${zram_used:-0} == 0 ]] && sudo systemctl restart dev-zram0.swap; then
    exit 0
  fi
fi

omarchy-state set reboot-required
