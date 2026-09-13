import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  property var hostWindow: null
  readonly property bool startOpen: !!(bar && bar.shell && typeof bar.shell.isPluginOpen === "function"
    && bar.shell.isPluginOpen("omarchy.ultimate-start"))
  implicitWidth: 54
  implicitHeight: parent ? parent.height : 48
  Accessible.role: Accessible.Button
  Accessible.name: bar && bar.chromeText ? bar.chromeText("Start") : "Start"
  Accessible.description: bar && bar.chromeText ? bar.chromeText("Open the Start menu") : "Open the Start menu"
  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.showTooltip(root, root.bar.chromeText("Start"))
      else if (!mouse.containsMouse) root.bar.hideTooltip(root)
    }
  }
  readonly property bool tooltipHovered: visible && (mouse.containsMouse || hover.hovered)

  Rectangle {
    id: orb
    width: 48
    height: 48
    radius: 24
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    color: mouse.pressed ? "#0d2433"
      : root.startOpen ? "#1a4a66"
      : mouse.containsMouse ? "#173e58"
      : "#122a3c"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, mouse.containsMouse || root.startOpen ? 0.45 : 0.22)

    Rectangle {
      width: 18
      height: 10
      x: 12
      y: 8
      radius: 5
      color: Qt.rgba(1, 1, 1, 0.28)
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: {
      if (!root.bar) return
      if (containsMouse || hover.hovered) root.bar.showTooltip(root, root.bar.chromeText("Start"))
      else root.bar.hideTooltip(root)
    }
    onClicked: {
      if (!root.bar || !root.bar.shell) return
      var screenName = root.hostWindow && root.hostWindow.screen
        ? String(root.hostWindow.screen.name || "") : ""
      root.bar.shell.summon("omarchy.ultimate-start", JSON.stringify({ screen: screenName }))
    }
  }
}
