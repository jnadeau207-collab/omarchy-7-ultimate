echo "Unpack the initramfs synchronously so Plymouth survives early boot"

if omarchy-cmd-present limine-mkinitcpio &&
  [[ -f /etc/limine-entry-tool.d/omarchy-defaults.conf ]] &&
  ! grep -rqs "initramfs_async" /etc/limine-entry-tool.d/ /etc/default/limine; then
  echo 'KERNEL_CMDLINE[default]+=" initramfs_async=0"' |
    sudo tee -a /etc/limine-entry-tool.d/omarchy-defaults.conf >/dev/null

  sudo limine-mkinitcpio
fi
