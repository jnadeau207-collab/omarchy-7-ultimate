var CATALOG_METHOD = "provider.catalog"
var READ_METHOD = "provider.read"
var PROVIDER_ID = "files.provider"
var MAX_CATALOG_ENTRIES = 128
var MAX_SOURCE_RECORDS = 256
var MAX_VISIBLE_RECORDS = 96
var MAX_TEXT = 480

var ROUTES = [
  { routeId: "files.overview", action: "inspect", capability: "files.inspect", kind: "overview", arguments: {} },
  { routeId: "files.this-pc", action: "inspect", capability: "files.inspect", kind: "this-pc", arguments: {} },
  { routeId: "files.desktop", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.desktop", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.documents", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.documents", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.downloads", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.downloads", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.recent", action: "recent", capability: "files.recent.read", kind: "entries", arguments: { limit: 96 } },
  { routeId: "files.search", action: "search", capability: "files.search", kind: "entries", arguments: null },
  { routeId: "files.trash", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.trash", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.network", action: "inspect", capability: "files.inspect", kind: "network", arguments: {} }
]

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function hasOwn(value, key) {
  return isObject(value) && Object.prototype.hasOwnProperty.call(value, key)
}

function exactKeys(value, expected) {
  if (!isObject(value)) return false
  var actual = Object.keys(value).sort()
  var wanted = expected.slice().sort()
  if (actual.length !== wanted.length) return false
  for (var i = 0; i < actual.length; i++) if (actual[i] !== wanted[i]) return false
  return true
}

function stableId(value) {
  return typeof value === "string" && value.length >= 1 && value.length <= 160 &&
    /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/.test(value)
}

function revision(value) {
  return typeof value === "string" && /^sha256\.[0-9a-f]{64}$/.test(value)
}

function clippedText(value, maximum) {
  var limit = typeof maximum === "number" ? maximum : MAX_TEXT
  var text = value === null || value === undefined ? "" : String(value)
  text = text.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
  return text.length <= limit ? text : text.slice(0, Math.max(1, limit - 1)) + "\u2026"
}

function copyArray(value) {
  return Array.isArray(value) ? value.slice() : []
}

function cloneState(state) {
  var result = {}
  var keys = Object.keys(state || {})
  for (var i = 0; i < keys.length; i++) result[keys[i]] = state[keys[i]]
  result.records = copyArray(state && state.records)
  result.reasons = copyArray(state && state.reasons)
  return result
}

function queryForRoute(routeId) {
  var id = String(routeId || "")
  for (var i = 0; i < ROUTES.length; i++) if (ROUTES[i].routeId === id) return ROUTES[i]
  return null
}

function structuredError(code, title, explanation, detail) {
  return {
    code: clippedText(code || "files.failed", 160),
    title: clippedText(title || "Files read failed", 160),
    explanation: clippedText(explanation || "Fabric did not return usable Files state.", 1000),
    detail: clippedText(detail || "", MAX_TEXT),
    retryable: true,
    changeState: "none",
    recoveryActions: ["provider.refresh"]
  }
}

function responseError(detail) {
  return structuredError("files.invalid-response", "Files rejected provider state", "Fabric returned data outside the closed Files read contract.", detail)
}

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
  var allowed = query && query.routeId === "files.search" ? { query: true, entityType: true, entityId: true }
    : query && (query.routeId === "files.overview" || query.routeId === "files.network") ? { entityType: true, entityId: true }
    : {}
  var names = Object.keys(args)
  for (var i = 0; i < names.length; i++) if (!allowed[names[i]]) throw new Error("The Files route contains an unsupported argument.")
  var entityType = hasOwn(args, "entityType") ? String(args.entityType || "") : ""
  var entityId = hasOwn(args, "entityId") ? String(args.entityId || "") : ""
  if ((entityType === "") !== (entityId === "")) throw new Error("Files entity type and identity must be supplied together.")
  if (entityId !== "" && !stableId(entityId)) throw new Error("The Files entity identity is invalid.")
  var expected = query && query.routeId === "files.overview" ? "location"
    : query && query.routeId === "files.network" ? "mount"
    : query && query.routeId === "files.search" ? "entry" : ""
  if (entityType !== "" && entityType !== expected) throw new Error("The Files entity type does not match this route.")
  var search = hasOwn(args, "query") ? String(args.query) : ""
  if (search.length > 120 || /[\u0000-\u001f\u007f]/.test(search)) throw new Error("The Files search query is invalid.")
  return { entityType: entityType, entityId: entityId, searchQuery: search }
}

