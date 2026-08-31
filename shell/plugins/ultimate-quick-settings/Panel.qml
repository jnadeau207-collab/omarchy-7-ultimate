import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.quick-settings"
  ipcTarget: "omarchy.quick-settings"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var tiles: Model.tiles()
  readonly property var nightlightService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.nightlight") : null
  readonly property var notificationService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property var appLibrary: bar && bar.shell ? bar.shell.appLibrary : null
  readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
  readonly property bool wifiOn: Networking.wifiEnabled === true
  readonly property bool bluetoothOn: bluetoothAdapter ? bluetoothAdapter.enabled === true : false
  readonly property bool nightlightOn: nightlightService ? nightlightService.enabled === true : false
  readonly property bool dndOn: notificationService ? notificationService.doNotDisturb === true : false
  readonly property color contentForeground: bar ? bar.foreground : Tokens.text.primary
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var productProfile: bar && bar.productProfile ? bar.productProfile : null

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function tileActive(tile) {
    if (!tile) return false
    if (tile.id === "wifi") return root.wifiOn
    if (tile.id === "bluetooth") return root.bluetoothOn
    if (tile.id === "nightlight") return root.nightlightOn
    if (tile.id === "dnd") return root.dndOn
    return false
  }

  function tileStatus(tile) {
    if (!tile) return ""
    if (tile.kind === "panel-toggle" || tile.kind === "nightlight" || tile.kind === "dnd")
      return tileActive(tile) ? "On" : "Off"
    if (tile.kind === "launch") return "Open"
    return "More"
  }

  function summonPanel(pluginId) {
    if (!pluginId) return
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function")
      root.bar.shell.toggle(pluginId)
  }

  function toggleTile(tile) {
    if (!tile) return
    if (tile.id === "wifi") {
      Networking.wifiEnabled = !Networking.wifiEnabled
      return
    }
    if (tile.id === "bluetooth") {
      if (root.bluetoothAdapter) root.bluetoothAdapter.enabled = !root.bluetoothAdapter.enabled
      return
    }
    if (tile.id === "nightlight") {
      if (root.nightlightService) root.nightlightService.toggle()
      return
    }
    if (tile.id === "dnd") {
      if (root.notificationService)
        root.notificationService.setDoNotDisturb(!root.notificationService.doNotDisturb)
      return
    }
    if (tile.kind === "launch") {
      if (root.appLibrary) root.appLibrary.launch(tile.desktopId, tile.label)
      root.close()
      return
    }
    summonPanel(tile.panelId)
  }

  function activateTile(tile) {
    if (!tile) return
    if (tile.panelId) {
      summonPanel(tile.panelId)
      return
    }
    toggleTile(tile)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: Semantics.text(root.productProfile, "Quick Settings")
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        GridLayout {
          width: parent.width
          columns: 3
          rowSpacing: Style.space(8)
          columnSpacing: Style.space(8)

          Repeater {
            model: root.tiles
            delegate: Item {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(88)

              Rectangle {
                anchors.fill: parent
                radius: Tokens.radius.medium
                color: tileMouse.containsMouse ? Tokens.chrome.hover : Tokens.chrome.menu
                border.color: Tokens.border.subtle
                border.width: 1

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: Semantics.text(root.productProfile, modelData.label)
                    color: Tokens.text.primary
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: Semantics.text(root.productProfile, root.tileStatus(modelData))
                    color: root.tileActive(modelData) ? Tokens.accent.primary : Tokens.text.secondary
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  id: tileMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(event) {
                    if (event.button === Qt.RightButton) root.toggleTile(modelData)
                    else root.activateTile(modelData)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
