import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

import "FilesModel.js" as FilesModel
import "ExplorerTheme.js" as Aero
import "." as Files

Item {
  id: root
  property var host: null
  property var controller: null
  property var queryState: FilesModel.baseState("files.overview", {}, "offline")

  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property bool busy: queryState.phase === "catalog-loading" || queryState.phase === "loading"
  readonly property bool canRetry: !busy && ["offline", "missing", "unavailable", "denied", "interrupted", "stale", "failed"].indexOf(queryState.phase) >= 0
  readonly property bool showRecords: ["ready", "available", "degraded", "partial", "empty"].indexOf(queryState.phase) >= 0
  readonly property bool healthy: ["ready", "available", "empty"].indexOf(queryState.phase) >= 0

  property string operationStage: ""
  property string operationRequestId: ""
  property string operationId: ""
  property string operationMessage: ""
  property string operationName: ""
  property string operationKind: ""
  readonly property bool operationBusy: operationStage !== ""
  readonly property string createLocationId: FilesModel.createLocationForRoute(host ? host.currentRoute : "")
  readonly property bool createVisible: createLocationId !== ""
  readonly property bool restoreVisible: FilesModel.isTrashRoute(host ? host.currentRoute : "")
  readonly property bool createEnabled: createVisible && !operationBusy && host !== null && host.fabricReady

  property var history: []
  property int historyIndex: -1
  property bool traversing: false
  property string viewMode: "details"
  property string sortColumn: "name"
  property bool sortAscending: true
  property string selectedId: ""
  property var selectedRecord: null

  readonly property string accountName: {
    var home = String(Tokens.home || "")
    var cut = home.lastIndexOf("/")
    var leaf = cut >= 0 ? home.slice(cut + 1) : home
    return leaf === "" ? "Home" : leaf
  }

  readonly property string relativePath: String(queryState.relativePath || "")
  readonly property string routeTitle: currentRoute ? String(currentRoute.title) : "Files"
  readonly property var crumbs: FilesModel.breadcrumbFor(routeTitle, relativePath)
  readonly property bool canBack: historyIndex > 0
  readonly property bool canForward: historyIndex >= 0 && historyIndex < history.length - 1

  readonly property var locationRoutes: ({
    "files.location.desktop": "files.desktop",
    "files.location.documents": "files.documents",
    "files.location.downloads": "files.downloads",
    "files.location.pictures": "files.pictures",
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
  }

  function retryState() {
    if (!controller || !host) return
    if (host.fabricReady) controller.refresh()
    else host.retryFabric()
  }

  function recordHistory(routeId, path) {
    if (root.traversing) return
    var entry = { routeId: String(routeId), relativePath: String(path || "") }
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
        details: mount.details, kind: "mount", status: mount.status, subtitle: mount.subtitle, tone: mount.tone
      })
    }
    return shaped
  }

  function openRecord(record) {
    if (!record || !host) return
    if (record.targetRoute) { host.navigate(record.targetRoute, {}); return }
    if (record.entryKind === "directory" && record.kind === "entry") {
      openPath(FilesModel.childRelativePath(root.relativePath, record.title))
    }
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

  function restoreEntry(record) {
    if (!host || operationBusy || !restoreVisible) return
    if (!record || String(record.kind || "") !== "entry") return
    root.operationName = String(record.title || "this entry")
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationKind = "restore"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "files.provider",
      action: "trash.restore",
      arguments: { entryId: String(record.id) },
      idempotencyKey: "files.trash.restore." + String(record.id)
    })
    if (root.operationRequestId === "") root.resetOperation("Files could not reach the operation service.")
  }

  function trashEntry(record) {
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
      var verb = root.operationKind === "trash" ? "Moved " : root.operationKind === "restore" ? "Restored " : "Created "
      var gerund = root.operationKind === "trash" ? "Moving " : root.operationKind === "restore" ? "Restoring " : "Creating "
      var tail = root.operationKind === "trash" ? " to the Recycle Bin." : "."
      root.resetOperation(succeeded
        ? verb + root.operationName + tail
        : gerund + root.operationName + " ended as " + String(result.status || "unknown") + ".")
      if (root.controller) root.controller.refresh()
    }
  }

  function commandActions() {
    var list = [{ key: "organize", label: "Organize", dropdown: true, enabled: true }]
    if (root.createVisible) list.push({ key: "new-folder", label: "New folder", dropdown: false, enabled: root.createEnabled })
    if (root.restoreVisible) {
      list.push({
        key: "restore", label: "Restore this item", dropdown: false,
        enabled: !root.operationBusy && root.selectedRecord !== null && String(root.selectedRecord.kind || "") === "entry"
      })
    } else if (root.createVisible) {
      list.push({
        key: "delete", label: "Delete", dropdown: false,
        enabled: !root.operationBusy && root.selectedRecord !== null && String(root.selectedRecord.kind || "") === "entry" && String(root.selectedRecord.status || "") !== "symlink"
      })
    }
    if (root.selectedRecord !== null) list.push({ key: "properties", label: "Properties", dropdown: false, enabled: true })
    return list
  }

  function invoke(key) {
    if (key === "organize") { organizeMenu.visible ? organizeMenu.close() : organizeMenu.open(); return }
    if (key === "new-folder") { root.createFolder(root.nextFolderName()); return }
    if (key === "delete") { root.trashEntry(root.selectedRecord); return }
    if (key === "restore") { root.restoreEntry(root.selectedRecord); return }
    if (key === "properties") { propertiesDialog.open(); return }
    if (key === "refresh") { root.retryState(); return }
    if (key === "open") { root.openRecord(root.selectedRecord); return }
  }

  onHostChanged: synchronizeHost()
  Component.onCompleted: { ensureController(); focusTimer.restart() }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_F5 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R)) { root.retryState(); event.accepted = true }
    else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) { addressBar.forceActiveFocus(); event.accepted = true }
    else if (event.key === Qt.Key_Backspace) { root.goUp(); event.accepted = true }
    else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Left) { root.goBack(); event.accepted = true }
    else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Right) { root.goForward(); event.accepted = true }
    else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Up) { root.goUp(); event.accepted = true }
    else if (event.key === Qt.Key_Delete) { root.trashEntry(root.selectedRecord); event.accepted = true }
  }

  Timer {
    id: focusTimer
    interval: 60
    repeat: false
    onTriggered: itemView.forceActiveFocus()
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

  Rectangle {
    anchors.fill: parent
    color: Aero.contentFill
  }

  Files.ExplorerAddressBar {
    id: addressBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    crumbs: root.crumbs
    locationIcon: root.currentRoute && root.currentRoute.id === "files.this-pc" ? "computer"
      : root.currentRoute && root.currentRoute.id === "files.network" ? "network"
      : root.currentRoute && root.currentRoute.id === "files.trash" ? "trash" : "directory"
    searchPlaceholder: "Search " + root.routeTitle
    searchText: String(root.queryState.searchQuery || "")
    canBack: root.canBack
    canForward: root.canForward
    busy: root.busy
    onBackRequested: root.goBack()
    onForwardRequested: root.goForward()
    onCrumbActivated: function(path) { root.openPath(path) }
    onRefreshRequested: root.retryState()
    onSearchAccepted: function(text) { root.runSearch(text) }
  }

  Files.ExplorerCommandBar {
    id: commandBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: addressBar.bottom
    actions: root.commandActions()
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
    visible: !root.healthy || root.operationMessage !== ""
    color: root.healthy ? Aero.warningFill : (["failed", "denied", "unavailable"].indexOf(root.queryState.phase) >= 0 ? Aero.errorFill : Aero.warningFill)

    Rectangle {
      width: parent.width
      height: 1
      y: parent.height - 1
      color: root.healthy ? Aero.warningBorder : Aero.errorBorder
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.right: retryLink.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: root.operationMessage !== "" ? root.operationMessage : FilesModel.stateExplanation(root.queryState)
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
      text: root.queryState.phase === "offline" ? "Reconnect" : "Try again"
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
    Accessible.name: notice.visible ? FilesModel.stateTitle(root.queryState) : ""
  }

  Files.ExplorerNavigationPane {
    id: navigationPane
    anchors.left: parent.left
    anchors.top: notice.bottom
    anchors.bottom: detailsPane.top
    width: root.width < 900 ? 150 : 190
    accountName: root.accountName
    currentRoute: root.host ? root.host.currentRoute : ""
    mounts: FilesModel.explorerMounts(root.queryState.records)
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

  Files.ExplorerItemView {
    id: itemView
    anchors.left: splitter.right
    anchors.right: parent.right
    anchors.top: notice.bottom
    anchors.bottom: detailsPane.top
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
    visible: root.showRecords && itemView.count === 0
    text: FilesModel.isIdleSearch(root.queryState) ? "Type in the search box to begin."
      : root.queryState.selectedMissing ? "That item is no longer in this folder."
      : "This folder is empty."
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
    itemCount: itemView.count
    locationLabel: root.routeTitle
    boundary: "File contents are never read by this surface."
    folderPath: {
      if (!root.selectedRecord || String(root.selectedRecord.kind || "") !== "entry") return ""
      var parent = FilesModel.parentRelativePath(String(root.selectedRecord.relativePath || ""))
      return parent === "" ? root.routeTitle : root.routeTitle + " › " + parent.split("/").join(" › ")
    }
  }

  Controls.Popup {
    id: organizeMenu
    x: 6
    y: addressBar.height + commandBar.height
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
        model: [
          { key: "new-folder", label: "New folder", enabled: root.createEnabled },
          { key: "delete", label: "Delete", enabled: root.createVisible && root.selectedRecord !== null && !root.operationBusy },
          { key: "restore", label: "Restore this item", enabled: root.restoreVisible && root.selectedRecord !== null && !root.operationBusy },
          { key: "refresh", label: "Refresh", enabled: true },
          { key: "properties", label: "Properties", enabled: root.selectedRecord !== null }
        ]

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
        model: [
          { key: "open", label: "Open", enabled: root.selectedRecord !== null },
          { key: "delete", label: "Delete", enabled: root.createVisible && root.selectedRecord !== null && !root.operationBusy },
          { key: "restore", label: "Restore", enabled: root.restoreVisible && root.selectedRecord !== null && !root.operationBusy },
          { key: "properties", label: "Properties", enabled: root.selectedRecord !== null }
        ]

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
    id: propertiesDialog
    anchors.centerIn: Controls.Overlay.overlay
    width: Math.min(420, root.width - 40)
    height: Math.min(360, root.height - 40)
    modal: true
    padding: 10

    background: Rectangle {
      color: "#f0f4f8"
      border.width: 1
      border.color: "#8ea0b2"
    }

    contentItem: Column {
      spacing: 8

      Text {
        text: root.selectedRecord ? root.selectedRecord.title + " Properties" : "Properties"
        textFormat: Text.PlainText
        color: Aero.textPrimary
        font.family: Aero.fontFamily
        font.pixelSize: 13
        font.bold: true
      }

      Loader {
        width: propertiesDialog.availableWidth
        active: propertiesDialog.visible && root.selectedRecord !== null

        sourceComponent: Files.FilesRecordCard {
          width: propertiesDialog.availableWidth
          record: root.selectedRecord
          selected: false
          trashable: false
          trashBusy: root.operationBusy
          restorable: false
        }
      }
    }
  }
}
