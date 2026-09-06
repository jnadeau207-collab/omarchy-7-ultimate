import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  signal finished(string kind, bool ok, string message)

  readonly property string helper: {
    var base = Quickshell.env("OMARCHY_PATH")
    return (base ? base : "/usr") + "/bin/omarchy-fabric-session-apply"
  }
  property bool busy: false
  property string pendingKind: ""
  property string pendingPayload: ""
  property string pendingTitle: ""

  function createArchive(record) {
    return root.run("archive", "files-archive-create", record)
  }

  function extractArchive(record) {
    return root.run("extract", "files-archive-extract", record)
  }

  function run(kind, action, plan) {
    if (root.busy || proc.running) return false
    if (!plan || typeof plan !== "object" || String(plan.action || "") === "unavailable") {
      root.finished(kind, false, plan && plan.reason ? String(plan.reason) : (kind === "extract" ? "That Extract action is unavailable." : "That Compress action is unavailable."))
      return false
    }
    var entries = []
    if (Array.isArray(plan.entries) && plan.entries.length > 0) {
      for (var i = 0; i < plan.entries.length; i++) {
        var item = plan.entries[i]
        if (!item || typeof item !== "object") continue
        entries.push({
          locationId: String(item.locationId || plan.locationId || ""),
          entryRelativePath: String(item.entryRelativePath || ""),
          entryId: String(item.entryId || "")
        })
      }
    } else {
      entries.push({
        locationId: String(plan.locationId || ""),
        entryRelativePath: String(plan.entryRelativePath || ""),
        entryId: String(plan.entryId || "")
      })
    }
    if (entries.length === 0) {
      root.finished(kind, false, "That item has no admitted Files identity.")
      return false
    }
    var locationId = String(plan.locationId || entries[0].locationId || "")
    if (kind === "extract" && entries.length !== 1) {
      root.finished(kind, false, "Extract one zip archive at a time through this session.")
      return false
    }
    if (locationId === "files.location.trash") {
      root.finished(kind, false, kind === "extract" ? "Trash entries cannot be extracted." : "Trash entries cannot be compressed.")
      return false
    }
    var payloadEntries = []
    for (var e = 0; e < entries.length; e++) {
      if (entries[e].entryRelativePath === "" || entries[e].entryId === "") {
        root.finished(kind, false, "That item has no admitted Files identity.")
        return false
      }
      if (entries[e].locationId === "files.location.trash") {
        root.finished(kind, false, kind === "extract" ? "Trash entries cannot be extracted." : "Trash entries cannot be compressed.")
        return false
      }
      payloadEntries.push({
        entryRelativePath: entries[e].entryRelativePath,
        entryId: entries[e].entryId
      })
    }
    var payload = {
      locationId: locationId,
      entries: payloadEntries
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
      var kind = root.pendingKind
      var raw = String(procStdout.text || "").trim()
      var ok = false
      var message = kind === "extract" ? "The session Extract helper failed." : "The session Compress helper failed."
      try {
        var parsed = JSON.parse(raw)
        ok = parsed && parsed.ok === true && exitCode === 0
        if (parsed && parsed.explanation) message = String(parsed.explanation)
        else if (ok && kind === "extract") {
          var folder = parsed.folderName ? String(parsed.folderName) : "the folder"
          message = "Extracted to " + folder + " through this session."
        } else if (ok) {
          var name = parsed.archiveName ? String(parsed.archiveName) : "the archive"
          message = "Created " + name + " through this session."
        }
      } catch (error) {
        ok = false
      }
      root.pendingKind = ""
      root.pendingTitle = ""
      root.busy = false
      root.finished(kind, ok, message)
    }
  }
}
