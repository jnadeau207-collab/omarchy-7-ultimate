#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const Model = requireFromRoot('shell/apps/ultimate-administration/AdministrationModel.js')

const routes = JSON.parse(fs.readFileSync(path.join(root, 'shell/apps/ultimate-administration/routes-v1.json'), 'utf8'))
const domainRoutes = routes.routes.filter(route => route.id !== Model.OVERVIEW_ROUTE)

assertEqual(routes.routes.length, 11, 'Administration exposes home plus all ten administration tools')
assertEqual(Model.ROUTE_QUERIES.length, 10, 'Administration closed query map covers all ten provider domains')
assertEqual(new Set(Model.ROUTE_QUERIES.map(query => query.routeId)).size, 10, 'Administration query map has no duplicate route')
assertDeepEqual(
  domainRoutes.map(route => route.id),
  Model.ROUTE_QUERIES.map(query => query.routeId),
  'Administration route order exactly matches the closed query map'
)
assertEqual(routes.appId, 'org.omarchy.Administration', 'Administration owns its own application identity')
assertEqual(routes.scheme, 'omarchy-administration', 'Administration owns its own deep-link scheme')

for (const route of domainRoutes) {
  const query = Model.queryForRoute(route.id)
  assert(query !== null, `${route.id} has a closed provider query`)
  assertEqual(query.providerId, route.providerId, `${route.id} reads only its catalog provider`)
  assertEqual(query.action, 'inspect', `${route.id} uses a read-only inventory action`)
  assertDeepEqual(
    Model.requestParameters(query),
    { provider: route.providerId, action: 'inspect', arguments: {} },
    `${route.id} sends exact empty inspect arguments`
  )
}

const builtins = fs.readFileSync(path.join(root, 'default/fabric/omarchy_fabric/provider_builtins.py'), 'utf8')
for (const query of Model.ROUTE_QUERIES) {
  assert(builtins.includes(`BuiltinProviderSpec("${query.providerId}"`), `${query.providerId} is a registered builtin provider`)
}

const leaf = fs.readFileSync(path.join(root, 'default/fabric/omarchy_fabric/providers/process/_leaf.py'), 'utf8')
assert(/inventory_action: str = "inspect"/.test(leaf), 'administration leaf providers declare inspect as their inventory action')

assert(Model.hostedPanel('administration.processes.overview') === null, 'Administration hosts no live panel')

function assertThrows(fn, description) {
  let threw = false
  try { fn() } catch (_) { threw = true }
  assert(threw, description)
}
assertThrows(
  () => Model.normalizedSelection(Model.queryForRoute('administration.processes.overview'), { resourceId: '../outside' }),
  'resource deep links reject traversal-shaped identifiers'
)
assertThrows(
  () => Model.normalizedSelection(Model.queryForRoute('administration.processes.overview'), { resourceId: 'process.1', extra: true }),
  'resource deep links reject unknown argument fields'
)
JS
pass "Administration reads ten registered providers through closed read-only queries"

desktop="$ROOT/applications/org.omarchy.Administration.desktop"
[[ -f $desktop ]] || fail "Administration ships a desktop entry"
grep -Fq 'StartupWMClass=org.omarchy.Administration' "$desktop"   || fail "Administration desktop entry declares its compositor class"
grep -Fq 'Actions=Home;Processes;Services;DeviceManager;Storage;Printers;Backup;Scheduled;Troubleshoot;Firewall;Accounts;' "$desktop"   || fail "Administration jump list offers every tool by name"
grep -Fq 'Name=Task Manager' "$desktop"   || fail "the processes route is published as Task Manager"
grep -Fq 'Name=Device Manager' "$desktop"   || fail "the devices route is published as Device Manager"
pass "Administration publishes a jump list naming Task Manager and Device Manager"

grep -Fq 'o.bind("CTRL + SHIFT + ESCAPE", "Task Manager"' "$ROOT/default/hypr/bindings/desktop.lua"   || fail "Desktop Mode binds Ctrl+Shift+Esc to Task Manager"
grep -Fq 'administration.processes.overview' "$ROOT/default/hypr/bindings/desktop.lua"   || fail "Ctrl+Shift+Esc opens the processes route directly"
pass "Ctrl+Shift+Esc opens Task Manager in Desktop Mode"

for registry in normalize_launch.py launch-product-app.bash ProductProtocol.js; do
  grep -Fq 'administration' "$ROOT/shell/apps/shared/$registry"     || fail "$registry registers the administration application"
done
pass "the standalone launch path registers administration everywhere it dispatches"

application="$ROOT/shell/apps/ultimate-administration/AdministrationApplication.qml"
model="$ROOT/shell/apps/ultimate-administration/AdministrationModel.js"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-administration/AdministrationModel.js')

