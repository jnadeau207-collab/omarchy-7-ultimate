echo "Rename the T2 Mac BCE module (apple-bce → t2bce) and repair the boot image"

conf="${OMARCHY_T2_MKINITCPIO_CONF:-/etc/mkinitcpio.conf.d/apple-t2.conf}"
modules_conf="${OMARCHY_T2_MODULES_CONF:-/etc/modules-load.d/t2.conf}"

if [[ -f $conf ]] && grep -q 'apple-bce ' "$conf"; then
  sudo sed -i 's/apple-bce /apple-bce? t2bce_vhci? /' "$conf"

  if [[ -f $modules_conf ]]; then
    sudo sed -i 's/^apple-bce$/t2bce_vhci/' "$modules_conf"
  fi

  sudo limine-update
fi
