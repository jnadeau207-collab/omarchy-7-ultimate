.pragma library

var OPERATION_IDS = [
  "success", "no-op", "progress", "denial", "failure", "cancel", "restart", "recovery"
]

var OPERATION_DEFINITIONS = {
  "success": {
    label: "Success",
    message: "The requested change completed.",
    tone: "success",
    symbol: "\u2713",
    primaryAction: "Done"
  },
  "no-op": {
    label: "No change needed",
    message: "The requested state was already active.",
    tone: "info",
    symbol: "\u2014",
    primaryAction: "Done"
  },
  "progress": {
    label: "Working",
    message: "The operation is still in progress.",
    tone: "info",
    symbol: "\u2026",
    primaryAction: "Cancel"
  },
  "denial": {
    label: "Permission denied",
    message: "The operation was not authorized and made no change.",
    tone: "danger",
    symbol: "!",
    primaryAction: "Review"
  },
  "failure": {
    label: "Could not complete",
    message: "The operation failed without claiming success.",
    tone: "danger",
    symbol: "\u00d7",
    primaryAction: "Try again"
  },
  "cancel": {
    label: "Cancelled",
    message: "The operation stopped before completion.",
    tone: "warning",
    symbol: "\u25a0",
    primaryAction: "Retry"
  },
  "restart": {
    label: "Restart required",
    message: "Restart the affected service to finish applying the change.",
    tone: "warning",
    symbol: "\u21bb",
    primaryAction: "Restart"
  },
  "recovery": {
    label: "Recovery available",
    message: "A known-good previous state can be restored.",
    tone: "success",
    symbol: "\u21a9",
    primaryAction: "Restore"
  }
}

var DENSITY_SCALE = { compact: 0.86, comfortable: 1.0, touch: 1.25 }
var TARGET_SIZE = { compact: 28, comfortable: 32, touch: 44 }

function clamp(value, minimum, maximum) {
  var number = Number(value)
  if (!isFinite(number)) return minimum
  return Math.max(minimum, Math.min(maximum, number))
}

function normalizeDensity(value) {
  var density = String(value || "comfortable")
  return DENSITY_SCALE[density] === undefined ? "comfortable" : density
}

function densityScale(value) {
  return DENSITY_SCALE[normalizeDensity(value)]
}

function displayScale(value) {
  return clamp(value === undefined ? 1 : value, 0.5, 2)
}

function fontScale(profile) {
  var source = profile || {}
  var large = source.largeText ? clamp(source.textScale || 1.25, 1, 2) : 1
  return displayScale(source.scaleFactor) * large
}

function spacingScale(profile) {
  var source = profile || {}
  return densityScale(source.densityMode) * displayScale(source.scaleFactor)
}

function scaledMetric(value, profile, minimum) {
  var result = Math.round(clamp(value, 0, 4096) * spacingScale(profile))
  return Math.max(minimum === undefined ? 0 : minimum, result)
}

function scaledFont(value, profile) {
  return Math.max(1, Math.round(clamp(value, 1, 4096) * fontScale(profile)))
}

function minimumTarget(profile) {
  var source = profile || {}
  var density = normalizeDensity(source.densityMode)
  var base = TARGET_SIZE[density]
  return Math.max(base, Math.round(base * displayScale(source.scaleFactor)))
}

function duration(milliseconds, profile) {
  var source = profile || {}
  if (source.reducedMotion) return 0
  return Math.round(clamp(milliseconds, 0, 60000))
}

function operationIds() {
  return OPERATION_IDS.slice()
}

function operationDefinition(id) {
  var key = String(id || "failure")
  var source = OPERATION_DEFINITIONS[key] || OPERATION_DEFINITIONS.failure
  return {
    id: OPERATION_DEFINITIONS[key] ? key : "failure",
    label: source.label,
    message: source.message,
    tone: source.tone,
    symbol: source.symbol,
    primaryAction: source.primaryAction
  }
}

