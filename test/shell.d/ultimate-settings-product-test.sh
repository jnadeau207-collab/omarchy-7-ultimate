#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const routes = JSON.parse(fs.readFileSync(path.join(root, 'shell/apps/ultimate-settings/routes-v1.json'), 'utf8'))
const domainRoutes = routes.routes.filter(route => route.id !== Model.OVERVIEW_ROUTE)

assertEqual(routes.routes.length, 13, 'Settings exposes home plus all twelve product domains')
assertEqual(Model.ROUTE_QUERIES.length, 12, 'Settings closed query map covers all twelve provider domains')
assertEqual(new Set(Model.ROUTE_QUERIES.map(query => query.routeId)).size, 12, 'Settings query map has no duplicate route')
assertDeepEqual(
  domainRoutes.map(route => route.id),
  Model.ROUTE_QUERIES.map(query => query.routeId),
  'Settings route order exactly matches the closed query map'
)
for (const route of domainRoutes) {
  const query = Model.queryForRoute(route.id)
  assert(query !== null, `${route.id} has a closed provider query`)
  assertEqual(query.providerId, route.providerId, `${route.id} reads only its catalog provider`)
  assertEqual(query.action, 'inspect', `${route.id} uses its intended inventory action rather than sorting actions`)
  assertDeepEqual(
    Model.requestParameters(query),
    { provider: route.providerId, action: 'inspect', arguments: {} },
    `${route.id} sends exact empty inspect arguments`
  )
}

const staticManifestDomains = ['display', 'audio', 'network', 'bluetooth', 'input', 'power', 'defaults']
for (const domain of staticManifestDomains) {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, `default/fabric/omarchy_fabric/providers/${domain}/manifest-v0.json`), 'utf8'))
  const query = Model.ROUTE_QUERIES.find(candidate => candidate.providerId === manifest.provider)
  assert(query !== undefined, `${manifest.provider} has a Settings route`)
  assertEqual(manifest.actions[query.action].mode, 'read', `${manifest.provider}.${query.action} is read-only in provider truth`)
  assertEqual(manifest.actions[query.action].capability, query.capability, `${manifest.provider} capability matches the Settings mapping`)
}
const leafBuilder = fs.readFileSync(path.join(root, 'default/fabric/omarchy_fabric/providers/process/_leaf.py'), 'utf8')
assert(/inventory_action: str = "inspect"/.test(leafBuilder), 'administration leaf providers declare inspect as their inventory action')
for (const domain of ['update', 'recovery']) {
  const source = fs.readFileSync(path.join(root, `default/fabric/omarchy_fabric/providers/${domain}/provider.py`), 'utf8')
  assert(source.includes(`PROVIDER_ID = "${domain}.provider"`), `${domain} route targets the code-owned provider identity`)
  assert(source.includes('provider_bundle('), `${domain} provider consumes the closed administration leaf contract`)
}
const builtins = fs.readFileSync(path.join(root, 'default/fabric/omarchy_fabric/provider_builtins.py'), 'utf8')
for (const missingProvider of ['personalization.provider', 'accessibility.provider', 'system-information.provider']) {
  assert(!builtins.includes(`BuiltinProviderSpec("${missingProvider}"`), `${missingProvider} remains honestly not registered`)
}

function assertThrows(fn, description) {
  let threw = false
  try { fn() } catch (_) { threw = true }
  assert(threw, description)
}

assertThrows(
  () => Model.normalizedSelection(Model.queryForRoute('settings.personalization.overview'), { resourceId: 'theme.one' }),
  'routes without a resource contract reject resource deep links'
)
assertThrows(
  () => Model.normalizedSelection(Model.queryForRoute('settings.network.overview'), { resourceId: '../outside' }),
  'resource deep links reject traversal-shaped identifiers'
)
assertThrows(
  () => Model.normalizedSelection(Model.queryForRoute('settings.network.overview'), { resourceId: 'network.radio.wifi', extra: true }),
  'resource deep links reject unknown argument fields'
)
assertEqual(Model.queryForRoute('settings.not-real'), null, 'unknown Settings routes fail closed before transport')

