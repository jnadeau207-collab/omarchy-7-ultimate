echo "Rebuild the boot image when it predates the Limine kernel command line"

defaults_conf="${OMARCHY_LIMINE_DEFAULTS_CONF:-/etc/limine-entry-tool.d/omarchy-defaults.conf}"
running_cmdline="${OMARCHY_RUNNING_CMDLINE:-/proc/cmdline}"
rebuild_marker="${OMARCHY_LIMINE_REBUILD_MARKER:-/var/lib/omarchy/migrations/1786482992}"

omarchy-cmd-present limine-mkinitcpio || exit 0
[[ -f $defaults_conf && -r $running_cmdline ]] || exit 0

[[ ! -e $rebuild_marker ]] || exit 0

booted=$(<"$running_cmdline")
missing=()

for param in $(sed -n 's/^KERNEL_CMDLINE\[default\]+="\(.*\)"[[:space:]]*$/\1/p' "$defaults_conf"); do
  [[ " $booted " == *" $param "* ]] || missing+=("$param")
done

(( ${#missing[@]} )) || exit 0

echo "The booted kernel is missing ${missing[*]}; rebuilding the boot image"
sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$rebuild_marker"
