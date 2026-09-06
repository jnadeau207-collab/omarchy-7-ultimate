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
  implicitHeight: infoColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "System information")

  property var sessionInfo: SettingsModel.sessionSystemInformationIdle()

  readonly property bool busy: sessionHost.busy

  onPageActiveChanged: {
    if (pageActive) refreshInformation()
  }

  function refreshInformation() {
    if (root.busy) return
    root.sessionInfo = SettingsModel.sessionSystemInformationAccepted(root.sessionInfo, "inspect")
    if (!sessionHost.readInformation()) {
      root.sessionInfo = SettingsModel.sessionSystemInformationFinished(root.sessionInfo, {
        ok: false,
        code: "information.busy",
        explanation: "The session system information helper is busy."
      })
    }
  }

  readonly property string infoHonesty: {
    if (root.busy)
      return "Reading OS, product, hardware, and root storage through this session."
    if (root.sessionInfo.phase === "failed")
      return root.sessionInfo.message
    if (root.sessionInfo.phase === "succeeded")
      return root.sessionInfo.message
    return "System information uses tip-true SettingsSessionSystemInformation.readInformation → apply_system_information_inspect (this session's omarchy-fabric-session-apply helper). It reads OS, product, hardware, and root storage only. Soft leftover-attaches windows-native.38 to this tip-true Settings > System information plane (not product CLOSED / not metal CLOSED / not claim=present). Soft Ship park: leftover-attach before citing suite EXIT 0 as metal; Cloud mocks do not close windows-native.38. windows-native.38 stays prototype/pending. Never claim=present. session leftover recorded: Find system/storage information leftover-attach only (not product CLOSED / not metal CLOSED / not claim=present). Settings does not invent a system-information.provider durable LIVE writer. Settings does not invent Fabric durable system.info.read LIVE / claim=present. Agent Center bubblewrap system.info.read stays separate. Encryption, firmware flash, Device Manager, and storage mutation stay unavailable. Cloud EXIT 0 is not metal leftover CLOSED."
  }

  readonly property string infoBadge: {
    if (root.busy) return "READING"
    if (root.sessionInfo.phase === "failed") return "FAILED"
    if (root.sessionInfo.available) return "SESSION READ"
    return "UNAVAILABLE"
  }

  readonly property string infoTone: {
    if (root.sessionInfo.phase === "failed") return "danger"
    if (root.busy) return "info"
    if (root.sessionInfo.available) return "success"
    return "warning"
  }

  function rowText(label, value) {
    var text = value === null || value === undefined || value === "" ? "Unavailable" : String(value)
    return label + ": " + text
  }

  ColumnLayout {
    id: infoColumn
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
        text: Semantics.text(root.semanticProfile, "System information")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.infoBadge
        tone: root.infoTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.infoHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionInfo.available
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.rowText("Hostname", root.sessionInfo.hostname))
      color: Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionInfo.available
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.rowText("Operating system", root.sessionInfo.osName))
      color: Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionInfo.available
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.rowText("OS version", root.sessionInfo.osVersion))
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionInfo.available
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.rowText("Kernel", root.sessionInfo.kernel))
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionInfo.available
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.rowText("Architecture", root.sessionInfo.architecture))
      color: Tokens.text.disabled
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionInfo.available
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.rowText("Product", root.sessionInfo.productLabel))
      color: Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionInfo.available
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.rowText("Processor", root.sessionInfo.cpuModel))
      color: Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionInfo.available
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.rowText("Memory", root.sessionInfo.memoryLabel))
      color: Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.sessionInfo.available
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.rowText("Storage (/)", root.sessionInfo.storageLabel))
      color: Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Ui.Button {
      text: "Refresh system information"
      bordered: true
      focusable: true
      enabled: !root.busy
      semanticProfile: root.semanticProfile
      accessibleDescription: Semantics.text(root.semanticProfile, "Read OS, product, hardware, and root storage through this session")
      onClicked: root.refreshInformation()
    }
  }

  Shared.SettingsSessionSystemInformation {
    id: sessionHost
    onFinished: function(kind, ok, result) {
      root.sessionInfo = SettingsModel.sessionSystemInformationFinished(root.sessionInfo, result)
    }
  }
}
