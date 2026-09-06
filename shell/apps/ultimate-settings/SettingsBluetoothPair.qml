import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui as Ui
import "SettingsModel.js" as SettingsModel

Rectangle {
  id: root

  property var semanticProfile: null
  property bool pageActive: false

  signal paired(string address)
  signal connected(string address)
  signal pairFailed(string address, string reason)

  radius: Tokens.radius.medium
  color: Tokens.surface.raised
  border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
  border.width: Tokens.accessibility.highContrast ? 2 : 1
  implicitHeight: pairColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "Bluetooth devices")

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var deviceObjects: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property bool adapterEnabled: !!(adapter && adapter.enabled)
  property var groups: ({ connected: [], known: [], discovered: [] })
  property bool owesDiscoveryStop: false
  property string actionAddress: ""
  property string actionKind: ""
  property string failureAddress: ""
  property string failureReason: ""
  readonly property bool busy: actionKind !== ""

  onPageActiveChanged: {
    if (pageActive) startDiscovery()
    else stopDiscovery()
  }

  onAdapterChanged: {
    if (pageActive) startDiscovery()
    else stopDiscovery()
  }

  onDeviceObjectsChanged: syncDevices()

  Component.onDestruction: stopDiscovery()

  function syncDevices() {
    groups = SettingsModel.bluetoothDeviceGroups(deviceObjects || [])
    checkActionCompletion()
  }

  function deviceForAddress(address) {
    var devices = deviceObjects || []
    for (var i = 0; i < devices.length; i++) {
      if (devices[i] && devices[i].address === address) return devices[i]
    }
    return null
  }

  function startDiscovery() {
    discoveryRetry.stop()
    if (!(pageActive && adapter && adapter.enabled)) {
      stopDiscovery()
      return
    }
    owesDiscoveryStop = true
    if (!adapter.discovering) adapter.discovering = true
    discoveryRetry.start()
  }

  function stopDiscovery() {
    discoveryRetry.stop()
    if (owesDiscoveryStop && adapter && adapter.discovering)
      adapter.discovering = false
    owesDiscoveryStop = false
    clearAction()
  }

  function clearAction() {
    actionTimeout.stop()
    actionAddress = ""
    actionKind = ""
  }

  function checkActionCompletion() {
    if (actionKind === "" || actionAddress === "") return
    var device = deviceForAddress(actionAddress)
    if (actionKind === "pair" && device && (device.paired || device.bonded || device.trusted)) {
      var address = actionAddress
      if (typeof device.connect === "function") device.connect()
      actionKind = "connect"
      actionTimeout.restart()
      return
    }
    if ((actionKind === "pair" || actionKind === "connect") && device && device.connected) {
      var done = actionAddress
      var kind = actionKind
      clearAction()
      failureAddress = ""
      failureReason = ""
      if (kind === "pair") root.paired(done)
      root.connected(done)
      return
    }
    if (actionKind === "disconnect" && (!device || !device.connected)) {
      clearAction()
      syncDevices()
    }
  }

  function failAction(reason) {
    actionTimeout.stop()
    failureAddress = actionAddress
    failureReason = reason || "Failed to connect"
    var address = actionAddress
    actionAddress = ""
    actionKind = ""
    root.pairFailed(address, failureReason)
  }

  function pairOrConnect(address) {
    if (busy) return
    var device = deviceForAddress(address)
    if (!device) return
    var row = SettingsModel.bluetoothDeviceRow(device)
    var action = SettingsModel.bluetoothPairAction(row)
    if (action === "connected") {
      disconnectDevice(address)
      return
    }
    if (!SettingsModel.bluetoothCanSubmit(action)) return
    actionAddress = address
    actionKind = action
    failureAddress = ""
    failureReason = ""
    if (device.trusted === false) device.trusted = true
    if (action === "pair") {
      if (typeof device.pair === "function") device.pair()
      else if (typeof device.connect === "function") device.connect()
      else {
        failAction("Pairing is unavailable in this session.")
        return
      }
    } else if (typeof device.connect === "function") device.connect()
    else {
      failAction("Connecting is unavailable in this session.")
      return
    }
    actionTimeout.restart()
  }

  function disconnectDevice(address) {
    var device = deviceForAddress(address)
    if (!device || busy) return
    actionAddress = address
    actionKind = "disconnect"
    failureAddress = ""
    failureReason = ""
    if (typeof device.disconnect === "function") device.disconnect()
    else {
      failAction("Disconnect is unavailable in this session.")
      return
    }
    actionTimeout.restart()
  }

  readonly property var visibleRows: {
    var rows = []
    var i
    for (i = 0; i < (groups.connected || []).length; i++) rows.push(groups.connected[i])
    for (i = 0; i < (groups.known || []).length; i++) rows.push(groups.known[i])
    for (i = 0; i < (groups.discovered || []).length; i++) rows.push(groups.discovered[i])
    return rows
  }

  readonly property string pairHonesty: {
    if (!adapter)
      return "No Bluetooth adapter is present. Pairing stays unavailable until this computer has a BlueZ adapter."
    if (!adapterEnabled)
      return "Turn Bluetooth on to scan and pair. Settings uses this session's BlueZ adapter; pairing secrets never enter Fabric."
    if (busy && actionKind === "pair")
      return "Pairing " + actionAddress + "."
    if (busy && actionKind === "connect")
      return "Connecting " + actionAddress + "."
    if (busy && actionKind === "disconnect")
      return "Disconnecting " + actionAddress + "."
    if (failureReason !== "")
      return failureReason
    if (adapter.discovering)
      return "Scanning for devices. Pairing uses this session's BlueZ adapter; pairing secrets never enter Fabric."
    if (visibleRows.length === 0)
      return "No devices found. Audio routing, PIN-entry UI, and adapter rfkill stay unavailable from Settings."
    return "Pair and connect use this session's BlueZ adapter. Pairing secrets never enter Fabric. Audio routing, PIN-entry UI, and adapter rfkill stay unavailable."
  }

  readonly property string pairBadge: {
    if (!adapter) return "NO ADAPTER"
    if (!adapterEnabled) return "OFF"
    if (busy && actionKind === "pair") return "PAIRING"
    if (busy && actionKind === "connect") return "CONNECTING"
    if (busy && actionKind === "disconnect") return "DISCONNECTING"
    if (failureReason !== "") return "FAILED"
    if (adapter.discovering) return "SCANNING"
    return "LIVE CONTROL"
  }

  readonly property string pairTone: {
    if (!adapter || !adapterEnabled) return "warning"
    if (failureReason !== "") return "danger"
    if (busy || (adapter && adapter.discovering)) return "info"
    return "success"
  }

  Timer {
    id: discoveryRetry
    interval: 1000
    repeat: true
    running: root.pageActive && root.adapter && adapter.enabled && !adapter.discovering
    onTriggered: {
      root.owesDiscoveryStop = true
      if (root.adapter) root.adapter.discovering = true
    }
  }

  Timer {
    id: actionTimeout
    interval: 20000
    repeat: false
    onTriggered: {
      if (root.actionKind === "") return
      root.failAction("Timed out")
    }
  }

  Connections {
    target: root.adapter
    function onDiscoveringChanged() {
      if (root.adapter && !root.adapter.discovering && !root.pageActive)
        root.owesDiscoveryStop = false
    }
    function onEnabledChanged() {
      if (root.pageActive) root.startDiscovery()
    }
  }

  ColumnLayout {
    id: pairColumn
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
        text: Semantics.text(root.semanticProfile, "Bluetooth devices")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.pairBadge
        tone: root.pairTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.pairHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Repeater {
      model: root.visibleRows
      delegate: RowLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: Style.space(8)

        readonly property string address: modelData && modelData.address ? modelData.address : ""
        readonly property string action: SettingsModel.bluetoothPairAction(modelData)
        readonly property bool isBusy: root.busy && root.actionAddress === address
        readonly property bool isFailed: root.failureReason !== "" && root.failureAddress === address
        readonly property var liveDevice: root.deviceForAddress(address)

        Connections {
          target: liveDevice
          function onConnectedChanged() { root.checkActionCompletion() }
          function onPairedChanged() { root.checkActionCompletion() }
          function onPairingChanged() { root.checkActionCompletion() }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: modelData && modelData.label ? modelData.label : address
            color: Tokens.text.primary
            font.family: Tokens.typography.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Text {
            textFormat: Text.PlainText
            text: {
              if (isBusy && root.actionKind === "pair") return Semantics.text(root.semanticProfile, "Pairing")
              if (isBusy && root.actionKind === "connect") return Semantics.text(root.semanticProfile, "Connecting")
              if (isBusy && root.actionKind === "disconnect") return Semantics.text(root.semanticProfile, "Disconnecting")
              if (isFailed) return Semantics.text(root.semanticProfile, root.failureReason)
              if (action === "connected") return Semantics.text(root.semanticProfile, "Connected")
              if (action === "connect") return Semantics.text(root.semanticProfile, "Paired")
              if (action === "pair") return Semantics.text(root.semanticProfile, "Available")
              return ""
            }
            color: isFailed ? Tokens.state.danger : Tokens.text.secondary
            font.family: Tokens.typography.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }
        }

        Ui.Button {
          visible: action === "connected"
          text: "Disconnect"
          bordered: true
          focusable: true
          enabled: !root.busy
          semanticProfile: root.semanticProfile
          accessibleDescription: Semantics.text(root.semanticProfile, "Disconnect this Bluetooth device")
          onClicked: root.disconnectDevice(address)
        }

        Ui.Button {
          visible: action === "connect" || action === "pair"
          text: action === "pair" ? "Pair" : "Connect"
          bordered: true
          focusable: true
          enabled: !root.busy
          semanticProfile: root.semanticProfile
          accessibleDescription: Semantics.text(root.semanticProfile, action === "pair" ? "Pair this Bluetooth device" : "Connect this Bluetooth device")
          onClicked: root.pairOrConnect(address)
        }
      }
    }
  }
}
