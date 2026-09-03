var CATALOG_METHOD = "provider.catalog"
var READ_METHOD = "provider.read"
var PROVIDER_ID = "files.provider"
var MAX_CATALOG_ENTRIES = 128
var MAX_SOURCE_RECORDS = 256
var MAX_VISIBLE_RECORDS = 96
var MAX_TEXT = 480
var PLACE_LOCATION_ORDER = {
  "files.location.home": 0,
  "files.location.desktop": 1,
  "files.location.documents": 2,
  "files.location.downloads": 3,
  "files.location.pictures": 4,
  "files.location.music": 5,
  "files.location.videos": 6
}

var ROUTES = [
  { routeId: "files.overview", action: "inspect", capability: "files.inspect", kind: "overview", arguments: {} },
  { routeId: "files.this-pc", action: "inspect", capability: "files.inspect", kind: "this-pc", arguments: {} },
  { routeId: "files.desktop", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.desktop", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.documents", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.documents", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.downloads", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.downloads", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.pictures", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.pictures", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.music", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.music", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.videos", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.videos", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.recent", action: "recent", capability: "files.recent.read", kind: "entries", arguments: { limit: 96 } },
  { routeId: "files.search", action: "search", capability: "files.search", kind: "entries", arguments: null },
  { routeId: "files.trash", action: "browse", capability: "files.browse", kind: "entries", arguments: { locationId: "files.location.trash", relativePath: "", includeHidden: false, limit: 96 } },
  { routeId: "files.network", action: "inspect", capability: "files.inspect", kind: "network", arguments: {} }
]

var CREATE_LOCATIONS = [
  "files.location.desktop", "files.location.documents", "files.location.downloads", "files.location.pictures",
  "files.location.music", "files.location.videos"
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

function createLocationForRoute(routeId) {
  var query = queryForRoute(routeId)
  if (!query || !query.arguments || !query.arguments.locationId) return ""
  return CREATE_LOCATIONS.indexOf(query.arguments.locationId) >= 0 ? query.arguments.locationId : ""
}

function isTrashRoute(routeId) {
  return String(routeId || "") === "files.trash"
}

function createNameRefusal(name) {
  var value = String(name === null || name === undefined ? "" : name)
  if (value.length === 0) return "Enter a folder name."
  if (value.length > 255) return "Folder names stop at 255 characters."
  if (value === "." || value === "..") return "That name is reserved by the filesystem."
  if (value.indexOf("/") >= 0 || value.indexOf("\\") >= 0) return "Folder names cannot contain a path separator."
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code < 32 || code === 127) return "Folder names cannot contain control characters."
  }
  return ""
}

function nextCopyName(taken, sourceName) {
  var names = taken && typeof taken === "object" ? taken : {}
  var base = String(sourceName === null || sourceName === undefined ? "" : sourceName)
  if (createNameRefusal(base) !== "") return ""
  if (!names[base.toLowerCase()]) return base
  var ext = ""
  var stem = base
  var dot = base.lastIndexOf(".")
  if (dot > 0) {
    ext = base.slice(dot)
    stem = base.slice(0, dot)
  }
  for (var n = 2; n < 512; n++) {
    var candidate = stem + " (" + n + ")" + ext
    if (!names[candidate.toLowerCase()] && createNameRefusal(candidate) === "") return candidate
  }
  return ""
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

function browsesEntries(query) {
  return !!query && query.kind === "entries" && query.action === "browse"
}

function normalizedRelativePath(value) {
  var text = String(value === null || value === undefined ? "" : value)
  if (text === "") return ""
  if (text.length > 512) throw new Error("The Files relative path is too long.")
  if (/[\u0000-\u001f\u007f]/.test(text)) throw new Error("The Files relative path holds a control character.")
  if (text.charAt(0) === "/" || text.charAt(text.length - 1) === "/") throw new Error("The Files relative path is not bounded to its location.")
  var parts = text.split("/")
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "" || parts[i] === "." || parts[i] === "..") throw new Error("The Files relative path is not bounded to its location.")
  }
  return text
}

