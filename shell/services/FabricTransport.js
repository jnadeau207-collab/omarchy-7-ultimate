// Bounded state machine for the owner-scoped Fabric RPC socket.
//
// This file deliberately has no QML or Quickshell dependencies. FabricClient.qml
// supplies the Unix-socket adapter, while shell tests supply a deterministic fake
// socket and clock. Keeping the wire state machine here makes every failure path
// testable without starting a second shell process.

var PROTOCOL_NAME = "omarchy.fabric.rpc/v0"
var PROTOCOL_VERSION = 0
var MAX_FRAME_BYTES = 64 * 1024
var MAX_REQUEST_ID_BYTES = 128
var DEFAULT_MAX_PENDING = 64
var DEFAULT_EVENT_BACKLOG = 256
var DEFAULT_REQUEST_TIMEOUT_MS = 5000
var DEFAULT_RECONNECT_BASE_MS = 250
var DEFAULT_RECONNECT_MAX_MS = 8000
var MAX_JSON_DEPTH = 64
var WIRE_CHARACTER_SET = "us-ascii"

var STABLE_ID = /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/
var UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
var CHANGE_STATES = {
  none: true,
  partial: true,
  complete: true,
  unknown: true
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function isInteger(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
}

function isSafeInteger(value) {
  return isInteger(value) && Math.abs(value) <= 9007199254740991
}

function hasOwn(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key)
}

function exactKeys(object, expected) {
  if (!isObject(object)) return false
  var keys = Object.keys(object)
  if (keys.length !== expected.length) return false
  for (var i = 0; i < expected.length; i++) {
    if (!hasOwn(object, expected[i])) return false
  }
  return true
}

function utf8ByteLength(value) {
  var text = String(value)
  var bytes = 0
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code <= 0x7f) {
      bytes += 1
    } else if (code <= 0x7ff) {
      bytes += 2
    } else if (code >= 0xd800 && code <= 0xdbff) {
      if (i + 1 >= text.length) throw new Error("unpaired UTF-16 high surrogate")
      var low = text.charCodeAt(++i)
      if (low < 0xdc00 || low > 0xdfff) throw new Error("unpaired UTF-16 high surrogate")
      bytes += 4
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      throw new Error("unpaired UTF-16 low surrogate")
    } else {
      bytes += 3
    }
  }
  return bytes
}

function fabricError(code, title, explanation, options) {
  var source = options || {}
  var error = {
    code: code,
    title: title,
    explanation: explanation,
    detail: typeof source.detail === "string" ? source.detail : "",
    retryable: source.retryable === true,
    changeState: hasOwn(source, "changeState") ? source.changeState : "none"
  }
  if (Array.isArray(source.recoveryActions) && source.recoveryActions.length > 0)
    error.recoveryActions = source.recoveryActions.slice()
  return error
}

function protocolError(code, explanation, options) {
  return fabricError(
    code,
    "Fabric protocol failure",
    explanation,
    options
  )
}

function characterSetError(detail) {
  return protocolError(
    "rpc.unsupported-character-set",
    "This provisional Quickshell adapter accepts US-ASCII JSON only.",
    {
      detail: detail || "",
      recoveryActions: ["system.update"]
    }
  )
}

function validateJsonValue(value, depth, ancestors) {
  if (depth > MAX_JSON_DEPTH) throw new Error("JSON nesting exceeds the client limit")
  if (value === null || typeof value === "string" || typeof value === "boolean") return
  if (typeof value === "number") {
    if (!isFinite(value)) throw new Error("JSON number is not finite")
    return
  }
  if (typeof value !== "object") throw new Error("value is not JSON")
  if (!Array.isArray(value) && Object.prototype.toString.call(value) !== "[object Object]")
    throw new Error("value is not a plain JSON object")
  if (ancestors.indexOf(value) !== -1) throw new Error("JSON value is cyclic")
  ancestors.push(value)
  if (Array.isArray(value)) {
    for (var i = 0; i < value.length; i++) validateJsonValue(value[i], depth + 1, ancestors)
  } else {
    var keys = Object.keys(value)
    for (var j = 0; j < keys.length; j++) validateJsonValue(value[keys[j]], depth + 1, ancestors)
  }
  ancestors.pop()
}

function isAsciiString(value) {
  if (typeof value !== "string") return false
  for (var i = 0; i < value.length; i++) {
    if (value.charCodeAt(i) > 0x7f) return false
  }
  return true
}

