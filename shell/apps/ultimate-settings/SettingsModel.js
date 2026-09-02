var CATALOG_METHOD = "provider.catalog"
var READ_METHOD = "provider.read"
var OVERVIEW_ROUTE = "settings.overview"
var MAX_CATALOG_ENTRIES = 128
var MAX_SOURCE_RECORDS = 256
var MAX_VISIBLE_RECORDS = 96
var MAX_VISIBLE_FIELDS = 18
var MAX_DISPLAY_TEXT = 480

var ROUTE_QUERIES = [
  {
    routeId: "settings.display.overview",
    title: "Display",
    providerId: "display.provider",
    action: "inspect",
    capability: "display.inspect",
    supportsResource: true,
    coverage: "Display inventory is readable from display.inspect (connector, mode, scale, position), and brightness applies through display.provider brightness.set on outputs that expose a controllable backlight. Resolution, scale, and arrangement changes remain unavailable from Settings. Night light remains a Superbar leftover, not a Settings LIVE writer."
  },
  {
    routeId: "settings.audio.overview",
    title: "Sound",
    providerId: "audio.provider",
    action: "inspect",
    capability: "audio.inspect",
    supportsResource: true,
    coverage: "Audio output inventory is readable from audio.inspect (sink, default, mute, channel volume, ports). Output volume applies through the durable operation service as this user. Routing, mute, and port changes remain unavailable from Settings."
  },
  {
    routeId: "settings.network.overview",
    title: "Network & internet",
    providerId: "network.provider",
    action: "inspect",
    capability: "network.inspect",
    supportsResource: true,
    coverage: "Network inventory is readable from network.inspect (Wi-Fi radio, interfaces, connection status), and the Wi-Fi radio switches through network.provider wifi.set-enabled. Joining a network and per-connection changes remain unavailable from Settings."
  },
  {
    routeId: "settings.power.overview",
    title: "Power & battery",
    providerId: "power.provider",
    action: "inspect",
    capability: "power.inspect",
    supportsResource: true,
    coverage: "Power inventory is readable from power.inspect (AC/battery source, active profile, available profiles, battery percentage). The profile.set write plane exists, but Settings does not offer LIVE profile mutation: the fabric daemon runs under app.slice without a login session scope, so polkit allow_active cannot authorize org.freedesktop.UPower.PowerProfiles.switch-profile. Sleep, lock, and lid changes remain unavailable from Settings."
  },
  {
    routeId: "settings.bluetooth.overview",
    title: "Bluetooth & devices",
    providerId: "bluetooth.provider",
    action: "inspect",
    capability: "bluetooth.inspect",
    supportsResource: true,
    coverage: "Bluetooth inventory is readable from bluetooth.inspect (controller power, discovering, paired and connected devices). Discovery, pairing, and connection changes remain unavailable from Settings."
  },
  {
    routeId: "settings.input.overview",
    title: "Input",
    providerId: "input.provider",
    action: "inspect",
    capability: "input.inspect",
    supportsResource: true,
    coverage: "Keyboard inventory and layout state are readable, and the active layout applies through input.provider keyboard-layout.set on keyboards that carry more than one layout. Pointer, repeat rate, and accessibility input changes remain unavailable from Settings."
  },
  {
    routeId: "settings.personalization.overview",
    title: "Personalization",
    providerId: "personalization.provider",
    action: "inspect",
    capability: "personalization.inspect",
    supportsResource: false,
    coverage: "Settings hosts the existing image picker for theme packs and wallpapers. No code-owned personalization.provider is registered. Density, cursor, motion, and a typed full theme service remain unavailable from Settings."
  },
  {
    routeId: "settings.apps.overview",
    title: "Apps",
    providerId: "defaults.provider",
    action: "inspect",
    capability: "defaults.inspect",
    supportsResource: true,
    coverage: "Default applications and associations are readable through defaults.inspect, including MIME inventory. The default browser applies through defaults.provider protocol.set. The mime.set write plane exists. Settings does not offer MIME LIVE CONTROL. Other associations, startup, and background application inventory remain unavailable from Settings."
  },
  {
    routeId: "settings.accessibility.overview",
    title: "Accessibility",
    providerId: "accessibility.provider",
    action: "inspect",
    capability: "accessibility.inspect",
    supportsResource: false,
    coverage: "No code-owned accessibility provider is registered. Accessibility preferences are not inferred from unrelated shell state."
  },
  {
    routeId: "settings.update.overview",
    title: "Update",
    providerId: "update.provider",
    action: "inspect",
    capability: "update.inspect",
    supportsResource: false,
    coverage: "Update availability and lifecycle state are readable. Download, apply, checkpoint, restart, and reboot controls remain unavailable from Settings."
  },
  {
    routeId: "settings.recovery.overview",
    title: "Recovery",
    providerId: "recovery.provider",
    action: "inspect",
    capability: "recovery.inspect",
    supportsResource: true,
    coverage: "Restore-point inventory is readable. Restore planning and execution remain unavailable from Settings."
  },
  {
    routeId: "settings.system.overview",
    title: "System information",
    providerId: "system-information.provider",
    action: "inspect",
    capability: "system-information.inspect",
    supportsResource: false,
    coverage: "No code-owned aggregate system-information provider is registered. Settings does not assemble an unofficial substitute from direct commands."
  }]

var LIVE_WRITER_ROUTES = [
  "settings.audio.overview",
  "settings.network.overview",
  "settings.display.overview",
  "settings.input.overview",
  "settings.apps.overview"
]

function routeHasLiveWriter(routeId) {
  return LIVE_WRITER_ROUTES.indexOf(String(routeId || "")) >= 0
}

function coverageBadge(routeId) {
  return routeHasLiveWriter(routeId) ? "PARTIAL LIVE CONTROL" : "CHANGES UNAVAILABLE"
}

function coverageTone(routeId) {
  return routeHasLiveWriter(routeId) ? "info" : "warning"
}

function declaredOpsHonesty(routeId) {
  return routeHasLiveWriter(routeId)
    ? "Settings runs this operation through preflight, approval, and the durable coordinator."
    : "Settings exposes no preflight, approval, or execution control for this domain."
}

