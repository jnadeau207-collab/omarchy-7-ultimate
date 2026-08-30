const path = require('path')

const root = path.resolve(__dirname, '..', '..')
const Files = require(path.join(root, 'shell/apps/ultimate-files/FilesModel.js'))
const Software = require(path.join(root, 'shell/apps/ultimate-software/SoftwareModel.js'))
const Compatibility = require(path.join(root, 'shell/apps/ultimate-compatibility/CompatibilityModel.js'))

let assertions = 0
function assert(condition, message) {
  assertions++
  if (!condition) throw new Error(message)
}
function equal(actual, expected, message) {
  assert(JSON.stringify(actual) === JSON.stringify(expected), `${message}\nexpected ${JSON.stringify(expected)}\nactual   ${JSON.stringify(actual)}`)
}
function throws(call, message) {
  let failed = false
  try { call() } catch (_) { failed = true }
  assert(failed, message)
}

const revA = `sha256.${'a'.repeat(64)}`
const revB = `sha256.${'b'.repeat(64)}`
const digestA = `sha256:${'a'.repeat(64)}`
const digestB = `sha256:${'b'.repeat(64)}`

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

function catalog(provider, actions, state = 'available') {
  return {
    providers: [{
      manifest: {
        schemaVersion: 'v0',
        provider,
        providerVersion: 'v0',
        minFabricProtocol: 0,
        maxFabricProtocol: 0,
        capabilities: Object.values(actions).map(action => action.capability),
        actions
      },
      fingerprint: 'a'.repeat(64),
      generation: 4,
      registrationOrder: 1,
      state,
      detail: state === 'degraded' ? 'Plan-only contract seed.' : '',
      registeredAt: 1,
      changedAt: 2
    }]
  }
}

const fileActions = {
  inspect: readAction('files.inspect'),
  browse: readAction('files.browse'),
  search: readAction('files.search'),
  recent: readAction('files.recent.read')
}
const softwareActions = {
  'catalog.search': readAction('packages.catalog.inspect'),
  'inventory.inspect': readAction('packages.inventory.inspect'),
  'adoption.inspect': readAction('packages.adoption.inspect'),
  'operations.inspect': readAction('packages.operations.inspect')
}
const compatibilityActions = {
  'route.decide': readAction('compatibility.route.decide'),
  'deployments.inspect': readAction('compatibility.deployments.inspect')
}

equal(Files.requestParameters(Files.baseState('files.desktop', {}, 'loading')), {
  provider: 'files.provider', action: 'browse',
  arguments: { locationId: 'files.location.desktop', relativePath: '', includeHidden: false, limit: 96 }
}, 'Files desktop constructs the exact closed browse request')
equal(Files.requestParameters(Files.baseState('files.search', { query: 'quarterly report' }, 'loading')), {
  provider: 'files.provider', action: 'search',
  arguments: { query: 'quarterly report', locationIds: [], includeHidden: false, limit: 96 }
}, 'Files search constructs a bounded typed request')
throws(() => Files.normalizedSelection(Files.queryForRoute('files.search'), { query: 'x'.repeat(121) }), 'Files rejects overlong search text')
throws(() => Files.normalizedSelection(Files.queryForRoute('files.overview'), { entityType: 'location' }), 'Files rejects half-bound entity links')
assert(Files.catalogEntry(catalog('files.provider', fileActions), Files.queryForRoute('files.recent')).entry.manifest.provider === 'files.provider', 'Files admits the exact provider manifest')
assert(Files.catalogEntry(catalog('files.provider', { ...fileActions, recent: { ...fileActions.recent, mode: 'operation' } }), Files.queryForRoute('files.recent')).error, 'Files rejects a mutating read-action substitution')