assertEqual(Model.hostedPanel('settings.display.overview'), null, 'Display reads Fabric inspect instead of hosting the Process monitor panel')
assertEqual(Model.hostedPanel('settings.audio.overview'), null, 'Sound reads Fabric inspect instead of hosting the Process audio panel')
assertEqual(Model.hostedPanel('settings.network.overview'), null, 'Network reads Fabric inspect instead of hosting the Process nmcli panel')
assertEqual(Model.hostedPanel('settings.bluetooth.overview'), null, 'Bluetooth reads Fabric inspect instead of hosting the Process bluetoothctl panel')
assertEqual(Model.hostedPanel('settings.power.overview'), null, 'Power reads Fabric inspect instead of hosting the Process power panel')
const hosted = [
  ['settings.personalization.overview', 'Ui/SettingsPersonalizationHost.qml', 'omarchy.image-picker']
]
for (const [routeId, source, pluginId] of hosted) {
  const spec = Model.hostedPanel(routeId)
  assert(spec !== null, `${routeId} hosts an existing panel`)
  assertEqual(spec.source, source, `${routeId} hosts ${source}`)
  assertEqual(spec.pluginId, pluginId, `${routeId} names ${pluginId}`)
  assert(String(spec.honesty).includes('Phase 5'), `${routeId} labels typed services as Phase 5`)
}
const liveWriterRoutes = [
  'settings.audio.overview',
  'settings.network.overview',
  'settings.power.overview',
  'settings.display.overview',
  'settings.input.overview',
  'settings.apps.overview'
]
assertDeepEqual(Model.LIVE_WRITER_ROUTES, liveWriterRoutes, 'Settings names the six live writer routes')
for (const routeId of liveWriterRoutes) {
  assertEqual(Model.routeHasLiveWriter(routeId), true, `${routeId} is a live writer`)
  assertEqual(Model.coverageBadge(routeId), 'PARTIAL LIVE CONTROL', `${routeId} coverage badge is partial live control`)
  assertEqual(Model.coverageTone(routeId), 'info', `${routeId} coverage tone is info`)
  assert(Model.declaredOpsHonesty(routeId).includes('preflight, approval, and the durable coordinator'), `${routeId} declared ops name the live writer path`)
}
for (const routeId of ['settings.bluetooth.overview', 'settings.update.overview', 'settings.recovery.overview', 'settings.accessibility.overview', 'settings.system.overview', 'settings.personalization.overview', '']) {
  assertEqual(Model.routeHasLiveWriter(routeId), false, `${routeId || '(none)'} is not a live writer`)
  assertEqual(Model.coverageBadge(routeId), 'CHANGES UNAVAILABLE', `${routeId || '(none)'} coverage badge stays unavailable`)
  assert(Model.declaredOpsHonesty(routeId).includes('no preflight, approval, or execution control'), `${routeId || '(none)'} declared ops stay unavailable`)
}
const footer = Model.authorityFooter()
assert(footer.includes('Sound volume') && footer.includes('Network Wi-Fi radio') && footer.includes('Power profile') && footer.includes('Display brightness') && footer.includes('Input layout') && footer.includes('Apps default browser'), 'authority footer names every live writer')
assert(footer.includes('other domains stay inspect-only'), 'authority footer keeps remaining domains inspect-only')
assert(!footer.includes('no direct commands, mutation, preflight, approval, or execution authority'), 'authority footer does not deny mutation on a mutating window')

