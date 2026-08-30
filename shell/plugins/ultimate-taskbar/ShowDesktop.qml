import QtQuick
import qs.Commons

Item {
  id: root
  property var bar: null
  implicitWidth: 14
  implicitHeight: parent ? parent.height : 40
  Accessible.role: Accessible.Button
  Accessible.name: "Show desktop"
  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.showTooltip(root, "Show desktop")
      else if (!mouse.containsMouse) root.bar.hideTooltip(root)
    }
  }
  readonly property bool tooltipHovered: visible && (mouse.containsMouse || hover.hovered)

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
    onContainsMouseChanged: {
      if (!root.bar) return
      if (containsMouse) root.bar.showTooltip(root, "Show desktop")
      else root.bar.hideTooltip(root)
    }
    onClicked: {
      if (root.bar && root.bar.shell && root.bar.shell.windowService)
        root.bar.shell.windowService.toggleShowDesktop()
    }
  }
}
