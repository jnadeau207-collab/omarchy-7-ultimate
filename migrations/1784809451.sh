echo "Configure locate to skip Btrfs snapshots and index Btrfs subvolumes"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
locate_config_script="$OMARCHY_PATH/install/config/locate.sh"
UPDATEDB_CONF_PATH="${OMARCHY_UPDATEDB_CONF_PATH:-/etc/updatedb.conf}"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

[[ -f $UPDATEDB_CONF_PATH ]] || exit 0
[[ -f $locate_config_script ]] || exit 0

if grep -q '^PRUNE_BIND_MOUNTS = "no"' "$UPDATEDB_CONF_PATH" &&
  grep -E '^PRUNEPATHS' "$UPDATEDB_CONF_PATH" | grep -E '(^|[[:space:]"])/\.snapshots([[:space:]"]|$)' >/dev/null; then
  exit 0
fi

as_root env OMARCHY_UPDATEDB_CONF_PATH="$UPDATEDB_CONF_PATH" bash -euo pipefail "$locate_config_script"

as_root systemctl restart --no-block plocate-updatedb.service >/dev/null 2>&1 || true
