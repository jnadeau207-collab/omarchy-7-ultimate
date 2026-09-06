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
    coverage: "Display inventory is readable from display.inspect (connector, mode, scale, position), and brightness applies through display.provider brightness.set on outputs that expose a controllable backlight. Night light uses the same NightlightService session/heritage plane as Superbar > Quick Settings; Settings hosts that control here and does not invent a display.provider night-light durable writer. Scale applies through this session's omarchy-hyprland-monitor-scaling helper; Settings does not invent a display.provider scale durable writer. Fabric display.inspect stays separate. Resolution, arrangement, and HDR remain unavailable from Settings. Night light or scaling alone is not modern display complete. session leftover recorded: Settings Display scaling session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present)."
  },
  {
    routeId: "settings.audio.overview",
    title: "Sound",
    providerId: "audio.provider",
    action: "inspect",
    capability: "audio.inspect",
    supportsResource: true,
    coverage: "Audio output inventory is readable from audio.inspect (sink, default, mute, channel volume, ports). Output volume applies through the durable operation service as this user. Output mute and default sink apply through this session's omarchy-fabric-session-apply audio-output-mute-set / audio-output-default-set helpers with tip-true audio.sink identities; Settings does not invent an audio.provider mute or default-sink durable writer. Audio troubleshoot restart applies through this session's omarchy-fabric-session-apply audio-troubleshoot-restart helper wrapping tip-true absolute omarchy-restart-audio FixedArgv; Settings does not invent a troubleshooting.provider or audio.provider troubleshoot durable writer. Soft leftover-attach of catalog audio.output.manage and troubleshooting.audio.run leftover legacy-direct. session leftover recorded: Settings Sound mute, default output, and audio restart session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present). Port changes and the full troubleshoot wizard remain OPEN leftover. Mute, default, or restart alone is not Sound product-complete. windows-native.6 stays pending. windows-native.39 stays prototype/pending."
  },
  {
    routeId: "settings.network.overview",
    title: "Network & internet",
    providerId: "network.provider",
    action: "inspect",
    capability: "network.inspect",
    supportsResource: true,
    coverage: "Network inventory is readable from network.inspect (Wi-Fi radio, interfaces, connection status), and the Wi-Fi radio switches through network.provider wifi.set-enabled. Joining an open or password-protected network uses this session's NetworkManager access from Settings; the passphrase never enters Fabric. Enterprise, VPN, and per-connection DNS remain unavailable from Settings."
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
    coverage: "Bluetooth inventory is readable from bluetooth.inspect (controller power, discovering, paired and connected devices). Pairing and connecting use this session's BlueZ adapter from Settings; pairing secrets never enter Fabric. Audio routing, PIN-entry UI, and adapter rfkill remain unavailable from Settings."
  },
  {
    routeId: "settings.input.overview",
    title: "Input",
    providerId: "input.provider",
    action: "inspect",
    capability: "input.inspect",
    supportsResource: true,
    coverage: "Keyboard inventory and layout state are readable from input.inspect. The active layout applies through tip-true SettingsSessionKeyboardLayout.setLayout → input-keyboard-layout (this session's omarchy-fabric-session-apply helper) when a typed keyboard carries more than one configured layout. Settings does not invent an input.provider keyboard-layout durable writer. Fabric input.inspect stays separate. Pointer, repeat rate, and accessibility input changes remain unavailable from Settings. Layout alone is not locale complete. session leftover recorded: Change keyboard layout soft leftover-attaches windows-native.33 to this tip-true Settings > Input plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.33. windows-native.33 stays prototype/pending. Never claim=present."
  },
  {
    routeId: "settings.printers.overview",
    title: "Printers",
    providerId: "printer.provider",
    action: "inspect",
    capability: "printer.inspect",
    supportsResource: true,
    coverage: "Printer inventory is readable through this session's omarchy-fabric-session-apply printer-status helper (/usr/bin/lpstat -v/-d/-a, tip-true printer.* identities; credentialed URIs refused). Set-default, pause, resume, and test-page apply through printer-default-set / printer-pause / printer-resume / printer-test-page FixedArgv helpers. Soft leftover-attach of catalog printers.manage leftover legacy-direct. session leftover recorded: Settings Printers inventory and queue session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present). Settings does not invent a printers.provider durable writer or Fabric SHELL LIVE queue mutation. Fabric printer.inspect and plan-only queue.plan stay separate. Network Add / driver wizard remains OPEN leftover. Inventory or set-default alone is not Devices and Printers product-complete. windows-native.32 stays pending. Administration > Printers and scanners remains the bounded printer.inspect host."
  },
  {
    routeId: "settings.personalization.overview",
    title: "Personalization",
    providerId: "personalization.provider",
    action: "inspect",
    capability: "personalization.inspect",
    supportsResource: false,
    coverage: "Settings hosts the existing image picker for theme packs and wallpapers. Wallpaper apply runs through tip-true ImagePicker.applyEmbedded → omarchy-theme-bg-set. No code-owned personalization.provider is registered. Density, cursor, motion, and a typed full theme service remain unavailable from Settings. session leftover recorded: Change the wallpaper soft leftover-attaches windows-native.4 to this tip-true Settings > Personalization wallpaper plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.4. windows-native.4 stays prototype/pending. Never claim=present."
  },
  {
    routeId: "settings.apps.overview",
    title: "Apps",
    providerId: "defaults.provider",
    action: "inspect",
    capability: "defaults.inspect",
    supportsResource: true,
    coverage: "Default applications and associations are readable through defaults.inspect, including MIME inventory. The default browser applies through defaults.provider protocol.set for the http and https schemes. The default email application applies through defaults.provider protocol.set for the mailto scheme. MIME defaults apply through defaults.provider mime.set for writable associations with more than one installed candidate. Startup applications enable or disable through tip-true SettingsSessionStartup.setEnabled → apps-startup-set (this session's XDG autostart helper). Fabric defaults.inspect stays readable. Settings does not invent a Fabric apps.startup.disable durable writer. Settings does not invent Task Manager present. session leftover recorded: Disable a startup application soft leftover-attaches windows-native.27 to this tip-true Settings > Apps startup plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.27. windows-native.27 stays prototype/pending. Never claim=present. Background application inventory remains unavailable from Settings. Default Programs is the dedicated protocol and MIME page."
  },
  {
    routeId: "settings.apps.default-programs",
    title: "Default Programs",
    providerId: "defaults.provider",
    action: "inspect",
    capability: "defaults.inspect",
    supportsResource: true,
    coverage: "Default Programs page partial LIVE. The default browser applies through defaults.provider protocol.set for http and https. The default email application applies through defaults.provider protocol.set for mailto. MIME defaults apply through defaults.provider mime.set for writable associations with more than one installed candidate. session leftover recorded: Change the default browser soft leftover-attaches windows-native.19 to this tip-true Settings > Default Programs browser plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.19. AutoPlay, Set Program Access and Computer Defaults, and files.associations.set remain unavailable. This is not the Win7 Default Programs applet. Win7 applet parity still open. windows-native.19 stays prototype/pending. Cloud EXIT 0 is not metal leftover CLOSED. Do not invent MIME association UI / AutoPlay / SPAD / files.associations.set product-complete."
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
    coverage: "Update availability and lifecycle state are readable. Install uses this session's update helper; elevated auth never enters Fabric. Fabric system.update stays inspect-only / not LIVE. History is readable from this session's update log through SettingsSessionUpdate.readHistory. session leftover recorded: Inspect update history soft leftover-attaches windows-native.29 to this tip-true Settings > Update history plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.29. Restart and reboot writers remain unavailable from Settings. windows-native.29 stays prototype/pending. Update is not present as product. Never claim=present."
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
    coverage: "OS, product, hardware, and root storage are readable through this session's omarchy-fabric-session-apply system-information-inspect helper. Settings does not invent a system-information.provider durable writer. Settings does not invent Fabric durable system.info.read LIVE / claim=present. Agent Center bubblewrap system.info.read stays separate. Encryption, firmware flash, Device Manager, and storage mutation remain unavailable. session leftover recorded: Settings System information session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present)."
  }]

