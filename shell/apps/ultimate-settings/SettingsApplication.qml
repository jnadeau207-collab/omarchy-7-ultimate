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
  readonly property var productProfile: host && host.productProfile ? host.productProfile : null

  readonly property var currentRoute: host ? host.routeById(host.currentRoute) : null
  readonly property var hostedSpec: SettingsModel.hostedPanel(host ? host.currentRoute : "")
  readonly property bool hostedPage: hostedSpec !== null
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

  property string operationStage: ""
  property string operationRequestId: ""
  property string operationId: ""
  property string operationMessage: ""
  property int operationTarget: 0
  property string operationKind: ""
  property string operationProfile: ""
  readonly property bool operationBusy: operationStage !== ""
  readonly property var audioResource: firstAudioResource()
  readonly property int audioPercent: currentAudioPercent()
  readonly property var powerResource: firstPowerResource()
  readonly property var powerProfiles: powerResource && powerResource.profiles ? powerResource.profiles : []
  readonly property string activePowerProfile: powerResource ? String(powerResource.activeProfile || "") : ""

  readonly property var browserResource: firstBrowserResource()
  readonly property var browserOptions: browserResource ? SettingsModel.browserCandidates(browserResource, queryState.records) : []
  readonly property string activeBrowserId: browserResource ? String(browserResource.defaultAppId || "") : ""
  property string operationBrowserId: ""

  function firstBrowserResource() {
    if (!currentRoute || currentRoute.id !== "settings.apps.overview") return null
    var record = SettingsModel.browserAssociation(queryState.records)
    return record && record.writable ? record : null
  }

  function applyDefaultBrowser(appId) {
    if (!host || operationBusy) return
    var record = firstBrowserResource()
    if (!record || record.candidateAppIds.indexOf(appId) < 0) return
    root.operationKind = "browser"
    root.operationBrowserId = String(appId)
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "defaults.provider",
      action: "protocol.set",
      arguments: { scheme: record.associationKey, appId: root.operationBrowserId },
      idempotencyKey: "settings.default-browser." + root.operationBrowserId + "." + Date.now()
    })
    if (root.operationRequestId === "") root.resetOperation("Settings could not reach the operation service.")
  }

  function browserLabel(appId) {
    for (var i = 0; i < browserOptions.length; i++) {
      if (browserOptions[i].id === appId) return browserOptions[i].label
    }
    return "this application"
  }
  readonly property var radioResource: firstRadioResource()
  readonly property bool radioEnabled: radioResource ? radioResource.radioEnabled === true : false
  readonly property bool radioBlocked: radioResource ? radioResource.radioBlocked === true : false
  property bool operationRadioTarget: false

  function firstRadioResource() {
    if (!currentRoute || currentRoute.id !== "settings.network.overview") return null
    if (!queryState.records) return null
    for (var i = 0; i < queryState.records.length; i++) {
      if (queryState.records[i].radioControllable) return queryState.records[i]
    }
    return null
  }

  function applyWifiEnabled(enabled) {
    if (!host || operationBusy) return
    var record = firstRadioResource()
    if (!record) return
    if (enabled && record.radioBlocked) return
    root.operationKind = "network"
    root.operationRadioTarget = enabled === true
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "network.provider",
      action: "wifi.set-enabled",
      arguments: { resourceId: record.id, enabled: root.operationRadioTarget },
      idempotencyKey: "settings.wifi." + (root.operationRadioTarget ? "on" : "off") + "." + Date.now()
    })
    if (root.operationRequestId === "") root.resetOperation("Settings could not reach the operation service.")
  }
  readonly property var layoutResource: firstLayoutResource()
  readonly property var keyboardLayouts: layoutResource && layoutResource.layouts ? layoutResource.layouts : []
  readonly property int activeLayoutIndex: layoutResource ? layoutResource.activeLayoutIndex : -1
  property int operationLayoutIndex: -1

  function firstLayoutResource() {
    if (!currentRoute || currentRoute.id !== "settings.input.overview") return null
    if (!queryState.records) return null
    for (var i = 0; i < queryState.records.length; i++) {
      if (queryState.records[i].layouts && queryState.records[i].layouts.length > 1) return queryState.records[i]
    }
    return null
  }

  function applyKeyboardLayout(index) {
    if (!host || operationBusy) return
    var record = firstLayoutResource()
    if (!record) return
    if (!(index >= 0 && index < record.layouts.length)) return
    root.operationKind = "input"
    root.operationLayoutIndex = index
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "input.provider",
      action: "keyboard-layout.set",
      arguments: { resourceId: record.id, layoutIndex: index },
      idempotencyKey: "settings.keyboard-layout." + record.id + "." + index + "." + Date.now()
    })
    if (root.operationRequestId === "") root.resetOperation("Settings could not reach the operation service.")
  }

  readonly property var brightnessResource: firstBrightnessResource()
  readonly property int brightnessPercent: brightnessResource ? brightnessResource.brightnessPercent : -1

  function firstBrightnessResource() {
    if (!currentRoute || currentRoute.id !== "settings.display.overview") return null
    if (!queryState.records) return null
    for (var i = 0; i < queryState.records.length; i++) {
      if (queryState.records[i].brightnessAvailable) return queryState.records[i]
    }
    return null
  }

  function applyBrightness(percent) {
    if (!host || operationBusy) return
    var record = firstBrightnessResource()
    if (!record) return
    root.operationKind = "display"
    root.operationTarget = Math.max(0, Math.min(100, Math.round(percent)))
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "display.provider",
      action: "brightness.set",
      arguments: { resourceId: record.id, percent: root.operationTarget },
      idempotencyKey: "settings.brightness." + record.id + "." + root.operationTarget + "." + Date.now()
    })
    if (root.operationRequestId === "") root.resetOperation("Settings could not reach the operation service.")
  }

  function firstPowerResource() {
    if (!currentRoute || currentRoute.id !== "settings.power.overview") return null
    if (!queryState.records || queryState.records.length === 0) return null
    return queryState.records[0]
  }

  function profileLabel(profile) {
    if (profile === "power-saver") return "Power saver"
    if (profile === "balanced") return "Balanced"
    if (profile === "performance") return "Performance"
    return profile
  }

  function applyPowerProfile(profile) {
    if (!host || operationBusy) return
    var record = firstPowerResource()
    if (!record || SettingsModel.POWER_PROFILES.indexOf(profile) < 0) return
    if (record.profiles.indexOf(profile) < 0) return
    root.operationKind = "power"
    root.operationProfile = String(profile)
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "power.provider",
      action: "profile.set",
      arguments: { resourceId: record.id, profile: root.operationProfile },
      idempotencyKey: "settings.power-profile." + root.operationProfile + "." + Date.now()
    })
    if (root.operationRequestId === "") root.resetOperation("Settings could not reach the operation service.")
  }

  function firstAudioResource() {
    if (!queryState.records || queryState.records.length === 0) return null
    return queryState.records[0]
  }

  function currentAudioPercent() {
    var record = firstAudioResource()
    if (!record || !record.details) return 0
    for (var i = 0; i < record.details.length; i++) {
      var label = String(record.details[i].label || "").toLowerCase()
      if (label.indexOf("front-left") >= 0 || label.indexOf("channel") >= 0) {
        var parsed = parseInt(String(record.details[i].value).replace(/[^0-9]/g, ""), 10)
        if (!isNaN(parsed)) return parsed
      }
    }
    return 0
  }

  function applyAudioVolume(percent) {
    if (!host || operationBusy) return
    var record = firstAudioResource()
    if (!record) return
    root.operationKind = "audio"
    root.operationTarget = Math.max(0, Math.min(100, Math.round(percent)))
    root.operationMessage = ""
    root.operationStage = "preflight"
    root.operationRequestId = host.requestFabric("operation.preflight", {
      provider: "audio.provider",
      action: "output-volume.set",
      arguments: { resourceId: record.id, percent: root.operationTarget },
      idempotencyKey: "settings.volume." + root.operationTarget + "." + Date.now()
    })
    if (root.operationRequestId === "") root.resetOperation("Settings could not reach the operation service.")
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
      var applied = root.operationKind === "power"
        ? "Power profile set to " + root.profileLabel(root.operationProfile) + "."
        : root.operationKind === "display"
          ? "Brightness set to " + root.operationTarget + " percent."
          : root.operationKind === "input"
            ? "Keyboard layout set to " + root.keyboardLayouts[root.operationLayoutIndex] + "."
            : root.operationKind === "browser"
              ? "Default browser set to " + root.browserLabel(root.operationBrowserId) + "."
            : root.operationKind === "network"
              ? "Wi-Fi turned " + (root.operationRadioTarget ? "on" : "off") + "."
            : "Output volume set to " + root.operationTarget + " percent."
      var refused = root.operationKind === "power"
        ? "The power profile change ended as " + String(result.status || "unknown") + "."
        : root.operationKind === "display"
          ? "The brightness change ended as " + String(result.status || "unknown") + "."
          : root.operationKind === "input"
            ? "The keyboard layout change ended as " + String(result.status || "unknown") + "."
            : root.operationKind === "browser"
              ? "The default browser change ended as " + String(result.status || "unknown") + "."
            : root.operationKind === "network"
              ? "The Wi-Fi change ended as " + String(result.status || "unknown") + "."
            : "The volume change ended as " + String(result.status || "unknown") + "."
      root.resetOperation(succeeded ? applied : refused)
      if (root.controller) root.controller.refresh()
    }
  }

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
      if (root.operationBusy && requestId === root.operationRequestId) {
        root.advanceOperation(result)
        return
      }
      if (root.controller) root.controller.receiveResult(requestId, result)
    }

    function onFabricFailure(requestId, error) {
      if (root.operationBusy && requestId === root.operationRequestId) {
        root.resetOperation(error && error.explanation
          ? String(error.explanation)
          : (root.operationKind === "power" ? "The power profile change failed." : "The volume change failed."))
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
      title: "Settings"
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
              text: Semantics.text(root.productProfile, root.currentRoute ? root.currentRoute.title : "Settings")
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
              text: Semantics.text(root.productProfile, root.hostedPage && root.hostedSpec
                ? root.hostedSpec.honesty
                : (root.currentRoute ? root.currentRoute.description : "The requested route is unavailable."))
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
            text: root.hostedPage ? "LIVE PANEL" : SettingsModel.phaseBadge(root.queryState)
            tone: root.hostedPage ? "info" : SettingsModel.phaseTone(root.queryState)
            Layout.alignment: Qt.AlignTop
          }
        }

        Ui.SettingsHostedPanel {
          visible: root.hostedPage
          sourcePath: root.hostedSpec ? root.hostedSpec.source : ""
          Layout.fillWidth: true
          Layout.fillHeight: true
        }

        Controls.ScrollView {
          id: contentScroll
          visible: !root.hostedPage
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
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile, SettingsModel.stateTitle(root.queryState))
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
                  text: Semantics.text(root.productProfile, SettingsModel.stateExplanation(root.queryState))
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
                    ? "Loading Settings provider catalog" : "Loading current Settings provider state"
                  Layout.fillWidth: true
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.domainVisible
                  text: SettingsModel.provenance(root.queryState)
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
                  text: "Exact resource: " + SettingsModel.clippedText(root.queryState.selectedResourceId, 180)
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
                  text: Semantics.text(root.productProfile, "Detail") + ": " + SettingsModel.clippedText(root.queryState.error ? root.queryState.error.detail : "", 480)
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

                      text: "\u2022 " + SettingsModel.clippedText(modelData, 320)
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
                      tooltipText: "Open the read-only " + modelData.title + " Settings route"
                      semanticProfile: root.productProfile
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
              visible: root.currentRoute && root.currentRoute.id === "settings.audio.overview" && root.audioResource !== null
              Layout.fillWidth: true
              implicitHeight: volumeColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Output volume"

              ColumnLayout {
                id: volumeColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(14)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile, "Output volume")
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Badge {
                    text: root.operationBusy ? "APPLYING" : "LIVE CONTROL"
                    tone: root.operationBusy ? "info" : "success"
                  }
                }

                Ui.PanelSlider {
                  id: volumeSlider
                  Layout.fillWidth: true
                  minimum: 0
                  maximum: 100
                  value: root.operationBusy ? root.operationTarget : root.audioPercent
                  enabled: !root.operationBusy
                  onReleased: function(next) { root.applyAudioVolume(next) }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.operationMessage !== ""
                    ? root.operationMessage
                    : Semantics.text(root.productProfile,
                        "Changes run through the durable operation service as this user, never with elevated privilege.")
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                }
              }
            }

            Rectangle {
              visible: root.currentRoute && root.currentRoute.id === "settings.apps.overview" && root.browserOptions.length > 1
              Layout.fillWidth: true
              implicitHeight: browserColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Default browser"

              ColumnLayout {
                id: browserColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(14)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile, "Default browser")
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Badge {
                    text: root.operationBusy && root.operationKind === "browser" ? "APPLYING" : "LIVE CONTROL"
                    tone: root.operationBusy && root.operationKind === "browser" ? "info" : "success"
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Repeater {
                    model: root.browserOptions
                    delegate: Ui.Button {
                      required property var modelData
                      text: modelData.label
                      focusable: true
                      bordered: true
                      enabled: !root.operationBusy && modelData.id !== root.activeBrowserId
                      accessibleDescription: "Set the default browser through defaults.provider protocol.set"
                      onClicked: root.applyDefaultBrowser(modelData.id)
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.operationMessage !== "" && root.operationKind === "browser"
                    ? root.operationMessage
                    : Semantics.text(root.productProfile,
                        "Only applications that declare they handle web links are shown. Changes run through the durable operation service as this user, never with elevated privilege.")
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                }
              }
            }
            Rectangle {
              visible: root.currentRoute && root.currentRoute.id === "settings.network.overview" && root.radioResource !== null
              Layout.fillWidth: true
              implicitHeight: radioColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Wi-Fi"

              ColumnLayout {
                id: radioColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(14)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile, "Wi-Fi")
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Badge {
                    text: root.operationBusy && root.operationKind === "network" ? "APPLYING"
                      : root.radioBlocked ? "BLOCKED BY HARDWARE" : "LIVE CONTROL"
                    tone: root.operationBusy && root.operationKind === "network" ? "info"
                      : root.radioBlocked ? "warning" : "success"
                  }
                }

                Ui.Toggle {
                  id: radioToggle
                  Layout.fillWidth: true
                  label: root.radioEnabled ? "Wi-Fi is on" : "Wi-Fi is off"
                  checked: root.operationBusy && root.operationKind === "network" ? root.operationRadioTarget : root.radioEnabled
                  enabled: !root.operationBusy && !(root.radioBlocked && !root.radioEnabled)
                  onClicked: root.applyWifiEnabled(!radioToggle.checked)
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.operationMessage !== "" && root.operationKind === "network"
                    ? root.operationMessage
                    : root.radioBlocked
                      ? Semantics.text(root.productProfile, "A hardware switch or airplane mode is holding this radio off. Settings cannot turn it back on.")
                      : Semantics.text(root.productProfile, "Changes run through the durable operation service as this user, never with elevated privilege.")
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                }
              }
            }
            Rectangle {
              visible: root.currentRoute && root.currentRoute.id === "settings.input.overview" && root.keyboardLayouts.length > 1
              Layout.fillWidth: true
              implicitHeight: layoutColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Keyboard layout"

              ColumnLayout {
                id: layoutColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(14)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile,
                      root.layoutResource ? "Keyboard layout — " + root.layoutResource.label : "Keyboard layout")
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Badge {
                    text: root.operationBusy && root.operationKind === "input" ? "APPLYING" : "LIVE CONTROL"
                    tone: root.operationBusy && root.operationKind === "input" ? "info" : "success"
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Repeater {
                    model: root.keyboardLayouts
                    delegate: Ui.Button {
                      required property int index
                      required property string modelData
                      text: modelData
                      focusable: true
                      bordered: true
                      enabled: !root.operationBusy && index !== root.activeLayoutIndex
                      accessibleDescription: "Set the active keyboard layout through input.provider keyboard-layout.set"
                      onClicked: root.applyKeyboardLayout(index)
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.operationMessage !== "" && root.operationKind === "input"
                    ? root.operationMessage
                    : Semantics.text(root.productProfile,
                        "Only keyboards carrying more than one layout are shown. Changes run through the durable operation service as this user, never with elevated privilege.")
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                }
              }
            }
            Rectangle {
              visible: root.currentRoute && root.currentRoute.id === "settings.display.overview" && root.brightnessResource !== null
              Layout.fillWidth: true
              implicitHeight: brightnessColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Display brightness"

              ColumnLayout {
                id: brightnessColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(14)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile,
                      root.brightnessResource ? "Brightness — " + root.brightnessResource.label : "Brightness")
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Badge {
                    text: root.operationBusy && root.operationKind === "display" ? "APPLYING" : "LIVE CONTROL"
                    tone: root.operationBusy && root.operationKind === "display" ? "info" : "success"
                  }
                }

                Ui.PanelSlider {
                  id: brightnessSlider
                  Layout.fillWidth: true
                  minimum: 0
                  maximum: 100
                  value: root.operationBusy && root.operationKind === "display" ? root.operationTarget : root.brightnessPercent
                  enabled: !root.operationBusy
                  onReleased: function(next) { root.applyBrightness(next) }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.operationMessage !== "" && root.operationKind === "display"
                    ? root.operationMessage
                    : Semantics.text(root.productProfile,
                        "Only outputs that expose a controllable backlight are shown. Changes run through the durable operation service as this user, never with elevated privilege.")
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                }
              }
            }

            Rectangle {
              visible: root.currentRoute && root.currentRoute.id === "settings.power.overview" && root.powerProfiles.length > 0
              Layout.fillWidth: true
              implicitHeight: profileColumn.implicitHeight + Style.space(28)
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
              border.width: Tokens.accessibility.highContrast ? 2 : 1
              Accessible.role: Accessible.Pane
              Accessible.name: "Power profile"

              ColumnLayout {
                id: profileColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(14)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile, "Power profile")
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    Layout.fillWidth: true
                  }

                  Ui.Badge {
                    text: root.operationBusy && root.operationKind === "power" ? "APPLYING" : "LIVE CONTROL"
                    tone: root.operationBusy && root.operationKind === "power" ? "info" : "success"
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Repeater {
                    model: root.powerProfiles
                    delegate: Ui.Button {
                      required property string modelData
                      text: root.profileLabel(modelData)
                      focusable: true
                      bordered: true
                      enabled: !root.operationBusy && modelData !== root.activePowerProfile
                      accessibleDescription: "Set the active power profile through power.provider profile.set"
                      onClicked: root.applyPowerProfile(modelData)
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.operationMessage !== "" && root.operationKind === "power"
                    ? root.operationMessage
                    : Semantics.text(root.productProfile,
                        "The active profile is " + root.profileLabel(root.activePowerProfile) +
                        ". Changes run through the durable operation service as this user, never with elevated privilege.")
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
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
                    textFormat: Text.PlainText
                    text: Semantics.text(root.productProfile, "Coverage")
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
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
                    Semantics.text(root.productProfile, root.currentRoute && root.currentRoute.id === "settings.audio.overview"
                      ? "Settings runs this operation through preflight, approval, and the durable coordinator."
                      : "Settings exposes no preflight, approval, or execution control for this domain yet.")
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
                text: "Display bound reached at " + SettingsModel.MAX_VISIBLE_RECORDS + " records. " +
                  root.queryState.totalRecords + " records were reported; use an exact resource deep link for a narrower view."
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
}