const availability = { state: 'available', read: true, operation: false, reasons: [] }
const fileReadState = Files.baseState('files.search', { entityType: 'entry', entityId: 'files.entry.readme' }, 'loading')
fileReadState.providerEntry = catalog('files.provider', fileActions).providers[0]
const fileResult = {
  provider: 'files.provider', providerVersion: 'v0', generation: 4, action: 'search', capability: 'files.search', observedAt: 20,
  value: {
    schemaVersion: 'v0', provider: 'files.provider', providerVersion: 'v0', action: 'search', availability, revision: revA, truncated: false,
    entries: [{ id: 'files.entry.readme', locationId: 'files.location.desktop', parentId: null, name: 'README.md', relativePath: 'README.md', kind: 'file', sizeBytes: 42, modifiedNs: 1, mimeType: 'text/plain', hidden: false, writable: true, identity: revB, symlinkTargetState: null, trash: null }]
  }
}
const normalizedFiles = Files.normalizeResult(fileReadState, fileResult)
assert(!normalizedFiles.error && normalizedFiles.records.length === 1, 'Files accepts exact current-generation query results')
assert(normalizedFiles.records[0].details.some(field => field.label === 'Relative path' && field.value === 'README.md'), 'Files preserves bounded file provenance fields')
assert(Files.normalizeResult(fileReadState, { ...fileResult, generation: 3 }).error, 'Files rejects obsolete provider generations')

const picturesControllerStates = []
let picturesRequest = 0
const picturesController = Files.createController({
  send() { return `pictures-${++picturesRequest}` },
  cancel() { return true },
  onState(state) { picturesControllerStates.push(state) }
})
picturesController.activate('files.pictures', {})
picturesController.setConnected(true)
picturesController.receiveResult('pictures-1', catalog('files.provider', fileActions, 'degraded'))
picturesController.receiveResult('pictures-2', {
  provider: 'files.provider', providerVersion: 'v0', generation: 4, action: 'browse', capability: 'files.browse', observedAt: 21,
  value: {
    schemaVersion: 'v0', provider: 'files.provider', providerVersion: 'v0', action: 'browse',
    availability: { state: 'available', read: true, operation: false, reasons: [] },
    revision: revA, truncated: false,
    entries: [{ id: 'files.entry.sunset', locationId: 'files.location.pictures', parentId: null, name: 'sunset.png', relativePath: 'sunset.png', kind: 'file', sizeBytes: 8, modifiedNs: 1, mimeType: 'image/png', hidden: false, writable: true, identity: revB, symlinkTargetState: null, trash: null }]
  }
})
assert(picturesController.state.phase === 'available', 'Pictures browse stays available when only the workspace catalog is degraded')
assert(picturesController.state.records.length === 1 && picturesController.state.records[0].title === 'sunset.png', 'Pictures browse keeps the location entries')

