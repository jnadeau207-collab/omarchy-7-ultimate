import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import qs.apps.shared as Shared

import "CompatibilityModel.js" as CompatibilityModel
import "." as Compatibility

Item {
  id: root
  property var host: null
  property var controller: null
  property var queryState: CompatibilityModel.baseState("compatibility.overview", {}, "offline")
  property bool decisionTouched: false

  readonly property var productProfile: host && host.productProfile ? host.productProfile : null
  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property var visibleRoutes: filteredRoutes(navigation.query)
  readonly property bool busy: queryState.phase === "catalog-loading" || queryState.phase === "loading"
  readonly property bool canRetry: !busy && ["offline", "missing", "unavailable", "denied", "interrupted", "stale", "failed"].indexOf(queryState.phase) >= 0
  readonly property bool showRecords: ["ready", "degraded", "partial", "unsupported", "empty"].indexOf(queryState.phase) >= 0
  readonly property int recordColumns: contentScroll.availableWidth >= 1050 ? 2 : 1
  readonly property bool decisionRoute: host && host.currentRoute === "compatibility.decide"

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
    controller = CompatibilityModel.createController({
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
    controller.activate(host.currentRoute || "compatibility.overview", host.currentArguments || {})
    controller.setConnected(host.fabricReady)
  }

  function retryState() {
    if (!controller || !host) return
    if (host.fabricReady) controller.refresh()
    else host.retryFabric()
  }

  function splitValues(text) {
    var raw = String(text || "").split(",")
    var result = []
    for (var i = 0; i < raw.length; i++) {
      var value = raw[i].trim()
      if (value !== "") result.push(value)
    }
    return result
  }

  function evaluateDecision() {
    if (!controller) return
    var artifactIsNone = artifactKind.value === "none"
    controller.decide({
      id: workloadId.text,
      name: workloadName.text,
      workloadType: workloadType.value,
      architecture: workloadArchitecture.value,
      artifact: {
        kind: artifactKind.value,
        origin: artifactIsNone ? null : artifactOrigin.text,
        digest: artifactIsNone || artifactDigest.text === "" ? null : artifactDigest.text
      },
      permissions: splitValues(permissionList.text),
      constraints: {
        requiresKernelDriver: kernelDriver.checked,
        requiresAdmin: adminRequired.checked,
        antiCheat: antiCheat.value,
        offlineRequired: offlineRequired.checked,
        acceptsBrowser: acceptsBrowser.checked
      }
    }, {
      architecture: hostArchitecture.value,
      virtualizationAvailable: virtualizationAvailable.checked,
      protonAvailable: protonAvailable.checked,
      isolationAvailable: isolationAvailable.checked,
      browserAvailable: browserAvailable.checked,
      availableRuntimes: splitValues(runtimeList.text),
      memoryMiB: memoryMiB.value,
      diskMiB: diskMiB.value
    })
  }

  function statusBorder() {
    if (["failed", "denied", "unavailable", "unsupported"].indexOf(queryState.phase) >= 0) return Tokens.state.danger
    if (["ready", "empty"].indexOf(queryState.phase) >= 0) return Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
    return Tokens.state.warning
  }

  onHostChanged: synchronizeHost()
  Component.onCompleted: ensureController()

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_F5 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R)) { root.retryState(); event.accepted = true }
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
    function onRouteActivated(routeId, routeArguments, context) { root.ensureController(); root.decisionTouched = false; root.controller.activate(routeId, routeArguments || {}) }
    function onFabricResult(requestId, result) { if (root.controller) root.controller.receiveResult(requestId, result) }
    function onFabricFailure(requestId, error) { if (root.controller) root.controller.receiveFailure(requestId, error) }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0
    Shared.ApplicationNavigation {
      id: navigation
      title: "Compatibility Center"
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
              text: root.currentRoute ? root.currentRoute.title : "Compatibility Center"
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
              text: root.currentRoute ? root.currentRoute.description : "The requested Compatibility Center route is unavailable."
              color: Tokens.text.secondary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              maximumLineCount: 4
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
          Ui.Badge { text: String(root.queryState.phase || "offline").toUpperCase(); tone: CompatibilityModel.phaseTone(root.queryState); Layout.alignment: Qt.AlignTop }
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
              Accessible.role: ["failed", "denied", "unavailable", "unsupported"].indexOf(root.queryState.phase) >= 0 ? Accessible.AlertMessage : Accessible.Pane
              Accessible.name: CompatibilityModel.stateTitle(root.queryState)
              Accessible.description: CompatibilityModel.stateExplanation(root.queryState)
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
                    text: CompatibilityModel.stateTitle(root.queryState)
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
                  text: CompatibilityModel.stateExplanation(root.queryState)
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  maximumLineCount: 9
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
                Text {
                  textFormat: Text.PlainText
                  visible: root.queryState.revision !== "" || root.queryState.providerGeneration > 0
                  text: (root.queryState.revision !== "" ? "Revision " + root.queryState.revision + " \u00b7 " : "") + "assurance " + root.queryState.assurance + " \u00b7 generation " + root.queryState.providerGeneration + " \u00b7 " + root.queryState.totalRecords + " source record" + (root.queryState.totalRecords === 1 ? "" : "s")
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

            Rectangle {
              visible: root.decisionRoute
              Layout.fillWidth: true
              implicitHeight: decisionForm.implicitHeight + Style.space(28)
              radius: Tokens.radius.large
              color: Tokens.surface.raised
              border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Compatibility route declaration"

              ColumnLayout {
                id: decisionForm
                anchors.fill: parent
                anchors.margins: Style.space(14)
                spacing: Style.space(12)

                Text {
                  text: "USER-DECLARED INPUT \u00b7 NOT HOST-MEASURED"
                  color: Tokens.state.warning
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  Layout.fillWidth: true
                }
                Text {
                  text: "Every field is sent only to compatibility.provider route.decide. The result is a read-only decision, not a deployment plan or execution request."
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }

                GridLayout {
                  Layout.fillWidth: true
                  columns: contentScroll.availableWidth >= 760 ? 2 : 1
                  columnSpacing: Style.space(12)
                  rowSpacing: Style.space(10)

                  ColumnLayout {
                    Layout.fillWidth: true
                    Text { text: "Workload identity"; color: Tokens.text.disabled; font.family: Tokens.typography.family; font.pixelSize: Style.font.caption; font.bold: true }
                    Ui.TextField { id: workloadId; Layout.fillWidth: true; semanticPlaceholderText: "workload.example"; accessibleName: "Stable workload identity"; maximumLength: 160; onTextEdited: root.decisionTouched = true }
                  }
                  ColumnLayout {
                    Layout.fillWidth: true
                    Text { text: "Display name"; color: Tokens.text.disabled; font.family: Tokens.typography.family; font.pixelSize: Style.font.caption; font.bold: true }
                    Ui.TextField { id: workloadName; Layout.fillWidth: true; semanticPlaceholderText: "Application name"; accessibleName: "Workload display name"; maximumLength: 160; onTextEdited: root.decisionTouched = true }
                  }
                  Ui.Dropdown { id: workloadType; Layout.fillWidth: true; label: "Workload type"; value: "desktop"; options: ["desktop", "web", "windows-game", "windows-app", "portable"]; onChanged: root.decisionTouched = true }
                  Ui.Dropdown { id: workloadArchitecture; Layout.fillWidth: true; label: "Workload architecture"; value: "any"; options: ["any", "x86_64", "aarch64"]; onChanged: root.decisionTouched = true }
                  Ui.Dropdown { id: artifactKind; Layout.fillWidth: true; label: "Artifact kind"; value: "none"; options: ["none", "native-package", "web-url", "windows-executable", "portable"]; onChanged: root.decisionTouched = true }
                  ColumnLayout {
                    Layout.fillWidth: true
                    Text { text: "HTTPS artifact origin"; color: Tokens.text.disabled; font.family: Tokens.typography.family; font.pixelSize: Style.font.caption; font.bold: true }
                    Ui.TextField { id: artifactOrigin; Layout.fillWidth: true; semanticPlaceholderText: "https://example.invalid/artifact"; accessibleName: "HTTPS artifact origin"; maximumLength: 500; enabled: artifactKind.value !== "none"; onTextEdited: root.decisionTouched = true }
                  }
                  ColumnLayout {
                    Layout.fillWidth: true
                    Text { text: "Pinned artifact digest"; color: Tokens.text.disabled; font.family: Tokens.typography.family; font.pixelSize: Style.font.caption; font.bold: true }
                    Ui.TextField { id: artifactDigest; Layout.fillWidth: true; semanticPlaceholderText: "sha256:64 lowercase hex characters"; accessibleName: "Pinned artifact digest"; maximumLength: 71; enabled: artifactKind.value !== "none"; onTextEdited: root.decisionTouched = true }
                  }
                  ColumnLayout {
                    Layout.fillWidth: true
                    Text { text: "Permissions (comma-separated)"; color: Tokens.text.disabled; font.family: Tokens.typography.family; font.pixelSize: Style.font.caption; font.bold: true }
                    Ui.TextField { id: permissionList; Layout.fillWidth: true; semanticPlaceholderText: "network, audio"; accessibleName: "Requested permissions"; maximumLength: 300; onTextEdited: root.decisionTouched = true }
                  }
                  Ui.Dropdown { id: antiCheat; Layout.fillWidth: true; label: "Anti-cheat"; value: "none"; options: ["none", "supported", "blocked", "unknown"]; onChanged: root.decisionTouched = true }
                  Ui.Dropdown { id: hostArchitecture; Layout.fillWidth: true; label: "Declared host architecture"; value: "x86_64"; options: ["x86_64", "aarch64"]; onChanged: root.decisionTouched = true }
                  ColumnLayout {
                    Layout.fillWidth: true
                    Text { text: "Available runtimes (comma-separated)"; color: Tokens.text.disabled; font.family: Tokens.typography.family; font.pixelSize: Style.font.caption; font.bold: true }
                    Ui.TextField { id: runtimeList; Layout.fillWidth: true; semanticPlaceholderText: "native, browser"; accessibleName: "Declared available runtimes"; maximumLength: 100; onTextEdited: root.decisionTouched = true }
                  }
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(12)
                    Ui.NumberField { id: memoryMiB; label: "Memory MiB"; from: 128; to: 262144; value: 128; onModified: function(newValue) { memoryMiB.value = newValue; root.decisionTouched = true } }
                    Ui.NumberField { id: diskMiB; label: "Disk MiB"; from: 1; to: 1048576; value: 1; onModified: function(newValue) { diskMiB.value = newValue; root.decisionTouched = true } }
                  }
                }

                GridLayout {
                  Layout.fillWidth: true
                  columns: contentScroll.availableWidth >= 760 ? 3 : 1
                  columnSpacing: Style.space(12)
                  rowSpacing: Style.space(10)
                  Ui.Checkbox { id: kernelDriver; label: "Requires kernel driver"; focusable: true; onToggled: { checked = !checked; root.decisionTouched = true } }
                  Ui.Checkbox { id: adminRequired; label: "Requires administration"; focusable: true; onToggled: { checked = !checked; root.decisionTouched = true } }
                  Ui.Checkbox { id: offlineRequired; label: "Offline required"; focusable: true; onToggled: { checked = !checked; root.decisionTouched = true } }
                  Ui.Checkbox { id: acceptsBrowser; label: "Accepts browser route"; focusable: true; onToggled: { checked = !checked; root.decisionTouched = true } }
                  Ui.Checkbox { id: virtualizationAvailable; label: "Virtualization available"; focusable: true; onToggled: { checked = !checked; root.decisionTouched = true } }
                  Ui.Checkbox { id: protonAvailable; label: "Proton available"; focusable: true; onToggled: { checked = !checked; root.decisionTouched = true } }
                  Ui.Checkbox { id: isolationAvailable; label: "Isolation available"; focusable: true; onToggled: { checked = !checked; root.decisionTouched = true } }
                  Ui.Checkbox { id: browserAvailable; label: "Browser available"; focusable: true; onToggled: { checked = !checked; root.decisionTouched = true } }
                }

                Ui.Button {
                  text: "Evaluate all six routes"
                  focusable: true
                  bordered: true
                  enabled: root.decisionTouched && !root.busy && root.queryState.providerEntry !== null
                  accessibleDescription: "Send one complete user-declared workload and host snapshot to the read-only compatibility route decision"
                  onClicked: root.evaluateDecision()
                  Layout.alignment: Qt.AlignRight
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
                delegate: Compatibility.CompatibilityRecordCard {
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
              title: root.queryState.selectedMissing ? "Deep-linked deployment not found" : "No compatibility deployments"
              message: root.queryState.selectedMissing ? "This exact identity is absent from the displayed provider revision." : "The provider returned a valid empty deployment inventory."
            }

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: boundaryText.implicitHeight + Style.space(20)
              radius: Tokens.radius.medium
              color: Qt.rgba(Tokens.state.warning.r, Tokens.state.warning.g, Tokens.state.warning.b, 0.08)
              border.color: Tokens.state.warning
              border.width: 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Compatibility mutation boundary"
              Text {
                id: boundaryText
                anchors.fill: parent
                anchors.margins: Style.space(10)
                text: "Read-only compatibility v0 \u00b7 deploy, remove, export, recipe execution, VM provisioning, and host mutation controls remain unavailable until coordinator, executor, measured-host, and release-attestation integration is complete."
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