function validateAsciiJsonValue(value, depth) {
  if (depth > MAX_JSON_DEPTH) throw new Error("JSON nesting exceeds the client limit")
  if (typeof value === "string") {
    if (!isAsciiString(value)) throw new Error("non-ASCII JSON string")
    return
  }
  if (value === null || typeof value === "boolean" || typeof value === "number") return
  if (Array.isArray(value)) {
    for (var i = 0; i < value.length; i++) validateAsciiJsonValue(value[i], depth + 1)
    return
  }
  if (isObject(value)) {
    var keys = Object.keys(value)
    for (var j = 0; j < keys.length; j++) {
      if (!isAsciiString(keys[j])) throw new Error("non-ASCII JSON object key")
      validateAsciiJsonValue(value[keys[j]], depth + 1)
    }
  }
}

// JSON.parse discards duplicate object keys, which would make a strict protocol
// validator accept an ambiguous envelope. This small bounded parser rejects them
// before any envelope field is trusted.
function StrictJsonReader(text) {
  this.text = text
  this.index = 0
}

StrictJsonReader.prototype._skipSpace = function() {
  while (this.index < this.text.length && /[\x20\x09\x0a\x0d]/.test(this.text.charAt(this.index)))
    this.index++
}

StrictJsonReader.prototype._parseString = function() {
  if (this.text.charAt(this.index) !== '"') throw new Error("expected JSON string")
  var start = this.index++
  var escaped = false
  while (this.index < this.text.length) {
    var code = this.text.charCodeAt(this.index)
    var character = this.text.charAt(this.index++)
    if (escaped) {
      if (character === "u") {
        var hex = this.text.slice(this.index, this.index + 4)
        if (!/^[0-9a-fA-F]{4}$/.test(hex)) throw new Error("invalid JSON unicode escape")
        this.index += 4
      } else if ('"\\/bfnrt'.indexOf(character) === -1) {
        throw new Error("invalid JSON escape")
      }
      escaped = false
    } else if (character === "\\") {
      escaped = true
    } else if (character === '"') {
      return JSON.parse(this.text.slice(start, this.index))
    } else if (code < 0x20) {
      throw new Error("unescaped control character in JSON string")
    }
  }
  throw new Error("unterminated JSON string")
}

StrictJsonReader.prototype._parseNumber = function() {
  var match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(this.text.slice(this.index))
  if (!match) throw new Error("invalid JSON number")
  this.index += match[0].length
  var value = Number(match[0])
  if (!isFinite(value)) throw new Error("non-finite JSON number")
  return value
}

StrictJsonReader.prototype._parseArray = function(depth) {
  this.index++
  var result = []
  this._skipSpace()
  if (this.text.charAt(this.index) === "]") {
    this.index++
    return result
  }
  while (true) {
    result.push(this._parseValue(depth + 1))
    this._skipSpace()
    var separator = this.text.charAt(this.index++)
    if (separator === "]") return result
    if (separator !== ",") throw new Error("expected comma or array terminator")
    this._skipSpace()
  }
}

StrictJsonReader.prototype._parseObject = function(depth) {
  this.index++
  var result = Object.create(null)
  var seen = Object.create(null)
  this._skipSpace()
  if (this.text.charAt(this.index) === "}") {
    this.index++
    return result
  }
  while (true) {
    var key = this._parseString()
    if (hasOwn(seen, key)) throw new Error("duplicate JSON object key: " + key)
    seen[key] = true
    this._skipSpace()
    if (this.text.charAt(this.index++) !== ":") throw new Error("expected colon after JSON object key")
    this._skipSpace()
    result[key] = this._parseValue(depth + 1)
    this._skipSpace()
    var separator = this.text.charAt(this.index++)
    if (separator === "}") return result
    if (separator !== ",") throw new Error("expected comma or object terminator")
    this._skipSpace()
  }
}

StrictJsonReader.prototype._parseValue = function(depth) {
  if (depth > MAX_JSON_DEPTH) throw new Error("JSON nesting exceeds the client limit")
  this._skipSpace()
  var character = this.text.charAt(this.index)
  if (character === '"') return this._parseString()
  if (character === "{") return this._parseObject(depth)
  if (character === "[") return this._parseArray(depth)
  if (this.text.slice(this.index, this.index + 4) === "true") {
    this.index += 4
    return true
  }
  if (this.text.slice(this.index, this.index + 5) === "false") {
    this.index += 5
    return false
  }
  if (this.text.slice(this.index, this.index + 4) === "null") {
    this.index += 4
    return null
  }
  return this._parseNumber()
}

