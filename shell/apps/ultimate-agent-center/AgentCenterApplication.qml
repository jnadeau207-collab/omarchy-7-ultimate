import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import qs.apps.shared as Shared

Item {
  id: root

  property var host: null
  property var providerCatalog: []
  property string catalogState: "offline"
  property var catalogError: null
  property string catalogRequestId: ""
  property string operationRequestId: ""
  property string operationState: "idle"
  property var operation: null
  property var operationError: null

  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property var visibleRoutes: filteredRoutes(navigation.query)
  readonly property string entityType: host && host.currentArguments && host.currentArguments.entityType
    ? String(host.currentArguments.entityType) : ""
  readonly property string entityId: host && host.currentArguments && host.currentArguments.entityId
    ? String(host.currentArguments.entityId) : ""

  function filteredRoutes(query) {
    if (!host || !host.routeCatalog || !Array.isArray(host.routeCatalog.routes)) return []
    var needle = String(query || "").toLowerCase().trim()
    if (needle === "") return host.routeCatalog.routes
    return host.routeCatalog.routes.filter(function(route) {
      var haystack = [route.title, route.description, route.section].concat(route.keywords || []).join(" ").toLowerCase()
      return haystack.indexOf(needle) >= 0
    })
  }

  function refreshCatalog() {
    if (!host || !host.fabricReady) {
      providerCatalog = []
      catalogState = "offline"
      catalogRequestId = ""
      return
    }
    catalogState = "loading"
    catalogError = null
    catalogRequestId = host.requestFabric("provider.catalog", {})
    if (catalogRequestId === "") catalogState = "failed"
  }

  function refreshEntity() {
    operationRequestId = ""
    operation = null
    operationError = null
    if (entityType !== "operation" || entityId === "") {
      operationState = "idle"
      return
    }
    if (!host || !host.fabricReady) {
      operationState = "offline"
      return
    }
    operationState = "loading"
    operationRequestId = host.requestFabric("reference.operation.get", { operationId: entityId })
    if (operationRequestId === "") operationState = "failed"
  }

  function backendMessage() {
    if (!currentRoute) return "The requested route is unavailable."
    if (currentRoute.id === "agent.overview")
      return "Agent Center only presents data exposed by its constrained Fabric client. Missing task and automation query contracts remain visibly unavailable."
    if (currentRoute.id === "agent.providers")
      return catalogState === "ready"
        ? providerCatalog.length + " typed provider" + (providerCatalog.length === 1 ? " is" : "s are") + " registered in the current daemon."
        : "Provider inventory is unavailable until the current Fabric catalog loads."
    if (currentRoute.id === "agent.activity" && entityType === "operation") {
      if (operationState === "ready") return "The operation was read through reference.operation.get using this app's endpoint session."
      if (operationState === "loading") return "Reading the requested durable operation."
      if (operationState === "offline") return "The requested operation is not shown while Fabric is offline."
      if (operationState === "failed") return operationError && operationError.explanation
        ? String(operationError.explanation) : "Fabric could not read the requested operation."
    }
    if (entityId !== "")
      return "The link selected " + entityType + " " + entityId + ", but this Fabric revision has no read contract for that entity type."
    return "This destination is present, but its backend query contract is not part of the current Fabric revision. No placeholder records are shown."
  }

  onHostChanged: {
    if (!host) return
    refreshCatalog()
    refreshEntity()
  }

  Connections {
    target: root.host
    enabled: root.host !== null

    function onFabricConnectionReady(hello) {
      root.refreshCatalog()
      root.refreshEntity()
    }
    function onFabricReadyChanged() {
      if (root.host.fabricReady) {
        root.refreshCatalog()
        root.refreshEntity()
      } else {
        root.providerCatalog = []
        root.catalogState = "offline"
        root.operation = null
        root.operationState = root.entityType === "operation" ? "offline" : "idle"
      }
    }
    function onRouteActivated(routeId, routeArguments, context) {
      Qt.callLater(root.refreshEntity)
    }
    function onFabricResult(requestId, result) {
      if (requestId === root.catalogRequestId) {
        root.catalogRequestId = ""
        if (!result || !Array.isArray(result.providers)) {
          root.catalogState = "failed"
          root.catalogError = { explanation: "Fabric returned an invalid provider catalog." }
        } else {
          root.providerCatalog = result.providers
          root.catalogState = "ready"
          root.catalogError = null
        }
      } else if (requestId === root.operationRequestId) {
        root.operationRequestId = ""
        root.operation = result
        root.operationError = null
        root.operationState = "ready"
      }
    }
    function onFabricFailure(requestId, error) {
      if (requestId === root.catalogRequestId || (requestId === "" && root.catalogState === "loading")) {
        root.catalogRequestId = ""
        root.catalogState = "failed"
        root.catalogError = error
      } else if (requestId === root.operationRequestId || (requestId === "" && root.operationState === "loading")) {
        root.operationRequestId = ""
        root.operationState = "failed"
        root.operationError = error
      }
    }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0

    Shared.ApplicationNavigation {
      id: navigation
      title: "Agent Center"
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
          Layout.fillWidth: true
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(3)

          Text {
            text: root.currentRoute ? root.currentRoute.title : "Agent Center"
            color: Tokens.text.primary
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            Layout.fillWidth: true
          }

          Text {
            text: root.currentRoute ? root.currentRoute.description : "The requested route is unavailable."
            color: Tokens.text.secondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }

        Controls.ScrollView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true

          ColumnLayout {
            width: parent.width
            spacing: Style.space(12)

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: backendColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.large
              color: Tokens.surface.base
              border.color: Tokens.border.subtle
              border.width: 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Backend readiness"
              Accessible.description: root.backendMessage()

              ColumnLayout {
                id: backendColumn
                anchors.fill: parent
                anchors.margins: Style.space(14)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true

                  Text {
                    text: root.operationState === "ready" ? "Durable operation" : "Backend readiness"
                    color: Tokens.text.primary
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Button {
                    visible: root.operationState === "failed" || root.catalogState === "failed"
                    text: "Try again"
                    focusable: true
                    onClicked: {
                      if (root.catalogState === "failed") root.refreshCatalog()
                      if (root.operationState === "failed") root.refreshEntity()
                    }
                  }
                }

                Text {
                  text: root.backendMessage()
                  color: Tokens.text.secondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }

                Ui.ProgressBar {
                  visible: root.catalogState === "loading" || root.operationState === "loading"
                  indeterminate: true
                  accessibleName: "Loading Agent Center state"
                  Layout.fillWidth: true
                }

                Text {
                  visible: root.entityId !== ""
                  text: "Selected " + root.entityType + ": " + root.entityId
                  color: Tokens.text.disabled
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WrapAnywhere
                  Layout.fillWidth: true
                }
              }
            }

            Rectangle {
              visible: root.operationState === "ready" && root.operation !== null
              Layout.fillWidth: true
              implicitHeight: operationColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.border.subtle
              border.width: 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Operation " + String(root.operation && root.operation.operationId || root.entityId)

              ColumnLayout {
                id: operationColumn
                anchors.fill: parent
                anchors.margins: Style.space(14)
                spacing: Style.space(6)

                Text {
                  text: String(root.operation && (root.operation.label || root.operation.capability || root.operation.operationId) || "Operation")
                  color: Tokens.text.primary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  Layout.fillWidth: true
                }

                Text {
                  text: "Status: " + String(root.operation && root.operation.status || "unknown")
                  color: Tokens.text.secondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  Layout.fillWidth: true
                }

                Text {
                  text: "Operation ID: " + String(root.operation && root.operation.operationId || root.entityId)
                  color: Tokens.text.disabled
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WrapAnywhere
                  Layout.fillWidth: true
                }
              }
            }

            Repeater {
              model: root.currentRoute && root.currentRoute.id === "agent.providers" && root.catalogState === "ready"
                ? root.providerCatalog : []

              delegate: Rectangle {
                required property var modelData

                readonly property string providerId: modelData && modelData.manifest ? String(modelData.manifest.provider || "") : ""
                readonly property bool selected: root.entityType === "provider" && root.entityId === providerId

                Layout.fillWidth: true
                implicitHeight: providerColumn.implicitHeight + Style.space(24)
                radius: Tokens.radius.medium
                color: Tokens.surface.raised
                border.color: selected ? Tokens.accent.primary : Tokens.border.subtle
                border.width: 1
                Accessible.role: Accessible.Pane
                Accessible.name: providerId

                ColumnLayout {
                  id: providerColumn
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  spacing: Style.space(5)

                  RowLayout {
                    Layout.fillWidth: true

                    Text {
                      text: providerId
                      color: Tokens.text.primary
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      Layout.fillWidth: true
                    }

                    Ui.Badge {
                      text: String(modelData.state || "unknown").toUpperCase()
                      tone: modelData.state === "available" ? "success" : "warning"
                    }
                  }

                  Text {
                    text: "Version " + String(modelData.manifest && modelData.manifest.providerVersion || "unknown")
                    color: Tokens.text.disabled
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    Layout.fillWidth: true
                  }

                  Text {
                    visible: modelData.detail !== null && modelData.detail !== undefined && String(modelData.detail) !== ""
                    text: String(modelData.detail || "")
                    color: Tokens.text.secondary
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }
                }
              }
            }

            Ui.EmptyState {
              visible: root.currentRoute && root.currentRoute.id === "agent.providers" && root.catalogState === "ready" && root.providerCatalog.length === 0
              Layout.fillWidth: true
              Layout.topMargin: Style.space(20)
              title: "No typed providers registered"
              message: "The daemon returned an empty current provider catalog."
            }
          }
        }
      }
    }
  }
}
