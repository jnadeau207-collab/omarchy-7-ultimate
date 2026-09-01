pragma Singleton
import Quickshell
import QtQuick

QtObject {
  id: root

  function clamp(value, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return min
    return Math.max(min, Math.min(max, n))
  }

  function clampAlpha(value) {
    return clamp(value, 0, 1)
  }

  function wheelSteps(accumulator, delta) {
    delta = Math.max(-120, Math.min(120, delta))
    if (accumulator * delta < 0) accumulator = 0
    var total = accumulator + delta
    var steps = total < 0 ? Math.ceil(total / 120) : Math.floor(total / 120)
    return { steps: steps, remainder: total - steps * 120 }
  }

  function alpha(c, opacity) {
    var a = clampAlpha(opacity)
    if (!c) return Qt.rgba(0, 0, 0, a)
    if (typeof c === "string") c = Qt.color(c)
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  function fileUrl(path) {
    if (!path) return ""
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function execDetached(command) {
    Quickshell.execDetached(["bash", "-lc", command])
  }

  function execArgv(argv) {
    Quickshell.execDetached(["bash", "-lc", 'exec "$@"', "bash"].concat(argv))
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function canonicalWidgetId(id) {
    return String(id || "")
  }

  function decodeBase64(value) {
    var s = String(value || "")
    if (!s) return ""
    try { return Qt.atob(s) } catch (e) { return "" }
  }

  function cloneJson(value) {
    return JSON.parse(JSON.stringify(value === undefined ? null : value))
  }

  function parseModuleJson(raw) {
    var text = String(raw || "").trim()
    if (!text) return {}
    var lines = text.split("\n")
    try {
      return JSON.parse(lines[lines.length - 1])
    } catch (e) {
      return { text: text }
    }
  }

  function editsFilter(event, text) {
    if (!text) return false
    if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) return false
    if (event.key === Qt.Key_U)
      return event.modifiers === Qt.ControlModifier
    return event.key === Qt.Key_Backspace
  }

  function editedFilter(event, text) {
    if (event.key === Qt.Key_U) return ""
    if (event.modifiers & Qt.ControlModifier)
      return text.replace(/\s+$/, "").replace(/\S+$/, "")
    return text.slice(0, -1)
  }

  function normalizeLayoutEntry(entry) {
    if (typeof entry === "string") return { id: canonicalWidgetId(entry) }
    if (isPlainObject(entry) && entry.id) {
      var copy = cloneJson(entry)
      copy.id = canonicalWidgetId(copy.id)
      return copy
    }
    return null
  }

  function normalizeLayoutSection(list) {
    if (!Array.isArray(list)) return []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var e = normalizeLayoutEntry(list[i])
      if (e) out.push(e)
    }
    return out
  }

  function normalizeLayout(layout) {
    var src = isPlainObject(layout) ? layout : {}
    return {
      left:   normalizeLayoutSection(src.left),
      center: normalizeLayoutSection(src.center),
      right:  normalizeLayoutSection(src.right)
    }
  }
}
