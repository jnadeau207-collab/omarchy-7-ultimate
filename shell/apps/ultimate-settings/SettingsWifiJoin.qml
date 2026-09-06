import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.Commons
import qs.Ui as Ui
import "SettingsModel.js" as SettingsModel

Rectangle {
  id: root

  property var semanticProfile: null
  property bool pageActive: false

  signal joined(string ssid)
  signal joinFailed(string ssid, string reason)

  radius: Tokens.radius.medium
  color: Tokens.surface.raised
  border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
  border.width: Tokens.accessibility.highContrast ? 2 : 1
  implicitHeight: joinColumn.implicitHeight + Style.space(28)
  Accessible.role: Accessible.Pane
  Accessible.name: Semantics.text(root.semanticProfile, "Available networks")

  readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  readonly property bool wifiEnabled: Networking.wifiEnabled === true
  readonly property var securityEnums: ({
    open: WifiSecurityType.Open,
    owe: WifiSecurityType.Owe,
    wpa2Eap: WifiSecurityType.Wpa2Eap,
    wpaEap: WifiSecurityType.WpaEap,
    wpa2Psk: WifiSecurityType.Wpa2Psk
  })
  readonly property var connectionFailReasons: ({
    NoSecrets: ConnectionFailReason.NoSecrets,
    WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
    WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
    WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
    WifiClientFailed: ConnectionFailReason.WifiClientFailed
  })

  property var wifiNetworks: []
  property bool scanning: false
  property var scannerDevice: null
  property string actionSsid: ""
  property string actionKind: ""
  property string failureSsid: ""
  property string failureReason: ""
  property string passwordSsid: ""
  property string passwordText: ""
  readonly property bool busy: actionKind !== ""

  onPageActiveChanged: {
    if (pageActive) refresh(true)
    else {
      scanRestart.stop()
      scanDone.stop()
      setScannerEnabled(false)
      cancelPasswordPrompt()
      clearNetworkAction()
    }
  }

  onWifiDeviceChanged: {
    if (pageActive) refresh(true)
    else setScannerEnabled(false)
  }

  onWifiNetworkObjectsChanged: syncWifiNetworks()

  Component.onDestruction: {
    if (scannerDevice) scannerDevice.scannerEnabled = false
  }

  function findDevice(type) {
    var devices = networkDevices || []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }

  function setScannerEnabled(enabled) {
    var nextDevice = pageActive ? wifiDevice : null
    if (scannerDevice && scannerDevice !== nextDevice)
      scannerDevice.scannerEnabled = false
    scannerDevice = nextDevice
    if (scannerDevice)
      scannerDevice.scannerEnabled = enabled
  }

  function refresh(scanWifi) {
    if (scanWifi === undefined) scanWifi = false
    if (pageActive && wifiDevice) {
      if (scanWifi) {
        scanning = true
        setScannerEnabled(false)
        scanRestart.start()
      } else {
        setScannerEnabled(true)
      }
    } else {
      setScannerEnabled(false)
    }
    syncWifiNetworks()
  }

  function syncWifiNetworks() {
    var nets = []
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      var network = networks[i]
      if (!network) continue
      checkActionCompletion(network)
      var row = SettingsModel.wifiJoinRow(network)
      if (row) nets.push(row)
    }
    wifiNetworks = SettingsModel.sortWifiJoinRows(nets)
    if (actionKind === "") scanning = false
  }

  function networkForSsid(ssid) {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].name === ssid) return networks[i]
    }
    return null
  }

  function rowForSsid(ssid) {
    for (var i = 0; i < wifiNetworks.length; i++) {
      if (wifiNetworks[i] && wifiNetworks[i].ssid === ssid) return wifiNetworks[i]
    }
    return null
  }

  function cancelPasswordPrompt() {
    passwordSsid = ""
    passwordText = ""
  }

  function clearNetworkAction() {
    actionTimeout.stop()
    if (actionKind === "connect") cancelPasswordPrompt()
    actionSsid = ""
    actionKind = ""
  }

  function checkActionCompletion(network) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    if (actionKind === "connect" && network.connected) {
      var ssid = actionSsid
      clearNetworkAction()
      failureSsid = ""
      failureReason = ""
      root.joined(ssid)
    } else if (actionKind === "disconnect" && !network.connected && !network.stateChanging) {
      clearNetworkAction()
      syncWifiNetworks()
    }
  }

  function failNetworkAction(network, reason) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    actionTimeout.stop()
    var row = SettingsModel.wifiJoinRow(network)
    var action = SettingsModel.wifiJoinAction(row, securityEnums)
    failureSsid = actionSsid
    failureReason = SettingsModel.wifiJoinFailureReason(reason, action, connectionFailReasons)
    actionSsid = ""
    actionKind = ""
    root.joinFailed(failureSsid, failureReason)
    if (action === "prompt-password") {
      passwordSsid = failureSsid
      passwordText = ""
    }
  }

  function joinNetwork(ssid) {
    if (busy) return
    var network = networkForSsid(ssid)
    if (!network) return
    var row = SettingsModel.wifiJoinRow(network)
    var action = SettingsModel.wifiJoinAction(row, securityEnums)
    if (action === "connected") {
      disconnectRow(ssid)
      return
    }
    if (action === "enterprise-unavailable" || action === "hidden") return
    if (action === "prompt-password") {
      if (passwordSsid !== ssid) {
        passwordSsid = ssid
        passwordText = ""
      }
      if (!SettingsModel.wifiJoinCanSubmit(action, passwordText)) return
      runConnect(network, function() { network.connectWithPsk(passwordText) })
      return
    }
    if (!SettingsModel.wifiJoinCanSubmit(action, "")) return
    runConnect(network, function() { network.connect() })
  }

  function runConnect(network, callback) {
    actionSsid = network.name || ""
    actionKind = "connect"
    failureSsid = ""
    failureReason = ""
    callback()
    actionTimeout.restart()
  }

  function disconnectRow(ssid) {
    var network = networkForSsid(ssid)
    if (!network || busy) return
    actionSsid = network.name || ""
    actionKind = "disconnect"
    failureSsid = ""
    failureReason = ""
    network.disconnect()
    actionTimeout.restart()
  }

  readonly property string joinHonesty: {
    if (!networkManagerAvailable)
      return "Wi-Fi join needs NetworkManager in this session. Settings does not send a passphrase through Fabric."
    if (!wifiDevice)
      return "No Wi-Fi adapter is present. Ethernet and other interfaces stay on the inventory cards."
    if (!wifiEnabled)
      return "Turn Wi-Fi on to scan and join. The radio switch above is the durable Fabric writer."
    if (busy && actionKind === "connect")
      return "Connecting to " + actionSsid + "."
    if (busy && actionKind === "disconnect")
      return "Disconnecting " + actionSsid + "."
    if (failureReason !== "")
      return failureReason + (failureSsid !== "" ? " (" + failureSsid + ")." : ".")
    if (scanning)
      return "Scanning for networks."
    if (wifiNetworks.length === 0)
      return "No networks found. Open and password-protected networks can join here; enterprise, VPN, and per-connection DNS stay unavailable."
    return "Join uses this session's NetworkManager access. The passphrase never enters Fabric. Enterprise, VPN, and per-connection DNS stay unavailable."
  }

  readonly property string joinBadge: {
    if (!networkManagerAvailable || !wifiDevice) return "NO ADAPTER"
    if (busy && actionKind === "connect") return "CONNECTING"
    if (busy && actionKind === "disconnect") return "DISCONNECTING"
    if (failureReason !== "") return "FAILED"
    if (scanning) return "SCANNING"
    return "LIVE CONTROL"
  }

  readonly property string joinTone: {
    if (!networkManagerAvailable || !wifiDevice) return "warning"
    if (failureReason !== "") return "danger"
    if (busy || scanning) return "info"
    return "success"
  }

  Timer {
    id: scanRestart
    interval: 100
    repeat: false
    onTriggered: {
      if (root.pageActive && root.wifiDevice) {
        root.setScannerEnabled(true)
        scanDone.start()
      }
    }
  }

  Timer {
    id: scanDone
    interval: 1500
    repeat: false
    onTriggered: root.syncWifiNetworks()
  }

  Timer {
    id: actionTimeout
    interval: 30000
    repeat: false
    onTriggered: {
      if (root.actionKind === "") return
      var network = root.networkForSsid(root.actionSsid)
      if (network) root.failNetworkAction(network, root.connectionFailReasons.WifiClientFailed)
      else {
        root.failureSsid = root.actionSsid
        root.failureReason = "Failed to connect"
        root.joinFailed(root.failureSsid, root.failureReason)
        root.actionSsid = ""
        root.actionKind = ""
      }
    }
  }

  ColumnLayout {
    id: joinColumn
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
        text: Semantics.text(root.semanticProfile, "Available networks")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Ui.Badge {
        text: root.joinBadge
        tone: root.joinTone
        semanticProfile: root.semanticProfile
      }
    }

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.joinHonesty)
      color: Tokens.text.secondary
      font.family: Tokens.typography.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Repeater {
      model: root.wifiNetworks
      delegate: ColumnLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: Style.space(4)

        readonly property string ssid: modelData && modelData.ssid ? modelData.ssid : ""
        readonly property string action: SettingsModel.wifiJoinAction(modelData, root.securityEnums)
        readonly property bool isBusy: root.busy && root.actionSsid === ssid
        readonly property bool isFailed: root.failureReason !== "" && root.failureSsid === ssid
        readonly property bool passwordOpen: root.passwordSsid === ssid
        readonly property var liveNetwork: root.networkForSsid(ssid)

        Connections {
          target: liveNetwork
          function onConnectionFailed(reason) {
            root.failNetworkAction(root.networkForSsid(ssid), reason)
          }
          function onConnectedChanged() {
            root.checkActionCompletion(root.networkForSsid(ssid))
          }
          function onStateChangingChanged() {
            root.checkActionCompletion(root.networkForSsid(ssid))
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: ssid
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
                if (isBusy && root.actionKind === "connect") return Semantics.text(root.semanticProfile, "Connecting")
                if (isBusy && root.actionKind === "disconnect") return Semantics.text(root.semanticProfile, "Disconnecting")
                if (isFailed) return Semantics.text(root.semanticProfile, root.failureReason)
                if (action === "connected") return Semantics.text(root.semanticProfile, "Connected")
                if (action === "enterprise-unavailable") return Semantics.text(root.semanticProfile, "Enterprise Wi-Fi stays unavailable from Settings")
                if (action === "join-known") return Semantics.text(root.semanticProfile, "Saved network")
                if (action === "prompt-password") return Semantics.text(root.semanticProfile, "Password required")
                if (action === "join-open") return Semantics.text(root.semanticProfile, "Open network")
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
            accessibleDescription: Semantics.text(root.semanticProfile, "Disconnect this Wi-Fi network")
            onClicked: root.disconnectRow(ssid)
          }

          Ui.Button {
            visible: action === "join-open" || action === "join-known" || (action === "prompt-password" && !passwordOpen)
            text: action === "join-known" ? "Join" : (action === "prompt-password" ? "Password" : "Join")
            bordered: true
            focusable: true
            enabled: !root.busy
            semanticProfile: root.semanticProfile
            accessibleDescription: Semantics.text(root.semanticProfile, "Join this Wi-Fi network")
            onClicked: {
              if (action === "prompt-password") {
                root.passwordSsid = ssid
                root.passwordText = ""
                return
              }
              root.joinNetwork(ssid)
            }
          }
        }

        RowLayout {
          visible: passwordOpen && action === "prompt-password"
          Layout.fillWidth: true
          spacing: Style.space(8)

          Ui.TextField {
            Layout.fillWidth: true
            password: true
            semanticProfile: root.semanticProfile
            semanticPlaceholderText: "Password"
            accessibleName: "Wi-Fi password"
            enabled: !root.busy
            text: root.passwordSsid === ssid ? root.passwordText : ""
            onTextChanged: if (root.passwordSsid === ssid && text !== root.passwordText) root.passwordText = text
            onAccepted: root.joinNetwork(ssid)
          }

          Ui.Button {
            text: "Join"
            bordered: true
            focusable: true
            enabled: !root.busy && SettingsModel.wifiJoinCanSubmit("prompt-password", root.passwordText)
            semanticProfile: root.semanticProfile
            accessibleDescription: Semantics.text(root.semanticProfile, "Join this Wi-Fi network with the entered password")
            onClicked: root.joinNetwork(ssid)
          }
        }
      }
    }
  }
}
