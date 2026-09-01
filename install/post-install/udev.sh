if [ -d /etc/udev/rules.d ] && [ -f "$(dirname -- "${BASH_SOURCE[0]}")"/../../etc/udev/rules.d/70-omarchy-uinput.rules ]; then
  install -o root -g root -m 644 \
    "$(dirname -- "${BASH_SOURCE[0]}")"/../../etc/udev/rules.d/70-omarchy-uinput.rules \
    /etc/udev/rules.d/70-omarchy-uinput.rules || true
fi
udevadm control --reload 2>/dev/null || true
udevadm trigger --subsystem-match=power_supply 2>/dev/null || true
udevadm trigger --name-match=uinput 2>/dev/null || true

