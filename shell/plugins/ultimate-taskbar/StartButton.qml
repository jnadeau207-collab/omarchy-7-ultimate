import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  property var hostWindow: null
  readonly property bool startOpen: !!(bar && bar.shell && typeof bar.shell.isPluginOpen === "function"
    && bar.shell.isPluginOpen("omarchy.ultimate-start"))
  implicitWidth: 56
  implicitHeight: parent ? parent.height : 40
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
    anchors.centerIn: parent
    width: 40
    height: 40
    radius: 20
    color: mouse.pressed ? "#081820"
      : root.startOpen ? "#16324c"
      : mouse.containsMouse ? "#122a40"
      : "#0c2236"
    border.color: Qt.rgba(1, 1, 1, mouse.containsMouse || root.startOpen ? 0.55 : 0.35)
    border.width: 1

    Rectangle {
      width: 16
      height: 8
      x: 10
      y: 6
      radius: 4
      color: Qt.rgba(1, 1, 1, 0.22)
    }

    Grid {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 2
      columns: 2
      rows: 2
      rowSpacing: 3
      columnSpacing: 3
      Repeater {
        model: [Tokens.caption.close.background, Tokens.caption.maximize.background, Tokens.state.info, Tokens.state.success]
        Rectangle {
          width: 11
          height: 11
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
