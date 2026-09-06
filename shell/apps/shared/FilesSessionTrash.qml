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
  property string pendingTitle: ""

  function trashRecord(record) {
    return root.run("trash", "files-entry-trash", record)
  }

  function restoreRecord(record) {
    return root.run("restore", "files-trash-restore", record)
  }

  function emptyBin(record) {
    return root.run("empty", "files-trash-manage", record || { action: "empty", locationId: "files.location.trash", parentRelativePath: "" })
  }

  function run(kind, action, plan) {
    if (root.busy || proc.running) return false
    if (!plan || typeof plan !== "object" || String(plan.action || "") === "unavailable") {
      root.finished(kind, false, plan && plan.reason ? String(plan.reason) : "That Recycle action is unavailable.")
      return false
    }
    var payload = {}
    if (kind === "empty") {
      payload.locationId = String(plan.locationId || "files.location.trash")
      payload.parentRelativePath = String(plan.parentRelativePath || "")
    } else {
      payload.locationId = String(plan.locationId || "")
      payload.entryRelativePath = String(plan.entryRelativePath || "")
      payload.entryId = String(plan.entryId || "")
      if (payload.locationId === "" || payload.entryRelativePath === "" || payload.entryId === "") {
        root.finished(kind, false, "That item has no admitted Files identity.")
        return false
      }
    }
    root.busy = true
    root.pendingKind = kind
    root.pendingTitle = String(plan.title || "")
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
      var message = "The session recycle helper failed."
      try {
        var parsed = JSON.parse(raw)
        ok = parsed && parsed.ok === true && exitCode === 0
        if (parsed && parsed.explanation) message = String(parsed.explanation)
        else if (ok && root.pendingKind === "trash") message = "Moved " + (root.pendingTitle || "this item") + " to the Recycle Bin."
        else if (ok && root.pendingKind === "restore") message = "Restored " + (root.pendingTitle || "this item") + "."
        else if (ok && root.pendingKind === "empty") {
          var count = parsed.count
          if (parsed.emptied === false || count === 0) message = "The Recycle Bin is already empty."
          else message = count === 1 ? "Emptied 1 item from the Recycle Bin." : "Emptied " + String(count) + " items from the Recycle Bin."
        }
      } catch (error) {
        ok = false
      }
      var kind = root.pendingKind
      root.pendingKind = ""
      root.pendingTitle = ""
      root.busy = false
      root.finished(kind, ok, message)
    }
  }
}
