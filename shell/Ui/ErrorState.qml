import QtQuick
import qs.Commons

Column {
  id: root

  property string title: ""
  property string explanation: ""

  property string detail: ""

  property bool hasCursor: false
  property var semanticProfile: null

  signal retryClicked()
  signal detailsToggled(bool visible)

  property bool _detailsOpen: false

  spacing: Semantics.metric(semanticProfile, Style.space(8))
  Accessible.role: Accessible.AlertMessage
  Accessible.name: Semantics.text(semanticProfile, title !== "" ? title : "Operation failed")
  Accessible.description: Semantics.text(semanticProfile, explanation)

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: "\u26a0"
    color: Semantics.toneColor("danger", root.semanticProfile)
    font.family: Tokens.typography.family
    font.pixelSize: Semantics.font(root.semanticProfile, Style.font.display)
  }

  Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.title !== ""
    text: Semantics.text(root.semanticProfile, root.title)
    color: root.semanticProfile ? root.semanticProfile.textPrimary : Tokens.text.primary
    font.family: Tokens.typography.family
    font.pixelSize: Semantics.font(root.semanticProfile, Style.font.body)
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.explanation !== ""
    text: Semantics.text(root.semanticProfile, root.explanation)
    color: root.semanticProfile ? root.semanticProfile.textSecondary : Tokens.text.secondary
    font.family: Tokens.typography.family
    font.pixelSize: Semantics.font(root.semanticProfile, Style.font.bodySmall)
    horizontalAlignment: Text.AlignHCenter
    width: Math.min(root.width || 0, 420)
    wrapMode: Text.WordWrap
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Semantics.metric(root.semanticProfile, Style.space(8))

    Button {
      text: "Try again"
      semanticProfile: root.semanticProfile
      focusable: true
      onClicked: root.retryClicked()
    }

    Button {
      visible: root.detail !== ""
      text: root._detailsOpen ? "Hide details" : "Details"
      semanticProfile: root.semanticProfile
      focusable: true
      onClicked: {
        root._detailsOpen = !root._detailsOpen
        root.detailsToggled(root._detailsOpen)
      }
    }
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root._detailsOpen && root.detail !== ""
    width: Math.min(root.width || 480, 480)
    height: detailText.implicitHeight + Style.space(12)
    radius: Math.max(4, Math.round(Style.cornerRadius * 0.5))
    color: root.semanticProfile ? root.semanticProfile.surfaceRaised : Tokens.surface.raised

    Text {
      textFormat: Text.PlainText
      id: detailText
      anchors.fill: parent
      anchors.margins: Style.space(6)
      text: Semantics.text(root.semanticProfile, root.detail)
      color: root.semanticProfile ? root.semanticProfile.textSecondary : Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Semantics.font(root.semanticProfile, Style.font.bodySmall)
      wrapMode: Text.WrapAnywhere
    }
  }
}
