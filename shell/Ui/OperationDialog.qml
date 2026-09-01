import QtQuick
import qs.Commons

Item {
  id: root

  property bool opened: false
  property var semanticProfile: null
  property string stateId: "restart"
  property string title: ""
  property string message: ""
  property string recoveryText: ""
  property string cancelText: "Cancel"
  property string primaryText: ""
  property bool destructive: false
  property string toneOverride: ""
  property int selectedIndex: 0

  signal canceled()
  signal confirmed()

  readonly property var definition: Semantics.operation(stateId)
  readonly property string resolvedTitle: title !== "" ? title : definition.label
  readonly property string resolvedMessage: message !== "" ? message : definition.message
  readonly property string resolvedPrimaryText: primaryText !== "" ? primaryText : definition.primaryAction
  readonly property string resolvedTone: toneOverride !== "" ? toneOverride : definition.tone
  readonly property color toneColor: Semantics.toneColor(resolvedTone, semanticProfile)

  visible: opened
  focus: opened
  Accessible.role: Accessible.Dialog
  Accessible.name: Semantics.text(semanticProfile, resolvedTitle)
  Accessible.description: Semantics.text(semanticProfile, resolvedMessage
    + (recoveryText !== "" ? " " + recoveryText : ""))

  onOpenedChanged: {
    if (opened) {
      selectedIndex = 0
      forceActiveFocus()
    }
  }

  Keys.onPressed: function(event) {
    if (!root.opened) return
    if (event.key === Qt.Key_Escape) {
      root.canceled()
      event.accepted = true
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
      || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      if (root.selectedIndex === 0) root.canceled()
      else root.confirmed()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(root.semanticProfile ? root.semanticProfile.surfaceCanvas : Tokens.surface.canvas, 0.78)

    MouseArea {
      anchors.fill: parent
      onClicked: root.canceled()
    }

    Card {
      id: dialogCard
      anchors.centerIn: parent
      width: Math.min(parent.width - Semantics.metric(root.semanticProfile, 32),
        Semantics.metric(root.semanticProfile, 430, 320))
      implicitHeight: dialogBody.implicitHeight + Semantics.metric(root.semanticProfile, 32)
      elevation: "raised"
      semanticProfile: root.semanticProfile
      borderSpec: Border.flat(root.toneColor,
        root.semanticProfile && root.semanticProfile.highContrast ? root.semanticProfile.focusWidth : 1)
      accessibleName: root.resolvedTitle
      accessibleDescription: root.resolvedMessage

      MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

      Column {
        id: dialogBody
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Semantics.metric(root.semanticProfile, 16)
        spacing: Semantics.metric(root.semanticProfile, 10)
        LayoutMirroring.enabled: root.semanticProfile && root.semanticProfile.rtl
        LayoutMirroring.childrenInherit: true

        Row {
          width: parent.width
          spacing: Semantics.metric(root.semanticProfile, 8)
          layoutDirection: root.semanticProfile && root.semanticProfile.rtl ? Qt.RightToLeft : Qt.LeftToRight

          Text {
            textFormat: Text.PlainText
            text: root.definition.symbol
            color: root.toneColor
            font.family: Tokens.typography.family
            font.pixelSize: Semantics.font(root.semanticProfile, Style.font.title)
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width - x
            text: Semantics.text(root.semanticProfile, root.resolvedTitle)
            color: root.semanticProfile ? root.semanticProfile.textPrimary : Tokens.text.primary
            font.family: Tokens.typography.family
            font.pixelSize: Semantics.font(root.semanticProfile, Style.font.title)
            font.bold: true
            wrapMode: Text.WordWrap
            horizontalAlignment: root.semanticProfile && root.semanticProfile.rtl ? Text.AlignRight : Text.AlignLeft
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: Semantics.text(root.semanticProfile, root.resolvedMessage)
          color: root.semanticProfile ? root.semanticProfile.textPrimary : Tokens.text.primary
          font.family: Tokens.typography.family
          font.pixelSize: Semantics.font(root.semanticProfile, Style.font.body)
          wrapMode: Text.WordWrap
          horizontalAlignment: root.semanticProfile && root.semanticProfile.rtl ? Text.AlignRight : Text.AlignLeft
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.recoveryText !== ""
          text: Semantics.text(root.semanticProfile, root.recoveryText)
          color: root.toneColor
          font.family: Tokens.typography.family
          font.pixelSize: Semantics.font(root.semanticProfile, Style.font.bodySmall)
          font.bold: true
          wrapMode: Text.WordWrap
          horizontalAlignment: root.semanticProfile && root.semanticProfile.rtl ? Text.AlignRight : Text.AlignLeft
        }

        Flow {
          width: parent.width
          spacing: Semantics.metric(root.semanticProfile, 8)
          layoutDirection: root.semanticProfile && root.semanticProfile.rtl ? Qt.RightToLeft : Qt.LeftToRight

          Button {
            text: root.cancelText
            semanticProfile: root.semanticProfile
            selected: root.selectedIndex === 0
            focusable: true
            bordered: true
            onClicked: root.canceled()
          }

          Button {
            text: root.resolvedPrimaryText
            semanticProfile: root.semanticProfile
            selected: root.selectedIndex === 1
            focusable: true
            bordered: true
            foreground: root.destructive ? root.toneColor
              : (root.semanticProfile ? root.semanticProfile.textPrimary : Tokens.text.primary)
            onClicked: root.confirmed()
          }
        }
      }
    }
  }
}
