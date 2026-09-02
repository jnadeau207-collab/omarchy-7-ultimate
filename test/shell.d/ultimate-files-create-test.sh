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

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-files/FilesModel.js')

function readAction(capability) {
  return {
    capability,
    mode: 'read',
    risk: 'read-only',
    effects: [],
    arguments: { id: 'contract.arguments', version: 'v0' },
    result: { id: 'contract.result', version: 'v0' },
    preflight: null,
    state: null,
    supportsRollback: false,
    supportsCancellation: false
  }
}

const fileActions = {
  inspect: readAction('files.inspect'),
  browse: readAction('files.browse'),
  search: readAction('files.search'),
  recent: readAction('files.recent.read')
}

function filesCatalog() {
  return {
    providers: [{
      manifest: {
        schemaVersion: 'v0',
        provider: 'files.provider',
        providerVersion: 'v0',
        minFabricProtocol: 0,
        maxFabricProtocol: 0,
        capabilities: Object.values(fileActions).map(action => action.capability),
        actions: fileActions
      },
      fingerprint: 'a'.repeat(64),
      generation: 4,
      registrationOrder: 1,
      state: 'available',
      detail: '',
      registeredAt: 1,
      changedAt: 2
    }]
  }
}

function desktopBrowse(observedAt) {
  return {
    provider: 'files.provider',
    providerVersion: 'v0',
    generation: 4,
    action: 'browse',
    capability: 'files.browse',
    observedAt,
    value: {
      schemaVersion: 'v0',
      provider: 'files.provider',
      providerVersion: 'v0',
      action: 'browse',
      availability: { state: 'available', read: true, operation: false, reasons: [] },
      revision: `sha256.${'a'.repeat(64)}`,
      truncated: false,
      entries: [{
        id: 'files.entry.note',
        locationId: 'files.location.desktop',
        parentId: null,
        name: 'note.txt',
        relativePath: 'note.txt',
        kind: 'file',
        sizeBytes: 4,
        modifiedMs: 1,
        mimeType: 'text/plain',
        hidden: false,
        writable: true,
        identity: `sha256.${'b'.repeat(64)}`,
        symlinkTargetState: null,
        trash: null
      }]
    }
  }
}

let sent = []
let serial = 0
const controller = Model.createController({
  send: (method, params) => {
    const id = `request.${++serial}`
    sent.push({ id, method, params })
    return id
  },
  cancel: () => true
})

controller.activate('files.desktop', {})
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'an offline Files surface does not reread')
assertEqual(sent.length, 0, 'offline surface-visible refresh issues no Fabric request')

assert(controller.setConnected(true), 'connecting starts the current catalog read')
assertEqual(controller.state.phase, 'catalog-loading', 'connect waits on the Files catalog')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a catalog-loading Files surface does not start a second reread')
assertEqual(sent.length, 1, 'catalog-loading surface-visible refresh does not duplicate the catalog request')

const catalogRequest = sent.at(-1)
assert(controller.receiveResult(catalogRequest.id, filesCatalog()), 'current Files catalog response is accepted')
assertEqual(controller.state.phase, 'loading', 'catalog selection advances to browse')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a loading Files surface does not start a second reread')
assertEqual(sent.length, 2, 'in-flight browse is not duplicated by surface-visible refresh')

const browseRequest = sent.at(-1)
assertEqual(browseRequest.method, 'provider.read', 'catalog selection issues files.browse')
assert(controller.receiveResult(browseRequest.id, desktopBrowse(21)), 'current desktop browse is accepted')
assertEqual(controller.state.phase, 'available', 'non-empty desktop browse reaches current state')

assert(controller.refreshWhenSurfaceVisible(), 'a ready Files surface rereads when it becomes visible')
const visibleReread = sent.at(-1)
assertEqual(visibleReread.method, 'provider.catalog', 'surface-visible refresh reuses controller.refresh catalog plus inspect')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a loading surface does not start a second reread')
assertEqual(sent.at(-1).id, visibleReread.id, 'in-flight surface reread is not duplicated')
JS
pass "Files rereads inspect when the surface becomes visible and skips while loading"

model="$ROOT/shell/apps/ultimate-files/FilesModel.js"
grep -Fq 'refreshWhenSurfaceVisible()' "$application" \
  || fail "Files rereads Fabric inspect when the product surface becomes visible"
grep -Fq 'function onSurfaceBecameActive()' "$application" \
  || fail "Files listens for host surface activation"
grep -Fq 'if (!controller || !host || operationBusy) return' "$application" \
  || fail "Files skips surface-visible reread while an operation is busy"
grep -Fq 'signal surfaceBecameActive()' "$ROOT/shell/apps/shared/ProductAppHost.qml" \
  || fail "Product host publishes surface activation instead of a Files polling loop"
if grep -Eq 'events[.](subscribe|unsubscribe)' "$application" "$model" "$entrypoint"; then
  fail "Files does not invent an events.subscribe path"
fi
pass "Files listens for surface activation without events.subscribe or a polling daemon"
