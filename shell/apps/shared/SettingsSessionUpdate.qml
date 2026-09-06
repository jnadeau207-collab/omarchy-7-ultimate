import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  signal finished(string kind, bool ok, var result)

  readonly property string helper: {
    var base = Quickshell.env("OMARCHY_PATH")
    return base ? base + "/bin/omarchy-fabric-session-apply" : "omarchy-fabric-session-apply"
  }
  property bool busy: false
  property string pendingKind: ""
  property string pendingPayload: ""

  function checkStatus() {
    return root.run("check", "system-update-status", {})
  }

  function applyUpdate(channel) {
    return root.run("apply", "system-update", { channel: String(channel || "") })
  }

  function readHistory() {
    return root.run("history", "system-update-history", {})
  }

  function run(kind, action, payload) {
    if (root.busy || proc.running) return false
    root.busy = true
    root.pendingKind = kind
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
        parsed = { ok: false, code: "command.failed", explanation: "The session update helper failed." }
      }
      if (typeof parsed !== "object" || parsed === null)
        parsed = { ok: false, code: "command.failed", explanation: "The session update helper failed." }
      var ok = parsed.ok === true && exitCode === 0
      parsed.ok = ok
      var kind = root.pendingKind
      root.pendingKind = ""
      root.busy = false
      root.finished(kind, ok, parsed)
    }
  }
}
