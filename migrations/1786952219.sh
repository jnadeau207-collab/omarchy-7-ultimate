echo "Switch mise to the mise-bin package from the Omarchy repo"

if omarchy-pkg-missing mise-bin; then
  sudo pacman -S --noconfirm --ask=4 mise-bin
fi
