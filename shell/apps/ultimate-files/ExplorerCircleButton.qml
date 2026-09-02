import QtQuick
import qs.Commons

import "ExplorerTheme.js" as Aero

Item {
  id: root

  property var productProfile: null
  property string direction: "back"
  property bool enabled: true

  signal triggered()

  implicitWidth: 24
  implicitHeight: 24

  Canvas {
    id: face
    anchors.fill: parent
    antialiasing: true

    readonly property bool hovered: hover.hovered && root.enabled
    readonly property bool pressed: press.pressed && root.enabled

    onHoveredChanged: requestPaint()
    onPressedChanged: requestPaint()

    Connections {
      target: root
      function onEnabledChanged() { face.requestPaint() }
      function onDirectionChanged() { face.requestPaint() }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)

      var cx = width / 2
      var cy = height / 2
      var r = Math.min(width, height) / 2 - 1.5

      var top = Aero.circleTop
      var bottom = Aero.circleBottom
      var edge = Aero.circleBorder
      var arrow = Aero.circleArrow

      if (!root.enabled) {
        top = Aero.circleDisabledTop
        bottom = Aero.circleDisabledBottom
        edge = Aero.circleDisabledBorder
        arrow = Aero.circleDisabledArrow
      } else if (pressed) {
        top = Aero.circlePressedTop
        bottom = Aero.circlePressedBottom
        edge = Aero.circleHoverBorder
      } else if (hovered) {
        top = Aero.circleHoverTop
        bottom = Aero.circleHoverBottom
        edge = Aero.circleHoverBorder
      }

      var fill = ctx.createLinearGradient(cx, cy - r, cx, cy + r)
      fill.addColorStop(0, top)
      fill.addColorStop(1, bottom)

      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.fillStyle = fill
      ctx.fill()
      ctx.strokeStyle = edge
      ctx.lineWidth = 1
      ctx.stroke()

      ctx.beginPath()
      ctx.arc(cx, cy, r - 1.5, Math.PI * 1.05, Math.PI * 1.95)
      ctx.strokeStyle = "#ffffff"
      ctx.lineWidth = 1
      ctx.stroke()

      var sign = root.direction === "back" ? 1 : -1
      var span = r * 0.44
      ctx.beginPath()
      ctx.moveTo(cx + sign * span * 0.55, cy - span)
      ctx.lineTo(cx - sign * span * 0.62, cy)
      ctx.lineTo(cx + sign * span * 0.55, cy + span)
      ctx.closePath()
      ctx.fillStyle = arrow
      ctx.fill()

      ctx.beginPath()
      ctx.moveTo(cx - sign * span * 0.62, cy)
      ctx.lineTo(cx + sign * span * 0.95, cy)
      ctx.strokeStyle = arrow
      ctx.lineWidth = Math.max(1.6, r * 0.22)
      ctx.lineCap = "butt"
      ctx.stroke()
    }
  }

  HoverHandler { id: hover; enabled: root.enabled }

  TapHandler {
    id: press
    enabled: root.enabled
    onSingleTapped: root.triggered()
  }

  Accessible.role: Accessible.Button
  Accessible.name: Semantics.text(root.productProfile, root.direction === "back" ? "Back" : "Forward")
  Accessible.onPressAction: if (root.enabled) root.triggered()
}
