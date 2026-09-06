import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  signal finished(bool ok, var result)
  signal listed(var volumes)

  readonly property string helper: {
    var base = Quickshell.env("OMARCHY_PATH")
    return (base ? base : "/usr") + "/bin/omarchy-fabric-session-apply"
  }
  property bool busy: false
  property string pendingKind: ""
  property string pendingPayload: ""

  function listVolumes() {
    if (root.busy || proc.running) return false
    root.busy = true
    root.pendingKind = "list"
    root.pendingPayload = "{}"
    proc.command = [root.helper, "storage-removable-list"]
    proc.running = true
    return true
  }

  function mountVolume(plan) {
    if (root.busy || proc.running) return false
    if (!plan || typeof plan !== "object" || String(plan.action || "") === "unavailable") {
      root.finished(false, {
        ok: false,
        code: "payload.invalid",
        explanation: plan && plan.reason ? String(plan.reason) : "That Mount action is unavailable."
      })
      return false
    }
    var volumeId = String(plan.volumeId || "")
    if (volumeId === "") {
      root.finished(false, {
        ok: false,
        code: "payload.invalid",
        explanation: "That volume has no admitted Files volume identity."
      })
      return false
    }
    root.busy = true
    root.pendingKind = "mount"
    root.pendingPayload = JSON.stringify({ volumeId: volumeId })
    proc.command = [root.helper, "storage-removable-mount"]
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
      root.pendingKind = ""
      var raw = String(procStdout.text || "").trim()
      var parsed = {}
      try {
        parsed = JSON.parse(raw)
      } catch (error) {
        parsed = { ok: false, code: "command.failed", explanation: kind === "list" ? "The session Mount inventory failed." : "The session Mount helper failed." }
      }
      if (typeof parsed !== "object" || parsed === null)
        parsed = { ok: false, code: "command.failed", explanation: kind === "list" ? "The session Mount inventory failed." : "The session Mount helper failed." }
      var ok = parsed.ok === true && exitCode === 0
      parsed.ok = ok
      root.busy = false
      if (kind === "list") {
        var volumes = ok && parsed.volumes && parsed.volumes.constructor === Array ? parsed.volumes : []
        root.listed(volumes)
        return
      }
      if (!parsed.explanation)
        parsed.explanation = ok ? "Mounted the removable volume through this session." : "The session Mount helper failed."
      root.finished(ok, parsed)
    }
  }
}