function normalizedSelection(query, argumentsValue) {
  var args = isObject(argumentsValue) ? argumentsValue : {}
  var allowed = query && query.routeId === "files.search" ? { query: true, entityType: true, entityId: true }
    : query && (query.routeId === "files.overview" || query.routeId === "files.network") ? { entityType: true, entityId: true }
    : browsesEntries(query) ? { relativePath: true }
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
  var relative = hasOwn(args, "relativePath") ? normalizedRelativePath(args.relativePath) : ""
  return { entityType: entityType, entityId: entityId, searchQuery: search, relativePath: relative }
}

function baseState(routeId, argumentsValue, phase) {
  var query = queryForRoute(routeId)
  var selection = { entityType: "", entityId: "", searchQuery: "", relativePath: "" }
  var error = null
  if (!query) error = responseError("The route is not in the closed Files map.")
  else {
    try { selection = normalizedSelection(query, argumentsValue) }
    catch (problem) { error = responseError(String(problem)) }
  }
  return {
    routeId: String(routeId || ""), query: query,
    entityType: selection.entityType, entityId: selection.entityId, searchQuery: selection.searchQuery,
    relativePath: selection.relativePath,
    phase: error ? "failed" : String(phase || "offline"), requestId: "", providerEntry: null,
    records: [], totalRecords: 0, clipped: false, truncated: false, selectedMissing: false,
    availability: "unknown", revision: "", observedAt: null, providerGeneration: 0,
    error: error, reasons: []
  }
}

