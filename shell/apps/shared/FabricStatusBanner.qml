import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

Rectangle {
  id: root

  required property var host
  property var semanticProfile: null

  readonly property bool connected: host && host.fabricReady
  readonly property bool incompatible: host && host.fabricConnectionState === "incompatible"

  implicitHeight: content.implicitHeight + Style.space(16)
  radius: Tokens.radius.medium
  color: connected ? Qt.rgba(Tokens.state.success.r, Tokens.state.success.g, Tokens.state.success.b, 0.10)
    : incompatible ? Qt.rgba(Tokens.state.danger.r, Tokens.state.danger.g, Tokens.state.danger.b, 0.12)
    : Qt.rgba(Tokens.state.warning.r, Tokens.state.warning.g, Tokens.state.warning.b, 0.10)
  border.color: connected ? Tokens.state.success : (incompatible ? Tokens.state.danger : Tokens.state.warning)
  border.width: 1
  Accessible.role: incompatible ? Accessible.AlertMessage : Accessible.Pane
  Accessible.name: statusTitle.text
  Accessible.description: statusDetail.text

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    Rectangle {
      width: Style.space(8)
      height: width
      radius: width / 2
      color: root.connected ? Tokens.state.success : (root.incompatible ? Tokens.state.danger : Tokens.state.warning)
      Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        id: statusTitle
        text: Semantics.text(root.semanticProfile, root.connected ? "Fabric connected" : (root.incompatible ? "Fabric update required" : "Fabric unavailable"))
        color: Tokens.text.primary
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        Layout.fillWidth: true
      }

      Text {
        textFormat: Text.PlainText
        id: statusDetail
        text: root.connected
          ? "Client " + root.host.fabricIdentity + " has its own endpoint session."
          : (root.incompatible
            ? "This app and the Fabric daemon do not share a compatible protocol."
            : "Provider-backed state stays unavailable until the owner-scoped Fabric connection is ready.")
        color: Tokens.text.secondary
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    Ui.Button {
      visible: !root.connected
      text: "Try again"
      semanticProfile: root.semanticProfile
      focusable: true
      onClicked: root.host.retryFabric()
      Layout.alignment: Qt.AlignVCenter
    }
  }
}
