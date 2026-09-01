echo "Take ownership of the FIDO2 authfile so it cannot be rewritten without root"

authfile="/etc/fido2/fido2"

report_unrepairable() {
  echo "  $1"
  echo "  $2"
  omarchy-notification-send -u critical -g  "FIDO2 authfile needs attention" "$1 $2" || true
}

if [[ ! -L $authfile && ! -e $authfile ]]; then
  authdir=${authfile%/*}

  if [[ -L $authdir || ! -d $authdir || -x $authdir ]]; then
    exit 0
  fi

  if ! sudo test -e "$authfile" && ! sudo test -L "$authfile"; then
    exit 0
  fi

  sudo chmod 755 "$authdir"
fi

if [[ -L $authfile ]]; then
  report_unrepairable "$authfile is a symlink, not a regular file." \
    "Leaving it alone. If you did not create it, remove it and re-run Setup > Security > Fido2."
  exit 0
fi

if [[ ! -f $authfile ]]; then
  report_unrepairable "$authfile is not a regular file." \
    "Leaving it alone. Remove it and re-run Setup > Security > Fido2."
  exit 0
fi

owner=$(stat -c %U "$authfile" 2>/dev/null) || owner=""
group=$(stat -c %G "$authfile" 2>/dev/null) || group=""
mode=$(stat -c %a "$authfile" 2>/dev/null) || mode=""
if [[ $owner == "root" && $group == "root" && $mode == "644" ]]; then
  exit 0
fi

stage=""

safe_stage_path() {
  local candidate=$1
  local prefix="$authfile.new."
  local suffix

  [[ $candidate == "$prefix"* ]] || return 1
  suffix=${candidate#"$prefix"}
  [[ $suffix =~ ^[[:alnum:]]{6}$ ]]
}

cleanup_stage() {
  local status=$?

  if safe_stage_path "$stage"; then
    sudo rm -f -- "$stage" || true
  fi

  return "$status"
}

trap cleanup_stage EXIT
stage=$(sudo mktemp "$authfile.new.XXXXXX")

if ! safe_stage_path "$stage" || [[ ! -f $stage || -L $stage ]]; then
  echo "  Could not create a safe staging file beside $authfile."
  exit 1
fi

sudo install -T -m 644 -o root -g root "$authfile" "$stage"
sudo mv -Tf "$stage" "$authfile"
stage=""
trap - EXIT