StrictJsonReader.prototype.parse = function() {
  var value = this._parseValue(0)
  this._skipSpace()
  if (this.index !== this.text.length) throw new Error("trailing data after JSON value")
  return value
}

function strictParseJson(text) {
  return new StrictJsonReader(String(text)).parse()
}

function validStableId(value) {
  return typeof value === "string" && value.length >= 1 && value.length <= 160 && STABLE_ID.test(value)
}

function validRequestId(value) {
  if (typeof value !== "string" || value.length === 0) return false
  try {
    return utf8ByteLength(value) <= MAX_REQUEST_ID_BYTES
  } catch (error) {
    return false
  }
}

function validateRemoteError(value) {
  var required = ["code", "title", "explanation", "detail", "retryable", "changeState"]
  var keys = Object.keys(value || {})
  if (!isObject(value) || keys.length < required.length || keys.length > required.length + 1)
    throw new Error("invalid Fabric error envelope")
  for (var i = 0; i < required.length; i++) {
    if (!hasOwn(value, required[i])) throw new Error("invalid Fabric error envelope")
  }
  if (keys.length === required.length + 1 && !hasOwn(value, "recoveryActions"))
    throw new Error("unknown Fabric error field")
  if (!validStableId(value.code)) throw new Error("invalid Fabric error code")
  if (typeof value.title !== "string" || value.title.length < 1 || value.title.length > 160)
    throw new Error("invalid Fabric error title")
  if (typeof value.explanation !== "string" || value.explanation.length < 1 || value.explanation.length > 2000)
    throw new Error("invalid Fabric error explanation")
  if (typeof value.detail !== "string" || value.detail.length > 16000)
    throw new Error("invalid Fabric error detail")
  if (typeof value.retryable !== "boolean" || !hasOwn(CHANGE_STATES, value.changeState))
    throw new Error("invalid Fabric error state")
  var actions = hasOwn(value, "recoveryActions") ? value.recoveryActions : []
  if (!Array.isArray(actions)) throw new Error("invalid Fabric recovery actions")
  var seen = Object.create(null)
  for (var j = 0; j < actions.length; j++) {
    if (!validStableId(actions[j]) || hasOwn(seen, actions[j]))
      throw new Error("invalid Fabric recovery action")
    seen[actions[j]] = true
  }
  return value
}

function validateEvent(value) {
  if (!exactKeys(value, ["sequence", "id", "topic", "payload", "createdAt"]))
    throw new Error("invalid Fabric event envelope")
  if (!isSafeInteger(value.sequence) || value.sequence < 1) throw new Error("invalid Fabric event sequence")
  if (typeof value.id !== "string" || !UUID.test(value.id)) throw new Error("invalid Fabric event ID")
  if (!validStableId(value.topic)) throw new Error("invalid Fabric event topic")
  if (!isObject(value.payload)) throw new Error("invalid Fabric event payload")
  if (typeof value.createdAt !== "number" || !isFinite(value.createdAt) || value.createdAt < 0)
    throw new Error("invalid Fabric event timestamp")
  return value
}

function positiveInteger(value, fallback) {
  return isInteger(value) && value > 0 ? value : fallback
}

function nonNegativeNumber(value, fallback) {
  return typeof value === "number" && isFinite(value) && value >= 0 ? value : fallback
}