function authorityFooter() {
  return "Typed writers run through preflight, approval, and the durable coordinator as this user \u00b7 Sound volume, Network Wi-Fi radio, Display brightness, Input layout, and Apps default browser are LIVE \u00b7 Power profile stays inspect-only because polkit cannot authorize the fabric daemon under app.slice \u00b7 other domains stay inspect-only \u00b7 no direct commands or elevated privilege \u00b7 Open pages re-read when shown and after local writers; out-of-band changes while this window stays focused need F5 or Retry, with no live hardware-key subscription"
}

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
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] !== wanted[i]) return false
  }
  return true
}

function copyArray(value) {
  return Array.isArray(value) ? value.slice() : []
}

function clippedText(value, maximum) {
  var limit = typeof maximum === "number" && maximum > 0 ? Math.floor(maximum) : MAX_DISPLAY_TEXT
  var text = value === null || value === undefined ? "" : String(value)
  text = text.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
  if (text.length <= limit) return text
  return text.slice(0, Math.max(1, limit - 1)) + "\u2026"
}

function stableId(value) {
  return typeof value === "string" && value.length >= 1 && value.length <= 160 &&
    /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/.test(value)
}

function opaqueId(value) {
  return typeof value === "string" && value.length >= 1 && value.length <= 160 &&
    /^[A-Za-z0-9](?:[A-Za-z0-9._:+@/-]{0,159})$/.test(value)
}

function queryForRoute(routeId) {
  var id = String(routeId || "")
  if (id === OVERVIEW_ROUTE) return {
    routeId: OVERVIEW_ROUTE,
    title: "Settings home",
    providerId: "",
    action: "",
    capability: "",
    supportsResource: false,
    coverage: ""
  }
  for (var i = 0; i < ROUTE_QUERIES.length; i++) {
    if (ROUTE_QUERIES[i].routeId === id) return ROUTE_QUERIES[i]
  }
  return null
}

function normalizedSelection(query, argumentsValue) {
  var args = isObject(argumentsValue) ? argumentsValue : {}
  var keys = Object.keys(args)
  for (var i = 0; i < keys.length; i++) {
    if (keys[i] !== "resourceId") throw new Error("The route arguments contain an unsupported selector.")
  }
  var resourceId = hasOwn(args, "resourceId") ? String(args.resourceId || "") : ""
  if (resourceId !== "") {
    if (!query || !query.supportsResource) throw new Error("This Settings route has no resource selector.")
    if (!opaqueId(resourceId)) throw new Error("The Settings resource ID is invalid.")
  }
  return resourceId
}

function requestParameters(query) {
  if (!query || query.providerId === "" || !stableId(query.providerId) || !stableId(query.action))
    throw new Error("The Settings provider query is invalid.")
  return { provider: query.providerId, action: query.action, arguments: {} }
}

function validActionShape(action) {
  return exactKeys(action, [
    "capability", "mode", "risk", "effects", "arguments", "result", "preflight", "state",
    "supportsRollback", "supportsCancellation"
  ]) && stableId(action.capability) && (action.mode === "read" || action.mode === "operation") &&
    typeof action.risk === "string" && Array.isArray(action.effects) && isObject(action.arguments) &&
    isObject(action.result) && typeof action.supportsRollback === "boolean" &&
    typeof action.supportsCancellation === "boolean"
}

function validManifest(manifest) {
  if (!exactKeys(manifest, [
    "schemaVersion", "provider", "providerVersion", "minFabricProtocol", "maxFabricProtocol",
    "capabilities", "actions"
  ])) return false
  if (manifest.schemaVersion !== "v0" || !stableId(manifest.provider) || !stableId(manifest.providerVersion)) return false
  if (!Number.isInteger(manifest.minFabricProtocol) || !Number.isInteger(manifest.maxFabricProtocol)) return false
  if (!Array.isArray(manifest.capabilities) || manifest.capabilities.length < 1 || manifest.capabilities.length > 128) return false
  if (!isObject(manifest.actions)) return false
  var actionNames = Object.keys(manifest.actions)
  if (actionNames.length < 1 || actionNames.length > 128) return false
  var capabilities = Object.create(null)
  for (var i = 0; i < manifest.capabilities.length; i++) {
    if (!stableId(manifest.capabilities[i]) || capabilities[manifest.capabilities[i]]) return false
    capabilities[manifest.capabilities[i]] = true
  }
  for (var j = 0; j < actionNames.length; j++) {
    var name = actionNames[j]
    var action = manifest.actions[name]
    if (!stableId(name) || !validActionShape(action) || !capabilities[action.capability]) return false
  }
  return true
}

function validateCatalogResponse(response) {
  if (!exactKeys(response, ["providers"])) return "The catalog envelope has an unexpected field set."
  if (!Array.isArray(response.providers) || response.providers.length > MAX_CATALOG_ENTRIES)
    return "The provider catalog exceeds its bounded entry contract."
  var providers = Object.create(null)
  var orders = Object.create(null)
  for (var i = 0; i < response.providers.length; i++) {
    var entry = response.providers[i]
    if (!exactKeys(entry, [
      "manifest", "fingerprint", "generation", "registrationOrder", "state", "detail", "registeredAt", "changedAt"
    ])) return "A provider catalog entry has an unexpected field set."
    if (!validManifest(entry.manifest)) return "A provider catalog manifest is invalid."
    if (providers[entry.manifest.provider]) return "The provider catalog contains a duplicate provider."
    if (typeof entry.fingerprint !== "string" || !/^[0-9a-f]{64}$/.test(entry.fingerprint))
      return "A provider catalog fingerprint is invalid."
    if (!Number.isInteger(entry.generation) || entry.generation < 1 ||
        !Number.isInteger(entry.registrationOrder) || entry.registrationOrder < 0)
      return "A provider catalog generation or order is invalid."
    if (orders[entry.registrationOrder]) return "The provider catalog contains a duplicate registration order."
    if (["available", "degraded", "unavailable", "incompatible"].indexOf(entry.state) < 0)
      return "A provider catalog availability state is invalid."
    if (typeof entry.detail !== "string" || entry.detail.length > 500 ||
        typeof entry.registeredAt !== "number" || !isFinite(entry.registeredAt) || entry.registeredAt < 0 ||
        typeof entry.changedAt !== "number" || !isFinite(entry.changedAt) || entry.changedAt < 0)
      return "A provider catalog detail or timestamp is invalid."
    providers[entry.manifest.provider] = true
    orders[entry.registrationOrder] = true
  }
  return ""
}

