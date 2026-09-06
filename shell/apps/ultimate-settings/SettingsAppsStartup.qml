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

  signal changed(string desktopId, bool enabled)
  signal changeFailed(string code, string message)

  radius: Tokens.radius.medium
  color: Tokens.surface.raised
  border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
  border.width: Tokens.accessibility.highContrast ? 2 : 1
  implicitHeight: startupColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "Startup applications")

  property var sessionStartup: SettingsModel.sessionStartupIdle()

  readonly property bool busy: sessionHost.busy
  readonly property var startupRows: sessionStartup.entries || []

  onPageActiveChanged: {
    if (pageActive) refreshEntries()
  }

  function refreshEntries() {
    if (root.busy) return
    root.sessionStartup = SettingsModel.sessionStartupAccepted(root.sessionStartup, "list")
    if (!sessionHost.listEntries()) {
      root.sessionStartup = SettingsModel.sessionStartupFinished(root.sessionStartup, {
        ok: false,
        code: "startup.busy",
        explanation: "The session startup helper is busy."
      })
    }
  }

  function applyEnabled(desktopId, enabled) {
    if (root.busy) return
    var row = { desktopId: desktopId, enabled: enabled, controllable: true }
    if (!SettingsModel.sessionStartupCanSubmit(row)) return
    root.sessionStartup = SettingsModel.sessionStartupAccepted(root.sessionStartup, "set")
    if (!sessionHost.setEnabled(desktopId, enabled)) {
      root.sessionStartup = SettingsModel.sessionStartupFinished(root.sessionStartup, {
        ok: false,
        code: "startup.busy",
        explanation: "The session startup helper is busy."
      })
    }
  }

  readonly property string startupHonesty: {
    if (root.busy && root.sessionStartup.action === "set")
      return "Changing XDG autostart through this session."
    if (root.busy)
      return "Reading XDG autostart through this session."
    if (root.sessionStartup.phase === "failed")
      return root.sessionStartup.message
    if (root.sessionStartup.unavailable)
      return root.sessionStartup.message
    if (root.sessionStartup.empty)
      return root.sessionStartup.message || "No XDG autostart applications were found for this session. Hyprland session hooks stay outside this list."
    return "These entries launch at sign-in through this session's XDG autostart helper. Enable or disable writes ~/.config/autostart. System entries use a user override. Fabric defaults.inspect stays readable. Settings does not invent a Fabric apps.startup.disable durable writer. Settings does not invent Task Manager present. Hyprland session hooks stay outside this list."
  }

  readonly property string startupBadge: {
    if (root.busy && root.sessionStartup.action === "set") return "APPLYING"
    if (root.busy) return "READING"
    if (root.sessionStartup.phase === "failed" || root.sessionStartup.unavailable) return "UNAVAILABLE"
    if (root.sessionStartup.empty) return "NONE FOUND"
    return "SESSION CONTROL"
  }

  readonly property string startupTone: {
    if (root.sessionStartup.phase === "failed" || root.sessionStartup.unavailable) return "warning"
    if (root.busy) return "info"
    if (root.sessionStartup.empty) return "info"
    return "success"
  }

  ColumnLayout {
    id: startupColumn
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
        text: Semantics.text(root.semanticProfile, "Startup applications")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.startupBadge
        tone: root.startupTone
        semanticProfile: root.semanticProfile
      }
    }

    Repeater {
      model: root.startupRows
      delegate: RowLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: modelData.label
          color: Tokens.text.primary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.body
          Layout.fillWidth: true
        }

        Text {
          textFormat: Text.PlainText
          text: modelData.startupSource === "user" ? "Your autostart" : "System autostart"
          color: Tokens.text.secondary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.bodySmall
        }

        Ui.Toggle {
          semanticProfile: root.semanticProfile
          label: modelData.startupEnabled ? "Enabled at sign-in" : "Disabled at sign-in"
          checked: modelData.startupEnabled === true
          enabled: !root.busy && modelData.controllable === true
          onClicked: root.applyEnabled(modelData.desktopId, !checked)
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.startupHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Ui.Button {
      text: "Refresh startup applications"
      bordered: true
      focusable: true
      enabled: !root.busy
      semanticProfile: root.semanticProfile
      accessibleDescription: Semantics.text(root.semanticProfile, "Read XDG autostart through this session")
      onClicked: root.refreshEntries()
    }
  }

  Shared.SettingsSessionStartup {
    id: sessionHost
    onFinished: function(kind, ok, result) {
      root.sessionStartup = SettingsModel.sessionStartupFinished(root.sessionStartup, result)
      if (ok && kind === "set") {
        root.changed(String(result && result.desktopId || ""), result && result.enabled === true)
        return
      }
      if (!ok)
        root.changeFailed(String(result && result.code || "command.failed"), root.sessionStartup.message)
    }
  }
}
