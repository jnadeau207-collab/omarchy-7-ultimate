function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// The widest glyph `iconFor` can return. The progress OSD sizes its icon
// column to it so the bar keeps its place as the icon changes.
var widestIcon = "\u266B"

function iconFor(name, percent) {
  var n = String(name || "").toLowerCase()
  if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return "\u2205"
  if (n === "volume-low") return "\u266A"
  if (n === "volume-medium") return "\u266B"
  if (n === "volume-high" || n === "volume") return "\u266B"
  if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return "\u2715"
  if (n === "microphone" || n === "mic") return "\u25CF"
  if (n === "keyboard") return "\u2328"
  if (n === "brightness" || n === "display") return "\u2600"
  if (n === "touchpad") return "\u25A1"
  if (n === "touch" || n === "touchscreen") return "\u25A3"
  if (n === "reboot" || n === "restart") return "\u21BB"
  if (n === "shutdown" || n === "power" || n === "poweroff") return "\u23FB"
  if (n === "logout" || n === "sign-out" || n === "leave") return "\u2190"
  if (n === "media" || n === "player") return "\u266A"
  if (n === "media-source" || n === "player-source") return "\u266A"
  if (n === "media-play" || n === "player-play") return "\u25B6"
  if (n === "media-pause" || n === "player-pause") return "\u23F8"
  if (n === "media-next" || n === "player-next") return "\u23ED"
  if (n === "media-previous" || n === "player-previous") return "\u23EE"
  if (n.length > 0) return name
  if (percent <= 0) return "\u2205"
  if (percent <= 33) return "\u266A"
  if (percent <= 66) return "\u266B"
  return "\u266B"
}

function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
  var maxValue = Math.max(1, parseInt(rawMax || "100", 10))
  var parsedValue = parseInt(rawValue || "0", 10)
  var hasProgress = rawValue !== "" && !isNaN(parsedValue) && rawMessage === ""
  var value = hasProgress ? clamp(parsedValue, 0, maxValue) : 0
  var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
  var parsedDuration = parseInt(rawDuration || "1200", 10)

  return {
    iconKey: String(iconName || "").toLowerCase(),
    maxValue: maxValue,
    hasProgress: hasProgress,
    value: value,
    message: String(rawMessage || (hasProgress ? (rawProgressText || percent + "%") : "")),
    icon: iconFor(iconName, percent),
    duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    widestIcon: widestIcon,
    iconFor: iconFor,
    stateForShow: stateForShow
  }
}