function FabricEngine(options) {
  var config = options || {}
  this.clientName = typeof config.clientName === "string" && config.clientName.length > 0
    ? config.clientName : "omarchy-shell"
  this.maxPending = positiveInteger(config.maxPending, DEFAULT_MAX_PENDING)
  this.eventBacklog = positiveInteger(config.eventBacklog, DEFAULT_EVENT_BACKLOG)
  this.requestTimeoutMs = positiveInteger(config.requestTimeoutMs, DEFAULT_REQUEST_TIMEOUT_MS)
  this.reconnectBaseMs = positiveInteger(config.reconnectBaseMs, DEFAULT_RECONNECT_BASE_MS)
  this.reconnectMaxMs = positiveInteger(config.reconnectMaxMs, DEFAULT_RECONNECT_MAX_MS)
  if (this.reconnectMaxMs < this.reconnectBaseMs) this.reconnectMaxMs = this.reconnectBaseMs

  this.callbacks = config.callbacks || {}
  this.allowedMethods = Object.create(null)
  this.setAllowedMethods(config.allowedMethods || [])

  this.wanted = false
  this.transportUp = false
  this.connectInFlight = false
  this.ready = false
  this.compatibilityBlocked = false
  this.disconnectExpected = false
  this.suppressDisconnectFeedback = false
  this.state = "disabled"
  this.lastError = null
  this.generation = 0
  this.requestSerial = 0
  this.pending = Object.create(null)
  this.events = []
  this.rxBuffer = ""
  this.rxBytes = 0
  this.reconnectAttempt = 0
  this.reconnectAt = null
}

FabricEngine.prototype._call = function(name, args) {
  var callback = this.callbacks[name]
  if (typeof callback !== "function") return undefined
  try {
    return callback.apply(null, args || [])
  } catch (error) {
    var observer = this.callbacks.onCallbackError
    if (name !== "onCallbackError" && typeof observer === "function") observer(name, String(error))
    return undefined
  }
}

FabricEngine.prototype.snapshot = function() {
  return {
    state: this.state,
    ready: this.ready,
    pendingCount: Object.keys(this.pending).length,
    eventCount: this.events.length,
    compatibilityBlocked: this.compatibilityBlocked,
    disconnectExpected: this.disconnectExpected,
    suppressDisconnectFeedback: this.suppressDisconnectFeedback,
    reconnectAttempt: this.reconnectAttempt,
    lastError: this.lastError
  }
}

FabricEngine.prototype._publish = function() {
  this._call("onState", [this.snapshot()])
}

FabricEngine.prototype._setState = function(state) {
  this.state = state
  this._publish()
}

FabricEngine.prototype.setAllowedMethods = function(methods) {
  this.allowedMethods = Object.create(null)
  if (!Array.isArray(methods)) return
  for (var i = 0; i < methods.length; i++) {
    if (validStableId(methods[i])) this.allowedMethods[methods[i]] = true
  }
}

FabricEngine.prototype.start = function(now) {
  if (this.wanted) return false
  this.wanted = true
  this.compatibilityBlocked = false
  this.lastError = null
  this.reconnectAttempt = 0
  this.reconnectAt = nonNegativeNumber(now, 0)
  if (this.disconnectExpected) {
    this._setState("disconnecting")
    return true
  }
  this.suppressDisconnectFeedback = false
  this._setState("connecting")
  this.tick(now)
  return true
}

FabricEngine.prototype.stop = function(now) {
  if (!this.wanted && this.state === "disabled") return
  var needsCloseFeedback = this.transportUp || this.connectInFlight || this.disconnectExpected
  var disabledError = fabricError(
    "client.disabled",
    "Fabric client disabled",
    "The client stopped before the request completed.",
    { changeState: "unknown" }
  )
  this.wanted = false
  this.compatibilityBlocked = false
  this.disconnectExpected = needsCloseFeedback
  this.reconnectAt = null
  this.connectInFlight = false
  this.ready = false
  this.lastError = null
  this._failAll(disabledError)
  if (needsCloseFeedback) this._call("onCloseNeeded", [disabledError])
  this.transportUp = false
  this.rxBuffer = ""
  this.rxBytes = 0
  this.events = []
  this._setState("disabled")
}

FabricEngine.prototype.retry = function(now) {
  if (
    !this.wanted || this.ready || this.transportUp || this.connectInFlight ||
    this.disconnectExpected || (!this.compatibilityBlocked && this.state !== "reconnecting")
  ) return false
  this.compatibilityBlocked = false
  this.lastError = null
  this.reconnectAttempt = 0
  this.reconnectAt = nonNegativeNumber(now, 0)
  this._setState("connecting")
  this.tick(now)
  return true
}

