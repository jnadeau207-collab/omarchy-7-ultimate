echo "Switch fingerprint support back to stock libfprint"

if pacman -Q libfprint-git &>/dev/null; then
  sudo pacman -Rdd --noconfirm libfprint-git
  omarchy-pkg-add libfprint
elif pacman -Q fprintd &>/dev/null && ! pacman -Q libfprint &>/dev/null; then
  omarchy-pkg-add libfprint
fi