var PSEUDO_MAP = {
  a: "\u00e4", A: "\u00c4", b: "\u0180", B: "\u0181", c: "\u00e7", C: "\u00c7",
  d: "\u0111", D: "\u0110", e: "\u00eb", E: "\u00cb", f: "\u0192", F: "\u0191",
  g: "\u011d", G: "\u011c", h: "\u0127", H: "\u0126", i: "\u00ef", I: "\u00cf",
  j: "\u0135", J: "\u0134", k: "\u0137", K: "\u0136", l: "\u013a", L: "\u0139",
  m: "\u0271", M: "\u2c6e", n: "\u00f1", N: "\u00d1", o: "\u00f6", O: "\u00d6",
  p: "\u00fe", P: "\u00de", q: "\u024b", Q: "\u024a", r: "\u0155", R: "\u0154",
  s: "\u0161", S: "\u0160", t: "\u0167", T: "\u0166", u: "\u00fc", U: "\u00dc",
  v: "\u1e7d", V: "\u1e7c", w: "\u0175", W: "\u0174", x: "\u1e8b", X: "\u1e8a",
  y: "\u00ff", Y: "\u0178", z: "\u017e", Z: "\u017d"
}

function pseudoLocalize(value) {
  var text = String(value === undefined || value === null ? "" : value)
  var protectedParts = []
  text = text.replace(/(%\d+|%[a-zA-Z]|\{[^{}]+\}|<[^<>]+>)/g, function(match) {
    protectedParts.push(match)
    return "\u0000" + (protectedParts.length - 1) + "\u0000"
  })
  var mapped = ""
  for (var i = 0; i < text.length; i++) mapped += PSEUDO_MAP[text.charAt(i)] || text.charAt(i)
  var expansion = mapped.replace(/([\u00e4\u00eb\u00ef\u00f6\u00fcAEIOUaeiou])/g, "$1\u00b7")
  expansion = expansion.replace(/\u0000(\d+)\u0000/g, function(_, index) {
    return protectedParts[Number(index)]
  })
  return "[!! " + expansion + " !!]"
}

function localize(value, profile) {
  var source = profile || {}
  if (source.pseudoLocale || source.locale === "pseudo") return pseudoLocalize(value)
  if (source.locale === "long") return String(value) + " \u2014 deliberately extended localization fixture"
  return String(value)
}

function parseHexColor(value) {
  var text = String(value || "").replace(/^#/, "")
  if (text.length === 8) text = text.substring(2)
  if (!text.match(/^[0-9a-fA-F]{6}$/)) return null
  return {
    r: parseInt(text.substring(0, 2), 16),
    g: parseInt(text.substring(2, 4), 16),
    b: parseInt(text.substring(4, 6), 16)
  }
}

function linearChannel(value) {
  var channel = clamp(value, 0, 255) / 255
  return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
}

function relativeLuminance(value) {
  var color = parseHexColor(value)
  if (!color) return NaN
  return 0.2126 * linearChannel(color.r) + 0.7152 * linearChannel(color.g) + 0.0722 * linearChannel(color.b)
}

function contrastRatio(foreground, background) {
  var first = relativeLuminance(foreground)
  var second = relativeLuminance(background)
  if (!isFinite(first) || !isFinite(second)) return 0
  var light = Math.max(first, second)
  var dark = Math.min(first, second)
  return (light + 0.05) / (dark + 0.05)
}

function logicalEdges(rtl, leading, trailing) {
  return rtl ? { left: trailing, right: leading } : { left: leading, right: trailing }
}

function estimateTextRows(text, pixelSize, width) {
  var available = Math.max(1, Number(width) || 1)
  var glyphWidth = Math.max(1, Number(pixelSize) || 1) * 0.62
  return Math.max(1, Math.ceil(String(text || "").length * glyphWidth / available))
}

function auditFixture(profile, width, title, message, actionCount) {
  var target = minimumTarget(profile)
  var padding = scaledMetric(12, profile, 6)
  var body = scaledFont(12, profile)
  var titleRows = estimateTextRows(localize(title, profile), scaledFont(14, profile), width - padding * 2)
  var messageRows = estimateTextRows(localize(message, profile), body, width - padding * 2)
  var actions = Math.max(0, Number(actionCount) || 0)
  var actionsWidth = actions * target + Math.max(0, actions - 1) * scaledMetric(8, profile, 4)
  return {
    minimumTarget: target,
    pointerTargetPass: target >= 24,
    touchTargetPass: normalizeDensity(profile && profile.densityMode) !== "touch" || target >= 44,
    titleRows: titleRows,
    messageRows: messageRows,
    actionsWrap: actionsWidth > Math.max(1, width - padding * 2),
    requiredHeight: padding * 2 + titleRows * scaledFont(14, profile) * 1.3
      + messageRows * body * 1.35 + (actions > 0 ? target + padding : 0)
  }
}