assertEqual(Model.hostedPanel('settings.accessibility.overview'), null, 'Accessibility stays an honest Fabric page; no accessibility panel exists')
assertEqual(Model.hostedPanel('settings.system.overview'), null, 'System stays an honest Fabric page; no system-information panel exists')
const displayResource = Model.normalizeLeafResource({
  id: `display.output.${'d'.repeat(64)}`,
  label: 'HDMI-A-1',
  kind: 'output',
  enabled: true,
  focused: true,
  mode: { width: 1920, height: 1080, refreshHz: 60 },
  position: { x: 0, y: 0 },
  scale: 1,
  transform: 0,
  mirrorOf: null,
  dpms: true,
  state: { available: false, percent: null }
}, 0)
assert(displayResource, 'display.inspect resources project into Settings records')
assertEqual(displayResource.label, 'HDMI-A-1', 'Display records keep the connector label')
const displayDetail = Object.fromEntries((displayResource.details || []).map(field => [field.label, field.value]))
assertEqual(displayDetail['Mode Width'], '1920', 'Display records surface host mode width')
assertEqual(displayDetail['Mode Height'], '1080', 'Display records surface host mode height')
assertEqual(displayDetail.Scale, '1', 'Display records surface host scale')
const audioResource = Model.normalizeLeafResource({
  id: `audio.sink.${'a'.repeat(64)}`,
  label: 'Starship/Matisse HD Audio Controller Digital Stereo (IEC958)',
  kind: 'sink',
  default: true,
  physical: true,
  ports: [],
  activePort: null,
  state: { muted: false, channels: { 'front-left': 40, 'front-right': 40 } }
}, 0)
assert(audioResource, 'audio.inspect resources project into Settings records')
assertEqual(audioResource.label, 'Starship/Matisse HD Audio Controller Digital Stereo (IEC958)', 'Sound records keep the sink label')
const audioDetail = Object.fromEntries((audioResource.details || []).map(field => [field.label, field.value]))
assertEqual(audioDetail.Muted, 'No', 'Sound records surface host mute')
assertEqual(audioDetail['Channels Front Left'], '40', 'Sound records surface host left channel volume')
assertEqual(audioDetail['Channels Front Right'], '40', 'Sound records surface host right channel volume')
assertEqual(audioDetail.Default, 'Yes', 'Sound records surface the default sink')
const networkRadio = Model.normalizeLeafResource({
  id: 'network.radio.wifi',
  label: 'Wi-Fi radio',
  kind: 'wifi-radio',
  state: { managerRunning: true, hardwareEnabled: false, enabled: true }
}, 0)
assert(networkRadio, 'network.inspect radio resources project into Settings records')
assertEqual(networkRadio.label, 'Wi-Fi radio', 'Network records keep the Wi-Fi radio label')
const radioDetail = Object.fromEntries((networkRadio.details || []).map(field => [field.label, field.value]))
assertEqual(radioDetail.Enabled, 'Yes', 'Network records surface host Wi-Fi radio enabled')
assertEqual(radioDetail['Hardware Enabled'], 'No', 'Network records surface host Wi-Fi hardware missing as not enabled')
assertEqual(radioDetail['Manager Running'], 'Yes', 'Network records surface host NetworkManager running')
const networkIface = Model.normalizeLeafResource({
  id: `network.interface.${'b'.repeat(64)}`,
  label: 'enp4s0',
  kind: 'ethernet',
  state: { status: 'connected', connection: 'enp4s0' }
}, 0)
assert(networkIface, 'network.inspect interface resources project into Settings records')
assertEqual(networkIface.label, 'enp4s0', 'Network records keep the interface label')
const ifaceDetail = Object.fromEntries((networkIface.details || []).map(field => [field.label, field.value]))
assertEqual(ifaceDetail.Status, 'connected', 'Network records surface host interface status')
assertEqual(ifaceDetail.Connection, 'enp4s0', 'Network records surface host connection name')
const bluetoothController = Model.normalizeLeafResource({
  id: `bluetooth.controller.${'c'.repeat(64)}`,
  label: 'Omarchy Box',
  kind: 'controller',
  state: { powered: true, discovering: false }
}, 0)
assert(bluetoothController, 'bluetooth.inspect controller resources project into Settings records')
assertEqual(bluetoothController.label, 'Omarchy Box', 'Bluetooth records keep the controller label')
const controllerDetail = Object.fromEntries((bluetoothController.details || []).map(field => [field.label, field.value]))
assertEqual(controllerDetail.Powered, 'Yes', 'Bluetooth records surface host controller power')
assertEqual(controllerDetail.Discovering, 'No', 'Bluetooth records surface host discovering state')
const bluetoothDevice = Model.normalizeLeafResource({
  id: `bluetooth.device.${'e'.repeat(64)}`,
  label: 'Headphones',
  kind: 'device',
  state: { paired: true, connected: true }
}, 0)
assert(bluetoothDevice, 'bluetooth.inspect device resources project into Settings records')
assertEqual(bluetoothDevice.label, 'Headphones', 'Bluetooth records keep the device label')
const deviceDetail = Object.fromEntries((bluetoothDevice.details || []).map(field => [field.label, field.value]))
assertEqual(deviceDetail.Paired, 'Yes', 'Bluetooth records surface host paired state')
assertEqual(deviceDetail.Connected, 'Yes', 'Bluetooth records surface host connected state')
const powerResource = Model.normalizeLeafResource({
  id: 'power.profile.current',
  label: 'Power profile',
  kind: 'profile',
  battery: null,
  state: { source: 'ac', activeProfile: 'balanced', availableProfiles: ['balanced', 'performance', 'power-saver'] }
}, 0)
assert(powerResource, 'power.inspect resources project into Settings records')
assertEqual(powerResource.label, 'Power profile', 'Power records keep the profile label')
const powerDetail = Object.fromEntries((powerResource.details || []).map(field => [field.label, field.value]))
assertEqual(powerDetail.Source, 'ac', 'Power records surface host AC/battery source')
assertEqual(powerDetail['Active Profile'], 'balanced', 'Power records surface the active profile')
assertEqual(powerDetail['Available Profiles'], 'balanced, performance, power-saver', 'Power records surface available profiles')
assertEqual(powerDetail.Battery, 'Not reported', 'Desktop hosts without a battery stay null, not mocked')
assertEqual(Model.hostedPanel('settings.input.overview'), null, 'Input stays an honest Fabric page; keyboard layout is a bar widget, not a panel')
assertEqual(Model.hostedPanel('settings.overview'), null, 'Settings home is not a hosted panel')

function actionContract(capability, mode) {
  return {
    capability,
    mode,
    risk: mode === 'read' ? 'read-only' : 'low',
    effects: mode === 'read' ? [] : ['mutating'],
    arguments: { id: `urn:test:${capability}:arguments`, version: 'v0' },
    result: { id: `urn:test:${capability}:result`, version: 'v0' },
    preflight: mode === 'read' ? null : { id: `urn:test:${capability}:preflight`, version: 'v0' },
    state: mode === 'read' ? null : { id: `urn:test:${capability}:state`, version: 'v0' },
    supportsRollback: mode !== 'read',
    supportsCancellation: false
  }
}

