#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"
printf '#!/bin/bash\nexit 0\n' >"$TMPDIR/bin/getent"
cat >"$TMPDIR/bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == "-Qq" ]] || exit 2
[[ " ${STUB_PACKAGES:-} " == *" $2 "* ]]
STUB
chmod +x "$TMPDIR/bin/getent" "$TMPDIR/bin/pacman"
export PATH="$TMPDIR/bin:$PATH"

PROVISIONING_DIR="$TMPDIR/prov"
mkdir -p "$PROVISIONING_DIR"
printf 'wheel\ninput\ndocker\n' >"$PROVISIONING_DIR/groups"

eval "$(sed -n '/^user_groups() {/,/^}/p' "$ROOT/bin/omarchy-provision-owner")"
groups=$(user_groups)

[[ ",$groups," == *",wheel,"* ]] || fail "user_groups always includes wheel"
[[ ",$groups," != *",input,"* ]] || fail "user_groups must not replay the blanket input grant"
[[ ",$groups," == *",docker,"* ]] && fail "user_groups must never grant the docker group"
pass "first-boot user_groups replays neither privileged default"

groups=$(STUB_PACKAGES=xpadneo-dkms user_groups)
[[ ",$groups," == *",input,"* ]] || fail "user_groups keeps input for installed controller support"
groups=$(STUB_PACKAGES=ydotool user_groups)
[[ ",$groups," == *",input,"* ]] || fail "user_groups keeps input for installed ydotool support"
pass "first-boot user_groups keeps deliberate input-group opt-ins"

if rg -q 'usermod -aG docker' "$ROOT/bin/omarchy-upgrade-to-quattro"; then
  fail "omarchy-upgrade-to-quattro must not add the user to the docker group"
fi
pass "the Quattro upgrade does not grant the docker group"
