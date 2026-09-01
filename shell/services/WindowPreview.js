
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

function geometry(win) {
  if (!win) return null
  var x = 0
  var y = 0
  var width = 0
  var height = 0
  if (isLengthList(win.at) && win.at.length >= 2) {
    x = Number(win.at[0])
    y = Number(win.at[1])
  } else {
    x = Number(win.x || 0)
    y = Number(win.y || 0)
  }
  if (isLengthList(win.size) && win.size.length >= 2) {
    width = Number(win.size[0])
    height = Number(win.size[1])
  } else {
    width = Number(win.width || 0)
    height = Number(win.height || 0)
  }
  if (!(width > 0) || !(height > 0) || !isFinite(x) || !isFinite(y)) return null
  return { x: x, y: y, width: width, height: height }
}

function workspaceIdOf(win) {
  if (!win) return ""
  if (win.workspaceId !== undefined && win.workspaceId !== null && String(win.workspaceId) !== "")
    return win.workspaceId
  if (win.workspace && typeof win.workspace === "object")
    return win.workspace.id
  if (win.workspace === undefined || win.workspace === null) return ""
  return win.workspace
}

function onActiveDesktop(win, activeDesktopId) {
  if (activeDesktopId === undefined || activeDesktopId === null || String(activeDesktopId) === "") return true
  var id = Number(activeDesktopId)
  if (!isFinite(id) || id <= 0) return true
  var winId = workspaceIdOf(win)
  if (winId === undefined || winId === null || String(winId) === "") return true
  return Number(winId) === id
}

function sameOutput(a, b) {
  var left = String((a && (a.monitorName || a.monitor)) || "")
  var right = String((b && (b.monitorName || b.monitor)) || "")
  if (!left || !right) return true
  return left === right
}

function rectsOverlap(a, b) {
  var left = geometry(a)
  var right = geometry(b)
  if (!left || !right) return false
  if (left.x + left.width <= right.x || right.x + right.width <= left.x) return false
  if (left.y + left.height <= right.y || right.y + right.height <= left.y) return false
  return true
}

function focusRank(win) {
  var n = Number(win && win.focusHistoryID)
  if (!isFinite(n)) return null
  return n
}

function coversWindow(other, win) {
  if (!other || !win) return false
  if (String(other.address || "") === String(win.address || "")) return false
  if (other.minimized === true || other.hidden === true) return false
  if (other.mapped === false) return false
  if (!sameOutput(other, win)) return false
  if (!onActiveDesktop(other, workspaceIdOf(win))) return false
  if (!rectsOverlap(other, win)) return false
  var otherRank = focusRank(other)
  var winRank = focusRank(win)
  if (otherRank === null || winRank === null) return true
  return otherRank < winRank
}

function isOccluded(win, others) {
  var list = isLengthList(others) ? others : []
  var i
  for (i = 0; i < list.length; i++) {
    if (coversWindow(list[i], win)) return true
  }
  return false
}

function previewRow(win, activeDesktopId, others) {
  if (!win) return null
  var box = geometry(win)
  var minimized = win.minimized === true || win.hidden === true
  return {
    address: String(win.address || ""),
    title: windowTitle(win),
    appId: String(win.appId || ""),
    workspace: workspaceLabel(win),
    minimized: minimized,
    mapped: win.mapped !== false,
    x: box ? box.x : 0,
    y: box ? box.y : 0,
    width: box ? box.width : 0,
    height: box ? box.height : 0,
    capturable: !!(box && !minimized && onActiveDesktop(win, activeDesktopId) && !isOccluded(win, others))
  }
}

function isLengthList(value) {
  return !!value && typeof value !== "function" && typeof value.length === "number"
}

function previewRows(windows, activeDesktopId, others) {
  var list = isLengthList(windows) ? windows : []
  var occluders = isLengthList(others) ? others : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var row = previewRow(list[i], activeDesktopId, occluders)
    if (row && row.address) out.push(row)
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    windowTitle: windowTitle,
    workspaceLabel: workspaceLabel,
    previewRow: previewRow,
    previewRows: previewRows,
    geometry: geometry,
    onActiveDesktop: onActiveDesktop,
    workspaceIdOf: workspaceIdOf,
    rectsOverlap: rectsOverlap,
    isOccluded: isOccluded,
    coversWindow: coversWindow
  }
}