function baseState(routeId, argumentsValue, phase) {
  var query = queryForRoute(routeId)
  var selection = { entityType: "", entityId: "", searchQuery: "" }
  var error = null
  if (!query) error = responseError("The route is not in the closed Files map.")
  else {
    try { selection = normalizedSelection(query, argumentsValue) }
    catch (problem) { error = responseError(String(problem)) }
  }
  return {
    routeId: String(routeId || ""), query: query,
    entityType: selection.entityType, entityId: selection.entityId, searchQuery: selection.searchQuery,
    phase: error ? "failed" : String(phase || "offline"), requestId: "", providerEntry: null,
    records: [], totalRecords: 0, clipped: false, truncated: false, selectedMissing: false,
    availability: "unknown", revision: "", observedAt: null, providerGeneration: 0,
    error: error, reasons: []
  }
}

function routeArguments(state) {
  var result = {}
  if (state.query && state.query.routeId === "files.search" && state.searchQuery !== "") result.query = state.searchQuery
  if (state.entityType !== "") { result.entityType = state.entityType; result.entityId = state.entityId }
  return result
}

function failureState(previous, errorValue) {
  var next = cloneState(previous)
  var error = isObject(errorValue) ? errorValue : structuredError("files.failed", "Files read failed", String(errorValue || "Unknown Fabric failure."), "")
  next.phase = phaseForError(error)
  next.requestId = ""
  next.records = []
  next.totalRecords = 0
  next.clipped = false
  next.truncated = false
  next.selectedMissing = false
  next.observedAt = null
  next.error = error
  next.reasons = []
  return next
}

function validAction(action, query) {
  return exactKeys(action, ["capability", "mode", "risk", "effects", "arguments", "result", "preflight", "state", "supportsRollback", "supportsCancellation"]) &&
    action.capability === query.capability && action.mode === "read" && action.risk === "read-only" &&
    Array.isArray(action.effects) && action.effects.length === 0 && isObject(action.arguments) && isObject(action.result) &&
    action.preflight === null && action.state === null && action.supportsRollback === false && action.supportsCancellation === false
}

function catalogEntry(response, query) {
  if (!exactKeys(response, ["providers"]) || !Array.isArray(response.providers) || response.providers.length > MAX_CATALOG_ENTRIES)
    return { error: "The provider catalog envelope is invalid." }
  var found = null
  for (var i = 0; i < response.providers.length; i++) {
    var entry = response.providers[i]
    if (!exactKeys(entry, ["manifest", "fingerprint", "generation", "registrationOrder", "state", "detail", "registeredAt", "changedAt"]) || !isObject(entry.manifest))
      return { error: "A provider catalog entry has an unexpected field set." }
    if (entry.manifest.provider === PROVIDER_ID) {
      if (found) return { error: "The provider catalog repeats files.provider." }
      found = entry
    }
  }
  if (!found) return { missing: true }
  var manifest = found.manifest
  if (!exactKeys(manifest, ["schemaVersion", "provider", "providerVersion", "minFabricProtocol", "maxFabricProtocol", "capabilities", "actions"]) ||
      manifest.schemaVersion !== "v0" || manifest.provider !== PROVIDER_ID || manifest.providerVersion !== "v0" || !Number.isInteger(manifest.minFabricProtocol) || !Number.isInteger(manifest.maxFabricProtocol) ||
      !Array.isArray(manifest.capabilities) || manifest.capabilities.length < 1 || manifest.capabilities.length > 128 || !isObject(manifest.actions) ||
      !Number.isInteger(found.generation) || found.generation < 1 || !/^[0-9a-f]{64}$/.test(String(found.fingerprint || "")) ||
      !Number.isInteger(found.registrationOrder) || found.registrationOrder < 1 || typeof found.detail !== "string" || found.detail.length > 500 ||
      typeof found.registeredAt !== "number" || !isFinite(found.registeredAt) || found.registeredAt < 0 || typeof found.changedAt !== "number" || !isFinite(found.changedAt) || found.changedAt < 0 ||
      ["available", "degraded", "unavailable", "incompatible"].indexOf(found.state) < 0)
    return { error: "The files.provider catalog identity is invalid." }
  var action = manifest.actions[query.action]
  if (!validAction(action, query)) return { error: "The selected Files read action does not match its closed manifest contract." }
  return { entry: found }
}