FabricEngine.prototype.tick = function(now) {
  var current = nonNegativeNumber(now, 0)
  var ids = Object.keys(this.pending)
  for (var i = 0; i < ids.length; i++) {
    var entry = this.pending[ids[i]]
    if (entry && current >= entry.deadline) {
      delete this.pending[ids[i]]
      var timeout = fabricError(
        "rpc.timeout",
        "Fabric request timed out",
        "The daemon did not finish the request before the client deadline.",
        { retryable: true, changeState: "unknown", recoveryActions: ["fabric.reconnect"] }
      )
      this._deliverError(ids[i], entry, timeout)
      if (entry.kind === "hello") {
        this._fatal(timeout, current, false)
        return
      }
    }
  }
  if (
    this.wanted && !this.compatibilityBlocked && !this.disconnectExpected &&
    !this.transportUp && !this.connectInFlight &&
    this.reconnectAt !== null && current >= this.reconnectAt
  ) {
    this.reconnectAt = null
    this.suppressDisconnectFeedback = false
    this.connectInFlight = true
    this._setState("connecting")
    this._call("onConnectNeeded", [])
  } else {
    this._publish()
  }
}

FabricEngine.prototype.transportOpened = function(now) {
  if (!this.wanted || this.compatibilityBlocked || this.disconnectExpected) {
    this.disconnectExpected = true
    this._call("onCloseNeeded", [this.lastError])
    return
  }
  this.connectInFlight = false
  this.suppressDisconnectFeedback = false
  this.transportUp = true
  this.ready = false
  this.generation++
  this.requestSerial = 0
  this.rxBuffer = ""
  this.rxBytes = 0
  this.events = []
  this.reconnectAt = null
  this._setState("handshaking")
  var hello = this._beginRequest(
    "hello",
    { client: this.clientName, minVersion: PROTOCOL_VERSION, maxVersion: PROTOCOL_VERSION },
    "hello",
    null,
    nonNegativeNumber(now, 0)
  )
  if (!hello.ok)
    this._fatal(hello.error, now, hello.error.code === "rpc.unsupported-character-set")
}

FabricEngine.prototype._scheduleReconnect = function(now) {
  if (!this.wanted || this.compatibilityBlocked) return
  var multiplier = Math.pow(2, Math.min(this.reconnectAttempt, 20))
  var delay = Math.min(this.reconnectMaxMs, this.reconnectBaseMs * multiplier)
  this.reconnectAttempt++
  this.reconnectAt = nonNegativeNumber(now, 0) + delay
  this._setState("reconnecting")
  this._call("onReconnectScheduled", [delay, this.reconnectAttempt])
}

FabricEngine.prototype.transportClosed = function(reason, now) {
  if (this.disconnectExpected) {
    this.disconnectExpected = false
    this.suppressDisconnectFeedback = true
    this.transportUp = false
    this.connectInFlight = false
    this.ready = false
    this.rxBuffer = ""
    this.rxBytes = 0
    if (!this.wanted) {
      this._setState("disabled")
    } else if (this.compatibilityBlocked) {
      this._setState("incompatible")
    } else {
      if (this.reconnectAt === null) this.reconnectAt = nonNegativeNumber(now, 0)
      this.tick(now)
    }
    return
  }
  if (this.suppressDisconnectFeedback && !this.transportUp && !this.connectInFlight) return
  if (!this.wanted && this.state === "disabled" && !this.transportUp && !this.connectInFlight) return
  if (!this.transportUp && !this.connectInFlight && this.reconnectAt !== null) {
    if (isObject(reason)) {
      this.lastError = reason
      this._publish()
    }
    return
  }
  this.transportUp = false
  this.connectInFlight = false
  this.ready = false
  var truncated = this.rxBytes > 0 || this.rxBuffer.length > 0
  this.rxBuffer = ""
  this.rxBytes = 0
  var error
  if (truncated) {
    error = protocolError(
      "rpc.truncated-frame",
      "The Fabric connection closed before the response newline arrived.",
      { retryable: true, changeState: "unknown", recoveryActions: ["fabric.reconnect"] }
    )
    this._call("onProtocolError", [error])
  } else {
    error = isObject(reason) ? reason : fabricError(
      "daemon.disconnected",
      "Fabric connection closed",
      "The Fabric daemon closed the connection.",
      { retryable: true, changeState: "unknown", recoveryActions: ["fabric.reconnect"] }
    )
  }
  this.lastError = error
  this._failAll(error)
  if (!this.wanted) {
    this._setState("disabled")
  } else if (this.compatibilityBlocked) {
    this._setState("incompatible")
  } else {
    this._scheduleReconnect(now)
  }
}

FabricEngine.prototype._nextRequestId = function() {
  this.requestSerial++
  return "qml-" + this.generation + "-" + this.requestSerial
}

