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
  implicitHeight: layoutColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "Keyboard layout")

  property var sessionLayout: SettingsModel.sessionKeyboardLayoutIdle()
  readonly property var layoutChoices: sessionLayout.layouts || []

  readonly property bool busy: sessionHost.busy

  onPageActiveChanged: {
    if (pageActive) refreshStatus()
  }

  function refreshStatus() {
    if (root.busy) return
    root.sessionLayout = SettingsModel.sessionKeyboardLayoutAccepted(root.sessionLayout, "status")
    if (!sessionHost.readStatus()) {
      root.sessionLayout = SettingsModel.sessionKeyboardLayoutFinished(root.sessionLayout, {
        ok: false,
        code: "layout.busy",
        explanation: "The session keyboard layout helper is busy."
      })
    }
  }

  function applyLayout(layout) {
    if (root.busy) return
    root.sessionLayout = SettingsModel.sessionKeyboardLayoutAccepted(root.sessionLayout, "set")
    if (!SettingsModel.sessionKeyboardLayoutCanSubmit(layout, root.layoutChoices)) {
      root.sessionLayout = SettingsModel.sessionKeyboardLayoutFinished(root.sessionLayout, {
        ok: false,
        code: "payload.invalid",
        explanation: "Layout must be one of the configured keyboard layouts."
      })
      return
    }
    if (!sessionHost.setLayout(layout)) {
      root.sessionLayout = SettingsModel.sessionKeyboardLayoutFinished(root.sessionLayout, {
        ok: false,
        code: "layout.busy",
        explanation: "The session keyboard layout helper is busy."
      })
    }
  }

  readonly property string layoutHonesty: {
    if (root.busy && root.sessionLayout.action === "set")
      return "Applying typed Hyprland keyboard layout through this session."
    if (root.busy)
      return "Reading typed Hyprland keyboard layout through this session."
    if (root.sessionLayout.phase === "failed")
      return root.sessionLayout.message
    if (root.sessionLayout.empty)
      return root.sessionLayout.message || "No typed keyboard reported configured layouts through this session. Pointer, repeat rate, and full locale stay unavailable."
    if (root.sessionLayout.known && !root.sessionLayout.switchable)
      return "This session's typed keyboard reports one configured layout. Settings shows that layout and does not invent a second layout or a locale/region writer."
    if (root.sessionLayout.phase === "succeeded")
      return root.sessionLayout.message
    return "Keyboard layout uses this session's /usr/bin/hyprctl helper through omarchy-fabric-session-apply. Only configured layout identities are accepted. session leftover recorded: Settings Input keyboard layout session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present). Settings does not invent an input.provider keyboard-layout durable writer. Fabric input.inspect stays separate. Pointer, repeat rate, IME, and full locale/region remain unavailable. Layout alone is not locale complete. Cloud EXIT 0 is not metal leftover CLOSED. windows-native.33 stays pending."
  }

  readonly property string layoutBadge: {
    if (root.busy && root.sessionLayout.action === "set") return "APPLYING"
    if (root.busy) return "READING"
    if (root.sessionLayout.phase === "failed") return "FAILED"
    if (root.sessionLayout.empty) return "NONE FOUND"
    if (!root.sessionLayout.known) return "UNKNOWN"
    if (!root.sessionLayout.switchable) return "SINGLE LAYOUT"
    return "SESSION CONTROL"
  }

  readonly property string layoutTone: {
    if (root.sessionLayout.phase === "failed") return "danger"
    if (root.sessionLayout.empty || !root.sessionLayout.known) return "warning"
    if (root.busy) return "info"
    return "success"
  }

  ColumnLayout {
    id: layoutColumn
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
        text: Semantics.text(root.semanticProfile, "Keyboard layout")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.layoutBadge
        tone: root.layoutTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.layoutHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionLayout.known && root.sessionLayout.layout !== ""
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "Current layout") + ": " + root.sessionLayout.layout
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    RowLayout {
      visible: root.sessionLayout.switchable
      Layout.fillWidth: true
      spacing: Style.space(8)

      Repeater {
        model: root.layoutChoices
        delegate: Ui.Button {
          required property string modelData
          text: modelData
          semanticProfile: root.semanticProfile
          focusable: true
          bordered: true
          enabled: !root.busy && modelData !== root.sessionLayout.layout
          accessibleDescription: Semantics.text(root.semanticProfile, "Set typed Hyprland keyboard layout to") + " " + modelData
          onClicked: root.applyLayout(modelData)
        }
      }
    }

    Ui.Button {
      text: "Refresh keyboard layout"
      bordered: true
      focusable: true
      enabled: !root.busy
      semanticProfile: root.semanticProfile
      accessibleDescription: Semantics.text(root.semanticProfile, "Read typed Hyprland keyboard layout through this session")
      onClicked: root.refreshStatus()
    }
  }

  Shared.SettingsSessionKeyboardLayout {
    id: sessionHost
    onFinished: function(kind, ok, result) {
      root.sessionLayout = SettingsModel.sessionKeyboardLayoutFinished(root.sessionLayout, result)
    }
  }
}