function requestArguments(state) {
  var query = state.query
  if (query.routeId === "files.search") return { query: state.searchQuery, locationIds: [], includeHidden: false, limit: 96 }
  var source = query.arguments || {}
  var result = {}
  var keys = Object.keys(source)
  for (var i = 0; i < keys.length; i++) result[keys[i]] = source[keys[i]]
  return result
}

function requestParameters(state) {
  return { provider: PROVIDER_ID, action: state.query.action, arguments: requestArguments(state) }
}

function validReason(reason) {
  if (!isObject(reason)) return false
  var keys = ["code", "title", "explanation", "detail", "retryable", "changeState"]
  if (hasOwn(reason, "recoveryActions")) keys.push("recoveryActions")
  if (!exactKeys(reason, keys) || !stableId(reason.code) || typeof reason.title !== "string" || reason.title.length < 1 || reason.title.length > 160 ||
      typeof reason.explanation !== "string" || reason.explanation.length < 1 || reason.explanation.length > 2000 || typeof reason.detail !== "string" || reason.detail.length > 2000 ||
      typeof reason.retryable !== "boolean" || ["none", "partial", "complete", "unknown"].indexOf(reason.changeState) < 0) return false
  if (hasOwn(reason, "recoveryActions")) {
    if (!Array.isArray(reason.recoveryActions) || reason.recoveryActions.length > 8) return false
    for (var i = 0; i < reason.recoveryActions.length; i++) if (!stableId(reason.recoveryActions[i]) || reason.recoveryActions.indexOf(reason.recoveryActions[i]) !== i) return false
  }
  return true
}

function validAvailability(value) {
  if (!exactKeys(value, ["state", "read", "operation", "reasons"]) || ["available", "degraded", "unavailable"].indexOf(value.state) < 0 ||
      typeof value.read !== "boolean" || typeof value.operation !== "boolean" || !Array.isArray(value.reasons) || value.reasons.length > 16) return false
  for (var i = 0; i < value.reasons.length; i++) if (!validReason(value.reasons[i])) return false
  return true
}

function detail(label, value) {
  return { label: label, value: clippedText(value === null || value === undefined || value === "" ? "Not reported" : value, MAX_TEXT) }
}

function validLocation(location) {
  return exactKeys(location, ["id", "kind", "label", "state", "writable", "rootToken", "reason"]) && stableId(location.id) &&
    ["this-pc", "home", "desktop", "documents", "downloads", "trash", "mount", "network"].indexOf(location.kind) >= 0 &&
    typeof location.label === "string" && location.label.length >= 1 && location.label.length <= 160 &&
    ["available", "degraded", "unavailable"].indexOf(location.state) >= 0 && typeof location.writable === "boolean" && revision(location.rootToken) &&
    (location.reason === null || validReason(location.reason))
}

