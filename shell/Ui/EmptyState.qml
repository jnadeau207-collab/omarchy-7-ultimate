import QtQuick
import qs.Commons

// EmptyState: the "nothing here yet" surface for lists, search results, and
// panels. A labeled empty state is a visible affordance (Rule 4) — it tells
// the user the surface exists and what belongs in it.
Column {
  id: root

  property string iconText: "\u25cb"
  property string title: ""
  property string message: ""
  property var semanticProfile: null

  spacing: Semantics.metric(semanticProfile, Style.space(8))
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(semanticProfile, title !== "" ? title : "Empty state")
  Accessible.description: Semantics.text(semanticProfile, message)

  Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.iconText
    color: root.semanticProfile ? root.semanticProfile.textDisabled : Tokens.text.disabled
    font.family: Style.font.family
    font.pixelSize: Semantics.font(root.semanticProfile, Style.font.display)
  }

  Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.title !== ""
    text: Semantics.text(root.semanticProfile, root.title)
    color: root.semanticProfile ? root.semanticProfile.textSecondary : Tokens.text.secondary
    font.family: Style.font.family
    font.pixelSize: Semantics.font(root.semanticProfile, Style.font.body)
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.message !== ""
    text: Semantics.text(root.semanticProfile, root.message)
    color: root.semanticProfile ? root.semanticProfile.textDisabled : Tokens.text.disabled
    font.family: Style.font.family
    font.pixelSize: Semantics.font(root.semanticProfile, Style.font.bodySmall)
    horizontalAlignment: Text.AlignHCenter
    width: Math.min(root.width || 0, 420)
    wrapMode: Text.WordWrap
  }
}
