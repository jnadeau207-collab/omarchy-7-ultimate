import QtQuick
import qs.Commons

Item {
  id: root

  property bool checked: false
  property string label: ""
  property real labelMaximumWidth: 0
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
  readonly property int boxSize: Math.max(16, Math.round(Semantics.font(semanticProfile, Style.font.body) * 1.25))

  implicitWidth: box.implicitWidth
  implicitHeight: Math.max(box.implicitHeight, Semantics.minimumTarget(semanticProfile))

  Accessible.role: Accessible.CheckBox
  Accessible.name: Semantics.text(semanticProfile, label)
  Accessible.description: accessibleDescription !== "" ? accessibleDescription
    : Semantics.text(semanticProfile, checked ? "Checked" : "Not checked")
  Accessible.onPressAction: {
    if (root.enabled) root.toggled()
  }

  Row {
    id: box
    anchors.verticalCenter: parent.verticalCenter
    spacing: Semantics.metric(root.semanticProfile, Style.space(8))

    BorderSurface {
      id: square
      width: root.boxSize
      height: root.boxSize
      radius: Math.max(3, Math.round(Style.cornerRadius * 0.5))
      color: root.checked ? root.accent
        : mouse.pressed ? Util.alpha(root.accent, 0.18)
        : root.hot ? Util.alpha(root.foreground, 0.08)
        : "transparent"
      borderSpec: root.semanticProfile && root.semanticProfile.highContrast && root.focusable && root.activeFocus
        ? Border.flat(root.semanticProfile.focusRing, root.semanticProfile.focusWidth)
        : Border.controlSpec(root.checked ? "selected" : (root.hot || (root.focusable && root.activeFocus) ? "hover-cursor" : "normal"), root.foreground, root.accent)

      Behavior on color { ColorAnimation { duration: Semantics.duration(root.semanticProfile, Tokens.motion.fast) } }

      Text {
        anchors.centerIn: parent
        visible: root.checked
        text: "\u2713"
        color: root.semanticProfile ? root.semanticProfile.surfaceBase : Tokens.surface.base
        font.family: Tokens.typography.family
        font.pixelSize: root.boxSize * 0.8
        font.bold: true
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
      if (root.focusable) root.forceActiveFocus()
      root.toggled()
    }
  }
}