FabricEngine.prototype._writeEnvelope = function(envelope) {
  try {
    validateJsonValue(envelope, 0, [])
  } catch (error) {
    return { ok: false, error: protocolError(
      "rpc.invalid-request",
      "The request cannot be encoded as finite bounded JSON.",
      { detail: String(error) }
    ) }
  }
  try {
    validateAsciiJsonValue(envelope, 0)
  } catch (asciiError) {
    return { ok: false, error: characterSetError(String(asciiError)) }
  }
  try {
    var frame = JSON.stringify(envelope)
    if (frame.length > MAX_FRAME_BYTES) {
      return { ok: false, error: protocolError(
        "rpc.frame-too-large",
        "A Fabric frame may contain at most " + MAX_FRAME_BYTES + " US-ASCII bytes."
      ) }
    }
    var sender = this.callbacks.sendFrame
    if (typeof sender !== "function") throw new Error("socket adapter has no sendFrame callback")
    var accepted
    try {
      accepted = sender(frame + "\n")
    } catch (sendError) {
      return { ok: false, error: fabricError(
        "daemon.disconnected",
        "Fabric connection closed",
        "The Fabric socket failed while writing the request frame.",
        { detail: String(sendError), retryable: true, changeState: "unknown", recoveryActions: ["fabric.reconnect"] }
      ) }
    }
    if (accepted === false) {
      return { ok: false, error: fabricError(
        "daemon.disconnected",
        "Fabric connection closed",
        "The Fabric socket did not accept the request frame.",
        { retryable: true, changeState: "unknown", recoveryActions: ["fabric.reconnect"] }
      ) }
    }
    return { ok: true }
  } catch (error) {
    return { ok: false, error: protocolError(
      "rpc.invalid-request",
      "The request cannot be encoded as finite bounded JSON.",
      { detail: String(error) }
    ) }
  }
}

FabricEngine.prototype._beginRequest = function(method, params, kind, handlers, now) {
  if (Object.keys(this.pending).length >= this.maxPending) {
    return { ok: false, error: fabricError(
      "rpc.pending-limit",
      "Fabric request limit reached",
      "Wait for an in-flight request to finish before sending another request.",
      { retryable: true }
    ) }
  }
  var id = this._nextRequestId()
  var entry = {
    kind: kind || "request",
    handlers: handlers || {},
    deadline: nonNegativeNumber(now, 0) + this.requestTimeoutMs
  }
  this.pending[id] = entry
  var write = this._writeEnvelope({
    protocol: PROTOCOL_NAME,
    id: id,
    method: method,
    params: params
  })
  if (!write.ok) {
    delete this.pending[id]
    this._deliverError(id, entry, write.error)
    return { ok: false, id: id, error: write.error }
  }
  this._publish()
  return { ok: true, id: id }
}

FabricEngine.prototype.request = function(method, params, handlers, now) {
  if (!validStableId(method)) {
    return { ok: false, error: protocolError("rpc.invalid-method", "Fabric methods use stable dotted identifiers.") }
  }
  if (!hasOwn(this.allowedMethods, method)) {
    return { ok: false, error: fabricError(
      "client.method-denied",
      "Fabric method is not enabled",
      "This client instance has no authority to request that method."
    ) }
  }
  if (!this.ready || !this.transportUp) {
    return { ok: false, error: fabricError(
      "daemon.disconnected",
      "Fabric is disconnected",
      "Wait for the Fabric handshake before sending a request.",
      { retryable: true, recoveryActions: ["fabric.reconnect"] }
    ) }
  }
  if (!isObject(params)) {
    return { ok: false, error: protocolError("rpc.invalid-params", "Fabric request params must be a JSON object.") }
  }
  try {
    validateJsonValue(params, 0, [])
  } catch (error) {
    return { ok: false, error: protocolError(
      "rpc.invalid-params",
      "Fabric request params must contain finite acyclic JSON.",
      { detail: String(error) }
    ) }
  }
  try {
    validateAsciiJsonValue(params, 0)
  } catch (asciiError) {
    return { ok: false, error: characterSetError(String(asciiError)) }
  }
  var outcome = this._beginRequest(method, params, "request", handlers, now)
  if (!outcome.ok && outcome.error && outcome.error.code === "daemon.disconnected")
    this.transportClosed(outcome.error, now)
  return outcome
}

