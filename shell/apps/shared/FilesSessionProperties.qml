import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  signal finished(bool ok, var result)

  readonly property string helper: {
    var base = Quickshell.env("OMARCHY_PATH")
    return (base ? base : "/usr") + "/bin/omarchy-fabric-session-apply"
  }
  property bool busy: false
  property string pendingPayload: ""

  function readProperties(plan) {
    if (root.busy || proc.running) return false
    if (!plan || typeof plan !== "object" || String(plan.action || "") === "unavailable") {
      root.finished(false, {
        ok: false,
        code: "payload.invalid",
        explanation: plan && plan.reason ? String(plan.reason) : "That Properties action is unavailable."
      })
      return false
    }
    var locationId = String(plan.locationId || "")
    var entryRelativePath = String(plan.entryRelativePath || "")
    var entryId = String(plan.entryId || "")
    if (locationId === "files.location.trash") {
      root.finished(false, {
        ok: false,
        code: "payload.invalid",
        explanation: "Trash entries cannot show session Properties."
      })
      return false
    }
    if (locationId === "" || entryRelativePath === "" || entryId === "") {
      root.finished(false, {
        ok: false,
        code: "payload.invalid",
        explanation: "That item has no admitted Files identity."
      })
      return false
    }
    var payload = {
      locationId: locationId,
      entryRelativePath: entryRelativePath,
      entryId: entryId
    }
    root.busy = true
    root.pendingPayload = JSON.stringify(payload)
    proc.command = [root.helper, "files-entry-properties"]
    proc.running = true
    return true
  }

  Process {
    id: proc
    stdinEnabled: true
    stdout: StdioCollector {
      id: procStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: procStderr
      waitForEnd: true
    }
    onStarted: {
      write(root.pendingPayload)
      if (typeof closeStdin === "function") closeStdin()
      else stdinEnabled = false
      root.pendingPayload = ""
    }
    onExited: function(exitCode) {
      var raw = String(procStdout.text || "").trim()
      var parsed = {}
      try {
        parsed = JSON.parse(raw)
      } catch (error) {
        parsed = { ok: false, code: "command.failed", explanation: "The session Properties helper failed." }
      }
      if (typeof parsed !== "object" || parsed === null)
        parsed = { ok: false, code: "command.failed", explanation: "The session Properties helper failed." }
      var ok = parsed.ok === true && exitCode === 0
      parsed.ok = ok
      if (!parsed.explanation)
        parsed.explanation = ok ? "Read Properties through this session." : "The session Properties helper failed."
      root.busy = false
      root.finished(ok, parsed)
    }
  }
}
