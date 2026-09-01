import QtQuick
import qs.Commons

BorderSurface {
  id: root

  property bool hasCursor: false
  property bool current: false
  property bool outline: false
  property bool bordered: false

  property color foreground: Tokens.text.primary
  property color accent: Tokens.accent.primary
  property color fill: Style.hoverFillFor(foreground, accent)
  property color currentFill: Style.selectedFillFor(foreground, accent)

  radius: Style.cornerRadius

  color: hasCursor ? fill : (current ? currentFill : "transparent")
  borderSpec: root.hasCursor
    ? Border.controlSpec("hover-cursor", root.foreground, root.accent)
    : (root.current
      ? Border.controlSpec("selected", root.foreground, root.accent)
      : (root.bordered
        ? Border.controlSpec("normal", root.foreground, root.accent)
        : Border.none()))

  Behavior on color {
    ColorAnimation { duration: 60 }
  }
}
