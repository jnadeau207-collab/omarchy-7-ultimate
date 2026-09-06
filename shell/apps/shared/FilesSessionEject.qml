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

  function ejectDevice(plan) {
    if (root.busy || proc.running) return false
    if (!plan || typeof plan !== "object" || String(plan.action || "") === "unavailable") {
      root.finished(false, {
        ok: false,
        code: "payload.invalid",
        explanation: plan && plan.reason ? String(plan.reason) : "That Eject action is unavailable."
      })
      return false
    }
    var mountId = String(plan.mountId || "")
    if (mountId === "") {
      root.finished(false, {
        ok: false,
        code: "payload.invalid",
        explanation: "That device has no admitted Files mount identity."
      })
      return false
    }
    var payload = { mountId: mountId }
    root.busy = true
    root.pendingPayload = JSON.stringify(payload)
    proc.command = [root.helper, "storage-removable-eject"]
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
        parsed = { ok: false, code: "command.failed", explanation: "The session Eject helper failed." }
      }
      if (typeof parsed !== "object" || parsed === null)
        parsed = { ok: false, code: "command.failed", explanation: "The session Eject helper failed." }
      var ok = parsed.ok === true && exitCode === 0
      parsed.ok = ok
      if (!parsed.explanation)
        parsed.explanation = ok ? "Ejected the removable device through this session." : "The session Eject helper failed."
      root.busy = false
      root.finished(ok, parsed)
    }
  }
}