const thisPcState = Files.baseState('files.this-pc', {}, 'loading')
thisPcState.providerEntry = catalog('files.provider', fileActions, 'degraded').providers[0]
const thisPcResult = {
  provider: 'files.provider', providerVersion: 'v0', generation: 4, action: 'inspect', capability: 'files.inspect', observedAt: 22,
  value: {
    schemaVersion: 'v0', provider: 'files.provider', providerVersion: 'v0', action: 'inspect',
    availability: { state: 'degraded', read: true, operation: false, reasons: [] },
    revision: revA,
    state: {
      schemaVersion: 'v0', workspaceId: 'files.workspace.primary',
      locations: [
        { id: 'files.location.this-pc', kind: 'this-pc', label: 'This PC', state: 'available', writable: false, rootToken: revA, reason: null },
        { id: 'files.location.home', kind: 'home', label: 'Home', state: 'available', writable: true, rootToken: revA, reason: null },
        { id: 'files.location.desktop', kind: 'desktop', label: 'Desktop', state: 'available', writable: true, rootToken: revA, reason: null },
        { id: 'files.location.pictures', kind: 'pictures', label: 'Pictures', state: 'available', writable: true, rootToken: revA, reason: null }
      ],
      entries: [
        { id: 'files.entry.bashrc', locationId: 'files.location.home', parentId: null, name: '.bashrc', relativePath: '.bashrc', kind: 'file', sizeBytes: 12, modifiedNs: 1, mimeType: 'text/plain', hidden: true, writable: true, identity: revB, symlinkTargetState: null, trash: null },
        { id: 'files.entry.note', locationId: 'files.location.desktop', parentId: null, name: 'note.txt', relativePath: 'note.txt', kind: 'file', sizeBytes: 4, modifiedNs: 1, mimeType: 'text/plain', hidden: false, writable: true, identity: revB, symlinkTargetState: null, trash: null }
      ],
      mounts: [],
      recent: []
    }
  }
}
const normalizedThisPc = Files.normalizeResult(thisPcState, thisPcResult)
assert(!normalizedThisPc.error, 'This PC accepts a degraded inspect inventory')
assert(normalizedThisPc.records.some(record => record.kind === 'entry' && record.title === '.bashrc'), 'This PC shows Home records from the inspect inventory')
assert(normalizedThisPc.records.some(record => record.kind === 'entry' && record.title === 'note.txt'), 'This PC shows Desktop records from the inspect inventory')
assert(normalizedThisPc.records.some(record => record.kind === 'location' && record.title === 'Home' && record.details.some(field => field.label === 'Entries' && field.value === '1')), 'This PC Home card reports its remaining inventory count')
assert(normalizedThisPc.records.findIndex(record => record.kind === 'location' && record.title === 'Home') === 0, 'This PC lists the Home location before later places')
let thisPcRequest = 0
const thisPcAccepted = Files.createController({
  send() { return `this-pc-${++thisPcRequest}` },
  cancel() { return true },
  onState() {}
})
thisPcAccepted.activate('files.this-pc', {})
thisPcAccepted.setConnected(true)
thisPcAccepted.receiveResult('this-pc-1', catalog('files.provider', fileActions, 'degraded'))
thisPcAccepted.receiveResult('this-pc-2', thisPcResult)
assert(thisPcAccepted.state.phase === 'available', 'This PC reports the virtual this-pc location, not workspace degradation')
assert(thisPcAccepted.state.availability === 'available', 'This PC page availability stays location-local')
assert(thisPcResult.value.availability.state === 'degraded', 'This PC inspect payload keeps the workspace degraded')
let homeRequest = 0
const homeAccepted = Files.createController({
  send() { return `home-${++homeRequest}` },
  cancel() { return true },
  onState() {}
})
homeAccepted.activate('files.overview', {})
homeAccepted.setConnected(true)
homeAccepted.receiveResult('home-1', catalog('files.provider', fileActions, 'degraded'))
homeAccepted.receiveResult('home-2', { ...thisPcResult, action: 'inspect' })
assert(homeAccepted.state.phase === 'degraded', 'Files Home keeps workspace inspect degradation')
assert(Files.normalizeResult(fileReadState, { ...fileResult, value: { ...fileResult.value, shell: 'rm -rf /' } }).error, 'Files rejects extra response fields')

equal(Software.requestParameters(Software.baseState('software.catalog', { query: 'editor' }, 'loading')), {
  provider: 'packages.provider', action: 'catalog.search', arguments: { query: 'editor', sourceTypes: [] }
}, 'Software catalog constructs the exact cross-source search request')
equal(Software.requestParameters(Software.baseState('software.installed', {}, 'loading')), {
  provider: 'packages.provider', action: 'inventory.inspect', arguments: { includeUnmanaged: true }
}, 'Software installed route requests explicit unmanaged inventory')
throws(() => Software.normalizedSelection(Software.queryForRoute('software.adoption'), { entityType: 'software', entityId: 'software.test' }), 'Software rejects entity selectors on the adoption aggregate')
assert(Software.catalogEntry(catalog('packages.provider', softwareActions, 'degraded'), Software.queryForRoute('software.catalog')).entry.state === 'degraded', 'Software admits readable degraded contract-seed providers')

