import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

import "AgentCenterModel.js" as AgentCenterModel

Rectangle {
  id: root

  required property string view
  required property var record
  property string selectedEntityType: ""
  property string selectedEntityId: ""

  readonly property var presentation: AgentCenterModel.presentation(view, record)
  readonly property bool selected: AgentCenterModel.selectedIdentity(
    view,
    record,
    selectedEntityType,
    selectedEntityId
  )

  Layout.fillWidth: true
  implicitHeight: content.implicitHeight + Style.space(28)
  radius: Tokens.radius.medium
  color: Tokens.surface.raised
  border.color: selected ? Tokens.accent.primary : Tokens.border.subtle
  border.width: selected ? 2 : 1
  Accessible.role: Accessible.Pane
  Accessible.name: presentation.title
  Accessible.description: presentation.subtitle + ". Status " + presentation.status + "."

  ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(7)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          text: root.presentation.title
          color: Tokens.text.primary
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 3
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Text {
          visible: root.presentation.subtitle !== ""
          text: root.presentation.subtitle
          color: Tokens.text.disabled
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 3
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      Ui.Badge {
        text: String(root.presentation.status || "unknown").toUpperCase()
        tone: root.presentation.tone
        Layout.alignment: Qt.AlignTop
      }
    }

    Text {
      visible: root.presentation.body !== ""
      text: root.presentation.body
      color: Tokens.text.secondary
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 6
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    Rectangle {
      visible: root.presentation.details.length > 0
      Layout.fillWidth: true
      implicitHeight: detailColumn.implicitHeight + Style.space(16)
      radius: Tokens.radius.small
      color: Tokens.surface.base
      border.color: Tokens.border.subtle
      border.width: 1

      ColumnLayout {
        id: detailColumn
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(5)

        Repeater {
          model: root.presentation.details

          delegate: RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: Style.space(10)

            Text {
              text: modelData.label
              color: Tokens.text.disabled
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              wrapMode: Text.WordWrap
              Layout.preferredWidth: 128
              Layout.maximumWidth: 128
              Layout.alignment: Qt.AlignTop
            }

            Text {
              text: modelData.value
              color: Tokens.text.secondary
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
              maximumLineCount: 5
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }
      }
    }

    Rectangle {
      visible: root.presentation.recoveryActions.length > 0
      Layout.fillWidth: true
      implicitHeight: recoveryColumn.implicitHeight + Style.space(16)
      radius: Tokens.radius.small
      color: Qt.rgba(Tokens.state.warning.r, Tokens.state.warning.g, Tokens.state.warning.b, 0.10)
      border.color: Tokens.state.warning
      border.width: 1
      Accessible.role: Accessible.Pane
      Accessible.name: "Recovery status"

      ColumnLayout {
        id: recoveryColumn
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(4)

        Text {
          text: "RECOVERY STATUS"
          color: Tokens.state.warning
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          Layout.fillWidth: true
        }

        Repeater {
          model: root.presentation.recoveryActions

          delegate: Text {
            required property var modelData

            text: "\u2022 " + AgentCenterModel.clippedText(modelData, 320)
            color: Tokens.text.secondary
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 4
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }
      }
    }
  }
}
