import QtQuick
import qs.Commons

Item {
  id: root
  property var bar: null
  implicitWidth: 8
  implicitHeight: parent ? parent.height : 40
  Accessible.role: Accessible.Button
  Accessible.name: bar && bar.chromeText ? bar.chromeText("Show desktop") : "Show desktop"
  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.showTooltip(root, root.bar.chromeText("Show desktop"))
      else if (!mouse.containsMouse) root.bar.hideTooltip(root)
    }
  }
  readonly property bool tooltipHovered: visible && (mouse.containsMouse || hover.hovered)

  Rectangle {
    anchors.fill: parent
    color: mouse.containsMouse ? "#66d2eaf4" : "#22000000"
    border.width: 0
  }

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 1
    color: mouse.containsMouse ? "#d2eaf4" : "#80ffffff"
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: {
      if (!root.bar) return
      if (containsMouse) root.bar.showTooltip(root, root.bar.chromeText("Show desktop"))
      else root.bar.hideTooltip(root)
    }
    onClicked: {
      if (root.bar && root.bar.shell && root.bar.shell.windowService)
        root.bar.shell.windowService.toggleShowDesktop()
    }
  }
}
