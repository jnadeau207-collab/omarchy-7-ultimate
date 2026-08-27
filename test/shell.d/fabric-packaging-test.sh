#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command bwrap

service="$ROOT/default/systemd/user/omarchy-fabric.service"
lifecycle="$ROOT/bin/omarchy-fabric-service"
contract="$ROOT/default/fabric/packaging/package-contract"
migration="$ROOT/migrations/1787794139.sh"

grep -Fx 'After=graphical-session.target' "$service" >/dev/null ||
  fail "Fabric starts before the authoritative Omarchy session environment exists"
grep -Fx 'PartOf=graphical-session.target' "$service" >/dev/null ||
  fail "Fabric is not stopped with its graphical user session"
grep -Fx 'ConditionEnvironment=OMARCHY_PATH' "$service" >/dev/null ||
  fail "Fabric can start without the authoritative OMARCHY_PATH"
grep -Fx 'ExecStartPre=/usr/bin/omarchy-fabric-service prepare-start' "$service" >/dev/null ||
  fail "Fabric service bypasses its package and state preflight"
grep -Fx 'ExecStart=/usr/bin/omarchy-fabricd' "$service" >/dev/null ||
  fail "Fabric service does not use the fixed packaged daemon argv"
grep -Fx 'RuntimeDirectory=omarchy' "$service" >/dev/null
grep -Fx 'RuntimeDirectoryMode=0700' "$service" >/dev/null
grep -Fx 'StateDirectory=omarchy/fabric' "$service" >/dev/null
grep -Fx 'StateDirectoryMode=0700' "$service" >/dev/null
grep -Fx 'UMask=0077' "$service" >/dev/null ||
  fail "Fabric service does not make runtime and durable files owner-only"
grep -Fx 'RestartPreventExitStatus=78' "$service" >/dev/null ||
  fail "Fabric does not distinguish permanent startup refusal from a restartable daemon crash"
if grep -Eq '^RestartPreventExitStatus=.*(^|[[:space:]])1($|[[:space:]])' "$service"; then
  fail "Fabric suppresses restart for ordinary Python exit status 1"
fi
grep -Fx 'WantedBy=graphical-session.target' "$service" >/dev/null ||
  fail "Fabric is not enabled with the graphical user session"
if grep -Eq 'Exec(Start|StartPre)=.*/(ba)?sh|Exec(Start|StartPre)=.*[[:space:]]-c([[:space:]]|$)' "$service"; then
  fail "Fabric service launches a shell instead of fixed package commands"
fi
pass "Fabric user unit has fixed argv, session ordering, bounded restart, and owner-only directory contracts"

[[ $(<"$contract") == "omarchy.fabric.package/v0" ]] ||
  fail "Fabric package ABI marker is not the expected provisional contract"
[[ -x $lifecycle ]] || fail "Fabric lifecycle helper is not executable in a source checkout"
for command in omarchy-fabricd omarchy-fabricctl; do
  grep -F '"$OMARCHY_PATH/bin/omarchy-fabric-service" verify-package' "$ROOT/bin/$command" >/dev/null ||
    fail "$command imports runtime modules before package compatibility is proven"
  grep -F 'exec /usr/bin/python3 -m omarchy_fabric.' "$ROOT/bin/$command" >/dev/null ||
    fail "$command does not execute the declared packaged Python runtime"
done
grep -F 'omarchy-fabric.service' "$ROOT/install/user/first-run/enable-user-units.sh" >/dev/null ||
  fail "fresh users do not enable Fabric"
grep -F '"$fabric_service" install' "$migration" >/dev/null ||
  fail "existing users do not enter the same Fabric lifecycle"
grep -F 'omarchy-fabric-service refresh' "$ROOT/bin/omarchy-update-restart" >/dev/null ||
  fail "later updates leave a stale Fabric daemon running"
for package in bubblewrap python python-jsonschema; do
  grep -Fx "$package" "$ROOT/install/omarchy-base.packages" >/dev/null ||
    fail "$package is missing from the ISO-owned Fabric runtime package set"
done
pass "fresh install, existing-user migration, package refresh, and runtime dependencies are wired"

# Cross-repository release assertions belong to omarchy-pkgs, where the built
# .PKGINFO and archive contents can be checked together. This repository keeps
# its lifecycle suite hermetic and verifies only the runtime behavior it owns.
grep -F '[[ $OMARCHY_PATH == "/usr/share/omarchy" ]] || return 0' "$lifecycle" >/dev/null ||
  fail "packaged Fabric does not activate its installed-pair version check"
