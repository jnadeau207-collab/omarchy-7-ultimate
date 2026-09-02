#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

entrypoint="$ROOT/shell/ultimate-files.qml"
application="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"

grep -Fqx '  fabricAllowedMethods: ["provider.catalog", "provider.read", "operation.preflight", "operation.approve", "operation.start", "operation.get"]' "$entrypoint" ||
  fail "Files declares the read plus bounded-operation Fabric allowlist"
for method in operation.get; do
  grep -Fq "\"$method\"" "$entrypoint" || fail "Files allowlists $method"
done
pass "Files carries the bounded operation allowlist and nothing wider"

grep -Fq 'provider: "files.provider"' "$application" || fail "Files creates through its own provider"
grep -Fq 'action: "directory.create"' "$application" || fail "Files uses the typed directory.create action"
for stage in operation.preflight operation.approve operation.start; do
  grep -Fq "\"$stage\"" "$application" || fail "Files drives the $stage step"
done
grep -Fq 'if (!host || operationBusy || !createVisible) return' "$application" ||
  fail "Files refuses a create outside a writable location route or during another operation"
pass "Files drives preflight, approve, and start against files.provider only"

card="$ROOT/shell/apps/ultimate-files/FilesRecordCard.qml"
grep -Fq 'action: "entry.trash"' "$application" || fail "Files trashes through the typed entry.trash action"
grep -Fq 'arguments: { entryId: String(record.id) }' "$application" ||
  fail "Files sends only the entry identity; the daemon derives the path from its own scope"
grep -Fq 'if (!record || String(record.kind || "") !== "entry" || String(record.status || "") === "symlink") return' "$application" ||
  fail "Files refuses to trash a non-entry record or a symlink"
grep -Fq 'if (!host || operationBusy || createLocationId === "") return' "$application" ||
  fail "Files offers Trash only where the route is a writable location"
grep -Fq "signal trashRequested()" "$card" || fail "the record card raises a Trash request rather than acting itself"
if grep -Eq 'rm |unlink|shutil' "$application"; then
  fail "Files deletes directly instead of routing through the operation plane"
fi
pass "Files moves an entry to Trash through entry.trash and never deletes directly"

if grep -Fq 'action: "trash.restore"' "$application"; then
  fail "Files does not offer trash.restore while the write plane cannot derive a Trash path"
fi
if grep -Eq 'key: "restore"' "$application"; then
  fail "Files does not show a Restore control that the write plane cannot complete"
fi
pass "Files keeps Restore honest-unavailable; Recycle Bin is not product-complete"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-files/FilesModel.js')

assertEqual(Model.createLocationForRoute('files.desktop'), 'files.location.desktop', 'Desktop is a create target')
assertEqual(Model.createLocationForRoute('files.documents'), 'files.location.documents', 'Documents is a create target')
assertEqual(Model.createLocationForRoute('files.downloads'), 'files.location.downloads', 'Downloads is a create target')
assertEqual(Model.createLocationForRoute('files.pictures'), 'files.location.pictures', 'Pictures is a create target')

for (const routeId of ['files.overview', 'files.this-pc', 'files.recent', 'files.search', 'files.trash', 'files.network', 'files.nope']) {
  assertEqual(Model.createLocationForRoute(routeId), '', `${routeId} offers no create target`)
}

assertEqual(Model.isTrashRoute('files.trash'), true, 'Trash is the Recycle Bin browse route')
for (const routeId of ['files.documents', 'files.desktop', 'files.overview', 'files.recent', 'files.search', 'files.network', '']) {
  assertEqual(Model.isTrashRoute(routeId), false, `${routeId || '(none)'} is not the Recycle Bin browse route`)
}

assertEqual(Model.createNameRefusal('Reports'), '', 'an ordinary folder name is accepted')
assertEqual(Model.createNameRefusal('My Folder'), '', 'a space is a legal folder name character')
assert(Model.createNameRefusal('') !== '', 'an empty name is refused')
assert(Model.createNameRefusal('.') !== '', 'a single dot is refused')
assert(Model.createNameRefusal('..') !== '', 'a double dot is refused')
assert(Model.createNameRefusal('a/b') !== '', 'a forward slash is refused')
assert(Model.createNameRefusal('a' + String.fromCharCode(92) + 'b') !== '', 'a backslash is refused')
assert(Model.createNameRefusal('a' + String.fromCharCode(0) + 'b') !== '', 'a null character is refused')
assert(Model.createNameRefusal('a' + String.fromCharCode(31) + 'b') !== '', 'a control character is refused')
assert(Model.createNameRefusal('x'.repeat(256)) !== '', 'a name past 255 characters is refused')
assertEqual(Model.createNameRefusal('x'.repeat(255)), '', 'a 255 character name is still accepted')

const traversal = Model.createNameRefusal('../../etc/passwd')
assert(traversal !== '', 'a traversal attempt is refused before it reaches the operation plane')
JS
pass "the create target map and name guard refuse traversal, separators, and control characters"
