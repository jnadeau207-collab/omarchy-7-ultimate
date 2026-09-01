#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1787580187.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
omarchy_path="$test_dir/omarchy"
stub_bin="$test_dir/bin"
mkdir -p "$home/.local/share/applications" "$omarchy_path/applications" "$stub_bin"

printf 'NEW-LAUNCHER\n' >"$omarchy_path/applications/Docker.desktop"
printf 'OLD-LAUNCHER\n' >"$home/.local/share/applications/Docker.desktop"

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
printf '%s\n' "${STUB_GROUPS:-wheel input}"
STUB
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat >"$stub_bin/gpasswd" <<'STUB'
#!/bin/bash
echo "$@" >>"${GPASSWD_CALLS:?}"
STUB
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
[[ $1 == confirm ]] && exit 0
exit 0
STUB
cat >"$stub_bin/omarchy-system-reboot" <<'STUB'
#!/bin/bash
touch "${REBOOT_CALLED:?}"
STUB
chmod +x "$stub_bin/id" "$stub_bin/sudo" "$stub_bin/gpasswd" "$stub_bin/gum" "$stub_bin/omarchy-system-reboot"

reboot_flag="$home/.local/state/omarchy/reboot-required"
gpasswd_calls="$test_dir/gpasswd-calls"
reboot_called="$test_dir/reboot-called"
launcher="$home/.local/share/applications/Docker.desktop"

run_migration() {
  rm -f "$gpasswd_calls" "$reboot_flag" "$reboot_called"
  HOME="$home" OMARCHY_PATH="$omarchy_path" USER="tester" STUB_GROUPS="$1" \
    GPASSWD_CALLS="$gpasswd_calls" REBOOT_CALLED="$reboot_called" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null 2>&1
}

run_migration "wheel input docker" || fail "migration runs when the user is in the docker group"
grep -q -- "-d tester docker" "$gpasswd_calls" || fail "migration removes the user from the docker group"
[[ -f $reboot_flag ]] || fail "migration flags a reboot so the group change takes effect"
[[ ! -f $reboot_called ]] || fail "migration must defer the reboot (not reboot mid-update)"
[[ $(cat "$launcher") == "NEW-LAUNCHER" ]] || fail "migration refreshes the stale Docker launcher entry"
pass "migration removes the group, flags a reboot, and refreshes the launcher"

printf 'OLD-LAUNCHER\n' >"$launcher"
run_migration "wheel input" || fail "migration runs when the user is not in the docker group"
[[ ! -f $gpasswd_calls ]] || fail "migration must not touch the group when the user is not in it"
[[ ! -f $reboot_flag ]] || fail "migration must not flag a reboot when nothing changed"
[[ $(cat "$launcher") == "NEW-LAUNCHER" ]] || fail "migration still refreshes the launcher when the group is already absent"
pass "migration is a no-op on the group and reboot when already out"

rm -f "$launcher"
run_migration "wheel input" || fail "migration tolerates a missing launcher entry"
[[ ! -e $launcher ]] || fail "migration does not create a launcher entry that was not there"
pass "migration skips the launcher refresh when no entry exists"
