import QtQuick
import qs.Commons

// Card: the standard content container for Ultimate surfaces. Settings
// pages, Start tiles, notification stacks, and dashboard panels all sit in
// cards so elevation reads consistently across the shell.
//
// Elevation maps to the semantic surface doctrine (docs/design-tokens.md):
//   base   — windows, settings pages, standard cards (default)
//   raised — cards floating above other content (hover-elevated rows, popovers)
//   glass  — transient shell chrome; prefer PopupCard for that today
//
// Cards are passive by default: they paint surface + border only. Interactive
// cards set `clickable` to get the kit's hover/press/focus states and clicked().
BorderSurface {
  id: root

  // Elevation: "base" | "raised"
  property string elevation: "base"
  property var semanticProfile: null
  property string accessibleName: ""
  property string accessibleDescription: ""

  // Interactive affordances. Off by default — most cards are containers.
  property bool clickable: false
  property bool hasCursor: false

  signal clicked()
  signal rightClicked()
  signal hovered(bool on)

  readonly property bool _hot: clickable && (mouse.containsMouse || hasCursor)

  radius: Tokens.radius.large
  color: semanticProfile
    ? (elevation === "raised" ? semanticProfile.surfaceRaised : semanticProfile.surfaceBase)
    : (elevation === "raised" ? Tokens.surface.raised : Tokens.surface.base)
  borderSpec: Border.controlSpec(clickable && _hot ? "hover-cursor" : "normal",
    semanticProfile ? semanticProfile.textPrimary : Tokens.text.primary,
    semanticProfile ? semanticProfile.accent : Tokens.accent.primary)

  Behavior on color { ColorAnimation { duration: Semantics.duration(root.semanticProfile, Tokens.motion.fast) } }

  implicitWidth: content.implicitWidth + Semantics.metric(semanticProfile, Style.spacing.controlPaddingX) * 2
  implicitHeight: content.implicitHeight + Semantics.metric(semanticProfile, Style.spacing.controlPaddingY) * 2

  Accessible.role: clickable ? Accessible.Button : Accessible.Pane
  Accessible.name: Semantics.text(semanticProfile, accessibleName)
  Accessible.description: Semantics.text(semanticProfile, accessibleDescription)
  Accessible.onPressAction: {
    if (root.clickable && root.enabled) root.clicked()
  }

  default property alias contentData: content.data

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: 0
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.clickable
    hoverEnabled: true
    cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }
}