const softwareState = Software.baseState('software.catalog', { entityType: 'software', entityId: 'software.curated.neovim' }, 'loading')
softwareState.providerEntry = catalog('packages.provider', softwareActions, 'degraded').providers[0]
const softwareResult = {
  provider: 'packages.provider', providerVersion: 'v0', generation: 4, action: 'catalog.search', capability: 'packages.catalog.inspect', observedAt: 21,
  value: {
    schemaVersion: 'v0', provider: 'packages.provider', assurance: 'contract-seed', revision: revA,
    entries: [{
      id: 'software.curated.neovim', sourceId: 'source.omarchy.curated', sourceType: 'curated', packageRef: 'neovim', displayName: 'Neovim', summary: 'Curated editor', version: '0.11', architecture: 'x86_64', keywords: ['editor'],
      provenance: { assurance: 'contract-seed', publisher: 'Omarchy', origin: 'https://example.invalid/neovim', artifactDigest: digestA, reviewRevision: digestB, trustLevel: 'core', signature: { status: 'declared', keyId: 'omarchy.release' } },
      install: { requiredBytes: 1024, permissions: [], conflicts: [] }
    }]
  }
}
const normalizedSoftware = Software.normalizeResult(softwareState, softwareResult)
assert(!normalizedSoftware.error && normalizedSoftware.records[0].status === 'contract-seed', 'Software surfaces seed assurance without upgrading it')
assert(normalizedSoftware.records[0].details.some(field => field.label === 'Signature' && field.value === 'declared'), 'Software surfaces signature evidence')
assert(Software.normalizeResult(softwareState, { ...softwareResult, value: { ...softwareResult.value, entries: [{ ...softwareResult.value.entries[0], provenance: { ...softwareResult.value.entries[0].provenance, origin: 'file:///tmp/pkg' } }] } }).error, 'Software rejects unsafe provenance origins')

const validRequest = {
  id: 'workload.reader', name: 'Reader', workloadType: 'windows-app', architecture: 'x86_64',
  artifact: { kind: 'windows-executable', origin: 'https://example.invalid/reader.exe', digest: digestA },
  permissions: ['filesystem-home', 'network'],
  constraints: { requiresKernelDriver: false, requiresAdmin: false, antiCheat: 'none', offlineRequired: false, acceptsBrowser: false }
}
const validHost = {
  architecture: 'x86_64', virtualizationAvailable: true, protonAvailable: false, isolationAvailable: true, browserAvailable: true,
  availableRuntimes: ['native', 'browser', 'wine'], memoryMiB: 8192, diskMiB: 65536
}
const normalizedInput = Compatibility.normalizeDecisionInput(validRequest, validHost)
equal(normalizedInput.request.permissions, ['network', 'filesystem-home'], 'Compatibility canonicalizes permission order')
equal(normalizedInput.host.availableRuntimes, ['wine', 'browser', 'native'], 'Compatibility canonicalizes runtime order')
throws(() => Compatibility.normalizeDecisionInput({ ...validRequest, command: 'wine setup.exe' }, validHost), 'Compatibility rejects command-bearing request fields')
throws(() => Compatibility.normalizeDecisionInput({ ...validRequest, artifact: { ...validRequest.artifact, digest: null } }, validHost), 'Compatibility requires pinned executable artifacts')
throws(() => Compatibility.normalizeDecisionInput(validRequest, { ...validHost, availableRuntimes: ['wine', 'wine'] }), 'Compatibility rejects duplicate runtime declarations')

assert(Compatibility.catalogEntry(catalog('compatibility.provider', compatibilityActions, 'degraded'), Compatibility.queryForRoute('compatibility.overview')).entry.state === 'degraded', 'Compatibility overview requires both code-owned read actions')
assert(Compatibility.catalogEntry(catalog('compatibility.provider', { 'route.decide': compatibilityActions['route.decide'] }), Compatibility.queryForRoute('compatibility.overview')).error, 'Compatibility overview rejects incomplete provider manifests')

