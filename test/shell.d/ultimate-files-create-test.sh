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
grep -Fq 'action: "entry.open"' "$application" || fail "Files uses the typed entry.open action"
grep -Fq 'action: "entry.rename"' "$application" || fail "Files uses the typed entry.rename action"
grep -Fq 'action: "entry.copy"' "$application" || fail "Files uses the typed entry.copy action"
grep -Fq 'function openEntry(record)' "$application" || fail "Files names openEntry for the launch plane"
grep -Fq 'function renameEntry(record, name)' "$application" || fail "Files names renameEntry for the rename plane"
grep -Fq 'function pasteStagedCopy()' "$application" || fail "Files names pasteStagedCopy for the copy plane"
grep -Fq 'arguments: { entryId: String(record.id) }' "$application" || fail "Files sends only the entry identity for Open"
for stage in operation.preflight operation.approve operation.start; do
  grep -Fq "\"$stage\"" "$application" || fail "Files drives the $stage step"
done
grep -Fq 'if (!host || operationBusy || !createVisible) return' "$application" ||
  fail "Files refuses a create outside a writable location route or during another operation"
pass "Files drives preflight, approve, and start against files.provider only"

card="$ROOT/shell/apps/ultimate-files/FilesRecordCard.qml"
grep -Fq 'readonly property bool trashAuthorized: false' "$application" \
  || fail "trashAuthorized stays false; shell principal cannot authorize Trash"
if grep -Eq 'trashAuthorized:\s*true' "$application"; then
  fail "Files must not authorize shell consequential trash"
fi
grep -Fq 'if (!root.trashAuthorized) return' "$application" \
  || fail "trashEntry refuses to start a doomed shell preflight"
grep -Fq 'if (root.createVisible && root.trashAuthorized)' "$application" \
  || fail "Delete stays hidden while trashAuthorized is false"
grep -Fq 'if (root.trashAuthorized) {' "$application" \
  || fail "Organize and context Delete stay hidden while trashAuthorized is false"
grep -Fq 'action: "entry.trash"' "$application" || fail "Files keeps the typed entry.trash action"
grep -Fq 'arguments: { entryId: String(record.id) }' "$application" ||
  fail "Files sends only the entry identity; the daemon derives the path from its own scope"
grep -Fq 'if (!record || String(record.kind || "") !== "entry" || String(record.status || "") === "symlink") return' "$application" ||
  fail "Files refuses to trash a non-entry record or a symlink"
grep -Fq 'if (!host || operationBusy || createLocationId === "") return' "$application" ||
  fail "Files still scopes trash to a writable location if authorization is ever granted"
grep -Fq "signal trashRequested()" "$card" || fail "the record card raises a Trash request rather than acting itself"
grep -Fq 'trashable: false' "$application" || fail "the properties card does not enable Move to Trash under the shell principal"
if grep -Eq 'rm |unlink|shutil' "$application"; then
  fail "Files deletes directly instead of routing through the operation plane"
fi
if grep -Eq 'action: "(files\.)?trash\.manage"|key: "trash.manage"' "$application"; then
  fail "Files does not invent a files.trash.manage action or control"
fi
grep -Fq 'files.trash.manage remain unavailable' "$application" \
  || fail "Files names files.trash.manage only as unavailable"
if grep -Fq 'LIVE CONTROL' "$application"; then
  fail "Files must not claim LIVE CONTROL for Trash under the shell principal"
fi
grep -Fq 'readonly property bool createEnabled: createVisible && !operationBusy && host !== null && host.fabricReady' "$application" \
  || fail "New folder stays enabled on writable location routes"
grep -Fq 'if (root.createVisible) list.push({ key: "new-folder", label: "New folder", dropdown: false, enabled: root.createEnabled })' "$application" \
  || fail "New folder remains a LIVE command-bar control"
pass "Files keeps typed entry.trash but does not enable LIVE Trash under the shell principal"

if grep -Fq 'action: "trash.restore"' "$application"; then
  fail "Files does not offer trash.restore LIVE under the shell principal"