var LIVE_WRITER_ROUTES = [
  "settings.audio.overview",
  "settings.network.overview",
  "settings.bluetooth.overview",
  "settings.display.overview",
  "settings.input.overview",
  "settings.printers.overview",
  "settings.apps.overview",
  "settings.apps.default-programs",
  "settings.update.overview"
]

function isDefaultsWriterRoute(routeId) {
  var id = String(routeId || "")
  return id === "settings.apps.overview" || id === "settings.apps.default-programs"
}

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
  if (String(routeId || "") === "settings.display.overview")
    return "Brightness applies through preflight, approval, and the durable coordinator. Night light uses NightlightService / Quick Settings on this session. Scale uses this session's omarchy-hyprland-monitor-scaling helper. Fabric display.inspect stays separate. Settings does not invent a display.provider night-light durable writer. Settings does not invent a display.provider scale durable writer."
  if (String(routeId || "") === "settings.audio.overview")
    return "Volume applies through preflight, approval, and the durable coordinator. Mute and default sink use this session's omarchy-fabric-session-apply audio-output-mute-set / audio-output-default-set helpers. Audio troubleshoot restart uses this session's omarchy-fabric-session-apply audio-troubleshoot-restart helper wrapping tip-true absolute omarchy-restart-audio FixedArgv. Fabric audio.inspect stays separate. Settings does not invent an audio.provider mute, default-sink, or troubleshoot durable writer. Port changes and the full troubleshoot wizard remain OPEN leftover."
  if (String(routeId || "") === "settings.printers.overview")
    return "Printer inventory, set-default, pause, resume, and test-page use this session's omarchy-fabric-session-apply printer-status / printer-default-set / printer-pause / printer-resume / printer-test-page helpers. Fabric printer.inspect stays separate. Settings does not invent a printers.provider durable writer. Network Add remains OPEN leftover."
  if (String(routeId || "") === "settings.input.overview")
    return "Layout uses tip-true SettingsSessionKeyboardLayout.setLayout → input-keyboard-layout (this session's omarchy-fabric-session-apply helper). Fabric input.inspect stays separate. Settings does not invent an input.provider keyboard-layout durable writer. soft leftover-attaches windows-native.33 to this tip-true Settings > Input plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.33. windows-native.33 stays prototype/pending. Never claim=present."
  if (String(routeId || "") === "settings.system.overview")
    return "System information uses this session's omarchy-fabric-session-apply system-information-inspect helper. Settings exposes no preflight, approval, or execution control for this domain. Settings does not invent a system-information.provider durable writer. Agent Center bubblewrap system.info.read stays separate."
  if (String(routeId || "") === "settings.apps.overview")
    return "Settings runs browser, mailer, and MIME defaults through preflight, approval, and the durable coordinator. Startup applications enable or disable through tip-true SettingsSessionStartup.setEnabled → apps-startup-set (this session's XDG autostart helper). Fabric defaults.inspect stays readable. Settings does not invent a Fabric apps.startup.disable durable writer. Settings does not invent Task Manager present. soft leftover-attaches windows-native.27 to this tip-true Settings > Apps startup plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.27. windows-native.27 stays prototype/pending. Never claim=present."
  if (String(routeId || "") === "settings.bluetooth.overview")
    return "Settings pairs and connects through this session's BlueZ adapter. Fabric bluetooth.inspect stays read-only; pairing secrets never enter durable evidence."
  if (String(routeId || "") === "settings.update.overview")
    return "Settings applies updates through this session's update helper. Fabric system.update stays inspect-only; elevated auth never enters durable evidence."
  return routeHasLiveWriter(routeId)
    ? "Settings runs this operation through preflight, approval, and the durable coordinator."
    : "Settings exposes no preflight, approval, or execution control for this domain."
}

function authorityFooter() {
  return "Typed writers run through preflight, approval, and the durable coordinator as this user \u00b7 Sound volume, Network Wi-Fi radio, Display brightness, Apps default browser, Apps default email, and Default Programs protocol and MIME associations are LIVE \u00b7 Sound mute, default output, and audio troubleshoot restart use this session's omarchy-fabric-session-apply audio helpers \u00b7 Printers inventory and queue controls use this session's omarchy-fabric-session-apply printer helpers \u00b7 Display night light uses NightlightService on this session, the same plane as Quick Settings \u00b7 Display scaling uses this session's omarchy-hyprland-monitor-scaling helper \u00b7 Input layout uses this session's omarchy-fabric-session-apply input-keyboard-layout helper \u00b7 System information uses this session's omarchy-fabric-session-apply system-information-inspect helper \u00b7 Apps startup uses this session's XDG autostart helper \u00b7 Bluetooth pair and connect use this session's BlueZ adapter \u00b7 Update apply uses this session's update helper \u00b7 Fabric system.update is not LIVE \u00b7 Power profile stays inspect-only because polkit cannot authorize the fabric daemon under app.slice \u00b7 other domains stay inspect-only \u00b7 no direct commands \u00b7 Update elevated auth stays on the session helper and never enters Fabric \u00b7 Open pages re-read when shown and after local writers; out-of-band changes while this window stays focused need F5 or Retry, with no live hardware-key subscription"
}

