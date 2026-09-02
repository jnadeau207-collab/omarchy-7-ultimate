import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

import "AdministrationModel.js" as AdministrationModel

Rectangle {
  id: root

  required property var record
  property var semanticProfile: null
  property bool selected: false
  property bool endTaskEnabled: false
  property bool endTaskBusy: false

  signal endTaskRequested(var record)

  Layout.fillWidth: true
  implicitHeight: content.implicitHeight + Style.space(28)
  radius: Tokens.radius.medium
  color: Tokens.surface.raised
  border.color: selected ? Tokens.accent.primary
    : Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
  border.width: selected || Tokens.accessibility.highContrast ? 2 : 1
  Accessible.role: Accessible.Pane
  Accessible.name: String(record.label || record.id || "") !== ""
    ? String(record.label || record.id)
    : Semantics.text(semanticProfile, "Provider resource")
  Accessible.description: String(record.kind || Semantics.text(semanticProfile, "Provider resource")) + ". " +
    Semantics.text(semanticProfile, "Status") + " " + String(record.status || "unknown") + "."

  ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(8)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          text: String(root.record.label || root.record.id || Semantics.text(root.semanticProfile, "Unnamed resource"))
          color: Tokens.text.primary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 3
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Text {
          textFormat: Text.PlainText
          text: String(root.record.subtitle || root.record.kind || Semantics.text(root.semanticProfile, "Provider resource"))
          color: Tokens.text.secondary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 3
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      Ui.Badge {
        text: String(root.record.status || "unknown").toUpperCase()
        tone: AdministrationModel.toneForRecord(root.record.status)
        Layout.alignment: Qt.AlignTop
      }
    }

    Text {
      textFormat: Text.PlainText
      text: String(root.record.kind || "provider-resource") + " \u00b7 " + String(root.record.id || "")
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 3
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    Rectangle {
      visible: root.record.details && root.record.details.length > 0
      Layout.fillWidth: true
      implicitHeight: detailsColumn.implicitHeight + Style.space(16)
      radius: Tokens.radius.small
      color: Tokens.surface.base
      border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
      border.width: Tokens.accessibility.highContrast ? 2 : 1
      Accessible.role: Accessible.StaticText
      Accessible.name: Semantics.text(root.semanticProfile, "Current") + " " +
        String(root.record.label || root.record.id || Semantics.text(root.semanticProfile, "resource")) + " " +
        Semantics.text(root.semanticProfile, "details")

      ColumnLayout {
        id: detailsColumn
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(5)

        Repeater {
          model: root.record.details || []

          delegate: RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              text: modelData.label
              color: Tokens.text.disabled
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.caption
              font.bold: true
              wrapMode: Text.WordWrap
              Layout.preferredWidth: root.width < 520 ? 104 : 144
              Layout.maximumWidth: root.width < 520 ? 104 : 144
              Layout.alignment: Qt.AlignTop
            }

            Text {
              textFormat: Text.PlainText
              text: modelData.value
              color: Tokens.text.secondary
              font.family: Tokens.typography.family
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

    RowLayout {
      visible: root.endTaskEnabled
      Layout.fillWidth: true
      spacing: Style.space(8)

      Item { Layout.fillWidth: true }

      Ui.Button {
        text: root.endTaskBusy ? "Ending task" : "End task"
        enabled: !root.endTaskBusy
        onClicked: root.endTaskRequested(root.record)
      }
    }
  }
}
