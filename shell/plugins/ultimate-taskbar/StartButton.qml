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
  Accessible.name: "Start"
  Accessible.description: "Open the Start menu"
  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!root.bar) return
      if (hovered) root.bar.showTooltip(root, "Start")
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
    color: mouse.pressed ? bar.chromePressed
      : root.startOpen ? bar.chromeStart
      : mouse.containsMouse ? bar.chromeHover
      : Tokens.chrome.glass
    border.color: root.startOpen ? bar.chromeGlow : Tokens.chrome.edge
    border.width: root.startOpen ? 2 : 1

    Rectangle {
      anchors.fill: parent
      anchors.margins: 2
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(Tokens.chrome.glow.r, Tokens.chrome.glow.g, Tokens.chrome.glow.b, root.startOpen ? 0.55 : 0.18)
    }

    Grid {
      anchors.centerIn: parent
      columns: 2
      rows: 2
      rowSpacing: 2
      columnSpacing: 2
      Repeater {
        model: [Tokens.caption.close.background, Tokens.caption.maximize.background, Tokens.state.info, Tokens.state.success]
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
      if (containsMouse || hover.hovered) root.bar.showTooltip(root, "Start")
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
