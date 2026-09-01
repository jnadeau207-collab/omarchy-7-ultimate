echo "Rebuild the initramfs so NVIDIA-only systems shed nouveau's unused GSP firmware"

hooks_conf="${OMARCHY_MKINITCPIO_HOOKS_CONF:-/etc/mkinitcpio.conf.d/omarchy_hooks.conf}"
nvidia_conf="${OMARCHY_MKINITCPIO_NVIDIA_CONF:-/etc/mkinitcpio.conf.d/nvidia.conf}"
rebuild_marker="${OMARCHY_KMS_REBUILD_MARKER:-/var/lib/omarchy/migrations/1786605598}"

omarchy-cmd-present limine-mkinitcpio || exit 0
[[ -f $hooks_conf && -f $nvidia_conf ]] || exit 0

[[ ! -e $rebuild_marker ]] || exit 0

hooks=$(bash -c 'source "$1" && source "$2" && echo " ${HOOKS[*]} "' -- "$nvidia_conf" "$hooks_conf") || exit 0

[[ $hooks != *" kms "* ]] || exit 0

echo "This machine no longer uses the kms hook; rebuilding the initramfs without nouveau"
sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$rebuild_marker"