grep -F '[[ $runtime_version == "$settings_version" ]]' "$lifecycle" >/dev/null ||
  fail "packaged Fabric does not require matching full package releases"
pass "packaged runtime verification requires one matching full package release"

test_root=$(mktemp -d)
fabric_pid=""
cleanup() {
  if [[ -n $fabric_pid ]] && kill -0 "$fabric_pid" 2>/dev/null; then
    kill "$fabric_pid"
    wait "$fabric_pid" || true
  fi
  rm -rf "$test_root"
}
trap cleanup EXIT

export HOME="$test_root/home"
export XDG_RUNTIME_DIR="$test_root/runtime"
export XDG_STATE_HOME="$test_root/state"
export OMARCHY_PATH="$ROOT"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME"

"$lifecycle" prepare-start
[[ $(stat -c %a "$XDG_RUNTIME_DIR/omarchy") == "700" ]] ||
  fail "Fabric runtime directory is not mode 0700"
[[ $(stat -c %a "$XDG_STATE_HOME/omarchy") == "700" ]] ||
  fail "Fabric state parent is not mode 0700"
[[ $(stat -c %a "$XDG_STATE_HOME/omarchy/fabric") == "700" ]] ||
  fail "Fabric state directory is not mode 0700"
pass "Fabric pre-start creates and normalizes owner-only runtime and state directories"

corrupt_database="$test_root/corrupt.db"
printf 'not-a-sqlite-database\n' >"$corrupt_database"
set +e
permanent_output=$(PYTHONDONTWRITEBYTECODE=1 "$ROOT/bin/omarchy-fabricd" \
  --socket "$test_root/corrupt.sock" --database "$corrupt_database" 2>&1)
permanent_status=$?
set -e
(( permanent_status == 78 )) ||
  fail "a permanent Fabric startup refusal does not use EX_CONFIG/78" "$permanent_output"
pass "permanent startup refusal is classified separately from restartable exit status 1"

rm -rf "$XDG_STATE_HOME/omarchy/fabric"
mkdir -p "$test_root/symlink-target"
ln -s "$test_root/symlink-target" "$XDG_STATE_HOME/omarchy/fabric"
set +e
unsafe_output=$("$lifecycle" prepare-start 2>&1)
unsafe_status=$?
set -e
(( unsafe_status == 78 )) || fail "Fabric accepts a symbolic-link state directory" "$unsafe_output"
[[ -z $(find "$test_root/symlink-target" -mindepth 1 -print -quit) ]] ||
  fail "Fabric touched the target behind a rejected state-directory symlink"
rm "$XDG_STATE_HOME/omarchy/fabric"
mkdir "$XDG_STATE_HOME/omarchy/fabric"
pass "Fabric pre-start rejects a symbolic-link state path without touching its target"

artifact_target="$test_root/database-target"
printf 'do-not-touch\n' >"$artifact_target"
ln -s "$artifact_target" "$XDG_STATE_HOME/omarchy/fabric/fabric.db"
set +e
unsafe_artifact_output=$("$lifecycle" prepare-start 2>&1)
unsafe_artifact_status=$?
set -e
(( unsafe_artifact_status == 78 )) ||
  fail "Fabric accepts a symbolic-link database artifact" "$unsafe_artifact_output"
[[ $(<"$artifact_target") == "do-not-touch" ]] ||
  fail "Fabric changed the target behind a rejected database symlink"
rm "$XDG_STATE_HOME/omarchy/fabric/fabric.db"
backup_artifact="$XDG_STATE_HOME/omarchy/fabric/fabric.db.pre-migrate-v1-to-v2-test.bak"
printf 'backup\n' >"$backup_artifact"
chmod 0666 "$backup_artifact"
"$lifecycle" prepare-start
[[ $(stat -c %a "$backup_artifact") == "600" ]] ||
  fail "Fabric did not normalize a migration backup to mode 0600"
rm "$backup_artifact"
pass "Fabric pre-start rejects unsafe database links and normalizes backup permissions"

