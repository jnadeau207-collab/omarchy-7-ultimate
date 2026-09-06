import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  signal finished(string kind, bool ok, var result)

  readonly property string helper: {
    var base = Quickshell.env("OMARCHY_PATH")
    return (base ? base : "/usr") + "/bin/omarchy-shell"
  }
  property bool busy: false
  property string pendingKind: ""
  property bool followWithStatus: false

  function readStatus() {
    return root.run("status", false)
  }

  function setEnabled(enabled) {
    return root.run(enabled ? "enable" : "disable", true)
  }

  function run(method, refreshAfter) {
    if (root.busy || proc.running) return false
    root.busy = true
    root.pendingKind = method === "status" ? "status" : "set"
    root.followWithStatus = refreshAfter === true
    proc.command = [root.helper, "nightlight", method]
    proc.running = true
    return true
  }

  Process {
    id: proc
    stdout: StdioCollector {
      id: procStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: procStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var kind = root.pendingKind
      var payload = {
        raw: String(procStdout.text || ""),
        stderr: String(procStderr.text || ""),
        exitCode: exitCode
      }
      if (root.followWithStatus && exitCode === 0) {
        root.followWithStatus = false
        root.pendingKind = "status"
        proc.command = [root.helper, "nightlight", "status"]
        proc.running = true
        return
      }
      var ok = exitCode === 0
      root.followWithStatus = false
      root.pendingKind = ""
      root.busy = false
      root.finished(kind, ok, payload)
    }
  }
}
