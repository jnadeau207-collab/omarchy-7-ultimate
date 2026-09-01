import QtQuick
import QtQuick.Layouts
import qs.Commons

// Reusable operation-result surface. The state identifier is the contract;
// label, symbol, tone, default explanation and primary action all come from
// the shared semantic vocabulary. Callers may override copy without losing
// the color-independent state label or accessibility description.
Card {
  id: root

  property string stateId: "success"
  property string title: ""
  property string message: ""
  property real progress: -1
  property bool indeterminate: stateId === "progress" && progress < 0
  property bool showProgress: stateId === "progress" || progress >= 0
  property string primaryActionText: ""
  property string secondaryActionText: ""
  property bool showPrimaryAction: primaryActionText !== "" || stateId !== "success"
  property bool showSecondaryAction: secondaryActionText !== ""

  signal primaryClicked()
  signal secondaryClicked()

  readonly property var definition: Semantics.operation(stateId)
  readonly property string resolvedTitle: title !== "" ? title : definition.label
  readonly property string resolvedMessage: message !== "" ? message : definition.message
  readonly property string resolvedPrimaryAction: primaryActionText !== ""
    ? primaryActionText : definition.primaryAction
  readonly property color toneColor: Semantics.toneColor(definition.tone, semanticProfile)
  readonly property string stateDescription: resolvedTitle + ". " + resolvedMessage

  elevation: "raised"
  accessibleName: resolvedTitle
  accessibleDescription: stateDescription
  Accessible.role: stateId === "failure" || stateId === "denial"
    ? Accessible.AlertMessage : Accessible.Pane

  implicitWidth: Math.max(Semantics.metric(semanticProfile, 280, 240), body.implicitWidth
    + Semantics.metric(semanticProfile, Style.space(24)))
  implicitHeight: body.implicitHeight + Semantics.metric(semanticProfile, Style.space(24))

  Rectangle {
    width: Semantics.metric(root.semanticProfile, Style.space(4), 3)
    height: parent.height
    radius: root.radius
    color: root.toneColor
  }

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Semantics.metric(root.semanticProfile, Style.space(14))
    anchors.rightMargin: Semantics.metric(root.semanticProfile, Style.space(12))
    spacing: Semantics.metric(root.semanticProfile, Style.space(8))
    LayoutMirroring.enabled: root.semanticProfile && root.semanticProfile.rtl
    LayoutMirroring.childrenInherit: true

    RowLayout {
      width: parent.width
      layoutDirection: root.semanticProfile && root.semanticProfile.rtl ? Qt.RightToLeft : Qt.LeftToRight
      spacing: Semantics.metric(root.semanticProfile, Style.space(8))

      Rectangle {
        Layout.preferredWidth: Semantics.metric(root.semanticProfile, 28, 24)
        Layout.preferredHeight: Layout.preferredWidth
        radius: width / 2
        color: Util.alpha(root.toneColor, root.semanticProfile && root.semanticProfile.highContrast ? 0.28 : 0.18)
        border.width: root.semanticProfile && root.semanticProfile.highContrast ? 2 : 1
        border.color: root.toneColor

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.definition.symbol
          color: root.toneColor
          font.family: Tokens.typography.family
          font.pixelSize: Semantics.font(root.semanticProfile, Style.font.subtitle)
          font.bold: true
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: Semantics.text(root.semanticProfile, root.resolvedTitle)
        color: root.semanticProfile ? root.semanticProfile.textPrimary : Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Semantics.font(root.semanticProfile, Style.font.body)
        font.bold: true
        wrapMode: Text.WordWrap
        horizontalAlignment: root.semanticProfile && root.semanticProfile.rtl ? Text.AlignRight : Text.AlignLeft
      }

      Text {
        textFormat: Text.PlainText
        text: root.definition.id
        color: root.semanticProfile ? root.semanticProfile.textDisabled : Tokens.text.disabled
        font.family: Tokens.typography.family
        font.pixelSize: Semantics.font(root.semanticProfile, Style.font.caption)
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: Semantics.text(root.semanticProfile, root.resolvedMessage)
      color: root.semanticProfile ? root.semanticProfile.textPrimary : Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Semantics.font(root.semanticProfile, Style.font.bodySmall)
      wrapMode: Text.WordWrap
      horizontalAlignment: root.semanticProfile && root.semanticProfile.rtl ? Text.AlignRight : Text.AlignLeft
    }

    ProgressBar {
      width: parent.width
      visible: root.showProgress
      value: root.progress < 0 ? 0 : root.progress
      indeterminate: root.indeterminate
      tone: root.definition.tone
      semanticProfile: root.semanticProfile
      accessibleName: root.resolvedTitle + " progress"
    }

    Flow {
      width: parent.width
      spacing: Semantics.metric(root.semanticProfile, Style.space(8))
      layoutDirection: root.semanticProfile && root.semanticProfile.rtl ? Qt.RightToLeft : Qt.LeftToRight

      Button {
        visible: root.showPrimaryAction
        text: root.resolvedPrimaryAction
        semanticProfile: root.semanticProfile
        foreground: root.definition.tone === "danger" ? root.toneColor
          : (root.semanticProfile ? root.semanticProfile.textPrimary : Tokens.text.primary)
        bordered: true
        focusable: true
        onClicked: root.primaryClicked()
      }

      Button {
        visible: root.showSecondaryAction
        text: root.secondaryActionText
        semanticProfile: root.semanticProfile
        bordered: true
        focusable: true
        onClicked: root.secondaryClicked()
      }
    }
  }
}