bad_root="$test_root/bad-package"
mkdir -p "$bad_root/bin" "$bad_root/default/fabric/packaging"
cp "$lifecycle" "$bad_root/bin/omarchy-fabric-service"
chmod 0755 "$bad_root/bin/omarchy-fabric-service"
printf '%s\n' 'omarchy.fabric.package/v99' >"$bad_root/default/fabric/packaging/package-contract"
set +e
bad_output=$(OMARCHY_PATH="$bad_root" "$ROOT/bin/omarchy-fabricd" 2>&1)
bad_status=$?
set -e
(( bad_status == 78 )) || fail "Fabric daemon accepts mixed package ABI assets" "$bad_output"
[[ $bad_output == *"update omarchy and omarchy-settings together"* ]] ||
  fail "Fabric package mismatch does not name the paired-package recovery" "$bad_output"
pass "Fabric commands refuse a mixed package pair before importing daemon state code"

stub_bin="$test_root/bin"
systemctl_log="$test_root/systemctl.log"
mkdir -p "$stub_bin"
cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
if [[ ${SYSTEMCTL_AVAILABLE:-1} == 0 && $* == "--user daemon-reload" ]]; then
  exit 1
fi
case "$*" in
  "--user is-active --quiet graphical-session.target")
    [[ ${GRAPHICAL_ACTIVE:-0} == 1 ]]
    ;;
  "--user is-enabled --quiet omarchy-fabric.service")
    [[ ${FABRIC_ENABLED:-0} == 1 ]]
    ;;
  "--user is-active --quiet omarchy-fabric.service")
    [[ ${FABRIC_ACTIVE:-0} == 1 ]]
    ;;
  "--user stop omarchy-fabric.service")
    [[ ${FABRIC_STOP_SUCCEEDS:-1} == 1 ]]
    ;;
esac
STUB
chmod 0755 "$stub_bin/systemctl"
export PATH="$stub_bin:$PATH"
export SYSTEMCTL_LOG="$systemctl_log"

: >"$systemctl_log"
GRAPHICAL_ACTIVE=1 "$lifecycle" install
grep -Fx -- '--user daemon-reload' "$systemctl_log" >/dev/null
grep -Fx -- '--user enable omarchy-fabric.service' "$systemctl_log" >/dev/null
grep -Fx -- '--user start omarchy-fabric.service' "$systemctl_log" >/dev/null ||
  fail "Fabric install does not start in an active graphical session"
pass "Fabric install reloads, enables, and starts through the user manager"

: >"$systemctl_log"
FABRIC_ENABLED=1 FABRIC_ACTIVE=1 GRAPHICAL_ACTIVE=1 "$lifecycle" refresh
stop_line=$(grep -nFx -- '--user stop omarchy-fabric.service' "$systemctl_log" | cut -d: -f1)
start_line=$(grep -nFx -- '--user start omarchy-fabric.service' "$systemctl_log" | cut -d: -f1)
[[ -n $stop_line && -n $start_line ]] || fail "Fabric refresh did not stop and restart an active enabled daemon"
(( stop_line < start_line )) || fail "Fabric refresh starts new code before stopping stale code"
pass "Fabric refresh replaces an active daemon in stop-verify-start order"

: >"$systemctl_log"
set +e
failed_stop=$(FABRIC_ENABLED=1 FABRIC_ACTIVE=1 FABRIC_STOP_SUCCEEDS=0 GRAPHICAL_ACTIVE=1 \
  "$lifecycle" refresh 2>&1)
failed_stop_status=$?
set -e
(( failed_stop_status == 75 )) ||
  fail "Fabric refresh does not report an uncertain manager state when stop fails" "$failed_stop"
if grep -Fx -- '--user start omarchy-fabric.service' "$systemctl_log" >/dev/null; then
  fail "Fabric refresh tried to start another daemon after stop failed"
fi
pass "Fabric refresh fails closed when the user manager cannot confirm the daemon stopped"

: >"$systemctl_log"
set +e
bad_refresh=$(OMARCHY_PATH="$bad_root" FABRIC_ENABLED=1 FABRIC_ACTIVE=1 GRAPHICAL_ACTIVE=1 \
  "$lifecycle" refresh 2>&1)
bad_refresh_status=$?
set -e
(( bad_refresh_status == 78 )) || fail "mixed-package refresh does not fail closed" "$bad_refresh"
grep -Fx -- '--user stop omarchy-fabric.service' "$systemctl_log" >/dev/null ||
  fail "mixed-package refresh leaves the stale daemon running"
if grep -Fx -- '--user start omarchy-fabric.service' "$systemctl_log" >/dev/null; then
  fail "mixed-package refresh restarted an incompatible daemon"
