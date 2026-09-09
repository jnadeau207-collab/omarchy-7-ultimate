import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.apps.shared as Shared

import "FilesModel.js" as FilesModel
import "ExplorerTheme.js" as Aero
import "." as Files

Item {
  id: root
  property var host: null
  property var controller: null
  property var queryState: FilesModel.baseState("files.overview", {}, "offline")

  readonly property var productProfile: host && host.productProfile ? host.productProfile : null
  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property bool busy: queryState.phase === "catalog-loading" || queryState.phase === "loading"
  readonly property bool canRetry: !busy && ["offline", "missing", "unavailable", "denied", "interrupted", "stale", "failed"].indexOf(queryState.phase) >= 0
  readonly property bool showRecords: ["ready", "available", "degraded", "partial", "empty"].indexOf(queryState.phase) >= 0
  readonly property bool healthy: ["ready", "available", "empty"].indexOf(queryState.phase) >= 0
  readonly property bool computerRoute: host !== null && host.currentRoute === "files.this-pc"
  readonly property bool faulted: ["offline", "missing", "unavailable", "denied", "interrupted", "stale", "failed"].indexOf(queryState.phase) >= 0

  property string operationStage: ""
  property string operationRequestId: ""
  property string operationId: ""
  property string operationMessage: ""
  property string operationName: ""
  property string operationKind: ""
  readonly property bool operationBusy: operationStage !== ""
  readonly property string createLocationId: FilesModel.createLocationForRoute(host ? host.currentRoute : "")
  readonly property bool createVisible: createLocationId !== ""
  readonly property bool createEnabled: createVisible && !operationBusy && host !== null && host.fabricReady
  readonly property bool trashAuthorized: false
  readonly property bool renameAuthorized: true
  readonly property bool copyAuthorized: true
  readonly property bool cutAuthorized: false // leftover Fabric SHELL refuse; session Cut does not consult this pin
  readonly property bool deleteAuthorized: false // leftover Fabric SHELL refuse; session Permanent Delete does not consult this pin
  readonly property bool emptyBinAuthorized: false
  readonly property bool ejectAuthorized: false // leftover Fabric SHELL refuse; session Eject does not consult this pin
  readonly property bool mountAuthorized: false // leftover Fabric SHELL refuse; session Mount does not consult this pin
  readonly property bool smbAuthorized: false // leftover Fabric SHELL refuse; session Connect does not consult this pin
  readonly property bool trashRoute: FilesModel.isTrashRoute(host ? host.currentRoute : "")
  readonly property bool sessionBusy: sessionTrash.busy || sessionMutate.busy || sessionArchive.busy || sessionProperties.busy || sessionEject.busy || sessionMount.busy || sessionSmb.busy
  property string smbHostDraft: ""
  property string smbShareDraft: ""
  property string renameDraft: ""
  property var renameRecord: null
  property var stagedCopyRecord: null
  property var stagedCutRecord: null
  property var pendingDeleteRecord: null
  property string propertiesPhase: "empty"
  property string propertiesMessage: ""
  property var propertiesResult: null

  property var history: []
  property int historyIndex: -1
  property bool traversing: false
  property string viewMode: "details"
  property string sortColumn: "name"
  property bool sortAscending: true
  property string selectedId: ""
  property var selectedRecord: null
  property var knownMounts: []
  property var sessionUnmountedVolumes: []

  readonly property string accountName: {
    var home = String(Tokens.home || "")
    var cut = home.lastIndexOf("/")
    var leaf = cut >= 0 ? home.slice(cut + 1) : home
    return leaf === "" ? "Home" : leaf
  }

  readonly property string relativePath: String(queryState.relativePath || "")
  readonly property string sessionBoundaryHonesty: "File contents are never read. Downloads place browses tip-true FilesModel files.downloads → files.location.downloads (SESSION CONTROL, READ-ONLY; files.downloads.open leftover-direct soft leftover-attached claim=partial visible Start > Downloads; Superbar > Files > Downloads; windows-native.9 stays prototype/pending; Cloud mocks do not close windows-native.9; not product CLOSED / not metal CLOSED / not claim=present). New folder runs through files.provider. Open runs through files.provider entry.open and launches the default handler by path (including PDF via the tip-true default/associated viewer; files.document.open leftover-direct soft leftover-attached claim=partial visible Files > PDF; windows-native.17 stays prototype/pending; including .txt via the tip-true default/associated graphical editor text/plain → org.gnome.TextEditor not Neovim-as-default; files.text.edit leftover-direct soft leftover-attached claim=partial visible Files > Text; windows-native.18 stays prototype/pending; no MIME association picker invent). Rename runs through files.provider entry.rename in the same directory. Copy and Paste run through files.provider entry.copy and also place or read files on this session's clipboard. Cut and Paste-after-cut run through this session's move helper. Permanent Delete runs through this session's delete helper after confirm. Compress runs through this session's archive helper (SESSION CONTROL). Extract runs through this session's archive helper (SESSION CONTROL). Properties runs through this session's read helper (SESSION CONTROL, READ-ONLY). Eject runs through tip-true FilesSessionEject.ejectDevice → storage-removable-eject (SESSION CONTROL; storage.removable.eject leftover-direct soft leftover-attached claim=partial visible Files > Devices > Eject; windows-native.15 stays prototype/pending; Cloud mocks do not close windows-native.15; not product CLOSED / not metal CLOSED / not claim=present). Mount runs through tip-true FilesSessionMount.mountVolume → storage-removable-mount (SESSION CONTROL; storage.removable.mount leftover-direct soft leftover-attached claim=partial visible Files > Devices > Mount; windows-native.14 stays prototype/pending; Cloud mocks do not close windows-native.14; not product CLOSED / not metal CLOSED / not claim=present). Connect to Server runs through this session's connect helper (SESSION CONTROL). Files does not invent a Fabric SHELL LIVE archive writer. Files does not invent a Fabric SHELL LIVE Properties writer. Files does not invent a Fabric SHELL LIVE eject writer. Files does not invent a Fabric SHELL LIVE mount writer. Files does not invent a Fabric SHELL LIVE SMB writer. The cut/move write plane exists but is not shell-authorizable (CHANGES UNAVAILABLE). cutAuthorized and deleteAuthorized stay leftover Fabric SHELL refuse; session Cut and Permanent Delete do not consult them. ejectAuthorized stays leftover Fabric SHELL refuse; session Eject does not consult it. mountAuthorized stays leftover Fabric SHELL refuse; session Mount does not consult it. smbAuthorized stays leftover Fabric SHELL refuse; session Connect does not consult it. Delete, Restore, and Empty Recycle Bin run through this session's trash helper. Trash write plane exists but is not shell-authorizable (CHANGES UNAVAILABLE). Restore write plane exists but is not shell-authorizable. The permanent delete write plane exists but is not shell-authorizable (CHANGES UNAVAILABLE). The empty Recycle Bin write plane exists but is not shell-authorizable. Fabric Restore UI and Empty Bin LIVE remain unavailable under SHELL. Recycle Bin is not product-complete."
  readonly property string routeTitle: currentRoute ? String(currentRoute.title) : "Files"
  readonly property bool paintsOwnTitleBar: true
  readonly property string sharedCaptionPath: "files-glass"
  readonly property var crumbs: FilesModel.breadcrumbFor(routeTitle, relativePath)
  readonly property bool canBack: historyIndex > 0
  readonly property bool canForward: historyIndex >= 0 && historyIndex < history.length - 1
  readonly property var historyMenu: {
    var menu = []
    var start = Math.max(0, root.history.length - 9)
    for (var i = root.history.length - 1; i >= start; i--) {
      var entry = root.history[i]
      var tail = String(entry.relativePath || "").split("/").filter(function(part) { return part !== "" })
      menu.push({
        index: i,
        current: i === root.historyIndex,
        label: tail.length > 0 ? tail[tail.length - 1] : String(entry.title || "Files")
      })
    }
    return menu
  }

  readonly property var locationRoutes: ({
    "files.location.desktop": "files.desktop",
    "files.location.documents": "files.documents",
    "files.location.downloads": "files.downloads",
    "files.location.pictures": "files.pictures",
    "files.location.music": "files.music",
    "files.location.videos": "files.videos",
    "files.location.trash": "files.trash"
  })

  focus: true

  function ensureController() {
    if (controller) return
    controller = FilesModel.createController({
      send: function(method, parameters) { return root.host ? root.host.requestFabric(method, parameters) : "" },
      cancel: function(requestId) { return root.host ? root.host.cancelFabric(requestId) : false },
      onState: function(state) {
        root.queryState = state
        var seen = FilesModel.explorerMounts(state.records)
        if (seen.length > 0) root.knownMounts = seen
        root.refreshSessionVolumes()
        root.selectedId = ""
        root.selectedRecord = null
        if (state.requestId !== "" && (state.phase === "catalog-loading" || state.phase === "loading")) staleTimer.restart()
        else staleTimer.stop()
      }
    })
  }

  function synchronizeHost() {
    ensureController()
    if (!host) return
    controller.activate(host.currentRoute || "files.overview", host.currentArguments || {})
    controller.setConnected(host.fabricReady)
    root.syncPlaceCaption()
  }

  function syncPlaceCaption() {
    if (!host) return
    var title = root.routeTitle
    if (title === "" || title === "Files") return
    host.placeTitle = title
  }

  function retryState() {
    if (!controller || !host) return
    if (host.fabricReady) controller.refresh()
    else host.retryFabric()
  }

  function refreshVisibleSurface() {
    if (!controller || !host || operationBusy) return
    if (!host.fabricReady) return
    controller.refreshWhenSurfaceVisible()
  }

  function recordHistory(routeId, path) {
    if (root.traversing) return
    var entry = { routeId: String(routeId), relativePath: String(path || ""), title: root.routeTitle }
    var top = root.historyIndex >= 0 ? root.history[root.historyIndex] : null
    if (top && top.routeId === entry.routeId && top.relativePath === entry.relativePath) return
    var trimmed = root.history.slice(0, root.historyIndex + 1)
    trimmed.push(entry)
    root.history = trimmed
    root.historyIndex = trimmed.length - 1
  }

  function travel(index) {
    if (index < 0 || index >= root.history.length || !root.host) return
    var entry = root.history[index]
    root.traversing = true
    root.historyIndex = index
    root.host.navigate(entry.routeId, entry.relativePath === "" ? {} : { relativePath: entry.relativePath })
    root.traversing = false
  }

  function goBack() { if (root.canBack) travel(root.historyIndex - 1) }
  function goForward() { if (root.canForward) travel(root.historyIndex + 1) }

  function goUp() {
    if (!host) return
    if (root.relativePath === "") return
    openPath(FilesModel.parentRelativePath(root.relativePath))
  }

  function openPath(path) {
    if (!host) return
    var target = String(path || "")
    host.navigate(host.currentRoute, target === "" ? {} : { relativePath: target })
  }

  function runSearch(text) {
    if (!host) return
    var query = String(text || "")
    host.navigate("files.search", query === "" ? {} : { query: query })
  }

  function viewItems() {
    if (!root.showRecords) return []
    var kind = root.currentRoute ? String(root.queryState.query ? root.queryState.query.kind : "") : ""
    if (kind === "entries") return FilesModel.sortedEntries(root.queryState.records, root.sortColumn, root.sortAscending)

    var shaped = []
    var locations = FilesModel.explorerLocations(root.queryState.records)
    for (var i = 0; i < locations.length; i++) {
      var location = locations[i]
      shaped.push({
        id: location.id, title: location.title, entryKind: location.locationKind === "trash" ? "trash" : "directory",
        typeLabel: "File folder", sizeText: "", modifiedText: "", hidden: false, writable: location.writable,
        targetRoute: root.locationRoutes[location.id] || "", relativePath: "", details: location.details, kind: "location",
        status: location.status, subtitle: location.subtitle, tone: location.tone
      })
    }
    var mounts = FilesModel.explorerMounts(root.queryState.records)
    for (var m = 0; m < mounts.length; m++) {
      var mount = mounts[m]
      shaped.push({
        id: mount.id, title: mount.title, entryKind: mount.mountKind === "smb" ? "network" : "drive",
        typeLabel: mount.mountKind === "smb" ? "Network Location" : mount.mountKind === "removable" ? "Removable Disk" : "Local Disk",
        sizeText: "", modifiedText: "", hidden: false, writable: mount.writable, targetRoute: "", relativePath: "",
        details: mount.details, kind: "mount", status: mount.status, subtitle: mount.subtitle, tone: mount.tone,
        mountKind: mount.mountKind, mountState: mount.mountState, display: mount.display,
        capacityText: mount.capacityText, usedFraction: mount.usedFraction,
        totalBytes: mount.totalBytes, freeBytes: mount.freeBytes
      })
    }
    return FilesModel.mergeSessionVolumes(shaped, root.sessionUnmountedVolumes)
  }

  function refreshSessionVolumes() {
    if (!sessionMount.busy) sessionMount.listVolumes()
  }

  function openRecord(record) {
    if (!record || !host) return
    if (record.targetRoute) { host.navigate(record.targetRoute, {}); return }
    if (record.entryKind === "directory" && record.kind === "entry") {
      openPath(FilesModel.childRelativePath(root.relativePath, record.title))
      return
    }
    if (record.entryKind === "file" && record.kind === "entry") {
      openEntry(record)
    }
  }

  function openEntry(record) {
    if (!host || operationBusy) return
    if (!record || String(record.kind || "") !== "entry" || String(record.entryKind || "") !== "file") return
    if (String(record.status || "") === "symlink") return
    if (String(record.locationId || "") === "files.location.trash") return
    root.operationName = String(record.title || "this entry")
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationKind = "open"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "files.provider",
      action: "entry.open",
      arguments: { entryId: String(record.id) },
      idempotencyKey: "files.entry.open." + String(record.id)
    })
    if (root.operationRequestId === "") root.resetOperation("Files could not reach the operation service.")
  }

  function nextFolderName() {
    var taken = {}
    var existing = FilesModel.explorerEntries(root.queryState.records)
    for (var i = 0; i < existing.length; i++) taken[String(existing[i].title).toLowerCase()] = true
    var base = "New folder"
    if (!taken[base.toLowerCase()]) return base
    for (var n = 2; n < 512; n++) {
      var candidate = base + " (" + n + ")"
      if (!taken[candidate.toLowerCase()]) return candidate
    }
    return base
  }

  function beginRename(record) {
    if (!root.renameAuthorized) return
    if (!host || operationBusy || createLocationId === "") return
    if (!record || String(record.kind || "") !== "entry" || String(record.status || "") === "symlink") return
    if (String(record.locationId || "") === "files.location.trash") return
    root.renameRecord = record
    root.renameDraft = String(record.title || "")
    renameDialog.open()
  }

  function renameEntry(record, name) {
    if (!root.renameAuthorized) return
    if (!host || operationBusy || createLocationId === "") return
    if (!record || String(record.kind || "") !== "entry" || String(record.status || "") === "symlink") return
    if (String(record.locationId || "") === "files.location.trash") return
    var refusal = FilesModel.createNameRefusal(name)
    if (refusal !== "") {
      root.operationMessage = refusal
      return
    }
    if (String(name) === String(record.title || "")) return
    root.operationName = String(name)
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationKind = "rename"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "files.provider",
      action: "entry.rename",
      arguments: { entryId: String(record.id), newName: String(name) },
      idempotencyKey: "files.entry.rename." + String(record.id) + "." + String(name)
    })
    if (root.operationRequestId === "") root.resetOperation("Files could not reach the operation service.")
  }

  function copyableRecord(record) {
    return FilesModel.copyableRecord(record)
  }

  function stageCopy(record) {
    if (!root.copyAuthorized) return
    if (!host || operationBusy) return
    if (!root.copyableRecord(record)) return
    root.stagedCopyRecord = record
    root.stagedCutRecord = null
    var payload = FilesModel.clipboardCopyArguments(record)
    if (payload) osClipboard.copyPayload(payload)
    root.operationMessage = "Copied " + String(record.title || "this entry") + " to the clipboard."
  }

  function nextDestinationName(sourceTitle) {
    var taken = {}
    var existing = FilesModel.explorerEntries(root.queryState.records)
    for (var i = 0; i < existing.length; i++) taken[String(existing[i].title).toLowerCase()] = true
    return FilesModel.nextCopyName(taken, sourceTitle)
  }

  function pasteFromClipboard() {
    if (root.stagedCutRecord) {
      root.sessionMoveStagedCut()
      return
    }
    if (!root.copyAuthorized) return
    if (!host || operationBusy || createLocationId === "") return
    var payload = FilesModel.clipboardPasteArguments(root.createLocationId, root.relativePath)
    if (!payload) {
      root.operationMessage = "This folder cannot receive a paste."
      return
    }
    if (osClipboard.pastePayload(payload)) return
    root.pasteStagedCopy()
  }

  function pasteStagedCopy() {
    if (!root.copyAuthorized) return
    if (!host || operationBusy || createLocationId === "") return
    if (!root.stagedCopyRecord) return
    if (!root.copyableRecord(root.stagedCopyRecord)) return
    var destName = root.nextDestinationName(String(root.stagedCopyRecord.title || ""))
    var refusal = FilesModel.createNameRefusal(destName)
    if (refusal !== "") {
      root.operationMessage = refusal
      return
    }
    root.operationName = String(destName)
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationKind = "copy"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "files.provider",
      action: "entry.copy",
      arguments: {
        entryId: String(root.stagedCopyRecord.id),
        destinationLocationId: root.createLocationId,
        destinationParentRelativePath: root.relativePath,
        destinationName: destName
      },
      idempotencyKey: "files.entry.copy." + String(root.stagedCopyRecord.id) + "." + root.createLocationId + "." + destName
    })
    if (root.operationRequestId === "") root.resetOperation("Files could not reach the operation service.")
  }

  function trashEntry(record) {
    if (!root.trashAuthorized) return
    if (!host || operationBusy || createLocationId === "") return
    if (!record || String(record.kind || "") !== "entry" || String(record.status || "") === "symlink") return
    root.operationName = String(record.title || "this entry")
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationKind = "trash"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "files.provider",
      action: "entry.trash",
      arguments: { entryId: String(record.id) },
      idempotencyKey: "files.entry.trash." + String(record.id)
    })
    if (root.operationRequestId === "") root.resetOperation("Files could not reach the operation service.")
  }

  function sessionTrashEntry(record) {
    if (root.operationBusy || root.sessionBusy) return
    var plan = FilesModel.sessionTrashPlan(record)
    if (!FilesModel.sessionTrashCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That item cannot be moved to Trash through this session."
      return
    }
    root.operationMessage = "Moving " + String(record.title || "this item") + " to the Recycle Bin through this session."
    if (!sessionTrash.trashRecord(plan)) root.operationMessage = "The session recycle helper is busy."
  }

  function sessionRestoreEntry(record) {
    if (root.operationBusy || root.sessionBusy) return
    var plan = FilesModel.sessionRestorePlan(record)
    if (!FilesModel.sessionTrashCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That Recycle Bin item cannot be restored through this session."
      return
    }
    root.operationMessage = "Restoring " + String(record.title || "this item") + " through this session."
    if (!sessionTrash.restoreRecord(plan)) root.operationMessage = "The session recycle helper is busy."
  }

  function sessionEmptyBin() {
    if (root.operationBusy || root.sessionBusy || !root.trashRoute) return
    var plan = FilesModel.sessionEmptyPlan()
    root.operationMessage = "Emptying the Recycle Bin through this session."
    if (!sessionTrash.emptyBin(plan)) root.operationMessage = "The session recycle helper is busy."
  }

  function sessionCutEntry(record) {
    if (root.operationBusy || root.sessionBusy) return
    if (!FilesModel.sessionMovableRecord(record)) {
      var preview = FilesModel.sessionMovePlan(record, "files.location.desktop", "", String(record && record.title || "item"))
      root.operationMessage = preview.reason || "That item cannot be cut through this session."
      return
    }
    root.stagedCutRecord = record
    root.stagedCopyRecord = null
    root.operationMessage = "Cut " + String(record.title || "this item") + ". Paste moves it through this session."
  }

  function sessionMoveStagedCut() {
    if (root.operationBusy || root.sessionBusy) return
    if (!root.stagedCutRecord) return
    var destName = String(root.stagedCutRecord.title || "")
    var plan = FilesModel.sessionMovePlan(root.stagedCutRecord, root.createLocationId, root.relativePath, destName)
    if (!FilesModel.sessionMutateCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That item cannot be moved through this session."
      return
    }
    root.operationMessage = "Moving " + destName + " through this session."
    if (!sessionMutate.moveRecord(plan)) root.operationMessage = "The session cut helper is busy."
  }

  function beginPermanentDelete(record) {
    if (root.operationBusy || root.sessionBusy) return
    var plan = FilesModel.sessionDeletePlan(record)
    if (!FilesModel.sessionMutateCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That item cannot be permanently deleted through this session."
      return
    }
    root.pendingDeleteRecord = record
    deleteDialog.open()
  }

  function sessionDeleteEntry(record) {
    if (root.operationBusy || root.sessionBusy) return
    var plan = FilesModel.sessionDeletePlan(record)
    if (!FilesModel.sessionMutateCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That item cannot be permanently deleted through this session."
      return
    }
    root.operationMessage = "Permanently deleting " + String(record.title || "this item") + " through this session."
    if (!sessionMutate.deleteRecord(plan)) root.operationMessage = "The session delete helper is busy."
  }

  function sessionCompressEntry(record) {
    if (root.operationBusy || root.sessionBusy) return
    var plan = FilesModel.sessionArchivePlan(record)
    if (!FilesModel.sessionArchiveCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That item cannot be compressed through this session."
      return
    }
    root.operationMessage = "Compressing " + String(plan.title || record.title || "this item") + " through this session."
    if (!sessionArchive.createArchive(plan)) root.operationMessage = "The session Compress helper is busy."
  }

  function sessionExtractEntry(record) {
    if (root.operationBusy || root.sessionBusy) return
    var plan = FilesModel.sessionExtractPlan(record)
    if (!FilesModel.sessionExtractCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That item cannot be extracted through this session."
      return
    }
    root.operationMessage = "Extracting " + String(plan.title || record.title || "this item") + " through this session."
    if (!sessionArchive.extractArchive(plan)) root.operationMessage = "The session Extract helper is busy."
  }

  function sessionEjectDevice(record) {
    if (root.operationBusy || root.sessionBusy) return
    var plan = FilesModel.sessionEjectPlan(record)
    if (!FilesModel.sessionEjectCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That device cannot be ejected through this session."
      return
    }
    root.operationMessage = "Ejecting " + String(plan.title || record.title || "this device") + " through this session."
    if (!sessionEject.ejectDevice(plan)) root.operationMessage = "The session Eject helper is busy."
  }

  function sessionMountVolume(record) {
    if (root.operationBusy || root.sessionBusy) return
    var plan = FilesModel.sessionMountPlan(record)
    if (!FilesModel.sessionMountCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That volume cannot be mounted through this session."
      return
    }
    root.operationMessage = "Mounting " + String(plan.title || record.title || "this volume") + " through this session."
    if (!sessionMount.mountVolume(plan)) root.operationMessage = "The session Mount helper is busy."
  }

  function sessionConnectShare() {
    if (root.operationBusy || root.sessionBusy) return
    var plan = FilesModel.sessionSmbPlan(root.smbHostDraft, root.smbShareDraft)
    if (!FilesModel.sessionSmbCanSubmit(plan)) {
      root.operationMessage = plan.reason || "That share cannot be connected through this session."
      return
    }
    root.operationMessage = "Connecting to " + plan.host + "/" + plan.share + " through this session."
    smbDialog.close()
    if (!sessionSmb.connectShare(plan)) root.operationMessage = "The session Connect helper is busy."
  }

  function sessionReadProperties(record) {
    var plan = FilesModel.sessionPropertiesPlan(record)
    root.propertiesResult = null
    if (!FilesModel.sessionPropertiesCanSubmit(plan)) {
      root.propertiesPhase = record ? "failed" : "empty"
      root.propertiesMessage = plan.reason || "Select a file or folder to view Properties through this session."
      return
    }
    root.propertiesPhase = "loading"
    root.propertiesMessage = "Reading Properties through this session."
    if (!sessionProperties.readProperties(plan)) {
      root.propertiesPhase = "failed"
      root.propertiesMessage = "The session Properties helper is busy."
    }
  }

  function createFolder(name) {
    if (!host || operationBusy || !createVisible) return
    var refusal = FilesModel.createNameRefusal(name)
    if (refusal !== "") {
      root.operationMessage = refusal
      return
    }
    root.operationName = String(name)
    root.operationKind = "create"
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "files.provider",
      action: "directory.create",
      arguments: { locationId: root.createLocationId, parentRelativePath: root.relativePath, name: root.operationName },
      idempotencyKey: "files.directory.create." + root.createLocationId + "." + root.operationName
    })
    if (root.operationRequestId === "") root.resetOperation("Files could not reach the operation service.")
  }

  function resetOperation(message) {
    root.operationStage = ""
    root.operationRequestId = ""
    root.operationId = ""
    root.operationMessage = message || ""
  }

  function advanceOperation(result) {
    if (root.operationStage === "preflight") {
      root.operationId = String(result.operationId || "")
      root.operationStage = "approve"
      root.operationRequestId = host.requestFabric("operation.approve", { operationId: root.operationId })
      return
    }
    if (root.operationStage === "approve") {
      root.operationStage = "start"
      root.operationRequestId = host.requestFabric("operation.start", {
        operationId: root.operationId,
        approvalId: String(result.approvalId || "")
      })
      return
    }
    if (root.operationStage === "start") {
      var succeeded = String(result.status || "") === "succeeded"
      var verb = root.operationKind === "trash" ? "Moved " : root.operationKind === "open" ? "Opened " : root.operationKind === "rename" ? "Renamed " : root.operationKind === "copy" ? "Copied " : "Created "
      var gerund = root.operationKind === "trash" ? "Moving " : root.operationKind === "open" ? "Opening " : root.operationKind === "rename" ? "Renaming " : root.operationKind === "copy" ? "Copying " : "Creating "
      var tail = root.operationKind === "trash" ? " to the Recycle Bin." : "."
      root.resetOperation(succeeded
        ? verb + root.operationName + tail
        : gerund + root.operationName + " ended as " + String(result.status || "unknown") + ".")
      if (root.controller) root.controller.refresh()
    }
  }

  function commandActions() {
    if (root.trashRoute) {
      return [
        { key: "organize", label: "Organize", dropdown: true, icon: "organize", enabled: true },
        { key: "restore", label: "Restore", dropdown: false, icon: "restore", enabled: !root.operationBusy && !root.sessionBusy && FilesModel.sessionRestorableRecord(root.selectedRecord) },
        { key: "empty-bin", label: "Empty Recycle Bin", dropdown: false, icon: "trash", enabled: !root.operationBusy && !root.sessionBusy && root.showRecords },
        { key: "properties", label: "Properties", dropdown: false, icon: "file", enabled: !sessionProperties.busy }
      ]
    }
    var list = [{ key: "organize", label: "Organize", dropdown: true, enabled: true }]
    if (root.createVisible) list.push({ key: "new-folder", label: "New folder", dropdown: false, enabled: root.createEnabled })
    if (root.createVisible && root.renameAuthorized) {
      list.push({
        key: "rename", label: "Rename", dropdown: false,
        enabled: !root.operationBusy && root.selectedRecord !== null && String(root.selectedRecord.kind || "") === "entry" && String(root.selectedRecord.status || "") !== "symlink"
      })
    }
    if (root.copyAuthorized) {
      list.push({
        key: "copy", label: "Copy", dropdown: false,
        enabled: !root.operationBusy && root.copyableRecord(root.selectedRecord)
      })
    }
    list.push({
      key: "cut", label: "Cut", dropdown: false,
      enabled: !root.operationBusy && !root.sessionBusy && FilesModel.sessionMovableRecord(root.selectedRecord)
    })
    if (root.createVisible && root.copyAuthorized) {
      list.push({
        key: "paste", label: "Paste", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy
      })
    }
    if (root.createVisible && FilesModel.sessionTrashableLocation(root.createLocationId)) {
      list.push({
        key: "compress", label: "Compress", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy && FilesModel.sessionCompressableRecord(root.selectedRecord)
      })
      list.push({
        key: "extract", label: "Extract", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy && FilesModel.sessionExtractableRecord(root.selectedRecord)
      })
    }
    if (root.createVisible && FilesModel.sessionTrashableLocation(root.createLocationId)) {
      list.push({
        key: "delete", label: "Delete", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy && FilesModel.sessionTrashableRecord(root.selectedRecord)
      })
      list.push({
        key: "permanently-delete", label: "Permanently delete", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy && FilesModel.sessionDeletableRecord(root.selectedRecord)
      })
    }
    if (root.trashRoute) {
      list.push({
        key: "restore", label: "Restore", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy && FilesModel.sessionRestorableRecord(root.selectedRecord)
      })
      list.push({
        key: "empty-bin", label: "Empty Recycle Bin", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy && root.showRecords
      })
    }
    if (root.computerRoute || FilesModel.sessionMountableRecord(root.selectedRecord) || FilesModel.sessionEjectableRecord(root.selectedRecord)) {
      list.push({
        key: "mount", label: "Mount", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy && FilesModel.sessionMountableRecord(root.selectedRecord)
      })
      list.push({
        key: "eject", label: "Eject", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy && FilesModel.sessionEjectableRecord(root.selectedRecord)
      })
    }
    if (!root.trashRoute) {
      list.push({
        key: "connect", label: "Connect to Server", dropdown: false,
        enabled: !root.operationBusy && !root.sessionBusy
      })
    }
    list.push({ key: "properties", label: "Properties", dropdown: false, enabled: !sessionProperties.busy })
    return list
  }

  function organizeMenuItems() {
    var list = [{ key: "new-folder", label: "New folder", enabled: root.createEnabled }]
    if (root.renameAuthorized) {
      list.push({ key: "rename", label: "Rename", enabled: root.createVisible && root.selectedRecord !== null && !root.operationBusy })
    }
    if (root.copyAuthorized) {
      list.push({ key: "copy", label: "Copy", enabled: root.copyableRecord(root.selectedRecord) && !root.operationBusy })
    }
    list.push({ key: "cut", label: "Cut", enabled: FilesModel.sessionMovableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
    if (root.copyAuthorized) {
      list.push({ key: "paste", label: "Paste", enabled: root.createVisible && !root.operationBusy && !root.sessionBusy })
    }
    if (FilesModel.sessionTrashableLocation(root.createLocationId)) {
      list.push({ key: "compress", label: "Compress", enabled: FilesModel.sessionCompressableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
      list.push({ key: "extract", label: "Extract", enabled: FilesModel.sessionExtractableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
    }
    if (root.trashRoute) {
      list.push({ key: "restore", label: "Restore", enabled: FilesModel.sessionRestorableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
      list.push({ key: "empty-bin", label: "Empty Recycle Bin", enabled: !root.operationBusy && !root.sessionBusy && root.showRecords })
    } else if (FilesModel.sessionTrashableLocation(root.createLocationId)) {
      list.push({ key: "delete", label: "Delete", enabled: FilesModel.sessionTrashableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
      list.push({ key: "permanently-delete", label: "Permanently delete", enabled: FilesModel.sessionDeletableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
    }
    list.push({ key: "refresh", label: "Refresh", enabled: true })
    if (root.computerRoute || FilesModel.sessionMountableRecord(root.selectedRecord) || FilesModel.sessionEjectableRecord(root.selectedRecord)) {
      list.push({ key: "mount", label: "Mount", enabled: FilesModel.sessionMountableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
      list.push({ key: "eject", label: "Eject", enabled: FilesModel.sessionEjectableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
    }
    if (!root.trashRoute) list.push({ key: "connect", label: "Connect to Server", enabled: !root.operationBusy && !root.sessionBusy })
    list.push({ key: "properties", label: "Properties", enabled: !sessionProperties.busy })
    return list
  }

  function contextMenuItems() {
    var list = [{ key: "open", label: "Open", enabled: root.selectedRecord !== null }]
    if (root.renameAuthorized) {
      list.push({ key: "rename", label: "Rename", enabled: root.createVisible && root.selectedRecord !== null && !root.operationBusy })
    }
    if (root.copyAuthorized) {
      list.push({ key: "copy", label: "Copy", enabled: root.copyableRecord(root.selectedRecord) && !root.operationBusy })
    }
    list.push({ key: "cut", label: "Cut", enabled: FilesModel.sessionMovableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
    if (root.copyAuthorized) {
      list.push({ key: "paste", label: "Paste", enabled: root.createVisible && !root.operationBusy && !root.sessionBusy })
    }
    if (FilesModel.sessionTrashableLocation(root.createLocationId)) {
      list.push({ key: "compress", label: "Compress", enabled: FilesModel.sessionCompressableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
      list.push({ key: "extract", label: "Extract", enabled: FilesModel.sessionExtractableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
    }
    if (root.trashRoute) {
      list.push({ key: "restore", label: "Restore", enabled: FilesModel.sessionRestorableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
      list.push({ key: "empty-bin", label: "Empty Recycle Bin", enabled: !root.operationBusy && !root.sessionBusy && root.showRecords })
    } else if (FilesModel.sessionTrashableLocation(root.createLocationId)) {
      list.push({ key: "delete", label: "Delete", enabled: FilesModel.sessionTrashableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
      list.push({ key: "permanently-delete", label: "Permanently delete", enabled: FilesModel.sessionDeletableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
    }
    if (root.computerRoute || FilesModel.sessionMountableRecord(root.selectedRecord) || FilesModel.sessionEjectableRecord(root.selectedRecord)) {
      list.push({ key: "mount", label: "Mount", enabled: FilesModel.sessionMountableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
      list.push({ key: "eject", label: "Eject", enabled: FilesModel.sessionEjectableRecord(root.selectedRecord) && !root.operationBusy && !root.sessionBusy })
    }
    if (!root.trashRoute) list.push({ key: "connect", label: "Connect to Server", enabled: !root.operationBusy && !root.sessionBusy })
    list.push({ key: "properties", label: "Properties", enabled: !sessionProperties.busy })
    return list
  }

  function invoke(key) {
    if (key === "organize") { organizeMenu.visible ? organizeMenu.close() : organizeMenu.open(); return }
    if (key === "new-folder") { root.createFolder(root.nextFolderName()); return }
    if (key === "rename") { root.beginRename(root.selectedRecord); return }
    if (key === "copy") { root.stageCopy(root.selectedRecord); return }
    if (key === "cut") { root.sessionCutEntry(root.selectedRecord); return }
    if (key === "paste") { root.pasteFromClipboard(); return }
    if (key === "compress") { root.sessionCompressEntry(root.selectedRecord); return }
    if (key === "extract") { root.sessionExtractEntry(root.selectedRecord); return }
    if (key === "delete") { root.sessionTrashEntry(root.selectedRecord); return }
    if (key === "permanently-delete") { root.beginPermanentDelete(root.selectedRecord); return }
    if (key === "restore") { root.sessionRestoreEntry(root.selectedRecord); return }
    if (key === "empty-bin") { emptyBinDialog.open(); return }
    if (key === "mount") { root.sessionMountVolume(root.selectedRecord); return }
    if (key === "eject") { root.sessionEjectDevice(root.selectedRecord); return }
    if (key === "connect") { smbDialog.open(); return }
    if (key === "properties") { root.sessionReadProperties(root.selectedRecord); propertiesDialog.open(); return }
    if (key === "refresh") { root.retryState(); return }
    if (key === "open") { root.openRecord(root.selectedRecord); return }
  }

  onHostChanged: synchronizeHost()
  onRouteTitleChanged: root.syncPlaceCaption()
  onComputerRouteChanged: if (root.computerRoute) root.refreshSessionVolumes()
  Component.onCompleted: { ensureController(); root.syncPlaceCaption(); focusTimer.restart(); if (root.computerRoute) root.refreshSessionVolumes() }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_F5 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R)) { root.retryState(); event.accepted = true }
    else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) { addressBar.forceActiveFocus(); event.accepted = true }
    else if (event.key === Qt.Key_Backspace) { root.goUp(); event.accepted = true }
    else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Left) { root.goBack(); event.accepted = true }
    else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Right) { root.goForward(); event.accepted = true }
    else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Up) { root.goUp(); event.accepted = true }
    else if (event.key === Qt.Key_F2) { root.beginRename(root.selectedRecord); event.accepted = true }
    else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) { root.stageCopy(root.selectedRecord); event.accepted = true }
    else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_X) { root.sessionCutEntry(root.selectedRecord); event.accepted = true }
    else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { root.pasteFromClipboard(); event.accepted = true }
    else if (event.key === Qt.Key_Delete) { if (root.trashRoute) return; if (event.modifiers & Qt.ShiftModifier) root.beginPermanentDelete(root.selectedRecord); else root.sessionTrashEntry(root.selectedRecord); event.accepted = true }
  }

  Shared.FilesSessionTrash {
    id: sessionTrash
    onFinished: function(kind, ok, message) {
      root.operationMessage = message
      if (ok && root.controller) root.controller.refresh()
    }
  }

  Shared.FilesSessionMutate {
    id: sessionMutate
    onFinished: function(kind, ok, message) {
      root.operationMessage = message
      if (ok && kind === "move") root.stagedCutRecord = null
      if (ok && kind === "delete") root.pendingDeleteRecord = null
      if (ok && root.controller) root.controller.refresh()
    }
  }

  Shared.FilesSessionArchive {
    id: sessionArchive
    onFinished: function(kind, ok, message) {
      root.operationMessage = message
      if (ok && root.controller) root.controller.refresh()
    }
  }

  Shared.FilesSessionEject {
    id: sessionEject
    onFinished: function(ok, result) {
      root.operationMessage = result && result.explanation ? String(result.explanation) : (ok ? "Ejected the removable device through this session." : "The session Eject helper failed.")
      if (ok && root.controller) root.controller.refresh()
      else root.refreshSessionVolumes()
    }
  }

  Shared.FilesSessionMount {
    id: sessionMount
    onListed: function(volumes) {
      root.sessionUnmountedVolumes = volumes
    }
    onFinished: function(ok, result) {
      root.operationMessage = result && result.explanation ? String(result.explanation) : (ok ? "Mounted the removable volume through this session." : "The session Mount helper failed.")
      if (ok && root.controller) root.controller.refresh()
      else root.refreshSessionVolumes()
    }
  }

  Shared.FilesSessionSmb {
    id: sessionSmb
    onFinished: function(ok, result) {
      root.operationMessage = result && result.explanation ? String(result.explanation) : (ok ? "Connected the guest SMB share through this session." : "The session Connect helper failed.")
      if (ok && root.controller) root.controller.refresh()
    }
  }

  Shared.FilesSessionProperties {
    id: sessionProperties
    onFinished: function(ok, result) {
      if (ok) {
        root.propertiesPhase = "ready"
        root.propertiesResult = result
        root.propertiesMessage = ""
        return
      }
      root.propertiesPhase = "failed"
      root.propertiesResult = null
      root.propertiesMessage = result && result.explanation ? String(result.explanation) : "The session Properties helper failed."
    }
  }

  Shared.FilesOsClipboard {
    id: osClipboard
    onFinished: function(kind, ok, message) {
      if (kind === "copy") {
        if (!ok) root.operationMessage = message
        return
      }
      if (kind !== "paste") return
      if (ok) {
        root.operationMessage = message
        if (root.controller) root.controller.refresh()
        return
      }
      if (root.stagedCopyRecord) {
        root.pasteStagedCopy()
        return
      }
      root.operationMessage = message
    }
  }

  Timer {
    id: focusTimer
    interval: 60
    repeat: false
    onTriggered: root.computerRoute ? computerView.forceActiveFocus() : itemView.forceActiveFocus()
  }

  Timer {
    id: staleTimer
    interval: 9000
    repeat: false
    onTriggered: if (root.controller && root.queryState.requestId !== "") root.controller.markStale(root.queryState.requestId)
  }

  Connections {
    target: root.host
    enabled: root.host !== null
    function onFabricConnectionReady(hello) { root.ensureController(); root.controller.setConnected(true) }
    function onFabricReadyChanged() { root.ensureController(); root.controller.setConnected(root.host.fabricReady) }
    function onRouteActivated(routeId, routeArguments, context) {
      root.ensureController()
      root.controller.activate(routeId, routeArguments || {})
      root.recordHistory(routeId, routeArguments && routeArguments.relativePath ? String(routeArguments.relativePath) : "")
      focusTimer.restart()
    }
    function onSurfaceBecameActive() { root.refreshVisibleSurface() }
    function onFabricResult(requestId, result) {
      if (root.operationBusy && requestId === root.operationRequestId) {
        root.advanceOperation(result)
        return
      }
      if (root.controller) root.controller.receiveResult(requestId, result)
    }
    function onFabricFailure(requestId, error) {
      if (root.operationBusy && requestId === root.operationRequestId) {
        root.resetOperation(error && error.explanation ? String(error.explanation) : "The folder was not created.")
        return
      }
      if (root.controller) root.controller.receiveFailure(requestId, error)
    }
  }

  Files.ExplorerGlassCaption {
    id: captionBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    productProfile: root.productProfile
    title: root.routeTitle
    onCloseRequested: if (root.host) root.host.closeSurface()
    onMinimizeRequested: if (root.host) root.host.minimizeSurface()
    onMaximizeRequested: if (root.host) root.host.toggleMaximizeSurface()
  }

  Files.ExplorerAddressBar {
    id: addressBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: captionBar.bottom
    productProfile: root.productProfile
    crumbs: root.crumbs
    locationIcon: root.currentRoute && root.currentRoute.id === "files.this-pc" ? "computer"
      : root.currentRoute && root.currentRoute.id === "files.network" ? "network"
      : root.currentRoute && root.currentRoute.id === "files.trash" ? "trash" : "directory"
    searchPlaceholder: "Search " + root.routeTitle
    searchText: String(root.queryState.searchQuery || "")
    canBack: root.canBack
    canForward: root.canForward
    busy: root.busy
    historyMenu: root.historyMenu
    onBackRequested: root.goBack()
    onForwardRequested: root.goForward()
    onTravelRequested: function(index) { root.travel(index) }
    onCrumbActivated: function(path) { root.openPath(path) }
    onRefreshRequested: root.retryState()
    onSearchAccepted: function(text) { root.runSearch(text) }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: addressBar.bottom
    anchors.bottom: parent.bottom
    color: Aero.contentFill
  }

  Files.ExplorerCommandBar {
    id: commandBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: addressBar.bottom
    productProfile: root.productProfile
    actions: root.commandActions()
    sessionBadge: ""
    viewMode: root.viewMode
    onActionTriggered: function(key) { root.invoke(key) }
    onViewModeRequested: function(mode) { root.viewMode = mode }
  }

  Rectangle {
    id: notice
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: commandBar.bottom
    height: visible ? 26 : 0
    visible: root.faulted || root.operationMessage !== ""
    color: ["failed", "denied", "unavailable"].indexOf(root.queryState.phase) >= 0 ? Aero.errorFill : Aero.warningFill

    Rectangle {
      width: parent.width
      height: 1
      y: parent.height - 1
      color: ["failed", "denied", "unavailable"].indexOf(root.queryState.phase) >= 0 ? Aero.errorBorder : Aero.warningBorder
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.right: retryLink.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: root.operationMessage !== ""
        ? root.operationMessage
        : Semantics.text(root.productProfile, FilesModel.stateExplanation(root.queryState))
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Aero.textPrimary
      font.family: Aero.fontFamily
      font.pixelSize: 12
    }

    Text {
      id: retryLink
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      visible: root.canRetry
      text: Semantics.text(root.productProfile, root.queryState.phase === "offline" ? "Reconnect" : "Try again")
      textFormat: Text.PlainText
      color: Aero.linkText
      font.family: Aero.fontFamily
      font.pixelSize: 12
      font.underline: retryHover.hovered

      HoverHandler { id: retryHover }
      TapHandler { onSingleTapped: root.retryState() }

      Accessible.role: Accessible.Button
      Accessible.name: retryLink.text
    }

    Accessible.role: Accessible.AlertMessage
    Accessible.name: notice.visible ? Semantics.text(root.productProfile, FilesModel.stateTitle(root.queryState)) : ""
  }

  Files.ExplorerNavigationPane {
    id: navigationPane
    anchors.left: parent.left
    anchors.top: notice.bottom
    anchors.bottom: detailsPane.top
    width: root.width < 900 ? 150 : 190
    accountName: root.accountName
    currentRoute: root.host ? root.host.currentRoute : ""
    mounts: root.knownMounts
    onRouteActivated: function(routeId) { if (root.host) root.host.navigate(routeId, {}) }
  }

  Rectangle {
    id: splitter
    anchors.left: navigationPane.right
    anchors.top: navigationPane.top
    anchors.bottom: navigationPane.bottom
    width: 1
    color: Aero.navBorder
  }

  Files.ExplorerComputerView {
    id: computerView
    visible: root.computerRoute
    anchors.left: splitter.right
    anchors.right: parent.right
    anchors.top: notice.bottom
    anchors.bottom: detailsPane.top
    items: root.viewItems()
    selectedId: root.selectedId

    onSelectionChanged: function(record) {
      root.selectedId = record ? String(record.id) : ""
      root.selectedRecord = record
    }
    onActivated: function(record) { root.openRecord(record) }
    onContextRequested: function(record, windowX, windowY) {
      root.selectedRecord = record
      root.selectedId = record ? String(record.id) : ""
      contextMenu.x = windowX
      contextMenu.y = windowY
      contextMenu.open()
    }
  }

  Files.ExplorerItemView {
    id: itemView
    visible: !root.computerRoute
    anchors.left: splitter.right
    anchors.right: parent.right
    anchors.top: notice.bottom
    anchors.bottom: detailsPane.top
    productProfile: root.productProfile
    items: root.viewItems()
    focus: true
    mode: root.viewMode
    sortColumn: root.sortColumn
    sortAscending: root.sortAscending
    selectedId: root.selectedId

    onSelectionChanged: function(record) {
      root.selectedId = record ? String(record.id) : ""
      root.selectedRecord = record
    }
    onActivated: function(record) { root.openRecord(record) }
    onSortRequested: function(column) {
      if (root.sortColumn === column) root.sortAscending = !root.sortAscending
      else { root.sortColumn = column; root.sortAscending = true }
    }
    onContextRequested: function(record, windowX, windowY) {
      root.selectedRecord = record
      root.selectedId = record ? String(record.id) : ""
      contextMenu.x = windowX
      contextMenu.y = windowY
      contextMenu.open()
    }
  }

  Text {
    anchors.centerIn: itemView
    visible: root.showRecords && itemView.count === 0 && !root.computerRoute
    text: FilesModel.isIdleSearch(root.queryState) ? "Type in the search box to begin."
      : root.queryState.selectedMissing ? "That item is no longer in this folder."
      : "This folder is empty."
    textFormat: Text.PlainText
    color: Aero.textSecondary
    font.family: Aero.fontFamily
    font.pixelSize: 12
  }

  Files.ExplorerDetailsPane {
    id: detailsPane
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    record: root.selectedRecord
    itemCount: root.computerRoute ? computerView.count : itemView.count
    locationLabel: root.routeTitle
    truncated: root.queryState.truncated === true || root.queryState.clipped === true
    boundary: ""
    folderPath: {
      if (!root.selectedRecord || String(root.selectedRecord.kind || "") !== "entry") return ""
      var parent = FilesModel.parentRelativePath(String(root.selectedRecord.relativePath || ""))
      return parent === "" ? root.routeTitle : root.routeTitle + " › " + parent.split("/").join(" › ")
    }
  }

  Controls.Popup {
    id: organizeMenu
    x: 6
    y: captionBar.height + addressBar.height + commandBar.height
    width: 168
    padding: 1

    background: Rectangle {
      color: "#ffffff"
      border.width: 1
      border.color: "#a0a0a0"
    }

    contentItem: Column {
      spacing: 0

      Repeater {
        model: organizeMenuItems()

        delegate: Item {
          required property var modelData
          width: 166
          height: 22

          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            visible: organizeHover.hovered && modelData.enabled
            border.width: 1
            border.color: Aero.hoverBorder
            gradient: Gradient {
              GradientStop { position: 0; color: Aero.hoverTop }
              GradientStop { position: 1; color: Aero.hoverBottom }
            }
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            textFormat: Text.PlainText
            color: modelData.enabled ? Aero.textPrimary : Aero.textDisabled
            font.family: Aero.fontFamily
            font.pixelSize: 12
          }

          HoverHandler { id: organizeHover; enabled: modelData.enabled }
          TapHandler {
            enabled: modelData.enabled
            onSingleTapped: {
              organizeMenu.close()
              root.invoke(String(modelData.key))
            }
          }

          Accessible.role: Accessible.MenuItem
          Accessible.name: modelData.label
        }
      }
    }
  }

  Controls.Popup {
    id: contextMenu
    width: 168
    padding: 1

    background: Rectangle {
      color: "#ffffff"
      border.width: 1
      border.color: "#a0a0a0"
    }

    contentItem: Column {
      spacing: 0

      Repeater {
        model: contextMenuItems()

        delegate: Item {
          required property var modelData
          width: 166
          height: 22

          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            visible: contextHover.hovered && modelData.enabled
            border.width: 1
            border.color: Aero.hoverBorder
            gradient: Gradient {
              GradientStop { position: 0; color: Aero.hoverTop }
              GradientStop { position: 1; color: Aero.hoverBottom }
            }
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            textFormat: Text.PlainText
            color: modelData.enabled ? Aero.textPrimary : Aero.textDisabled
            font.family: Aero.fontFamily
            font.pixelSize: 12
          }

          HoverHandler { id: contextHover; enabled: modelData.enabled }
          TapHandler {
            enabled: modelData.enabled
            onSingleTapped: {
              contextMenu.close()
              root.invoke(String(modelData.key))
            }
          }

          Accessible.role: Accessible.MenuItem
          Accessible.name: modelData.label
        }
      }
    }
  }

  Controls.Popup {
    id: renameDialog
    anchors.centerIn: Controls.Overlay.overlay
    width: Math.min(320, root.width - 40)
    modal: true
    padding: 12
    onOpened: renameField.forceActiveFocus()

    background: Rectangle {
      color: "#f0f0f0"
      border.width: 1
      border.color: "#8b97a3"
    }

    contentItem: Column {
      spacing: 8
      width: renameDialog.availableWidth

      Text {
        text: "Rename"
        textFormat: Text.PlainText
        color: Aero.textPrimary
        font.family: Aero.fontFamily
        font.pixelSize: 12
      }

      Controls.TextField {
        id: renameField
        width: parent.width
        text: root.renameDraft
        onTextChanged: root.renameDraft = text
        onAccepted: {
          renameDialog.close()
          root.renameEntry(root.renameRecord, root.renameDraft)
        }
      }

      Row {
        anchors.right: parent.right
        spacing: 6

        Repeater {
          model: [
            { key: "ok", label: "OK" },
            { key: "cancel", label: "Cancel" }
          ]

          delegate: Rectangle {
            required property var modelData
            width: 74
            height: 23
            radius: 3
            border.width: 1
            border.color: renameHover.hovered ? Aero.hoverSelectedBorder : "#a0a6ac"
            gradient: Gradient {
              GradientStop { position: 0; color: renameHover.hovered ? Aero.hoverTop : "#fdfdfd" }
              GradientStop { position: 1; color: renameHover.hovered ? Aero.hoverBottom : "#e6e8ea" }
            }

            Text {
              anchors.centerIn: parent
              text: modelData.label
              textFormat: Text.PlainText
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            HoverHandler { id: renameHover }
            TapHandler {
              onSingleTapped: {
                renameDialog.close()
                if (modelData.key === "ok") root.renameEntry(root.renameRecord, root.renameDraft)
              }
            }

            Accessible.role: Accessible.Button
            Accessible.name: modelData.label
          }
        }
      }
    }
  }

  Controls.Popup {
    id: emptyBinDialog
    anchors.centerIn: Controls.Overlay.overlay
    width: Math.min(360, root.width - 40)
    modal: true
    padding: 12

    background: Rectangle {
      color: "#f0f0f0"
      border.width: 1
      border.color: "#8b97a3"
    }

    contentItem: Column {
      spacing: 8
      width: emptyBinDialog.availableWidth

      Text {
        text: "Empty Recycle Bin"
        textFormat: Text.PlainText
        color: Aero.textPrimary
        font.family: Aero.fontFamily
        font.pixelSize: 12
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "This permanently removes regular files and empty folders in Trash, plus their .trashinfo records. Symlinks and non-empty trees stay refused."
        textFormat: Text.PlainText
        color: Aero.textSecondary
        font.family: Aero.fontFamily
        font.pixelSize: 12
      }

      Row {
        anchors.right: parent.right
        spacing: 6

        Repeater {
          model: [
            { key: "ok", label: "Empty Bin" },
            { key: "cancel", label: "Cancel" }
          ]

          delegate: Rectangle {
            required property var modelData
            width: 86
            height: 23
            radius: 3
            border.width: 1
            border.color: emptyHover.hovered ? Aero.hoverSelectedBorder : "#a0a6ac"
            gradient: Gradient {
              GradientStop { position: 0; color: emptyHover.hovered ? Aero.hoverTop : "#fdfdfd" }
              GradientStop { position: 1; color: emptyHover.hovered ? Aero.hoverBottom : "#e6e8ea" }
            }

            Text {
              anchors.centerIn: parent
              text: modelData.label
              textFormat: Text.PlainText
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            HoverHandler { id: emptyHover }
            TapHandler {
              onSingleTapped: {
                emptyBinDialog.close()
                if (modelData.key === "ok") root.sessionEmptyBin()
              }
            }

            Accessible.role: Accessible.Button
            Accessible.name: modelData.label
          }
        }
      }
    }
  }

  Controls.Popup {
    id: deleteDialog
    anchors.centerIn: Controls.Overlay.overlay
    width: Math.min(360, root.width - 40)
    modal: true
    padding: 12

    background: Rectangle {
      color: "#f0f0f0"
      border.width: 1
      border.color: "#8b97a3"
    }

    contentItem: Column {
      spacing: 8
      width: deleteDialog.availableWidth

      Text {
        text: "Permanently delete"
        textFormat: Text.PlainText
        color: Aero.textPrimary
        font.family: Aero.fontFamily
        font.pixelSize: 12
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "This permanently removes " + String(root.pendingDeleteRecord && root.pendingDeleteRecord.title || "this item") + " from this folder. It does not go to the Recycle Bin. Regular files and empty folders only. Trash stays on Empty Recycle Bin."
        textFormat: Text.PlainText
        color: Aero.textSecondary
        font.family: Aero.fontFamily
        font.pixelSize: 12
      }

      Row {
        anchors.right: parent.right
        spacing: 6

        Repeater {
          model: [
            { key: "ok", label: "Delete" },
            { key: "cancel", label: "Cancel" }
          ]

          delegate: Rectangle {
            required property var modelData
            width: 86
            height: 23
            radius: 3
            border.width: 1
            border.color: deleteHover.hovered ? Aero.hoverSelectedBorder : "#a0a6ac"
            gradient: Gradient {
              GradientStop { position: 0; color: deleteHover.hovered ? Aero.hoverTop : "#fdfdfd" }
              GradientStop { position: 1; color: deleteHover.hovered ? Aero.hoverBottom : "#e6e8ea" }
            }

            Text {
              anchors.centerIn: parent
              text: modelData.label
              textFormat: Text.PlainText
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            HoverHandler { id: deleteHover }
            TapHandler {
              onSingleTapped: {
                deleteDialog.close()
                if (modelData.key === "ok") root.sessionDeleteEntry(root.pendingDeleteRecord)
              }
            }

            Accessible.role: Accessible.Button
            Accessible.name: modelData.label
          }
        }
      }
    }
  }

  Controls.Popup {
    id: propertiesDialog
    anchors.centerIn: Controls.Overlay.overlay
    width: Math.min(420, root.width - 40)
    height: Math.min(460, root.height - 40)
    modal: true
    padding: 0

    background: Rectangle {
      color: "#f0f0f0"
      border.width: 1
      border.color: "#8b97a3"
    }

    contentItem: Item {
      Accessible.role: Accessible.Dialog
      Accessible.name: "Properties"

      Rectangle {
        id: propertiesTabs
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 26
        gradient: Gradient {
          GradientStop { position: 0; color: Aero.commandTop }
          GradientStop { position: 1; color: Aero.commandBottom }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.leftMargin: 8
          anchors.top: parent.top
          anchors.topMargin: 4
          width: generalTab.implicitWidth + 22
          height: parent.height - 4
          color: Aero.contentFill
          border.width: 1
          border.color: Aero.headerBorder

          Text {
            id: generalTab
            anchors.centerIn: parent
            text: "General"
            textFormat: Text.PlainText
            color: Aero.textPrimary
            font.family: Aero.fontFamily
            font.pixelSize: 12
          }
        }

        Item {
          visible: false
          readonly property string sessionControlReadOnlyMark: "SESSION CONTROL · READ-ONLY"
        }

        Rectangle {
          width: parent.width
          height: 1
          anchors.bottom: parent.bottom
          color: Aero.headerBorder
        }
      }

      Column {
        id: propertiesBody
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: propertiesTabs.bottom
        anchors.bottom: propertiesButtons.top
        anchors.margins: 12
        spacing: 8

        Text {
          width: parent.width
          visible: root.propertiesPhase !== "ready"
          text: root.propertiesPhase === "loading"
            ? "Reading Properties through this session."
            : (root.propertiesMessage !== "" ? root.propertiesMessage : "Select a file or folder to view Properties through this session.")
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.propertiesPhase === "failed" ? Aero.errorBorder : Aero.textSecondary
          font.family: Aero.fontFamily
          font.pixelSize: 12
        }

        Repeater {
          model: root.propertiesPhase === "ready" ? FilesModel.sessionPropertiesRows(root.propertiesResult) : []

          delegate: Row {
            required property var modelData
            width: propertiesBody.width
            spacing: 10

            Text {
              width: 110
              text: modelData.label
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: Aero.textSecondary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            Text {
              width: parent.width - 120
              text: modelData.value
              textFormat: Text.PlainText
              wrapMode: Text.WrapAnywhere
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }
          }
        }

        Text {
          width: parent.width
          text: "Read-only. Files does not invent a Fabric SHELL LIVE Properties writer."
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: Aero.textDisabled
          font.family: Aero.fontFamily
          font.pixelSize: 11
        }
      }

      Row {
        id: propertiesButtons
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
        spacing: 6

        Repeater {
          model: ["OK", "Cancel"]

          delegate: Rectangle {
            required property var modelData
            width: 74
            height: 23
            radius: 3
            border.width: 1
            border.color: dialogHover.hovered ? Aero.hoverSelectedBorder : "#a0a6ac"
            gradient: Gradient {
              GradientStop { position: 0; color: dialogHover.hovered ? Aero.hoverTop : "#fdfdfd" }
              GradientStop { position: 1; color: dialogHover.hovered ? Aero.hoverBottom : "#e6e8ea" }
            }

            Text {
              anchors.centerIn: parent
              text: modelData
              textFormat: Text.PlainText
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            HoverHandler { id: dialogHover }
            TapHandler { onSingleTapped: propertiesDialog.close() }

            Accessible.role: Accessible.Button
            Accessible.name: modelData
          }
        }
      }
    }
  }

  Controls.Popup {
    id: smbDialog
    anchors.centerIn: Controls.Overlay.overlay
    width: Math.min(360, root.width - 40)
    modal: true
    padding: 12
    onOpened: smbHostField.forceActiveFocus()

    background: Rectangle {
      color: "#f0f0f0"
      border.width: 1
      border.color: "#8b97a3"
    }

    contentItem: Column {
      spacing: 8
      width: smbDialog.availableWidth

      Row {
        width: parent.width

        Text {
          text: "Connect to Server"
          textFormat: Text.PlainText
          color: Aero.textPrimary
          font.family: Aero.fontFamily
          font.pixelSize: 12
        }

        Item { width: 12; height: 1 }

        Item {
          visible: false
          readonly property string sessionControlMark: "SESSION CONTROL"
        }
      }

      Text {
        width: parent.width
        text: "Guest or public SMB share only. This session leftover does not invent password vault or keyring UI."
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Aero.textSecondary
        font.family: Aero.fontFamily
        font.pixelSize: 11
      }

      Text {
        text: "Host"
        textFormat: Text.PlainText
        color: Aero.textSecondary
        font.family: Aero.fontFamily
        font.pixelSize: 11
      }

      Controls.TextField {
        id: smbHostField
        width: parent.width
        text: root.smbHostDraft
        onTextChanged: root.smbHostDraft = text
        onAccepted: smbShareField.forceActiveFocus()
      }

      Text {
        text: "Share"
        textFormat: Text.PlainText
        color: Aero.textSecondary
        font.family: Aero.fontFamily
        font.pixelSize: 11
      }

      Controls.TextField {
        id: smbShareField
        width: parent.width
        text: root.smbShareDraft
        onTextChanged: root.smbShareDraft = text
        onAccepted: root.sessionConnectShare()
      }

      Row {
        anchors.right: parent.right
        spacing: 6

        Repeater {
          model: [
            { key: "connect", label: "Connect" },
            { key: "cancel", label: "Cancel" }
          ]

          delegate: Rectangle {
            required property var modelData
            width: 74
            height: 23
            radius: 3
            border.width: 1
            border.color: smbHover.hovered ? Aero.hoverSelectedBorder : "#a0a6ac"
            gradient: Gradient {
              GradientStop { position: 0; color: smbHover.hovered ? Aero.hoverTop : "#fdfdfd" }
              GradientStop { position: 1; color: smbHover.hovered ? Aero.hoverBottom : "#e6e8ea" }
            }

            Text {
              anchors.centerIn: parent
              text: modelData.label
              textFormat: Text.PlainText
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            HoverHandler { id: smbHover }
            TapHandler {
              onSingleTapped: {
                if (modelData.key === "connect") root.sessionConnectShare()
                else smbDialog.close()
              }
            }

            Accessible.role: Accessible.Button
            Accessible.name: modelData.label
          }
        }
      }
    }
  }
}
