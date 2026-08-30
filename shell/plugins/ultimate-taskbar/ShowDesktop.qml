import QtQuick
import qs.Commons

Item {
  id: root
  property var bar: null
  implicitWidth: 14
  implicitHeight: parent ? parent.height : 40
  Accessible.role: Accessible.Button
  Accessible.name: "Show desktop"

  Rectangle {
    anchors.fill: parent
    color: mouse.containsMouse ? bar.chromeGlow : Tokens.chrome.edge
    border.color: Tokens.border.subtle
    border.width: 1
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.bar && root.bar.shell && root.bar.shell.windowService)
        root.bar.shell.windowService.toggleShowDesktop()
    }
  }
}
