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

  function moveRecord(record) {
    return root.run("move", "files-entry-move", record)
  }

  function deleteRecord(record) {
    return root.run("delete", "files-entry-delete", record)
  }

  function run(kind, action, plan) {
    if (root.busy || proc.running) return false
    if (!plan || typeof plan !== "object" || String(plan.action || "") === "unavailable") {
      root.finished(kind, false, plan && plan.reason ? String(plan.reason) : "That Files action is unavailable.")
      return false
    }
    var payload = {
      locationId: String(plan.locationId || ""),
      entryRelativePath: String(plan.entryRelativePath || ""),
      entryId: String(plan.entryId || "")
    }
    if (payload.locationId === "" || payload.entryRelativePath === "" || payload.entryId === "") {
      root.finished(kind, false, "That item has no admitted Files identity.")
      return false
    }
    if (payload.locationId === "files.location.trash") {
      root.finished(kind, false, kind === "delete"
        ? "Trash entries cannot be permanently deleted. Empty Recycle Bin stays on Empty Bin."
        : "Trash entries cannot be moved.")
      return false
    }
    if (kind === "move") {
      payload.destinationLocationId = String(plan.destinationLocationId || "")
      payload.destinationParentRelativePath = String(plan.destinationParentRelativePath || "")
      payload.destinationName = String(plan.destinationName || "")
      if (payload.destinationLocationId === "" || payload.destinationName === "") {
        root.finished(kind, false, "That folder cannot receive a session move.")
        return false
      }
      if (payload.destinationLocationId === "files.location.trash") {
        root.finished(kind, false, "Trash is not a move destination.")
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
      var message = "The session Files helper failed."
      try {
        var parsed = JSON.parse(raw)
        ok = parsed && parsed.ok === true && exitCode === 0
        if (parsed && parsed.explanation) message = String(parsed.explanation)
        else if (ok && root.pendingKind === "move") {
          if (parsed.moved === false) message = (root.pendingTitle || "This item") + " is already in this folder."
          else message = "Moved " + (root.pendingTitle || "this item") + " through this session."
        } else if (ok && root.pendingKind === "delete") {
          message = "Permanently deleted " + (root.pendingTitle || "this item") + " through this session."
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