function validTrash(trash) {
  return trash === null || (exactKeys(trash, ["originalLocationId", "originalParentId", "originalRelativePath"]) &&
    stableId(trash.originalLocationId) && (trash.originalParentId === null || stableId(trash.originalParentId)) &&
    typeof trash.originalRelativePath === "string" && trash.originalRelativePath.length >= 1 && trash.originalRelativePath.length <= 1024)
}

function validEntry(entry) {
  return exactKeys(entry, ["id", "locationId", "parentId", "name", "relativePath", "kind", "sizeBytes", "modifiedNs", "mimeType", "hidden", "writable", "identity", "symlinkTargetState", "trash"]) &&
    stableId(entry.id) && stableId(entry.locationId) && (entry.parentId === null || stableId(entry.parentId)) && typeof entry.name === "string" && entry.name.length >= 1 && entry.name.length <= 255 &&
    typeof entry.relativePath === "string" && entry.relativePath.length >= 1 && entry.relativePath.length <= 1024 && ["file", "directory", "symlink"].indexOf(entry.kind) >= 0 &&
    (entry.sizeBytes === null || (Number.isSafeInteger(entry.sizeBytes) && entry.sizeBytes >= 0)) && (entry.modifiedNs === null || (Number.isSafeInteger(entry.modifiedNs) && entry.modifiedNs >= 0)) &&
    (entry.mimeType === null || (typeof entry.mimeType === "string" && entry.mimeType.length <= 160 && /^[a-z0-9.+-]+\/[a-z0-9.+-]+$/.test(entry.mimeType))) &&
    typeof entry.hidden === "boolean" && typeof entry.writable === "boolean" && revision(entry.identity) &&
    (entry.symlinkTargetState === null || ["inside-root", "outside-root", "missing", "unknown"].indexOf(entry.symlinkTargetState) >= 0) && validTrash(entry.trash)
}

function validMountSource(source) {
  return exactKeys(source, ["scheme", "display", "host", "share"]) && ["system", "device", "smb"].indexOf(source.scheme) >= 0 &&
    typeof source.display === "string" && source.display.length >= 1 && source.display.length <= 320 &&
    (source.host === null || (typeof source.host === "string" && source.host.length >= 1 && source.host.length <= 253)) &&
    (source.share === null || (typeof source.share === "string" && source.share.length >= 1 && source.share.length <= 255))
}

function validMount(mount) {
  return exactKeys(mount, ["id", "kind", "label", "state", "writable", "locationId", "source", "reason"]) && stableId(mount.id) &&
    ["system", "removable", "smb"].indexOf(mount.kind) >= 0 && typeof mount.label === "string" && mount.label.length >= 1 && mount.label.length <= 160 &&
    ["mounted", "unmounted", "degraded", "unavailable"].indexOf(mount.state) >= 0 && typeof mount.writable === "boolean" &&
    (mount.locationId === null || stableId(mount.locationId)) && isObject(mount.source) && validMountSource(mount.source) && (mount.reason === null || validReason(mount.reason))
}

function validRecent(recent) {
  return exactKeys(recent, ["entryId", "rank"]) && stableId(recent.entryId) && Number.isInteger(recent.rank) && recent.rank >= 0 && recent.rank <= 127
}

function entryRecord(entry, index) {
  if (!isObject(entry) || !validEntry(entry)) return null
  var details = [detail("Location", entry.locationId), detail("Relative path", entry.relativePath), detail("Type", entry.mimeType || entry.kind)]
  if (entry.sizeBytes !== null && entry.sizeBytes !== undefined) details.push(detail("Size", entry.sizeBytes + " bytes"))
  if (entry.modifiedNs !== null && entry.modifiedNs !== undefined) details.push(detail("Modified", entry.modifiedNs + " ns"))
  details.push(detail("Writable", entry.writable === true ? "Yes" : "No"))
  if (entry.symlinkTargetState) details.push(detail("Symlink target", entry.symlinkTargetState))
  if (isObject(entry.trash)) {
    details.push(detail("Original location", entry.trash.originalLocationId))
    details.push(detail("Original path", entry.trash.originalRelativePath))
  }
  return { id: entry.id, kind: "entry", title: clippedText(entry.name, 240), subtitle: clippedText(entry.relativePath, 320), status: entry.kind, tone: entry.kind === "symlink" ? "warning" : "neutral", details: details, order: index }
}