FabricEngine.prototype.cancel = function(requestId) {
  var id = String(requestId || "")
  var entry = this.pending[id]
  if (!entry || entry.kind === "hello") return false
  delete this.pending[id]
  this._deliverError(id, entry, fabricError(
    "rpc.cancelled",
    "Fabric request cancelled locally",
    "The client stopped waiting for this request. The remote change state is unknown.",
    { changeState: "unknown" }
  ))
  this._publish()
  return true
}

FabricEngine.prototype._deliverResult = function(id, entry, result) {
  if (entry.handlers && typeof entry.handlers.onResult === "function")
    entry.handlers.onResult(id, result)
  if (entry.kind !== "hello") this._call("onRequestResult", [id, result])
}

FabricEngine.prototype._deliverError = function(id, entry, error) {
  if (entry.handlers && typeof entry.handlers.onError === "function")
    entry.handlers.onError(id, error)
  if (entry.kind !== "hello") this._call("onRequestError", [id, error])
}

FabricEngine.prototype._failAll = function(error) {
  var ids = Object.keys(this.pending)
  for (var i = 0; i < ids.length; i++) {
    var entry = this.pending[ids[i]]
    delete this.pending[ids[i]]
    this._deliverError(ids[i], entry, error)
  }
  this._publish()
}

FabricEngine.prototype._fatal = function(error, now, compatibilityFailure) {
  var needsCloseFeedback = this.transportUp || this.connectInFlight
  this.lastError = error
  this.compatibilityBlocked = compatibilityFailure === true
  this.disconnectExpected = needsCloseFeedback
  this.ready = false
  this.transportUp = false
  this.connectInFlight = false
  this.rxBuffer = ""
  this.rxBytes = 0
  this._failAll(error)
  this._call("onProtocolError", [error])
  if (this.compatibilityBlocked) {
    this.reconnectAt = null
    this._setState("incompatible")
  } else {
    this._scheduleReconnect(now)
  }
  if (needsCloseFeedback) this._call("onCloseNeeded", [error])
}

FabricEngine.prototype.receiveChunk = function(chunk, now) {
  if (!this.transportUp) return
  if (typeof chunk !== "string") {
    this._fatal(protocolError("rpc.invalid-encoding", "Fabric socket chunks must be text."), now, false)
    return
  }
  if (!isAsciiString(chunk)) {
    this._fatal(characterSetError(
      "Quickshell exposes independently decoded QString chunks, so non-ASCII bytes cannot be framed safely."
    ), now, true)
    return
  }
  var start = 0
  while (start <= chunk.length && this.transportUp) {
    var newline = chunk.indexOf("\n", start)
    var end = newline === -1 ? chunk.length : newline
    var piece = chunk.slice(start, end)
    this.rxBytes += piece.length
    if (this.rxBytes > MAX_FRAME_BYTES) {
      this._fatal(protocolError(
        "rpc.frame-too-large",
        "A Fabric frame may contain at most " + MAX_FRAME_BYTES + " US-ASCII bytes."
      ), now, false)
      return
    }
    this.rxBuffer += piece
    if (newline === -1) return
    var line = this.rxBuffer
    this.rxBuffer = ""
    this.rxBytes = 0
    this._handleFrame(line, now)
    start = newline + 1
    if (start === chunk.length) return
  }
}

