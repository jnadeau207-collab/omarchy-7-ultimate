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

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-files/FilesModel.js')

assertEqual(Model.createLocationForRoute('files.desktop'), 'files.location.desktop', 'Desktop is a create target')
assertEqual(Model.createLocationForRoute('files.documents'), 'files.location.documents', 'Documents is a create target')
assertEqual(Model.createLocationForRoute('files.downloads'), 'files.location.downloads', 'Downloads is a create target')
assertEqual(Model.createLocationForRoute('files.pictures'), 'files.location.pictures', 'Pictures is a create target')

for (const routeId of ['files.overview', 'files.this-pc', 'files.recent', 'files.search', 'files.trash', 'files.network', 'files.nope']) {
  assertEqual(Model.createLocationForRoute(routeId), '', `${routeId} offers no create target`)
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
