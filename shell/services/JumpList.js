
function normalizeDesktopId(id) {
  var value = String(id || "").trim()
  if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
  return value
}

function sameDesktopId(a, b) {
  return normalizeDesktopId(a).toLowerCase() === normalizeDesktopId(b).toLowerCase()
}

function iconNameFor(id) {
  var value = normalizeDesktopId(id).toLowerCase()
  if (value === "org.omarchy.terminal" || value === "tui.float" || value === "tui.tile")
    return "foot"
  return ""
}

function copyLengthList(value) {
  if (!isLengthList(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function isLengthList(value) {
  return !!value && typeof value !== "function" && typeof value.length === "number"
}

function actionList(entry) {
  if (!entry) return []
  var raw = entry.actions
  if (!raw || typeof raw === "function") return []
  if (isLengthList(raw)) return copyLengthList(raw)
  if (raw.values && typeof raw.values !== "function" && isLengthList(raw.values))
    return copyLengthList(raw.values)
  return []
}

function actionCommand(action) {
  if (!action) return ""
  if (isLengthList(action.command) && action.command.length > 0)
    return copyLengthList(action.command).map(function(part) { return String(part) }).join(" ")
  if (typeof action.execString === "string" && action.execString.length > 0) return action.execString
  if (typeof action.exec === "string" && action.exec.length > 0) return action.exec
  if (typeof action.command === "string" && action.command.length > 0) return action.command
  return ""
}

function actionName(action) {
  if (!action) return ""
  return String(action.name || action.id || "").trim()
}

function actionId(action) {
  if (!action) return ""
  return String(action.id || action.name || "").trim()
}

function desktopActions(entry) {
  var raw = actionList(entry)
  var out = []
  var seen = {}
  for (var i = 0; i < raw.length; i++) {
    var action = raw[i]
    var command = actionCommand(action)
    var name = actionName(action)
    if (!command || !name) continue
    var id = actionId(action) || name
    if (seen[id]) continue
    seen[id] = true
    out.push({
      id: id,
      name: name,
      command: command,
      kind: "desktop-action"
    })
  }
  return out
}

function desktopIdAliases(id) {
  var value = normalizeDesktopId(id)
  var aliases = [value]
  if (value === "google-chrome") {
    aliases.push("google-chrome-stable")
    aliases.push("chromium")
  }
  if (value === "google-chrome-stable") aliases.push("google-chrome")
  return aliases
}

function indexedActions(actionIndex, desktopId) {
  if (!actionIndex) return []
  var aliases = desktopIdAliases(desktopId)
  var i
  var key
  var rows
  for (i = 0; i < aliases.length; i++) {
    rows = actionIndex[aliases[i]]
    if (isLengthList(rows) && rows.length > 0) return copyLengthList(rows)
  }
  for (i = 0; i < aliases.length; i++) {
    for (key in actionIndex) {
      if (!Object.prototype.hasOwnProperty.call(actionIndex, key)) continue
      if (!sameDesktopId(key, aliases[i])) continue
      rows = actionIndex[key]
      if (isLengthList(rows) && rows.length > 0) return copyLengthList(rows)
    }
  }
  return []
}

function jumpListFor(entry, desktopId, actionIndex) {
  var id = normalizeDesktopId(desktopId || (entry && entry.id) || "")
  var items = [{
    id: "",
    name: "Open new window",
    command: "",
    kind: "open-new",
    desktopId: id
  }]
  var fromEntry = desktopActions(entry)
  if (fromEntry.length > 0) return items.concat(fromEntry)
  return items.concat(indexedActions(actionIndex, id))
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeDesktopId: normalizeDesktopId,
    sameDesktopId: sameDesktopId,
    iconNameFor: iconNameFor,
    actionList: actionList,
    actionCommand: actionCommand,
    desktopActions: desktopActions,
    desktopIdAliases: desktopIdAliases,
    indexedActions: indexedActions,
    jumpListFor: jumpListFor
  }
}
