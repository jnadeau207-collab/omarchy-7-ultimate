import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import qs.apps.shared as Shared

import "FilesModel.js" as FilesModel
import "." as Files

Item {
  id: root
  property var host: null
  property var controller: null
  property var queryState: FilesModel.baseState("files.overview", {}, "offline")

  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property var visibleRoutes: filteredRoutes(navigation.query)
  readonly property bool busy: queryState.phase === "catalog-loading" || queryState.phase === "loading"
  readonly property bool canRetry: !busy && ["offline", "missing", "unavailable", "denied", "interrupted", "stale", "failed"].indexOf(queryState.phase) >= 0
  readonly property bool showRecords: ["ready", "available", "degraded", "partial", "empty"].indexOf(queryState.phase) >= 0
  readonly property int recordColumns: contentScroll.availableWidth >= 1050 ? 2 : 1

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

  focus: true

  function filteredRoutes(query) {
    if (!host || !host.routeCatalog || !Array.isArray(host.routeCatalog.routes)) return []
    var needle = String(query || "").toLowerCase().trim()
    if (needle === "") return host.routeCatalog.routes
    return host.routeCatalog.routes.filter(function(route) {
      return [route.title, route.description, route.section].concat(route.keywords || []).join(" ").toLowerCase().indexOf(needle) >= 0
    })
  }

  function ensureController() {
    if (controller) return
    controller = FilesModel.createController({
      send: function(method, parameters) { return root.host ? root.host.requestFabric(method, parameters) : "" },
      cancel: function(requestId) { return root.host ? root.host.cancelFabric(requestId) : false },
      onState: function(state) {
        root.queryState = state
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

  function runSearch() {
    if (!host) return
    host.navigate("files.search", searchInput.text === "" ? {} : { query: searchInput.text })
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
      arguments: { locationId: root.createLocationId, parentRelativePath: "", name: root.operationName },
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
      var tail = root.operationKind === "trash" ? " to Trash." : "."
      root.resetOperation(succeeded
        ? verb + root.operationName + tail
        : gerund + root.operationName + " ended as " + String(result.status || "unknown") + ".")
      if (succeeded && root.operationKind === "create") createInput.text = ""
      if (root.controller) root.controller.refresh()
    }
  }

  function statusBorder() {
    if (["failed", "denied", "unavailable"].indexOf(queryState.phase) >= 0) return Tokens.state.danger
    if (["ready", "available", "empty"].indexOf(queryState.phase) >= 0) return Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
    return Tokens.state.warning
  }

  onHostChanged: synchronizeHost()
  Component.onCompleted: ensureController()

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_F5 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R)) { root.retryState(); event.accepted = true }
    else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) { searchInput.forceActiveFocus(); event.accepted = true }
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
      if (routeId === "files.search") searchInput.text = routeArguments && routeArguments.query ? String(routeArguments.query) : ""
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

  RowLayout {
    anchors.fill: parent
    spacing: 0

    Shared.ApplicationNavigation {
      id: navigation
      title: "Files"
      routes: root.visibleRoutes
      currentRoute: root.host ? root.host.currentRoute : ""
      Layout.preferredWidth: root.width < 860 ? 188 : root.width > 1450 ? 300 : 252
      Layout.minimumWidth: 176
      Layout.maximumWidth: 320
      Layout.fillHeight: true
      onRouteActivated: function(routeId) { root.host.navigate(routeId, {}) }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.width < 900 ? Style.space(12) : Style.space(20)
        spacing: Style.space(12)

        Shared.FabricStatusBanner { host: root.host; Layout.fillWidth: true }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(3)
            Text {
              textFormat: Text.PlainText
              text: root.currentRoute ? root.currentRoute.title : "Files"
              color: Tokens.text.primary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.heading
              font.bold: true
              wrapMode: Text.WrapAnywhere
              maximumLineCount: 3
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            Text {
              textFormat: Text.PlainText
              text: root.currentRoute ? root.currentRoute.description : "The requested Files route is unavailable."
              color: Tokens.text.secondary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              maximumLineCount: 4
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
          Ui.Badge { text: String(root.queryState.phase || "offline").toUpperCase(); tone: FilesModel.phaseTone(root.queryState); Layout.alignment: Qt.AlignTop }
        }

        RowLayout {
          visible: root.host && root.host.currentRoute === "files.search"
          Layout.fillWidth: true
          spacing: Style.space(8)
          Ui.SearchBox {
            id: searchInput
            Layout.fillWidth: true
            semanticPlaceholderText: "Search trusted file metadata"
            accessibleName: "Files search query"
            onAccepted: root.runSearch()
            onCleared: root.host.navigate("files.search", {})
          }
          Ui.Button {
            text: "Search"
            focusable: true
            bordered: true
            accessibleDescription: "Run a bounded files.provider metadata search"
            onClicked: root.runSearch()
          }
        }

        RowLayout {
          visible: root.createVisible
          Layout.fillWidth: true
          spacing: Style.space(8)
          Ui.TextField {
            id: createInput
            Layout.fillWidth: true
            enabled: root.createEnabled
            semanticPlaceholderText: "New folder name"
            accessibleName: "New folder name"
            accessibleDescription: "Name for a folder created in this location through the Fabric operation plane"
            onAccepted: root.createFolder(createInput.text)
          }
          Ui.Button {
            text: root.operationBusy ? "Creating…" : "New folder"
            focusable: true
            bordered: true
            enabled: root.createEnabled
            accessibleDescription: "Create a folder in this location through files.directory.create"
            onClicked: root.createFolder(createInput.text)
          }
        }

        Text {
          visible: root.operationMessage !== ""
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.operationMessage
          color: Tokens.text.secondary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
          Accessible.role: Accessible.StaticText
          Accessible.name: root.operationMessage
        }

        Controls.ScrollView {
          id: contentScroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: availableWidth
          clip: true
          Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

          ColumnLayout {
            width: contentScroll.availableWidth
            spacing: Style.space(12)

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: statusColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.large
              color: Tokens.surface.base
              border.color: root.statusBorder()
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: ["failed", "denied", "unavailable"].indexOf(root.queryState.phase) >= 0 ? Accessible.AlertMessage : Accessible.Pane
              Accessible.name: FilesModel.stateTitle(root.queryState)
              Accessible.description: FilesModel.stateExplanation(root.queryState)

              ColumnLayout {
                id: statusColumn
                anchors.fill: parent
                anchors.margins: Style.space(14)
                spacing: Style.space(8)
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(10)
                  Text {
                    textFormat: Text.PlainText
                    text: FilesModel.stateTitle(root.queryState)
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                  Ui.Button {
                    visible: root.canRetry
                    text: root.queryState.phase === "offline" ? "Reconnect" : "Retry"
                    focusable: true
                    bordered: true
                    onClicked: root.retryState()
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  text: FilesModel.stateExplanation(root.queryState)
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  maximumLineCount: 8
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
                Text {
                  textFormat: Text.PlainText
                  visible: root.queryState.revision !== ""
                  text: "Revision " + root.queryState.revision + " \u00b7 generation " + root.queryState.providerGeneration + " \u00b7 " + root.queryState.totalRecords + " source record" + (root.queryState.totalRecords === 1 ? "" : "s")
                  color: Tokens.text.disabled
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WrapAnywhere
                  maximumLineCount: 3
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
              }
            }

            GridLayout {
              visible: root.showRecords && root.queryState.records.length > 0
              Layout.fillWidth: true
              columns: root.recordColumns
              columnSpacing: Style.space(12)
              rowSpacing: Style.space(12)
              Repeater {
                model: root.queryState.records
                delegate: Files.FilesRecordCard {
                  required property var modelData
                  record: modelData
                  selected: root.queryState.entityId !== "" && modelData.id === root.queryState.entityId
                  trashable: root.createLocationId !== "" && String(modelData.kind || "") === "entry" && String(modelData.status || "") !== "symlink"
                  trashBusy: root.operationBusy
                  restorable: root.restoreVisible && String(modelData.kind || "") === "entry"
                  onTrashRequested: root.trashEntry(modelData)
                  onRestoreRequested: root.restoreEntry(modelData)
                  Layout.fillWidth: true
                  Layout.columnSpan: 1
                }
              }
            }

            Ui.EmptyState {
              visible: root.showRecords && root.queryState.records.length === 0
              Layout.fillWidth: true
              title: FilesModel.isIdleSearch(root.queryState) ? "Type a search query" : root.queryState.selectedMissing ? "Deep-linked item not found" : "No records in this route"
              message: FilesModel.isIdleSearch(root.queryState) ? "Enter a query to search trusted file names and relative paths. File contents are never read." : root.queryState.selectedMissing ? "This exact identity is absent from the displayed provider revision." : "The provider returned a valid empty result."
            }

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: boundaryText.implicitHeight + Style.space(20)
              radius: Tokens.radius.medium
              color: Qt.rgba(Tokens.state.warning.r, Tokens.state.warning.g, Tokens.state.warning.b, 0.08)
              border.color: Tokens.state.warning
              border.width: 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Files mutation boundary"
              Text {
                id: boundaryText
                anchors.fill: parent
                anchors.margins: Style.space(10)
                text: "Files v0 \u00b7 directory creation runs through the durable operation service as this user. Rename, trash, restore, mount, and disconnect remain unavailable. File contents are never read by this surface."
                color: Tokens.text.secondary
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }
    }
  }
}
