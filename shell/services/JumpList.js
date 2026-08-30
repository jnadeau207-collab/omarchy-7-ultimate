// Jump lists for Superbar task buttons. The default action is always
// "Open new window". Extra rows come from the desktop entry's Actions=
// groups when the entry exposes a launchable command. Entries without a
// command are omitted rather than shown as dead items.

function normalizeDesktopId(id) {
  var value = String(id || "").trim()
  if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
  return value
}

function copyLengthList(value) {
  if (!value || value.length === undefined) return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function actionList(entry) {
  if (!entry) return []
  var raw = entry.actions
  if (!raw) return []
  if (Array.isArray(raw) || raw.length !== undefined) return copyLengthList(raw)
  if (raw.values && (Array.isArray(raw.values) || raw.values.length !== undefined))
    return copyLengthList(raw.values)
  return []
}

function actionCommand(action) {
  if (!action) return ""
  if (Array.isArray(action.command) && action.command.length > 0)
    return action.command.map(function(part) { return String(part) }).join(" ")
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

function jumpListFor(entry, desktopId) {
  var id = normalizeDesktopId(desktopId || (entry && entry.id) || "")
  var items = [{
    id: "",
    name: "Open new window",
    command: "",
    kind: "open-new",
    desktopId: id
  }]
  return items.concat(desktopActions(entry))
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeDesktopId: normalizeDesktopId,
    actionList: actionList,
    actionCommand: actionCommand,
    desktopActions: desktopActions,
    jumpListFor: jumpListFor
  }
}