function providerEntry(catalog, providerId) {
  if (!Array.isArray(catalog)) return null
  for (var i = 0; i < catalog.length; i++) {
    var entry = catalog[i]
    if (entry && entry.manifest && entry.manifest.provider === providerId) return entry
  }
  return null
}

function queryContractError(entry, query) {
  if (!entry || !entry.manifest || entry.manifest.provider !== query.providerId)
    return "The selected provider identity does not match this Settings route."
  var action = entry.manifest.actions && entry.manifest.actions[query.action]
  if (!action) return "The provider does not expose the code-owned inventory action for this route."
  if (!validActionShape(action) || action.mode !== "read" || action.risk !== "read-only" ||
      action.effects.length !== 0 || action.capability !== query.capability || action.preflight !== null ||
      action.state !== null || action.supportsRollback || action.supportsCancellation)
    return "The provider inventory action does not match the closed read-only Settings contract."
  return ""
}

function operationActions(entry) {
  if (!entry || !entry.manifest || !isObject(entry.manifest.actions)) return []
  var names = Object.keys(entry.manifest.actions).sort()
  var result = []
  for (var i = 0; i < names.length; i++) {
    var action = entry.manifest.actions[names[i]]
    if (action && action.mode === "operation") result.push(names[i])
  }
  return result.slice(0, 16)
}

function structuredError(code, title, explanation, detail, recoveryActions) {
  return {
    code: String(code || "settings.failed"),
    title: clippedText(title || "Settings read failed", 160),
    explanation: clippedText(explanation || "Fabric did not return usable provider state.", 1000),
    detail: clippedText(detail || "", 480),
    retryable: true,
    changeState: "none",
    recoveryActions: copyArray(recoveryActions).slice(0, 8)
  }
}

function responseError(detail) {
  return structuredError(
    "settings.invalid-response",
    "Settings rejected provider state",
    "Fabric returned data outside the closed Settings read contract.",
    detail,
    ["fabric.reconnect"]
  )
}

function phaseForError(error) {
  var code = String(error && error.code || "")
  if (code === "rpc.cancelled") return "interrupted"
  if (code === "rpc.timeout" || code === "provider.changed-during-read") return "stale"
  if (code === "daemon.disconnected" || code === "daemon.socket-error") return "offline"
  if (code === "client.method-denied" || code.indexOf("access.") === 0 ||
      code.indexOf("permission.") === 0 || code.indexOf("policy.") === 0 || code === "principal.expired")
    return "denied"
  if (code === "provider.unavailable" || code === "provider.incompatible-version" || code.indexOf("unavailable.") === 0)
    return "unavailable"
  return "failed"
}

function cloneState(state) {
  var copy = {}
  var keys = Object.keys(state || {})
  for (var i = 0; i < keys.length; i++) copy[keys[i]] = state[keys[i]]
  copy.catalog = copyArray(state && state.catalog)
  copy.records = copyArray(state && state.records)
  copy.overviewCards = copyArray(state && state.overviewCards)
  copy.operationActions = copyArray(state && state.operationActions)
  copy.recoveryActions = copyArray(state && state.recoveryActions)
  return copy
}

function baseState(routeId, argumentsValue, phase) {
  var query = queryForRoute(routeId)
  var selected = ""
  var error = null
  if (query) {
    try {
      selected = normalizedSelection(query, argumentsValue)
    } catch (selectionError) {
      error = responseError(String(selectionError))
    }
  } else {
    error = responseError("The requested Settings route is not in the closed route map.")
  }
  return {
    routeId: String(routeId || ""),
    query: query,
    selectedResourceId: selected,
    phase: error ? "failed" : String(phase || "offline"),
    catalog: [],
    catalogReady: false,
    providerEntry: null,
    records: [],
    totalRecords: 0,
    clipped: false,
    selectedMissing: false,
    overviewCards: [],
    operationActions: [],
    payloadAvailability: "unknown",
    observedAt: null,
    requestId: "",
    error: error,
    recoveryActions: error ? copyArray(error.recoveryActions) : []
  }
}

function failureState(previous, errorValue) {
  var next = cloneState(previous)
  var error = isObject(errorValue) ? errorValue : structuredError(
    "settings.failed", "Settings read failed", String(errorValue || "Unknown Fabric failure.")
  )
  next.phase = phaseForError(error)
  next.requestId = ""
  next.records = []
  next.totalRecords = 0
  next.clipped = false
  next.selectedMissing = false
  next.observedAt = null
  next.error = error
  next.recoveryActions = copyArray(error.recoveryActions).slice(0, 8)
  if (next.phase === "offline") {
    next.catalog = []
    next.catalogReady = false
    next.providerEntry = null
    next.overviewCards = []
    next.operationActions = []
  }
  return next
}

function catalogCards(catalog) {
  var cards = []
  for (var i = 0; i < ROUTE_QUERIES.length; i++) {
    var query = ROUTE_QUERIES[i]
    var entry = providerEntry(catalog, query.providerId)
    var status = "not registered"
    var tone = "warning"
    var detail = query.coverage
    if (entry) {
      status = entry.state
      tone = entry.state === "available" ? "success" : entry.state === "degraded" ? "warning" : "danger"
      if ((entry.state === "available" || entry.state === "degraded") && queryContractError(entry, query) !== "") {
        status = "contract mismatch"
        tone = "danger"
        detail = queryContractError(entry, query)
      } else if (entry.detail) {
        detail = clippedText(entry.detail, MAX_DISPLAY_TEXT)
      }
    }
    cards.push({
      routeId: query.routeId,
      title: query.title,
      providerId: query.providerId,
      status: status,
      tone: tone,
      detail: clippedText(detail, MAX_DISPLAY_TEXT)
    })
  }
  return cards
}