function entryFor(query, order, state = 'available') {
  const operationCapability = query.providerId.replace('.provider', '.configure')
  return {
    manifest: {
      schemaVersion: 'v0', provider: query.providerId, providerVersion: 'v0',
      minFabricProtocol: 0, maxFabricProtocol: 0,
      capabilities: [query.capability, operationCapability],
      actions: {
        inspect: actionContract(query.capability, 'read'),
        configure: actionContract(operationCapability, 'operation')
      }
    },
    fingerprint: String(order % 10).repeat(64),
    generation: 1,
    registrationOrder: order,
    state,
    detail: state === 'available' ? '' : `${query.providerId} is ${state}`,
    registeredAt: 1,
    changedAt: 1
  }
}

const fullCatalog = { providers: Model.ROUTE_QUERIES.map((query, index) => entryFor(query, index)) }
assertEqual(Model.validateCatalogResponse(fullCatalog), '', 'Settings accepts the bounded exact provider catalog envelope')
for (const query of Model.ROUTE_QUERIES) {
  assertEqual(
    Model.queryContractError(Model.providerEntry(fullCatalog.providers, query.providerId), query),
    '',
    `${query.routeId} validates its intended action against catalog truth`
  )
}
const duplicateCatalog = { providers: fullCatalog.providers.concat([{ ...fullCatalog.providers[0], registrationOrder: 99 }]) }
assert(Model.validateCatalogResponse(duplicateCatalog).includes('duplicate provider'), 'duplicate provider identities fail closed')
const extraCatalogField = { providers: fullCatalog.providers, continuation: null }
assert(Model.validateCatalogResponse(extraCatalogField).includes('unexpected field'), 'extra catalog envelope fields fail closed')
const mismatchedEntry = JSON.parse(JSON.stringify(fullCatalog.providers[0]))
mismatchedEntry.manifest.actions.inspect.capability = mismatchedEntry.manifest.actions.configure.capability
assert(Model.queryContractError(mismatchedEntry, Model.ROUTE_QUERIES[0]).includes('closed read-only'), 'catalog action capability drift fails closed')

const productionLike = {
  providers: fullCatalog.providers.filter(entry => ![
    'personalization.provider', 'accessibility.provider', 'system-information.provider'
  ].includes(entry.manifest.provider))
}
const cards = Model.catalogCards(productionLike.providers)
assertEqual(cards.length, 12, 'overview always represents all twelve Settings domains')
assertEqual(cards.filter(card => card.status === 'not registered').length, 3, 'overview exposes every intentionally missing provider')
assert(cards.every(card => card.detail.length <= Model.MAX_DISPLAY_TEXT), 'overview details obey the display text bound')

function leafResult(query, entry, resources, availability = { read: true, operation: false, reason: null }) {
  return {
    provider: query.providerId,
    providerVersion: 'v0',
    generation: entry.generation,
    action: query.action,
    capability: query.capability,
    value: {
      schemaVersion: 'v0', provider: query.providerId, providerVersion: 'v0', action: query.action,
      availability,
      revision: `sha256.${'a'.repeat(64)}`,
      resources
    },
    observedAt: 1
  }
}

let sent = []
let cancelled = []
let serial = 0
const controller = Model.createController({
  send: (method, params) => {
    const id = `request.${++serial}`
    sent.push({ id, method, params })
    return id
  },
  cancel: id => { cancelled.push(id); return true }
})

assert(!controller.activate('settings.network.overview', { resourceId: 'network.radio.wifi' }), 'offline route activation does not issue a request')
assert(controller.setConnected(true), 'connecting starts the current catalog read')
const firstCatalogRequest = sent.at(-1)
assertEqual(firstCatalogRequest.method, 'provider.catalog', 'controller begins with only provider.catalog')
assertDeepEqual(firstCatalogRequest.params, {}, 'provider catalog uses exact empty parameters')
assert(controller.receiveResult(firstCatalogRequest.id, fullCatalog), 'current catalog response is accepted')
const networkRequest = sent.at(-1)
assertEqual(networkRequest.method, 'provider.read', 'catalog selection advances to only provider.read')
assertDeepEqual(
  networkRequest.params,
  { provider: 'network.provider', action: 'inspect', arguments: {} },
  'network route sends the exact intended inventory request'
)

assert(controller.activate('settings.display.overview', { resourceId: `display.output.${'a'.repeat(64)}` }), 'route activation starts a read from the validated current catalog')
assert(cancelled.includes(networkRequest.id), 'route activation cancels the superseded local read correlation')
assert(!controller.receiveResult(networkRequest.id, leafResult(
  Model.queryForRoute('settings.network.overview'),
  Model.providerEntry(fullCatalog.providers, 'network.provider'),
  [{ id: 'network.radio.wifi', label: 'Wi-Fi radio', kind: 'wifi-radio', state: { enabled: true } }]
)), 'late superseded provider results are ignored')
assertEqual(controller.state.routeId, 'settings.display.overview', 'late results cannot replace the active Settings route')

