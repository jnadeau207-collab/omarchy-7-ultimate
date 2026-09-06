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

  signal applied(string channel)
  signal applyFailed(string code, string message)

  radius: Tokens.radius.medium
  color: Tokens.surface.raised
  border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
  border.width: Tokens.accessibility.highContrast ? 2 : 1
  implicitHeight: updateColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "System updates")

  property var sessionUpdate: SettingsModel.sessionUpdateIdle()
  property string probedChannel: ""
  property bool available: false
  property bool lockHeld: false
  property bool diskOk: true
  property var availableLines: []

  readonly property bool busy: sessionHost.busy
  readonly property var applyPlan: SettingsModel.sessionUpdatePlan("apply", {
    channel: root.probedChannel,
    available: root.available,
    lockHeld: root.lockHeld,
    diskOk: root.diskOk
  })
  readonly property bool canApply: SettingsModel.sessionUpdateCanSubmit(root.applyPlan) && !root.busy

  onPageActiveChanged: {
    if (pageActive) refreshStatus()
  }

  function refreshStatus() {
    if (root.busy) return
    var plan = SettingsModel.sessionUpdatePlan("check")
    root.sessionUpdate = SettingsModel.sessionUpdateAccepted(root.sessionUpdate, plan)
    if (!sessionHost.checkStatus()) {
      root.sessionUpdate = SettingsModel.sessionUpdateFinished(root.sessionUpdate, {
        ok: false,
        explanation: "The session update helper is busy."
      })
    }
  }

  function installUpdates() {
    if (!root.canApply) return
    root.sessionUpdate = SettingsModel.sessionUpdateAccepted(root.sessionUpdate, root.applyPlan)
    if (!sessionHost.applyUpdate(root.applyPlan.channel)) {
      root.sessionUpdate = SettingsModel.sessionUpdateFinished(root.sessionUpdate, {
        ok: false,
        explanation: "The session update helper is busy."
      })
    }
  }

  readonly property string updateHonesty: {
    if (root.busy && root.sessionUpdate.action === "apply")
      return "Installing system updates through this session."
    if (root.busy && root.sessionUpdate.action === "check")
      return "Checking this machine's update channel and available updates."
    if (root.sessionUpdate.phase === "failed")
      return root.sessionUpdate.message
    if (root.sessionUpdate.phase === "succeeded" && root.sessionUpdate.action === "apply")
      return root.sessionUpdate.message
    if (root.lockHeld)
      return "An Omarchy update is already running."
    if (!root.diskOk)
      return "This machine does not have enough free disk space to update safely."
    if (root.probedChannel !== "" && !root.available)
      return "No system updates are available on " + root.probedChannel + "."
    if (root.probedChannel !== "" && root.available)
      return "Updates are available on " + root.probedChannel + ". Apply uses this session's update helper."
    return "Apply uses this session's update helper. Elevated auth never enters Fabric. Fabric system.update stays inspect-only / not LIVE. Restart and reboot writers stay unavailable. Update history is a session log read soft leftover-attached to windows-native.29 (prototype/pending; not product CLOSED / not metal CLOSED / not claim=present). Update is not present as product."
  }

  readonly property string updateBadge: {
    if (root.busy && root.sessionUpdate.action === "apply") return "APPLYING"
    if (root.busy && root.sessionUpdate.action === "check") return "CHECKING"
    if (root.sessionUpdate.phase === "failed") return "FAILED"
    if (root.lockHeld) return "LOCK HELD"
    if (!root.diskOk) return "DISK SPACE"
    if (root.probedChannel !== "" && !root.available) return "UP TO DATE"
    if (root.canApply) return "LIVE CONTROL"
    return "CHECK REQUIRED"
  }

  readonly property string updateTone: {
    if (root.sessionUpdate.phase === "failed") return "danger"
    if (root.lockHeld || !root.diskOk) return "warning"
    if (root.busy) return "info"
    if (root.canApply) return "success"
    return "info"
  }

  ColumnLayout {
    id: updateColumn
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
        text: Semantics.text(root.semanticProfile, "System updates")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.updateBadge
        tone: root.updateTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.updateHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.probedChannel !== ""
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "Channel") + ": " + root.probedChannel
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Repeater {
      model: root.availableLines
      delegate: Text {
        required property string modelData
        textFormat: Text.PlainText
        text: modelData
        color: Tokens.text.secondary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
        Layout.fillWidth: true
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Ui.Button {
        text: "Check for updates"
        bordered: true
        focusable: true
        enabled: !root.busy
        semanticProfile: root.semanticProfile
        accessibleDescription: Semantics.text(root.semanticProfile, "Check this session's update channel and available updates")
        onClicked: root.refreshStatus()
      }

      Ui.Button {
        text: "Install updates"
        bordered: true
        focusable: true
        enabled: root.canApply
        semanticProfile: root.semanticProfile
        accessibleDescription: Semantics.text(root.semanticProfile, "Install system updates through this session's update helper")
        onClicked: root.installUpdates()
      }
    }
  }

  Shared.SettingsSessionUpdate {
    id: sessionHost
    onFinished: function(kind, ok, result) {
      root.sessionUpdate = SettingsModel.sessionUpdateFinished(root.sessionUpdate, result)
      if (ok) {
        if (result && result.channel) root.probedChannel = String(result.channel)
        if (kind === "check") {
          root.available = result && result.available === true
          root.lockHeld = result && result.lockHeld === true
          root.diskOk = !(result && result.diskOk === false)
          root.availableLines = result && result.availableLines ? result.availableLines : []
        }
        if (kind === "apply") {
          root.available = false
          root.availableLines = []
          root.applied(root.probedChannel)
        }
        return
      }
      if (result && result.channel) root.probedChannel = String(result.channel)
      if (result && result.code === "update.lock-held") root.lockHeld = true
      if (result && result.code === "update.disk-space") root.diskOk = false
      if (result && result.code === "update.none-available") {
        root.available = false
        root.availableLines = []
      }
      root.applyFailed(String(result && result.code || "command.failed"), root.sessionUpdate.message)
    }
  }
}
