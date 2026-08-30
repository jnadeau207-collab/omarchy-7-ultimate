// Quick Settings tile catalog. Tiles either toggle a first-party service
// or summon an existing panel plugin. The panel plugins stay the owners of
// Wi-Fi, Bluetooth, audio, display, and power — this file only names them.

var HOSTED_PANEL_IDS = [
  "omarchy.network",
  "omarchy.bluetooth",
  "omarchy.audio",
  "omarchy.monitor",
  "omarchy.power"
]

function hostedPanelIds() {
  return HOSTED_PANEL_IDS.slice()
}

function hostedSource(pluginId) {
  var id = String(pluginId || "")
  if (id === "omarchy.network") return "../panels/network/Panel.qml"
  if (id === "omarchy.bluetooth") return "../panels/bluetooth/Panel.qml"
  if (id === "omarchy.audio") return "../panels/audio/Panel.qml"
  if (id === "omarchy.monitor") return "../panels/monitor/Panel.qml"
  if (id === "omarchy.power") return "../panels/power/Panel.qml"
  return ""
}

function tiles() {
  return [
    { id: "wifi", label: "Wi-Fi", panelId: "omarchy.network", kind: "panel-toggle" },
    { id: "bluetooth", label: "Bluetooth", panelId: "omarchy.bluetooth", kind: "panel-toggle" },
    { id: "audio", label: "Sound", panelId: "omarchy.audio", kind: "panel" },
    { id: "display", label: "Display", panelId: "omarchy.monitor", kind: "panel" },
    { id: "nightlight", label: "Night light", panelId: "", kind: "nightlight" },
    { id: "dnd", label: "Do not disturb", panelId: "", kind: "dnd" },
    { id: "power", label: "Power", panelId: "omarchy.power", kind: "panel" },
    { id: "settings", label: "Settings", panelId: "", kind: "launch", desktopId: "org.omarchy.Settings" },
    { id: "agents", label: "Agent Center", panelId: "", kind: "launch", desktopId: "org.omarchy.AgentCenter" }
  ]
}

if (typeof module !== "undefined") {
  module.exports = {
    hostedPanelIds: hostedPanelIds,
    hostedSource: hostedSource,
    tiles: tiles
  }
}
