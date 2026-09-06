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
    return root.run("status", "printer-status", {}, false)
  }

  function setDefault(resourceId) {
    var token = String(resourceId || "")
    if (!token) {
      root.finished("default", false, {
        ok: false,
        resourceId: "",
        printers: [],
        defaultResourceId: "",
        known: false,
        code: "payload.invalid",
        explanation: "Default printer must name one tip-true printer identity from this session inventory."
      })
      return false
    }
    return root.run("default", "printer-default-set", { resourceId: token }, true)
  }

  function pauseQueue(resourceId) {
    var token = String(resourceId || "")
    if (!token) {
      root.finished("pause", false, {
        ok: false,
        resourceId: "",
        printers: [],
        defaultResourceId: "",
        known: false,
        code: "payload.invalid",
        explanation: "Pause must name one tip-true printer identity from this session inventory."
      })
      return false
    }
    return root.run("pause", "printer-pause", { resourceId: token }, true)
  }

  function resumeQueue(resourceId) {
    var token = String(resourceId || "")
    if (!token) {
      root.finished("resume", false, {
        ok: false,
        resourceId: "",
        printers: [],
        defaultResourceId: "",
        known: false,
        code: "payload.invalid",
        explanation: "Resume must name one tip-true printer identity from this session inventory."
      })
      return false
    }
    return root.run("resume", "printer-resume", { resourceId: token }, true)
  }

  function testPage(resourceId) {
    var token = String(resourceId || "")
    if (!token) {
      root.finished("test-page", false, {
        ok: false,
        resourceId: "",
        printers: [],
        defaultResourceId: "",
        known: false,
        code: "payload.invalid",
        explanation: "Test page must name one tip-true printer identity from this session inventory."
      })
      return false
    }
    return root.run("test-page", "printer-test-page", { resourceId: token }, true)
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
        parsed = { ok: false, code: "command.failed", explanation: "The session Printers helper failed." }
      }
      if (typeof parsed !== "object" || parsed === null)
        parsed = { ok: false, code: "command.failed", explanation: "The session Printers helper failed." }
      var ok = parsed.ok === true && exitCode === 0
      parsed.ok = ok
      if (root.followWithStatus && ok) {
        root.followWithStatus = false
        root.pendingKind = "status"
        root.pendingPayload = "{}"
        stdinEnabled = true
        proc.command = [root.helper, "printer-status"]
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
