function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
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

function isStableId(value) {
  return typeof value === "string" && /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/.test(value) && value.length <= 128
}

function isOpaqueId(value) {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$/.test(value)
}

function isAppId(value) {
  return typeof value === "string" && value.length <= 255 && /^[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)+$/.test(value)
}

function expectedScheme(application) {
  if (application === "settings") return "omarchy-settings"
  if (application === "agent-center") return "omarchy-agent"
  return ""
}

function fail(code, explanation) {
  return { ok: false, code: code, explanation: explanation }
}

function validateArgument(value, contract) {
  if (!isObject(contract) || typeof contract.type !== "string") return false
  if (contract.type === "stable-id") return isStableId(value)
  if (contract.type === "opaque-id") return isOpaqueId(value)
  if (contract.type === "boolean") return typeof value === "boolean"
  if (contract.type === "integer") return typeof value === "number" && isFinite(value) && Math.floor(value) === value
  if (contract.type === "enum") return Array.isArray(contract.values) && contract.values.indexOf(value) >= 0
  return false
}

function validateArgumentContract(contract) {
  if (!isObject(contract) || typeof contract.type !== "string") return "argument contract must be an object with a type"
  var kinds = ["stable-id", "opaque-id", "boolean", "integer", "enum"]
  if (kinds.indexOf(contract.type) < 0) return "argument type is unsupported"
  var keys = ["type"]
  if (Object.prototype.hasOwnProperty.call(contract, "optional")) {
    if (typeof contract.optional !== "boolean") return "argument optional flag must be boolean"
    keys.push("optional")
  }
  if (contract.type === "enum") keys.push("values")
  if (!exactKeys(contract, keys)) return "argument contract has unexpected or missing fields"
  if (contract.type !== "enum") return ""
  if (!Array.isArray(contract.values) || contract.values.length < 1 || contract.values.length > 32)
    return "argument enum values are invalid"
  var seen = Object.create(null)
  for (var i = 0; i < contract.values.length; i++) {
    var value = contract.values[i]
    if (typeof value !== "string" || value.length < 1 || value.length > 128)
      return "argument enum values must be bounded strings"
    if (seen[value]) return "argument enum repeats a value"
    seen[value] = true
  }
  return ""
}

function validateRoute(route) {
  if (!isObject(route) || !isStableId(route.id)) return "route IDs must be stable dotted identifiers"
  var routeKeys = ["id", "section", "title", "description", "keywords", "providerId", "argumentSchema"]
  if (Object.prototype.hasOwnProperty.call(route, "deepLink")) routeKeys.push("deepLink")
  if (!exactKeys(route, routeKeys)) return "route has unexpected or missing fields"
  if (typeof route.section !== "string" || route.section.length < 1 || route.section.length > 80) return "route section is invalid"
  if (typeof route.title !== "string" || route.title.length < 1 || route.title.length > 120) return "route title is invalid"
  if (typeof route.description !== "string" || route.description.length < 1 || route.description.length > 320) return "route description is invalid"
  if (!Array.isArray(route.keywords) || route.keywords.length > 32) return "route keywords are invalid"
  for (var i = 0; i < route.keywords.length; i++) {
    if (typeof route.keywords[i] !== "string" || route.keywords[i].length < 1 || route.keywords[i].length > 80)
      return "route keyword is invalid"
  }
  if (typeof route.providerId !== "string" || (route.providerId !== "" && !isStableId(route.providerId)))
    return "route provider identity is invalid"
  if (!isObject(route.argumentSchema)) return "route argument schema must be an object"
  var argumentNames = Object.keys(route.argumentSchema)
  for (i = 0; i < argumentNames.length; i++) {
    var name = argumentNames[i]
    var contract = route.argumentSchema[name]
    if (!/^[a-z][A-Za-z0-9]{0,47}$/.test(name) || !isObject(contract)) return "route argument contract is invalid"
    var contractProblem = validateArgumentContract(contract)
    if (contractProblem !== "") return contractProblem
  }
  if (Object.prototype.hasOwnProperty.call(route, "deepLink")) {
    if (!exactKeys(route.deepLink, ["host", "path"])) return "route deep link contract is invalid"
    if (typeof route.deepLink.host !== "string" || !/^[a-z][a-z0-9-]{0,62}$/.test(route.deepLink.host)) return "route deep link host is invalid"
    if (typeof route.deepLink.path !== "string" || route.deepLink.path.length > 256 || !/^[a-z0-9-]*(?:\/[a-z0-9-]+)*$/.test(route.deepLink.path))
      return "route deep link path is invalid"
  }
  return ""
}

