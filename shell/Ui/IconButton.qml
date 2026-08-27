import QtQuick
import QtQuick.Controls
import qs.Commons

// Icon-only button for toolbars, caption bars, and tray-adjacent chrome.
// Square hitbox with a generous target area even when the glyph is small —
// caption buttons and titlebar controls depend on this (Rule 2: everything
// possible with the mouse).
//
// `danger` flips hover/press to the semantic danger color for destructive
// actions (window close). States follow the shared kit priority: pressed >
// focus > hover > idle.
BorderSurface {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property var semanticProfile: null
  property string accessibleName: tooltipText
  property string accessibleDescription: ""

  property bool danger: false
  property bool hasCursor: false
  property bool focusable: false
  property bool forceFocusVisible: false
  property bool bordered: false
  property bool selected: false

  // Square by default; consumers can stretch via explicit width/height.
  property int size: Math.max(28, Math.round(Style.spacing.controlHeight * 0.9),
    semanticProfile ? Semantics.minimumTarget(semanticProfile) : 0)
  property real glyphSize: Semantics.font(semanticProfile, Style.font.icon)

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  implicitWidth: size
  implicitHeight: size
  radius: Style.cornerRadius

  readonly property bool hot: mouse.containsMouse || hasCursor
  readonly property bool _showFocusRing: focusable && (activeFocus || forceFocusVisible)
  readonly property color _stateColor: danger
    ? Semantics.toneColor("danger", semanticProfile)
    : Semantics.toneColor("accent", semanticProfile)
  readonly property color _fg: semanticProfile ? semanticProfile.textPrimary : Tokens.text.primary

  color: mouse.pressed ? Util.alpha(_stateColor, 0.28)
    : _showFocusRing ? Util.alpha(_stateColor, 0.20)
    : hot ? Util.alpha(_stateColor, 0.14)
    : selected ? Util.alpha(_stateColor, 0.18)
    : "transparent"

  borderSpec: _showFocusRing && semanticProfile && semanticProfile.highContrast
    ? Border.flat(semanticProfile.focusRing, semanticProfile.focusWidth)
    : bordered || hot || _showFocusRing
    ? Border.controlSpec(hot || _showFocusRing ? "hover-cursor" : "normal", _fg, _stateColor)
    : Border.none()

  Behavior on color { ColorAnimation { duration: Semantics.duration(root.semanticProfile, Tokens.motion.fast) } }

  Accessible.role: Accessible.Button
  Accessible.name: accessibleName !== "" ? Semantics.text(semanticProfile, accessibleName) : "Icon action"
  Accessible.description: accessibleDescription
  Accessible.onPressAction: {
    if (root.enabled) root.clicked()
  }

  ToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: Semantics.text(root.semanticProfile, root.tooltipText)
    delay: 400
    padding: 0
    background: BorderSurface {
      color: Tokens.surface.overlay
      radius: Style.cornerRadius
    }
    contentItem: Text {
      text: Semantics.text(root.semanticProfile, root.tooltipText)
      color: Tokens.text.primary
      font.family: Style.font.family
      font.pixelSize: Semantics.font(root.semanticProfile, Style.font.bodySmall)
    }
  }

  Text {
    anchors.centerIn: parent
    text: root.iconText
    color: root._fg
    font.family: Style.font.family
    font.pixelSize: root.glyphSize
    anchors.verticalCenterOffset: -1
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (root.focusable) root.forceActiveFocus()
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