const compatibilityState = Compatibility.baseState('compatibility.decide', {}, 'loading')
compatibilityState.providerEntry = catalog('compatibility.provider', compatibilityActions, 'degraded').providers[0]
const considered = Compatibility.ROUTE_ORDER.map((route, index) => ({ route, status: index === 5 ? 'eligible' : 'ineligible', reason: index === 5 ? 'Use an isolated VM.' : 'Declared constraints reject this route.' }))
const decisionResult = {
  provider: 'compatibility.provider', providerVersion: 'v0', generation: 4, action: 'route.decide', capability: 'compatibility.route.decide', observedAt: 22,
  value: { schemaVersion: 'v0', provider: 'compatibility.provider', decisionId: 'compatibility.decision.reader', recipeRevision: revA, recipeAssurance: 'contract-seed', eligibility: 'supported', selectedRoute: 'vm', recipeId: null, reasonCode: 'compatibility.vm', explanation: 'Use an isolated Windows VM.', requiredPermissions: ['filesystem-home'], considered, revision: revB }
}
const normalizedDecision = Compatibility.normalizeResult(compatibilityState, decisionResult)
assert(!normalizedDecision.error && normalizedDecision.records.length === 7, 'Compatibility surfaces the decision and all six canonical routes')
assert(normalizedDecision.records[0].details.some(field => field.label === 'Input provenance' && field.value.includes('not measured')), 'Compatibility labels user-declared host provenance')
const unsupportedResult = { ...decisionResult, value: { ...decisionResult.value, eligibility: 'unsupported', selectedRoute: null, recipeId: null, reasonCode: 'compatibility.unsupported', explanation: 'No route is safe.', considered: considered.map(item => ({ ...item, status: 'ineligible' })) } }
assert(Compatibility.normalizeResult(compatibilityState, unsupportedResult).unsupported, 'Compatibility preserves explicit unsupported outcomes')
const reordered = considered.slice(); [reordered[0], reordered[1]] = [reordered[1], reordered[0]]
assert(Compatibility.normalizeResult(compatibilityState, { ...decisionResult, value: { ...decisionResult.value, considered: reordered } }).error, 'Compatibility rejects reordered route evidence')

function exerciseIsolation(Model, defaultRoute, nextRoute, providerCatalog, readResult) {
  let nextId = 0
  const sent = [], cancelled = [], states = []
  const controller = Model.createController({
    send(method, parameters) { const id = `request-${++nextId}`; sent.push({ id, method, parameters }); return id },
    cancel(id) { cancelled.push(id); return true },
    onState(state) { states.push(state) }
  })
  controller.activate(defaultRoute, {})
  controller.setConnected(true)
  assert(sent[0].method === 'provider.catalog', `${defaultRoute} connects through provider.catalog first`)
  controller.receiveResult(sent[0].id, providerCatalog)
  assert(sent[1].method === 'provider.read', `${defaultRoute} follows with its exact provider.read`)
  controller.activate(nextRoute, {})
  assert(cancelled.includes(sent[1].id), `${defaultRoute} cancels the superseded correlation`)
  assert(controller.receiveResult(sent[1].id, readResult) === false, `${defaultRoute} ignores a stale prior-route response`)
  controller.setConnected(false)
  assert(controller.state.phase === 'offline' && controller.state.records.length === 0, `${defaultRoute} clears records on disconnect`)
}

exerciseIsolation(Files, 'files.desktop', 'files.recent', catalog('files.provider', fileActions), fileResult)
const inventoryState = Software.baseState('software.installed', {}, 'loading'); inventoryState.providerEntry = catalog('packages.provider', softwareActions, 'degraded').providers[0]
const inventoryResult = { provider: 'packages.provider', providerVersion: 'v0', generation: 4, action: 'inventory.inspect', capability: 'packages.inventory.inspect', observedAt: 30, value: { schemaVersion: 'v0', provider: 'packages.provider', revision: revA, items: [] } }
exerciseIsolation(Software, 'software.catalog', 'software.installed', catalog('packages.provider', softwareActions, 'degraded'), softwareResult)

console.log(`domain product model assertions: ${assertions}`)
