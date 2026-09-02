import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import qs.apps.shared as Shared

import "SoftwareModel.js" as SoftwareModel
import "." as Software

Item {
  id: root
  property var host: null
  property var controller: null
  property var queryState: SoftwareModel.baseState("software.catalog", {}, "offline")

  readonly property var productProfile: host && host.productProfile ? host.productProfile : null
  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property var visibleRoutes: filteredRoutes(navigation.query)
  readonly property bool busy: queryState.phase === "catalog-loading" || queryState.phase === "loading"
  readonly property bool canRetry: !busy && ["offline", "missing", "unavailable", "denied", "interrupted", "stale", "failed"].indexOf(queryState.phase) >= 0
  readonly property bool showRecords: ["ready", "degraded", "partial", "empty"].indexOf(queryState.phase) >= 0
  readonly property int recordColumns: contentScroll.availableWidth >= 1050 ? 2 : 1

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
    controller = SoftwareModel.createController({
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
    controller.activate(host.currentRoute || "software.catalog", host.currentArguments || {})
    controller.setConnected(host.fabricReady)
  }

  function retryState() {
    if (!controller || !host) return
    if (host.fabricReady) controller.refresh()
    else host.retryFabric()
  }

  function runSearch() {
    if (!host) return
    host.navigate("software.catalog", searchInput.text === "" ? {} : { query: searchInput.text })
  }

  function statusBorder() {
    if (["failed", "denied", "unavailable"].indexOf(queryState.phase) >= 0) return Tokens.state.danger
    if (["ready", "empty"].indexOf(queryState.phase) >= 0) return Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
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
      if (routeId === "software.catalog") searchInput.text = routeArguments && routeArguments.query ? String(routeArguments.query) : ""
    }
    function onFabricResult(requestId, result) { if (root.controller) root.controller.receiveResult(requestId, result) }
    function onFabricFailure(requestId, error) { if (root.controller) root.controller.receiveFailure(requestId, error) }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0
    Shared.ApplicationNavigation {
      id: navigation
      title: "Software Center"
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

        Shared.FabricStatusBanner { host: root.host; semanticProfile: root.productProfile; Layout.fillWidth: true }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(3)
            Text {
              textFormat: Text.PlainText
              text: root.currentRoute ? root.currentRoute.title : "Software Center"
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
              text: root.currentRoute ? root.currentRoute.description : "The requested Software Center route is unavailable."
              color: Tokens.text.secondary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              maximumLineCount: 4
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
          Ui.Badge { text: String(root.queryState.phase || "offline").toUpperCase(); tone: SoftwareModel.phaseTone(root.queryState); Layout.alignment: Qt.AlignTop }
        }

        RowLayout {
          visible: root.host && root.host.currentRoute === "software.catalog"
          Layout.fillWidth: true
          spacing: Style.space(8)
          Ui.SearchBox {
            id: searchInput
            Layout.fillWidth: true
            semanticPlaceholderText: "Search admitted software"
            accessibleName: "Software catalog query"
            onAccepted: root.runSearch()
            onCleared: root.host.navigate("software.catalog", {})
          }
          Ui.Button {
            text: "Search"
            focusable: true
            bordered: true
            accessibleDescription: "Search the bounded packages.provider catalog"
            onClicked: root.runSearch()
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
              border.color: root.statusBorder()
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: ["failed", "denied", "unavailable"].indexOf(root.queryState.phase) >= 0 ? Accessible.AlertMessage : Accessible.Pane
              Accessible.name: SoftwareModel.stateTitle(root.queryState)
              Accessible.description: SoftwareModel.stateExplanation(root.queryState)
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
                    text: SoftwareModel.stateTitle(root.queryState)
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
                    semanticProfile: root.productProfile
                    focusable: true
                    bordered: true
                    onClicked: root.retryState()
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  text: SoftwareModel.stateExplanation(root.queryState)
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
                  text: "Revision " + root.queryState.revision + " \u00b7 assurance " + root.queryState.assurance + " \u00b7 generation " + root.queryState.providerGeneration + " \u00b7 " + root.queryState.totalRecords + " source record" + (root.queryState.totalRecords === 1 ? "" : "s")
                  color: Tokens.text.disabled
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WrapAnywhere
                  maximumLineCount: 4
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
                delegate: Software.SoftwareRecordCard {
                  required property var modelData
                  record: modelData
                  selected: root.queryState.entityId !== "" && modelData.id === root.queryState.entityId
                  Layout.fillWidth: true
                  Layout.columnSpan: 1
                }
              }
            }

            Ui.EmptyState {
              visible: root.showRecords && root.queryState.records.length === 0
              Layout.fillWidth: true
              title: root.queryState.selectedMissing ? "Deep-linked software not found" : "No software records"
              message: root.queryState.selectedMissing ? "This exact identity is absent from the displayed provider revision." : "The provider returned a valid empty result."
            }

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: boundaryText.implicitHeight + Style.space(20)
              radius: Tokens.radius.medium
              color: Qt.rgba(Tokens.state.warning.r, Tokens.state.warning.g, Tokens.state.warning.b, 0.08)
              border.color: Tokens.state.warning
              border.width: 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Software mutation boundary"
              Text {
                id: boundaryText
                anchors.fill: parent
                anchors.margins: Style.space(10)
                text: "Read-only packages v0 \u00b7 install, remove, adopt, and recover controls remain unavailable until the durable coordinator, executor, and release-attested catalogs are connected. This surface never invokes a package manager."
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
