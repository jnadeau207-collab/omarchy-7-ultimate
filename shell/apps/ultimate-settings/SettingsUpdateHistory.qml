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
  implicitHeight: historyColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "Update history")

  property var sessionHistory: SettingsModel.sessionUpdateHistoryIdle()

  readonly property bool busy: sessionHost.busy

  onPageActiveChanged: {
    if (pageActive) refreshHistory()
  }

  function refreshHistory() {
    if (root.busy) return
    if (!sessionHost.readHistory()) {
      root.sessionHistory = SettingsModel.sessionUpdateHistoryFinished(root.sessionHistory, {
        ok: false,
        explanation: "The session update helper is busy."
      })
    }
  }

  readonly property string historyHonesty: {
    if (root.busy)
      return "Reading this session's Omarchy update transcript."
    if (root.sessionHistory.phase === "failed")
      return root.sessionHistory.message
    if (root.sessionHistory.phase === "succeeded")
      return root.sessionHistory.message
    return "History reads this session's Omarchy update log through system-update-history. session leftover recorded: Inspect update history soft leftover-attaches windows-native.29 to this tip-true Settings > Update history plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.29. Elevated auth never enters Fabric. Fabric update.inspect and system.update stay inspect-only / not LIVE. Restart and reboot writers stay unavailable. windows-native.29 stays prototype/pending. Update is not present as product. Never claim=present."
  }

  readonly property string historyBadge: {
    if (root.busy) return "READING"
    if (root.sessionHistory.phase === "failed") return "FAILED"
    if (root.sessionHistory.empty) return "EMPTY"
    if (root.sessionHistory.failures && root.sessionHistory.failures.length > 0) return "FAILED"
    return "RECORDED"
  }

  readonly property string historyTone: {
    if (root.sessionHistory.phase === "failed") return "danger"
    if (root.sessionHistory.failures && root.sessionHistory.failures.length > 0) return "danger"
    if (root.sessionHistory.empty) return "info"
    if (root.busy) return "info"
    return "success"
  }

  ColumnLayout {
    id: historyColumn
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
        text: Semantics.text(root.semanticProfile, "Update history")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.historyBadge
        tone: root.historyTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.historyHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionHistory.empty && root.sessionHistory.phase === "succeeded"
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "No update transcript is available on this session.")
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Repeater {
      model: root.sessionHistory.entries
      delegate: ColumnLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          text: String(modelData.title || "Update transcript")
          color: Tokens.text.primary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          Layout.fillWidth: true
        }

        Text {
          visible: String(modelData.occurredAt || "") !== ""
          textFormat: Text.PlainText
          text: Semantics.text(root.semanticProfile, "Recorded") + ": " + String(modelData.occurredAt || "")
          color: Tokens.text.disabled
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          Layout.fillWidth: true
        }

        Text {
          textFormat: Text.PlainText
          text: String(modelData.detail || "")
          color: Tokens.text.secondary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          Layout.fillWidth: true
        }
      }
    }

    Repeater {
      model: root.sessionHistory.failures
      delegate: Text {
        required property var modelData
        textFormat: Text.PlainText
        text: String(modelData.title || modelData.code || "Update failure") + " — " + String(modelData.detail || "")
        color: Tokens.text.secondary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
        Layout.fillWidth: true
      }
    }

    Text {
      visible: root.sessionHistory.rebootRequired === true
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "A reboot marker is present. Settings does not offer a reboot writer.")
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionHistory.restartRequired && root.sessionHistory.restartRequired.length > 0
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "Restart markers are present. Settings does not offer restart writers.") +
        " " + (root.sessionHistory.restartRequired || []).join(", ")
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Ui.Button {
      text: "Refresh history"
      bordered: true
      focusable: true
      enabled: !root.busy
      semanticProfile: root.semanticProfile
      accessibleDescription: Semantics.text(root.semanticProfile, "Read this session's Omarchy update transcript")
      onClicked: root.refreshHistory()
    }
  }

  Shared.SettingsSessionUpdate {
    id: sessionHost
    onFinished: function(kind, ok, result) {
      if (kind !== "history") return
      root.sessionHistory = SettingsModel.sessionUpdateHistoryFinished(root.sessionHistory, result)
    }
  }
}