function validateCatalog(candidate, expectedApplication, expectedAppId) {
  if (!isObject(candidate)) return fail("catalog.invalid", "The route catalog is not an object.")
  if (!exactKeys(candidate, ["schemaVersion", "application", "appId", "scheme", "defaultRoute", "routes", "entityDeepLinks"]))
    return fail("catalog.invalid", "The route catalog has unexpected or missing fields.")
  if (candidate.schemaVersion !== "omarchy.product-routes/v1")
    return fail("catalog.incompatible", "The route catalog schema is not supported.")
  if (candidate.application !== expectedApplication || candidate.appId !== expectedAppId)
    return fail("catalog.identity-mismatch", "The route catalog belongs to a different application identity.")
  if (!isStableId(candidate.application) || !isAppId(candidate.appId) || !isAppId(expectedAppId))
    return fail("catalog.invalid", "The route catalog identity is invalid.")
  var scheme = expectedScheme(expectedApplication)
  if (scheme === "" || typeof candidate.scheme !== "string" || candidate.scheme !== scheme || !/^[a-z][a-z0-9-]{1,62}$/.test(candidate.scheme))
    return fail("catalog.invalid", "The route catalog scheme is invalid.")
  if (!isStableId(candidate.defaultRoute)) return fail("catalog.invalid-default", "The default route identity is invalid.")
  if (!Array.isArray(candidate.routes) || candidate.routes.length < 1 || candidate.routes.length > 128)
    return fail("catalog.invalid", "The route catalog must contain between one and 128 routes.")
  var routeIndex = Object.create(null)
  var deepLinkIndex = Object.create(null)
  for (var i = 0; i < candidate.routes.length; i++) {
    var problem = validateRoute(candidate.routes[i])
    if (problem !== "") return fail("catalog.invalid", problem)
    var route = candidate.routes[i]
    if (routeIndex[route.id]) return fail("catalog.duplicate-route", "The route catalog repeats " + route.id + ".")
    routeIndex[route.id] = route
    if (route.deepLink) {
      var deepLinkKey = route.deepLink.host + "/" + route.deepLink.path
      if (deepLinkIndex[deepLinkKey]) return fail("catalog.duplicate-link", "The route catalog repeats a deep link.")
      deepLinkIndex[deepLinkKey] = route.id
    }
  }
  if (!routeIndex[candidate.defaultRoute]) return fail("catalog.invalid-default", "The default route is not registered.")
  if (!Array.isArray(candidate.entityDeepLinks) || candidate.entityDeepLinks.length > 32)
    return fail("catalog.invalid", "The entity deep link table is invalid.")
  var entityHosts = Object.create(null)
  for (i = 0; i < candidate.entityDeepLinks.length; i++) {
    var link = candidate.entityDeepLinks[i]
    if (!exactKeys(link, ["host", "routeId", "entityType"]) ||
        typeof link.host !== "string" || !/^[a-z][a-z0-9-]{0,62}$/.test(link.host) ||
        !isStableId(link.routeId) || !routeIndex[link.routeId] || !isStableId(link.entityType))
      return fail("catalog.invalid", "An entity deep link is invalid.")
    if (entityHosts[link.host]) return fail("catalog.duplicate-link", "The route catalog repeats an entity link host.")
    entityHosts[link.host] = true
  }
  return { ok: true, catalog: candidate, routeIndex: routeIndex }
}

