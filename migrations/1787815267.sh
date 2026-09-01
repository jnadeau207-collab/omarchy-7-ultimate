echo "Separate printer discovery from root and print-filter access"

machine_marker="${OMARCHY_CUPS_MIGRATION_MARKER:-/var/lib/omarchy/migrations/1787815267}"

[[ ! -e $machine_marker ]] || exit 0

if omarchy-pkg-present cups; then
  cups_browsed_account=$(getent passwd cups-browsed || true)
  cups_browsed_group=$(getent group cups-browsed || true)

  if [[ -n $cups_browsed_account || -n $cups_browsed_group ]]; then
    IFS=: read -r _ _ cups_browsed_uid cups_browsed_gid cups_browsed_description cups_browsed_home cups_browsed_shell <<<"$cups_browsed_account"
    IFS=: read -r _ _ cups_browsed_group_gid cups_browsed_group_members <<<"$cups_browsed_group"
    other_primary_user=$(getent passwd | awk -F: -v gid="$cups_browsed_gid" '$1 != "cups-browsed" && $4 == gid { print $1; exit }')

    if [[ ! $cups_browsed_uid =~ ^[0-9]+$ || ! $cups_browsed_group_gid =~ ^[0-9]+$ ]] ||
      ((cups_browsed_uid <= 0 || cups_browsed_uid >= 1000)) ||
      [[ $cups_browsed_gid != $cups_browsed_group_gid ]] ||
      [[ $cups_browsed_description != "CUPS printer discovery" || $cups_browsed_home != "/" || $cups_browsed_shell != "/usr/bin/nologin" ]] ||
      [[ -n $cups_browsed_group_members || -n $other_primary_user ]]; then
      echo "Cannot harden printer discovery: the existing cups-browsed user or group is not a dedicated system account." >&2
      false
    fi
  fi
fi

omarchy-pkg-drop cups-pdf

if omarchy-pkg-present cups; then
  omarchy-pkg-add cups-pk-helper
fi

if systemctl is-active --quiet cups-browsed.service 2>/dev/null; then
  sudo systemctl stop cups-browsed.service
fi

if omarchy-pkg-present cups; then
  sudo systemctl daemon-reload
  sudo systemctl try-reload-or-restart cups.service
fi

if systemctl is-enabled --quiet cups-browsed.service 2>/dev/null; then
  sudo systemctl restart cups-browsed.service
fi

sudo install -Dm644 /dev/null "$machine_marker"
