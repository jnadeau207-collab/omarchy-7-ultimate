import QtQuick
import qs.Commons

Rectangle {
  id: root

  property real value: 0
  property bool indeterminate: false
  property var semanticProfile: null
  property string accessibleName: "Progress"

  property string tone: "accent"

  readonly property color _tone: Semantics.toneColor(tone, semanticProfile)
  readonly property bool _animate: indeterminate && visible
    && Semantics.duration(semanticProfile, 1400) > 0

  implicitWidth: 200
  implicitHeight: Math.max(4, Style.space(5))
  radius: height / 2
  color: Util.alpha(semanticProfile ? semanticProfile.textPrimary : Tokens.text.primary, 0.12)
  clip: true

  Accessible.role: Accessible.ProgressBar
  Accessible.name: Semantics.text(semanticProfile, accessibleName)
  Accessible.description: Semantics.accessibleProgress(
    Semantics.text(semanticProfile, accessibleName), value, indeterminate)

  Rectangle {
    radius: parent.radius
    color: root._tone
    anchors.verticalCenter: parent.verticalCenter
    height: parent.height

    width: root.indeterminate ? parent.width * 0.3 : Math.max(height, parent.width * Util.clampAlpha(root.value))
    x: root.indeterminate
      ? (root._animate ? (parent.width + width) * sweep.phase - width : (parent.width - width) / 2)
      : 0

    Behavior on width { NumberAnimation { duration: Semantics.duration(root.semanticProfile, Tokens.motion.normal) } }

    SequentialAnimation {
      id: sweep
      property real phase: 0
      running: root._animate
      loops: Animation.Infinite
      NumberAnimation {
        target: sweep
        property: "phase"
        from: 0
        to: 1
        duration: Semantics.duration(root.semanticProfile, 1400)
      }
    }
  }
}
