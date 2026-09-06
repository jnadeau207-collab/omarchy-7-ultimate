import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  signal finished(string kind, bool ok, string message)

  readonly property string helper: {
    var base = Quickshell.env("OMARCHY_PATH")
    return base ? base + "/bin/omarchy-fabric-session-apply" : "omarchy-fabric-session-apply"
  }
  property bool busy: false
  property string pendingKind: ""
  property string pendingPayload: ""

  function installRecord(record) {
    return root.run("install", "software-install", record)
  }

  function removeRecord(record) {
    return root.run("remove", "software-remove", record)
  }

  function run(kind, action, record) {
    if (root.busy || proc.running) return false
    var packageId = record && record.id ? String(record.id) : ""
    if (packageId === "") {
      root.finished(kind, false, "This record has no admitted package identity.")
      return false
    }
    root.busy = true
    root.pendingKind = kind
    root.pendingPayload = JSON.stringify({ packageId: packageId })
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
      var ok = false
      var message = "The session package helper failed."
      try {
        var parsed = JSON.parse(raw)
        ok = parsed && parsed.ok === true && exitCode === 0
        if (parsed && parsed.explanation) message = String(parsed.explanation)
      } catch (error) {
        ok = false
      }
      var kind = root.pendingKind
      root.pendingKind = ""
      root.busy = false
      root.finished(kind, ok, message)
    }
  }
}
