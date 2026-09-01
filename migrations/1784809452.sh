echo "Remove Snapper timeline snapshots leaked by earlier defaults"

SNAPPER_CONFIG_PATH="${OMARCHY_SNAPPER_CONFIG_PATH:-/etc/snapper/configs/root}"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

command -v snapper >/dev/null || exit 0
[[ -f $SNAPPER_CONFIG_PATH ]] || exit 0

if [[ -r $SNAPPER_CONFIG_PATH ]]; then
  grep -qFx 'TIMELINE_CREATE="no"' "$SNAPPER_CONFIG_PATH" || exit 0
else
  as_root grep -qFx 'TIMELINE_CREATE="no"' "$SNAPPER_CONFIG_PATH" || exit 0
fi

leaked=$(as_root snapper -c root --csvout list --columns number,cleanup 2>/dev/null | awk -F, '$2 == "timeline" { print $1 }' || true)
[[ -n $leaked ]] || exit 0

echo "Deleting $(wc -w <<<"$leaked") leaked timeline snapshots (disk space is reclaimed in the background)"

failed=0
batch=()

for number in $leaked; do
  batch+=("$number")
  if (( ${#batch[@]} == 20 )); then
    as_root snapper -c root delete "${batch[@]}" || failed=$((failed + ${#batch[@]}))
    batch=()
  fi
done

if (( ${#batch[@]} > 0 )); then
  as_root snapper -c root delete "${batch[@]}" || failed=$((failed + ${#batch[@]}))
fi

if (( failed > 0 )); then
  echo "$failed snapshots could not be deleted. Finish with: sudo snapper -c root delete <number>"
fi