function locationRecord(location, index) {
  if (!isObject(location) || !validLocation(location)) return null
  var details = [detail("Kind", location.kind), detail("Writable", location.writable === true ? "Yes" : "No"), detail("Root revision", location.rootToken)]
  if (isObject(location.reason)) details.push(detail("Reason", location.reason.explanation || location.reason.title))
  return { id: location.id, kind: "location", title: clippedText(location.label, 240), subtitle: clippedText(location.kind, 160), status: location.state, tone: location.state === "available" ? "success" : location.state === "degraded" ? "warning" : "danger", details: details, order: index }
}

function mountRecord(mount, index) {
  if (!isObject(mount) || !validMount(mount)) return null
  var source = mount.source
  var display = source.scheme === "smb" ? (source.host || "network") + "/" + (source.share || "share") : source.display
  var details = [detail("Kind", mount.kind), detail("Source", display), detail("Writable", mount.writable === true ? "Yes" : "No"), detail("Location", mount.locationId)]
  if (isObject(mount.reason)) details.push(detail("Reason", mount.reason.explanation || mount.reason.title))
  return { id: mount.id, kind: "mount", title: clippedText(mount.label, 240), subtitle: clippedText(display, 320), status: clippedText(mount.state, 80), tone: mount.state === "mounted" ? "success" : mount.state === "degraded" ? "warning" : "danger", details: details, order: index }
}

function validateEnvelope(state, result) {
  if (!exactKeys(result, ["provider", "providerVersion", "generation", "action", "capability", "value", "observedAt"])) return "The provider result envelope has an unexpected field set."
  if (result.provider !== PROVIDER_ID || result.providerVersion !== "v0" || result.action !== state.query.action || result.capability !== state.query.capability) return "The provider result identity does not match this Files route."
  if (!Number.isInteger(result.generation) || result.generation !== state.providerEntry.generation || typeof result.observedAt !== "number" || !isFinite(result.observedAt) || result.observedAt < 0 || !isObject(result.value)) return "The provider result belongs to an invalid or obsolete generation."
  return ""
}