function fieldLabel(path) {
  var text = String(path || "").replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[._-]+/g, " ")
  return text.replace(/\b\w/g, function(character) { return character.toUpperCase() })
}

function compactValue(value) {
  if (value === null || value === undefined) return "Not reported"
  if (typeof value === "boolean") return value ? "Yes" : "No"
  if (typeof value === "string" || typeof value === "number") return clippedText(value)
  if (Array.isArray(value)) {
    var simple = true
    for (var i = 0; i < value.length; i++) {
      if (value[i] !== null && typeof value[i] === "object") simple = false
    }
    if (simple) return clippedText(value.join(", "))
  }
  try {
    return clippedText(JSON.stringify(value))
  } catch (_) {
    return "Unrepresentable structured value"
  }
}

function detailFields(value, excluded) {
  var fields = []
  var blocked = excluded || {}
  function append(label, candidate) {
    if (fields.length >= MAX_VISIBLE_FIELDS) return
    fields.push({ label: fieldLabel(label), value: compactValue(candidate) })
  }
  function walk(candidate, prefix, depth) {
    if (fields.length >= MAX_VISIBLE_FIELDS || !isObject(candidate)) return
    var keys = Object.keys(candidate).sort()
    for (var i = 0; i < keys.length && fields.length < MAX_VISIBLE_FIELDS; i++) {
      var key = keys[i]
      if (blocked[key] && prefix === "") continue
      var item = candidate[key]
      var path = prefix === "" ? key : prefix + "." + key
      if (isObject(item) && depth < 1) walk(item, path, depth + 1)
      else append(path, item)
    }
  }
  walk(value, "", 0)
  return fields
}

function resourceStatus(resource) {
  var state = isObject(resource && resource.state) ? resource.state : {}
  if (typeof state.phase === "string") return state.phase
  if (typeof state.status === "string") return state.status
  if (typeof state.health === "string") return state.health
  if (typeof state.state === "string") return state.state
  if (typeof state.enabled === "boolean") return state.enabled ? "enabled" : "disabled"
  if (typeof resource.status === "string") return resource.status
  return "reported"
}

function resourceSubtitle(resource) {
  var state = isObject(resource && resource.state) ? resource.state : {}
  if (typeof state.connection === "string" && state.connection !== "") return state.connection
  if (typeof state.activeProfile === "string") return state.activeProfile + " profile"
  if (typeof state.activeKeymap === "string") return state.activeKeymap
  if (typeof state.availableCount === "number") return state.availableCount + " update" + (state.availableCount === 1 ? "" : "s")
  if (typeof resource.kind === "string") return resource.kind
  return "Provider resource"
}

var POWER_PROFILES = ["power-saver", "balanced", "performance"]

function closedProfiles(state) {
  var available = state && Array.isArray(state.availableProfiles) ? state.availableProfiles : []
  var closed = []
  for (var i = 0; i < available.length; i++) {
    if (POWER_PROFILES.indexOf(available[i]) >= 0 && closed.indexOf(available[i]) < 0) closed.push(available[i])
  }
  return closed
}

function closedActiveProfile(state) {
  var active = state && typeof state.activeProfile === "string" ? state.activeProfile : ""
  return POWER_PROFILES.indexOf(active) >= 0 ? active : ""
}

function brightnessAvailable(state) {
  return !!(state && state.available === true && typeof state.percent === "number" &&
    isFinite(state.percent) && state.percent >= 0 && state.percent <= 100)
}

function brightnessPercent(state) {
  return brightnessAvailable(state) ? Math.round(state.percent) : -1
}

function closedLayouts(state) {
  if (!state || state.switchable !== true || !Array.isArray(state.layouts)) return []
  var layouts = []
  for (var i = 0; i < state.layouts.length && i < 8; i++) {
    var name = state.layouts[i]
    if (typeof name !== "string" || name.length === 0 || name.length > 64) return []
    layouts.push(name)
  }
  return layouts.length > 1 ? layouts : []
}

function closedLayoutIndex(state) {
  var layouts = closedLayouts(state)
  if (layouts.length === 0) return -1
  var active = state.activeIndex
  if (typeof active !== "number" || !isFinite(active)) return -1
  active = Math.round(active)
  return active >= 0 && active < layouts.length ? active : -1
}

function radioControllable(state) {
  return !!(state && typeof state.enabled === "boolean" &&
    state.managerRunning === true && typeof state.hardwareEnabled === "boolean")
}

function radioEnabled(state) {
  return radioControllable(state) ? state.enabled === true : false
}

function radioBlocked(state) {
  return radioControllable(state) && state.hardwareEnabled !== true
}

function normalizeLeafResource(resource, index) {
  if (!isObject(resource)) return null
  var id = typeof resource.id === "string" && resource.id.length <= 160 ? resource.id : ""
  if (id === "") return null
  var state = isObject(resource.state) ? resource.state : {}
  var details = detailFields(state, {})
  var topDetails = detailFields(resource, { id: true, label: true, kind: true, state: true })
  for (var i = 0; i < topDetails.length && details.length < MAX_VISIBLE_FIELDS; i++) details.push(topDetails[i])
  return {
    id: id,
    label: clippedText(resource.label || id, 240),
    kind: clippedText(resource.kind || "provider-resource", 160),
    status: clippedText(resourceStatus(resource), 80),
    subtitle: clippedText(resourceSubtitle(resource), 240),
    details: details,
    profiles: closedProfiles(state),
    radioControllable: radioControllable(state),
    radioEnabled: radioEnabled(state),
    radioBlocked: radioBlocked(state),
    layouts: closedLayouts(state),
    activeLayoutIndex: closedLayoutIndex(state),
    brightnessAvailable: brightnessAvailable(state),
    brightnessPercent: brightnessPercent(state),
    activeProfile: closedActiveProfile(state),
    order: index
  }
}

var BROWSER_SCHEMES = ["http", "https"]

