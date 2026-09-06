import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  signal finished(string kind, bool ok, var result)

  readonly property var allowedScales: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property string helper: {
    var base = Quickshell.env("OMARCHY_PATH")
    return (base ? base : "/usr") + "/bin/omarchy-fabric-session-apply"
  }
  property bool busy: false
  property string pendingKind: ""
  property string pendingPayload: ""
  property bool followWithStatus: false

  function readStatus() {
    return root.run("status", "display-monitor-scale-status", {}, false)
  }

  function setScale(scale) {
    var token = String(scale || "")
    if (root.allowedScales.indexOf(token) < 0) {
      root.finished("set", false, {
        ok: false,
        scale: "",
        known: false,
        code: "payload.invalid",
        explanation: "Scale must be one of 1, 1.25, 1.6, 2, 3, or 4."
      })
      return false
    }
    return root.run("set", "display-monitor-scale", { scale: token }, true)
  }

  function run(kind, action, payload, refreshAfter) {
    if (root.busy || proc.running) return false
    root.busy = true
    root.pendingKind = kind
    root.followWithStatus = refreshAfter === true
    root.pendingPayload = JSON.stringify(payload && typeof payload === "object" ? payload : {})
    proc.command = [root.helper, action]
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
        parsed = { ok: false, code: "command.failed", explanation: "The session monitor scaling helper failed." }
      }
      if (typeof parsed !== "object" || parsed === null)
        parsed = { ok: false, code: "command.failed", explanation: "The session monitor scaling helper failed." }
      var ok = parsed.ok === true && exitCode === 0
      parsed.ok = ok
      if (root.followWithStatus && ok) {
        root.followWithStatus = false
        root.pendingKind = "status"
        root.pendingPayload = "{}"
        stdinEnabled = true
        proc.command = [root.helper, "display-monitor-scale-status"]
        proc.running = true
        return
      }
      var kind = root.pendingKind
      root.followWithStatus = false
      root.pendingKind = ""
      root.busy = false
      root.finished(kind, ok, parsed)
    }
  }
}
