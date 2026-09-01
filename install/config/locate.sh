UPDATEDB_CONF_PATH="${OMARCHY_UPDATEDB_CONF_PATH:-/etc/updatedb.conf}"

echo "Configuring locate to skip Btrfs snapshots and index Btrfs subvolumes"

[[ -f $UPDATEDB_CONF_PATH ]] || exit 0

if grep -qE '^[[:space:]]*PRUNE_BIND_MOUNTS[[:space:]]*=' "$UPDATEDB_CONF_PATH"; then
  sed -i -E 's|^[[:space:]]*PRUNE_BIND_MOUNTS[[:space:]]*=.*|PRUNE_BIND_MOUNTS = "no"|' "$UPDATEDB_CONF_PATH"
else
  printf '%s\n' 'PRUNE_BIND_MOUNTS = "no"' >>"$UPDATEDB_CONF_PATH"
fi

if grep -qE '^[[:space:]]*PRUNEPATHS[[:space:]]*=' "$UPDATEDB_CONF_PATH"; then
  pruned=$(sed -nE 's|^[[:space:]]*PRUNEPATHS[[:space:]]*=[[:space:]]*"([^"]*)".*|\1|p' "$UPDATEDB_CONF_PATH" | tail -n 1)

  if [[ " $pruned " != *" /.snapshots "* ]]; then
    sed -i -E "s|^[[:space:]]*PRUNEPATHS[[:space:]]*=.*|PRUNEPATHS = \"/.snapshots${pruned:+ $pruned}\"|" "$UPDATEDB_CONF_PATH"
  fi
else
  printf '%s\n' 'PRUNEPATHS = "/.snapshots"' >>"$UPDATEDB_CONF_PATH"
fi
