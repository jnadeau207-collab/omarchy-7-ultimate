import QtQuick
import QtQuick.Controls
import qs.Commons

TextField {
  id: root

  property var semanticProfile: null
  property string semanticPlaceholderText: ""
  property string accessibleName: semanticPlaceholderText !== "" ? semanticPlaceholderText : placeholderText
  property string accessibleDescription: ""
  property color foreground: semanticProfile ? semanticProfile.textPrimary : Tokens.text.primary
  property color accent: semanticProfile ? semanticProfile.accent : Tokens.accent.primary
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property bool password: false
  property real horizontalPadding: Semantics.metric(semanticProfile, Style.spacing.controlPaddingX)
  property real verticalPadding: Semantics.metric(semanticProfile, Style.spacing.inputPaddingY)

  property bool hasCursor: false

  readonly property bool _focused: activeFocus
  readonly property bool _hot: hovered || hasCursor
  readonly property var _borderSpec: semanticProfile && semanticProfile.highContrast && _focused
    ? Border.flat(semanticProfile.focusRing, semanticProfile.focusWidth)
    : Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

  echoMode: password ? TextInput.Password : TextInput.Normal
  placeholderText: semanticPlaceholderText !== ""
    ? Semantics.text(semanticProfile, semanticPlaceholderText) : ""
  font.family: Tokens.typography.family
  font.pixelSize: Semantics.font(semanticProfile, Style.font.body)
  color: foreground
  selectionColor: selectionTint
  selectedTextColor: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)

  leftPadding: horizontalPadding + Border.left(_borderSpec)
  rightPadding: horizontalPadding + Border.right(_borderSpec)
  topPadding: verticalPadding + Border.top(_borderSpec)
  bottomPadding: verticalPadding + Border.bottom(_borderSpec)
  implicitHeight: Math.max(contentHeight + topPadding + bottomPadding,
    semanticProfile ? Semantics.minimumTarget(semanticProfile) : 0)

  Accessible.role: Accessible.EditableText
  Accessible.name: Semantics.text(semanticProfile, accessibleName)
  Accessible.description: Semantics.text(semanticProfile, accessibleDescription)

  background: BorderSurface {
    color: Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.cornerRadius
  }
}