const processResource = Model.normalizeLeafResource({
  id: 'process.1234.0123456789abcdef',
  label: 'firefox',
  kind: 'process',
  state: {
    lifecycle: 'running',
    startDigest: '0123456789abcdef',
    identityRevision: `sha256.${'a'.repeat(64)}`,
    plannedSignal: null
  }
}, 0)
assert(processResource, 'process inspect resources project into Administration records')
assertEqual(processResource.startDigest, '0123456789abcdef', 'process records carry typed startDigest from inspect state')
assertEqual(Model.recordStartDigest(processResource), '0123456789abcdef', 'endTask reads typed startDigest only')
assertEqual(Model.processStartDigest({
  kind: 'process',
  state: { startDigest: '0123456789abcdef' }
}), '0123456789abcdef', 'processStartDigest reads state.startDigest, not details labels')
assertDeepEqual(
  Model.endTaskPreflightArguments(processResource),
  { resourceId: 'process.1234.0123456789abcdef', expectedStartDigest: '0123456789abcdef', signal: 'term' },
  'End Task preflight arguments use the typed startDigest field'
)

assertEqual(
  Model.recordStartDigest({
    id: 'process.1.deadbeefdeadbeef',
    kind: 'process',
    details: [{ label: 'Start Digest', value: 'deadbeefdeadbeef' }]
  }),
  '',
  'details-label scrape is not a startDigest path'
)
assertEqual(
  Model.processStartDigest({
    kind: 'service',
    state: { startDigest: '0123456789abcdef' }
  }),
  '',
  'non-process records do not carry process startDigest'
)
assertEqual(
  Model.processStartDigest({
    kind: 'process',
    state: { startDigest: 'not-a-digest' }
  }),
  '',
  'invalid startDigest tokens are refused'
)

const copy = Model.endTaskConfirmCopy()
assertEqual(copy.title, 'End Task', 'confirm copy uses Win7 End Task title')
assert(copy.message.includes('end this task'), 'confirm copy asks before ending the task')
assertEqual(copy.cancel, 'Cancel', 'confirm copy has a cancel path')
JS
pass "Administration carries typed startDigest and refuses details-label scrape"

if grep -Eiq 'indexOf\(["'"'"']start digest' "$application"; then
  fail "AdministrationApplication no longer scrapes details labels for start digest"
fi
if grep -En 'details\[.*\]\.label|toLowerCase\(\)\.indexOf\("start' "$application"; then
  fail "AdministrationApplication contains no details-label scrape loop"
fi
grep -Fq 'AdministrationModel.endTaskPreflightArguments(record)' "$application" \
  || fail "endTask gates on typed preflight arguments"
grep -Fq 'AdministrationModel.endTaskPreflightRequest(record, Date.now())' "$application" \
  || fail "confirmEndTask builds preflight from the typed startDigest path"
grep -Fq 'startDigest: processStartDigest(resource)' "$model" \
  || fail "normalizeLeafResource carries typed startDigest from process inspect state"
pass "typed startDigest path exists; details-label scrape is gone"

grep -Fq 'function confirmEndTask()' "$application" \
  || fail "End Task has an explicit confirm function"
grep -Fq 'onConfirmed: root.confirmEndTask()' "$application" \
  || fail "the confirm dialog confirm action runs confirmEndTask"
grep -Fq 'onCanceled: root.cancelEndTaskConfirm()' "$application" \
  || fail "the confirm dialog cancel action is wired"
grep -Fq 'function cancelEndTaskConfirm()' "$application" \
  || fail "Cancel has an explicit no-op handler"
if grep -A6 'function cancelEndTaskConfirm()' "$application" | grep -Fq 'operation.preflight'; then
  fail "Cancel must not issue operation.preflight"
fi
if grep -A8 'function endTask(record)' "$application" | grep -Fq 'operation.preflight'; then
  fail "endTask must not issue operation.preflight before confirm"
fi
grep -Fq 'root.operationRequestId = host.requestFabric("operation.preflight", request)' "$application" \
  || fail "confirmEndTask is the operation.preflight call site"
preflight_sites=$(grep -c 'operation.preflight' "$application" || true)
(( preflight_sites == 1 )) || fail "operation.preflight has exactly one Administration call site" "found $preflight_sites"
grep -Fq 'Ui.OperationDialog' "$application" \
  || fail "End Task confirm uses the existing OperationDialog"
pass "confirm gate exists before End Task preflight"

grep -Fq 'readonly property bool terminationAuthorized: false' "$application" \
  || fail "terminationAuthorized stays false; shell principal cannot authorize End Task"
grep -Fq 'text: root.terminationAuthorized ? "LIVE CONTROL" : "CHANGES UNAVAILABLE"' "$application" \
  || fail "unauthorized Administration coverage badge stays CHANGES UNAVAILABLE"
grep -A4 'text: root.terminationAuthorized ? "LIVE CONTROL" : "CHANGES UNAVAILABLE"' "$application" \
  | grep -Fq 'semanticProfile: root.productProfile' \
  || fail "Administration coverage badge consumes Semantics.text"
grep -Fq 'Semantics.text(root.productProfile, "Exact resource")' "$application" \
  || fail "Administration Exact resource prefix consumes Semantics.text"
grep -Fq 'Semantics.text(root.productProfile, "Display bound reached at")' "$application" \
  || fail "Administration display-bound notice consumes Semantics.text"
grep -Fq 'endTaskEnabled: root.terminationAuthorized && String(modelData.kind || "") === "process"' "$application" \
  || fail "End Task control stays hidden while terminationAuthorized is false"
if grep -Eq 'terminationAuthorized:\s*true' "$application"; then
  fail "Administration must not authorize shell consequential termination"
fi
pass "terminationAuthorized remains false; End Task stays hidden; no LIVE CONTROL claim"
