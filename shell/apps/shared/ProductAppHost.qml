import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.services as Services

import "ProductProtocol.js" as ProductProtocol

ShellRoot {
  id: root

  required property string applicationId
  required property string appId
  required property string displayName
  required property string ipcTarget
  required property string routeCatalogPath
  required property string fabricIdentity
  required property var fabricAllowedMethods
  required property string applicationSourcePath

  property var routeCatalog: null
  property string routeCatalogError: "Route catalog is loading."
  property string currentRoute: ""
  property var currentArguments: ({})
  property var invocationContext: ({ screen: null, anchor: null, seat: null, focusReturn: null, source: "desktop" })
  property int activationSerial: 0
  property var targetScreen: null
  property string placementState: "automatic"
  property var fabricPrincipal: null

  // Shell chrome takes RTL and pseudo-locale from a Start summon payload. A
  // product window is its own process, so it reads the same two flags from the
  // state file the shell publishes them to.
  property bool presentationRtl: false
  property bool presentationPseudoLocale: false

  function applyPresentation(raw) {
    var parsed = ({})
    try { parsed = JSON.parse(String(raw || "{}")) } catch (e) { parsed = ({}) }
    root.presentationRtl = parsed.rtl === true
    root.presentationPseudoLocale = parsed.pseudoLocale === true
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/ultimate/presentation.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyPresentation(text())
    onFileChanged: reload()
    onLoadFailed: root.applyPresentation("")
  }

  SemanticProfile {
    id: chromeProfile
    profileId: "product"
    rtl: root.presentationRtl
    pseudoLocale: root.presentationPseudoLocale
  }
  readonly property var productProfile: chromeProfile

  readonly property bool fabricReady: fabric.ready
  readonly property string fabricConnectionState: fabric.connectionState
  readonly property var fabricLastError: fabric.lastError
  readonly property string fabricPrincipalId: fabricPrincipal && fabricPrincipal.id ? String(fabricPrincipal.id) : ""
  readonly property string fabricPrincipalEndpoint: fabricPrincipal && fabricPrincipal.endpoint ? String(fabricPrincipal.endpoint) : ""
  readonly property var window: appWindow

  signal routeActivated(string routeId, var arguments, var context)
  signal fabricConnectionReady(var hello)
  signal fabricResult(string requestId, var result)
  signal fabricFailure(string requestId, var error)

  function routeById(routeId) {
    if (!root.routeCatalog || !Array.isArray(root.routeCatalog.routes)) return null
    for (var i = 0; i < root.routeCatalog.routes.length; i++) {
      if (root.routeCatalog.routes[i].id === routeId) return root.routeCatalog.routes[i]
    }
    return null
  }

  function screenByName(name) {
    if (!name) return null
    for (var i = 0; i < Quickshell.screens.length; i++) {
      if (String(Quickshell.screens[i].name || "") === name) return Quickshell.screens[i]
    }
    return null
  }

  function applyPlacement(context) {
    var requested = context && context.screen ? String(context.screen) : ""
    if (requested === "") {
      root.placementState = "automatic"
      if (!root.targetScreen && Quickshell.screens.length > 0) root.targetScreen = Quickshell.screens[0]
      return
    }
    var selected = root.screenByName(requested)
    if (selected) {
      root.targetScreen = selected
      root.placementState = "requested-screen"
    } else {
      root.placementState = "requested-screen-unavailable"
    }
  }

  function activateEnvelope(envelopeJson) {
    var validated = ProductProtocol.validateEnvelope(envelopeJson, root.routeCatalog)
    if (!validated.ok) return "rejected:" + validated.code
    root.currentRoute = validated.envelope.routeId
    root.currentArguments = validated.envelope.arguments
    root.invocationContext = validated.envelope.context
    root.activationSerial++
    root.applyPlacement(validated.envelope.context)
    appWindow.visible = true
    appWindow.minimized = false
    root.routeActivated(root.currentRoute, root.currentArguments, root.invocationContext)
    return "ok"
  }

  function navigate(routeId, arguments) {
    var envelope = {
      schemaVersion: "omarchy.product-launch/v1",
      application: root.applicationId,
      routeId: String(routeId || ""),
      arguments: arguments || {},
      context: root.invocationContext
    }
    return root.activateEnvelope(JSON.stringify(envelope)) === "ok"
  }

  function requestFabric(method, parameters) {
    return fabric.request(method, parameters || {})
  }

  function cancelFabric(requestId) {
    return fabric.cancel(String(requestId || ""))
  }

  function retryFabric() {
    return fabric.retryConnection()
  }

  FileView {
    id: routeCatalogFile
    path: Quickshell.shellPath(root.routeCatalogPath)
    watchChanges: false
    printErrors: false
    onLoaded: {
      var candidate
      try {
        candidate = JSON.parse(text())
      } catch (error) {
        root.routeCatalog = null
        root.routeCatalogError = "The route catalog is malformed: " + error
        return
      }
      var validation = ProductProtocol.validateCatalog(candidate, root.applicationId, root.appId)
      if (!validation.ok) {
        root.routeCatalog = null
        root.routeCatalogError = validation.explanation
        return
      }
      root.routeCatalog = validation.catalog
      root.routeCatalogError = ""
      if (root.currentRoute === "") {
        root.currentRoute = validation.catalog.defaultRoute
        root.activationSerial++
        root.routeActivated(root.currentRoute, root.currentArguments, root.invocationContext)
      }
    }
    onLoadFailed: {
      root.routeCatalog = null
      root.routeCatalogError = "The route catalog could not be read."
    }
  }

  Services.FabricClient {
    id: fabric
    active: true
    clientName: root.fabricIdentity
    allowedMethods: root.fabricAllowedMethods
    onConnectionReady: function(hello) {
      root.fabricPrincipal = hello && hello.principal ? hello.principal : null
      root.fabricConnectionReady(hello)
    }
    onRequestSucceeded: function(requestId, result) { root.fabricResult(requestId, result) }
    onRequestFailed: function(requestId, error) { root.fabricFailure(requestId, error) }
    onRequestRejected: function(error) { root.fabricFailure("", error) }
  }

  IpcHandler {
    target: root.ipcTarget

    function activate(envelopeJson: string): string {
      return root.activateEnvelope(envelopeJson)
    }

    function status(): string {
      return JSON.stringify({
        schemaVersion: "omarchy.product-host-status/v1",
        application: root.applicationId,
        appId: root.appId,
        processId: Quickshell.processId,
        route: root.currentRoute,
        activationSerial: root.activationSerial,
        placementState: root.placementState,
        fabricIdentity: root.fabricIdentity,
        fabricState: root.fabricConnectionState,
        fabricPrincipalId: root.fabricPrincipalId,
        fabricPrincipalEndpoint: root.fabricPrincipalEndpoint
      })
    }

    function route(): string { return root.currentRoute }
    function processId(): int { return Quickshell.processId }
    function fabricClientIdentity(): string { return root.fabricIdentity }
    function fabricEndpointPrincipal(): string { return root.fabricPrincipalId }
  }

  FloatingWindow {
    id: appWindow
    reloadableId: root.applicationId + ".window"
    title: root.displayName
    visible: true
    implicitWidth: 1100
    implicitHeight: 720
    minimumSize: Qt.size(760, 520)
    maximumSize: Qt.size(16384, 16384)
    screen: root.targetScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    color: Tokens.surface.canvas
    onClosed: Qt.quit()

    Rectangle {
      anchors.fill: parent
      color: Tokens.surface.canvas

      Loader {
        id: applicationLoader
        anchors.fill: parent
        active: root.routeCatalog !== null
        source: Quickshell.shellPath(root.applicationSourcePath)
        onLoaded: item.host = root
      }

      Rectangle {
        anchors.fill: parent
        visible: root.routeCatalog === null
        color: Tokens.surface.canvas

        Column {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(48), 560)
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.displayName + " cannot start"
            color: Tokens.text.primary
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.routeCatalogError
            color: Tokens.text.secondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  Component.onCompleted: {
    if (Quickshell.screens.length > 0) root.targetScreen = Quickshell.screens[0]
  }
}
