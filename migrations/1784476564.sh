echo "Keep non-Latin keyboard layouts out of the initramfs so the LUKS passphrase stays typeable"

hooks_conf="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

layout=""
[[ -f /etc/vconsole.conf ]] && layout=$(unset XKBLAYOUT; . /etc/vconsole.conf; echo "${XKBLAYOUT:-}")
layout="${layout%%,*}"

if [[ $layout =~ ^(af|am|ara|bd|bg|by|et|ge|gr|il|in|iq|ir|kg|kh|kz|la|lk|mk|mm|mn|mv|np|rs|ru|sy|th|tj|ua)$ ]] &&
  [[ -f $hooks_conf ]] && grep -qx 'FILES+=(/etc/vconsole.conf)' "$hooks_conf"; then
  sudo sed -i '\|^FILES+=(/etc/vconsole.conf)$|d' "$hooks_conf"

  if omarchy-cmd-present limine-mkinitcpio; then
    sudo limine-mkinitcpio
  fi
fi
