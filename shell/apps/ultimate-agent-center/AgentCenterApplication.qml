import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import qs.apps.shared as Shared

import "AgentCenterModel.js" as AgentCenterModel
import "." as AgentCenter

Item {
  id: root

  property var host: null
  property var controller: null
  property var queryState: AgentCenterModel.baseState("agent.overview", {}, "offline")
  readonly property var productProfile: host && host.productProfile ? host.productProfile : null

  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property var visibleRoutes: filteredRoutes(navigation.query)
  readonly property string entityType: host && host.currentArguments && host.currentArguments.entityType
    ? String(host.currentArguments.entityType) : ""
  readonly property string entityId: host && host.currentArguments && host.currentArguments.entityId
    ? String(host.currentArguments.entityId) : ""
  readonly property var overviewMetrics: AgentCenterModel.overviewMetrics(queryState.summary)
  readonly property bool queryBusy: queryState.phase === "loading"
  readonly property bool canRefresh: host && host.fabricReady && !queryBusy
  readonly property bool canMutate: host && host.fabricReady && !queryBusy &&
    !(root.controller && root.controller.activeWorkId)
  readonly property var contextSources: AgentCenterModel.CONTEXT_SOURCES
  readonly property bool canLoadMore: host && host.fabricReady && !queryBusy &&
    queryState.nextCursor !== null && !queryState.clipped

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
    return {
      entityType: root.entityType,
      entityId: root.entityId
    }
  }

  function ensureController() {
    if (root.controller) return
    root.controller = AgentCenterModel.createController({
      send: function(method, params) {
        return root.host ? root.host.requestFabric(method, params) : ""
      },
      cancel: function(requestId) {
        return root.host ? root.host.cancelFabric(requestId) : false
      },
      onState: function(state) {
        root.queryState = state
      }
    })
  }

  function synchronizeHost() {
    root.ensureController()
    if (!root.host) return
    root.controller.activate(root.host.currentRoute || "agent.overview", root.currentArguments())
    root.controller.setConnected(root.host.fabricReady)
  }

  function retryQuery() {
    if (!root.controller) return
    if (root.host && root.host.fabricReady) root.controller.refresh()
    else if (root.host) root.host.retryFabric()
  }

  function sendWork(method, params) {
    if (!root.controller || !root.canMutate) return
    root.controller.sendWork(method, params)
  }

  function createInspectTask() {
    sendWork(AgentCenterModel.WORK_METHODS.create, AgentCenterModel.inspectTaskCreateParams(Date.now()))
  }

  function captureContext(source) {
    sendWork(AgentCenterModel.WORK_METHODS.capture, AgentCenterModel.captureContextParams(source, Date.now()))
  }

  function runTaskAction(action, record) {
    if (!action || !record || !record.task) return
    var now = Date.now()
    if (action.id === "execute")
      sendWork(action.method, AgentCenterModel.executeRunParams(record.task.taskId, now))
    else if (action.id === "cancel" || action.id === "recover")
      sendWork(action.method, AgentCenterModel.taskRevisionParams(record.task.taskId, record.task.revision))
  }

  function summaryLine() {
    if (queryState.view === "agent.usage" && queryState.summary) {
      return String(queryState.summary.recordCount || 0) + " total usage records \u00b7 " +
        String(queryState.summary.costMicrounits || 0) + " cost microunits"
    }
    if (queryState.view === "agent.history" && queryState.summary)
      return "History is durably pruned through sequence " + String(queryState.summary.prunedThrough || 0) + "."
    return ""
  }

  onHostChanged: synchronizeHost()

  Component.onCompleted: ensureController()

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
      if (root.controller) root.controller.receiveResult(requestId, result)
    }

    function onFabricFailure(requestId, error) {
      if (root.controller) root.controller.receiveFailure(requestId, error)
    }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0

    Shared.ApplicationNavigation {
      id: navigation
      title: "Agent Center"
      semanticProfile: root.productProfile
      routes: root.visibleRoutes
      currentRoute: root.host ? root.host.currentRoute : ""
      Layout.preferredWidth: root.width < 920 ? 220 : 280
      Layout.minimumWidth: 200
      Layout.fillHeight: true
      onRouteActivated: function(routeId) { root.host.navigate(routeId, {}) }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(20)
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
              text: Semantics.text(root.productProfile, root.currentRoute ? root.currentRoute.title : "Agent Center")
              color: Tokens.text.primary
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.currentRoute ? root.currentRoute.description : "The requested route is unavailable."
              color: Tokens.text.secondary
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }
          }

          Ui.Badge {
            text: AgentCenterModel.phaseBadge(root.queryState)
            tone: AgentCenterModel.phaseTone(root.queryState)
            Layout.alignment: Qt.AlignTop
          }
        }

        Controls.ScrollView {
          id: queryScroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: availableWidth
          clip: true
          Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

          ColumnLayout {
            width: queryScroll.availableWidth
            spacing: Style.space(12)

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: statusColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.large
              color: Tokens.surface.base
              border.color: root.queryState.phase === "failed" || root.queryState.phase === "denied"
                ? Tokens.state.danger
                : root.queryState.phase === "ready" || root.queryState.phase === "empty"
                  ? Tokens.border.subtle : Tokens.state.warning
              border.width: 1
              Accessible.role: root.queryState.phase === "failed" || root.queryState.phase === "denied"
                ? Accessible.AlertMessage : Accessible.Pane
              Accessible.name: AgentCenterModel.stateTitle(root.queryState)
              Accessible.description: AgentCenterModel.stateExplanation(root.queryState)

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
                    text: AgentCenterModel.stateTitle(root.queryState)
                    color: Tokens.text.primary
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }

                  Ui.Button {
                    visible: root.canRefresh
                    text: "Refresh"
                    tooltipText: "Read the current bounded page again"
                    semanticProfile: root.productProfile
                    focusable: true
                    bordered: true
                    onClicked: root.retryQuery()
                  }

                  Ui.Button {
                    visible: root.canMutate && (root.queryState.view === "agent.overview" || root.queryState.view === "agent.tasks")
                    text: "Create inspect task"
                    tooltipText: "Create a durable system.info.read inspect task"
                    semanticProfile: root.productProfile
                    focusable: true
                    bordered: true
                    onClicked: root.createInspectTask()
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: AgentCenterModel.stateExplanation(root.queryState)
                  color: Tokens.text.secondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  maximumLineCount: 6
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Ui.ProgressBar {
                  visible: root.queryBusy
                  indeterminate: true
                  accessibleName: root.queryState.appending ? "Loading more managed-work records" : "Loading Agent Center view"
                  Layout.fillWidth: true
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.entityId !== ""
                  text: "Selected " + root.entityType + ": " + AgentCenterModel.clippedText(root.entityId, 180)
                  color: Tokens.text.disabled
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WrapAnywhere
                  Layout.fillWidth: true
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.queryState.error !== null && !!root.queryState.error.detail
                  text: root.queryState.error
                    ? "Detail: " + AgentCenterModel.clippedText(root.queryState.error.detail, 480)
                    : ""
                  color: Tokens.text.disabled
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WrapAnywhere
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
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Repeater {
                    model: root.queryState.recoveryActions

                    delegate: Text {
                      textFormat: Text.PlainText
                      required property var modelData

                      text: "\u2022 " + AgentCenterModel.clippedText(modelData, 320)
                      color: Tokens.text.secondary
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WrapAnywhere
                      Layout.fillWidth: true
                    }
                  }
                }
              }
            }

            Flow {
              visible: root.canMutate && root.queryState.view === "agent.context"
              Layout.fillWidth: true
              spacing: Style.space(8)

              Repeater {
                model: root.contextSources
                delegate: Ui.Button {
                  required property var modelData
                  text: "Capture " + String(modelData)
                  tooltipText: "Capture the " + String(modelData) + " desktop context source"
                  semanticProfile: root.productProfile
                  focusable: true
                  bordered: true
                  onClicked: root.captureContext(modelData)
                }
              }
            }

            GridLayout {
              visible: root.queryState.view === "agent.overview" &&
                (root.queryState.phase === "ready" || root.queryState.phase === "partial")
              Layout.fillWidth: true
              columns: root.width < 1050 ? 2 : 5
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(8)

              Repeater {
                model: root.overviewMetrics

                delegate: Rectangle {
                  required property var modelData

                  Layout.fillWidth: true
                  implicitHeight: metricColumn.implicitHeight + Style.space(24)
                  radius: Tokens.radius.medium
                  color: Tokens.surface.raised
                  border.color: Tokens.border.subtle
                  border.width: 1
                  Accessible.role: Accessible.StaticText
                  Accessible.name: modelData.label + ": " + modelData.value

                  ColumnLayout {
                    id: metricColumn
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      text: String(modelData.value)
                      color: Tokens.text.primary
                      font.family: Style.font.family
                      font.pixelSize: Style.font.display
                      font.bold: true
                      Layout.fillWidth: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: Semantics.text(root.productProfile, modelData.label)
                      color: Tokens.text.secondary
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WordWrap
                      Layout.fillWidth: true
                    }
                  }
                }
              }
            }

            Rectangle {
              visible: root.summaryLine() !== ""
              Layout.fillWidth: true
              implicitHeight: summaryText.implicitHeight + Style.space(20)
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.border.subtle
              border.width: 1
              Accessible.role: Accessible.StaticText
              Accessible.name: summaryText.text

              Text {
                textFormat: Text.PlainText
                id: summaryText
                anchors.fill: parent
                anchors.margins: Style.space(10)
                text: root.summaryLine()
                color: Tokens.text.secondary
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Repeater {
              model: root.queryState.items

              delegate: AgentCenter.AgentRecordCard {
                required property var modelData

                view: root.queryState.view
                record: modelData
                selectedEntityType: root.entityType
                selectedEntityId: root.entityId
                actionsEnabled: root.canMutate
                semanticProfile: root.productProfile
                onWorkRequested: function(action) { root.runTaskAction(action, modelData) }
              }
            }

              Ui.EmptyState {
              visible: root.queryState.phase === "empty"
              semanticProfile: root.productProfile
              Layout.fillWidth: true
              Layout.topMargin: Style.space(20)
              title: root.entityId === "" ? "No records in this view" : "Requested record is absent"
              message: root.entityId === ""
                ? "Fabric returned an empty current owner-scoped page."
                : "The stable deep link did not resolve to a visible owner-scoped record."
            }

            RowLayout {
              visible: root.canLoadMore || root.queryState.clipped
              Layout.fillWidth: true
              spacing: Style.space(10)

              Ui.Button {
                visible: root.canLoadMore
                text: "Load more"
                tooltipText: "Read the next bounded managed-work page"
                semanticProfile: root.productProfile
                focusable: true
                bordered: true
                onClicked: root.controller.loadMore()
              }

              Text {
                textFormat: Text.PlainText
                text: root.queryState.clipped
                  ? "Display bound reached at " + AgentCenterModel.MAX_VISIBLE_ITEMS + " records."
                  : root.queryState.items.length + " records loaded; another page is available."
                color: Tokens.text.disabled
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }
            }

            Text {
              visible: root.queryState.phase === "ready" || root.queryState.phase === "empty" || root.queryState.phase === "partial"
              text: Semantics.text(root.productProfile, "Managed-work v0 \u00b7 inspect tasks can be created, run, cancelled, and recovered. Consent and provider operations stay outside Agent Center.")
              color: Tokens.text.disabled
              font.family: Style.font.family
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
}