function browserAssociation(records) {
  if (!Array.isArray(records)) return null
  for (var i = 0; i < records.length; i++) {
    if (records[i].associationKind === "protocol" && records[i].associationKey === "https") return records[i]
  }
  return null
}

function browserCandidates(record, records) {
  if (!record || !Array.isArray(record.candidateAppIds) || !Array.isArray(records)) return []
  var out = []
  for (var i = 0; i < record.candidateAppIds.length; i++) {
    var id = record.candidateAppIds[i]
    for (var j = 0; j < records.length; j++) {
      if (records[j].id === id && records[j].kind === "application" && records[j].status === "available") {
        out.push({ id: id, label: clippedText(records[j].label || id, 120) })
        break
      }
    }
  }
  return out
}

function normalizeAssociation(association, index) {
  if (!isObject(association) || typeof association.id !== "string" || association.id.length > 160) return null
  return {
    id: association.id,
    label: clippedText(association.key || association.id, 240),
    kind: clippedText((association.kind || "default") + " association", 160),
    status: clippedText(association.status || "unknown", 80),
    subtitle: clippedText(association.defaultAppId || "No default application", 240),
    details: detailFields(association, { id: true, key: true, kind: true, status: true, defaultAppId: true }),
    associationKind: typeof association.kind === "string" ? association.kind : "",
    associationKey: typeof association.key === "string" ? association.key : "",
    defaultAppId: typeof association.defaultAppId === "string" ? association.defaultAppId : "",
    writable: association.writable === true,
    candidateAppIds: Array.isArray(association.candidateAppIds) ? association.candidateAppIds.slice(0, 32) : [],
    order: index
  }
}

function normalizeApplication(application, index) {
  if (!isObject(application) || typeof application.id !== "string" || application.id.length > 160) return null
  return {
    id: application.id,
    label: clippedText(application.name || application.id, 240),
    kind: "application",
    status: clippedText(application.state || "unknown", 80),
    subtitle: clippedText(application.desktopId || application.source || "Application", 240),
    details: detailFields(application, { id: true, name: true, state: true, desktopId: true }),
    order: index
  }
}

function payloadAvailability(value) {
  var availability = isObject(value && value.availability) ? value.availability : null
  if (!availability) return { state: "unknown", detail: "The provider result has no availability declaration." }
  if (typeof availability.state === "string") {
    var reasons = Array.isArray(availability.reasons) ? availability.reasons : []
    var explanation = reasons.length > 0 && isObject(reasons[0]) ? reasons[0].explanation || reasons[0].title || "" : ""
    return { state: availability.state, detail: clippedText(explanation, MAX_DISPLAY_TEXT) }
  }
  if (availability.read === false) {
    var reason = isObject(availability.reason) ? availability.reason : null
    return { state: "unavailable", detail: clippedText(reason && (reason.explanation || reason.title) || "This information is not available right now.") }
  }
  if (availability.read === true && availability.reason) {
    var degradedReason = isObject(availability.reason) ? availability.reason : null
    return { state: "degraded", detail: clippedText(degradedReason && (degradedReason.explanation || degradedReason.title) || "Some changes are unavailable.") }
  }
  return { state: availability.read === true ? "available" : "unknown", detail: "" }
}

function validateReadResult(query, entry, result) {
  if (!exactKeys(result, ["provider", "providerVersion", "generation", "action", "capability", "value", "observedAt"]))
    return "The provider result envelope has an unexpected field set."
  if (result.provider !== query.providerId || result.action !== query.action || result.capability !== query.capability)
    return "The provider result does not match the selected Settings route."
  if (result.providerVersion !== entry.manifest.providerVersion || result.generation !== entry.generation)
    return "The provider result belongs to an obsolete catalog generation."
  if (!Number.isInteger(result.generation) || result.generation < 1 ||
      typeof result.observedAt !== "number" || !isFinite(result.observedAt) || result.observedAt < 0 || !isObject(result.value))
    return "The provider result version, generation, timestamp, or value is invalid."
  if (result.value.provider !== query.providerId || result.value.providerVersion !== result.providerVersion ||
      result.value.action !== query.action || !isObject(result.value.availability))
    return "The typed provider payload identity or availability is invalid."
  if (Array.isArray(result.value.resources) && result.value.resources.length > MAX_SOURCE_RECORDS)
    return "The provider resource inventory exceeds the Settings source bound."
  if (query.providerId === "defaults.provider") {
    if (result.value.state !== null && !isObject(result.value.state)) return "The defaults database state is invalid."
    if (isObject(result.value.state)) {
      if (!Array.isArray(result.value.state.applications) || result.value.state.applications.length > MAX_SOURCE_RECORDS ||
          !Array.isArray(result.value.state.associations) || result.value.state.associations.length > MAX_SOURCE_RECORDS)
        return "The defaults database inventory exceeds the Settings source bound."
    }
  }
  return ""
}

function normalizedRecords(query, value, selectedResourceId) {
  var all = []
  var sourceCount = 0
  if (Array.isArray(value.resources)) {
    sourceCount = value.resources.length
    for (var i = 0; i < value.resources.length; i++) {
      var resource = normalizeLeafResource(value.resources[i], i)
      if (resource) all.push(resource)
    }
  } else if (query.providerId === "defaults.provider" && isObject(value.state)) {
    var associations = value.state.associations
    var applications = value.state.applications
    sourceCount = associations.length + applications.length
    for (var j = 0; j < associations.length; j++) {
      var association = normalizeAssociation(associations[j], j)
      if (association) all.push(association)
    }
    for (var k = 0; k < applications.length; k++) {
      var application = normalizeApplication(applications[k], associations.length + k)
      if (application) all.push(application)
    }
  }
  var selectedMissing = false
  if (selectedResourceId !== "") {
    var selected = []
    for (var s = 0; s < all.length; s++) {
      if (all[s].id === selectedResourceId) selected.push(all[s])
    }
    selectedMissing = selected.length === 0
    all = selected
  }
  var clipped = all.length > MAX_VISIBLE_RECORDS
  if (clipped) all = all.slice(0, MAX_VISIBLE_RECORDS)
  return {
    records: all,
    totalRecords: selectedResourceId === "" ? sourceCount : all.length,
    clipped: clipped,
    selectedMissing: selectedMissing
  }
}

