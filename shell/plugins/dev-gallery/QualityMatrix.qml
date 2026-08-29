import QtQuick
import qs.Ui
import qs.Commons

// Executable quality matrix. Operation rows render the production
// OperationStatus primitive; presentation rows render production controls
// under real opt-in SemanticProfile instances. No case is a mock rectangle.
Column {
  id: root

  property bool hasCursor: false
  property string lastAction: "none"
  property alias focusAnchor: titleLabel
  readonly property bool hovered: matrixHover.hovered
  readonly property var operationStates: [
    { id: "success", message: "The update installed.", progress: 1 },
    { id: "no-op", message: "Everything was already current.", progress: 1 },
    { id: "progress", message: "Installing verified packages…", progress: -1 },
    { id: "denial", message: "Administrator approval was denied; no change was made.", progress: 0 },
    { id: "failure", message: "The transaction failed and rolled back safely.", progress: 0.42 },
    { id: "cancel", message: "The operation was cancelled before completion.", progress: 0.25 },
    { id: "restart", message: "Restart to finish applying changes.", progress: 1 },
    { id: "recovery", message: "The previous configuration can be restored.", progress: 1 }
  ]
  readonly property var presentationCases: [
    { id: "dark-comfortable-pointer", label: "Dark · comfortable · 1× · pointer", dark: true, density: "comfortable", scaleFactor: 1, highContrast: false, reducedMotion: false, rtl: false, large: false, locale: "en-US", focusMode: "pointer" },
    { id: "light-compact-keyboard-pseudo", label: "Light · compact · 1.25× · keyboard", dark: false, density: "compact", scaleFactor: 1.25, highContrast: true, reducedMotion: true, rtl: false, large: true, locale: "pseudo", focusMode: "keyboard" },
    { id: "dark-touch-rtl-long", label: "Touch density · 1.5× · reduced motion", dark: true, density: "touch", scaleFactor: 1.5, highContrast: true, reducedMotion: true, rtl: true, large: true, locale: "long", focusMode: "keyboard" },
    { id: "light-comfortable-rtl-two-x", label: "Light · comfortable · 2× · pointer", dark: false, density: "comfortable", scaleFactor: 2, highContrast: false, reducedMotion: false, rtl: true, large: false, locale: "en-US", focusMode: "pointer" }
  ]

  function activatePrimary() {
    lastAction = "success:primary"
  }

  spacing: Style.space(10)
  Accessible.role: Accessible.Pane
  Accessible.name: "Ultimate executable accessible state matrix"
  Accessible.description: "Operation outcomes and pairwise accessibility presentation fixtures built from shared controls"

  HoverHandler { id: matrixHover }

  Text {
    id: titleLabel
    text: "Executable accessible state and presentation matrix"
    color: Tokens.text.primary
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    text: "All eight operation outcomes use the shared status primitive. The four deterministic presentation profiles use shared inputs, choices, actions, progress, semantic roles, target sizing, bidirectional layout, large text, high contrast, and reduced motion."
    color: Tokens.text.primary
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Grid {
    width: parent.width
    columns: 2
    spacing: Style.space(8)

    Repeater {
      model: root.operationStates

      OperationStatus {
        required property var modelData
        required property int index
        width: (root.width - Style.space(8)) / 2
        stateId: modelData.id
        message: modelData.message
        progress: modelData.progress
        showProgress: true
        showPrimaryAction: true
        secondaryActionText: modelData.id === "failure" || modelData.id === "denial" ? "Details" : ""
        clickable: false
        onPrimaryClicked: root.lastAction = modelData.id + ":primary"
        onSecondaryClicked: root.lastAction = modelData.id + ":secondary"
      }
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Numeric AT-SPI value export is not yet available. Progress exposes a precise percentage or indeterminate state through its accessible description until the installed Qt runtime provides that attached property."
    color: Tokens.text.primary
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    Accessible.role: Accessible.StaticText
    Accessible.name: "AT-SPI progress-value feasibility"
    Accessible.description: text
  }

  Text {
    text: "Presentation profiles"
    color: Tokens.text.primary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Grid {
    width: parent.width
    columns: 2
    spacing: Style.space(8)

    Repeater {
      model: root.presentationCases

      SemanticFixture {
        required property var modelData
        width: (root.width - Style.space(8)) / 2
        caseId: modelData.id
        label: modelData.label
        dark: modelData.dark
        density: modelData.density
        profileScale: modelData.scaleFactor
        highContrast: modelData.highContrast
        reducedMotion: modelData.reducedMotion
        rtl: modelData.rtl
        largeText: modelData.large
        locale: modelData.locale
        focusMode: modelData.focusMode
        onActivated: function(action) { root.lastAction = modelData.id + ":" + action }
      }
    }
  }

  Text {
    text: "Operation dialogs"
    color: Tokens.text.primary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Grid {
    width: parent.width
    columns: 2
    spacing: Style.space(8)

    OperationDialog {
      width: (root.width - Style.space(8)) / 2
      height: Style.space(250)
      opened: true
      stateId: "restart"
      title: "Restart the shell?"
      message: "The new configuration is ready. Restart the shell to apply it."
      recoveryText: "Cancel keeps the current shell running."
      onCanceled: root.lastAction = "restart-dialog:cancel"
      onConfirmed: root.lastAction = "restart-dialog:confirm"
    }

    DestructiveDialog {
      width: (root.width - Style.space(8)) / 2
      height: Style.space(250)
      opened: true
      targetName: "saved workspace"
      consequence: "Deleting this workspace removes its local layout and shortcuts."
      recovery: "Export a backup first if you may need to restore it."
      destructiveActionText: "Delete workspace"
      onCanceled: root.lastAction = "destructive-dialog:cancel"
      onConfirmed: root.lastAction = "destructive-dialog:confirm"
    }
  }

  Row {
    spacing: Style.space(8)

    Button {
      text: "Keyboard focus action"
      focusable: true
      forceFocusVisible: root.hasCursor
      bordered: true
      Accessible.role: Accessible.Button
      Accessible.name: "Keyboard focus action"
      Accessible.onPressAction: root.lastAction = "keyboard"
      onClicked: root.lastAction = "keyboard"
    }

    Button {
      text: "Pointer focus action"
      bordered: true
      Accessible.role: Accessible.Button
      Accessible.name: "Pointer focus action"
      Accessible.onPressAction: root.lastAction = "pointer"
      onClicked: root.lastAction = "pointer"
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: "last action: " + root.lastAction
      color: Tokens.text.secondary
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      Accessible.role: Accessible.StaticText
      Accessible.name: "Last action"
      Accessible.description: "Last action: " + root.lastAction
    }
  }
}
