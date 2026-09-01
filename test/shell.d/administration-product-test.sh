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
