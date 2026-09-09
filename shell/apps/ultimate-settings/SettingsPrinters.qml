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
  implicitHeight: printersColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "Printers inventory and queue controls")

  property var sessionPrinters: SettingsModel.sessionPrintersIdle()
  readonly property var printerChoices: sessionPrinters.printers || []
  readonly property var defaultPrinter: {
    for (var i = 0; i < printerChoices.length; i++) {
      if (printerChoices[i] && printerChoices[i].default === true) return printerChoices[i]
    }
    return null
  }

  readonly property bool busy: sessionHost.busy

  onPageActiveChanged: {
    if (pageActive) refreshStatus()
  }

  function refreshStatus() {
    if (root.busy) return
    root.sessionPrinters = SettingsModel.sessionPrintersAccepted(root.sessionPrinters, "status")
    if (!sessionHost.readStatus()) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, {
        ok: false,
        code: "printers.busy",
        explanation: "The session Printers helper is busy."
      })
    }
  }

  function applyDefault(resourceId) {
    if (root.busy) return
    root.sessionPrinters = SettingsModel.sessionPrintersAccepted(root.sessionPrinters, "default")
    if (!SettingsModel.sessionPrintersCanSubmit(resourceId, root.printerChoices)) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, {
        ok: false,
        code: "payload.invalid",
        explanation: "Default printer must name one tip-true printer identity from this session inventory."
      })
      return
    }
    if (!sessionHost.setDefault(resourceId)) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, {
        ok: false,
        code: "printers.busy",
        explanation: "The session Printers helper is busy."
      })
    }
  }

  function applyPause(resourceId) {
    if (root.busy) return
    root.sessionPrinters = SettingsModel.sessionPrintersAccepted(root.sessionPrinters, "pause")
    if (!SettingsModel.sessionPrintersCanSubmit(resourceId, root.printerChoices)) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, {
        ok: false,
        code: "payload.invalid",
        explanation: "Pause must name one tip-true printer identity from this session inventory."
      })
      return
    }
    if (!sessionHost.pauseQueue(resourceId)) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, {
        ok: false,
        code: "printers.busy",
        explanation: "The session Printers helper is busy."
      })
    }
  }

  function applyResume(resourceId) {
    if (root.busy) return
    root.sessionPrinters = SettingsModel.sessionPrintersAccepted(root.sessionPrinters, "resume")
    if (!SettingsModel.sessionPrintersCanSubmit(resourceId, root.printerChoices)) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, {
        ok: false,
        code: "payload.invalid",
        explanation: "Resume must name one tip-true printer identity from this session inventory."
      })
      return
    }
    if (!sessionHost.resumeQueue(resourceId)) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, {
        ok: false,
        code: "printers.busy",
        explanation: "The session Printers helper is busy."
      })
    }
  }

  function applyTestPage(resourceId) {
    if (root.busy) return
    root.sessionPrinters = SettingsModel.sessionPrintersAccepted(root.sessionPrinters, "test-page")
    if (!SettingsModel.sessionPrintersCanSubmit(resourceId, root.printerChoices)) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, {
        ok: false,
        code: "payload.invalid",
        explanation: "Test page must name one tip-true printer identity from this session inventory."
      })
      return
    }
    if (!sessionHost.testPage(resourceId)) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, {
        ok: false,
        code: "printers.busy",
        explanation: "The session Printers helper is busy."
      })
    }
  }

  readonly property string printersHonesty: {
    if (root.busy && root.sessionPrinters.action === "default")
      return "Applying the default printer through this session."
    if (root.busy && root.sessionPrinters.action === "pause")
      return "Pausing the printer queue through this session."
    if (root.busy && root.sessionPrinters.action === "resume")
      return "Resuming the printer queue through this session."
    if (root.busy && root.sessionPrinters.action === "test-page")
      return "Submitting the printer test page through this session."
    if (root.busy)
      return "Reading printers through this session."
    if (root.sessionPrinters.phase === "failed")
      return root.sessionPrinters.message
    if (root.sessionPrinters.empty)
      return root.sessionPrinters.message || "No printers reported through this session. Add a printer remains OPEN leftover."
    if (root.sessionPrinters.phase === "succeeded")
      return root.sessionPrinters.message
    return "Printer inventory, set-default, pause, resume, and test-page use tip-true SettingsSessionPrinters.setDefault / pauseQueue / resumeQueue / testPage / readStatus → omarchy-fabric-session-apply printer-default-set / printer-pause / printer-resume / printer-test-page / printer-status with absolute /usr/bin/lpstat /usr/bin/lpoptions /usr/sbin/cupsdisable /usr/sbin/cupsenable /usr/bin/lp helpers and tip-true printer.* identities. Credentialed printer URIs are refused. session leftover recorded: soft leftover-attach ACC windows-native.32 via tip-true SettingsSessionPrinters.setDefault → printer-default-set (multi-verb session surface also hosts pause/resume/test-page/status); Settings Printers leftover-attach only (not product CLOSED / not metal CLOSED / not claim=present). Soft leftover-attach of catalog printers.manage leftover legacy-direct claim=partial visible Settings > Printers. Settings does not invent a printers.provider durable writer or Fabric SHELL LIVE queue mutation. Fabric printer.inspect and plan-only queue.plan stay separate. Network Add / driver wizard remains OPEN leftover and is not product-complete. Inventory or set-default alone is not Devices and Printers product-complete. Cloud EXIT 0 is not metal leftover CLOSED. windows-native.32 stays prototype/pending. Cloud mocks do not close windows-native.32. Administration > Printers and scanners remains the bounded printer.inspect host."
  }

  readonly property string printersBadge: {
    if (root.busy && (root.sessionPrinters.action === "default" || root.sessionPrinters.action === "pause" || root.sessionPrinters.action === "resume" || root.sessionPrinters.action === "test-page")) return "APPLYING"
    if (root.busy) return "READING"
    if (root.sessionPrinters.phase === "failed") return "FAILED"
    if (root.sessionPrinters.empty) return "NONE FOUND"
    if (!root.sessionPrinters.known) return "UNKNOWN"
    return "SESSION CONTROL"
  }

  readonly property string printersTone: {
    if (root.sessionPrinters.phase === "failed") return "danger"
    if (root.sessionPrinters.empty || !root.sessionPrinters.known) return "warning"
    if (root.busy) return "info"
    return "success"
  }

  function printerSubtitle(row) {
    var bits = []
    if (row.default === true) bits.push("default")
    if (row.accepting === true) bits.push("accepting")
    if (row.accepting === false) bits.push("paused")
    if (row.connection) bits.push(String(row.connection))
    if (row.endpoint) bits.push(String(row.endpoint))
    return bits.length ? bits.join(" · ") : "Printer"
  }

  ColumnLayout {
    id: printersColumn
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
        text: Semantics.text(root.semanticProfile, "Printers inventory and queue controls")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.printersBadge
        tone: root.printersTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.printersHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Text {
      visible: root.printerChoices.length > 0
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "Installed printers")
      color: Tokens.text.primary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
      Layout.fillWidth: true
    }

    ColumnLayout {
      visible: root.printerChoices.length > 0
      Layout.fillWidth: true
      spacing: Style.space(10)

      Repeater {
        model: root.printerChoices
        delegate: ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            text: Semantics.text(root.semanticProfile, modelData.label + " — " + root.printerSubtitle(modelData))
            color: Tokens.text.primary
            font.family: Tokens.typography.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Ui.Button {
              text: modelData.default === true ? "Default" : "Set default"
              bordered: true
              focusable: true
              enabled: !root.busy && modelData.default !== true
              semanticProfile: root.semanticProfile
              accessibleDescription: Semantics.text(root.semanticProfile, "Set default printer to") + " " + modelData.label
              onClicked: root.applyDefault(modelData.resourceId)
            }

            Ui.Button {
              text: "Pause"
              bordered: true
              focusable: true
              enabled: !root.busy && modelData.accepting !== false
              semanticProfile: root.semanticProfile
              accessibleDescription: Semantics.text(root.semanticProfile, "Pause printer queue for") + " " + modelData.label
              onClicked: root.applyPause(modelData.resourceId)
            }

            Ui.Button {
              text: "Resume"
              bordered: true
              focusable: true
              enabled: !root.busy && modelData.accepting !== true
              semanticProfile: root.semanticProfile
              accessibleDescription: Semantics.text(root.semanticProfile, "Resume printer queue for") + " " + modelData.label
              onClicked: root.applyResume(modelData.resourceId)
            }

            Ui.Button {
              text: "Test page"
              bordered: true
              focusable: true
              enabled: !root.busy
              semanticProfile: root.semanticProfile
              accessibleDescription: Semantics.text(root.semanticProfile, "Print test page on") + " " + modelData.label
              onClicked: root.applyTestPage(modelData.resourceId)
            }
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, "Add a printer stays OPEN leftover. Network discovery and driver wizard are not FixedArgv-safe on this plane.")
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Ui.Button {
      text: "Refresh printers"
      bordered: true
      focusable: true
      enabled: !root.busy
      semanticProfile: root.semanticProfile
      accessibleDescription: Semantics.text(root.semanticProfile, "Read printers through this session")
      onClicked: root.refreshStatus()
    }
  }

  Shared.SettingsSessionPrinters {
    id: sessionHost
    onFinished: function(kind, ok, result) {
      root.sessionPrinters = SettingsModel.sessionPrintersFinished(root.sessionPrinters, result)
    }
  }
}
