import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  implicitWidth: 44
  implicitHeight: parent ? parent.height : 40
  Accessible.role: Accessible.Button
  Accessible.name: "Task View"

  Rectangle {
    anchors.fill: parent
    anchors.margins: 4
    radius: Tokens.radius.small
    color: mouse.pressed ? bar.chromePressed
      : mouse.containsMouse ? bar.chromeHover
      : "transparent"

    Item {
      anchors.centerIn: parent
      width: 16
      height: 12
      Rectangle {
        x: 4
        y: 0
        width: 12
        height: 8
        radius: 1
        color: "transparent"
        border.width: 1
        border.color: Tokens.text.primary
        opacity: 0.7
      }
      Rectangle {
        x: 0
        y: 4
        width: 12
        height: 8
        radius: 1
        color: Tokens.surface.base
        border.width: 1
        border.color: Tokens.text.primary
        opacity: 0.95
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
        root.bar.shell.summon("omarchy.ultimate-task-switcher", JSON.stringify({ mode: "taskView" }))
    }
  }
}