function validateContext(context) {
  if (!exactKeys(context, ["screen", "anchor", "seat", "focusReturn", "source"]))
    return "the invocation context has unexpected or missing fields"
  if (context.screen !== null && !isOpaqueId(context.screen)) return "the requested screen is invalid"
  if (context.seat !== null && !isOpaqueId(context.seat)) return "the input seat is invalid"
  if (context.focusReturn !== null && !isOpaqueId(context.focusReturn)) return "the focus return target is invalid"
  if (["cli", "desktop", "shell", "notification", "automation"].indexOf(context.source) < 0)
    return "the invocation source is invalid"
  if (context.anchor !== null) {
    if (!exactKeys(context.anchor, ["x", "y", "width", "height"])) return "the invocation anchor is invalid"
    var values = [context.anchor.x, context.anchor.y, context.anchor.width, context.anchor.height]
    for (var i = 0; i < values.length; i++) {
      if (typeof values[i] !== "number" || !isFinite(values[i]) || Math.floor(values[i]) !== values[i] || Math.abs(values[i]) > 100000)
        return "the invocation anchor contains an invalid coordinate"
    }
    if (context.anchor.width < 1 || context.anchor.height < 1) return "the invocation anchor must have a positive size"
  }
  return ""
}

function validateEnvelope(raw, catalog) {
  var envelope
  try {
    envelope = typeof raw === "string" ? JSON.parse(raw) : raw
  } catch (error) {
    return fail("launch.invalid-json", "The launch envelope is not valid JSON.")
  }
  if (!isObject(catalog)) return fail("launch.catalog-unavailable", "The route catalog is unavailable.")
  if (!exactKeys(envelope, ["schemaVersion", "application", "routeId", "arguments", "context"]))
    return fail("launch.invalid-envelope", "The launch envelope has unexpected or missing fields.")
  if (envelope.schemaVersion !== "omarchy.product-launch/v1" || envelope.application !== catalog.application)
    return fail("launch.identity-mismatch", "The launch envelope belongs to a different protocol or application.")
  var route = null
  for (var i = 0; i < catalog.routes.length; i++) {
    if (catalog.routes[i].id === envelope.routeId) {
      route = catalog.routes[i]
      break
    }
  }
  if (!route) return fail("launch.unknown-route", "The requested route is not registered.")
  if (!isObject(envelope.arguments)) return fail("launch.invalid-arguments", "Route arguments must be an object.")
  var names = Object.keys(envelope.arguments)
  for (i = 0; i < names.length; i++) {
    var name = names[i]
    if (!Object.prototype.hasOwnProperty.call(route.argumentSchema, name))
      return fail("launch.unknown-argument", "The route does not accept " + name + ".")
    if (!validateArgument(envelope.arguments[name], route.argumentSchema[name]))
      return fail("launch.invalid-argument", "The route argument " + name + " has the wrong type.")
  }
  var contracts = Object.keys(route.argumentSchema)
  for (i = 0; i < contracts.length; i++) {
    var contractName = contracts[i]
    if (route.argumentSchema[contractName].optional !== true && !Object.prototype.hasOwnProperty.call(envelope.arguments, contractName))
      return fail("launch.missing-argument", "The route requires " + contractName + ".")
  }
  var contextProblem = validateContext(envelope.context)
  if (contextProblem !== "") return fail("launch.invalid-context", contextProblem)
  return { ok: true, envelope: envelope, route: route }
}

if (typeof module !== "undefined") {
  module.exports = {
    exactKeys: exactKeys,
    isStableId: isStableId,
    isOpaqueId: isOpaqueId,
    validateCatalog: validateCatalog,
    validateEnvelope: validateEnvelope
  }
}
