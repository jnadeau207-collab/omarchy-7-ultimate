import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import qs.apps.shared as Shared
import "." as SettingsComponents

import "SettingsModel.js" as SettingsModel

Item {
  id: root

  property var host: null
  property var controller: null
  property var queryState: SettingsModel.baseState(SettingsModel.OVERVIEW_ROUTE, {}, "offline")

  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property var visibleRoutes: filteredRoutes(navigation.query)
  readonly property bool queryBusy: queryState.phase === "catalog-loading" || queryState.phase === "loading"
  readonly property bool overviewVisible: queryState.phase === "overview"
  readonly property bool canRetry: !queryBusy && [
    "offline", "missing", "unavailable", "degraded", "contract-mismatch", "denied", "interrupted", "stale", "failed"
  ].indexOf(queryState.phase) >= 0
  readonly property bool domainVisible: queryState.query && queryState.query.providerId !== ""
  readonly property int recordColumns: contentScroll.availableWidth >= 980 ? 2 : 1
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
    controller = SettingsModel.createController({
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
    controller.activate(host.currentRoute || SettingsModel.OVERVIEW_ROUTE, currentArguments())
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
      title: "Settings"
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
          Layout.fillWidth: true
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(3)

            Text {
              text: root.currentRoute ? root.currentRoute.title : "Settings"
              color: Tokens.text.primary
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Text {
              text: root.currentRoute ? root.currentRoute.description : "The requested route is unavailable."
              color: Tokens.text.secondary
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              maximumLineCount: 4
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          Ui.Badge {
            text: SettingsModel.phaseBadge(root.queryState)
            tone: SettingsModel.phaseTone(root.queryState)
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
              Accessible.name: SettingsModel.stateTitle(root.queryState)
              Accessible.description: SettingsModel.stateExplanation(root.queryState)

              ColumnLayout {
                id: statusColumn
                anchors.fill: parent
                anchors.margins: Style.space(14)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(10)

                  Text {
                    text: SettingsModel.stateTitle(root.queryState)
                    color: Tokens.text.primary
                    font.family: Style.font.family
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
                    focusable: true
                    bordered: true
                    onClicked: root.retryState()
                  }
                }

                Text {
                  text: SettingsModel.stateExplanation(root.queryState)
                  color: Tokens.text.secondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  maximumLineCount: 7
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Ui.ProgressBar {
                  visible: root.queryBusy
                  indeterminate: true
                  accessibleName: root.queryState.phase === "catalog-loading"
                    ? "Loading Settings provider catalog" : "Loading current Settings provider state"
                  Layout.fillWidth: true
                }

                Text {
                  visible: root.domainVisible
                  text: SettingsModel.provenance(root.queryState)
                  color: Tokens.text.disabled
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WrapAnywhere
                  maximumLineCount: 4
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  visible: root.queryState.selectedResourceId !== ""
                  text: "Exact resource: " + SettingsModel.clippedText(root.queryState.selectedResourceId, 180)
                  color: Tokens.text.disabled
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WrapAnywhere
                  maximumLineCount: 3
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  visible: root.queryState.error && root.queryState.error.detail
                  text: "Detail: " + SettingsModel.clippedText(root.queryState.error ? root.queryState.error.detail : "", 480)
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
                    text: "RECOVERY PATHS"
                    color: Tokens.state.warning
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Repeater {
                    model: root.queryState.recoveryActions

                    delegate: Text {
                      required property var modelData

                      text: "\u2022 " + SettingsModel.clippedText(modelData, 320)
                      color: Tokens.text.secondary
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WrapAnywhere
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
                  Accessible.name: modelData.title + ". " + modelData.status
                  Accessible.description: modelData.detail

                  ColumnLayout {
                    id: overviewCardColumn
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(7)

                    RowLayout {
                      Layout.fillWidth: true
                      spacing: Style.space(8)

                      Text {
                        text: modelData.title
                        color: Tokens.text.primary
                        font.family: Style.font.family
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
                        Layout.alignment: Qt.AlignTop
                      }
                    }

                    Text {
                      text: modelData.detail
                      color: Tokens.text.secondary
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WordWrap
                      maximumLineCount: 5
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Text {
                      text: modelData.providerId
                      color: Tokens.text.disabled
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WrapAnywhere
                      maximumLineCount: 2
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Ui.Button {
                      text: "Open " + modelData.title
                      tooltipText: "Open the read-only " + modelData.title + " Settings route"
                      accessibleDescription: modelData.status + ". " + modelData.detail
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
              Accessible.name: "Settings coverage and unavailable changes"
              Accessible.description: root.queryState.query ? root.queryState.query.coverage : ""

              ColumnLayout {
                id: coverageColumn
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(6)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    text: "Coverage"
                    color: Tokens.text.primary
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Badge {
                    text: "CHANGES UNAVAILABLE"
                    tone: "warning"
                    Layout.alignment: Qt.AlignTop
                  }
                }

                Text {
                  text: root.queryState.query ? root.queryState.query.coverage : ""
                  color: Tokens.text.secondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  maximumLineCount: 6
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  visible: root.queryState.operationActions.length > 0
                  text: "Declared provider operations: " + root.queryState.operationActions.join(", ") +
                    ". Settings exposes no preflight, approval, or execution control until the durable coordinator is integrated."
                  color: Tokens.text.disabled
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WrapAnywhere
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

                delegate: SettingsComponents.SettingsRecordCard {
                  required property var modelData

                  record: modelData
                  selected: root.queryState.selectedResourceId !== "" &&
                    root.queryState.selectedResourceId === modelData.id
                }
              }
            }

            Ui.EmptyState {
              visible: root.queryState.phase === "empty"
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
                id: clippedNotice
                anchors.fill: parent
                anchors.margins: Style.space(10)
                text: "Display bound reached at " + SettingsModel.MAX_VISIBLE_RECORDS + " records. " +
                  root.queryState.totalRecords + " records were reported; use an exact resource deep link for a narrower view."
                color: Tokens.text.secondary
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Text {
              visible: !root.queryBusy
              text: "Read-only Fabric provider state \u00b7 no direct commands, mutation, preflight, approval, or execution authority"
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