function normalizeResult(state, result) {
  var invalid = validateEnvelope(state, result)
  if (invalid !== "") return { error: invalid }
  var value = result.value
  var base = ["schemaVersion", "provider", "providerVersion", "action", "availability", "revision"]
  var records = []
  var total = 0
  var truncated = false
  if (state.query.action === "inspect") {
    if (!exactKeys(value, base.concat(["state"])) || value.schemaVersion !== "v0" || value.provider !== PROVIDER_ID || value.providerVersion !== "v0" || value.action !== "inspect" || !validAvailability(value.availability) || (value.revision !== null && !revision(value.revision)) || (value.state !== null && !isObject(value.state))) return { error: "The Files inventory payload is invalid." }
    if (value.state !== null) {
      if (!exactKeys(value.state, ["schemaVersion", "workspaceId", "locations", "entries", "mounts", "recent"]) || value.state.schemaVersion !== "v0" || value.state.workspaceId !== "files.workspace.primary" || !Array.isArray(value.state.locations) || value.state.locations.length > 32 || !Array.isArray(value.state.entries) || value.state.entries.length > MAX_SOURCE_RECORDS || !Array.isArray(value.state.mounts) || value.state.mounts.length > 64 || !Array.isArray(value.state.recent) || value.state.recent.length > 128) return { error: "The Files workspace exceeds its closed inventory contract." }
      var locations = value.state.locations
      var mounts = value.state.mounts
      for (var locationIndex = 0; locationIndex < locations.length; locationIndex++) if (!validLocation(locations[locationIndex])) return { error: "A Files location is invalid." }
      for (var entryIndex = 0; entryIndex < value.state.entries.length; entryIndex++) if (!validEntry(value.state.entries[entryIndex])) return { error: "A Files entry is invalid." }
      for (var mountIndex = 0; mountIndex < mounts.length; mountIndex++) if (!validMount(mounts[mountIndex])) return { error: "A Files mount is invalid." }
      for (var recentIndex = 0; recentIndex < value.state.recent.length; recentIndex++) if (!validRecent(value.state.recent[recentIndex])) return { error: "A Files recent-item reference is invalid." }
      if (state.query.kind === "overview" || state.query.kind === "this-pc") {
        for (var i = 0; i < locations.length; i++) {
          if (state.query.kind === "this-pc" && ["network", "trash"].indexOf(locations[i].kind) >= 0) continue
          var location = locationRecord(locations[i], records.length)
          if (!location) return { error: "A Files location is invalid." }
          records.push(location)
        }
        for (var j = 0; j < mounts.length; j++) {
          if (state.query.kind === "this-pc" && ["system", "removable"].indexOf(mounts[j].kind) < 0) continue
          var mount = mountRecord(mounts[j], records.length)
          if (!mount) return { error: "A Files mount is invalid." }
          records.push(mount)
        }
      } else if (state.query.kind === "network") {
        for (var k = 0; k < locations.length; k++) if (locations[k].kind === "network" || locations[k].kind === "mount") {
          var networkLocation = locationRecord(locations[k], records.length)
          if (!networkLocation) return { error: "A Files network location is invalid." }
          records.push(networkLocation)
        }
        for (var m = 0; m < mounts.length; m++) if (mounts[m].kind === "smb" || mounts[m].kind === "removable") {
          var networkMount = mountRecord(mounts[m], records.length)
          if (!networkMount) return { error: "A Files network mount is invalid." }
          records.push(networkMount)
        }
      }
    }
  } else {
    if (!exactKeys(value, base.concat(["entries", "truncated"])) || value.schemaVersion !== "v0" || value.provider !== PROVIDER_ID || value.providerVersion !== "v0" || value.action !== state.query.action || !validAvailability(value.availability) || (value.revision !== null && !revision(value.revision)) || !Array.isArray(value.entries) || value.entries.length > 128 || typeof value.truncated !== "boolean") return { error: "The Files query payload is invalid." }
    total = value.entries.length
    truncated = value.truncated
    for (var n = 0; n < value.entries.length; n++) {
      var item = entryRecord(value.entries[n], n)
      if (!item) return { error: "A Files entry is invalid." }
      records.push(item)
    }
  }
  if (total === 0) total = records.length
  var selectedMissing = false
  if (state.entityId !== "") {
    var selected = []
    for (var s = 0; s < records.length; s++) if (records[s].id === state.entityId && records[s].kind === state.entityType) selected.push(records[s])
    selectedMissing = selected.length === 0
    records = selected
  }
  var clipped = records.length > MAX_VISIBLE_RECORDS
  if (clipped) records = records.slice(0, MAX_VISIBLE_RECORDS)
  return { value: value, records: records, totalRecords: total, clipped: clipped, truncated: truncated, selectedMissing: selectedMissing, observedAt: result.observedAt }
}

function acceptedState(previous, result) {
  var normalized = normalizeResult(previous, result)
  if (normalized.error) return failureState(previous, responseError(normalized.error))
  var next = cloneState(previous)
  next.records = normalized.records
  next.totalRecords = normalized.totalRecords
  next.clipped = normalized.clipped
  next.truncated = normalized.truncated
  next.selectedMissing = normalized.selectedMissing
  next.availability = normalized.value.availability.state
  next.revision = normalized.value.revision || ""
  next.observedAt = normalized.observedAt
  next.requestId = ""
  next.error = null
  next.reasons = copyArray(normalized.value.availability.reasons)
  if (normalized.value.availability.state === "unavailable" || normalized.value.availability.read === false) next.phase = "unavailable"
  else if (normalized.truncated || normalized.clipped) next.phase = "partial"
  else if (normalized.value.availability.state === "degraded" || previous.providerEntry.state === "degraded") next.phase = "degraded"
  else if (normalized.records.length === 0) next.phase = "empty"
  else next.phase = "ready"
  return next
}