const displayQuery = Model.queryForRoute('settings.display.overview')
const displayEntry = Model.providerEntry(fullCatalog.providers, displayQuery.providerId)
const selectedDisplay = `display.output.${'a'.repeat(64)}`
const otherDisplay = `display.output.${'b'.repeat(64)}`
const displayRequest = sent.at(-1)
assert(controller.receiveResult(displayRequest.id, leafResult(displayQuery, displayEntry, [
  { id: selectedDisplay, label: 'Internal display', kind: 'display-output', state: { width: 1920, height: 1080, scale: 1, enabled: true } },
  { id: otherDisplay, label: 'External display', kind: 'display-output', state: { width: 2560, height: 1440, scale: 1.25, enabled: true } }
])), 'current typed display result is accepted')
assertEqual(controller.state.phase, 'ready', 'non-empty typed inventory reaches current state')
assertDeepEqual(controller.state.records.map(record => record.id), [selectedDisplay], 'resource deep links select one exact identity')
assertEqual(controller.state.records[0].details.length, 4, 'real typed resource fields become a bounded presentation')

const readyObserved = controller.state.observedAt
const sentBeforeWriter = sent.length
assertEqual(controller.refreshAfterSuccessfulWriter('failed'), false, 'a failed writer does not reread')
assertEqual(controller.refreshAfterSuccessfulWriter('running'), false, 'a running writer does not reread')
assertEqual(controller.refreshAfterSuccessfulWriter(''), false, 'an empty writer status does not reread')
assertEqual(sent.length, sentBeforeWriter, 'unsuccessful writers issue no Fabric request')
assertEqual(controller.state.phase, 'ready', 'unsuccessful writers leave current state in place')
assertEqual(controller.state.observedAt, readyObserved, 'unsuccessful writers keep the observed timestamp')

assert(controller.refreshAfterSuccessfulWriter('succeeded'), 'a successful writer rereads the open route')
const writerReread = sent.at(-1)
assertEqual(writerReread.method, 'provider.read', 'successful writer refresh is provider.read of the open route')
assertDeepEqual(
  writerReread.params,
  { provider: 'display.provider', action: 'inspect', arguments: {} },
  'successful writer refresh keeps the closed display inspect arguments'
)
assertEqual(controller.state.phase, 'loading', 'successful writer refresh shows loading while rereading')
const writerResult = leafResult(displayQuery, displayEntry, [
  { id: selectedDisplay, label: 'Internal display', kind: 'display-output', state: { width: 1920, height: 1080, scale: 1, enabled: true } }
])
writerResult.observedAt = 55
assert(controller.receiveResult(writerReread.id, writerResult), 'writer reread result is accepted')
assertEqual(controller.state.phase, 'ready', 'writer reread returns current state')
assertEqual(controller.state.observedAt, 55, 'writer reread replaces the observed timestamp')

assert(controller.refreshWhenSurfaceVisible(), 'a ready surface rereads when it becomes visible')
const visibleReread = sent.at(-1)
assertEqual(visibleReread.method, 'provider.read', 'surface-visible refresh is provider.read')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a loading surface does not start a second reread')
assertEqual(sent.at(-1).id, visibleReread.id, 'in-flight surface reread is not duplicated')
assert(controller.receiveResult(visibleReread.id, leafResult(displayQuery, displayEntry, [
  { id: selectedDisplay, label: 'Internal display', kind: 'display-output', state: { width: 1920, height: 1080, scale: 1, enabled: true } }
])), 'surface-visible reread result is accepted')

controller.activate('settings.display.overview', { resourceId: `display.output.${'c'.repeat(64)}` })
const absentRequest = sent.at(-1)
controller.receiveResult(absentRequest.id, leafResult(displayQuery, displayEntry, [
  { id: selectedDisplay, label: 'Internal display', kind: 'display-output', state: { enabled: true } }
]))
assertEqual(controller.state.phase, 'empty', 'an absent exact deep-link target is not broadened to other resources')
assert(controller.state.selectedMissing, 'an absent exact target remains distinguishable from an empty provider')

controller.activate('settings.network.overview', {})
const networkCurrentRequest = sent.at(-1)
controller.receiveFailure(networkCurrentRequest.id, { code: 'access.denied', explanation: 'Provider state is not visible.', recoveryActions: [] })
assertEqual(controller.state.phase, 'denied', 'access failure has an explicit denied state')
controller.refresh()
const refreshCatalog = sent.at(-1)
controller.receiveFailure(refreshCatalog.id, { code: 'rpc.cancelled', explanation: 'Read cancelled.', recoveryActions: ['fabric.reconnect'] })
assertEqual(controller.state.phase, 'interrupted', 'catalog cancellation has an explicit interrupted state')
assertDeepEqual(controller.state.recoveryActions, ['fabric.reconnect'], 'structured recovery paths remain visible')

controller.refresh()
const staleCatalog = sent.at(-1)
assert(controller.markStale(staleCatalog.id), 'bounded deadline marks the active read stale')
assertEqual(controller.state.phase, 'stale', 'deadline state is explicitly stale')
assert(cancelled.includes(staleCatalog.id), 'stale deadline cancels the local pending correlation')
assert(!controller.receiveResult(staleCatalog.id, fullCatalog), 'late result after deadline is ignored')

