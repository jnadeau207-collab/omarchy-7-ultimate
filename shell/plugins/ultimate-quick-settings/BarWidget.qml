import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "omarchy.quick-settings"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property real openPanelIndicatorWidth: button.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property var hostedPluginIds: ["omarchy.network", "omarchy.bluetooth", "omarchy.audio", "omarchy.monitor", "omarchy.power"]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function hostedSource(pluginId) {
    var relative = Model.hostedSource(pluginId)
    return relative ? Qt.resolvedUrl(relative) : ""
  }

  function injectHosted(item, pluginId) {
    if (!item) return
    if ("chromeVisible" in item) item.chromeVisible = false
    if ("hostAnchor" in item) item.hostAnchor = button
    if ("bar" in item) item.bar = root.bar
    if ("settings" in item) item.settings = ({ id: pluginId })
    if (root.bar && typeof root.bar.registerSlot === "function")
      root.bar.registerSlot(pluginId, item)
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Repeater {
    model: root.hostedPluginIds
    delegate: Loader {
      required property string modelData
      active: true
      visible: false
      width: 0
      height: 0
      source: root.hostedSource(modelData)
      onLoaded: root.injectHosted(item, modelData)
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "omarchy.quick-settings"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true
    keepSpace: true
    fixedWidth: 36
    tooltipText: "Quick Settings"
    onPressed: function(b) { root.togglePanel() }

    Grid {
      anchors.centerIn: parent
      columns: 3
      rows: 3
      rowSpacing: 2
      columnSpacing: 2
      Repeater {
        model: 9
        Rectangle {
          width: 4
          height: 4
          radius: 1
          color: Tokens.text.primary
          opacity: Tokens.accessibility.highContrast ? 1 : 0.9
        }
      }
    }
  }
}
