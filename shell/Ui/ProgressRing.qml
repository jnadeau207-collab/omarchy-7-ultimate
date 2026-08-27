import QtQuick
import qs.Commons

// Circular progress indicator for compact surfaces: taskbar buttons, panel
// headers, list rows. Same contract as ProgressBar — determinate `value`
// 0..1 or `indeterminate` spin, semantic `tone`.
Item {
  id: root

  property real value: 0
  property bool indeterminate: false
  property string tone: "accent"
  property var semanticProfile: null
  property string accessibleName: "Progress"

  readonly property color _tone: Semantics.toneColor(tone, semanticProfile)
  readonly property bool _animate: indeterminate && visible
    && Semantics.duration(semanticProfile, 1100) > 0

  implicitWidth: 24
  implicitHeight: 24

  Accessible.role: Accessible.ProgressBar
  Accessible.name: Semantics.text(semanticProfile, accessibleName)
  Accessible.description: Semantics.accessibleProgress(
    Semantics.text(semanticProfile, accessibleName), value, indeterminate)

  // Track + value arc drawn as a conic-ish approximation: a full ring at
  // low alpha with an arc segment on top. Canvas is the honest tool here.
  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2
      var cy = height / 2
      var lw = Math.max(3, Math.min(width, height) * 0.14)
      var r = (Math.min(width, height) - lw) / 2
      var start = -Math.PI / 2

      ctx.lineWidth = lw
      ctx.lineCap = "round"

      var trackColor = root.semanticProfile ? root.semanticProfile.textPrimary : Tokens.text.primary
      ctx.strokeStyle = Qt.rgba(trackColor.r, trackColor.g, trackColor.b, 0.15)
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.stroke()

      ctx.strokeStyle = root._tone
      ctx.beginPath()
      if (root.indeterminate) {
        var head = (root._animate ? spin.phase : 0.25) * Math.PI * 2
        ctx.arc(cx, cy, r, start + head, start + head + Math.PI * 0.75)
      } else {
        var frac = Math.max(0.001, Math.min(1, root.value))
        if (frac >= 0.999) ctx.arc(cx, cy, r, 0, Math.PI * 2)
        else ctx.arc(cx, cy, r, start, start + Math.PI * 2 * frac)
      }
      ctx.stroke()
    }

    Connections {
      target: root
      function onValueChanged() { canvas.requestPaint() }
      function onIndeterminateChanged() { canvas.requestPaint() }
      function onToneChanged() { canvas.requestPaint() }
      function onSemanticProfileChanged() { canvas.requestPaint() }
    }

    RotationAnimation on rotation {
      running: root._animate
      from: 0
      to: 360
      duration: Semantics.duration(root.semanticProfile, 1100)
      loops: Animation.Infinite
    }

    // Repaint the indeterminate arc position as the sweep advances.
    SequentialAnimation {
      id: spin
      property real phase: 0.25
      running: root._animate
      loops: Animation.Infinite
      onPhaseChanged: canvas.requestPaint()
      NumberAnimation {
        target: spin
        property: "phase"
        from: 0
        to: 1
        duration: Semantics.duration(root.semanticProfile, 1100)
      }
    }
  }
}
