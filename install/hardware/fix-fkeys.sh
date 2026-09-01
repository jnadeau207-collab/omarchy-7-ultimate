if [[ ! -f /etc/modprobe.d/hid_apple.conf ]]; then
  sudo mkdir -p /etc/modprobe.d
  echo "options hid_apple fnmode=2" | sudo tee /etc/modprobe.d/hid_apple.conf >/dev/null
fi
