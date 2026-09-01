echo "Switch to the Omarchy quickshell-git build so shell restarts wait for instance exit"

if ! omarchy-pkg-present quickshell-git; then
  sudo pacman -S --noconfirm --ask 4 quickshell-git
fi
