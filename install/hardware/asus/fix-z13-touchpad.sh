
if omarchy-hw-asus-rog && omarchy-hw-match "GZ302"; then
  sudo mkdir -p /etc/udev/rules.d
  sudo tee /etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules >/dev/null <<'EOF'
ACTION=="add|change", KERNEL=="event*", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1a30", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
EOF
fi