fi
pass "Fabric refresh stops stale code and stays stopped on package mismatch"

: >"$systemctl_log"
fallback_link="$HOME/.config/systemd/user/graphical-session.target.wants/omarchy-fabric.service"
SYSTEMCTL_AVAILABLE=0 "$lifecycle" install >/dev/null
[[ -L $fallback_link ]] || fail "Fabric install without a user manager loses next-login enablement"
[[ $(readlink "$fallback_link") == "/usr/lib/systemd/user/omarchy-fabric.service" ]] ||
  fail "Fabric fallback enablement does not target the package-owned unit"
SYSTEMCTL_AVAILABLE=0 "$lifecycle" uninstall >/dev/null
[[ ! -e $fallback_link && ! -L $fallback_link ]] ||
  fail "Fabric fallback uninstall leaves its wants symlink behind"
pass "Fabric defers safely when the user manager is unavailable and can remove that enablement"

deferred_refresh=$(SYSTEMCTL_AVAILABLE=0 "$lifecycle" refresh)
[[ $deferred_refresh == *"deferred startup to the next graphical login"* ]] ||
  fail "Fabric refresh without a manager or socket did not report safe deferral" "$deferred_refresh"
pass "manager-unavailable refresh verifies packages and defers when no daemon socket exists"

SYSTEMCTL_AVAILABLE=0 "$lifecycle" install >/dev/null
python3 - "$XDG_RUNTIME_DIR/omarchy/fabric.sock" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(sys.argv[1])
sock.close()
PY
set +e
unknown_uninstall=$(SYSTEMCTL_AVAILABLE=0 "$lifecycle" uninstall 2>&1)
unknown_uninstall_status=$?
set -e
(( unknown_uninstall_status == 75 )) ||
  fail "Fabric uninstall guessed success while its manager was unavailable and a socket remained" "$unknown_uninstall"
[[ ! -L $fallback_link ]] || fail "uncertain Fabric uninstall left next-login enablement behind"
[[ -S $XDG_RUNTIME_DIR/omarchy/fabric.sock ]] ||
  fail "uncertain Fabric uninstall unlinked a possibly live socket"
set +e
unknown_refresh=$(SYSTEMCTL_AVAILABLE=0 "$lifecycle" refresh 2>&1)
unknown_refresh_status=$?
set -e
(( unknown_refresh_status == 75 )) ||
  fail "Fabric refresh guessed success while its manager was unavailable and a socket remained" "$unknown_refresh"
rm "$XDG_RUNTIME_DIR/omarchy/fabric.sock"
pass "manager-unavailable lifecycle preserves an unknown live socket and reports uncertainty"

database="$XDG_STATE_HOME/omarchy/fabric/fabric.db"
printf 'durable-state\n' >"$database"
chmod 0600 "$database"
python3 - "$XDG_RUNTIME_DIR/omarchy/fabric.sock" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(sys.argv[1])
sock.close()
PY
: >"$systemctl_log"
FABRIC_ACTIVE=1 "$lifecycle" uninstall >/dev/null
[[ -f $database && $(<"$database") == "durable-state" ]] ||
  fail "Fabric uninstall deleted or changed durable state"
[[ ! -e $XDG_RUNTIME_DIR/omarchy/fabric.sock ]] ||
  fail "Fabric uninstall left an owner-validated stale socket"
grep -Fx -- '--user disable --now omarchy-fabric.service' "$systemctl_log" >/dev/null ||
  fail "Fabric uninstall did not stop and disable the unit"
pass "Fabric uninstall disables execution, removes only its socket, and preserves durable state"

update_log="$test_root/update-restart.log"
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
exit 1
STUB
cat >"$stub_bin/omarchy-fabric-service" <<'STUB'
#!/bin/bash
printf 'fabric-service %s\n' "$*" >>"$UPDATE_LOG"
exit "${FABRIC_SERVICE_STATUS:-78}"
STUB
cat >"$stub_bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash
printf 'restart-shell\n' >>"$UPDATE_LOG"
STUB
cat >"$stub_bin/omarchy-state" <<'STUB'
#!/bin/bash
printf 'state %s\n' "$*" >>"$UPDATE_LOG"
STUB
chmod 0755 "$stub_bin/gum" "$stub_bin/omarchy-fabric-service" \
  "$stub_bin/omarchy-restart-shell" "$stub_bin/omarchy-state"
