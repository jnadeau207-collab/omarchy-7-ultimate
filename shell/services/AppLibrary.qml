import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "AppSearch.js" as AppSearch
import "JumpList.js" as JumpList

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property var configuredHiddenEntryIds: ({})
  property var desktopHiddenEntryIds: ({})

  property var iconIndex: ({})
  property var pendingIconIndex: ({})
  property var actionIndex: ({})
  property var recentIds: []
  readonly property string recentsPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/ultimate/start-recents.json"

  property int launchSerial: 0
  property int launchToplevelCount: 0
  property var launchActiveToplevel: null
  property bool launchOsdOpen: false
  property string launchOsdMessage: ""

  signal appsChanged()

  function entryName(entry) {
    return AppSearch.entryName(entry)
  }

  function entrySubtext(entry) {
    return AppSearch.entrySubtext(entry)
  }

  function isHiddenEntry(entry) {
    var id = String((entry && entry.id) || "")
    return root.configuredHiddenEntryIds[id] === true || root.desktopHiddenEntryIds[id] === true
  }

  function sortedEntries(query) {
    var raw = DesktopEntries.applications.values || []
    var values = []
    var i
    for (i = 0; i < raw.length; i++) values.push(raw[i])
    var dests = AppSearch.searchDestinations(query, values)
    for (i = 0; i < dests.length; i++) values.push(dests[i])
    return AppSearch.sortedEntries(values, query, function(entry) { return root.isHiddenEntry(entry) })
  }

  function isDeveloperTool(entry) {
    return AppSearch.isDeveloperTool(entry)
  }

  function visibleEntries(query, hideDeveloperTools) {
    return AppSearch.visibleEntries(root.sortedEntries(query), query, hideDeveloperTools)
  }

  function programRows(query, hideDeveloperTools) {
    return AppSearch.programRows(root.visibleEntries(query, hideDeveloperTools), query)
  }

  function recentEntries(limit, excludeIds) {
    return AppSearch.recentEntries(root.recentIds, DesktopEntries.applications.values || [], limit, excludeIds)
  }

  function recordLaunch(desktopId) {
    root.recentIds = AppSearch.withRecent(root.recentIds, desktopId)
    recentsFile.setText(AppSearch.serializeRecents(root.recentIds))
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var found = root.iconIndex[value]
    if (found) return Util.fileUrl(found)
    var aliased = JumpList.iconNameFor(value)
    if (aliased) {
      found = root.iconIndex[aliased]
      if (found) return Util.fileUrl(found)
      var themedAlias = Quickshell.iconPath(aliased, true)
      if (themedAlias.length > 0) return themedAlias
    }
    var entry = root.entryByDesktopId(value)
    var entryIcon = entry ? String(entry.icon || "") : ""
    if (entryIcon && entryIcon !== value) {
      found = root.iconIndex[entryIcon]
      if (found) return Util.fileUrl(found)
      var themedEntry = Quickshell.iconPath(entryIcon, true)
      if (themedEntry.length > 0) return themedEntry
    }
    if (value.indexOf(".") < 0) {
      var themed = Quickshell.iconPath(value, true)
      if (themed.length > 0) return themed
    }
    return Quickshell.iconPath("application-x-executable", true)
  }

  function refreshIcons() {
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

  function entryByDesktopId(desktopId) {
    var aliases = JumpList.desktopIdAliases(desktopId)
    if (aliases.length === 0) return null
    var values = DesktopEntries.applications.values || []
    for (var a = 0; a < aliases.length; a++) {
      var want = aliases[a]
      for (var i = 0; i < values.length; i++) {
        var entry = values[i]
        if (!entry) continue
        if (JumpList.sameDesktopId(entry.id, want)) return entry
      }
    }
    return null
  }

  function jumpListFor(desktopId) {
    return JumpList.jumpListFor(root.entryByDesktopId(desktopId), desktopId, root.actionIndex)
  }

  function launch(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    root.recordLaunch(id)
    root.beginLaunchFeedback(name)
    var command = JumpList.actionCommand(root.entryByDesktopId(id))
    if (command) {
      var space = command.indexOf(" ")
      var bin = space < 0 ? command : command.slice(0, space)
      if (bin.indexOf("omarchy-") === 0 || (root.omarchyPath && bin.indexOf(root.omarchyPath + "/bin/omarchy-") === 0)) {
        Util.execDetached("uwsm-app -- " + root.launchCommand(command))
        return
      }
    }
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  function launchCommand(command) {
    var raw = String(command || "").trim().replace(/\s+%[A-Za-z@]/g, "")
    if (!raw) return ""
    var space = raw.indexOf(" ")
    var bin = space < 0 ? raw : raw.slice(0, space)
    var rest = space < 0 ? "" : raw.slice(space)
    if (bin.charAt(0) === "/") return raw
    if (bin.indexOf("omarchy-") === 0 && root.omarchyPath)
      return Util.shellQuote(root.omarchyPath + "/bin/" + bin) + rest
    return raw
  }

  function launchAction(desktopId, action, name) {
    if (!action || action.kind === "open-new" || !action.command) {
      root.launch(desktopId, name)
      return
    }
    root.beginLaunchFeedback(name || action.name || desktopId)
    Util.execDetached("uwsm-app -- " + root.launchCommand(action.command))
  }

  function remove(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    Util.execDetached(Util.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry") + " " + Util.shellQuote(id) + " " + Util.shellQuote(String(name || id)))
  }

  function normalizeDesktopId(id) {
    var value = String(id || "").trim()
    if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
    return value
  }

  function loadConfiguredHides(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    root.configuredHiddenEntryIds = next
    root.appsChanged()
  }

  function loadDesktopHiddenEntries(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    root.desktopHiddenEntryIds = next
    root.appsChanged()
  }

  function iconIndexScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')
  }

  function indexIconLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length > 0 && root.pendingIconIndex[name] === undefined)
      root.pendingIconIndex[name] = value
  }

  function hiddenEntryScanCommand() {
    var desktop = [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function(v) { return String(v || "").length > 0 }).join(":")
    var script = root.omarchyPath + "/shell/services/hidden-entries.sh"
    return Util.shellQuote(script) + " " + Util.shellQuote(desktop)
  }

  function toplevelCount() {
    try { return ToplevelManager.toplevels.values.length } catch (e) { return 0 }
  }

  function beginLaunchFeedback(name) {
    root.launchSerial++
    root.launchToplevelCount = root.toplevelCount()
    root.launchActiveToplevel = ToplevelManager.activeToplevel
    root.launchOsdMessage = "Launching " + String(name || "application") + "…"
    launchDelay.restart()
    launchTimeout.restart()
  }

  function closeLaunchFeedback(serial) {
    if (serial !== root.launchSerial) return
    launchDelay.stop()
    launchTimeout.stop()
    if (root.launchOsdOpen) {
      Quickshell.execDetached(["omarchy-shell", "osd", "close"])
      root.launchOsdOpen = false
    }
  }

  function maybeFinishLaunchFeedback() {
    if (!launchDelay.running && !launchTimeout.running && !root.launchOsdOpen) return
    if (root.toplevelCount() <= root.launchToplevelCount && ToplevelManager.activeToplevel === root.launchActiveToplevel) return
    root.closeLaunchFeedback(root.launchSerial)
  }

  QtObject {
    id: hiddenEntryOutput
    property string text: ""
  }

  Process {
    id: hiddenEntryScan
    command: ["bash", "-c", root.hiddenEntryScanCommand()]
    stdout: SplitParser { onRead: function(line) { hiddenEntryOutput.text += line + "\n" } }
    onStarted: hiddenEntryOutput.text = ""
    onExited: root.loadDesktopHiddenEntries(hiddenEntryOutput.text)
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    onExited: root.iconIndex = root.pendingIconIndex
  }

  Process {
    id: actionIndexScan
    command: ["python3", root.omarchyPath + "/shell/services/desktop-actions.py"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.actionIndex = JSON.parse(String(text || "{}"))
        } catch (e) {
          root.actionIndex = ({})
        }
      }
    }
  }

  Timer {
    id: iconIndexDebounce
    interval: 750
    onTriggered: if (!iconIndexScan.running) iconIndexScan.running = true
  }

  FileView {
    id: recentsFile
    path: root.recentsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.recentIds = AppSearch.parseRecents(text())
    onFileChanged: reload()
    onLoadFailed: root.recentIds = []
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfiguredHides(text())
    onFileChanged: root.loadConfiguredHides(text())
    onLoadFailed: root.loadConfiguredHides("")
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.maybeFinishLaunchFeedback() }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.maybeFinishLaunchFeedback() }
  }

  Timer {
    id: launchDelay
    interval: 2000
    onTriggered: {
      if (root.toplevelCount() > root.launchToplevelCount || ToplevelManager.activeToplevel !== root.launchActiveToplevel) return
      root.launchOsdOpen = true
      Quickshell.execDetached(["omarchy-shell", "osd", "show", JSON.stringify({ icon: "󱓞", message: root.launchOsdMessage, duration: 0 })])
    }
  }

  Timer {
    id: launchTimeout
    interval: 15000
    onTriggered: root.closeLaunchFeedback(root.launchSerial)
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      hiddenEntryScan.running = true
      iconIndexDebounce.restart()
      if (!actionIndexScan.running) actionIndexScan.running = true
      root.appsChanged()
    }
  }

  Component.onCompleted: {
    hiddenEntryScan.running = true
    iconIndexScan.running = true
    actionIndexScan.running = true
  }
}
