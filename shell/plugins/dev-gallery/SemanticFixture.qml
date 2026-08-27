import QtQuick
import QtQuick.Layouts
import qs.Ui
import qs.Commons

// Executable presentation fixture: every case instantiates the same real
// shared controls under a different semantic profile. It is intentionally
// self-contained so light/dark, density and accessibility cases can coexist
// without mutating the process-wide theme.
Card {
  id: root

  property string caseId: "default"
  property string label: "Default presentation"
  property bool dark: true
  property string density: "comfortable"
  property real profileScale: 1
  property bool highContrast: false
  property bool reducedMotion: false
  property bool rtl: false
  property bool largeText: false
  property string locale: "en-US"
  property string focusMode: "pointer"
  property bool checked: true

  readonly property bool targetSizesPass: applyButton.implicitHeight >= profile.minimumTarget
    && choice.implicitHeight >= profile.minimumTarget
    && recoverySwitch.implicitHeight >= profile.minimumTarget
    && recoveryToggle.implicitHeight >= profile.minimumTarget
    && searchField.implicitHeight >= profile.minimumTarget
  readonly property bool contentFits: applyButton.implicitWidth <= controls.width + 0.5
    && choice.implicitWidth <= controls.width + 0.5
    && recoverySwitch.implicitWidth <= controls.width + 0.5
    && fixtureBody.implicitHeight + profile.metric(24) <= implicitHeight + 0.5

  signal activated(string action)

  SemanticProfile {
    id: profile
    profileId: root.caseId
    densityMode: root.density
    scaleFactor: root.profileScale
    highContrast: root.highContrast
    reducedMotion: root.reducedMotion
    largeText: root.largeText
    textScale: root.largeText ? 1.25 : 1
    rtl: root.rtl
    pseudoLocale: root.locale === "pseudo"
    locale: root.locale
    surfaceCanvas: root.dark ? "#111318" : "#eef1f5"
    surfaceBase: root.dark ? "#17191d" : "#f7f8fa"
    surfaceRaised: root.dark ? "#202329" : "#ffffff"
    textPrimary: root.dark ? "#ffffff" : "#101318"
    textSecondary: root.dark ? "#d5d9e1" : "#303844"
    textDisabled: root.dark ? "#aeb5c0" : "#596472"
    accent: root.dark ? "#8fc7ff" : "#005fcc"
    success: root.dark ? "#73d69c" : "#126b35"
    warning: root.dark ? "#ffd166" : "#714700"
    danger: root.dark ? "#ff8a80" : "#9b261f"
    info: root.dark ? "#8fc7ff" : "#005fcc"
    focusRing: root.dark ? "#b9dcff" : "#004fa8"
    borderStrong: root.dark ? "#ffffff" : "#101318"
  }

  semanticProfile: profile
  elevation: "raised"
  accessibleName: label
  accessibleDescription: density + " density at " + profileScale + " scale; "
    + (reducedMotion ? "reduced motion" : "full motion") + "; "
    + (rtl ? "right-to-left" : "left-to-right") + "; " + focusMode + " focus"
  color: profile.surfaceBase
  borderSpec: Border.flat(focusMode === "keyboard" ? profile.focusRing : profile.borderStrong,
    focusMode === "keyboard" ? profile.focusWidth : 1)
  implicitWidth: Semantics.metric(profile, 340, 300)
  implicitHeight: fixtureBody.implicitHeight + Semantics.metric(profile, 24)

  Column {
    id: fixtureBody
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Semantics.metric(profile, 12)
    anchors.rightMargin: Semantics.metric(profile, 12)
    spacing: Semantics.metric(profile, 8)
    LayoutMirroring.enabled: profile.rtl
    LayoutMirroring.childrenInherit: true

    Text {
      width: parent.width
      text: profile.text(root.label)
      color: profile.textPrimary
      font.family: Style.font.family
      font.pixelSize: profile.font(Style.font.body)
      font.bold: true
      wrapMode: Text.WordWrap
      horizontalAlignment: profile.rtl ? Text.AlignRight : Text.AlignLeft
    }

    Text {
      width: parent.width
      text: profile.text(root.density + " density · " + profile.minimumTarget
        + " px minimum target · " + (root.reducedMotion ? "motion off" : "motion on"))
      color: profile.textSecondary
      font.family: Style.font.family
      font.pixelSize: profile.font(Style.font.caption)
      wrapMode: Text.WordWrap
      horizontalAlignment: profile.rtl ? Text.AlignRight : Text.AlignLeft
    }

    TextField {
      id: searchField
      width: parent.width
      semanticProfile: profile
      semanticPlaceholderText: "Search settings"
      accessibleName: "Search settings"
    }

    Flow {
      id: controls
      width: parent.width
      spacing: profile.metric(8)
      layoutDirection: profile.rtl ? Qt.RightToLeft : Qt.LeftToRight

      Button {
        id: applyButton
        text: "Apply changes"
        textMaximumWidth: Math.max(100, fixtureBody.width - profile.metric(56))
        semanticProfile: profile
        focusable: true
        forceFocusVisible: root.focusMode === "keyboard"
        bordered: true
        onClicked: root.activated("apply")
      }

      Checkbox {
        id: choice
        label: "Include optional items"
        labelMaximumWidth: Math.max(120, fixtureBody.width - profile.metric(44))
        semanticProfile: profile
        checked: root.checked
        focusable: true
        onToggled: root.checked = !root.checked
      }

      ToggleSwitch {
        id: recoverySwitch
        semanticProfile: profile
        accessibleName: "Compact mode"
        checked: root.checked
        onToggled: root.checked = !root.checked
      }
    }

    Toggle {
      id: recoveryToggle
      width: parent.width
      semanticProfile: profile
      label: "Automatic recovery"
      description: "Restore the previous settings if applying changes fails."
      checked: root.checked
      onClicked: root.checked = !root.checked
    }

    ProgressBar {
      width: parent.width
      semanticProfile: profile
      accessibleName: "Fixture operation"
      value: 0.64
      indeterminate: true
      tone: "info"
    }
  }
}