function acceptedReadState(previous, result) {
  var entry = previous.providerEntry
  var invalid = validateReadResult(previous.query, entry, result)
  if (invalid !== "") {
    var code = invalid.indexOf("obsolete") >= 0 ? "provider.changed-during-read" : "settings.invalid-response"
    return failureState(previous, code === "provider.changed-during-read"
      ? structuredError(code, "Provider state became stale", invalid, previous.query.providerId, ["provider.refresh"])
      : responseError(invalid))
  }
  var normalized = normalizedRecords(previous.query, result.value, previous.selectedResourceId)
  var availability = payloadAvailability(result.value)
  var next = cloneState(previous)
  next.records = normalized.records
  next.totalRecords = normalized.totalRecords
  next.clipped = normalized.clipped
  next.selectedMissing = normalized.selectedMissing
  next.payloadAvailability = availability.state
  next.observedAt = result.observedAt
  next.requestId = ""
  next.error = null
  next.recoveryActions = []
  if (availability.state === "unavailable") {
    next.phase = "unavailable"
    next.error = structuredError(
      "provider.read-unavailable", "This information is not available right now",
      availability.detail || "The provider explicitly reported that its read state is unavailable.",
      previous.query.providerId, ["provider.refresh"]
    )
  } else if (entry.state === "degraded" || availability.state === "degraded") {
    next.phase = "degraded"
    if (availability.detail !== "") next.error = structuredError(
      "provider.read-degraded", "Some changes are unavailable", availability.detail,
      previous.query.providerId, ["provider.refresh"]
    )
  } else if (normalized.records.length === 0) {
    next.phase = "empty"
  } else {
    next.phase = "ready"
  }
  return next
}

function overviewState(previous, catalog) {
  var next = cloneState(previous)
  next.phase = "overview"
  next.catalog = copyArray(catalog)
  next.catalogReady = true
  next.providerEntry = null
  next.records = []
  next.totalRecords = 0
  next.clipped = false
  next.selectedMissing = false
  next.overviewCards = catalogCards(catalog)
  next.operationActions = []
  next.payloadAvailability = "available"
  next.observedAt = null
  next.requestId = ""
  next.error = null
  next.recoveryActions = []
  return next
}

function Controller(options) {
  var settings = options || {}
  this.send = typeof settings.send === "function" ? settings.send : function() { return "" }
  this.cancel = typeof settings.cancel === "function" ? settings.cancel : function() { return false }
  this.publish = typeof settings.onState === "function" ? settings.onState : function() {}
  this.connected = false
  this.generation = 0
  this.catalog = null
  this.activeCatalogRequestId = ""
  this.activeReadRequestId = ""
  this.pending = Object.create(null)
  this.sendingType = ""
  this.synchronousFailure = null
  this.state = baseState(OVERVIEW_ROUTE, {}, "offline")
}

Controller.prototype._setState = function(state) {
  this.state = state
  this.publish(cloneState(state))
}

Controller.prototype._cancelId = function(requestId) {
  var id = String(requestId || "")
  if (id === "") return
  delete this.pending[id]
  this.cancel(id)
}

Controller.prototype._cancelActive = function() {
  this._cancelId(this.activeCatalogRequestId)
  this._cancelId(this.activeReadRequestId)
  this.activeCatalogRequestId = ""
  this.activeReadRequestId = ""
}

Controller.prototype._send = function(type, method, params) {
  this.sendingType = type
  this.synchronousFailure = null
  var id = String(this.send(method, params) || "")
  this.sendingType = ""
  if (id === "") {
    var error = this.synchronousFailure || structuredError(
      "settings.request-rejected",
      "Settings request was rejected",
      "The constrained Fabric client did not accept the read-only Settings request.",
      method,
      ["fabric.reconnect"]
    )
    this.synchronousFailure = null
    this._setState(failureState(this.state, error))
    return ""
  }
  this.pending[id] = { type: type, generation: this.generation, routeId: this.state.routeId }
  if (type === "catalog") this.activeCatalogRequestId = id
  else this.activeReadRequestId = id
  var waiting = cloneState(this.state)
  waiting.requestId = id
  this._setState(waiting)
  return id
}

Controller.prototype._refreshCatalog = function() {
  this.generation++
  this._cancelActive()
  this.pending = Object.create(null)
  this.catalog = null
  var loading = baseState(this.state.routeId, { resourceId: this.state.selectedResourceId }, "catalog-loading")
  loading.phase = "catalog-loading"
  this._setState(loading)
  return this._send("catalog", CATALOG_METHOD, {}) !== ""
}

Controller.prototype._startRead = function() {
  var query = this.state.query
  if (!query) return false
  if (query.providerId === "") {
    this._setState(overviewState(this.state, this.catalog || []))
    return true
  }
  var entry = providerEntry(this.catalog, query.providerId)
  var prepared = cloneState(this.state)
  prepared.catalog = copyArray(this.catalog)
  prepared.catalogReady = true
  prepared.providerEntry = entry
  prepared.records = []
  prepared.totalRecords = 0
  prepared.clipped = false
  prepared.selectedMissing = false
  prepared.overviewCards = []
  prepared.operationActions = operationActions(entry)
  prepared.observedAt = null
  prepared.error = null
  prepared.recoveryActions = []
  if (!entry) {
    prepared.phase = "missing"
    this._setState(prepared)
    return false
  }
  if (entry.state === "unavailable" || entry.state === "incompatible") {
    prepared.phase = "unavailable"
    prepared.error = structuredError(
      entry.state === "incompatible" ? "provider.incompatible-version" : "provider.unavailable",
      entry.state === "incompatible" ? "Provider version is incompatible" : "Provider is unavailable",
      entry.detail || "The registered provider has no usable backend.",
      query.providerId,
      ["provider.refresh"]
    )
    prepared.recoveryActions = copyArray(prepared.error.recoveryActions)
    this._setState(prepared)
    return false
  }
  var mismatch = queryContractError(entry, query)
  if (mismatch !== "") {
    prepared.phase = "contract-mismatch"
    prepared.error = responseError(mismatch)
    prepared.recoveryActions = copyArray(prepared.error.recoveryActions)
    this._setState(prepared)
    return false
  }
  prepared.phase = "loading"
  this._setState(prepared)
  return this._send("read", READ_METHOD, requestParameters(query)) !== ""
}