controller.setConnected(false)
assertEqual(controller.state.phase, 'offline', 'disconnect has an explicit offline state')
assertEqual(controller.state.records.length, 0, 'disconnect clears live records instead of presenting stale cache')
assertEqual(controller.state.catalog.length, 0, 'disconnect clears the provider catalog')

const missingController = Model.createController({ send: (method, params) => {
  sent.push({ id: `missing.${++serial}`, method, params })
  return `missing.${serial}`
}})
missingController.activate('settings.personalization.overview', {})
missingController.setConnected(true)
const missingCatalogRequest = sent.at(-1)
missingController.receiveResult(missingCatalogRequest.id, productionLike)
assertEqual(missingController.state.phase, 'missing', 'unregistered route provider has an explicit missing state')
assertEqual(sent.at(-1).method, 'provider.catalog', 'missing providers never trigger a guessed provider read')

const degradedCatalog = JSON.parse(JSON.stringify(fullCatalog))
const degradedNetwork = degradedCatalog.providers.find(entry => entry.manifest.provider === 'network.provider')
degradedNetwork.state = 'degraded'
degradedNetwork.detail = 'Network inventory is partial.'
const degradedController = Model.createController({ send: (method, params) => {
  const id = `degraded.${++serial}`
  sent.push({ id, method, params })
  return id
}})
degradedController.activate('settings.network.overview', {})
degradedController.setConnected(true)
degradedController.receiveResult(sent.at(-1).id, degradedCatalog)
const degradedRead = sent.at(-1)
degradedController.receiveResult(degradedRead.id, leafResult(
  Model.queryForRoute('settings.network.overview'), degradedNetwork,
  [{ id: 'network.radio.wifi', label: 'Wi-Fi radio', kind: 'wifi-radio', state: { enabled: true } }]
))
assertEqual(degradedController.state.phase, 'degraded', 'usable degraded provider state stays visibly degraded')
assertEqual(degradedController.state.records.length, 1, 'degraded state shows only the real returned resources')

const defaultsQuery = Model.queryForRoute('settings.apps.overview')
const defaultsEntry = Model.providerEntry(fullCatalog.providers, defaultsQuery.providerId)
const defaultsResult = {
  provider: defaultsQuery.providerId, providerVersion: 'v0', generation: defaultsEntry.generation,
  action: defaultsQuery.action, capability: defaultsQuery.capability, observedAt: 2,
  value: {
    schemaVersion: 'v0', provider: defaultsQuery.providerId, providerVersion: 'v0', action: 'inspect',
    availability: { state: 'available', read: true, operation: false, reasons: [] },
    revision: `sha256.${'d'.repeat(64)}`,
    state: {
      schemaVersion: 'v0', databaseId: 'defaults.database.primary',
      associations: [{ id: 'defaults.association.http', kind: 'protocol', key: 'http', defaultAppId: 'app.browser', candidateAppIds: ['app.browser'], writable: true, source: 'user', status: 'configured', identity: `sha256.${'e'.repeat(64)}` }],
      applications: [{ id: 'app.browser', desktopId: 'browser.desktop', name: 'Browser', state: 'available', icon: 'browser', mimeTypes: ['text/html'], protocols: ['http'], source: 'user', identity: `sha256.${'f'.repeat(64)}`, reason: null }]
    }
  }
}
const defaultsState = Model.baseState('settings.apps.overview', { resourceId: 'app.browser' }, 'loading')
defaultsState.providerEntry = defaultsEntry
const acceptedDefaults = Model.acceptedReadState(defaultsState, defaultsResult)
assertEqual(acceptedDefaults.phase, 'ready', 'Apps renders the real defaults provider database')
assertDeepEqual(acceptedDefaults.records.map(record => record.id), ['app.browser'], 'Apps deep links select exact applications as well as provider resources')
assert(acceptedDefaults.records[0].label === 'Browser', 'Apps presents the typed application name')

const manyResources = Array.from({ length: Model.MAX_VISIBLE_RECORDS + 4 }, (_, index) => ({
  id: `network.interface.${String(index).padStart(3, '0')}`,
  label: `Interface ${index}`,
  kind: 'ethernet',
  state: Object.fromEntries(Array.from({ length: Model.MAX_VISIBLE_FIELDS + 5 }, (__, field) => [`field${field}`, `${'x'.repeat(1000)}-${field}`]))
}))
const bounded = Model.normalizedRecords(Model.queryForRoute('settings.network.overview'), { resources: manyResources }, '')
assertEqual(bounded.records.length, Model.MAX_VISIBLE_RECORDS, 'visible provider records have a hard local bound')
assert(bounded.clipped, 'record clipping is explicit')
assert(bounded.records.every(record => record.details.length <= Model.MAX_VISIBLE_FIELDS), 'record detail fields have a hard local bound')
assert(bounded.records.every(record => record.details.every(detail => detail.value.length <= Model.MAX_DISPLAY_TEXT)), 'record values have a hard text bound')
const controlText = Model.clippedText(`prefix\u0000${'z'.repeat(5000)}`)
assert(controlText.length <= Model.MAX_DISPLAY_TEXT && controlText.endsWith('\u2026') && !controlText.includes('\u0000'), 'display text strips controls and clips long strings')

