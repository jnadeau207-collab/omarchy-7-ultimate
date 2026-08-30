// Structured Superbar peek model. Each running window is one row with the
// fields the peek can actually show: icon, title, workspace, minimized,
// and the address used to activate or close. There is no bitmap capture
// path here and no silent substitute for one.

function windowTitle(win) {
  if (!win) return "Window"
  return String(win.title || win.appId || "Window")
}

function workspaceLabel(win) {
  if (!win) return ""
  if (win.workspaceId !== undefined && win.workspaceId !== null && String(win.workspaceId) !== "")
    return String(win.workspaceId)
  if (win.workspace && typeof win.workspace === "object")
    return String(win.workspace.id || win.workspace.name || "")
  if (win.workspace === undefined || win.workspace === null) return ""
  return String(win.workspace)
}

function previewRow(win) {
  if (!win) return null
  return {
    address: String(win.address || ""),
    title: windowTitle(win),
    appId: String(win.appId || ""),
    workspace: workspaceLabel(win),
    minimized: win.minimized === true,
    mapped: win.mapped !== false
  }
}

function isLengthList(value) {
  return !!value && typeof value !== "function" && typeof value.length === "number"
}

function previewRows(windows) {
  var list = isLengthList(windows) ? windows : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var row = previewRow(list[i])
    if (row && row.address) out.push(row)
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    windowTitle: windowTitle,
    workspaceLabel: workspaceLabel,
    previewRow: previewRow,
    previewRows: previewRows
  }
}
