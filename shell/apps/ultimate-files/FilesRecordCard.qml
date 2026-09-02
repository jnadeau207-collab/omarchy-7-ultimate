import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

Rectangle {
  id: root
  required property var record
  property bool selected: false
  property bool trashable: false
  property bool restorable: false
  property bool trashBusy: false

  signal trashRequested()
  signal restoreRequested()

  Layout.fillWidth: true
  implicitHeight: content.implicitHeight + Style.space(28)
  radius: Tokens.radius.medium
  color: Tokens.surface.raised
  border.color: selected ? Tokens.accent.primary : Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
  border.width: selected || Tokens.accessibility.highContrast ? 2 : 1
  Accessible.role: Accessible.Pane
  Accessible.name: String(record.title || record.id || "File record")
  Accessible.description: String(record.subtitle || "") + ". Status " + String(record.status || "unknown") + "."

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
          text: String(root.record.title || root.record.id || "Unnamed file record")
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
          text: String(root.record.subtitle || root.record.kind || "File metadata")
          color: Tokens.text.secondary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 4
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      Ui.Badge {
        text: String(root.record.status || "unknown").toUpperCase()
        tone: String(root.record.tone || "neutral")
        Layout.alignment: Qt.AlignTop
      }

      Ui.Button {
        visible: root.restorable
        text: "Restore"
        focusable: true
        bordered: true
        enabled: !root.trashBusy
        accessibleDescription: "Return " + String(root.record.title || "this entry") + " to where it came from through files.provider trash.restore"
        Layout.alignment: Qt.AlignTop
        onClicked: root.restoreRequested()
      }
      Ui.Button {
        visible: root.trashable
        text: "Move to Trash"
        focusable: true
        bordered: true
        enabled: !root.trashBusy
        accessibleDescription: "Move " + String(root.record.title || "this entry") + " to Trash through files.provider entry.trash"
        Layout.alignment: Qt.AlignTop
        onClicked: root.trashRequested()
      }
    }

    Text {
      textFormat: Text.PlainText
      text: String(root.record.kind || "record") + " \u00b7 " + String(root.record.id || "")
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
      implicitHeight: details.implicitHeight + Style.space(16)
      radius: Tokens.radius.small
      color: Tokens.surface.base
      border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
      border.width: Tokens.accessibility.highContrast ? 2 : 1
      Accessible.role: Accessible.StaticText
      Accessible.name: "Trusted metadata for " + String(root.record.title || root.record.id || "record")

      ColumnLayout {
        id: details
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
              maximumLineCount: 6
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }
      }
    }
  }
}
