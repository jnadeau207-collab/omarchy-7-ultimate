var CATALOG_METHOD = "provider.catalog"
var READ_METHOD = "provider.read"
var PROVIDER_ID = "compatibility.provider"
var MAX_CATALOG_ENTRIES = 128
var MAX_DEPLOYMENTS = 2048
var MAX_VISIBLE_RECORDS = 96
var MAX_TEXT = 480
var ROUTE_ORDER = ["native", "pwa", "known-good-recipe", "game-proton", "isolated-app", "vm"]
var PERMISSIONS = ["network", "audio", "camera", "microphone", "notifications", "filesystem-home", "filesystem-removable", "devices", "session"]
var RUNTIMES = ["wine", "proton", "container", "browser", "native"]

var ROUTES = [
  { routeId: "compatibility.overview", action: "", capability: "", kind: "overview" },
  { routeId: "compatibility.decide", action: "route.decide", capability: "compatibility.route.decide", kind: "decision" },
  { routeId: "compatibility.deployments", action: "deployments.inspect", capability: "compatibility.deployments.inspect", kind: "deployments" }
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
  return { code: clippedText(code || "compatibility.failed", 160), title: clippedText(title || "Compatibility read failed", 160), explanation: clippedText(explanation || "Fabric did not return usable Compatibility Center state.", 1000), detail: clippedText(detail || "", MAX_TEXT), retryable: true, changeState: "none", recoveryActions: ["provider.refresh"] }
}
function responseError(detail) { return structuredError("compatibility.invalid-response", "Compatibility Center rejected provider state", "Fabric returned data outside the closed Compatibility Center read contract.", detail) }
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
  var allowed = query && query.kind === "deployments" ? { entityType: true, entityId: true } : {}
  var names = Object.keys(args)
  for (var i = 0; i < names.length; i++) if (!allowed[names[i]]) throw new Error("The Compatibility Center route contains an unsupported argument.")
  var entityType = hasOwn(args, "entityType") ? String(args.entityType || "") : ""
  var entityId = hasOwn(args, "entityId") ? String(args.entityId || "") : ""
  if ((entityType === "") !== (entityId === "")) throw new Error("Compatibility entity type and identity must be supplied together.")
  if (entityType !== "" && entityType !== "deployment") throw new Error("The Compatibility entity type does not match this route.")
  if (entityId !== "" && !stableId(entityId)) throw new Error("The Compatibility entity identity is invalid.")
  return { entityType: entityType, entityId: entityId }
}
function routeArguments(state) {
  return state.entityType === "" ? {} : { entityType: state.entityType, entityId: state.entityId }
}
function baseState(routeId, argumentsValue, phase) {
  var query = queryForRoute(routeId), selection = { entityType: "", entityId: "" }, error = null
  if (!query) error = responseError("The route is not in the closed Compatibility Center map.")
  else { try { selection = normalizedSelection(query, argumentsValue) } catch (problem) { error = responseError(String(problem)) } }
  return { routeId: String(routeId || ""), query: query, entityType: selection.entityType, entityId: selection.entityId, phase: error ? "failed" : String(phase || "offline"), requestId: "", providerEntry: null, providerGeneration: 0, records: [], totalRecords: 0, clipped: false, selectedMissing: false, assurance: "unknown", revision: "", observedAt: null, inputProvenance: "none", error: error }
}
function failureState(previous, errorValue) {
  var next = cloneState(previous), error = isObject(errorValue) ? errorValue : structuredError("compatibility.failed", "Compatibility read failed", String(errorValue || "Unknown Fabric failure."), "")
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
    if (entry.manifest.provider === PROVIDER_ID) { if (found) return { error: "The provider catalog repeats compatibility.provider." }; found = entry }
  }
  if (!found) return { missing: true }
  var manifest = found.manifest
  if (!exactKeys(manifest, ["schemaVersion", "provider", "providerVersion", "minFabricProtocol", "maxFabricProtocol", "capabilities", "actions"]) || manifest.schemaVersion !== "v0" || manifest.provider !== PROVIDER_ID || manifest.providerVersion !== "v0" || !Number.isInteger(manifest.minFabricProtocol) || !Number.isInteger(manifest.maxFabricProtocol) || !Array.isArray(manifest.capabilities) || manifest.capabilities.length < 1 || manifest.capabilities.length > 128 || !isObject(manifest.actions) || !Number.isInteger(found.generation) || found.generation < 1 || !/^[0-9a-f]{64}$/.test(String(found.fingerprint || "")) || !Number.isInteger(found.registrationOrder) || found.registrationOrder < 1 || typeof found.detail !== "string" || found.detail.length > 500 || typeof found.registeredAt !== "number" || !isFinite(found.registeredAt) || found.registeredAt < 0 || typeof found.changedAt !== "number" || !isFinite(found.changedAt) || found.changedAt < 0 || ["available", "degraded", "unavailable", "incompatible"].indexOf(found.state) < 0) return { error: "The compatibility.provider catalog identity is invalid." }
  if (query.kind !== "overview" && !validAction(manifest.actions[query.action], query)) return { error: "The selected Compatibility Center read action does not match its closed manifest contract." }
  if (query.kind === "overview") {
    var decide = queryForRoute("compatibility.decide"), deployments = queryForRoute("compatibility.deployments")
    if (!validAction(manifest.actions[decide.action], decide) || !validAction(manifest.actions[deployments.action], deployments)) return { error: "The compatibility.provider overview does not contain both required read actions." }
  }
  return { entry: found }
}
function uniqueEnumArray(value, allowed, maximum, label) {
  if (!Array.isArray(value) || value.length > maximum) throw new Error(label + " exceeds its bounded array contract.")
  var seen = Object.create(null), result = []
  for (var i = 0; i < value.length; i++) {
    if (typeof value[i] !== "string" || allowed.indexOf(value[i]) < 0 || seen[value[i]]) throw new Error(label + " contains an invalid or duplicate value.")
    seen[value[i]] = true; result.push(value[i])
  }
  result.sort(function(left, right) { return allowed.indexOf(left) - allowed.indexOf(right) })
  return result
}
function boundedName(value, label, maximum) {
  if (typeof value !== "string" || value.length < 1 || value.length > maximum || /[\u0000-\u001f\u007f]/.test(value)) throw new Error(label + " is invalid.")
  return value
}
function safeHttps(value) {
  return typeof value === "string" && value.length >= 1 && value.length <= 500 && /^https:\/\/[^/@\s]+(?:[/:?#]|$)/.test(value) && !/[\u0000-\u0020\u007f]/.test(value)
}
function normalizeDecisionInput(requestValue, hostValue) {
  if (!exactKeys(requestValue, ["id", "name", "workloadType", "architecture", "artifact", "permissions", "constraints"])) throw new Error("The workload request has an unexpected field set.")
  if (!stableId(requestValue.id)) throw new Error("The workload identity is invalid.")
  var name = boundedName(requestValue.name, "The workload name", 160)
  if (["desktop", "web", "windows-game", "windows-app", "portable"].indexOf(requestValue.workloadType) < 0 || ["any", "x86_64", "aarch64"].indexOf(requestValue.architecture) < 0) throw new Error("The workload type or architecture is invalid.")
  var artifact = requestValue.artifact
  if (!exactKeys(artifact, ["kind", "origin", "digest"]) || ["native-package", "web-url", "windows-executable", "portable", "none"].indexOf(artifact.kind) < 0) throw new Error("The workload artifact is invalid.")
  if (artifact.kind === "none") { if (artifact.origin !== null || artifact.digest !== null) throw new Error("An absent artifact cannot carry an origin or digest.") }
  else {
    if (!safeHttps(artifact.origin)) throw new Error("The artifact origin must be bounded HTTPS without authority credentials.")
    if (["native-package", "windows-executable", "portable"].indexOf(artifact.kind) >= 0 && !digest(artifact.digest)) throw new Error("The executable artifact requires a pinned digest.")
    if (artifact.digest !== null && !digest(artifact.digest)) throw new Error("The artifact digest is invalid.")
  }
  var constraints = requestValue.constraints
  if (!exactKeys(constraints, ["requiresKernelDriver", "requiresAdmin", "antiCheat", "offlineRequired", "acceptsBrowser"]) || typeof constraints.requiresKernelDriver !== "boolean" || typeof constraints.requiresAdmin !== "boolean" || ["none", "supported", "blocked", "unknown"].indexOf(constraints.antiCheat) < 0 || typeof constraints.offlineRequired !== "boolean" || typeof constraints.acceptsBrowser !== "boolean") throw new Error("The workload constraints are invalid.")
  if (!exactKeys(hostValue, ["architecture", "virtualizationAvailable", "protonAvailable", "isolationAvailable", "browserAvailable", "availableRuntimes", "memoryMiB", "diskMiB"]) || ["x86_64", "aarch64"].indexOf(hostValue.architecture) < 0 || typeof hostValue.virtualizationAvailable !== "boolean" || typeof hostValue.protonAvailable !== "boolean" || typeof hostValue.isolationAvailable !== "boolean" || typeof hostValue.browserAvailable !== "boolean" || !Number.isInteger(hostValue.memoryMiB) || hostValue.memoryMiB < 128 || hostValue.memoryMiB > 262144 || !Number.isInteger(hostValue.diskMiB) || hostValue.diskMiB < 1 || hostValue.diskMiB > 1048576) throw new Error("The host declaration is invalid.")
  return {
    request: { id: requestValue.id, name: name, workloadType: requestValue.workloadType, architecture: requestValue.architecture, artifact: { kind: artifact.kind, origin: artifact.origin, digest: artifact.digest }, permissions: uniqueEnumArray(requestValue.permissions, PERMISSIONS, 16, "The permission declaration"), constraints: { requiresKernelDriver: constraints.requiresKernelDriver, requiresAdmin: constraints.requiresAdmin, antiCheat: constraints.antiCheat, offlineRequired: constraints.offlineRequired, acceptsBrowser: constraints.acceptsBrowser } },
    host: { architecture: hostValue.architecture, virtualizationAvailable: hostValue.virtualizationAvailable, protonAvailable: hostValue.protonAvailable, isolationAvailable: hostValue.isolationAvailable, browserAvailable: hostValue.browserAvailable, availableRuntimes: uniqueEnumArray(hostValue.availableRuntimes, RUNTIMES, 5, "The runtime declaration"), memoryMiB: hostValue.memoryMiB, diskMiB: hostValue.diskMiB }
  }
}
function requestParameters(state, explicitArguments) {
  var argumentsValue = state.query.kind === "decision" ? explicitArguments : {}
  return { provider: PROVIDER_ID, action: state.query.action, arguments: argumentsValue }
}
function detail(label, value) { return { label: label, value: clippedText(value === null || value === undefined || value === "" ? "Not reported" : value, MAX_TEXT) } }
function overviewRecord(entry) {
  var actions = Object.keys(entry.manifest.actions).sort()
  return { id: PROVIDER_ID, kind: "provider", title: "Compatibility provider", subtitle: clippedText(entry.detail || "Code-owned compatibility routing provider", 500), status: entry.state, tone: entry.state === "available" ? "success" : entry.state === "degraded" ? "warning" : "danger", details: [detail("Provider version", entry.manifest.providerVersion), detail("Generation", entry.generation), detail("Fingerprint", entry.fingerprint), detail("Read actions", "route.decide, deployments.inspect"), detail("Operation actions", actions.filter(function(name) { return isObject(entry.manifest.actions[name]) && entry.manifest.actions[name].mode === "operation" }).join(", ")), detail("Execution", "Unavailable until coordinator and executor integration")], order: 0 }
}
function decisionRecord(value, index) {
  return { id: value.decisionId, kind: "decision", title: value.eligibility === "supported" ? "Supported via " + value.selectedRoute : "Unsupported workload", subtitle: clippedText(value.explanation, 1000), status: value.eligibility, tone: value.eligibility === "supported" ? "success" : "danger", details: [detail("Selected route", value.selectedRoute), detail("Reason code", value.reasonCode), detail("Recipe", value.recipeId), detail("Recipe assurance", value.recipeAssurance), detail("Recipe revision", value.recipeRevision), detail("Required permissions", value.requiredPermissions.join(", ") || "None"), detail("Decision revision", value.revision), detail("Input provenance", "User-declared; host values were not measured by Compatibility Center")], order: index }
}
function consideredRecord(value, index) {
  return { id: "compatibility.considered." + value.route, kind: "considered-route", title: clippedText(value.route, 160), subtitle: clippedText(value.reason, 500), status: value.status, tone: value.status === "eligible" ? "success" : "neutral", details: [detail("Priority", index + 1), detail("Eligibility", value.status)], order: index + 1 }
}
function deploymentRecord(value, index) {
  if (!exactKeys(value, ["id", "workloadId", "displayName", "decisionId", "decisionRevision", "route", "recipeId", "state", "permissions", "dataArtifacts"]) || !stableId(value.id) || !stableId(value.workloadId) || typeof value.displayName !== "string" || value.displayName.length < 1 || value.displayName.length > 160 || /[\u0000-\u001f\u007f]/.test(value.displayName) || !stableId(value.decisionId) || !shaRevision(value.decisionRevision) || ROUTE_ORDER.indexOf(value.route) < 0 || (value.recipeId !== null && !stableId(value.recipeId)) || ["installed", "partial", "broken"].indexOf(value.state) < 0) return null
  var permissions, artifacts
  try { permissions = uniqueEnumArray(value.permissions, PERMISSIONS, 16, "Deployment permissions") } catch (_) { return null }
  if (!Array.isArray(value.dataArtifacts) || value.dataArtifacts.length > 64) return null
  artifacts = []
  for (var i = 0; i < value.dataArtifacts.length; i++) { if (!stableId(value.dataArtifacts[i]) || artifacts.indexOf(value.dataArtifacts[i]) >= 0) return null; artifacts.push(value.dataArtifacts[i]) }
  return { id: value.id, kind: "deployment", title: clippedText(value.displayName, 240), subtitle: clippedText(value.workloadId + " \u00b7 " + value.route, 320), status: value.state, tone: value.state === "installed" ? "success" : value.state === "partial" ? "warning" : "danger", details: [detail("Decision", value.decisionId), detail("Decision revision", value.decisionRevision), detail("Route", value.route), detail("Recipe", value.recipeId), detail("Permissions", permissions.join(", ") || "None"), detail("Data artifacts", artifacts.join(", ") || "None")], order: index }
}
function validateEnvelope(state, result) {
  if (!exactKeys(result, ["provider", "providerVersion", "generation", "action", "capability", "value", "observedAt"])) return "The provider result envelope has an unexpected field set."
  if (result.provider !== PROVIDER_ID || result.providerVersion !== "v0" || result.action !== state.query.action || result.capability !== state.query.capability) return "The provider result identity does not match this Compatibility Center route."
  if (!Number.isInteger(result.generation) || result.generation !== state.providerEntry.generation || typeof result.observedAt !== "number" || !isFinite(result.observedAt) || result.observedAt < 0 || !isObject(result.value)) return "The provider result belongs to an invalid or obsolete generation."
  return ""
}
function normalizeResult(state, result) {
  var invalid = validateEnvelope(state, result)
  if (invalid !== "") return { error: invalid }
  var value = result.value, records = [], total = 0, assurance = "unknown", revisionValue = "", unsupported = false
  if (state.query.kind === "decision") {
    if (!exactKeys(value, ["schemaVersion", "provider", "decisionId", "recipeRevision", "recipeAssurance", "eligibility", "selectedRoute", "recipeId", "reasonCode", "explanation", "requiredPermissions", "considered", "revision"]) || value.schemaVersion !== "v0" || value.provider !== PROVIDER_ID || !stableId(value.decisionId) || !shaRevision(value.recipeRevision) || ["contract-seed", "release-verified"].indexOf(value.recipeAssurance) < 0 || ["supported", "unsupported"].indexOf(value.eligibility) < 0 || (value.selectedRoute !== null && ROUTE_ORDER.indexOf(value.selectedRoute) < 0) || (value.recipeId !== null && !stableId(value.recipeId)) || !stableId(value.reasonCode) || typeof value.explanation !== "string" || value.explanation.length < 1 || value.explanation.length > 1000 || /[\u0000-\u001f\u007f]/.test(value.explanation) || !Array.isArray(value.requiredPermissions) || !Array.isArray(value.considered) || value.considered.length !== 6 || !shaRevision(value.revision)) return { error: "The compatibility decision payload is invalid." }
    try { uniqueEnumArray(value.requiredPermissions, PERMISSIONS, 16, "Decision permissions") } catch (problem) { return { error: String(problem) } }
    if ((value.eligibility === "supported") !== (value.selectedRoute !== null) || (value.selectedRoute === "known-good-recipe") !== (value.recipeId !== null)) return { error: "The decision eligibility, selected route, and recipe identity disagree." }
    records.push(decisionRecord(value, 0))
    for (var i = 0; i < value.considered.length; i++) {
      var considered = value.considered[i]
      if (!exactKeys(considered, ["route", "status", "reason"]) || considered.route !== ROUTE_ORDER[i] || ["eligible", "ineligible"].indexOf(considered.status) < 0 || typeof considered.reason !== "string" || considered.reason.length < 1 || considered.reason.length > 500 || /[\u0000-\u001f\u007f]/.test(considered.reason)) return { error: "The considered-route evidence is invalid or out of canonical order." }
      records.push(consideredRecord(considered, i))
    }
    var eligibleRoutes = value.considered.filter(function(item) { return item.status === "eligible" }).map(function(item) { return item.route })
    if (value.eligibility === "supported" && (eligibleRoutes.length !== 1 || eligibleRoutes[0] !== value.selectedRoute)) return { error: "The selected route does not match the canonical eligible route evidence." }
    if (value.eligibility === "unsupported" && eligibleRoutes.length !== 0) return { error: "An unsupported decision cannot contain an eligible route." }
    total = records.length; assurance = value.recipeAssurance; revisionValue = value.revision; unsupported = value.eligibility === "unsupported"
  } else {
    if (!exactKeys(value, ["schemaVersion", "provider", "revision", "deployments"]) || value.schemaVersion !== "v0" || value.provider !== PROVIDER_ID || !shaRevision(value.revision) || !Array.isArray(value.deployments) || value.deployments.length > MAX_DEPLOYMENTS) return { error: "The compatibility deployments payload is invalid." }
    total = value.deployments.length; revisionValue = value.revision
    for (var j = 0; j < value.deployments.length; j++) { var deployment = deploymentRecord(value.deployments[j], j); if (!deployment) return { error: "A compatibility deployment is invalid." }; records.push(deployment) }
  }
  var selectedMissing = false
  if (state.entityId !== "") { var selected = []; for (var k = 0; k < records.length; k++) if (records[k].id === state.entityId && records[k].kind === state.entityType) selected.push(records[k]); selectedMissing = selected.length === 0; records = selected }
  var clipped = records.length > MAX_VISIBLE_RECORDS
  if (clipped) records = records.slice(0, MAX_VISIBLE_RECORDS)
  return { records: records, totalRecords: total, clipped: clipped, selectedMissing: selectedMissing, assurance: assurance, revision: revisionValue, unsupported: unsupported, observedAt: result.observedAt }
}
function acceptedState(previous, result) {
  var normalized = normalizeResult(previous, result)
  if (normalized.error) return failureState(previous, responseError(normalized.error))
  var next = cloneState(previous)
  next.records = normalized.records; next.totalRecords = normalized.totalRecords; next.clipped = normalized.clipped; next.selectedMissing = normalized.selectedMissing; next.assurance = normalized.assurance; next.revision = normalized.revision; next.observedAt = normalized.observedAt; next.requestId = ""; next.error = null
  if (normalized.unsupported) next.phase = "unsupported"
  else if (normalized.clipped) next.phase = "partial"
  else if (previous.providerEntry.state === "degraded" || normalized.assurance === "contract-seed") next.phase = "degraded"
  else if (normalized.records.length === 0) next.phase = "empty"
  else next.phase = "ready"
  return next
}
function overviewState(previous, entry) {
  var next = cloneState(previous)
  next.records = [overviewRecord(entry)]; next.totalRecords = 1; next.clipped = false; next.assurance = entry.state === "degraded" ? "contract-seed" : "unknown"; next.revision = ""; next.observedAt = entry.changedAt; next.requestId = ""; next.error = null; next.phase = entry.state === "degraded" ? "degraded" : "ready"
  return next
}
function Controller(options) {
  var configuration = options || {}
  this.send = typeof configuration.send === "function" ? configuration.send : function() { return "" }
  this.cancel = typeof configuration.cancel === "function" ? configuration.cancel : function() { return false }
  this.publish = typeof configuration.onState === "function" ? configuration.onState : function() {}
  this.connected = false; this.generation = 0; this.catalogResponse = null; this.pending = Object.create(null); this.activeRequestId = ""; this.sending = false; this.synchronousFailure = null; this.state = baseState("compatibility.overview", {}, "offline")
}
Controller.prototype._setState = function(state) { this.state = state; this.publish(cloneState(state)) }
Controller.prototype._cancelActive = function() { if (this.activeRequestId !== "") { delete this.pending[this.activeRequestId]; this.cancel(this.activeRequestId) }; this.activeRequestId = "" }
Controller.prototype._send = function(kind, method, params) {
  this.sending = true; this.synchronousFailure = null
  var id = String(this.send(method, params) || "")
  this.sending = false
  if (id === "") { this._setState(failureState(this.state, this.synchronousFailure || structuredError("compatibility.request-rejected", "Compatibility request was rejected", "The constrained Fabric client did not accept the read-only request.", method))); return false }
  this.activeRequestId = id; this.pending[id] = { kind: kind, generation: this.generation, routeId: this.state.routeId }
  var waiting = cloneState(this.state); waiting.requestId = id; waiting.phase = kind === "catalog" ? "catalog-loading" : "loading"; this._setState(waiting); return true
}
Controller.prototype._startRoute = function() {
  var lookup = catalogEntry(this.catalogResponse, this.state.query)
  if (lookup.error) { this._setState(failureState(this.state, responseError(lookup.error))); return false }
  var prepared = cloneState(this.state)
  if (lookup.missing) { prepared.phase = "missing"; prepared.requestId = ""; this._setState(prepared); return false }
  prepared.providerEntry = lookup.entry; prepared.providerGeneration = lookup.entry.generation
  if (lookup.entry.state === "unavailable" || lookup.entry.state === "incompatible") { prepared.phase = "unavailable"; prepared.error = structuredError("provider.unavailable", "Compatibility provider is unavailable", lookup.entry.detail || "No usable compatibility backend is registered.", PROVIDER_ID); this._setState(prepared); return false }
  if (prepared.query.kind === "overview") { this._setState(overviewState(prepared, lookup.entry)); return true }
  if (prepared.query.kind === "decision") { prepared.phase = "input-required"; prepared.inputProvenance = "none"; prepared.requestId = ""; prepared.records = []; prepared.error = null; this._setState(prepared); return true }
  this._setState(prepared); return this._send("read", READ_METHOD, requestParameters(prepared, {}))
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
  if (this.catalogResponse) return this._startRoute()
  return this._send("catalog", CATALOG_METHOD, {})
}
Controller.prototype.decide = function(requestValue, hostValue) {
  if (!this.connected || !this.state.query || this.state.query.kind !== "decision" || !this.state.providerEntry) return false
  var normalized
  try { normalized = normalizeDecisionInput(requestValue, hostValue) }
  catch (problem) { this._setState(failureState(this.state, responseError(String(problem)))); return false }
  this.generation++; this._cancelActive(); this.pending = Object.create(null)
  var prepared = cloneState(this.state); prepared.inputProvenance = "user-declared-unmeasured"; prepared.records = []; prepared.error = null; this._setState(prepared)
  return this._send("read", READ_METHOD, requestParameters(prepared, normalized))
}
Controller.prototype.refresh = function() { return this.connected ? this._refreshCatalog() : false }
Controller.prototype.receiveResult = function(requestId, result) {
  var id = String(requestId || ""), ticket = this.pending[id]
  if (!ticket || id !== this.activeRequestId || ticket.generation !== this.generation || ticket.routeId !== this.state.routeId) return false
  delete this.pending[id]; this.activeRequestId = ""
  if (ticket.kind === "catalog") { var lookup = catalogEntry(result, this.state.query); if (lookup.error) { this._setState(failureState(this.state, responseError(lookup.error))); return true }; this.catalogResponse = result; this._startRoute() } else this._setState(acceptedState(this.state, result))
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
  this._cancelActive(); this._setState(failureState(this.state, structuredError("rpc.timeout", "Compatibility state became stale", "The bounded read deadline elapsed before a complete response arrived. No cached state is shown.", ""))); return true
}
function createController(options) { return new Controller(options) }
function stateTitle(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "catalog-loading") return "Loading compatibility provider"
  if (phase === "loading") return "Evaluating compatibility evidence"
  if (phase === "input-required") return "Complete workload and host input required"
  if (phase === "ready") return "Current compatibility evidence"
  if (phase === "unsupported") return "No safe route is supported"
  if (phase === "partial") return "Partial bounded results"
  if (phase === "degraded") return state && state.assurance === "contract-seed" ? "Contract-seed compatibility evidence" : "Compatibility provider is degraded"
  if (phase === "empty") return state && state.selectedMissing ? "Requested deployment is absent" : "No deployments"
  if (phase === "missing") return "Compatibility provider is not registered"
  if (phase === "unavailable") return "Compatibility state is unavailable"
  if (phase === "denied") return "Compatibility read was denied"
  if (phase === "interrupted") return "Compatibility read was interrupted"
  if (phase === "stale") return "Compatibility state is stale"
  if (phase === "failed") return "Compatibility read failed"
  return "Fabric is offline"
}
function stateExplanation(state) {
  if (!state) return ""
  if (state.error && state.error.explanation) return clippedText(state.error.explanation, 1000)
  if (state.phase === "catalog-loading") return "Compatibility Center is checking the exact code-owned provider generation before reading a route."
  if (state.phase === "loading") return "The provider is evaluating only the complete, explicitly declared workload and host snapshot."
  if (state.phase === "input-required") return "Compatibility Center does not guess host capabilities. Supply a complete user-declared snapshot to request a read-only route decision."
  if (state.phase === "unsupported") return "All six routes were considered in canonical order and none satisfied the declared workload, artifact, permissions, and host constraints."
  if (state.phase === "degraded" && state.assurance === "contract-seed") return "Recipe evidence is contract seed data with declared signatures, not release verification. Deployment remains unavailable."
  if (state.phase === "degraded") return "The provider is usable for reads but explicitly reports plan-only or degraded production readiness."
  if (state.phase === "partial") return "This surface reached its visible-record bound. Omitted records are not inferred."
  if (state.phase === "empty") return state.selectedMissing ? "The exact deep-linked deployment was not present in this revision." : "The provider returned a valid empty deployment inventory."
  if (state.phase === "ready") return "Every visible record is bound to the current provider generation and revision."
  if (state.phase === "missing") return "The code-owned compatibility.provider identity was not present in the current catalog."
  if (state.phase === "unavailable") return "The compatibility provider has no usable read backend."
  return "Connect to the owner-scoped Fabric daemon to read Compatibility Center state."
}
function phaseTone(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "ready" || phase === "empty") return "success"
  if (phase === "unsupported" || phase === "failed" || phase === "denied" || phase === "unavailable") return "danger"
  return "warning"
}
if (typeof module !== "undefined") module.exports = { ROUTES: ROUTES, ROUTE_ORDER: ROUTE_ORDER, PERMISSIONS: PERMISSIONS, RUNTIMES: RUNTIMES, queryForRoute: queryForRoute, normalizedSelection: normalizedSelection, normalizeDecisionInput: normalizeDecisionInput, requestParameters: requestParameters, catalogEntry: catalogEntry, normalizeResult: normalizeResult, baseState: baseState, createController: createController, stateTitle: stateTitle, stateExplanation: stateExplanation, phaseTone: phaseTone }
