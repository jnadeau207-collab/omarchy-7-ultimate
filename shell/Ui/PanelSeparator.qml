import QtQuick
import qs.Commons

Rectangle {
  id: root

  property color foreground: Tokens.text.primary
  property real strength: 0.12

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: 1
  height: 1
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, strength)
}
