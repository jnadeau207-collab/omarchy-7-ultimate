import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  property var hostWindow: null
  implicitWidth: 44
  implicitHeight: parent ? parent.height : 40
  Accessible.role: Accessible.Button
  Accessible.name: "Task View"
  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.showTooltip(root, "Task View")
      else if (!mouse.containsMouse) root.bar.hideTooltip(root)
    }
  }
  readonly property bool tooltipHovered: visible && (mouse.containsMouse || hover.hovered)

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
        border.width: bar && bar.highContrast ? 2 : 1
        border.color: Tokens.text.primary
        opacity: bar && bar.highContrast ? 1 : 0.7
      }
      Rectangle {
        x: 0
        y: 4
        width: 12
        height: 8
        radius: 1
        color: Tokens.surface.base
        border.width: bar && bar.highContrast ? 2 : 1
        border.color: Tokens.text.primary
        opacity: 1
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: {
      if (!root.bar) return
      if (containsMouse) root.bar.showTooltip(root, "Task View")
      else root.bar.hideTooltip(root)
    }
    onClicked: {
      if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function") {
        var screenName = root.hostWindow && root.hostWindow.screen
          ? String(root.hostWindow.screen.name || "") : ""
        root.bar.shell.summon("omarchy.ultimate-task-switcher", JSON.stringify({
          mode: "taskView",
          screen: screenName
        }))
      }
    }
  }
}