: >"$update_log"
set +e
update_output=$(UPDATE_LOG="$update_log" FABRIC_ENABLED=1 FABRIC_ACTIVE=1 \
  bash "$ROOT/bin/omarchy-update-restart" 2>&1)
update_status=$?
set -e
(( update_status == 1 )) || fail "update restart swallowed a failed Fabric refresh" "$update_output"
grep -Fx 'fabric-service refresh' "$update_log" >/dev/null ||
  fail "update restart did not invoke the lifecycle refresh"
grep -Fx 'restart-shell' "$update_log" >/dev/null ||
  fail "a failed Fabric refresh prevented the independent shell restart"
[[ $update_output == *"Fabric stopped because its updated runtime could not be verified"* ]] ||
  fail "update restart did not report that Fabric remained stopped" "$update_output"
pass "update refresh failure is visible, leaves Fabric stopped, and still completes the shell restart"

: >"$update_log"
set +e
unknown_update_output=$(UPDATE_LOG="$update_log" FABRIC_SERVICE_STATUS=75 \
  FABRIC_ENABLED=1 FABRIC_ACTIVE=1 bash "$ROOT/bin/omarchy-update-restart" 2>&1)
unknown_update_status=$?
set -e
(( unknown_update_status == 1 )) ||
  fail "update restart swallowed an uncertain Fabric manager failure" "$unknown_update_output"
[[ $unknown_update_output == *"previous daemon state is unknown"* ]] ||
  fail "update restart claimed Fabric stopped after a manager failure" "$unknown_update_output"
pass "update refresh distinguishes verified-stop incompatibility from unknown manager state"

rm -f "$database"
PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}" python3 - "$database" <<'PY'
import sqlite3
import sys

from omarchy_fabric.db import MIGRATIONS

connection = sqlite3.connect(sys.argv[1], isolation_level=None)
connection.execute("BEGIN IMMEDIATE")
try:
    for statement in MIGRATIONS[1]:
        connection.execute(statement)
    connection.execute(
        "INSERT OR REPLACE INTO schema_metadata(key, value) VALUES ('schema_version', '1')"
    )
    connection.execute("PRAGMA user_version = 1")
    connection.execute("COMMIT")
except Exception:
    connection.execute("ROLLBACK")
    raise
finally:
    connection.close()
PY
"$lifecycle" prepare-start

PYTHONDONTWRITEBYTECODE=1 "$ROOT/bin/omarchy-fabricd" &
fabric_pid=$!
for attempt in {1..160}; do
  [[ -S $XDG_RUNTIME_DIR/omarchy/fabric.sock ]] && break
  if ! kill -0 "$fabric_pid" 2>/dev/null; then
    wait "$fabric_pid"
    fail "packaged Fabric daemon exited during lifecycle migration"
  fi
  sleep 0.05
done
[[ -S $XDG_RUNTIME_DIR/omarchy/fabric.sock ]] || fail "packaged Fabric daemon did not create its socket"
kill "$fabric_pid"
wait "$fabric_pid"
fabric_pid=""

backup=$(find "$XDG_STATE_HOME/omarchy/fabric" -maxdepth 1 -type f -name 'fabric.db.pre-migrate-v1-to-v*-*.bak' -print -quit)
[[ -n $backup && $(stat -c %a "$backup") == "600" ]] ||
  fail "Fabric service startup did not retain an owner-only pre-migration backup"
PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}" python3 - "$database" "$backup" <<'PY'
import sqlite3
import sys

from omarchy_fabric.models import CURRENT_DATABASE_SCHEMA

database = sqlite3.connect(sys.argv[1])
backup = sqlite3.connect(sys.argv[2])
try:
    assert database.execute("PRAGMA user_version").fetchone()[0] == CURRENT_DATABASE_SCHEMA
    assert backup.execute("PRAGMA user_version").fetchone()[0] == 1
finally:
    database.close()
    backup.close()
PY
pass "packaged pre-start and daemon perform a real transactional schema migration with retained backup"

HOME="$test_root/migration-home" XDG_RUNTIME_DIR="$test_root/migration-runtime" \
  XDG_STATE_HOME="$test_root/migration-state" OMARCHY_PATH="$ROOT" \
  GRAPHICAL_ACTIVE=0 bash -euo pipefail "$migration" >/dev/null
pass "existing-user Fabric migration executes the real idempotent lifecycle helper"
