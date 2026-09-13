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
    color: mouse.pressed ? "#0a2438"
      : root.startOpen ? "#1a5a8c"
      : mouse.containsMouse ? "#1c4e78"
      : "#12344f"
    border.width: 1
    border.color: mouse.containsMouse || root.startOpen ? "#c8e6f4" : "#80a8c0"

    Rectangle {
      width: 22
      height: 12
      x: 10
      y: 7
      radius: 6
      color: "#99ffffff"
    }

    Rectangle {
      width: 10
      height: 6
      x: 14
      y: 9
      radius: 3
      color: "#ccffffff"
    }

    Grid {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 4
      columns: 2
      rows: 2
      rowSpacing: 2
      columnSpacing: 2
      Repeater {
        model: ["#f35325", "#81bc06", "#05a6f0", "#ffba08"]
        Rectangle {
          width: 8
          height: 8
          radius: 1
          color: modelData
        }
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
