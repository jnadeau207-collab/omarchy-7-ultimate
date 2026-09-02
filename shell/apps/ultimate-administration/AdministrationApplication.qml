import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import qs.apps.shared as Shared
import "." as AdministrationComponents

import "AdministrationModel.js" as AdministrationModel

Item {
  id: root

  property var host: null
  property var controller: null
  property var queryState: AdministrationModel.baseState(AdministrationModel.OVERVIEW_ROUTE, {}, "offline")
  readonly property var productProfile: host && host.productProfile ? host.productProfile : null

  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property var visibleRoutes: filteredRoutes(navigation.query)
  readonly property bool queryBusy: queryState.phase === "catalog-loading" || queryState.phase === "loading"
  readonly property bool overviewVisible: queryState.phase === "overview"
  readonly property bool canRetry: !queryBusy && [
    "offline", "missing", "unavailable", "degraded", "contract-mismatch", "denied", "interrupted", "stale", "failed"
  ].indexOf(queryState.phase) >= 0
  readonly property bool domainVisible: queryState.query && queryState.query.providerId !== ""
  readonly property int recordColumns: contentScroll.availableWidth >= 980 ? 2 : 1

  property string operationStage: ""
  property string operationRequestId: ""
  property string operationId: ""
  property string operationMessage: ""
  property string operationTargetId: ""
  readonly property bool operationBusy: operationStage !== ""
  readonly property bool terminationAvailable: queryState.query
    && String(queryState.query.providerId || "") === "process.provider"
    && queryState.operationAvailable === true
  readonly property bool terminationAuthorized: false
  property var pendingEndTaskRecord: null
  readonly property var endTaskConfirm: AdministrationModel.endTaskConfirmCopy()

  function endTask(record) {
    if (!host || operationBusy || !record) return
    if (!AdministrationModel.endTaskPreflightArguments(record)) return
    root.pendingEndTaskRecord = record
  }

  function cancelEndTaskConfirm() {
    root.pendingEndTaskRecord = null
  }

  function confirmEndTask() {
    var record = root.pendingEndTaskRecord
    root.pendingEndTaskRecord = null
    if (!host || operationBusy || !record) return
    var request = AdministrationModel.endTaskPreflightRequest(record, Date.now())
    if (!request) return
    root.operationTargetId = String(request.arguments.resourceId)
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationRequestId = host.requestFabric("operation.preflight", request)
    if (root.operationRequestId === "") root.resetOperation("Administration could not reach the operation service.")
  }

  function resetOperation(message) {
    root.operationStage = ""
    root.operationRequestId = ""
    root.operationId = ""
    root.operationTargetId = ""
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
      root.resetOperation(String(result.status || "") === "succeeded"
        ? "The task was ended."
        : "Ending the task finished as " + String(result.status || "unknown") + ".")
      if (root.controller) root.controller.refresh()
    }
  }
  readonly property int overviewColumns: contentScroll.availableWidth >= 1120 ? 3
    : contentScroll.availableWidth >= 700 ? 2 : 1

  focus: true

  function filteredRoutes(query) {
    if (!host || !host.routeCatalog || !Array.isArray(host.routeCatalog.routes)) return []
    var needle = String(query || "").toLowerCase().trim()
    if (needle === "") return host.routeCatalog.routes
    return host.routeCatalog.routes.filter(function(route) {
      var haystack = [route.title, route.description, route.section].concat(route.keywords || []).join(" ").toLowerCase()
      return haystack.indexOf(needle) >= 0
    })
  }

  function currentArguments() {
    if (!host || !host.currentArguments) return {}
    return host.currentArguments
  }

  function ensureController() {
    if (controller) return
    controller = AdministrationModel.createController({
      send: function(method, parameters) {
        return root.host ? root.host.requestFabric(method, parameters) : ""
      },
      cancel: function(requestId) {
        if (!root.host || typeof root.host.cancelFabric !== "function") return false
        return root.host.cancelFabric(requestId)
      },
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
    controller.activate(host.currentRoute || AdministrationModel.OVERVIEW_ROUTE, currentArguments())
    controller.setConnected(host.fabricReady)
  }

  function retryState() {
    if (!controller || !host) return
    if (host.fabricReady) controller.refresh()
    else host.retryFabric()
  }

  function statusBorderColor() {
    if (queryState.phase === "failed" || queryState.phase === "denied" || queryState.phase === "contract-mismatch")
      return Tokens.state.danger
    if (queryState.phase === "ready" || queryState.phase === "empty" || queryState.phase === "overview")
      return Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
    return Tokens.state.warning
  }

  onHostChanged: synchronizeHost()

  Component.onCompleted: ensureController()

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_F5 || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_R)) {
      root.retryState()
      event.accepted = true
    }
  }

  Timer {
    id: staleTimer
    interval: 9000
    repeat: false
    onTriggered: {
      if (root.controller && root.queryState.requestId !== "") root.controller.markStale(root.queryState.requestId)
    }
  }

  Connections {
    target: root.host
    enabled: root.host !== null

    function onFabricConnectionReady(hello) {
      root.ensureController()
      root.controller.setConnected(true)
    }

    function onFabricReadyChanged() {
      root.ensureController()
      root.controller.setConnected(root.host.fabricReady)
    }

    function onRouteActivated(routeId, routeArguments, context) {
      root.ensureController()
      root.controller.activate(routeId, routeArguments || {})
    }

    function onFabricResult(requestId, result) {
      if (root.operationRequestId !== "" && requestId === root.operationRequestId) {
        root.advanceOperation(result || {})
        return
      }
      if (root.controller) root.controller.receiveResult(requestId, result)
    }

    function onFabricFailure(requestId, error) {
      if (root.operationRequestId !== "" && requestId === root.operationRequestId) {
        root.resetOperation(error && error.explanation ? String(error.explanation) : "The task could not be ended.")
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
      title: "Administration"
      semanticProfile: root.productProfile
      routes: root.visibleRoutes
      currentRoute: root.host ? root.host.currentRoute : ""
      Layout.preferredWidth: root.width < 900 ? 210 : root.width > 1450 ? 300 : 260
      Layout.minimumWidth: 196
      Layout.maximumWidth: 320
      Layout.fillHeight: true
      onRouteActivated: function(routeId) { root.host.navigate(routeId, {}) }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.width < 900 ? Style.space(14) : Style.space(20)
        spacing: Style.space(14)

        Shared.FabricStatusBanner {
          host: root.host
          semanticProfile: root.productProfile
          Layout.fillWidth: true
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(3)

            Text {
              textFormat: Text.PlainText
              text: Semantics.text(root.productProfile, root.currentRoute ? root.currentRoute.title : "Administration")
              color: Tokens.text.primary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.heading
              font.bold: true
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Text {
              textFormat: Text.PlainText
              text: Semantics.text(root.productProfile, root.currentRoute ? root.currentRoute.description : "The requested route is unavailable.")
              color: Tokens.text.secondary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              maximumLineCount: 4
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          Ui.Badge {
            text: AdministrationModel.phaseBadge(root.queryState)
            tone: AdministrationModel.phaseTone(root.queryState)
            semanticProfile: root.productProfile
            Layout.alignment: Qt.AlignTop
          }
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
              border.color: root.statusBorderColor()
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: root.queryState.phase === "failed" || root.queryState.phase === "denied" ||
                root.queryState.phase === "contract-mismatch" ? Accessible.AlertMessage : Accessible.Pane
              Accessible.name: Semantics.text(root.productProfile, AdministrationModel.stateTitle(root.queryState))
              Accessible.description: Semantics.text(root.productProfile, AdministrationModel.stateExplanation(root.queryState))

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
                    text: Semantics.text(root.productProfile, AdministrationModel.stateTitle(root.queryState))
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
                    tooltipText: root.queryState.phase === "offline"
                      ? "Reconnect to Fabric and read current provider state"
                      : "Refresh the provider catalog and current route"
                    semanticProfile: root.productProfile
                    focusable: true
                    bordered: true
                    onClicked: root.retryState()
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: Semantics.text(root.productProfile, AdministrationModel.stateExplanation(root.queryState))
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  maximumLineCount: 7
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Ui.ProgressBar {
                  visible: root.queryBusy
                  indeterminate: true
                  semanticProfile: root.productProfile
                  accessibleName: root.queryState.phase === "catalog-loading"
                    ? "Loading Administration provider catalog" : "Loading current Administration provider state"
                  Layout.fillWidth: true
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.domainVisible
                  text: AdministrationModel.provenance(root.queryState)
                  color: Tokens.text.disabled
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                  maximumLineCount: 4
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.queryState.selectedResourceId !== ""
                  text: Semantics.text(root.productProfile, "Exact resource") + ": " + AdministrationModel.clippedText(root.queryState.selectedResourceId, 180)
                  color: Tokens.text.disabled
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.queryState.error && root.queryState.error.detail
                  text: Semantics.text(root.productProfile, "Detail") + ": " + AdministrationModel.clippedText(root.queryState.error ? root.queryState.error.detail : "", 480)
                  color: Tokens.text.disabled
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                  maximumLineCount: 4
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                ColumnLayout {
                  visible: root.queryState.recoveryActions.length > 0
                  Layout.fillWidth: true
                  spacing: Style.space(3)

                  Text {
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile, "RECOVERY PATHS")
                    color: Tokens.state.warning
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Repeater {
                    model: root.queryState.recoveryActions

                    delegate: Text {
                      textFormat: Text.PlainText
                      required property var modelData

                      text: "\u2022 " + AdministrationModel.clippedText(modelData, 320)
                      color: Tokens.text.secondary
                      font.family: Tokens.typography.family
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.Wrap
                      maximumLineCount: 3
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                  }
                }
              }
            }

            GridLayout {
              visible: root.overviewVisible
              Layout.fillWidth: true
              columns: root.overviewColumns
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(10)

              Repeater {
                model: root.queryState.overviewCards

                delegate: Rectangle {
                  required property var modelData

                  Layout.fillWidth: true
                  implicitHeight: overviewCardColumn.implicitHeight + Style.space(24)
                  radius: Tokens.radius.medium
                  color: Tokens.surface.raised
                  border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
                  border.width: Tokens.accessibility.highContrast ? 2 : 1
                  Accessible.role: Accessible.Pane
                  Accessible.name: Semantics.text(root.productProfile, modelData.title) + ". " + Semantics.text(root.productProfile, modelData.status)
                  Accessible.description: Semantics.text(root.productProfile, modelData.detail)

                  ColumnLayout {
                    id: overviewCardColumn
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(7)

                    RowLayout {
                      Layout.fillWidth: true
                      spacing: Style.space(8)

                      Text {
                        textFormat: Text.PlainText
                        text: Semantics.text(root.productProfile, modelData.title)
                        color: Tokens.text.primary
                        font.family: Tokens.typography.family
                        font.pixelSize: Style.font.title
                        font.bold: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                      }

                      Ui.Badge {
                        text: String(modelData.status).toUpperCase()
                        tone: modelData.tone
                        semanticProfile: root.productProfile
                        Layout.alignment: Qt.AlignTop
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: Semantics.text(root.productProfile, modelData.detail)
                      color: Tokens.text.secondary
                      font.family: Tokens.typography.family
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WordWrap
                      maximumLineCount: 5
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.providerId
                      color: Tokens.text.disabled
                      font.family: Tokens.typography.family
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.Wrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Ui.Button {
                      text: Semantics.text(root.productProfile, "Open") + " " + Semantics.text(root.productProfile, modelData.title)
                      tooltipText: "Open the read-only " + modelData.title + " Administration route"
                      semanticProfile: root.productProfile
                      accessibleDescription: Semantics.text(root.productProfile, modelData.status) + ". " + Semantics.text(root.productProfile, modelData.detail)
                      focusable: true
                      bordered: true
                      leftAlign: true
                      Layout.fillWidth: true
                      onClicked: root.host.navigate(modelData.routeId, {})
                    }
                  }
                }
              }
            }

            Rectangle {
              visible: root.domainVisible && !root.queryBusy
              Layout.fillWidth: true
              implicitHeight: coverageColumn.implicitHeight + Style.space(24)
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: Accessible.Pane
              Accessible.name: Semantics.text(root.productProfile, "Administration coverage and unavailable changes")
              Accessible.description: root.queryState.query ? Semantics.text(root.productProfile, root.queryState.query.coverage) : ""

              ColumnLayout {
                id: coverageColumn
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(6)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile, "Coverage")
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Badge {
                    text: root.terminationAuthorized ? "LIVE CONTROL" : "CHANGES UNAVAILABLE"
                    tone: root.terminationAuthorized ? "info" : "warning"
                    semanticProfile: root.productProfile
                    Layout.alignment: Qt.AlignTop
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.queryState.query ? Semantics.text(root.productProfile, root.queryState.query.coverage) : ""
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  maximumLineCount: 6
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.queryState.operationActions.length > 0
                  text: Semantics.text(root.productProfile, "Declared provider operations") + ": " +
                    root.queryState.operationActions.join(", ") + ". " +
                    (root.terminationAuthorized
                      ? Semantics.text(root.productProfile, "Ending a task runs through preflight, approval, and the durable coordinator as this user.")
                      : Semantics.text(root.productProfile, "Ending a task is declared consequential, and the shell principal cannot hold that authorization."))
                  color: Tokens.text.disabled
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                  maximumLineCount: 5
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
              }
            }

            GridLayout {
              visible: root.queryState.records.length > 0
              Layout.fillWidth: true
              columns: root.recordColumns
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(10)

              Repeater {
                model: root.queryState.records

                delegate: AdministrationComponents.AdministrationRecordCard {
                  required property var modelData

                  record: modelData
                  semanticProfile: root.productProfile
                  selected: root.queryState.selectedResourceId !== "" &&
                    root.queryState.selectedResourceId === modelData.id
                  endTaskEnabled: root.terminationAuthorized && String(modelData.kind || "") === "process"
                  endTaskBusy: root.operationBusy && root.operationTargetId === modelData.id
                  onEndTaskRequested: function(record) { root.endTask(record) }
                }
              }
            }

            Ui.EmptyState {
              visible: root.queryState.phase === "empty"
              semanticProfile: root.productProfile
              Layout.fillWidth: true
              Layout.topMargin: Style.space(16)
              title: root.queryState.selectedMissing ? "Requested resource is absent" : "No resources reported"
              message: root.queryState.selectedMissing
                ? "The current typed inventory contains no exact match for this stable resource link."
                : "The provider returned a valid current inventory with no resources."
            }

            Rectangle {
              visible: root.queryState.clipped
              Layout.fillWidth: true
              implicitHeight: clippedNotice.implicitHeight + Style.space(20)
              radius: Tokens.radius.medium
              color: Tokens.surface.base
              border.color: Tokens.state.warning
              border.width: 1
              Accessible.role: Accessible.AlertMessage
              Accessible.name: clippedNotice.text

              Text {
                textFormat: Text.PlainText
                id: clippedNotice
                anchors.fill: parent
                anchors.margins: Style.space(10)
                text: Semantics.text(root.productProfile, "Display bound reached at") + " " + AdministrationModel.MAX_VISIBLE_RECORDS +
                  Semantics.text(root.productProfile, " records. ") +
                  root.queryState.totalRecords +
                  Semantics.text(root.productProfile, " records were reported; use an exact resource deep link for a narrower view.")
                color: Tokens.text.secondary
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Text {
              visible: !root.queryBusy
              textFormat: Text.PlainText
              text: Semantics.text(root.productProfile, "Read-only Fabric provider state \u00b7 no direct commands, mutation, preflight, approval, or execution authority")
              color: Tokens.text.disabled
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              Layout.topMargin: Style.space(6)
              Layout.bottomMargin: Style.space(12)
            }
          }
        }
      }
    }
  }

  Ui.OperationDialog {
    id: endTaskConfirmDialog
    anchors.fill: parent
    z: 20
    opened: root.pendingEndTaskRecord !== null
    semanticProfile: root.productProfile
    stateId: "failure"
    toneOverride: "danger"
    destructive: true
    title: root.endTaskConfirm.title
    message: root.endTaskConfirm.message
    recoveryText: root.endTaskConfirm.recovery
    primaryText: root.endTaskConfirm.confirm
    cancelText: root.endTaskConfirm.cancel
    onCanceled: root.cancelEndTaskConfirm()
    onConfirmed: root.confirmEndTask()
  }
}