Controller.prototype.setConnected = function(connected) {
  var value = connected === true
  if (value === this.connected) return false
  this.connected = value
  if (!value) {
    this.generation++
    this._cancelActive()
    this.pending = Object.create(null)
    this.catalog = null
    this._setState(baseState(this.state.routeId, { resourceId: this.state.selectedResourceId }, "offline"))
    return true
  }
  return this._refreshCatalog()
}

Controller.prototype.activate = function(routeId, argumentsValue) {
  this.generation++
  this._cancelId(this.activeReadRequestId)
  this.activeReadRequestId = ""
  var next = baseState(routeId, argumentsValue, this.connected ? "loading" : "offline")
  if (this.catalog) {
    next.catalog = copyArray(this.catalog)
    next.catalogReady = true
  }
  this._setState(next)
  if (!this.connected || next.phase === "failed") return false
  if (!this.catalog) return this._refreshCatalog()
  return this._startRead()
}

Controller.prototype.refresh = function() {
  if (!this.connected) {
    this._setState(baseState(this.state.routeId, { resourceId: this.state.selectedResourceId }, "offline"))
    return false
  }
  return this._refreshCatalog()
}

Controller.prototype.refreshCurrent = function() {
  if (!this.connected) return false
  if (!this.catalog) return this._refreshCatalog()
  this.generation++
  this._cancelId(this.activeReadRequestId)
  this.activeReadRequestId = ""
  return this._startRead()
}

Controller.prototype.refreshAfterSuccessfulWriter = function(status) {
  if (String(status || "") !== "succeeded") return false
  return this.refreshCurrent()
}

Controller.prototype.refreshWhenSurfaceVisible = function() {
  if (!this.connected) return false
  var phase = String(this.state && this.state.phase || "")
  if (phase === "catalog-loading" || phase === "loading" || phase === "offline") return false
  return this.refreshCurrent()
}

Controller.prototype.receiveResult = function(requestId, result) {
  var id = String(requestId || "")
  var ticket = this.pending[id]
  if (!ticket || ticket.generation !== this.generation || ticket.routeId !== this.state.routeId) return false
  if (ticket.type === "catalog" && id !== this.activeCatalogRequestId) return false
  if (ticket.type === "read" && id !== this.activeReadRequestId) return false
  delete this.pending[id]
  if (ticket.type === "catalog") {
    this.activeCatalogRequestId = ""
    var invalid = validateCatalogResponse(result)
    if (invalid !== "") {
      this.catalog = null
      this._setState(failureState(this.state, responseError(invalid)))
      return true
    }
    this.catalog = copyArray(result.providers)
    this._startRead()
    return true
  }
  this.activeReadRequestId = ""
  this._setState(acceptedReadState(this.state, result))
  return true
}

Controller.prototype.receiveFailure = function(requestId, error) {
  var id = String(requestId || "")
  if (id === "" && this.sendingType !== "") {
    this.synchronousFailure = error
    return true
  }
  var ticket = this.pending[id]
  if (!ticket || ticket.generation !== this.generation || ticket.routeId !== this.state.routeId) return false
  if (ticket.type === "catalog" && id !== this.activeCatalogRequestId) return false
  if (ticket.type === "read" && id !== this.activeReadRequestId) return false
  delete this.pending[id]
  if (ticket.type === "catalog") {
    this.activeCatalogRequestId = ""
    this.catalog = null
  } else {
    this.activeReadRequestId = ""
  }
  this._setState(failureState(this.state, error))
  return true
}

Controller.prototype.markStale = function(requestId) {
  var id = String(requestId || "")
  var ticket = this.pending[id]
  if (!ticket || ticket.generation !== this.generation || ticket.routeId !== this.state.routeId) return false
  if (id !== this.activeCatalogRequestId && id !== this.activeReadRequestId) return false
  this._cancelId(id)
  if (id === this.activeCatalogRequestId) {
    this.activeCatalogRequestId = ""
    this.catalog = null
  }
  if (id === this.activeReadRequestId) this.activeReadRequestId = ""
  this._setState(failureState(this.state, structuredError(
    "rpc.timeout", "Settings state became stale",
    "The bounded read deadline elapsed before a complete response arrived. No cached state is shown.",
    ticket.type, ["provider.refresh"]
  )))
  return true
}

function createController(options) {
  return new Controller(options)
}

function stateTitle(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "catalog-loading") return "Loading provider catalog"
  if (phase === "loading") return "Reading current provider state"
  if (phase === "overview") return "Live settings coverage"
  if (phase === "ready") return "Current provider state"
  if (phase === "empty") return state && state.selectedMissing ? "Requested resource is absent" : "No resources reported"
  if (phase === "missing") return "Provider is not registered"
  if (phase === "unavailable") return "This information is not available right now"
  if (phase === "degraded") return "Some changes are unavailable"
  if (phase === "contract-mismatch") return "Provider contract does not match"
  if (phase === "denied") return "Settings read was denied"
  if (phase === "interrupted") return "Settings read was interrupted"
  if (phase === "stale") return "Settings state is stale"
  if (phase === "failed") return "Settings read failed"
  return "Fabric is offline"
}

