import QtQuick
import Quickshell
import Quickshell.Io

import "FabricTransport.js" as FabricTransport

// Reusable, authority-free adapter for the owner-scoped Fabric Unix socket.
// Callers must explicitly list every public RPC method they are permitted to
// request. The hello handshake is internal and cannot be replaced by a caller.
Item {
  id: root
  visible: false

  property bool active: false
  property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy/fabric.sock"
  property string clientName: "omarchy-shell"
  property var allowedMethods: []
  property int maxPendingRequests: 64
  property int maxBufferedEvents: 256
  property int requestTimeoutMs: 5000
  property int reconnectBaseMs: 250
  property int reconnectMaxMs: 8000
  property int clockIntervalMs: 50

  readonly property string protocol: "omarchy.fabric.rpc/v0"
  readonly property int protocolVersion: 0
  readonly property int maxFrameBytes: 65536
  readonly property string wireCharacterSet: "us-ascii"
  readonly property bool supportsUnicode: false
  readonly property string connectionState: root._state
  readonly property bool ready: root._ready
  readonly property int pendingRequestCount: root._pendingRequestCount
  readonly property int bufferedEventCount: root._bufferedEventCount
  readonly property bool compatibilityBlocked: root._compatibilityBlocked
  readonly property var lastError: root._lastError

  property string _state: "disabled"
  property bool _ready: false
  property int _pendingRequestCount: 0
  property int _bufferedEventCount: 0
  property bool _compatibilityBlocked: false
  property var _lastError: null
  property var _engine: null
  property bool _cyclingSocket: false
  property int _wireGeneration: 0

  signal connectionReady(var hello)
  signal requestSucceeded(string requestId, var result)
  signal requestFailed(string requestId, var error)
  signal requestRejected(var error)
  signal eventReceived(var event)
  signal protocolFailed(var error)
  signal lateResponseIgnored(string requestId, string kind)

  function _applySnapshot(snapshot) {
    if (!snapshot) return
    root._state = String(snapshot.state || "disabled")
    root._ready = snapshot.ready === true
    root._pendingRequestCount = Number(snapshot.pendingCount || 0)
    root._bufferedEventCount = Number(snapshot.eventCount || 0)
    root._compatibilityBlocked = snapshot.compatibilityBlocked === true
    root._lastError = snapshot.lastError || null
  }

  function _startEngine() {
    if (!root._engine) return
    root._engine.setAllowedMethods(root.allowedMethods)
    root._engine.start(Date.now())
  }

  function _wire() {
    return wireLoader.item
  }

  function _stopEngine() {
    if (root._engine) root._engine.stop(Date.now())
    if (root._wire()) root._wire().connected = false
  }

  function _recycleWire(connectAfter) {
    root._wireGeneration += 1
    var generation = root._wireGeneration
    root._cyclingSocket = true
    if (root._wire()) root._wire().connected = false
    wireLoader.active = false
    root._cyclingSocket = false
    if (connectAfter !== true) return
    Qt.callLater(function() {
      if (generation !== root._wireGeneration) return
      if (!root.active || root.socketPath === "") return
      wireLoader.active = true
      if (!root._wire()) return
      root._wire().path = root.socketPath
      root._wire().connected = true
    })
  }

  function request(method, params) {
    if (!root._engine) return ""
    var outcome = root._engine.request(String(method || ""), params || {}, null, Date.now())
    if (!outcome.ok) {
      root.requestRejected(outcome.error)
      return ""
    }
    return outcome.id
  }

  function cancel(requestId) {
    return root._engine ? root._engine.cancel(String(requestId || "")) : false
  }

  // Cancellation here only stops local correlation. A consequential operation
  // must use its typed operation-cancel RPC and reconcile the resulting state.
  function takeEvent() {
    return root._engine ? root._engine.takeEvent() : null
  }

  function retryConnection() {
    return root._engine ? root._engine.retry(Date.now()) : false
  }

  onActiveChanged: {
    if (!root._engine) return
    if (active) root._startEngine()
    else root._stopEngine()
  }

  onAllowedMethodsChanged: {
    if (root._engine) root._engine.setAllowedMethods(allowedMethods)
  }

  Component.onCompleted: {
    root._engine = FabricTransport.createEngine({
      clientName: root.clientName,
      allowedMethods: root.allowedMethods,
      maxPending: root.maxPendingRequests,
      eventBacklog: root.maxBufferedEvents,
      requestTimeoutMs: root.requestTimeoutMs,
      reconnectBaseMs: root.reconnectBaseMs,
      reconnectMaxMs: root.reconnectMaxMs,
      callbacks: {
        onState: function(snapshot) { root._applySnapshot(snapshot) },
        onConnectNeeded: function() {
          if (!root.active || root.socketPath === "") return
          // Quickshell Socket binds an inode for the life of the object.
          // Toggling path/connected on the same instance never opens a
          // replaced fabric.sock; destroy and create a new Socket instead.
          root._recycleWire(true)
        },
        onCloseNeeded: function(reason) {
          if (root._wire()) root._wire().connected = false
        },
        sendFrame: function(frame) {
          var sock = root._wire()
          if (!sock || !sock.connected) return false
          sock.write(frame)
          sock.flush()
          return true
        },
        onReady: function(hello) { root.connectionReady(hello) },
        onRequestResult: function(requestId, result) {
          root.requestSucceeded(requestId, result)
        },
        onRequestError: function(requestId, error) {
          root.requestFailed(requestId, error)
        },
        onEvent: function(event) { root.eventReceived(event) },
        onProtocolError: function(error) { root.protocolFailed(error) },
        onLateResponse: function(requestId, kind) {
          root.lateResponseIgnored(requestId, kind)
        },
        onCallbackError: function(name, detail) {
          console.warn("Fabric client callback failed:", name, detail)
        }
      }
    })
    if (root.active) root._startEngine()
  }

  Component.onDestruction: root._stopEngine()

  Component {
    id: wireFactory
    Socket {
      id: instance
      connected: false

      // Empty splitMarker yields arbitrary independently decoded chunks. This is
      // bounded only because the provisional adapter rejects every non-ASCII raw
      // or escaped value; one ASCII byte always maps to one QString character.
      parser: SplitParser {
        splitMarker: ""
        onRead: function(data) {
          if (root._engine) root._engine.receiveChunk(data, Date.now())
        }
      }

      onConnectedChanged: {
        if (!root._engine || root._cyclingSocket) return
        if (connected) root._engine.transportOpened(Date.now())
        else root._engine.transportClosed(null, Date.now())
      }

      onError: function(error) {
        if (!root._engine) return
        root._engine.transportClosed({
          code: "daemon.socket-error",
          title: "Fabric socket failed",
          explanation: "Quickshell could not maintain the owner-scoped Fabric socket.",
          detail: String(error),
          retryable: true,
          changeState: "unknown",
          recoveryActions: ["fabric.reconnect"]
        }, Date.now())
        instance.connected = false
      }
    }
  }

  Loader {
    id: wireLoader
    active: false
    sourceComponent: wireFactory
  }

  Timer {
    interval: Math.max(10, root.clockIntervalMs)
    repeat: true
    running: root.active && root._engine !== null
    onTriggered: root._engine.tick(Date.now())
  }
}