assert(sent.every(request => ['provider.catalog', 'provider.read'].includes(request.method)), 'Settings controller can issue only catalog and read methods')
assert(!sent.some(request => request.method.includes('preflight') || request.method.includes('invoke')), 'Settings never invokes mutation or preflight')

let rejectedController
rejectedController = Model.createController({
  send: () => {
    rejectedController.receiveFailure('', { code: 'client.method-denied', explanation: 'Method is not allowed.', recoveryActions: [] })
    return ''
  }
})
rejectedController.setConnected(true)
assertEqual(rejectedController.state.phase, 'denied', 'synchronous local allowlist rejection is correlated honestly')
JS
pass "Settings hosts Personalization; Display, Sound, Network, Bluetooth, and Power read Fabric inspect"

entrypoint="$ROOT/shell/ultimate-settings.qml"
application="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
card="$ROOT/shell/apps/ultimate-settings/SettingsRecordCard.qml"

grep -Fqx '  fabricAllowedMethods: ["provider.catalog", "provider.read", "operation.preflight", "operation.approve", "operation.start", "operation.get"]' "$entrypoint" \
  || fail "Settings allowlist is exactly the two reads and the four operation steps"
if grep -Eq 'fabricAllowedMethods:.*(provider[.]invoke|operation[.]cancel|operation[.]ledger|events[.])' "$entrypoint"; then
  fail "Settings must not hold a method beyond its reads and its own operation steps"
fi
if grep -En 'provider\.invoke|reference\.operation|operation\.(cancel|ledger)|managed-work\.query' \
  "$entrypoint" "$application" "$model" "$card"; then
  fail "Settings contains no unmediated mutation, legacy-operation, or managed-work method"
fi
pass "Settings method surface is exactly catalog plus typed read"

if grep -En '(^|[^A-Za-z])(Process[[:space:]]*\{|Quickshell\.execDetached|execDetached\(|pkexec|sudo|hyprctl|systemctl|bash[[:space:]]+-c|sh[[:space:]]+-c)' \
  "$application" "$model" "$card"; then
  fail "Settings presentation contains no process, shell, compositor, or privilege fallback"
fi
pass "Settings has no direct command or privilege path"

if grep -Fq 'firstReadAction' "$application" "$model"; then
  fail "Settings no longer guesses the first alphabetic read action"
fi
grep -Fq 'var ROUTE_QUERIES = [' "$model" || fail "Settings owns a closed route query map"
grep -Fq 'queryContractError(entry, query)' "$model" || fail "Settings validates route actions against catalog truth"
grep -Fq 'requestParameters(query)' "$model" || fail "Settings constructs exact provider read arguments"
pass "Settings selects deterministic contract-aware inventory actions"

grep -Fq 'typeof root.host.cancelFabric !== "function"' "$application" \
  || fail "Settings remains generation-safe on hosts without local correlation cancellation"
grep -Fq 'root.host.cancelFabric(requestId)' "$application" \
  || fail "Settings releases superseded correlations when the host exposes cancellation"
grep -Fq 'markStale(root.queryState.requestId)' "$application" \
  || fail "Settings enforces a bounded stale-read deadline"
grep -Fq 'refreshAfterSuccessfulWriter(result.status)' "$application" \
  || fail "Settings rereads Fabric inspect after a successful local writer"
grep -Fq 'refreshWhenSurfaceVisible()' "$application" \
  || fail "Settings rereads Fabric inspect when the product surface becomes visible"
grep -Fq 'function onSurfaceBecameActive()' "$application" \
  || fail "Settings listens for host surface activation"
grep -Fq 'signal surfaceBecameActive()' "$ROOT/shell/apps/shared/ProductAppHost.qml" \
  || fail "Product host publishes surface activation instead of a Settings polling loop"
if grep -Eq 'events[.](subscribe|unsubscribe)' "$application" "$model" "$entrypoint"; then
  fail "Settings does not invent an events.subscribe path"
fi
pass "Settings isolates superseded and stale request generations"
pass "Settings rereads after a successful writer and when the surface becomes visible"

grep -Fq 'readonly property var productProfile: host && host.productProfile ? host.productProfile : null' "$application" \
  || fail "Settings reads the standalone host SemanticProfile"
grep -Fq 'semanticProfile: root.productProfile' "$application" \
  || fail "Settings chrome verbs consume the host SemanticProfile"
grep -Fq 'focusable: true' "$application" || fail "Settings controls participate in keyboard focus"
grep -Fq 'Keys.onPressed:' "$application" || fail "Settings exposes a keyboard refresh path"
grep -Fq 'Accessible.role:' "$application" || fail "Settings state surfaces declare accessibility roles"
grep -Fq 'Accessible.role:' "$card" || fail "Settings resource cards declare accessibility roles"
grep -Fq 'Tokens.accessibility.highContrast' "$application" || fail "Settings honors high-contrast border semantics"
grep -Fq 'Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff' "$application" \
  || fail "Settings prevents horizontal content clipping"