function routeArguments(state) {
  var result = {}
  if (state.query && state.query.routeId === "files.search" && state.searchQuery !== "") result.query = state.searchQuery
  if (browsesEntries(state.query) && state.relativePath !== "") result.relativePath = state.relativePath
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

function isIdleSearch(state) {
  return !!(state && state.query && state.query.routeId === "files.search" && state.searchQuery === "")
}

function idleSearchState(previous) {
  var next = cloneState(previous)
  next.phase = "empty"
  next.requestId = ""
  next.records = []
  next.totalRecords = 0
  next.clipped = false
  next.truncated = false
  next.selectedMissing = false
  next.error = null
  next.reasons = []
  return next
}

function requestArguments(state) {
  var query = state.query
  if (query.routeId === "files.search") {
    if (state.searchQuery === "") throw new Error("Files search requires a non-empty query.")
    return { query: state.searchQuery, locationIds: [], includeHidden: false, limit: 96 }
  }
  var source = query.arguments || {}
  var result = {}
  var keys = Object.keys(source)
  for (var i = 0; i < keys.length; i++) result[keys[i]] = source[keys[i]]
  if (browsesEntries(query) && state.relativePath !== "") result.relativePath = state.relativePath
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
  return exactKeys(location, ["id", "kind", "label", "state", "writable", "rootDigest", "reason"]) && stableId(location.id) &&
    ["this-pc", "home", "desktop", "documents", "downloads", "pictures", "music", "videos", "trash", "mount", "network"].indexOf(location.kind) >= 0 &&
    typeof location.label === "string" && location.label.length >= 1 && location.label.length <= 160 &&
    ["available", "degraded", "unavailable"].indexOf(location.state) >= 0 && typeof location.writable === "boolean" && revision(location.rootDigest) &&
    (location.reason === null || validReason(location.reason))
}

function validTrash(trash) {
  return trash === null || (exactKeys(trash, ["originalLocationId", "originalParentId", "originalRelativePath"]) &&
    stableId(trash.originalLocationId) && (trash.originalParentId === null || stableId(trash.originalParentId)) &&
    typeof trash.originalRelativePath === "string" && trash.originalRelativePath.length >= 1 && trash.originalRelativePath.length <= 1024)
}

function validEntry(entry) {
  return exactKeys(entry, ["id", "locationId", "parentId", "name", "relativePath", "kind", "sizeBytes", "modifiedMs", "mimeType", "hidden", "writable", "identity", "symlinkTargetState", "trash"]) &&
    stableId(entry.id) && stableId(entry.locationId) && (entry.parentId === null || stableId(entry.parentId)) && typeof entry.name === "string" && entry.name.length >= 1 && entry.name.length <= 255 &&
    typeof entry.relativePath === "string" && entry.relativePath.length >= 1 && entry.relativePath.length <= 1024 && ["file", "directory", "symlink"].indexOf(entry.kind) >= 0 &&
    (entry.sizeBytes === null || (Number.isSafeInteger(entry.sizeBytes) && entry.sizeBytes >= 0)) && (entry.modifiedMs === null || (Number.isSafeInteger(entry.modifiedMs) && entry.modifiedMs >= 0)) &&
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
  return exactKeys(mount, ["id", "kind", "label", "state", "writable", "locationId", "source", "totalBytes", "freeBytes", "reason"]) && stableId(mount.id) &&
    ["system", "removable", "smb"].indexOf(mount.kind) >= 0 && typeof mount.label === "string" && mount.label.length >= 1 && mount.label.length <= 160 &&
    ["mounted", "unmounted", "degraded", "unavailable"].indexOf(mount.state) >= 0 && typeof mount.writable === "boolean" &&
    (mount.locationId === null || stableId(mount.locationId)) && isObject(mount.source) && validMountSource(mount.source) &&
    (mount.totalBytes === null || (Number.isSafeInteger(mount.totalBytes) && mount.totalBytes >= 0)) &&
    (mount.freeBytes === null || (Number.isSafeInteger(mount.freeBytes) && mount.freeBytes >= 0)) &&
    (mount.reason === null || validReason(mount.reason))
}

function validRecent(recent) {
  return exactKeys(recent, ["entryId", "rank"]) && stableId(recent.entryId) && Number.isInteger(recent.rank) && recent.rank >= 0 && recent.rank <= 127
}

var TYPE_LABELS = {
  txt: "Text Document", log: "Text Document", ini: "Configuration Settings", cfg: "Configuration Settings",
  conf: "Configuration Settings", toml: "TOML File", yml: "YAML File", yaml: "YAML File", json: "JSON File",
  xml: "XML Document", html: "HTML Document", htm: "HTML Document", css: "Cascading Style Sheet Document",
  js: "JavaScript File", qml: "QML File", py: "Python File", sh: "Shell Script", bash: "Shell Script",
  md: "Markdown Document", pdf: "Adobe Acrobat Document", doc: "Microsoft Word Document",
  docx: "Microsoft Word Document", xls: "Microsoft Excel Worksheet", xlsx: "Microsoft Excel Worksheet",
  ppt: "Microsoft PowerPoint Presentation", pptx: "Microsoft PowerPoint Presentation",
  png: "PNG Image", jpg: "JPEG Image", jpeg: "JPEG Image", gif: "GIF Image", bmp: "Bitmap Image",
  svg: "SVG Document", webp: "WebP Image", ico: "Icon", mp3: "MP3 File", wav: "Wave Sound",
  flac: "FLAC File", ogg: "OGG File", mp4: "MP4 Video", mkv: "Matroska Video", webm: "WebM Video",
  avi: "Video Clip", mov: "QuickTime Movie", zip: "Compressed (zipped) Folder", gz: "GZ File",
  xz: "XZ File", tar: "TAR File", bz2: "BZ2 File", "7z": "7Z File", rar: "RAR File",
  iso: "Disc Image File", exe: "Application", dll: "Application Extension", desktop: "Shortcut",
  ttf: "TrueType Font File", otf: "OpenType Font File", deb: "DEB File", rpm: "RPM File",
  pkg: "PKG File", zst: "ZST File", sig: "SIG File", lock: "LOCK File"
}

var MONTH_DAY_CLOCK = 12

function extensionOf(name) {
  var text = String(name || "")
  var dot = text.lastIndexOf(".")
  if (dot <= 0 || dot === text.length - 1) return ""
  return text.slice(dot + 1).toLowerCase()
}

function typeLabelFor(name, kind, mimeType) {
  if (kind === "directory") return "File folder"
  if (kind === "symlink") return "Shortcut"
  var extension = extensionOf(name)
  if (extension === "") return "File"
  if (hasOwn(TYPE_LABELS, extension)) return TYPE_LABELS[extension]
  if (typeof mimeType === "string" && mimeType.indexOf("text/") === 0) return extension.toUpperCase() + " File"
  return extension.toUpperCase() + " File"
}

function groupedDigits(value) {
  var text = String(value)
  var out = ""
  var count = 0
  for (var i = text.length - 1; i >= 0; i--) {
    out = text.charAt(i) + out
    count++
    if (count % 3 === 0 && i > 0) out = "," + out
  }
  return out
}

function formatSize(sizeBytes) {
  if (sizeBytes === null || sizeBytes === undefined) return ""
  var bytes = Number(sizeBytes)
  if (!isFinite(bytes) || bytes < 0) return ""
  return groupedDigits(Math.ceil(bytes / 1024)) + " KB"
}

function formatModified(modifiedMs) {
  if (modifiedMs === null || modifiedMs === undefined) return ""
  var milliseconds = Number(modifiedMs)
  if (!isFinite(milliseconds) || milliseconds <= 0) return ""
  var moment = new Date(milliseconds)
  var hours = moment.getHours()
  var suffix = hours >= MONTH_DAY_CLOCK ? "PM" : "AM"
  var display = hours % MONTH_DAY_CLOCK
  if (display === 0) display = MONTH_DAY_CLOCK
  var minutes = moment.getMinutes()
  var padded = minutes < 10 ? "0" + minutes : String(minutes)
  return (moment.getMonth() + 1) + "/" + moment.getDate() + "/" + moment.getFullYear() + " " + display + ":" + padded + " " + suffix
}

function explorerEntries(records) {
  var result = []
  if (!Array.isArray(records)) return result
  for (var i = 0; i < records.length; i++) if (records[i] && records[i].kind === "entry") result.push(records[i])
  return result
}

function explorerLocations(records) {
  var result = []
  if (!Array.isArray(records)) return result
  for (var i = 0; i < records.length; i++) if (records[i] && records[i].kind === "location") result.push(records[i])
  return result
}

function explorerMounts(records) {
  var result = []
  if (!Array.isArray(records)) return result
  for (var i = 0; i < records.length; i++) if (records[i] && records[i].kind === "mount") result.push(records[i])
  return result
}

function compareText(left, right) {
  var a = String(left || "").toLowerCase()
  var b = String(right || "").toLowerCase()
  if (a < b) return -1
  if (a > b) return 1
  return 0
}

function sortedEntries(records, column, ascending) {
  var items = explorerEntries(records).slice()
  var key = String(column || "name")
  var direction = ascending === false ? -1 : 1
  items.sort(function (left, right) {
    var leftFolder = left.entryKind === "directory" ? 0 : 1
    var rightFolder = right.entryKind === "directory" ? 0 : 1
    if (leftFolder !== rightFolder) return leftFolder - rightFolder
    var outcome = 0
    if (key === "size") outcome = (Number(left.sizeBytes) || 0) - (Number(right.sizeBytes) || 0)
    else if (key === "modified") outcome = (Number(left.modifiedMs) || 0) - (Number(right.modifiedMs) || 0)
    else if (key === "type") outcome = compareText(left.typeLabel, right.typeLabel)
    else outcome = compareText(left.title, right.title)
    if (outcome === 0) outcome = compareText(left.title, right.title)
    return outcome * direction
  })
  return items
}

function breadcrumbFor(routeTitle, relativePath) {
  var crumbs = [{ label: String(routeTitle || "Files"), relativePath: "" }]
  var text = String(relativePath || "")
  if (text === "") return crumbs
  var parts = text.split("/")
  var walked = ""
  for (var i = 0; i < parts.length; i++) {
    walked = walked === "" ? parts[i] : walked + "/" + parts[i]
    crumbs.push({ label: parts[i], relativePath: walked })
  }
  return crumbs
}

function childRelativePath(current, name) {
  var base = String(current || "")
  var leaf = String(name || "")
  if (leaf === "") return base
  return base === "" ? leaf : base + "/" + leaf
}

function parentRelativePath(current) {
  var text = String(current || "")
  if (text === "") return ""
  var cut = text.lastIndexOf("/")
  return cut < 0 ? "" : text.slice(0, cut)
}

var LOCATION_LABELS = {
  "files.location.home": "Home",
  "files.location.desktop": "Desktop",
  "files.location.documents": "Documents",
  "files.location.downloads": "Downloads",
  "files.location.pictures": "Pictures",
  "files.location.music": "Music",
  "files.location.videos": "Videos",
  "files.location.trash": "Recycle Bin"
}

function locationLabelFor(locationId, relativePath) {
  var base = hasOwn(LOCATION_LABELS, locationId) ? LOCATION_LABELS[locationId] : "This computer"
  var parent = parentRelativePath(relativePath)
  if (parent === "") return base
  return base + " › " + parent.split("/").join(" › ")
}

function entryRecord(entry, index) {
  if (!isObject(entry) || !validEntry(entry)) return null
  var details = [detail("Type of file", typeLabelFor(entry.name, entry.kind, entry.mimeType)), detail("Location", locationLabelFor(entry.locationId, entry.relativePath))]
  if (entry.sizeBytes !== null && entry.sizeBytes !== undefined) details.push(detail("Size", formatCapacity(entry.sizeBytes) + " (" + groupedDigits(entry.sizeBytes) + " bytes)"))
  if (entry.modifiedMs !== null && entry.modifiedMs !== undefined) details.push(detail("Modified", formatModified(entry.modifiedMs)))
  details.push(detail("Read-only", entry.writable === true ? "No" : "Yes"))
  if (entry.symlinkTargetState) details.push(detail("Symlink target", entry.symlinkTargetState))
  if (isObject(entry.trash)) {
    details.push(detail("Original location", entry.trash.originalLocationId))
    details.push(detail("Original path", entry.trash.originalRelativePath))
  }
  return {
    id: entry.id, kind: "entry", title: clippedText(entry.name, 240), subtitle: clippedText(entry.relativePath, 320),
    status: entry.kind, tone: entry.kind === "symlink" ? "warning" : "neutral", details: details, order: index,
    entryKind: entry.kind, locationId: entry.locationId, parentId: entry.parentId, relativePath: entry.relativePath,
    sizeBytes: entry.sizeBytes, modifiedMs: entry.modifiedMs, mimeType: entry.mimeType, hidden: entry.hidden,
    writable: entry.writable, typeLabel: typeLabelFor(entry.name, entry.kind, entry.mimeType),
    sizeText: entry.kind === "file" ? formatSize(entry.sizeBytes) : "", modifiedText: formatModified(entry.modifiedMs)
  }
}

function locationEntryCount(entries, locationId) {
  var count = 0
  for (var i = 0; i < entries.length; i++) if (entries[i].locationId === locationId) count++
  return count
}

function placeEntries(entries) {
  var selected = []
  for (var i = 0; i < entries.length; i++) {
    if (!hasOwn(PLACE_LOCATION_ORDER, entries[i].locationId)) continue
    selected.push(entries[i])
  }
  selected.sort(function (left, right) {
    var leftOrder = PLACE_LOCATION_ORDER[left.locationId]
    var rightOrder = PLACE_LOCATION_ORDER[right.locationId]
    if (leftOrder !== rightOrder) return leftOrder - rightOrder
    if (left.id < right.id) return -1
    if (left.id > right.id) return 1
    return 0
  })
  return selected
}

function locationRecord(location, index) {
  if (!isObject(location) || !validLocation(location)) return null
  var details = [detail("Kind", location.kind), detail("Writable", location.writable === true ? "Yes" : "No"), detail("Root revision", location.rootDigest)]
  if (isObject(location.reason)) details.push(detail("Reason", location.reason.explanation || location.reason.title))
  return {
    id: location.id, kind: "location", title: clippedText(location.label, 240), subtitle: clippedText(location.kind, 160),
    status: location.state, tone: location.state === "available" ? "success" : location.state === "degraded" ? "warning" : "danger",
    details: details, order: index, locationKind: location.kind, writable: location.writable === true, rootDigest: location.rootDigest
  }
}

function formatCapacity(bytes) {
  if (bytes === null || bytes === undefined) return ""
  var value = Number(bytes)
  if (!isFinite(value) || value < 0) return ""
  var units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
  var index = 0
  while (value >= 1024 && index < units.length - 1) {
    value = value / 1024
    index++
  }
  var rounded = index === 0 ? String(Math.round(value)) : value.toFixed(value < 10 ? 2 : 1)
  return rounded + " " + units[index]
}

function capacityText(totalBytes, freeBytes) {
  if (totalBytes === null || totalBytes === undefined || freeBytes === null || freeBytes === undefined) return ""
  return formatCapacity(freeBytes) + " free of " + formatCapacity(totalBytes)
}

function usedFraction(totalBytes, freeBytes) {
  if (totalBytes === null || totalBytes === undefined || freeBytes === null || freeBytes === undefined) return -1
  var total = Number(totalBytes)
  if (!isFinite(total) || total <= 0) return -1
  var used = total - Number(freeBytes)
  if (!isFinite(used) || used < 0) return -1
  return Math.max(0, Math.min(1, used / total))
}

function mountRecord(mount, index) {
  if (!isObject(mount) || !validMount(mount)) return null
  var source = mount.source
  var display = source.scheme === "smb" ? (source.host || "network") + "/" + (source.share || "share") : source.display
  var details = [detail("Kind", mount.kind), detail("Source", display), detail("Writable", mount.writable === true ? "Yes" : "No"), detail("Location", mount.locationId)]
  if (isObject(mount.reason)) details.push(detail("Reason", mount.reason.explanation || mount.reason.title))
  return {
    id: mount.id, kind: "mount", title: clippedText(mount.label, 240), subtitle: clippedText(display, 320),
    status: clippedText(mount.state, 80), tone: mount.state === "mounted" ? "success" : mount.state === "degraded" ? "warning" : "danger",
    details: details, order: index, mountKind: mount.kind, mountState: mount.state, locationId: mount.locationId,
    writable: mount.writable === true, display: clippedText(display, 320),
    totalBytes: mount.totalBytes, freeBytes: mount.freeBytes,
    capacityText: capacityText(mount.totalBytes, mount.freeBytes),
    usedFraction: usedFraction(mount.totalBytes, mount.freeBytes)
  }
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
        var shownLocations = []
        for (var i = 0; i < locations.length; i++) {
          if (state.query.kind === "this-pc" && ["network", "trash"].indexOf(locations[i].kind) >= 0) continue
          shownLocations.push(locations[i])
        }
        shownLocations.sort(function (left, right) {
          var leftOrder = hasOwn(PLACE_LOCATION_ORDER, left.id) ? PLACE_LOCATION_ORDER[left.id] : 50
          var rightOrder = hasOwn(PLACE_LOCATION_ORDER, right.id) ? PLACE_LOCATION_ORDER[right.id] : 50
          if (leftOrder !== rightOrder) return leftOrder - rightOrder
          if (left.id < right.id) return -1
          if (left.id > right.id) return 1
          return 0
        })
        for (var loc = 0; loc < shownLocations.length; loc++) {
          var location = locationRecord(shownLocations[loc], records.length)
          if (!location) return { error: "A Files location is invalid." }
          location.details.push(detail("Entries", String(locationEntryCount(value.state.entries, shownLocations[loc].id))))
          records.push(location)
        }
        for (var j = 0; j < mounts.length; j++) {
          if (state.query.kind === "this-pc" && ["system", "removable"].indexOf(mounts[j].kind) < 0) continue
          var mount = mountRecord(mounts[j], records.length)
          if (!mount) return { error: "A Files mount is invalid." }
          records.push(mount)
        }
        var placed = placeEntries(value.state.entries)
        for (var p = 0; p < placed.length; p++) {
          var item = entryRecord(placed[p], records.length)
          if (!item) return { error: "A Files entry is invalid." }
          records.push(item)
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

function locationById(locations, locationId) {
  if (!Array.isArray(locations)) return null
  for (var i = 0; i < locations.length; i++) if (locations[i].id === locationId) return locations[i]
  return null
}

function pageAvailability(query, value) {
  var availability = value.availability
  if (query.kind !== "this-pc" || value.action !== "inspect" || !isObject(value.state)) return availability
  if (availability.state === "unavailable" || availability.read === false) return availability
  var thisPc = locationById(value.state.locations, "files.location.this-pc")
  if (!thisPc) return availability
  if (thisPc.state === "available") return { state: "available", read: true, operation: false, reasons: [] }
  var reasons = isObject(thisPc.reason) ? [thisPc.reason] : []
  if (thisPc.state === "degraded") return { state: "degraded", read: true, operation: false, reasons: reasons }
  return { state: "unavailable", read: false, operation: false, reasons: reasons }
}

function acceptedState(previous, result) {
  var normalized = normalizeResult(previous, result)
  if (normalized.error) return failureState(previous, responseError(normalized.error))
  var page = pageAvailability(previous.query, normalized.value)
  var next = cloneState(previous)
  next.records = normalized.records
  next.totalRecords = normalized.totalRecords
  next.clipped = normalized.clipped
  next.truncated = normalized.truncated
  next.selectedMissing = normalized.selectedMissing
  next.availability = page.state
  next.revision = normalized.value.revision || ""
  next.observedAt = normalized.observedAt
  next.requestId = ""
  next.error = null
  next.reasons = copyArray(page.reasons)
  if (page.state === "unavailable" || page.read === false) next.phase = "unavailable"
  else if (normalized.truncated || normalized.clipped) next.phase = "partial"
  else if (page.state === "degraded") next.phase = "degraded"
  else if (normalized.records.length === 0) next.phase = "empty"
  else if (page.state === "available") next.phase = "available"
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
  if (isIdleSearch(this.state)) { this._setState(idleSearchState(this.state)); return true }
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
  if (isIdleSearch(next)) { this._setState(idleSearchState(next)); return true }
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
  if (phase === "ready" || phase === "available") return "Current file metadata"
  if (phase === "partial") return "Partial bounded results"
  if (phase === "degraded") return "Files is read-only or degraded"
  if (phase === "empty") {
    if (isIdleSearch(state)) return "Type a search query"
    return state && state.selectedMissing ? "Requested item is absent" : "No matching items"
  }
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
  if (state.phase === "empty") {
    if (isIdleSearch(state)) return "Enter a query to search trusted file names and relative paths. File contents are never read."
    return state.selectedMissing ? "The exact deep-linked identity was not present in this revision." : "The provider returned a valid empty result."
  }
  if (state.phase === "missing") return "The code-owned files.provider identity was not present in the current catalog."
  if (state.phase === "unavailable") return "The provider reported no trusted readable state for this route."
  if (state.phase === "ready" || state.phase === "available") return "Every visible record comes from the current files.provider revision."
  return "Connect to the owner-scoped Fabric daemon to read Files state."
}

function phaseTone(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "ready" || phase === "available" || phase === "empty") return "success"
  if (phase === "failed" || phase === "denied" || phase === "unavailable") return "danger"
  return "warning"
}

if (typeof module !== "undefined") module.exports = {
  ROUTES: ROUTES, queryForRoute: queryForRoute, requestParameters: requestParameters,
  normalizedSelection: normalizedSelection, catalogEntry: catalogEntry, normalizeResult: normalizeResult,
  baseState: baseState, createController: createController, isIdleSearch: isIdleSearch,
  stateTitle: stateTitle, stateExplanation: stateExplanation, phaseTone: phaseTone,
  CREATE_LOCATIONS: CREATE_LOCATIONS, createLocationForRoute: createLocationForRoute,
  createNameRefusal: createNameRefusal, nextCopyName: nextCopyName, isTrashRoute: isTrashRoute,
  typeLabelFor: typeLabelFor, formatSize: formatSize, formatModified: formatModified,
  explorerEntries: explorerEntries, explorerLocations: explorerLocations, explorerMounts: explorerMounts,
  sortedEntries: sortedEntries, breadcrumbFor: breadcrumbFor, childRelativePath: childRelativePath,
  formatCapacity: formatCapacity, capacityText: capacityText, usedFraction: usedFraction,
  parentRelativePath: parentRelativePath, normalizedRelativePath: normalizedRelativePath, extensionOf: extensionOf
}
