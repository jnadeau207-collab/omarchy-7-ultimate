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

  function connectShare(plan) {
    if (root.busy || proc.running) return false
    if (!plan || typeof plan !== "object" || String(plan.action || "") === "unavailable") {
      root.finished(false, {
        ok: false,
        code: "payload.invalid",
        explanation: plan && plan.reason ? String(plan.reason) : "That Connect action is unavailable."
      })
      return false
    }
    var host = String(plan.host || "")
    var share = String(plan.share || "")
    if (host === "" || share === "") {
      root.finished(false, {
        ok: false,
        code: "payload.invalid",
        explanation: "Enter a host and share to connect through this session."
      })
      return false
    }
    root.busy = true
    root.pendingPayload = JSON.stringify({ host: host, share: share })
    proc.command = [root.helper, "sharing-smb-connect"]
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
        parsed = { ok: false, code: "command.failed", explanation: "The session Connect helper failed." }
      }
      if (typeof parsed !== "object" || parsed === null)
        parsed = { ok: false, code: "command.failed", explanation: "The session Connect helper failed." }
      var ok = parsed.ok === true && exitCode === 0
      parsed.ok = ok
      root.busy = false
      if (!parsed.explanation)
        parsed.explanation = ok ? "Connected the guest SMB share through this session." : "The session Connect helper failed."
      root.finished(ok, parsed)
    }
  }
}
