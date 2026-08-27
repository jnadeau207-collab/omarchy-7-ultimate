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
  property string providerReadRequestId: ""
  property string providerViewState: "idle"
  property var providerReadResult: null
  property var providerReadError: null

  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property string selectedResourceId: host && host.currentArguments && host.currentArguments.resourceId
    ? String(host.currentArguments.resourceId) : ""
  readonly property var visibleRoutes: filteredRoutes(navigation.query)
  readonly property var selectedProvider: providerEntry(currentRoute ? currentRoute.providerId : "")
  readonly property var visibleResources: filteredResources()

  function filteredRoutes(query) {
    if (!host || !host.routeCatalog || !Array.isArray(host.routeCatalog.routes)) return []
    var needle = String(query || "").toLowerCase().trim()
    if (needle === "") return host.routeCatalog.routes
    return host.routeCatalog.routes.filter(function(route) {
      var haystack = [route.title, route.description, route.section].concat(route.keywords || []).join(" ").toLowerCase()
      return haystack.indexOf(needle) >= 0
    })
  }

  function providerEntry(providerId) {
    if (!providerId || !Array.isArray(providerCatalog)) return null
    for (var i = 0; i < providerCatalog.length; i++) {
      var entry = providerCatalog[i]
      if (entry && entry.manifest && entry.manifest.provider === providerId) return entry
    }
    return null
  }

  function firstReadAction(entry) {
    if (!entry || !entry.manifest || !entry.manifest.actions) return ""
    var names = Object.keys(entry.manifest.actions).sort()
    for (var i = 0; i < names.length; i++) {
      if (entry.manifest.actions[names[i]].mode === "read") return names[i]
    }
    return ""
  }

  function filteredResources() {
    var value = providerReadResult && providerReadResult.value ? providerReadResult.value : null
    var resources = value && Array.isArray(value.resources) ? value.resources : []
    if (selectedResourceId === "") return resources
    return resources.filter(function(resource) { return resource && resource.id === selectedResourceId })
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

  function refreshSelectedProvider() {
    providerReadRequestId = ""
    providerReadResult = null
    providerReadError = null
    if (!currentRoute || currentRoute.providerId === "") {
      providerViewState = "overview"
      return
    }
    if (!host || !host.fabricReady) {
      providerViewState = "offline"
      return
    }
    if (catalogState !== "ready") {
      providerViewState = "waiting-catalog"
      return
    }
    if (!selectedProvider) {
      providerViewState = "missing"
      return
    }
    if (selectedProvider.state !== "available") {
      providerViewState = "unavailable"
      return
    }
    var action = firstReadAction(selectedProvider)
    if (action === "") {
      providerViewState = "no-read-contract"
      return
    }
    providerViewState = "loading"
    providerReadRequestId = host.requestFabric("provider.read", {
      provider: currentRoute.providerId,
      action: action,
      arguments: {}
    })
    if (providerReadRequestId === "") providerViewState = "failed"
  }

  function providerStatusTitle() {
    if (providerViewState === "overview") return "Provider-backed settings"
    if (providerViewState === "offline") return "Fabric is offline"
    if (providerViewState === "waiting-catalog") return "Loading provider catalog"
    if (providerViewState === "missing") return "Provider is not registered"
    if (providerViewState === "unavailable") return "Provider is unavailable"
    if (providerViewState === "no-read-contract") return "Provider has no readable state"
    if (providerViewState === "loading") return "Reading current state"
    if (providerViewState === "failed") return "Provider read failed"
    if (providerViewState === "ready") return "Current provider state"
    return "Provider state"
  }

  function providerStatusExplanation() {
    if (providerViewState === "overview") return "Choose a domain to read its registered typed provider. No direct system command runs from this application."
    if (providerViewState === "offline") return "Settings does not display cached system state while its Fabric endpoint is disconnected."
    if (providerViewState === "waiting-catalog") return "Settings is waiting for the daemon's current provider registry."
    if (providerViewState === "missing") return "" + currentRoute.providerId + " is not present in the current Fabric catalog. This page does not advertise controls without it."
    if (providerViewState === "unavailable") return selectedProvider && selectedProvider.detail
      ? String(selectedProvider.detail) : "The provider is registered but has no usable backend."
    if (providerViewState === "no-read-contract") return "The registered provider exposes no read action, so Settings cannot represent current state honestly."
    if (providerViewState === "loading") return "The typed read is in progress."
    if (providerViewState === "failed") return providerReadError && providerReadError.explanation
      ? String(providerReadError.explanation) : "Fabric rejected or failed the typed provider read."
    if (providerViewState === "ready") return providerReadResult && providerReadResult.observedAt
      ? "Observed at " + providerReadResult.observedAt + "." : "The provider returned a validated state payload."
    return ""
  }

  onHostChanged: {
    if (!host) return
    refreshCatalog()
    refreshSelectedProvider()
  }

  Connections {
    target: root.host
    enabled: root.host !== null

    function onFabricConnectionReady(hello) { root.refreshCatalog() }
    function onFabricReadyChanged() {
      if (root.host.fabricReady) root.refreshCatalog()
      else {
        root.providerCatalog = []
        root.catalogState = "offline"
        root.refreshSelectedProvider()
      }
    }
    function onRouteActivated(routeId, routeArguments, context) {
      Qt.callLater(root.refreshSelectedProvider)
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
          root.refreshSelectedProvider()
        }
      } else if (requestId === root.providerReadRequestId) {
        root.providerReadRequestId = ""
        root.providerReadResult = result
        root.providerReadError = null
        root.providerViewState = "ready"
      }
    }
    function onFabricFailure(requestId, error) {
      if (requestId === root.catalogRequestId || (requestId === "" && root.catalogState === "loading")) {
        root.catalogRequestId = ""
        root.catalogState = "failed"
        root.catalogError = error
        root.providerViewState = "waiting-catalog"
      } else if (requestId === root.providerReadRequestId || (requestId === "" && root.providerViewState === "loading")) {
        root.providerReadRequestId = ""
        root.providerReadError = error
        root.providerViewState = "failed"
      }
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

          Ui.Badge {
            visible: root.currentRoute && root.currentRoute.providerId !== ""
            text: root.providerViewState === "ready" ? "LIVE" : "UNAVAILABLE"
            tone: root.providerViewState === "ready" ? "success" : "warning"
            Layout.alignment: Qt.AlignTop
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
              implicitHeight: statusColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.large
              color: Tokens.surface.base
              border.color: Tokens.border.subtle
              border.width: 1
              Accessible.role: Accessible.Pane
              Accessible.name: root.providerStatusTitle()
              Accessible.description: root.providerStatusExplanation()

              ColumnLayout {
                id: statusColumn
                anchors.fill: parent
                anchors.margins: Style.space(14)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true

                  Text {
                    text: root.providerStatusTitle()
                    color: Tokens.text.primary
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Button {
                    visible: root.providerViewState === "failed" || root.catalogState === "failed"
                    text: "Try again"
                    focusable: true
                    onClicked: {
                      if (root.catalogState === "failed") root.refreshCatalog()
                      else root.refreshSelectedProvider()
                    }
                  }
                }

                Text {
                  text: root.providerStatusExplanation()
                  color: Tokens.text.secondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }

                Ui.ProgressBar {
                  visible: root.providerViewState === "loading" || root.catalogState === "loading"
                  indeterminate: true
                  accessibleName: "Loading provider state"
                  Layout.fillWidth: true
                }

                Text {
                  visible: root.currentRoute && root.currentRoute.providerId !== ""
                  text: root.currentRoute ? "Provider: " + root.currentRoute.providerId : ""
                  color: Tokens.text.disabled
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  Layout.fillWidth: true
                }
              }
            }

            Ui.EmptyState {
              visible: root.providerViewState === "ready" && root.visibleResources.length === 0
              Layout.fillWidth: true
              Layout.topMargin: Style.space(20)
              title: root.selectedResourceId === "" ? "No resources reported" : "Requested resource is absent"
              message: root.selectedResourceId === ""
                ? "The provider returned a valid state with no resources."
                : "The current provider result does not contain " + root.selectedResourceId + "."
            }

            Repeater {
              model: root.providerViewState === "ready" ? root.visibleResources : []

              delegate: Rectangle {
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: resourceColumn.implicitHeight + Style.space(24)
                radius: Tokens.radius.medium
                color: Tokens.surface.raised
                border.color: root.selectedResourceId === modelData.id ? Tokens.accent.primary : Tokens.border.subtle
                border.width: 1
                Accessible.role: Accessible.Pane
                Accessible.name: String(modelData.label || modelData.id || "Provider resource")

                ColumnLayout {
                  id: resourceColumn
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  spacing: Style.space(5)

                  Text {
                    text: String(modelData.label || modelData.id || "Unnamed resource")
                    color: Tokens.text.primary
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Text {
                    text: String(modelData.kind || "resource") + " · " + String(modelData.id || "")
                    color: Tokens.text.disabled
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WrapAnywhere
                    Layout.fillWidth: true
                  }

                  Text {
                    visible: modelData.state !== undefined
                    text: JSON.stringify(modelData.state)
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
        }
      }
    }
  }
}
