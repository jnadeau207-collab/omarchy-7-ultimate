echo "Require signed packages from the Omarchy repository"

omarchy_sig_override='SigLevel = Optional TrustAll'

if [[ -f /etc/pacman.conf ]] &&
  sed -n '/^\[omarchy\]/,/^\[/p' /etc/pacman.conf | grep -qxF "$omarchy_sig_override"; then
  if omarchy-pkg-missing omarchy-keyring ||
    ! sudo pacman-key --list-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 &>/dev/null; then
    omarchy-update-keyring
  fi

  sudo sed -i "/^\[omarchy\]/,/^\[/{/^$omarchy_sig_override$/d}" /etc/pacman.conf
fi
