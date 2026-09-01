import QtQuick
import QtQuick.Controls
import qs.Commons

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

  property int size: Math.max(28, Math.round(Style.spacing.controlHeight * 0.9),
    Semantics.minimumTarget(semanticProfile))
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
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.tooltipText)
      color: Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Semantics.font(root.semanticProfile, Style.font.bodySmall)
    }
  }

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: root.iconText
    color: root._fg
    font.family: Tokens.icons.family
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