function stateExplanation(state) {
  if (!state) return ""
  var phase = state.phase
  if (phase === "catalog-loading") return "Settings is reading the current bounded code-owned provider registry before selecting a domain action."
  if (phase === "loading") return "Settings is issuing the exact read-only inventory action declared for this route."
  if (phase === "overview") {
    var available = 0
    for (var i = 0; i < state.overviewCards.length; i++) {
      if (state.overviewCards[i].status === "available" || state.overviewCards[i].status === "degraded") available++
    }
    return available + " of " + state.overviewCards.length + " Settings domains have a matching registered read contract. Missing domains remain visibly unavailable."
  }
  if (phase === "ready") return state.records.length + " current resource" + (state.records.length === 1 ? " is" : "s are") + " visible from the typed provider response."
  if (phase === "empty") return state.selectedMissing
    ? "The provider returned current state, but no resource exactly matched the deep-link ID."
    : "The provider returned a valid current inventory with no visible resources."
  if (phase === "missing") return clippedText(state.query.providerId) + " is absent from the live provider catalog. No substitute state is inferred."
  if (phase === "unavailable" || phase === "degraded" || phase === "contract-mismatch" ||
      phase === "denied" || phase === "failed")
    return state.error && state.error.explanation ? clippedText(state.error.explanation, 1000) : "The provider did not return complete usable state."
  if (phase === "interrupted") return "The client stopped waiting before a complete response arrived. Retry to establish current state."
  if (phase === "stale") return "The provider changed or the bounded deadline elapsed. The obsolete result was discarded."
  return "No cached provider state is shown while the authenticated Fabric endpoint is disconnected."
}

function phaseBadge(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "overview") return "CATALOG"
  if (phase === "ready") return "CURRENT"
  if (phase === "empty") return "EMPTY"
  if (phase === "catalog-loading" || phase === "loading") return "LOADING"
  if (phase === "degraded") return "DEGRADED"
  if (phase === "missing") return "NOT REGISTERED"
  if (phase === "contract-mismatch") return "MISMATCH"
  if (phase === "denied") return "DENIED"
  if (phase === "interrupted") return "INTERRUPTED"
  if (phase === "stale") return "STALE"
  if (phase === "failed") return "FAILED"
  if (phase === "unavailable") return "UNAVAILABLE"
  return "OFFLINE"
}

function phaseTone(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "overview" || phase === "ready" || phase === "empty") return "success"
  if (phase === "catalog-loading" || phase === "loading") return "info"
  if (phase === "failed" || phase === "denied" || phase === "contract-mismatch") return "danger"
  return "warning"
}

function toneForRecord(status) {
  var value = String(status || "").toLowerCase()
  if (["available", "connected", "enabled", "healthy", "ready", "idle", "fully-charged", "reported", "configured"].indexOf(value) >= 0)
    return "success"
  if (["failed", "unavailable", "dangling", "error", "incompatible"].indexOf(value) >= 0) return "danger"
  if (["unknown", "degraded", "disconnected", "disabled", "interrupted", "waiting-reboot", "unconfigured"].indexOf(value) >= 0)
    return "warning"
  return "info"
}

function observedText(value) {
  if (typeof value !== "number" || !isFinite(value) || value < 0) return "Not observed"
  try {
    return new Date(value * 1000).toISOString().replace("T", " ").replace(".000Z", " UTC")
  } catch (_) {
    return "Unknown observation time"
  }
}

function hostedPanel(routeId) {
  var id = String(routeId || "")
  if (id === "settings.personalization.overview") return {
    source: "Ui/SettingsPersonalizationHost.qml",
    pluginId: "omarchy.image-picker",
    label: "Live Personalization picker",
    honesty: "This page hosts the existing image picker for theme packs and wallpapers. Typed personalization.provider writers for density, cursor, motion, and a full theme service remain unavailable."
  }
  return null
}

function provenance(state) {
  if (!state || !state.query || state.query.providerId === "") return "Read-only provider catalog"
  var entry = state.providerEntry
  var parts = [state.query.providerId + "." + state.query.action, "capability " + state.query.capability]
  if (entry && entry.manifest) parts.push("provider " + entry.manifest.providerVersion + " generation " + entry.generation)
  if (state.observedAt !== null) parts.push("observed " + observedText(state.observedAt))
  return clippedText(parts.join(" \u00b7 "), 640)
}

if (typeof module !== "undefined") {
  module.exports = {
    CATALOG_METHOD: CATALOG_METHOD,
    READ_METHOD: READ_METHOD,
    OVERVIEW_ROUTE: OVERVIEW_ROUTE,
    ROUTE_QUERIES: ROUTE_QUERIES,
    MAX_CATALOG_ENTRIES: MAX_CATALOG_ENTRIES,
    MAX_SOURCE_RECORDS: MAX_SOURCE_RECORDS,
    MAX_VISIBLE_RECORDS: MAX_VISIBLE_RECORDS,
    MAX_VISIBLE_FIELDS: MAX_VISIBLE_FIELDS,
    POWER_PROFILES: POWER_PROFILES,
    BROWSER_SCHEMES: BROWSER_SCHEMES,
    browserAssociation: browserAssociation,
    browserCandidates: browserCandidates,
    normalizeAssociation: normalizeAssociation,
    normalizeApplication: normalizeApplication,
    MAX_DISPLAY_TEXT: MAX_DISPLAY_TEXT,
    queryForRoute: queryForRoute,
    normalizedSelection: normalizedSelection,
    requestParameters: requestParameters,
    validateCatalogResponse: validateCatalogResponse,
    queryContractError: queryContractError,
    providerEntry: providerEntry,
    operationActions: operationActions,
    validateReadResult: validateReadResult,
    normalizeLeafResource: normalizeLeafResource,
    normalizedRecords: normalizedRecords,
    acceptedReadState: acceptedReadState,
    baseState: baseState,
    failureState: failureState,
    catalogCards: catalogCards,
    createController: createController,
    clippedText: clippedText,
    compactValue: compactValue,
    stateTitle: stateTitle,
    stateExplanation: stateExplanation,
    phaseBadge: phaseBadge,
    phaseTone: phaseTone,
    toneForRecord: toneForRecord,
    observedText: observedText,
    provenance: provenance,
    hostedPanel: hostedPanel,
    LIVE_WRITER_ROUTES: LIVE_WRITER_ROUTES,
    routeHasLiveWriter: routeHasLiveWriter,
    coverageBadge: coverageBadge,
    coverageTone: coverageTone,
    declaredOpsHonesty: declaredOpsHonesty,
    authorityFooter: authorityFooter
  }
}