function operationIdempotencyToken(value) {
  var text = String(value == null ? "" : value)
  var out = ""
  var i
  for (i = 0; i < text.length; i += 1) {
    var ch = text.charAt(i)
    if ((ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch === "." || ch === "_" || ch === ":" || ch === "-") {
      out += ch
    } else {
      out += "."
    }
  }
  if (out.length === 0 || !((out.charAt(0) >= "A" && out.charAt(0) <= "Z") || (out.charAt(0) >= "a" && out.charAt(0) <= "z") || (out.charAt(0) >= "0" && out.charAt(0) <= "9"))) {
    out = "x" + out
  }
  if (out.length > 256) {
    out = out.slice(0, 256)
  }
  return out
}

function mimeDefaultIdempotencyKey(mimeType, appId, stamp) {
  return "settings.mime-default." + operationIdempotencyToken(mimeType) + "." + operationIdempotencyToken(appId) + "." + String(stamp)
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

var WIFI_JOIN_MAX_ROWS = 16
var WIFI_JOIN_SECURITY = {
  wpa3SuiteB192: 0,
  sae: 1,
  wpa2Eap: 2,
  wpa2Psk: 3,
  wpaEap: 4,
  wpaPsk: 5,
  staticWep: 6,
  dynamicWep: 7,
  leap: 8,
  owe: 9,
  open: 10,
  unknown: 11
}

function wifiJoinRow(network) {
  if (!isObject(network)) return null
  var ssid = typeof network.ssid === "string" ? network.ssid
    : typeof network.name === "string" ? network.name : ""
  if (ssid === "") return null
  var signal = 0
  if (typeof network.signal === "number" && isFinite(network.signal)) signal = Math.round(network.signal)
  else if (typeof network.signalStrength === "number" && isFinite(network.signalStrength)) {
    signal = network.signalStrength <= 1 ? Math.round(network.signalStrength * 100) : Math.round(network.signalStrength)
  }
  if (signal < 0) signal = 0
  if (signal > 100) signal = 100
  return {
    connected: network.connected === true,
    known: network.known === true,
    ssid: clippedText(ssid, 160),
    signal: signal,
    security: network.security
  }
}

function sortWifiJoinRows(rows) {
  var nets = []
  if (!Array.isArray(rows)) return nets
  for (var i = 0; i < rows.length; i++) {
    var row = wifiJoinRow(rows[i])
    if (row) nets.push(row)
  }
  nets.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    if (a.known !== b.known) return a.known ? -1 : 1
    if (b.signal !== a.signal) return b.signal - a.signal
    if (a.ssid < b.ssid) return -1
    if (a.ssid > b.ssid) return 1
    return 0
  })
  if (nets.length > WIFI_JOIN_MAX_ROWS) nets = nets.slice(0, WIFI_JOIN_MAX_ROWS)
  return nets
}

function wifiJoinAction(row, enums) {
  var codes = isObject(enums) ? enums : WIFI_JOIN_SECURITY
  if (!isObject(row) || typeof row.ssid !== "string" || row.ssid === "") return "hidden"
  if (row.connected === true) return "connected"
  if (row.security === codes.wpa2Eap || row.security === codes.wpaEap) return "enterprise-unavailable"
  var needsCredentials = row.security !== codes.open && row.security !== codes.owe
  if (!needsCredentials) return "join-open"
  if (row.known === true) return "join-known"
  return "prompt-password"
}

function wifiJoinCanSubmit(action, passphrase) {
  if (action === "join-open" || action === "join-known") return true
  if (action === "prompt-password") return typeof passphrase === "string" && passphrase.length > 0
  return false
}

var BLUETOOTH_PAIR_MAX_ROWS = 16

function bluetoothHasHumanName(label) {
  var text = String(label || "").trim()
  if (text === "") return false
  if (/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text)) return false
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)) return false
  return true
}

function bluetoothDeviceRow(device) {
  if (!isObject(device)) return null
  var address = String(device.address || "")
  if (address === "") return null
  var label = String(device.deviceName || device.name || "").trim()
  if (!bluetoothHasHumanName(label)) return null
  return {
    address: address,
    label: clippedText(label, 160),
    connected: device.connected === true,
    paired: device.paired === true || device.bonded === true || device.trusted === true,
    pairing: device.pairing === true
  }
}

function bluetoothDeviceGroups(devices) {
  var connected = []
  var known = []
  var discovered = []
  var list = Array.isArray(devices) ? devices : []
  for (var i = 0; i < list.length; i++) {
    var row = bluetoothDeviceRow(list[i])
    if (!row) continue
    if (row.connected) connected.push(row)
    else if (row.paired) known.push(row)
    else discovered.push(row)
  }
  function byLabel(a, b) {
    if (a.label < b.label) return -1
    if (a.label > b.label) return 1
    return 0
  }
  connected.sort(byLabel)
  known.sort(byLabel)
  discovered.sort(byLabel)
  return {
    connected: connected.slice(0, BLUETOOTH_PAIR_MAX_ROWS),
    known: known.slice(0, BLUETOOTH_PAIR_MAX_ROWS),
    discovered: discovered.slice(0, BLUETOOTH_PAIR_MAX_ROWS)
  }
}

function bluetoothPairAction(row) {
  if (!isObject(row) || typeof row.address !== "string" || row.address === "") return "hidden"
  if (row.connected === true) return "connected"
  if (row.paired === true) return "connect"
  return "pair"
}

function bluetoothCanSubmit(action) {
  return action === "pair" || action === "connect" || action === "disconnect"
}