fi
if grep -Eq 'key: "restore"' "$application"; then
  fail "Files does not show a Restore LIVE control under the shell principal"
fi
pass "Files keeps Restore UI honest-unavailable; Recycle Bin is not product-complete"

grep -Fq 'root.operationKind = "open"' "$application" || fail "Files drives the open operation kind"
grep -Fq 'String(record.entryKind || "") !== "file"' "$application" || fail "Files opens only regular file entries"
grep -Fq 'files.location.trash' "$application" || fail "Files refuses Open from Trash"
if grep -Eq 'Open With|Default Programs' "$application"; then
  fail "Files invents Open With or Default Programs MIME UI"
fi
if grep -Eq 'readFile\(|XMLHttpRequest|FileReader' "$application"; then
  fail "Files must not read file contents for thumbnails"
fi
grep -Fq 'File contents are never read' "$application" || fail "Files keeps the no-content-read boundary"
pass "Files Open is LIVE for regular files without inventing MIME UI or thumbnails"

grep -Fq 'readonly property bool renameAuthorized: true' "$application" \
  || fail "renameAuthorized stays true; SHELL can authorize same-directory rename"
if grep -Eq 'renameAuthorized:\s*false' "$application"; then
  fail "Files must not hide SHELL-grantable rename"
fi
grep -Fq 'if (!root.renameAuthorized) return' "$application" \
  || fail "renameEntry refuses when authorization is withdrawn"
grep -Fq 'key: "rename", label: "Rename"' "$application" \
  || fail "Rename stays a gated command-bar control"
grep -Fq 'arguments: { entryId: String(record.id), newName: String(name) }' "$application" \
  || fail "Files sends only the entry identity and new name for Rename"
grep -Fq 'readonly property bool copyAuthorized: true' "$application" \
  || fail "copyAuthorized stays true; SHELL can authorize scoped copy"
if grep -Eq 'copyAuthorized:\s*false' "$application"; then
  fail "Files must not hide SHELL-grantable copy"
fi
grep -Fq 'if (!root.copyAuthorized) return' "$application" \
  || fail "copy and paste refuse when authorization is withdrawn"
grep -Fq 'key: "copy", label: "Copy"' "$application" \
  || fail "Copy stays a gated command-bar control"
grep -Fq 'key: "paste", label: "Paste"' "$application" \
  || fail "Paste stays a gated command-bar control"
if grep -Eq 'key: "cut"' "$application"; then
  fail "Files invents LIVE Cut"
fi
if grep -Eq 'action: "entry.move"' "$application"; then
  fail "Files invents LIVE cut/move under SHELL"
fi
if grep -Eq 'wl-copy|wl-paste|Qt\.application\.clipboard' "$application"; then
  fail "Files invents an OS clipboard product"
fi
grep -Fq 'readonly property bool cutAuthorized: false' "$application" \
  || fail "cutAuthorized stays false; shell principal cannot authorize move"
if grep -Eq 'cutAuthorized:\s*true' "$application"; then
  fail "Files invents cutAuthorized=true"
fi
grep -Fq 'The cut/move write plane exists but is not shell-authorizable' "$application" \
  || fail "Files names the cut/move write plane as not shell-authorizable"
grep -Fq 'The OS clipboard and folder copy stay unavailable' "$application" \
  || fail "Files names the OS clipboard leftover instead of inventing one"
pass "Files Rename is LIVE and Copy/Paste stay in-app without inventing LIVE Cut or an OS clipboard"

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

assertEqual(Model.nextCopyName({}, 'notes.txt'), 'notes.txt', 'an unused name is reused')
assertEqual(Model.nextCopyName({ 'notes.txt': true }, 'notes.txt'), 'notes (2).txt', 'a taken name gets a numbered replica')
assertEqual(Model.nextCopyName({ 'notes.txt': true, 'notes (2).txt': true }, 'notes.txt'), 'notes (3).txt', 'numbered replicas skip taken names')
assertEqual(Model.nextCopyName({}, 'a/b'), '', 'a separator is refused before copy staging')
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
