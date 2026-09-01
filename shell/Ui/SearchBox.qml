import QtQuick
import qs.Commons

TextField {
  id: root

  property bool showClearButton: true

  signal cleared()

  font.pixelSize: Style.font.body
  leftPadding: Style.space(28)
  rightPadding: showClearButton && text.length > 0 ? Style.space(28) : horizontalPadding

  Text {
    visible: root.text.length === 0
    text: "\u2315"
    color: Tokens.text.secondary
    font.family: Tokens.typography.family
    font.pixelSize: root.font.pixelSize
    anchors.left: parent.left
    anchors.leftMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
  }

  IconButton {
    visible: root.showClearButton && root.text.length > 0
    iconText: "\u00d7"
    size: 20
    glyphSize: Style.font.body
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    onClicked: {
      root.text = ""
      root.cleared()
      root.forceActiveFocus()
    }
  }

  Keys.onEscapePressed: {
    if (text.length > 0) {
      text = ""
      root.cleared()
    } else {
      focus = false
    }
  }
}
