import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "components"

Panel {
  id: root
  moduleName: "omarchy.notifications"
  ipcTarget: "omarchy.notifications"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var notificationService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property var rows: notificationService && Array.isArray(notificationService.centerRows) ? notificationService.centerRows : []
  readonly property bool dndOn: notificationService ? notificationService.doNotDisturb === true : false
  readonly property color contentForeground: bar ? bar.foreground : Tokens.text.primary
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var productProfile: bar && bar.productProfile ? bar.productProfile : null

  function open() {
    if (root.notificationService && typeof root.notificationService.refreshCenterHistory === "function")
      root.notificationService.refreshCenterHistory()
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

  function toggleDnd() {
    if (!root.notificationService) return
    root.notificationService.setDoNotDisturb(!root.notificationService.doNotDisturb)
  }

  function clearHistory() {
    if (!root.notificationService) return
    root.notificationService.clearHistory()
    root.notificationService.refreshCenterHistory()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: Semantics.text(root.productProfile, "Notification Center")
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Button {
            semanticProfile: root.productProfile
            text: root.dndOn ? "Focus on" : "Focus off"
            bordered: true
            onClicked: root.toggleDnd()
          }

          Button {
            semanticProfile: root.productProfile
            text: "Clear"
            bordered: true
            enabled: root.rows.length > 0
            onClicked: root.clearHistory()
          }
        }

        Text {
          visible: root.rows.length === 0
          width: parent.width
          text: Semantics.text(root.productProfile, "No recent notifications")
          color: Tokens.text.secondary
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.rows
          delegate: NotificationCard {
            required property var modelData
            width: column.width
            app: modelData.app || ""
            appIcon: modelData.appIcon || ""
            summary: modelData.summary || ""
            body: modelData.body || ""
            image: modelData.image || ""
            glyph: modelData.glyph || ""
            urgency: typeof modelData.urgency === "number" ? modelData.urgency : 1
            timestamp: modelData.timestamp || 0
            fontFamily: root.contentFontFamily
            onCloseRequested: {
              if (root.notificationService && typeof root.notificationService.dismissHistoryEntry === "function")
                root.notificationService.dismissHistoryEntry(modelData)
            }
          }
        }
      }
    }
  }
}