FabricEngine.prototype._handleFrame = function(line, now) {
  var message
  try {
    message = strictParseJson(line)
  } catch (error) {
    this._fatal(protocolError(
      "rpc.invalid-json",
      "Fabric sent malformed or ambiguous JSON.",
      { detail: String(error) }
    ), now, false)
    return
  }
  try {
    validateAsciiJsonValue(message, 0)
  } catch (asciiError) {
    this._fatal(characterSetError(String(asciiError)), now, true)
    return
  }
  if (!isObject(message)) {
    this._fatal(protocolError("rpc.invalid-response", "Every Fabric response frame must be a JSON object."), now, false)
    return
  }
  if (message.protocol !== PROTOCOL_NAME) {
    this._fatal(protocolError(
      "rpc.incompatible-protocol",
      "The daemon replied with an unsupported Fabric protocol.",
      { recoveryActions: ["system.update"] }
    ), now, true)
    return
  }
  var keys = Object.keys(message)
  if (exactKeys(message, ["protocol", "event"])) {
    if (!this.ready) {
      this._fatal(protocolError("rpc.event-before-hello", "Fabric sent an event before the hello handshake completed."), now, false)
      return
    }
    var event
    try {
      event = validateEvent(message.event)
    } catch (error) {
      this._fatal(protocolError("rpc.invalid-response", String(error)), now, false)
      return
    }
    if (this.events.length >= this.eventBacklog) {
      this._fatal(fabricError(
        "events.client-overflow",
        "Fabric client event backlog overflowed",
        "The client did not consume Fabric events before its bounded backlog filled.",
        { retryable: true, changeState: "unknown", recoveryActions: ["events.reconnect-and-replay"] }
      ), now, false)
      return
    }
    this.events.push(event)
    this._call("onEvent", [event])
    this._publish()
    return
  }
  var kind = ""
  if (exactKeys(message, ["protocol", "id", "result"])) kind = "result"
  else if (exactKeys(message, ["protocol", "id", "error"])) kind = "error"
  else {
    this._fatal(protocolError(
      "rpc.invalid-response",
      "A Fabric response must contain exactly one result, error, or event envelope.",
      { detail: "keys=" + keys.sort().join(",") }
    ), now, false)
    return
  }
  if (!validRequestId(message.id)) {
    this._fatal(protocolError("rpc.invalid-response", "Fabric returned an invalid response ID."), now, false)
    return
  }
  if (kind === "error") {
    try {
      validateRemoteError(message.error)
    } catch (error) {
      this._fatal(protocolError("rpc.invalid-response", String(error)), now, false)
      return
    }
  }
  var entry = this.pending[message.id]
  if (!entry) {
    this._call("onLateResponse", [message.id, kind])
    return
  }
  delete this.pending[message.id]
  if (entry.kind === "hello") {
    if (kind === "error") {
      var incompatible = message.error.code === "rpc.incompatible-version" ||
        message.error.code === "rpc.incompatible-protocol"
      this._deliverError(message.id, entry, message.error)
      this._fatal(message.error, now, incompatible)
      return
    }
    this._finishHello(message.id, entry, message.result, now)
    return
  }
  if (kind === "error") this._deliverError(message.id, entry, message.error)
  else this._deliverResult(message.id, entry, message.result)
  this._publish()
}

FabricEngine.prototype._finishHello = function(id, entry, result, now) {
  if (!isObject(result)) {
    this._fatal(protocolError("rpc.invalid-handshake", "Fabric hello returned a non-object result."), now, false)
    return
  }
  if (result.protocol !== PROTOCOL_NAME || result.version !== PROTOCOL_VERSION) {
    this._fatal(protocolError(
      "rpc.incompatible-version",
      "The daemon selected a Fabric protocol version this shell does not implement.",
      { recoveryActions: ["system.update"] }
    ), now, true)
    return
  }
  if (result.client !== this.clientName || typeof result.connectionId !== "string" || result.connectionId.length === 0) {
    this._fatal(protocolError("rpc.invalid-handshake", "Fabric hello did not bind the requested client identity."), now, false)
    return
  }
  this.ready = true
  this.reconnectAttempt = 0
  this.lastError = null
  this._deliverResult(id, entry, result)
  this._setState("ready")
  this._call("onReady", [result])
}

FabricEngine.prototype.takeEvent = function() {
  if (this.events.length === 0) return null
  var event = this.events.shift()
  this._publish()
  return event
}

function createEngine(options) {
  return new FabricEngine(options)
}

if (typeof module !== "undefined") {
  module.exports = {
    PROTOCOL_NAME: PROTOCOL_NAME,
    PROTOCOL_VERSION: PROTOCOL_VERSION,
    MAX_FRAME_BYTES: MAX_FRAME_BYTES,
    MAX_REQUEST_ID_BYTES: MAX_REQUEST_ID_BYTES,
    DEFAULT_MAX_PENDING: DEFAULT_MAX_PENDING,
    DEFAULT_EVENT_BACKLOG: DEFAULT_EVENT_BACKLOG,
    WIRE_CHARACTER_SET: WIRE_CHARACTER_SET,
    utf8ByteLength: utf8ByteLength,
    isAsciiString: isAsciiString,
    strictParseJson: strictParseJson,
    validateRemoteError: validateRemoteError,
    validateEvent: validateEvent,
    fabricError: fabricError,
    createEngine: createEngine
  }
}