function wifiJoinFailureReason(reason, action, reasons) {
  var r = isObject(reasons) ? reasons : {}
  var needs = action === "prompt-password" || action === "join-known"
  if (needs && reason === r.NoSecrets) return "Passphrase required"
  if (needs && reason === r.WifiAuthTimeout) return "Wrong password"
  if (reason === r.WifiNetworkLost) return "Network lost"
  if (reason === r.WifiClientDisconnected) return "Disconnected"
  if (reason === r.WifiClientFailed) return "Connection failed"
  return "Failed to connect"
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

function protocolAssociation(records, scheme) {
  if (!Array.isArray(records) || typeof scheme !== "string" || scheme === "") return null
  for (var i = 0; i < records.length; i++) {
    if (records[i].associationKind === "protocol" && records[i].associationKey === scheme) return records[i]
  }
  return null
}

function browserAssociation(records) {
  return protocolAssociation(records, "https")
}

function mailerAssociation(records) {
  if (!Array.isArray(records)) return null
  for (var i = 0; i < records.length; i++) {
    if (records[i].associationKind === "protocol" && records[i].associationKey === "mailto") return records[i]
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

function mimeAssociations(records) {
  if (!Array.isArray(records)) return []
  var out = []
  for (var i = 0; i < records.length; i++) {
    var record = records[i]
    if (!record || record.associationKind !== "mime" || record.writable !== true) continue
    if (typeof record.associationKey !== "string" || record.associationKey === "") continue
    var candidates = browserCandidates(record, records)
    if (candidates.length < 2) continue
    out.push({
      key: record.associationKey,
      label: record.label,
      defaultAppId: typeof record.defaultAppId === "string" ? record.defaultAppId : "",
      candidates: candidates
    })
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

function normalizeStartup(entry, index) {
  if (!isObject(entry) || typeof entry.id !== "string" || entry.id.length > 160) return null
  if (typeof entry.desktopId !== "string" || typeof entry.name !== "string" || entry.name === "") return null
  if (entry.enabled !== true && entry.enabled !== false) return null
  if (entry.source !== "user" && entry.source !== "system") return null
  return {
    id: entry.id,
    label: clippedText(entry.name, 240),
    kind: "startup",
    status: entry.enabled ? "enabled" : "disabled",
    subtitle: clippedText(entry.desktopId + (entry.source === "user" ? " (your autostart)" : " (system autostart)"), 240),
    details: detailFields(entry, { id: true, name: true, desktopId: true }),
    desktopId: entry.desktopId,
    startupEnabled: entry.enabled,
    startupSource: entry.source,
    order: index
  }
}

function startupEntries(records) {
  if (!Array.isArray(records)) return []
  var out = []
  for (var i = 0; i < records.length; i++) {
    if (records[i] && records[i].kind === "startup") out.push(records[i])
  }
  return out
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
      if (result.value.state.startup !== undefined &&
          (!Array.isArray(result.value.state.startup) || result.value.state.startup.length > MAX_SOURCE_RECORDS))
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
    var startup = Array.isArray(value.state.startup) ? value.state.startup : []
    sourceCount = associations.length + applications.length + startup.length
    for (var j = 0; j < associations.length; j++) {
      var association = normalizeAssociation(associations[j], j)
      if (association) all.push(association)
    }
    for (var k = 0; k < applications.length; k++) {
      var application = normalizeApplication(applications[k], associations.length + k)
      if (application) all.push(application)
    }
    for (var t = 0; t < startup.length; t++) {
      var startupEntry = normalizeStartup(startup[t], associations.length + applications.length + t)
      if (startupEntry) all.push(startupEntry)
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
    honesty: "This page hosts the existing image picker for theme packs and wallpapers. Wallpaper apply runs through tip-true ImagePicker.applyEmbedded → omarchy-theme-bg-set. Soft leftover-attaches windows-native.4 to this tip-true Settings > Personalization wallpaper plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.4. Typed personalization.provider writers for density, cursor, motion, and a full theme service remain unavailable. windows-native.4 stays prototype/pending. Never claim=present."
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

function sessionUpdateIdle() {
  return { phase: "idle", action: "", channel: "", message: "", code: "" }
}

function sessionUpdatePlan(action, status) {
  if (action === "check") return { action: "check", channel: "", reason: "" }
  var state = isObject(status) ? status : {}
  var channel = typeof state.channel === "string" ? state.channel : ""
  var requested = typeof state.requestedChannel === "string" ? state.requestedChannel : ""
  if (requested && requested !== channel) {
    return { action: "unavailable", channel: channel, reason: "The requested channel is not the channel this machine tracks." }
  }
  if (!channel) return { action: "unavailable", channel: "", reason: "Settings has not read this machine's update channel." }
  if (state.available !== true) return { action: "unavailable", channel: channel, reason: "No system updates are available." }
  if (state.lockHeld === true) return { action: "unavailable", channel: channel, reason: "An Omarchy update is already running." }
  if (state.diskOk === false) return { action: "unavailable", channel: channel, reason: "This machine does not have enough free disk space to update safely." }
  return { action: "apply", channel: channel, reason: "" }
}

function sessionUpdateCanSubmit(plan) {
  return !!(plan && (plan.action === "check" || (plan.action === "apply" && plan.channel)))
}

function sessionUpdateAccepted(previous, plan) {
  return { phase: "running", action: plan && plan.action || "", channel: plan && plan.channel || "", message: "", code: "" }
}

function sessionUpdateFinished(previous, helperResult) {
  var result = isObject(helperResult) ? helperResult : {}
  var ok = result.ok === true
  var message = clippedText(result.explanation || result.message || (ok ? "The session update helper finished." : "The session update helper failed."), MAX_DISPLAY_TEXT)
  return {
    phase: ok ? "succeeded" : "failed",
    action: previous && previous.action || "",
    channel: result.channel || (previous && previous.channel) || "",
    message: message,
    code: result.code || ""
  }
}

function sessionUpdateHistoryIdle() {
  return { phase: "idle", available: false, empty: true, entries: [], failures: [], message: "", code: "", rebootRequired: false, restartRequired: [] }
}

function sessionUpdateHistoryFinished(previous, helperResult) {
  var result = isObject(helperResult) ? helperResult : {}
  var ok = result.ok === true
  var entries = Array.isArray(result.entries) ? result.entries.slice(0, MAX_VISIBLE_RECORDS) : []
  var failures = Array.isArray(result.failures) ? result.failures.slice(0, MAX_VISIBLE_FIELDS) : []
  var restartRequired = Array.isArray(result.restartRequired) ? result.restartRequired.slice(0, MAX_VISIBLE_FIELDS) : []
  return {
    phase: ok ? "succeeded" : "failed",
    available: result.available === true,
    empty: result.empty === true || entries.length === 0,
    entries: entries,
    failures: failures,
    rebootRequired: result.rebootRequired === true,
    restartRequired: restartRequired,
    message: clippedText(result.explanation || result.message || (ok ? "The session update history helper finished." : "The session update history helper failed."), MAX_DISPLAY_TEXT),
    code: result.code || ""
  }
}

function sessionStartupIdle() {
  return { phase: "idle", action: "", entries: [], empty: false, unavailable: false, message: "", code: "" }
}

function sessionStartupNormalizeEntry(entry) {
  if (!isObject(entry) || typeof entry.desktopId !== "string" || entry.desktopId === "") return null
  if (typeof entry.name !== "string" || entry.name === "") return null
  if (entry.enabled !== true && entry.enabled !== false) return null
  if (entry.source !== "user" && entry.source !== "system") return null
  return {
    desktopId: clippedText(entry.desktopId, 255),
    name: clippedText(entry.name, 240),
    label: clippedText(entry.name, 240),
    startupEnabled: entry.enabled === true,
    startupSource: entry.source,
    source: entry.source,
    controllable: entry.controllable === true
  }
}

function sessionStartupCanSubmit(row) {
  if (!isObject(row) || typeof row.desktopId !== "string" || row.desktopId === "") return false
  if (row.controllable !== true) return false
  return row.enabled === true || row.enabled === false || row.startupEnabled === true || row.startupEnabled === false
}

function sessionStartupAccepted(previous, action) {
  return {
    phase: "running",
    action: action || "",
    entries: previous && Array.isArray(previous.entries) ? previous.entries.slice() : [],
    empty: previous && previous.empty === true,
    unavailable: false,
    message: "",
    code: previous && previous.code || ""
  }
}

function sessionStartupFinished(previous, helperResult) {
  var result = isObject(helperResult) ? helperResult : {}
  var ok = result.ok === true
  var entries = []
  if (Array.isArray(result.entries)) {
    for (var i = 0; i < result.entries.length; i++) {
      var normalized = sessionStartupNormalizeEntry(result.entries[i])
      if (normalized) entries.push(normalized)
    }
  } else if (previous && Array.isArray(previous.entries)) {
    entries = previous.entries.slice()
    if (typeof result.desktopId === "string" && (result.enabled === true || result.enabled === false)) {
      for (var j = 0; j < entries.length; j++) {
        if (entries[j].desktopId === result.desktopId) {
          entries[j] = {
            desktopId: entries[j].desktopId,
            name: entries[j].name,
            label: entries[j].label,
            startupEnabled: result.enabled === true,
            startupSource: result.source === "user" || result.source === "system" ? result.source : entries[j].startupSource,
            source: result.source === "user" || result.source === "system" ? result.source : entries[j].source,
            controllable: entries[j].controllable
          }
        }
      }
    }
  }
  var code = result.code || result.reason || ""
  var unavailable = !ok && (
    code === "startup.home-unavailable" ||
    code === "startup.autostart-unreadable" ||
    code === "startup.autostart-unwritable"
  )
  var action = previous && previous.action || ""
  if (ok && Array.isArray(result.entries)) action = "list"
  else if (ok && typeof result.desktopId === "string") action = "set"
  return {
    phase: ok ? "succeeded" : "failed",
    action: action,
    entries: entries,
    empty: result.empty === true || (ok && entries.length === 0),
    unavailable: unavailable,
    message: clippedText(result.explanation || result.message || (ok ? "The session startup helper finished." : "The session startup helper failed."), MAX_DISPLAY_TEXT),
    code: code
  }
}

function sessionNightlightIdle() {
  return { phase: "idle", action: "", enabled: false, known: false, temperature: null, message: "", code: "" }
}

function sessionNightlightFailureCode(stderr) {
  var text = String(stderr || "")
  if (text.indexOf("not running") >= 0 || text.indexOf("not responding") >= 0 || text.indexOf("not ready") >= 0 || text.indexOf("OMARCHY_PATH") >= 0)
    return "nightlight.shell-unavailable"
  if (text.indexOf("Target not found") >= 0 || text.indexOf("Function not found") >= 0)
    return "nightlight.service-missing"
  return "nightlight.apply-failed"
}

function sessionNightlightFromIpc(kind, raw, exitCode, stderr) {
  var output = String(raw === undefined || raw === null ? "" : raw).trim()
  if (Number(exitCode) !== 0) {
    return {
      ok: false,
      enabled: false,
      known: false,
      temperature: null,
      code: sessionNightlightFailureCode(stderr),
      explanation: clippedText(String(stderr || "").trim() || "NightlightService is not reachable through this session.", MAX_DISPLAY_TEXT)
    }
  }
  if (output.charAt(0) === "\"" && output.charAt(output.length - 1) === "\"") {
    try {
      var unwrapped = JSON.parse(output)
      if (typeof unwrapped === "string") output = unwrapped
    } catch (unwrapError) {
    }
  }
  if (kind === "set") {
    var token = output.replace(/^"+|"+$/g, "")
    if (token === "enabled" || token === "disabled") {
      return {
        ok: true,
        enabled: token === "enabled",
        known: true,
        temperature: null,
        code: "",
        explanation: token === "enabled"
          ? "Night light is on through NightlightService."
          : "Night light is off through NightlightService."
      }
    }
    return {
      ok: false,
      enabled: false,
      known: false,
      temperature: null,
      code: "nightlight.parse-failed",
      explanation: "NightlightService returned an unreadable apply result."
    }
  }
  try {
    var parsed = JSON.parse(output)
    if (!isObject(parsed)) throw new Error("nightlight-status")
    var temperature = parsed.temperature
    if (temperature === "" || temperature === undefined) temperature = null
    if (temperature !== null) {
      temperature = Number(temperature)
      if (!isFinite(temperature)) temperature = null
    }
    var known = temperature !== null
    var enabled = parsed.enabled === true
    return {
      ok: true,
      enabled: enabled,
      known: known,
      temperature: temperature,
      code: "",
      explanation: !known
        ? "NightlightService could not read hyprsunset temperature."
        : enabled
          ? "Night light is on through NightlightService."
          : "Night light is off through NightlightService."
    }
  } catch (error) {
    return {
      ok: false,
      enabled: false,
      known: false,
      temperature: null,
      code: "nightlight.parse-failed",
      explanation: "NightlightService returned an unreadable status."
    }
  }
}

function sessionScalingAllowed() {
  return ["1", "1.25", "1.6", "2", "3", "4"]
}

function sessionScalingChoices() {
  return [
    { value: "1", label: "100%" },
    { value: "1.25", label: "125%" },
    { value: "1.6", label: "160%" },
    { value: "2", label: "200%" },
    { value: "3", label: "300%" },
    { value: "4", label: "400%" }
  ]
}

function sessionScalingLabel(scale) {
  var token = String(scale || "")
  var choices = sessionScalingChoices()
  var i
  for (i = 0; i < choices.length; i += 1) {
    if (choices[i].value === token) return choices[i].label
  }
  return token
}

function sessionScalingCanSubmit(scale) {
  return sessionScalingAllowed().indexOf(String(scale || "")) >= 0
}

function sessionScalingIdle() {
  return { phase: "idle", action: "", scale: "", known: false, message: "", code: "" }
}

function sessionScalingAccepted(previous, action) {
  var prior = isObject(previous) ? previous : sessionScalingIdle()
  return {
    phase: prior.phase,
    action: String(action || ""),
    scale: prior.scale || "",
    known: prior.known === true,
    message: prior.message || "",
    code: prior.code || ""
  }
}


function sessionSystemInformationIdle() {
  return {
    phase: "idle",
    action: "",
    available: false,
    hostname: "",
    osName: "",
    osVersion: "",
    osId: "",
    kernel: "",
    architecture: "",
    productLabel: "",
    cpuModel: "",
    memoryLabel: "",
    storageLabel: "",
    message: "",
    code: ""
  }
}

function sessionSystemInformationAccepted(previous, action) {
  var prior = isObject(previous) ? previous : sessionSystemInformationIdle()
  return {
    phase: prior.phase,
    action: String(action || ""),
    available: prior.available === true,
    hostname: prior.hostname || "",
    osName: prior.osName || "",
    osVersion: prior.osVersion || "",
    osId: prior.osId || "",
    kernel: prior.kernel || "",
    architecture: prior.architecture || "",
    productLabel: prior.productLabel || "",
    cpuModel: prior.cpuModel || "",
    memoryLabel: prior.memoryLabel || "",
    storageLabel: prior.storageLabel || "",
    message: prior.message || "",
    code: prior.code || ""
  }
}

function formatSystemInformationMib(value) {
  if (typeof value !== "number" || !isFinite(value) || value < 0) return ""
  var gib = value / 1024
  if (gib >= 10) return String(Math.round(gib)) + " GiB"
  if (gib >= 1) return (Math.round(gib * 10) / 10).toFixed(1).replace(/\.0$/, "") + " GiB"
  return String(Math.round(value)) + " MiB"
}

function formatSystemInformationBytes(value) {
  if (typeof value !== "number" || !isFinite(value) || value < 0) return ""
  var gib = value / (1024 * 1024 * 1024)
  if (gib >= 10) return String(Math.round(gib)) + " GiB"
  if (gib >= 1) return (Math.round(gib * 10) / 10).toFixed(1).replace(/\.0$/, "") + " GiB"
  var mib = value / (1024 * 1024)
  if (mib >= 1) return String(Math.round(mib)) + " MiB"
  return String(Math.round(value)) + " B"
}

function sessionSystemInformationProductLabel(product) {
  var row = isObject(product) ? product : {}
  var parts = []
  var vendor = clippedText(row.vendor || "", 120)
  var name = clippedText(row.name || "", 120)
  var version = clippedText(row.version || "", 120)
  if (vendor) parts.push(vendor)
  if (name && name !== vendor) parts.push(name)
  if (version && version !== name) parts.push(version)
  return parts.join(" · ")
}

function sessionSystemInformationFinished(previous, helperResult) {
  var result = isObject(helperResult) ? helperResult : {}
  var ok = result.ok === true
  var os = isObject(result.os) ? result.os : {}
  var product = isObject(result.product) ? result.product : {}
  var hardware = isObject(result.hardware) ? result.hardware : {}
  var storage = isObject(result.storage) ? result.storage : {}
  var memoryTotal = hardware.memoryTotalMib
  var memoryAvailable = hardware.memoryAvailableMib
  var memoryLabel = ""
  if (typeof memoryTotal === "number") {
    memoryLabel = formatSystemInformationMib(memoryTotal)
    if (typeof memoryAvailable === "number")
      memoryLabel = formatSystemInformationMib(memoryAvailable) + " available of " + memoryLabel
  }
  var storageLabel = ""
  if (storage.available === true && typeof storage.totalBytes === "number") {
    storageLabel = formatSystemInformationBytes(storage.usedBytes) + " used of " + formatSystemInformationBytes(storage.totalBytes)
    if (typeof storage.freeBytes === "number")
      storageLabel += " (" + formatSystemInformationBytes(storage.freeBytes) + " free)"
  }
  return {
    phase: ok ? "succeeded" : "failed",
    action: previous && previous.action || "",
    available: ok && result.available === true,
    hostname: clippedText(result.hostname || "", 160),
    osName: clippedText(os.name || "", 160),
    osVersion: clippedText(os.version || "", 120),
    osId: clippedText(os.id || "", 64),
    kernel: clippedText(os.kernel || "", 120),
    architecture: clippedText(os.architecture || "", 64),
    productLabel: sessionSystemInformationProductLabel(product),
    cpuModel: clippedText(hardware.cpuModel || "", 200),
    memoryLabel: memoryLabel,
    storageLabel: storageLabel,
    message: clippedText(result.explanation || result.message || (ok ? "The session system information helper finished." : "The session system information helper failed."), MAX_DISPLAY_TEXT),
    code: result.code || ""
  }
}

function sessionKeyboardLayoutIdle() {
  return { phase: "idle", action: "", layout: "", layouts: [], known: false, switchable: false, empty: false, message: "", code: "" }
}

function sessionKeyboardLayoutAccepted(previous, action) {
  var prior = isObject(previous) ? previous : sessionKeyboardLayoutIdle()
  return {
    phase: prior.phase,
    action: String(action || ""),
    layout: prior.layout || "",
    layouts: copyArray(prior.layouts),
    known: prior.known === true,
    switchable: prior.switchable === true,
    empty: prior.empty === true,
    message: prior.message || "",
    code: prior.code || ""
  }
}

function sessionKeyboardLayoutCanSubmit(layout, layouts) {
  var token = String(layout || "")
  var list = Array.isArray(layouts) ? layouts : []
  if (list.length < 2) return false
  return token !== "" && list.indexOf(token) >= 0
}

function sessionKeyboardLayoutFinished(previous, helperResult) {
  var result = isObject(helperResult) ? helperResult : {}
  var layouts = []
  if (Array.isArray(result.layouts)) {
    var i
    for (i = 0; i < result.layouts.length && i < 8; i += 1) {
      var name = result.layouts[i]
      if (typeof name !== "string" || name.length === 0 || name.length > 64) {
        layouts = []
        break
      }
      layouts.push(name)
    }
  }
  var ok = result.ok === true
  var layout = String(result.layout || "")
  if (layout && layouts.indexOf(layout) < 0) {
    ok = false
    result = {
      ok: false,
      layout: "",
      layouts: layouts,
      known: false,
      switchable: false,
      code: result.code || "layout.unknown",
      explanation: result.explanation || "The typed keyboard layout is not one of the configured layouts."
    }
    layout = ""
  }
  var empty = layouts.length === 0
  var known = result.known === true && layout !== "" && !empty
  return {
    phase: ok ? "succeeded" : "failed",
    action: previous && previous.action || "",
    layout: layout,
    layouts: layouts,
    known: known,
    switchable: layouts.length > 1,
    empty: empty,
    message: clippedText(result.explanation || result.message || (ok ? "The session keyboard layout helper finished." : "The session keyboard layout helper failed."), MAX_DISPLAY_TEXT),
    code: result.code || ""
  }
}

function sessionScalingFinished(previous, helperResult) {
  var result = isObject(helperResult) ? helperResult : {}
  var ok = result.ok === true
  var scale = String(result.scale || "")
  if (scale && sessionScalingAllowed().indexOf(scale) < 0) {
    ok = false
    result = {
      ok: false,
      scale: "",
      known: false,
      code: result.code || "scale.unknown",
      explanation: result.explanation || "The focused monitor scale is not one of the allowed Settings scales."
    }
    scale = ""
  }
  return {
    phase: ok ? "succeeded" : "failed",
    action: previous && previous.action || "",
    scale: scale,
    known: result.known === true && scale !== "",
    message: clippedText(result.explanation || result.message || (ok ? "The session monitor scaling helper finished." : "The session monitor scaling helper failed."), MAX_DISPLAY_TEXT),
    code: result.code || ""
  }
}

function sessionNightlightFinished(previous, helperResult) {
  var result = isObject(helperResult) ? helperResult : {}
  var ok = result.ok === true
  var temperature = result.temperature
  if (temperature === "" || temperature === undefined) temperature = null
  if (temperature !== null) {
    temperature = Number(temperature)
    if (!isFinite(temperature)) temperature = null
  }
  return {
    phase: ok ? "succeeded" : "failed",
    action: previous && previous.action || "",
    enabled: result.enabled === true,
    known: result.known === true,
    temperature: temperature,
    message: clippedText(result.explanation || result.message || (ok ? "NightlightService finished." : "NightlightService failed."), MAX_DISPLAY_TEXT),
    code: result.code || ""
  }
}



function sessionPrintersIdle() {
  return { phase: "idle", action: "", printers: [], defaultResourceId: "", known: false, empty: false, message: "", code: "" }
}

function sessionPrintersAccepted(previous, action) {
  var prior = isObject(previous) ? previous : sessionPrintersIdle()
  return {
    phase: "busy",
    action: String(action || ""),
    printers: Array.isArray(prior.printers) ? prior.printers.slice() : [],
    defaultResourceId: String(prior.defaultResourceId || ""),
    known: prior.known === true,
    empty: prior.empty === true,
    message: "",
    code: ""
  }
}

function sessionPrintersNormalizePrinters(raw) {
  if (!Array.isArray(raw)) return []
  var out = []
  for (var i = 0; i < raw.length && out.length < 32; i++) {
    var row = raw[i]
    if (!isObject(row)) continue
    var resourceId = String(row.resourceId || "")
    if (resourceId.indexOf("printer.") !== 0 || resourceId.length !== ("printer.".length + 24)) continue
    var accepting = null
    if (row.accepting === true) accepting = true
    if (row.accepting === false) accepting = false
    out.push({
      resourceId: resourceId,
      label: clippedText(row.label || "Printer", 128),
      connection: clippedText(row.connection || "unknown", 32),
      endpoint: clippedText(row.endpoint || "unknown", 253),
      accepting: accepting,
      default: row.default === true
    })
  }
  return out
}

function sessionPrintersCanSubmit(resourceId, printers) {
  var token = String(resourceId || "")
  if (token.indexOf("printer.") !== 0 || token.length !== ("printer.".length + 24)) return false
  var list = Array.isArray(printers) ? printers : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].resourceId === token) return true
  }
  return false
}

function sessionPrintersFinished(previous, helperResult) {
  var prior = isObject(previous) ? previous : sessionPrintersIdle()
  var result = isObject(helperResult) ? helperResult : {}
  var printers = sessionPrintersNormalizePrinters(result.printers)
  var defaultResourceId = String(result.defaultResourceId || "")
  if (defaultResourceId && !sessionPrintersCanSubmit(defaultResourceId, printers)) defaultResourceId = ""
  var known = result.known === true && printers.length > 0
  var empty = printers.length === 0
  var ok = result.ok === true
  var message = clippedText(result.explanation || result.message || "", MAX_DISPLAY_TEXT)
  if (!ok) {
    return {
      phase: "failed",
      action: String(prior.action || ""),
      printers: printers,
      defaultResourceId: defaultResourceId,
      known: false,
      empty: empty,
      message: message || "The session Printers helper failed.",
      code: String(result.code || "command.failed")
    }
  }
  if (known && result.resourceId && !sessionPrintersCanSubmit(result.resourceId, printers) && String(prior.action || "") !== "status") {
    return {
      phase: "failed",
      action: String(prior.action || ""),
      printers: printers,
      defaultResourceId: defaultResourceId,
      known: false,
      empty: empty,
      message: "The session Printers helper returned an unknown printer identity.",
      code: "payload.invalid"
    }
  }
  return {
    phase: "succeeded",
    action: String(prior.action || ""),
    printers: printers,
    defaultResourceId: defaultResourceId,
    known: known,
    empty: empty,
    message: message || (empty ? "No printers reported through this session." : "Typed printers through this session."),
    code: ""
  }
}

function sessionSoundIdle() {
  return { phase: "idle", action: "", sinks: [], defaultResourceId: "", known: false, empty: false, message: "", code: "" }
}

function sessionSoundAccepted(previous, action) {
  var prior = isObject(previous) ? previous : sessionSoundIdle()
  return {
    phase: "busy",
    action: String(action || ""),
    sinks: Array.isArray(prior.sinks) ? prior.sinks.slice() : [],
    defaultResourceId: String(prior.defaultResourceId || ""),
    known: prior.known === true,
    empty: prior.empty === true,
    message: "",
    code: ""
  }
}

function sessionSoundNormalizeSinks(raw) {
  if (!Array.isArray(raw)) return []
  var out = []
  for (var i = 0; i < raw.length && out.length < 8; i++) {
    var row = raw[i]
    if (!isObject(row)) continue
    var resourceId = String(row.resourceId || "")
    if (resourceId.indexOf("audio.sink.") !== 0 || resourceId.length !== ("audio.sink.".length + 64)) continue
    out.push({
      resourceId: resourceId,
      label: clippedText(row.label || "Audio output", 160),
      muted: row.muted === true,
      default: row.default === true
    })
  }
  return out
}

function sessionSoundCanSubmit(resourceId, sinks) {
  var token = String(resourceId || "")
  if (token.indexOf("audio.sink.") !== 0 || token.length !== ("audio.sink.".length + 64)) return false
  var list = Array.isArray(sinks) ? sinks : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].resourceId === token) return true
  }
  return false
}

function sessionSoundFinished(previous, helperResult) {
  var prior = isObject(previous) ? previous : sessionSoundIdle()
  var result = isObject(helperResult) ? helperResult : {}
  var sinks = sessionSoundNormalizeSinks(result.sinks)
  var defaultResourceId = String(result.defaultResourceId || "")
  if (defaultResourceId && !sessionSoundCanSubmit(defaultResourceId, sinks)) defaultResourceId = ""
  var known = result.known === true && sinks.length > 0
  var empty = sinks.length === 0
  var ok = result.ok === true
  var message = clippedText(result.explanation || result.message || "", MAX_DISPLAY_TEXT)
  if (!ok) {
    return {
      phase: "failed",
      action: String(prior.action || ""),
      sinks: sinks,
      defaultResourceId: defaultResourceId,
      known: false,
      empty: empty,
      message: message || "The session Sound helper failed.",
      code: String(result.code || "command.failed")
    }
  }
  if (known && result.resourceId && !sessionSoundCanSubmit(result.resourceId, sinks) && String(prior.action || "") !== "status" && String(prior.action || "") !== "troubleshoot") {
    return {
      phase: "failed",
      action: String(prior.action || ""),
      sinks: sinks,
      defaultResourceId: defaultResourceId,
      known: false,
      empty: empty,
      message: "The session Sound helper returned an unknown sink identity.",
      code: "payload.invalid"
    }
  }
  return {
    phase: "succeeded",
    action: String(prior.action || ""),
    sinks: sinks,
    defaultResourceId: defaultResourceId,
    known: known,
    empty: empty,
    message: message || (empty ? "No audio outputs reported through this session." : "Typed audio outputs through this session."),
    code: ""
  }
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
    protocolAssociation: protocolAssociation,
    browserAssociation: browserAssociation,
    mailerAssociation: mailerAssociation,
    browserCandidates: browserCandidates,
    mimeAssociations: mimeAssociations,
    normalizeStartup: normalizeStartup,
    startupEntries: startupEntries,
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
    isDefaultsWriterRoute: isDefaultsWriterRoute,
    routeHasLiveWriter: routeHasLiveWriter,
    coverageBadge: coverageBadge,
    coverageTone: coverageTone,
    declaredOpsHonesty: declaredOpsHonesty,
    authorityFooter: authorityFooter,
    operationIdempotencyToken: operationIdempotencyToken,
    mimeDefaultIdempotencyKey: mimeDefaultIdempotencyKey,
    WIFI_JOIN_MAX_ROWS: WIFI_JOIN_MAX_ROWS,
    WIFI_JOIN_SECURITY: WIFI_JOIN_SECURITY,
    wifiJoinRow: wifiJoinRow,
    sortWifiJoinRows: sortWifiJoinRows,
    wifiJoinAction: wifiJoinAction,
    wifiJoinCanSubmit: wifiJoinCanSubmit,
    wifiJoinFailureReason: wifiJoinFailureReason,
    BLUETOOTH_PAIR_MAX_ROWS: BLUETOOTH_PAIR_MAX_ROWS,
    bluetoothHasHumanName: bluetoothHasHumanName,
    bluetoothDeviceRow: bluetoothDeviceRow,
    bluetoothDeviceGroups: bluetoothDeviceGroups,
    bluetoothPairAction: bluetoothPairAction,
    bluetoothCanSubmit: bluetoothCanSubmit,
    sessionUpdateIdle: sessionUpdateIdle,
    sessionUpdatePlan: sessionUpdatePlan,
    sessionUpdateCanSubmit: sessionUpdateCanSubmit,
    sessionUpdateAccepted: sessionUpdateAccepted,
    sessionUpdateFinished: sessionUpdateFinished,
    sessionUpdateHistoryIdle: sessionUpdateHistoryIdle,
    sessionUpdateHistoryFinished: sessionUpdateHistoryFinished,
    sessionStartupIdle: sessionStartupIdle,
    sessionStartupNormalizeEntry: sessionStartupNormalizeEntry,
    sessionStartupCanSubmit: sessionStartupCanSubmit,
    sessionStartupAccepted: sessionStartupAccepted,
    sessionStartupFinished: sessionStartupFinished,
    sessionNightlightIdle: sessionNightlightIdle,
    sessionNightlightFailureCode: sessionNightlightFailureCode,
    sessionNightlightFromIpc: sessionNightlightFromIpc,
    sessionNightlightFinished: sessionNightlightFinished,
    sessionScalingAllowed: sessionScalingAllowed,
    sessionScalingChoices: sessionScalingChoices,
    sessionScalingLabel: sessionScalingLabel,
    sessionScalingCanSubmit: sessionScalingCanSubmit,
    sessionScalingIdle: sessionScalingIdle,
    sessionScalingAccepted: sessionScalingAccepted,
    sessionScalingFinished: sessionScalingFinished,
    sessionKeyboardLayoutIdle: sessionKeyboardLayoutIdle,
    sessionKeyboardLayoutAccepted: sessionKeyboardLayoutAccepted,
    sessionKeyboardLayoutCanSubmit: sessionKeyboardLayoutCanSubmit,
    sessionKeyboardLayoutFinished: sessionKeyboardLayoutFinished,
    sessionSystemInformationIdle: sessionSystemInformationIdle,
    sessionSystemInformationAccepted: sessionSystemInformationAccepted,
    sessionSystemInformationFinished: sessionSystemInformationFinished,
    sessionSoundIdle: sessionSoundIdle,
    sessionSoundAccepted: sessionSoundAccepted,
    sessionSoundCanSubmit: sessionSoundCanSubmit,
    sessionSoundFinished: sessionSoundFinished,
    sessionPrintersIdle: sessionPrintersIdle,
    sessionPrintersAccepted: sessionPrintersAccepted,
    sessionPrintersCanSubmit: sessionPrintersCanSubmit,
    sessionPrintersFinished: sessionPrintersFinished
  }
}
