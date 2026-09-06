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
  implicitHeight: nightlightColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "Night light")

  property var sessionNightlight: SettingsModel.sessionNightlightIdle()

  readonly property bool busy: sessionHost.busy

  onPageActiveChanged: {
    if (pageActive) refreshStatus()
  }

  function refreshStatus() {
    if (root.busy) return
    if (!sessionHost.readStatus()) {
      root.sessionNightlight = SettingsModel.sessionNightlightFinished(root.sessionNightlight, {
        ok: false,
        code: "nightlight.busy",
        explanation: "The NightlightService session helper is busy."
      })
    }
  }

  function applyEnabled(enabled) {
    if (root.busy) return
    if (!sessionHost.setEnabled(enabled)) {
      root.sessionNightlight = SettingsModel.sessionNightlightFinished(root.sessionNightlight, {
        ok: false,
        code: "nightlight.busy",
        explanation: "The NightlightService session helper is busy."
      })
    }
  }

  readonly property string nightlightHonesty: {
    if (root.busy)
      return "Talking to NightlightService on this session, the same plane as Superbar > Quick Settings."
    if (root.sessionNightlight.phase === "failed")
      return root.sessionNightlight.message
    if (root.sessionNightlight.phase === "succeeded" && !root.sessionNightlight.known)
      return root.sessionNightlight.message
    if (root.sessionNightlight.phase === "succeeded")
      return root.sessionNightlight.message
    return "Night light uses tip-true SettingsSessionNightlight.setEnabled → NightlightService on this session, the same heritage plane as Superbar > Quick Settings. Settings hosts that control here. Soft leftover-attaches windows-native.34 to this tip-true Settings > Display night-light plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.34. windows-native.34 stays prototype/pending. Never claim=present. Fabric display.inspect stays separate. Settings does not invent a display.provider night-light durable writer. HDR, arrangement, and multi-monitor policy remain unavailable. Scaling is a sibling session leftover. Night light alone is not modern display complete. session leftover recorded: Enable night light leftover-attach only (not product CLOSED / not metal CLOSED / not claim=present)."
  }

  readonly property string nightlightBadge: {
    if (root.busy) return "READING"
    if (root.sessionNightlight.phase === "failed") return "FAILED"
    if (!root.sessionNightlight.known) return "UNKNOWN"
    if (root.sessionNightlight.enabled) return "ON"
    return "OFF"
  }

  readonly property string nightlightTone: {
    if (root.sessionNightlight.phase === "failed") return "danger"
    if (!root.sessionNightlight.known) return "warning"
    if (root.busy) return "info"
    if (root.sessionNightlight.enabled) return "success"
    return "info"
  }

  ColumnLayout {
    id: nightlightColumn
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
        text: Semantics.text(root.semanticProfile, "Night light")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.nightlightBadge
        tone: root.nightlightTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.nightlightHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionNightlight.known && root.sessionNightlight.temperature !== null
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "Temperature") + ": " + String(root.sessionNightlight.temperature) + "K"
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Ui.Toggle {
      id: nightlightToggle
      Layout.fillWidth: true
      semanticProfile: root.semanticProfile
      label: root.sessionNightlight.enabled ? "Night light is on" : "Night light is off"
      description: "Uses NightlightService on this session, the same plane as Quick Settings."
      checked: root.sessionNightlight.enabled === true
      enabled: !root.busy
      onClicked: root.applyEnabled(!nightlightToggle.checked)
    }

    Ui.Button {
      text: "Refresh night light"
      bordered: true
      focusable: true
      enabled: !root.busy
      semanticProfile: root.semanticProfile
      accessibleDescription: Semantics.text(root.semanticProfile, "Read NightlightService status on this session")
      onClicked: root.refreshStatus()
    }
  }

  Shared.SettingsSessionNightlight {
    id: sessionHost
    onFinished: function(kind, ok, result) {
      var parsed = SettingsModel.sessionNightlightFromIpc(
        kind,
        result && result.raw,
        result && result.exitCode,
        result && result.stderr
      )
      root.sessionNightlight = SettingsModel.sessionNightlightFinished(root.sessionNightlight, parsed)
    }
  }
}