function Controller(options) {
  var configuration = options || {}
  this.send = typeof configuration.send === "function" ? configuration.send : function() { return "" }
  this.cancel = typeof configuration.cancel === "function" ? configuration.cancel : function() { return false }
  this.publish = typeof configuration.onState === "function" ? configuration.onState : function() {}
  this.connected = false
  this.generation = 0
  this.catalogResponse = null
  this.pending = Object.create(null)
  this.activeRequestId = ""
  this.sending = false
  this.synchronousFailure = null
  this.state = baseState("files.overview", {}, "offline")
}

Controller.prototype._setState = function(state) { this.state = state; this.publish(cloneState(state)) }
Controller.prototype._cancelActive = function() {
  if (this.activeRequestId !== "") { delete this.pending[this.activeRequestId]; this.cancel(this.activeRequestId) }
  this.activeRequestId = ""
}
Controller.prototype._send = function(kind, method, params) {
  this.sending = true
  this.synchronousFailure = null
  var id = String(this.send(method, params) || "")
  this.sending = false
  if (id === "") {
    this._setState(failureState(this.state, this.synchronousFailure || structuredError("files.request-rejected", "Files request was rejected", "The constrained Fabric client did not accept the read-only request.", method)))
    return false
  }
  this.activeRequestId = id
  this.pending[id] = { kind: kind, generation: this.generation, routeId: this.state.routeId }
  var waiting = cloneState(this.state)
  waiting.requestId = id
  waiting.phase = kind === "catalog" ? "catalog-loading" : "loading"
  this._setState(waiting)
  return true
}
Controller.prototype._startRead = function() {
  var lookup = catalogEntry(this.catalogResponse, this.state.query)
  if (lookup.error) { this._setState(failureState(this.state, responseError(lookup.error))); return false }
  var prepared = cloneState(this.state)
  if (lookup.missing) { prepared.phase = "missing"; prepared.requestId = ""; this._setState(prepared); return false }
  prepared.providerEntry = lookup.entry
  prepared.providerGeneration = lookup.entry.generation
  if (lookup.entry.state === "unavailable" || lookup.entry.state === "incompatible") {
    prepared.phase = "unavailable"
    prepared.error = structuredError("provider.unavailable", "Files provider is unavailable", lookup.entry.detail || "No usable Files backend is registered.", PROVIDER_ID)
    this._setState(prepared)
    return false
  }
  this._setState(prepared)
  return this._send("read", READ_METHOD, requestParameters(prepared))
}
Controller.prototype._refreshCatalog = function() {
  this.generation++
  this._cancelActive()
  this.pending = Object.create(null)
  this.catalogResponse = null
  return this._send("catalog", CATALOG_METHOD, {})
}
Controller.prototype.setConnected = function(connected) {
  var value = connected === true
  if (value === this.connected) return false
  this.connected = value
  if (!value) {
    this.generation++
    this._cancelActive()
    this.pending = Object.create(null)
    this.catalogResponse = null
    this._setState(baseState(this.state.routeId, routeArguments(this.state), "offline"))
    return true
  }
  return this._refreshCatalog()
}
Controller.prototype.activate = function(routeId, argumentsValue) {
  this.generation++
  this._cancelActive()
  this.pending = Object.create(null)
  var next = baseState(routeId, argumentsValue, this.connected ? "loading" : "offline")
  this._setState(next)
  if (!this.connected || next.phase === "failed") return false
  if (this.catalogResponse) return this._startRead()
  return this._send("catalog", CATALOG_METHOD, {})
}
Controller.prototype.refresh = function() { return this.connected ? this._refreshCatalog() : false }
Controller.prototype.receiveResult = function(requestId, result) {
  var id = String(requestId || "")
  var ticket = this.pending[id]
  if (!ticket || id !== this.activeRequestId || ticket.generation !== this.generation || ticket.routeId !== this.state.routeId) return false
  delete this.pending[id]
  this.activeRequestId = ""
  if (ticket.kind === "catalog") {
    var lookup = catalogEntry(result, this.state.query)
    if (lookup.error) { this._setState(failureState(this.state, responseError(lookup.error))); return true }
    this.catalogResponse = result
    this._startRead()
  } else this._setState(acceptedState(this.state, result))
  return true
}
Controller.prototype.receiveFailure = function(requestId, error) {
  var id = String(requestId || "")
  if (id === "" && this.sending) { this.synchronousFailure = error; return true }
  var ticket = this.pending[id]
  if (!ticket || id !== this.activeRequestId || ticket.generation !== this.generation || ticket.routeId !== this.state.routeId) return false
  delete this.pending[id]
  this.activeRequestId = ""
  if (ticket.kind === "catalog") this.catalogResponse = null
  this._setState(failureState(this.state, error))
  return true
}
Controller.prototype.markStale = function(requestId) {
  var id = String(requestId || "")
  if (!this.pending[id] || id !== this.activeRequestId) return false
  this._cancelActive()
  this._setState(failureState(this.state, structuredError("rpc.timeout", "Files state became stale", "The bounded read deadline elapsed before a complete response arrived. No cached state is shown.", "")))
  return true
}

