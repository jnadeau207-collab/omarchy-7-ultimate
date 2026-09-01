import QtQuick
import qs.Commons

// Labeled radio button for exclusive-choice groups. Give every radio in a
// group the same `group` string; only one per group paints its dot. Like
// Checkbox, the whole row is the hitbox and the caller owns the value.
Item {
  id: root

  property bool checked: false
  property string label: ""
  property real labelMaximumWidth: 0
  property string group: ""
  property var semanticProfile: null
  property string accessibleDescription: ""
  property bool hasCursor: false
  property bool focusable: false

  property color foreground: semanticProfile ? semanticProfile.textPrimary : Tokens.text.primary
  property color accent: semanticProfile ? semanticProfile.accent : Tokens.accent.primary

  signal toggled()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.toggled()
  Keys.onSpacePressed: if (focusable) root.toggled()

  readonly property bool hot: mouse.containsMouse || hasCursor
  readonly property int circleSize: Math.max(16, Math.round(Semantics.font(semanticProfile, Style.font.body) * 1.25))
  readonly property int dotSize: Math.max(6, Math.round(circleSize * 0.45))

  implicitWidth: circle.implicitWidth
  implicitHeight: Math.max(circle.implicitHeight, Semantics.minimumTarget(semanticProfile))

  Accessible.role: Accessible.RadioButton
  Accessible.name: Semantics.text(semanticProfile, label)
  Accessible.description: accessibleDescription !== "" ? accessibleDescription
    : Semantics.text(semanticProfile, checked ? "Selected" : "Not selected")
  Accessible.onPressAction: {
    if (root.enabled) root.toggled()
  }

  Row {
    id: circle
    anchors.verticalCenter: parent.verticalCenter
    spacing: Semantics.metric(root.semanticProfile, Style.space(8))

    BorderSurface {
      width: root.circleSize
      height: root.circleSize
      radius: width / 2
      color: mouse.pressed && !root.checked ? Util.alpha(root.accent, 0.18)
        : root.hot && !root.checked ? Util.alpha(root.foreground, 0.08)
        : "transparent"
      borderSpec: root.semanticProfile && root.semanticProfile.highContrast && root.focusable && root.activeFocus
        ? Border.flat(root.semanticProfile.focusRing, root.semanticProfile.focusWidth)
        : Border.controlSpec(root.checked ? "selected" : (root.hot || (root.focusable && root.activeFocus) ? "hover-cursor" : "normal"), root.foreground, root.accent)

      Rectangle {
        width: root.dotSize
        height: root.dotSize
        radius: width / 2
        anchors.centerIn: parent
        visible: root.checked
        color: root.accent

        Behavior on scale { NumberAnimation { duration: Semantics.duration(root.semanticProfile, Tokens.motion.fast) } }
      }
    }

    Text {
      textFormat: Text.PlainText
      id: labelText
      visible: root.label !== ""
      text: Semantics.text(root.semanticProfile, root.label)
      width: root.labelMaximumWidth > 0 ? root.labelMaximumWidth : implicitWidth
      color: root.foreground
      font.family: Tokens.typography.family
      font.pixelSize: Semantics.font(root.semanticProfile, Style.font.body)
      wrapMode: Text.WordWrap
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: {
      if (!root.checked) {
        // Exclusive selection within a group: uncheck siblings by walking
        // the parent's children. Cheap, dependency-free, good enough for
        // the small static groups this kit serves.
        if (root.group !== "" && root.parent) {
          var siblings = root.parent.children
          for (var i = 0; i < siblings.length; i++) {
            var s = siblings[i]
            if (s !== root && s.group === root.group && s.checked) s.checked = false
          }
        }
        root.checked = true
      }
      if (root.focusable) root.forceActiveFocus()
      root.toggled()
    }
  }
}
