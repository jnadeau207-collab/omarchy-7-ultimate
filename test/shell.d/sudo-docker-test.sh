#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

command="$ROOT/bin/omarchy-sudo-docker"

mkdir -p "$TMPDIR/bin"
cat >"$TMPDIR/bin/id" <<'STUB'
#!/bin/bash
printf '%s\n' "${STUB_GROUPS:-wheel input}"
STUB
chmod +x "$TMPDIR/bin/id"

reachable_socket="$TMPDIR/reachable.sock"
blocked_socket="$TMPDIR/blocked.sock"
touch "$reachable_socket" "$blocked_socket"
chmod 600 "$reachable_socket"
chmod 400 "$blocked_socket"

run() {
  env PATH="$TMPDIR/bin:$PATH" OMARCHY_DOCKER_SOCKET="$1" STUB_GROUPS="$2" USER=tester \
    bash "$command" ${3:+"$3"}
}

run "$blocked_socket" "wheel input" || fail "an unreachable socket means Docker needs sudo"
run "$reachable_socket" "wheel input" && fail "a reachable socket means Docker does not need sudo"
pass "default mode answers from the socket this session can reach"

run "$TMPDIR/absent.sock" "wheel input docker" || fail "a missing socket means Docker needs sudo"
pass "a missing socket counts as needing sudo"

run "$blocked_socket" "wheel input docker" --configured && fail "a configured docker group means no sudo is needed"
run "$reachable_socket" "wheel input" --configured || fail "no docker group means sudo is needed"
pass "--configured answers from the account's groups"

run "$blocked_socket" "wheel input docker" || fail "the session still needs sudo before the reboot"
run "$blocked_socket" "wheel input docker" --configured && fail "the account is already configured for sudoless Docker"
pass "the two modes disagree between enabling sudoless Docker and the reboot"

run "$reachable_socket" "wheel input" --bogus 2>/dev/null && fail "an unknown flag exits non-zero"
status=0
run "$reachable_socket" "wheel input" --bogus >/dev/null 2>&1 || status=$?
(( status == 2 )) || fail "an unknown flag exits 2, not the boolean 1"
pass "an unknown flag is a usage error"
