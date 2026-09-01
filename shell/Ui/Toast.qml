import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Card {
  id: root

  property string title: ""
  property string message: ""

  property string tone: "accent"

  property var actions: []

  signal actionClicked(int index)
  signal dismissed()

  readonly property color _tone: Semantics.toneColor(tone, semanticProfile)

  elevation: "raised"
  implicitWidth: 360
  implicitHeight: column.implicitHeight + Semantics.metric(semanticProfile, Style.spacing.controlPaddingY) * 2
  Accessible.role: Accessible.AlertMessage
  Accessible.name: Semantics.text(semanticProfile, title !== "" ? title : "Notification")
  Accessible.description: Semantics.text(semanticProfile, message)

  Rectangle {
    width: Semantics.metric(root.semanticProfile, Style.space(3), 3)
    height: parent.height
    radius: root.radius
    color: root._tone
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.leftMargin: Semantics.metric(root.semanticProfile, Style.space(12))
    anchors.right: parent.right
    anchors.rightMargin: Semantics.metric(root.semanticProfile, Style.spacing.controlPaddingX)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Semantics.metric(root.semanticProfile, Style.space(6))

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.title)
      color: root.semanticProfile ? root.semanticProfile.textPrimary : Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Semantics.font(root.semanticProfile, Style.font.body)
      font.bold: true
      width: parent.width
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      visible: root.message !== ""
      text: Semantics.text(root.semanticProfile, root.message)
      color: root.semanticProfile ? root.semanticProfile.textSecondary : Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Semantics.font(root.semanticProfile, Style.font.bodySmall)
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Semantics.metric(root.semanticProfile, Style.space(8))

      Repeater {
        model: root.actions

        delegate: Button {
          required property var modelData
          required property int index
          text: typeof modelData === "string" ? modelData : String(modelData.label || "")
          semanticProfile: root.semanticProfile
          focusable: true
          onClicked: {
            root.actionClicked(index)
            root.dismissed()
          }
        }
      }
    }
  }
}
