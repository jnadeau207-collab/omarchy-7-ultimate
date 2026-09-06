import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  signal finished(string kind, bool ok, var result)

  readonly property string helper: {
    var base = Quickshell.env("OMARCHY_PATH")
    return (base ? base : "/usr") + "/bin/omarchy-fabric-session-apply"
  }
  property bool busy: false
  property string pendingKind: ""
  property string pendingPayload: ""
  property bool followWithStatus: false

  function readStatus() {
    return root.run("status", "audio-output-status", {}, false)
  }

  function setMuted(resourceId, muted) {
    var token = String(resourceId || "")
    if (!token) {
      root.finished("mute", false, {
        ok: false,
        resourceId: "",
        muted: false,
        sinks: [],
        defaultResourceId: "",
        known: false,
        code: "payload.invalid",
        explanation: "Mute must name one tip-true audio.sink identity with a boolean muted flag."
      })
      return false
    }
    return root.run("mute", "audio-output-mute-set", { resourceId: token, muted: muted === true }, true)
  }

  function setDefault(resourceId) {
    var token = String(resourceId || "")
    if (!token) {
      root.finished("default", false, {
        ok: false,
        resourceId: "",
        sinks: [],
        defaultResourceId: "",
        known: false,
        code: "payload.invalid",
        explanation: "Default output must name one tip-true audio.sink identity from this session inventory."
      })
      return false
    }
    return root.run("default", "audio-output-default-set", { resourceId: token }, true)
  }

  function restartAudio() {
    return root.run("troubleshoot", "audio-troubleshoot-restart", {}, true)
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
        parsed = { ok: false, code: "command.failed", explanation: "The session Sound helper failed." }
      }
      if (typeof parsed !== "object" || parsed === null)
        parsed = { ok: false, code: "command.failed", explanation: "The session Sound helper failed." }
      var ok = parsed.ok === true && exitCode === 0
      parsed.ok = ok
      if (root.followWithStatus && ok) {
        root.followWithStatus = false
        root.pendingKind = "status"
        root.pendingPayload = "{}"
        stdinEnabled = true
        proc.command = [root.helper, "audio-output-status"]
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
