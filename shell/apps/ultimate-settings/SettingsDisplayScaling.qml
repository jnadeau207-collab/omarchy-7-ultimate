import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import qs.apps.shared as Shared
import "SettingsModel.js" as SettingsModel

Rectangle {
  id: root

  property var semanticProfile: null
  property bool pageActive: false

  radius: Tokens.radius.medium
  color: Tokens.surface.raised
  border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
  border.width: Tokens.accessibility.highContrast ? 2 : 1
  implicitHeight: scalingColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "Display scaling")

  property var sessionScaling: SettingsModel.sessionScalingIdle()
  readonly property var scaleChoices: SettingsModel.sessionScalingChoices()

  readonly property bool busy: sessionHost.busy

  onPageActiveChanged: {
    if (pageActive) refreshStatus()
  }

  function refreshStatus() {
    if (root.busy) return
    root.sessionScaling = SettingsModel.sessionScalingAccepted(root.sessionScaling, "status")
    if (!sessionHost.readStatus()) {
      root.sessionScaling = SettingsModel.sessionScalingFinished(root.sessionScaling, {
        ok: false,
        code: "scale.busy",
        explanation: "The session monitor scaling helper is busy."
      })
    }
  }

  function applyScale(scale) {
    if (root.busy) return
    root.sessionScaling = SettingsModel.sessionScalingAccepted(root.sessionScaling, "set")
    if (!SettingsModel.sessionScalingCanSubmit(scale)) {
      root.sessionScaling = SettingsModel.sessionScalingFinished(root.sessionScaling, {
        ok: false,
        code: "payload.invalid",
        explanation: "Scale must be one of 1, 1.25, 1.6, 2, 3, or 4."
      })
      return
    }
    if (!sessionHost.setScale(scale)) {
      root.sessionScaling = SettingsModel.sessionScalingFinished(root.sessionScaling, {
        ok: false,
        code: "scale.busy",
        explanation: "The session monitor scaling helper is busy."
      })
    }
  }

  readonly property string scalingHonesty: {
    if (root.busy && root.sessionScaling.action === "set")
      return "Applying focused Hyprland monitor scale through this session."
    if (root.busy)
      return "Reading focused Hyprland monitor scale through this session."
    if (root.sessionScaling.phase === "failed")
      return root.sessionScaling.message
    if (root.sessionScaling.phase === "succeeded" && !root.sessionScaling.known)
      return root.sessionScaling.message
    if (root.sessionScaling.phase === "succeeded")
      return root.sessionScaling.message
    return "Monitor scaling uses tip-true SettingsSessionScaling.setScale → display-monitor-scale (omarchy-hyprland-monitor-scaling whitelist) through omarchy-fabric-session-apply. Allowed scales are 100%, 125%, 160%, 200%, 300%, and 400% on the focused Hyprland monitor. Soft leftover-attaches windows-native.3 to this tip-true Settings > Display scale plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.3. windows-native.3 stays prototype/pending. Never claim=present. Settings does not invent a display.provider scale durable writer. Fabric display.inspect stays separate. HDR, arrangement, and multi-monitor policy remain unavailable. Scaling alone is not modern display complete. session leftover recorded: Set display scaling leftover-attach only (not product CLOSED / not metal CLOSED / not claim=present). Cloud EXIT 0 is not metal leftover CLOSED."
  }

  readonly property string scalingBadge: {
    if (root.busy && root.sessionScaling.action === "set") return "APPLYING"
    if (root.busy) return "READING"
    if (root.sessionScaling.phase === "failed") return "FAILED"
    if (!root.sessionScaling.known) return "UNKNOWN"
    return "SESSION CONTROL"
  }

  readonly property string scalingTone: {
    if (root.sessionScaling.phase === "failed") return "danger"
    if (!root.sessionScaling.known) return "warning"
    if (root.busy) return "info"
    return "success"
  }

  ColumnLayout {
    id: scalingColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(14)
    spacing: Style.space(8)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Semantics.text(root.semanticProfile, "Display scaling")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.scalingBadge
        tone: root.scalingTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.scalingHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionScaling.known && root.sessionScaling.scale !== ""
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "Current scale") + ": " + SettingsModel.sessionScalingLabel(root.sessionScaling.scale)
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Repeater {
        model: root.scaleChoices
        delegate: Ui.Button {
          required property var modelData
          text: modelData.label
          semanticProfile: root.semanticProfile
          focusable: true
          bordered: true
          enabled: !root.busy && modelData.value !== root.sessionScaling.scale
          accessibleDescription: Semantics.text(root.semanticProfile, "Set focused Hyprland monitor scale to") + " " + modelData.label
          onClicked: root.applyScale(modelData.value)
        }
      }
    }

    Ui.Button {
      text: "Refresh display scaling"
      bordered: true
      focusable: true
      enabled: !root.busy
      semanticProfile: root.semanticProfile
      accessibleDescription: Semantics.text(root.semanticProfile, "Read focused Hyprland monitor scale through this session")
      onClicked: root.refreshStatus()
    }
  }

  Shared.SettingsSessionScaling {
    id: sessionHost
    onFinished: function(kind, ok, result) {
      root.sessionScaling = SettingsModel.sessionScalingFinished(root.sessionScaling, result)
    }
  }
}
