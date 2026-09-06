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
  implicitHeight: soundColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "Output mute and default device")

  property var sessionSound: SettingsModel.sessionSoundIdle()
  readonly property var sinkChoices: sessionSound.sinks || []
  readonly property var defaultSink: {
    for (var i = 0; i < sinkChoices.length; i++) {
      if (sinkChoices[i] && sinkChoices[i].default === true) return sinkChoices[i]
    }
    return null
  }

  readonly property bool busy: sessionHost.busy

  onPageActiveChanged: {
    if (pageActive) refreshStatus()
  }

  function refreshStatus() {
    if (root.busy) return
    root.sessionSound = SettingsModel.sessionSoundAccepted(root.sessionSound, "status")
    if (!sessionHost.readStatus()) {
      root.sessionSound = SettingsModel.sessionSoundFinished(root.sessionSound, {
        ok: false,
        code: "sound.busy",
        explanation: "The session Sound helper is busy."
      })
    }
  }

  function applyMuted(muted) {
    if (root.busy) return
    var sink = root.defaultSink
    if (!sink || !sink.resourceId) {
      root.sessionSound = SettingsModel.sessionSoundFinished(root.sessionSound, {
        ok: false,
        code: "payload.invalid",
        explanation: "Mute must name one tip-true audio.sink identity with a boolean muted flag."
      })
      return
    }
    root.sessionSound = SettingsModel.sessionSoundAccepted(root.sessionSound, "mute")
    if (!sessionHost.setMuted(sink.resourceId, muted === true)) {
      root.sessionSound = SettingsModel.sessionSoundFinished(root.sessionSound, {
        ok: false,
        code: "sound.busy",
        explanation: "The session Sound helper is busy."
      })
    }
  }

  function applyDefault(resourceId) {
    if (root.busy) return
    root.sessionSound = SettingsModel.sessionSoundAccepted(root.sessionSound, "default")
    if (!SettingsModel.sessionSoundCanSubmit(resourceId, root.sinkChoices)) {
      root.sessionSound = SettingsModel.sessionSoundFinished(root.sessionSound, {
        ok: false,
        code: "payload.invalid",
        explanation: "Default output must name one tip-true audio.sink identity from this session inventory."
      })
      return
    }
    if (!sessionHost.setDefault(resourceId)) {
      root.sessionSound = SettingsModel.sessionSoundFinished(root.sessionSound, {
        ok: false,
        code: "sound.busy",
        explanation: "The session Sound helper is busy."
      })
    }
  }

  readonly property string soundHonesty: {
    if (root.busy && root.sessionSound.action === "mute")
      return "Applying audio output mute through this session."
    if (root.busy && root.sessionSound.action === "default")
      return "Applying the default audio output through this session."
    if (root.busy)
      return "Reading audio outputs through this session."
    if (root.sessionSound.phase === "failed")
      return root.sessionSound.message
    if (root.sessionSound.empty)
      return root.sessionSound.message || "No audio outputs reported through this session. Port changes and troubleshoot remain unavailable."
    if (root.sessionSound.phase === "succeeded")
      return root.sessionSound.message
    return "Output mute and default sink use this session's /usr/bin/pactl helper through omarchy-fabric-session-apply with tip-true audio.sink identities. session leftover recorded: Settings Sound mute and default output session-UI leftover only (not product CLOSED / not metal CLOSED / not claim=present). Soft leftover-attach of catalog audio.output.manage leftover legacy-direct. Settings does not invent an audio.provider mute or default-sink durable writer. Fabric audio.inspect and durable volume stay separate. Port changes and audio troubleshoot remain unavailable. Mute or default alone is not Sound product-complete. Cloud EXIT 0 is not metal leftover CLOSED. windows-native.6 stays pending. Superbar / Quick Settings Sound panel remains."
  }

  readonly property string soundBadge: {
    if (root.busy && (root.sessionSound.action === "mute" || root.sessionSound.action === "default")) return "APPLYING"
    if (root.busy) return "READING"
    if (root.sessionSound.phase === "failed") return "FAILED"
    if (root.sessionSound.empty) return "NONE FOUND"
    if (!root.sessionSound.known) return "UNKNOWN"
    return "SESSION CONTROL"
  }

  readonly property string soundTone: {
    if (root.sessionSound.phase === "failed") return "danger"
    if (root.sessionSound.empty || !root.sessionSound.known) return "warning"
    if (root.busy) return "info"
    return "success"
  }

  ColumnLayout {
    id: soundColumn
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
        text: Semantics.text(root.semanticProfile, "Output mute and default device")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.soundBadge
        tone: root.soundTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.soundHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Ui.Toggle {
      id: muteToggle
      visible: root.defaultSink !== null
      Layout.fillWidth: true
      semanticProfile: root.semanticProfile
      label: root.defaultSink && root.defaultSink.muted ? "Output is muted" : "Output is unmuted"
      description: "Toggles mute on the current default sink through this session."
      checked: root.defaultSink ? root.defaultSink.muted === true : false
      enabled: !root.busy && root.defaultSink !== null
      onClicked: root.applyMuted(!muteToggle.checked)
    }

    Text {
      visible: root.sinkChoices.length > 0
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "Default output")
      color: Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
      Layout.fillWidth: true
    }

    ColumnLayout {
      visible: root.sinkChoices.length > 0
      Layout.fillWidth: true
      spacing: Style.space(6)

      Repeater {
        model: root.sinkChoices
        delegate: Ui.Button {
          required property var modelData
          Layout.fillWidth: true
          text: modelData.label + (modelData.default ? " (default)" : "")
          semanticProfile: root.semanticProfile
          focusable: true
          bordered: true
          enabled: !root.busy && modelData.default !== true
          accessibleDescription: Semantics.text(root.semanticProfile, "Set default audio output to") + " " + modelData.label
          onClicked: root.applyDefault(modelData.resourceId)
        }
      }
    }

    Ui.Button {
      text: "Refresh sound outputs"
      bordered: true
      focusable: true
      enabled: !root.busy
      semanticProfile: root.semanticProfile
      accessibleDescription: Semantics.text(root.semanticProfile, "Read audio outputs through this session")
      onClicked: root.refreshStatus()
    }
  }

  Shared.SettingsSessionSound {
    id: sessionHost
    onFinished: function(kind, ok, result) {
      root.sessionSound = SettingsModel.sessionSoundFinished(root.sessionSound, result)
    }
  }
}
