import QtQuick
import qs.Commons

Item {
  id: root

  property bool checked: false
  property bool busy: false
  property var semanticProfile: null
  property string accessibleName: "Toggle"
  property string accessibleDescription: ""

  property bool interactive: true
  property bool focusable: interactive
  property bool accessibleIgnored: !interactive
  property bool forceFocusVisible: false

  property bool hasCursor: false

  property bool cursorRing: interactive
  property int cursorPad: Semantics.metric(semanticProfile, Style.space(6))
  property bool rounded: Style.cornerRadius > 0
  property color foreground: semanticProfile ? semanticProfile.textPrimary : Tokens.text.primary
  property color accent: semanticProfile ? semanticProfile.accent : Tokens.accent.primary

  signal toggled()
  signal hovered(bool isHovered)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property bool hot: hasCursor || mouse.containsMouse
  readonly property bool focusVisible: focusable && (activeFocus || forceFocusVisible)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable && !busy) root.toggled()
  Keys.onEnterPressed: if (focusable && !busy) root.toggled()
  Keys.onSpacePressed: if (focusable && !busy) root.toggled()

  property int trackHeight: Math.max(22, Math.round(Semantics.metric(semanticProfile, Style.spacing.controlHeight) * 0.55))
  property int trackWidth: Math.round(trackHeight * 1.9)
  property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
  property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))

  readonly property int _pad: cursorRing ? cursorPad : 0

  implicitWidth: Math.max(trackWidth + _pad * 2, semanticProfile ? Semantics.minimumTarget(semanticProfile) : 0)
  implicitHeight: Math.max(trackHeight + _pad * 2, semanticProfile ? Semantics.minimumTarget(semanticProfile) : 0)

  Accessible.role: Accessible.CheckBox
  Accessible.ignored: root.accessibleIgnored
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.focusable: root.focusable
  Accessible.name: Semantics.text(semanticProfile, accessibleName)
  Accessible.description: accessibleDescription !== "" ? accessibleDescription
    : Semantics.text(semanticProfile, busy ? "Busy" : checked ? "On" : "Off")
  Accessible.onPressAction: {
    if (root.interactive && !root.busy && root.enabled) root.toggled()
  }

  BorderSurface {
    anchors.fill: parent
    visible: root.cursorRing && (root.hot || root.focusVisible)
    color: "transparent"
    radius: Style.cornerRadius
    borderSpec: root.semanticProfile && root.semanticProfile.highContrast && root.focusVisible
      ? Border.flat(root.semanticProfile.focusRing, root.semanticProfile.focusWidth)
      : Border.controlSpec("hover-cursor", root.foreground, root.accent)
  }

  BorderSurface {
    id: track
    width: root.trackWidth
    height: root.trackHeight
    anchors.centerIn: parent
    radius: root.rounded ? height / 2 : 0
    color: root.checked
      ? Style.selectedFillFor(root.foreground, root.accent)
      : Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec(root.checked ? "selected" : "normal", root.foreground, root.accent)

    Behavior on color { ColorAnimation { duration: Semantics.duration(root.semanticProfile, 120) } }

    Rectangle {
      width: root.knobSize
      height: root.knobSize
      radius: root.rounded ? height / 2 : 0
      x: root.checked ? track.width - width - root.knobInset : root.knobInset
      anchors.verticalCenter: parent.verticalCenter
      color: root.checked ? Style.selectedStateColor(root.foreground, root.accent) : Qt.darker(root.foreground, 1.25)

      Behavior on x { NumberAnimation { duration: Semantics.duration(root.semanticProfile, 120); easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: Semantics.duration(root.semanticProfile, 120) } }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: {
      if (root.focusable) root.forceActiveFocus()
      if (!root.busy) root.toggled()
    }
  }
}
