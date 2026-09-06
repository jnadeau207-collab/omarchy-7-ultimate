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

  function copyPayload(payload) {
    if (!payload) {
      root.finished("copy", false, "That item cannot be copied to the clipboard.")
      return false
    }
    return root.run("copy", "files-clipboard-copy", payload)
  }

  function pastePayload(payload) {
    if (!payload) {
      root.finished("paste", false, "This folder cannot receive a paste.")
      return false
    }
    return root.run("paste", "files-clipboard-paste", payload)
  }

  function run(kind, action, payload) {
    if (root.busy || proc.running) return false
    root.busy = true
    root.pendingKind = kind
    root.pendingPayload = JSON.stringify(payload)
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
      var message = "The clipboard helper failed."
      try {
        var parsed = JSON.parse(raw)
        ok = parsed && parsed.ok === true && exitCode === 0
        if (ok && root.pendingKind === "copy") message = "Copied to the clipboard."
        else if (ok && root.pendingKind === "paste") {
          var count = parsed.count
          message = count === 1 ? "Pasted 1 item." : "Pasted " + String(count) + " items."
        } else if (parsed && parsed.explanation) message = String(parsed.explanation)
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
