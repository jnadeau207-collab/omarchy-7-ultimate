echo "Remember Bluetooth on and off through the rfkill soft block"

marker="${OMARCHY_BLUETOOTH_MIGRATION_MARKER:-/var/lib/omarchy/migrations/1786380259}"
main_conf="${OMARCHY_BLUETOOTH_MAIN_CONF:-/etc/bluetooth/main.conf}"

if [[ -e $marker ]]; then
  exit 0
fi

if omarchy-bluetooth-power is-on; then
  sudo omarchy-bluetooth-power on
else
  sudo omarchy-bluetooth-power off
fi

if [[ -f $main_conf ]]; then
  sudo sed -i 's/^AutoEnable=false$/#AutoEnable=true/' "$main_conf"
fi

sudo install -Dm644 /dev/null "$marker"
