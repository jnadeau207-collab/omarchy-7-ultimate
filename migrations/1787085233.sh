echo "Take the FIDO2 authfile out of the user's hands"

authfile="${OMARCHY_FIDO2_AUTHFILE:-/etc/fido2/fido2}"

[[ -f $authfile && $(stat -c '%u' "$authfile") != 0 ]] || exit 0

sudo install -o root -g root -m 644 "$authfile" "$authfile.new"
sudo mv -f "$authfile.new" "$authfile"