grep -Fq 'maximumLineCount:' "$application" || fail "Settings bounds long route and provider text"
grep -Fq 'maximumLineCount:' "$card" || fail "Settings bounds long resource text"
pass "Settings is responsive, keyboard reachable, accessible, and string bounded"

grep -Fq 'SettingsModel.coverageBadge' "$application" \
  || fail "Settings coverage badge is route-honest rather than always CHANGES UNAVAILABLE"
grep -A4 'SettingsModel.coverageBadge' "$application" | grep -Fq 'semanticProfile: root.productProfile' \
  || fail "Settings coverage badge localizes PARTIAL LIVE CONTROL / CHANGES UNAVAILABLE through Semantics.text"
grep -Fq 'SettingsModel.declaredOpsHonesty' "$application" \
  || fail "Settings declared-ops copy covers every live writer route"
grep -Fq 'SettingsModel.authorityFooter' "$application" \
  || fail "Settings footer states the window mutation authority"
if grep -A3 'Declared provider operations' "$application" | grep -q 'settings.audio.overview'; then
  fail "Settings declared-ops honesty is no longer an audio-only ternary"
fi
if grep -Fq 'no direct commands, mutation, preflight, approval, or execution authority' "$application"; then
  fail "Settings footer no longer claims the mutating window has no mutation authority"
fi
pass "Settings coverage badge, declared ops, and footer match live writers"

if grep -Eiq 'typed (settings |domain )?writers remain phase 5' "$ROOT/plans/project-ultimate.md" "$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"; then
  fail "plan and PARITY no longer blanket typed writers as remaining Phase 5"
fi
if grep -Fq 'Recycle is Phase 6' "$ROOT/plans/project-ultimate.md"; then
  fail "Current position no longer frames Recycle as Phase-6-only while Files trash/restore UI exists"
fi
if grep -Fq 'and cannot set one' "$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"; then
  fail "PARITY Default Programs notes no longer deny the live browser writer"
fi
pass "Plan and PARITY writer fences match the live Settings and Files surfaces"

grep -Fq 'Ui.SettingsHostedPanel' "$application" \
  || fail "Settings hosts existing panel pages inside its chrome"
grep -Fq 'LIVE PANEL' "$application" \
  || fail "Settings labels hosted pages as live panels"
grep -A4 'LIVE PANEL' "$application" | grep -Fq 'semanticProfile: root.productProfile' \
  || fail "Settings LIVE PANEL badge consumes Semantics.text"
grep -Fq 'Semantics.text(root.productProfile, "Exact resource")' "$application" \
  || fail "Settings Exact resource prefix consumes Semantics.text"
grep -Fq 'Semantics.text(root.productProfile, "Display bound reached at")' "$application" \
  || fail "Settings display-bound notice consumes Semantics.text"
grep -Fq 'hostedPanel(' "$model" \
  || fail "Settings owns a closed hosted-panel map"
if grep -Fq 'plugins/' "$application"; then
  fail "Settings application QML does not hard-code plugin paths"
fi
if grep -Fq 'plugins/panels/monitor/Panel.qml' "$model"; then
  fail "Settings Display map does not host the Process monitor panel"
fi
if grep -Fq 'plugins/panels/audio/Panel.qml' "$model"; then
  fail "Settings Sound map does not host the Process audio panel"
fi
if grep -Fq 'plugins/panels/network/Panel.qml' "$model"; then
  fail "Settings Network map does not host the Process nmcli panel"
fi
if grep -Fq 'plugins/panels/bluetooth/Panel.qml' "$model"; then
  fail "Settings Bluetooth map does not host the Process bluetoothctl panel"
fi
if grep -Fq 'plugins/panels/power/Panel.qml' "$model"; then
  fail "Settings Power map does not host the Process power panel"
fi
pass "Settings Personalization hosts a picker; Display, Sound, Network, Bluetooth, and Power read Fabric"

for panel in monitor audio network bluetooth power; do
  grep -Fq 'property bool embedMode: false' "$ROOT/shell/plugins/panels/$panel/Panel.qml" \
    || fail "$panel panel can embed inside Settings chrome"
  grep -Fq 'id: embedHost' "$ROOT/shell/plugins/panels/$panel/Panel.qml" \
    || fail "$panel panel reparents its page into Settings"
done
pass "Existing panels support Settings embed mode"

stub="$ROOT/shell/plugins/ultimate-settings/Settings.qml"
if grep -Fq 'omarchy.monitor' "$stub"; then
  fail "Settings stub no longer toggles the Display overlay"
fi
grep -Fq 'org.omarchy.Settings' "$stub" \
  || fail "Settings stub launches the Settings window"
pass "Settings overlay stub launches the Settings window"
