var CATALOG_METHOD = "provider.catalog"
var READ_METHOD = "provider.read"
var PROVIDER_ID = "packages.provider"
var MAX_CATALOG_ENTRIES = 128
var MAX_SOURCE_RECORDS = 4096
var MAX_VISIBLE_RECORDS = 96
var MAX_TEXT = 480
var SOURCE_TYPES = ["curated", "signed-repo", "flatpak", "reviewed-aur", "appimage", "web-app"]

var ROUTES = [
  { routeId: "software.catalog", action: "catalog.search", capability: "packages.catalog.inspect", kind: "catalog" },
  { routeId: "software.installed", action: "inventory.inspect", capability: "packages.inventory.inspect", kind: "inventory" },
  { routeId: "software.adoption", action: "adoption.inspect", capability: "packages.adoption.inspect", kind: "adoption" },
  { routeId: "software.history", action: "operations.inspect", capability: "packages.operations.inspect", kind: "operations" }
]

function isObject(value) { return value !== null && typeof value === "object" && !Array.isArray(value) }
function hasOwn(value, key) { return isObject(value) && Object.prototype.hasOwnProperty.call(value, key) }
function exactKeys(value, expected) {
  if (!isObject(value)) return false
  var actual = Object.keys(value).sort(), wanted = expected.slice().sort()
  if (actual.length !== wanted.length) return false
  for (var i = 0; i < actual.length; i++) if (actual[i] !== wanted[i]) return false
  return true
}
function stableId(value) { return typeof value === "string" && value.length >= 1 && value.length <= 160 && /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/.test(value) }
function shaRevision(value) { return typeof value === "string" && /^sha256\.[0-9a-f]{64}$/.test(value) }
function digest(value) { return typeof value === "string" && /^sha256:[0-9a-f]{64}$/.test(value) }
function clippedText(value, maximum) {
  var limit = typeof maximum === "number" ? maximum : MAX_TEXT
  var text = value === null || value === undefined ? "" : String(value)
  text = text.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
  return text.length <= limit ? text : text.slice(0, Math.max(1, limit - 1)) + "\u2026"
}
function copyArray(value) { return Array.isArray(value) ? value.slice() : [] }
function cloneState(state) {
  var result = {}, keys = Object.keys(state || {})
  for (var i = 0; i < keys.length; i++) result[keys[i]] = state[keys[i]]
  result.records = copyArray(state && state.records)
  return result
}
function queryForRoute(routeId) {
  var id = String(routeId || "")
  for (var i = 0; i < ROUTES.length; i++) if (ROUTES[i].routeId === id) return ROUTES[i]
  return null
}
function structuredError(code, title, explanation, detail) {
  return { code: clippedText(code || "software.failed", 160), title: clippedText(title || "Software read failed", 160), explanation: clippedText(explanation || "Fabric did not return usable Software Center state.", 1000), detail: clippedText(detail || "", MAX_TEXT), retryable: true, changeState: "none", recoveryActions: ["provider.refresh"] }
}
function responseError(detail) { return structuredError("software.invalid-response", "Software Center rejected provider state", "Fabric returned data outside the closed Software Center read contract.", detail) }
function phaseForError(error) {
  var code = String(error && error.code || "")
  if (code === "rpc.cancelled") return "interrupted"
  if (code === "rpc.timeout" || code === "provider.changed-during-read") return "stale"
  if (code === "daemon.disconnected" || code === "daemon.socket-error") return "offline"
  if (code === "client.method-denied" || code.indexOf("access.") === 0 || code.indexOf("permission.") === 0 || code.indexOf("policy.") === 0) return "denied"
  if (code === "provider.unavailable" || code === "provider.incompatible-version") return "unavailable"
  return "failed"
}
function normalizedSelection(query, argumentsValue) {
  var args = isObject(argumentsValue) ? argumentsValue : {}
  var allowed = query && query.kind === "catalog" ? { query: true, entityType: true, entityId: true }
    : query && (query.kind === "inventory" || query.kind === "operations") ? { entityType: true, entityId: true } : {}
  var names = Object.keys(args)
  for (var i = 0; i < names.length; i++) if (!allowed[names[i]]) throw new Error("The Software Center route contains an unsupported argument.")
  var entityType = hasOwn(args, "entityType") ? String(args.entityType || "") : ""
  var entityId = hasOwn(args, "entityId") ? String(args.entityId || "") : ""
  if ((entityType === "") !== (entityId === "")) throw new Error("Software entity type and identity must be supplied together.")
  if (entityId !== "" && !stableId(entityId)) throw new Error("The Software entity identity is invalid.")
  var expected = query && query.kind === "catalog" ? "software" : query && query.kind === "inventory" ? "installation" : query && query.kind === "operations" ? "operation" : ""
  if (entityType !== "" && entityType !== expected) throw new Error("The Software entity type does not match this route.")
  var search = hasOwn(args, "query") ? String(args.query) : ""
  if (search.length > 120 || /[\u0000-\u001f\u007f]/.test(search)) throw new Error("The Software catalog query is invalid.")
  return { entityType: entityType, entityId: entityId, searchQuery: search }
}
function routeArguments(state) {
  var result = {}
  if (state.query && state.query.kind === "catalog" && state.searchQuery !== "") result.query = state.searchQuery
  if (state.entityType !== "") { result.entityType = state.entityType; result.entityId = state.entityId }
  return result
}
function baseState(routeId, argumentsValue, phase) {
  var query = queryForRoute(routeId), selection = { entityType: "", entityId: "", searchQuery: "" }, error = null
  if (!query) error = responseError("The route is not in the closed Software Center map.")
  else { try { selection = normalizedSelection(query, argumentsValue) } catch (problem) { error = responseError(String(problem)) } }
  return { routeId: String(routeId || ""), query: query, entityType: selection.entityType, entityId: selection.entityId, searchQuery: selection.searchQuery, phase: error ? "failed" : String(phase || "offline"), requestId: "", providerEntry: null, providerGeneration: 0, records: [], totalRecords: 0, clipped: false, selectedMissing: false, assurance: "unknown", revision: "", observedAt: null, error: error }
}
function failureState(previous, errorValue) {
  var next = cloneState(previous)
  var error = isObject(errorValue) ? errorValue : structuredError("software.failed", "Software read failed", String(errorValue || "Unknown Fabric failure."), "")
  next.phase = phaseForError(error); next.requestId = ""; next.records = []; next.totalRecords = 0; next.clipped = false; next.selectedMissing = false; next.observedAt = null; next.error = error
  return next
}
function validAction(action, query) {
  return exactKeys(action, ["capability", "mode", "risk", "effects", "arguments", "result", "preflight", "state", "supportsRollback", "supportsCancellation"]) && action.capability === query.capability && action.mode === "read" && action.risk === "read-only" && Array.isArray(action.effects) && action.effects.length === 0 && isObject(action.arguments) && isObject(action.result) && action.preflight === null && action.state === null && action.supportsRollback === false && action.supportsCancellation === false
}
function catalogEntry(response, query) {
  if (!exactKeys(response, ["providers"]) || !Array.isArray(response.providers) || response.providers.length > MAX_CATALOG_ENTRIES) return { error: "The provider catalog envelope is invalid." }
  var found = null
  for (var i = 0; i < response.providers.length; i++) {
    var entry = response.providers[i]
    if (!exactKeys(entry, ["manifest", "fingerprint", "generation", "registrationOrder", "state", "detail", "registeredAt", "changedAt"]) || !isObject(entry.manifest)) return { error: "A provider catalog entry has an unexpected field set." }
    if (entry.manifest.provider === PROVIDER_ID) { if (found) return { error: "The provider catalog repeats packages.provider." }; found = entry }
  }
  if (!found) return { missing: true }
  var manifest = found.manifest
  if (!exactKeys(manifest, ["schemaVersion", "provider", "providerVersion", "minFabricProtocol", "maxFabricProtocol", "capabilities", "actions"]) || manifest.schemaVersion !== "v0" || manifest.provider !== PROVIDER_ID || manifest.providerVersion !== "v0" || !Number.isInteger(manifest.minFabricProtocol) || !Number.isInteger(manifest.maxFabricProtocol) || !Array.isArray(manifest.capabilities) || manifest.capabilities.length < 1 || manifest.capabilities.length > 128 || !isObject(manifest.actions) || !Number.isInteger(found.generation) || found.generation < 1 || !/^[0-9a-f]{64}$/.test(String(found.fingerprint || "")) || !Number.isInteger(found.registrationOrder) || found.registrationOrder < 1 || typeof found.detail !== "string" || found.detail.length > 500 || typeof found.registeredAt !== "number" || !isFinite(found.registeredAt) || found.registeredAt < 0 || typeof found.changedAt !== "number" || !isFinite(found.changedAt) || found.changedAt < 0 || ["available", "degraded", "unavailable", "incompatible"].indexOf(found.state) < 0) return { error: "The packages.provider catalog identity is invalid." }
  if (!validAction(manifest.actions[query.action], query)) return { error: "The selected Software Center read action does not match its closed manifest contract." }
  return { entry: found }
}
function requestParameters(state) {
  var argumentsValue = {}
  if (state.query.kind === "catalog") argumentsValue = { query: state.searchQuery, sourceTypes: [] }
  else if (state.query.kind === "inventory") argumentsValue = { includeUnmanaged: true }
  return { provider: PROVIDER_ID, action: state.query.action, arguments: argumentsValue }
}
function detail(label, value) { return { label: label, value: clippedText(value === null || value === undefined || value === "" ? "Not reported" : value, MAX_TEXT) } }
function boundedString(value, minimum, maximum) { return typeof value === "string" && value.length >= minimum && value.length <= maximum && !/[\u0000-\u001f\u007f]/.test(value) }
function uniqueStrings(value, maximum, validator) {
  if (!Array.isArray(value) || value.length > maximum) return false
  for (var i = 0; i < value.length; i++) if (!validator(value[i]) || value.indexOf(value[i]) !== i) return false
  return true
}
function safeHttps(value) { return boundedString(value, 1, 500) && /^https:\/\//.test(value) && !/\s/.test(value) }
function validProvenance(value) {
  return exactKeys(value, ["assurance", "publisher", "origin", "artifactDigest", "reviewRevision", "trustLevel", "signature"]) &&
    ["contract-seed", "release-verified"].indexOf(value.assurance) >= 0 && boundedString(value.publisher, 1, 160) && safeHttps(value.origin) &&
    digest(value.artifactDigest) && digest(value.reviewRevision) && ["core", "signed", "reviewed", "sandboxed"].indexOf(value.trustLevel) >= 0 &&
    isObject(value.signature) && exactKeys(value.signature, ["status", "keyId"]) &&
    ["declared", "verified", "reviewed", "not-applicable"].indexOf(value.signature.status) >= 0 &&
    (value.signature.keyId === null || stableId(value.signature.keyId))
}
function catalogRecord(item, index) {
  if (!exactKeys(item, ["id", "sourceId", "sourceType", "packageRef", "displayName", "summary", "version", "architecture", "keywords", "provenance", "install"]) || !stableId(item.id) || !stableId(item.sourceId) || SOURCE_TYPES.indexOf(item.sourceType) < 0 || !boundedString(item.packageRef, 1, 300) || !boundedString(item.displayName, 1, 160) || !boundedString(item.summary, 1, 500) || !boundedString(item.version, 1, 100) || ["any", "x86_64", "aarch64"].indexOf(item.architecture) < 0 || !uniqueStrings(item.keywords, 20, function(value) { return boundedString(value, 1, 80) }) || !validProvenance(item.provenance) || !isObject(item.install) || !exactKeys(item.install, ["requiredBytes", "permissions", "conflicts"]) || !Number.isSafeInteger(item.install.requiredBytes) || item.install.requiredBytes < 0 || item.install.requiredBytes > 1099511627776 || !uniqueStrings(item.install.permissions, 32, function(value) { return ["network", "audio", "camera", "microphone", "notifications", "filesystem-home", "filesystem-removable", "devices", "session"].indexOf(value) >= 0 }) || !uniqueStrings(item.install.conflicts, 32, stableId)) return null
  var provenance = item.provenance
  return { id: item.id, kind: "software", title: clippedText(item.displayName, 240), subtitle: clippedText(item.summary, 500), status: provenance.assurance, tone: provenance.assurance === "release-verified" ? "success" : "warning", details: [detail("Version", item.version), detail("Source", item.sourceType), detail("Package", item.packageRef), detail("Publisher", provenance.publisher), detail("Origin", provenance.origin), detail("Trust", provenance.trustLevel), detail("Signature", provenance.signature.status), detail("Review revision", provenance.reviewRevision), detail("Artifact digest", provenance.artifactDigest), detail("Required bytes", item.install.requiredBytes), detail("Permissions", item.install.permissions.join(", ") || "None")], order: index }
}
function inventoryRecord(item, index) {
  if (!exactKeys(item, ["id", "catalogId", "sourceType", "packageRef", "installedVersion", "artifactDigest", "adopted", "state", "configPaths", "dataPaths"]) || !stableId(item.id) || !stableId(item.catalogId) || SOURCE_TYPES.indexOf(item.sourceType) < 0 || !boundedString(item.packageRef, 1, 300) || !boundedString(item.installedVersion, 1, 100) || !digest(item.artifactDigest) || typeof item.adopted !== "boolean" || ["installed", "partial", "broken", "foreign"].indexOf(item.state) < 0 || !uniqueStrings(item.configPaths, 64, function(value) { return boundedString(value, 1, 500) && value.charAt(0) === "/" }) || !uniqueStrings(item.dataPaths, 64, function(value) { return boundedString(value, 1, 500) && value.charAt(0) === "/" })) return null
  return { id: item.id, kind: "installation", title: clippedText(item.packageRef, 240), subtitle: clippedText(item.catalogId, 240), status: item.state, tone: item.state === "installed" ? "success" : item.state === "partial" || item.state === "foreign" ? "warning" : "danger", details: [detail("Version", item.installedVersion), detail("Source", item.sourceType), detail("Adopted", item.adopted ? "Yes" : "No"), detail("Artifact digest", item.artifactDigest), detail("Config paths", item.configPaths.join(", ") || "None"), detail("Data paths", item.dataPaths.join(", ") || "None")], order: index }
}
function adoptionRecord(item, index) {
  if (!exactKeys(item, ["installedId", "catalogId", "state", "reason"]) || !stableId(item.installedId) || (item.catalogId !== null && !stableId(item.catalogId)) || ["managed", "unmanaged", "adoptable", "conflict"].indexOf(item.state) < 0 || !boundedString(item.reason, 1, 500)) return null
  return { id: item.installedId, kind: "adoption", title: clippedText(item.installedId, 240), subtitle: clippedText(item.reason, 500), status: item.state, tone: item.state === "managed" ? "success" : item.state === "adoptable" ? "neutral" : item.state === "conflict" ? "danger" : "warning", details: [detail("Catalog identity", item.catalogId), detail("Classification", item.state)], order: index }
}
function operationRecord(item, index) {
  if (!exactKeys(item, ["operationId", "requestId", "action", "status", "checkpoints", "inventoryRevision", "revision", "error"]) || !stableId(item.operationId) || !stableId(item.requestId) || ["install", "remove", "adopt", "recover"].indexOf(item.action) < 0 || ["running", "succeeded", "failed", "cancelled", "needs-reconcile", "rolled-back"].indexOf(item.status) < 0 || !Array.isArray(item.checkpoints) || item.checkpoints.length > 5 || !shaRevision(item.inventoryRevision) || !shaRevision(item.revision) || (item.error !== null && !boundedString(item.error, 0, 1000))) return null
  var checkpointOrder = ["verify-provenance", "stage-payload", "apply", "validate", "commit"]
  for (var checkpointIndex = 0; checkpointIndex < item.checkpoints.length; checkpointIndex++) if (item.checkpoints[checkpointIndex] !== checkpointOrder[checkpointIndex]) return null
  return { id: item.operationId, kind: "operation", title: clippedText(item.action + " \u00b7 " + item.operationId, 240), subtitle: clippedText(item.error || item.requestId, 500), status: item.status, tone: item.status === "succeeded" ? "success" : item.status === "running" ? "neutral" : item.status === "needs-reconcile" || item.status === "failed" ? "danger" : "warning", details: [detail("Request", item.requestId), detail("Checkpoints", item.checkpoints.join(" \u2192 ") || "None"), detail("Inventory revision", item.inventoryRevision), detail("Operation revision", item.revision), detail("Error", item.error)], order: index }
}
function validateEnvelope(state, result) {
  if (!exactKeys(result, ["provider", "providerVersion", "generation", "action", "capability", "value", "observedAt"])) return "The provider result envelope has an unexpected field set."
  if (result.provider !== PROVIDER_ID || result.providerVersion !== "v0" || result.action !== state.query.action || result.capability !== state.query.capability) return "The provider result identity does not match this Software Center route."
  if (!Number.isInteger(result.generation) || result.generation !== state.providerEntry.generation || typeof result.observedAt !== "number" || !isFinite(result.observedAt) || result.observedAt < 0 || !isObject(result.value)) return "The provider result belongs to an invalid or obsolete generation."
  return ""
}
function normalizeResult(state, result) {
  var invalid = validateEnvelope(state, result)
  if (invalid !== "") return { error: invalid }
  var value = result.value, source = null, assurance = "unknown", revisionValue = ""
  if (state.query.kind === "catalog") {
    if (!exactKeys(value, ["schemaVersion", "provider", "assurance", "revision", "entries"]) || value.schemaVersion !== "v0" || value.provider !== PROVIDER_ID || ["contract-seed", "release-verified"].indexOf(value.assurance) < 0 || !shaRevision(value.revision) || !Array.isArray(value.entries) || value.entries.length > MAX_SOURCE_RECORDS) return { error: "The Software catalog payload is invalid." }
    source = value.entries; assurance = value.assurance; revisionValue = value.revision
  } else if (state.query.kind === "inventory") {
    if (!exactKeys(value, ["schemaVersion", "provider", "revision", "items"]) || value.schemaVersion !== "v0" || value.provider !== PROVIDER_ID || !shaRevision(value.revision) || !Array.isArray(value.items) || value.items.length > MAX_SOURCE_RECORDS) return { error: "The installed software payload is invalid." }
    source = value.items; revisionValue = value.revision
  } else if (state.query.kind === "adoption") {
    if (!exactKeys(value, ["schemaVersion", "provider", "revision", "items"]) || value.schemaVersion !== "v0" || value.provider !== PROVIDER_ID || !shaRevision(value.revision) || !Array.isArray(value.items) || value.items.length > MAX_SOURCE_RECORDS) return { error: "The Software adoption payload is invalid." }
    source = value.items; revisionValue = value.revision
  } else {
    if (!exactKeys(value, ["schemaVersion", "provider", "revision", "operations"]) || value.schemaVersion !== "v0" || value.provider !== PROVIDER_ID || !shaRevision(value.revision) || !Array.isArray(value.operations) || value.operations.length > MAX_SOURCE_RECORDS) return { error: "The Software operation-history payload is invalid." }
    source = value.operations; revisionValue = value.revision
  }
  var records = []
  for (var i = 0; i < source.length; i++) {
    var record = state.query.kind === "catalog" ? catalogRecord(source[i], i) : state.query.kind === "inventory" ? inventoryRecord(source[i], i) : state.query.kind === "adoption" ? adoptionRecord(source[i], i) : operationRecord(source[i], i)
    if (!record) return { error: "A Software Center record is invalid." }
    records.push(record)
  }
  var selectedMissing = false
  if (state.entityId !== "") {
    var selected = []
    for (var j = 0; j < records.length; j++) if (records[j].id === state.entityId && records[j].kind === state.entityType) selected.push(records[j])
    selectedMissing = selected.length === 0; records = selected
  }
  var clipped = records.length > MAX_VISIBLE_RECORDS
  if (clipped) records = records.slice(0, MAX_VISIBLE_RECORDS)
  return { records: records, totalRecords: source.length, clipped: clipped, selectedMissing: selectedMissing, assurance: assurance, revision: revisionValue, observedAt: result.observedAt }
}
function acceptedState(previous, result) {
  var normalized = normalizeResult(previous, result)
  if (normalized.error) return failureState(previous, responseError(normalized.error))
  var next = cloneState(previous)
  next.records = normalized.records; next.totalRecords = normalized.totalRecords; next.clipped = normalized.clipped; next.selectedMissing = normalized.selectedMissing; next.assurance = normalized.assurance; next.revision = normalized.revision; next.observedAt = normalized.observedAt; next.requestId = ""; next.error = null
  if (normalized.clipped) next.phase = "partial"
  else if (previous.providerEntry.state === "degraded" || normalized.assurance === "contract-seed") next.phase = "degraded"
  else if (normalized.records.length === 0) next.phase = "empty"
  else next.phase = "ready"
  return next
}
function Controller(options) {
  var configuration = options || {}
  this.send = typeof configuration.send === "function" ? configuration.send : function() { return "" }
  this.cancel = typeof configuration.cancel === "function" ? configuration.cancel : function() { return false }
  this.publish = typeof configuration.onState === "function" ? configuration.onState : function() {}
  this.connected = false; this.generation = 0; this.catalogResponse = null; this.pending = Object.create(null); this.activeRequestId = ""; this.sending = false; this.synchronousFailure = null; this.state = baseState("software.catalog", {}, "offline")
}
Controller.prototype._setState = function(state) { this.state = state; this.publish(cloneState(state)) }
Controller.prototype._cancelActive = function() { if (this.activeRequestId !== "") { delete this.pending[this.activeRequestId]; this.cancel(this.activeRequestId) }; this.activeRequestId = "" }
Controller.prototype._send = function(kind, method, params) {
  this.sending = true; this.synchronousFailure = null
  var id = String(this.send(method, params) || "")
  this.sending = false
  if (id === "") { this._setState(failureState(this.state, this.synchronousFailure || structuredError("software.request-rejected", "Software request was rejected", "The constrained Fabric client did not accept the read-only request.", method))); return false }
  this.activeRequestId = id; this.pending[id] = { kind: kind, generation: this.generation, routeId: this.state.routeId }
  var waiting = cloneState(this.state); waiting.requestId = id; waiting.phase = kind === "catalog" ? "catalog-loading" : "loading"; this._setState(waiting); return true
}
Controller.prototype._startRead = function() {
  var lookup = catalogEntry(this.catalogResponse, this.state.query)
  if (lookup.error) { this._setState(failureState(this.state, responseError(lookup.error))); return false }
  var prepared = cloneState(this.state)
  if (lookup.missing) { prepared.phase = "missing"; prepared.requestId = ""; this._setState(prepared); return false }
  prepared.providerEntry = lookup.entry; prepared.providerGeneration = lookup.entry.generation
  if (lookup.entry.state === "unavailable" || lookup.entry.state === "incompatible") { prepared.phase = "unavailable"; prepared.error = structuredError("provider.unavailable", "Software provider is unavailable", lookup.entry.detail || "No usable package backend is registered.", PROVIDER_ID); this._setState(prepared); return false }
  this._setState(prepared); return this._send("read", READ_METHOD, requestParameters(prepared))
}
Controller.prototype._refreshCatalog = function() { this.generation++; this._cancelActive(); this.pending = Object.create(null); this.catalogResponse = null; return this._send("catalog", CATALOG_METHOD, {}) }
Controller.prototype.setConnected = function(connected) {
  var value = connected === true
  if (value === this.connected) return false
  this.connected = value
  if (!value) { this.generation++; this._cancelActive(); this.pending = Object.create(null); this.catalogResponse = null; this._setState(baseState(this.state.routeId, routeArguments(this.state), "offline")); return true }
  return this._refreshCatalog()
}
Controller.prototype.activate = function(routeId, argumentsValue) {
  this.generation++; this._cancelActive(); this.pending = Object.create(null)
  var next = baseState(routeId, argumentsValue, this.connected ? "loading" : "offline"); this._setState(next)
  if (!this.connected || next.phase === "failed") return false
  if (this.catalogResponse) return this._startRead()
  return this._send("catalog", CATALOG_METHOD, {})
}
Controller.prototype.refresh = function() { return this.connected ? this._refreshCatalog() : false }
Controller.prototype.refreshWhenSurfaceVisible = function() {
  if (!this.connected) return false
  var phase = String(this.state && this.state.phase || "")
  if (phase === "catalog-loading" || phase === "loading" || phase === "offline") return false
  return this.refresh()
}
Controller.prototype.receiveResult = function(requestId, result) {
  var id = String(requestId || ""), ticket = this.pending[id]
  if (!ticket || id !== this.activeRequestId || ticket.generation !== this.generation || ticket.routeId !== this.state.routeId) return false
  delete this.pending[id]; this.activeRequestId = ""
  if (ticket.kind === "catalog") { var lookup = catalogEntry(result, this.state.query); if (lookup.error) { this._setState(failureState(this.state, responseError(lookup.error))); return true }; this.catalogResponse = result; this._startRead() } else this._setState(acceptedState(this.state, result))
  return true
}
Controller.prototype.receiveFailure = function(requestId, error) {
  var id = String(requestId || "")
  if (id === "" && this.sending) { this.synchronousFailure = error; return true }
  var ticket = this.pending[id]
  if (!ticket || id !== this.activeRequestId || ticket.generation !== this.generation || ticket.routeId !== this.state.routeId) return false
  delete this.pending[id]; this.activeRequestId = ""; if (ticket.kind === "catalog") this.catalogResponse = null; this._setState(failureState(this.state, error)); return true
}
Controller.prototype.markStale = function(requestId) {
  var id = String(requestId || "")
  if (!this.pending[id] || id !== this.activeRequestId) return false
  this._cancelActive(); this._setState(failureState(this.state, structuredError("rpc.timeout", "Software state became stale", "The bounded read deadline elapsed before a complete response arrived. No cached state is shown.", ""))); return true
}
function createController(options) { return new Controller(options) }
function stateTitle(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "catalog-loading") return "Loading package provider"
  if (phase === "loading") return "Reading software evidence"
  if (phase === "ready") return "Verified provider response"
  if (phase === "partial") return "Partial bounded results"
  if (phase === "degraded") return state && state.assurance === "contract-seed" ? "Contract-seed catalog" : "Software provider is degraded"
  if (phase === "empty") return state && state.selectedMissing ? "Requested software is absent" : "No software records"
  if (phase === "missing") return "Package provider is not registered"
  if (phase === "unavailable") return "Software state is unavailable"
  if (phase === "denied") return "Software read was denied"
  if (phase === "interrupted") return "Software read was interrupted"
  if (phase === "stale") return "Software state is stale"
  if (phase === "failed") return "Software read failed"
  return "Fabric is offline"
}
function stateExplanation(state) {
  if (!state) return ""
  if (state.error && state.error.explanation) return clippedText(state.error.explanation, 1000)
  if (state.phase === "catalog-loading") return "Software Center is checking the exact code-owned provider generation before reading a route."
  if (state.phase === "loading") return "Only the route's declared read action is active. No package command or mutation is available."
  if (state.phase === "partial") return "This surface reached its visible-record bound. Omitted records are not inferred."
  if (state.phase === "degraded" && state.assurance === "contract-seed") return "Catalog records are contract seeds with declared provenance, not release verification. Installation remains unavailable."
  if (state.phase === "degraded") return "The current provider is usable for reads but explicitly reports degraded production readiness."
  if (state.phase === "empty") return state.selectedMissing ? "The exact deep-linked identity was not present in this revision." : "The provider returned a valid empty result."
  if (state.phase === "ready") return "Every visible record is bound to the displayed provider revision and provenance."
  if (state.phase === "missing") return "The code-owned packages.provider identity was not present in the current catalog."
  if (state.phase === "unavailable") return "The package provider has no usable read backend."
  return "Connect to the owner-scoped Fabric daemon to read Software Center state."
}
function phaseTone(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "ready" || phase === "empty") return "success"
  if (phase === "failed" || phase === "denied" || phase === "unavailable") return "danger"
  return "warning"
}
if (typeof module !== "undefined") module.exports = { ROUTES: ROUTES, queryForRoute: queryForRoute, normalizedSelection: normalizedSelection, requestParameters: requestParameters, catalogEntry: catalogEntry, normalizeResult: normalizeResult, baseState: baseState, createController: createController, stateTitle: stateTitle, stateExplanation: stateExplanation, phaseTone: phaseTone }