function createController(options) { return new Controller(options) }

function stateTitle(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "catalog-loading") return "Loading Files provider"
  if (phase === "loading") return "Reading trusted file metadata"
  if (phase === "ready") return "Current file metadata"
  if (phase === "partial") return "Partial bounded results"
  if (phase === "degraded") return "Files is read-only or degraded"
  if (phase === "empty") return state && state.selectedMissing ? "Requested item is absent" : "No matching items"
  if (phase === "missing") return "Files provider is not registered"
  if (phase === "unavailable") return "Files state is unavailable"
  if (phase === "denied") return "Files read was denied"
  if (phase === "interrupted") return "Files read was interrupted"
  if (phase === "stale") return "Files state is stale"
  if (phase === "failed") return "Files read failed"
  return "Fabric is offline"
}

function stateExplanation(state) {
  if (!state) return ""
  if (state.error && state.error.explanation) return clippedText(state.error.explanation, 1000)
  if (state.phase === "catalog-loading") return "Files is checking the exact code-owned provider generation before reading a route."
  if (state.phase === "loading") return "Only bounded location-relative metadata is being read; file contents are never requested."
  if (state.phase === "partial") return "The provider or this surface reached a declared result bound. No omitted records are inferred."
  if (state.phase === "degraded") return state.reasons.length > 0 ? clippedText(state.reasons[0].explanation, 1000) : "Trusted read state is visible, while host mutations remain unavailable."
  if (state.phase === "empty") return state.selectedMissing ? "The exact deep-linked identity was not present in this revision." : "The provider returned a valid empty result."
  if (state.phase === "missing") return "The code-owned files.provider identity was not present in the current catalog."
  if (state.phase === "unavailable") return "The provider reported no trusted readable state for this route."
  if (state.phase === "ready") return "Every visible record comes from the current files.provider revision."
  return "Connect to the owner-scoped Fabric daemon to read Files state."
}

function phaseTone(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "ready" || phase === "empty") return "success"
  if (phase === "failed" || phase === "denied" || phase === "unavailable") return "danger"
  return "warning"
}

if (typeof module !== "undefined") module.exports = {
  ROUTES: ROUTES, queryForRoute: queryForRoute, requestParameters: requestParameters,
  normalizedSelection: normalizedSelection, catalogEntry: catalogEntry, normalizeResult: normalizeResult,
  baseState: baseState, createController: createController, stateTitle: stateTitle,
  stateExplanation: stateExplanation, phaseTone: phaseTone
}
