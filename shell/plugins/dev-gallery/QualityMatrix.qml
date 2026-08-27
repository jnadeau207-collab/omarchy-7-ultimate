import QtQuick
import QtQuick.Layouts
import qs.Ui
import qs.Commons

Column {
  id: root

  property bool hasCursor: false
  property string lastAction: "none"
  readonly property bool hovered: matrixHover.hovered
  readonly property var operationStates: [
    { id: "success", label: "Success", message: "The update installed.", tone: "success", progress: 1 },
    { id: "no-op", label: "No-op", message: "Everything was already current.", tone: "info", progress: 1 },
    { id: "progress", label: "Progress", message: "Installing verified packages…", tone: "accent", progress: 0.64 },
    { id: "denial", label: "Denial", message: "Administrator approval was denied.", tone: "warning", progress: 0 },
    { id: "failure", label: "Failure", message: "The transaction rolled back safely.", tone: "danger", progress: 0.42 },
    { id: "cancel", label: "Cancel", message: "The operation was cancelled.", tone: "warning", progress: 0.25 },
    { id: "restart", label: "Restart", message: "Restart to finish applying changes.", tone: "info", progress: 1 },
    { id: "recovery", label: "Recovery", message: "The previous configuration was restored.", tone: "success", progress: 1 }
  ]
  readonly property var presentationCases: [
    { id: "dark-comfortable-pointer", label: "Dark · comfortable · 1× · pointer", dark: true, density: "comfortable", scaleFactor: 1, highContrast: false, reducedMotion: false, rtl: false, large: false, focusMode: "pointer" },
    { id: "light-compact-keyboard-pseudo", label: "[!! Ŀïĝħŧ · çöɱþäçŧ · 1.25× · ķëÿɓöäŕđ !!]", dark: false, density: "compact", scaleFactor: 1.25, highContrast: true, reducedMotion: true, rtl: false, large: true, focusMode: "keyboard" },
    { id: "dark-touch-rtl-long", label: "Touch density · 1.5× · reduced motion · deliberately extended localization fixture", dark: true, density: "touch", scaleFactor: 1.5, highContrast: true, reducedMotion: true, rtl: true, large: true, focusMode: "keyboard" },
    { id: "light-comfortable-rtl-two-x", label: "فاتح · مريح · ٢× · مؤشر", dark: false, density: "comfortable", scaleFactor: 2, highContrast: false, reducedMotion: false, rtl: true, large: false, focusMode: "pointer" }
  ]

  function activatePrimary() {
    root.lastAction = "success"
  }

  spacing: Style.space(10)
  Accessible.role: Accessible.Pane
  Accessible.name: "Ultimate quality state matrix"
  Accessible.description: "Operation outcomes and pairwise accessibility presentation fixtures"

  HoverHandler { id: matrixHover }

  Text {
    text: "Accessible state and presentation matrix"
    color: Tokens.text.primary
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    text: "All operation outcomes are exhaustive. Presentation profiles are deterministic pairwise fixtures; AT-SPI proof remains a separate disposable-VM gate."
    color: Tokens.text.secondary
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Grid {
    width: parent.width
    columns: 2
    spacing: Style.space(8)

    Repeater {
      model: root.operationStates

      Card {
        required property var modelData
        required property int index
        width: (root.width - Style.space(8)) / 2
        implicitHeight: stateContent.implicitHeight + Style.space(20)
        clickable: true
        hasCursor: root.hasCursor && index === 0
        Accessible.role: Accessible.Button
        Accessible.name: modelData.label + " operation state"
        Accessible.description: modelData.message
        Accessible.onPressAction: root.lastAction = modelData.id
        onClicked: root.lastAction = modelData.id

        Column {
          id: stateContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(6)

          RowLayout {
            width: parent.width

            Text {
              Layout.fillWidth: true
              text: modelData.label
              color: modelData.tone === "danger" ? Tokens.state.danger
                : modelData.tone === "warning" ? Tokens.state.warning
                : modelData.tone === "success" ? Tokens.state.success
                : Tokens.text.primary
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              text: modelData.id
              color: Tokens.text.disabled
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: modelData.message
            color: Tokens.text.secondary
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          ProgressBar {
            width: parent.width
            value: modelData.progress
            indeterminate: modelData.id === "progress"
            tone: modelData.tone
            Accessible.role: Accessible.ProgressBar
            Accessible.name: modelData.label + " progress"
            Accessible.description: modelData.label + " progress: " + Math.round(modelData.progress * 100) + " percent. Numeric AT-SPI value export is not yet available."
          }
        }
      }
    }
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

      Rectangle {
        required property var modelData
        width: (root.width - Style.space(8)) / 2
        height: Math.round((modelData.density === "touch" ? 88 : modelData.density === "compact" ? 60 : 72) * Math.min(modelData.scaleFactor, 1.25))
        radius: Tokens.radius.medium
        color: modelData.dark ? "#17191d" : "#f7f8fa"
        border.width: modelData.highContrast ? 3 : modelData.focusMode === "keyboard" ? 2 : 1
        border.color: modelData.focusMode === "keyboard" ? "#4f9dff" : modelData.dark ? "#ffffff" : "#000000"
        Accessible.role: Accessible.StaticText
        Accessible.name: modelData.id + " presentation fixture"
        Accessible.description: modelData.density + " density at " + modelData.scaleFactor + " scale; " + (modelData.reducedMotion ? "reduced motion" : "full motion") + "; " + modelData.focusMode + " focus"

        RowLayout {
          anchors.fill: parent
          anchors.margins: modelData.density === "compact" ? Style.space(6) : modelData.density === "touch" ? Style.space(14) : Style.space(10)
          layoutDirection: modelData.rtl ? Qt.RightToLeft : Qt.LeftToRight

          Rectangle {
            Layout.preferredWidth: modelData.large ? 28 : 20
            Layout.preferredHeight: width
            radius: width / 2
            color: modelData.dark ? "#8fc7ff" : "#005fcc"
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: modelData.label
            color: modelData.dark ? "#ffffff" : "#101318"
            font.family: Style.font.family
            font.pixelSize: Math.round((modelData.large ? Style.font.subtitle : Style.font.bodySmall) * Math.min(modelData.scaleFactor, 1.3))
            horizontalAlignment: modelData.rtl ? Text.AlignRight : Text.AlignLeft
          }

          Text {
            text: modelData.reducedMotion ? "motion off" : "motion on"
            color: modelData.dark ? "#c5c9d2" : "#3e4652"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  Row {
    spacing: Style.space(8)

    Button {
      text: "Keyboard focus action"
      focusable: true
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
