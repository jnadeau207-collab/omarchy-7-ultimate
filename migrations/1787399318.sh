echo "Switch back to the packaged quickshell now that 0.3.1 kills synchronously"

if omarchy-pkg-present quickshell-git; then
  sudo pacman -S --noconfirm --ask 4 quickshell
fi
