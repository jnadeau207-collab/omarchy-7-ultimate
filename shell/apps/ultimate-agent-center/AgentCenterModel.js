var QUERY_METHOD = "managed-work.query"
var QUERY_VERSION = "v0"
var PAGE_SIZE = 20
var MAX_VISIBLE_ITEMS = 100
var MAX_CURSOR_LENGTH = 1024
var MAX_DISPLAY_TEXT = 640

var QUERY_VIEWS = [
  "agent.overview",
  "agent.tasks",
  "agent.approvals",
  "agent.automations",
  "agent.activity",
  "agent.history",
  "agent.context",
  "agent.permissions",
  "agent.usage",
  "agent.providers",
  "agent.artifacts",
  "agent.troubleshooting"
]

var PAGINATED_VIEWS = {
  "agent.tasks": true,
  "agent.approvals": true,
  "agent.automations": true,
  "agent.activity": true,
  "agent.history": true,
  "agent.context": true,
  "agent.permissions": true,
  "agent.usage": true,
  "agent.providers": true,
  "agent.artifacts": true
}

var EXPECTED_KINDS = {
  "agent.approvals": "approval-projection",
  "agent.automations": "managed-automation",
  "agent.activity": "operation-link",
  "agent.history": "managed-work-event",
  "agent.context": "context-snapshot",
  "agent.permissions": "permission-projection",
  "agent.usage": "usage-record",
  "agent.providers": "managed-provider-readiness",
  "agent.artifacts": "managed-artifact",
  "agent.troubleshooting": "managed-work-diagnostics"
}

function hasOwn(value, key) {
  return value !== null && typeof value === "object" && Object.prototype.hasOwnProperty.call(value, key)
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function exactKeys(value, expected) {
  if (!isObject(value)) return false
  var actual = Object.keys(value).sort()
  var wanted = expected.slice().sort()
  if (actual.length !== wanted.length) return false
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] !== wanted[i]) return false
  }
  return true
}

function validView(view) {
  return QUERY_VIEWS.indexOf(String(view || "")) >= 0
}

function validOpaqueId(value) {
  if (typeof value !== "string" || value.length < 1 || value.length > 160) return false
  return /^(?:[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/.test(value)
}

function normalizedArguments(view, value) {
  var args = isObject(value) ? value : {}
  var entityType = hasOwn(args, "entityType") ? String(args.entityType || "") : ""
  var entityId = hasOwn(args, "entityId") ? String(args.entityId || "") : ""
  if ((entityType === "") !== (entityId === "")) throw new Error("Entity type and ID must be supplied together.")
  if (entityType !== "") {
    if (!validOpaqueId(entityId)) throw new Error("The entity ID is invalid.")
    if (view === "agent.tasks" && entityType !== "task" && entityType !== "run")
      throw new Error("The tasks route accepts only task or run entities.")
    if (view === "agent.activity" && entityType !== "operation")
      throw new Error("The activity route accepts only operation entities.")
    if (view === "agent.providers" && entityType !== "provider")
      throw new Error("The providers route accepts only provider entities.")
    if (view !== "agent.tasks" && view !== "agent.activity" && view !== "agent.providers")
      throw new Error("This route has no entity selector.")
  }
  return { entityType: entityType, entityId: entityId }
}

function requestParameters(view, argumentsValue, cursor) {
  var normalizedView = String(view || "")
  if (!validView(normalizedView)) throw new Error("The Agent Center view is invalid.")
  var entity = normalizedArguments(normalizedView, argumentsValue)
  var params = { version: QUERY_VERSION, view: normalizedView }
  if (entity.entityType !== "") {
    if (cursor !== null && cursor !== undefined && cursor !== "")
      throw new Error("Entity queries cannot be paginated.")
    params.entityType = entity.entityType
    params.entityId = entity.entityId
    return params
  }
  if (PAGINATED_VIEWS[normalizedView]) {
    params.limit = PAGE_SIZE
    if (cursor !== null && cursor !== undefined && cursor !== "") {
      if (typeof cursor !== "string" || cursor.length > MAX_CURSOR_LENGTH)
        throw new Error("The pagination cursor is invalid.")
      params.cursor = cursor
    }
  } else if (cursor !== null && cursor !== undefined && cursor !== "") {
    throw new Error("This route cannot be paginated.")
  }
  return params
}

function copyArray(value) {
  return Array.isArray(value) ? value.slice() : []
}

function baseState(view, argumentsValue, phase) {
  var entity
  try {
    entity = normalizedArguments(view, argumentsValue)
  } catch (_) {
    entity = { entityType: "", entityId: "" }
  }
  return {
    view: String(view || ""),
    entityType: entity.entityType,
    entityId: entity.entityId,
    phase: phase || "offline",
    items: [],
    summary: {},
    availability: null,
    nextCursor: null,
    partial: false,
    clipped: false,
    appending: false,
    requestId: "",
    error: null,
    recoveryActions: []
  }
}

function cloneState(state) {
  var result = {}
  var keys = Object.keys(state || {})
  for (var i = 0; i < keys.length; i++) result[keys[i]] = state[keys[i]]
  result.items = copyArray(state && state.items)
  result.recoveryActions = copyArray(state && state.recoveryActions)
  return result
}

function structuredError(code, title, explanation, detail, recoveryActions) {
  return {
    code: String(code || "agent-center.failed"),
    title: String(title || "Agent Center query failed"),
    explanation: String(explanation || "Fabric did not return a usable Agent Center response."),
    detail: String(detail || ""),
    retryable: true,
    changeState: "none",
    recoveryActions: copyArray(recoveryActions)
  }
}

function responseError(detail) {
  return structuredError(
    "agent-center.invalid-response",
    "Agent Center response rejected",
    "Fabric returned data outside the closed managed-work v0 query contract.",
    detail,
    ["fabric.reconnect"]
  )
}

function validAvailability(value) {
  return exactKeys(value, ["available", "code", "executionAvailable"]) &&
    typeof value.available === "boolean" &&
    typeof value.code === "string" && value.code.length >= 1 && value.code.length <= 160 &&
    /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/.test(value.code) &&
    value.executionAvailable === false
}

function validExecution(value) {
  return exactKeys(value, [
    "schemaVersion",
    "kind",
    "available",
    "code",
    "explanation",
    "legacyInteractiveIncluded",
    "networkDefault"
  ]) &&
    value.schemaVersion === QUERY_VERSION &&
    value.kind === "managed-execution-status" &&
    value.available === false &&
    value.code === "managed-execution.not-integrated" &&
    typeof value.explanation === "string" &&
    value.explanation.length >= 1 && value.explanation.length <= 2000 &&
    value.legacyInteractiveIncluded === false &&
    value.networkDefault === "denied"
}

function validCount(value) {
  return typeof value === "number" && isFinite(value) && value >= 0 && Math.floor(value) === value
}

function validTaskItem(item) {
  if (!exactKeys(item, ["entityType", "task", "run"])) return false
  if (item.entityType !== "task" && item.entityType !== "run") return false
  if (item.entityType === "task") return isObject(item.task) && item.task.kind === "managed-task" && (item.run === null || isObject(item.run))
  return item.task === null && isObject(item.run) && item.run.kind === "managed-run"
}

function validItem(view, item) {
  if (!isObject(item)) return false
  if (view === "agent.tasks") return validTaskItem(item)
  return item.kind === EXPECTED_KINDS[view]
}

function itemIdentity(view, item) {
  if (!isObject(item)) return ""
  if (view === "agent.tasks") {
    if (item.entityType === "run" && item.run) return "run:" + String(item.run.runId || "")
    return "task:" + String(item.task && item.task.taskId || "")
  }
  var fields = {
    "agent.approvals": "approvalId",
    "agent.automations": "automationId",
    "agent.activity": "operationId",
    "agent.history": "eventId",
    "agent.context": "contextId",
    "agent.permissions": "grantId",
    "agent.usage": "usageId",
    "agent.providers": "providerId",
    "agent.artifacts": "artifactId"
  }
  if (view === "agent.troubleshooting") return "diagnostics"
  var field = fields[view]
  return field ? view + ":" + String(item[field] || "") : ""
}

function validSummary(view, summary) {
  if (!isObject(summary)) return false
  if (view === "agent.overview") {
    return exactKeys(summary, ["activeTasks", "pendingApprovals", "enabledAutomations", "pendingUnavailableFirings", "liveContexts", "execution"]) &&
      validCount(summary.activeTasks) &&
      validCount(summary.pendingApprovals) &&
      validCount(summary.enabledAutomations) &&
      validCount(summary.pendingUnavailableFirings) &&
      validCount(summary.liveContexts) &&
      validExecution(summary.execution)
  }
  if (view === "agent.history") return exactKeys(summary, ["prunedThrough"]) && validCount(summary.prunedThrough)
  if (view === "agent.usage") return exactKeys(summary, ["costMicrounits", "recordCount"]) &&
    validCount(summary.costMicrounits) && validCount(summary.recordCount)
  return Object.keys(summary).length === 0
}

function validateResponse(view, response) {
  if (!exactKeys(response, ["schemaVersion", "kind", "view", "items", "nextCursor", "partial", "availability", "summary"]))
    return "The result envelope has an unexpected field set."
  if (response.schemaVersion !== QUERY_VERSION || response.kind !== "agent-center-query" || response.view !== view)
    return "The result envelope does not match the requested managed-work view."
  if (!Array.isArray(response.items) || response.items.length > MAX_VISIBLE_ITEMS)
    return "The result item page is invalid."
  if (response.nextCursor !== null && (typeof response.nextCursor !== "string" || response.nextCursor.length < 1 || response.nextCursor.length > MAX_CURSOR_LENGTH))
    return "The result cursor is invalid."
  if (typeof response.partial !== "boolean") return "The result partial marker is invalid."
  if (!validAvailability(response.availability)) return "The result availability contract is invalid."
  if (!validSummary(view, response.summary)) return "The result summary contract is invalid."
  if (view === "agent.overview" && (response.items.length !== 0 || response.nextCursor !== null))
    return "The overview result cannot contain records or a cursor."
  if (view === "agent.troubleshooting" && (response.items.length !== 1 || response.nextCursor !== null))
    return "The troubleshooting result must contain exactly one diagnostics record."
  if (response.items.length === 0 && response.nextCursor !== null)
    return "An empty page cannot advance a cursor."
  var seen = Object.create(null)
  for (var i = 0; i < response.items.length; i++) {
    if (!validItem(view, response.items[i])) return "A result item does not belong to the requested view."
    var identity = itemIdentity(view, response.items[i])
    if (identity === "" || seen[identity]) return "The result contains an empty or duplicate record identity."
    seen[identity] = true
  }
  return ""
}

function phaseForError(error) {
  var code = String(error && error.code || "")
  if (code === "rpc.cancelled") return "interrupted"
  if (code === "daemon.disconnected" || code === "daemon.socket-error" || code === "rpc.timeout") return "offline"
  if (code === "client.method-denied" || code.indexOf("access.") === 0 || code.indexOf("permission.") === 0 || code.indexOf("policy.") === 0)
    return "denied"
  if (code === "provider.unavailable" || code.indexOf("unavailable.") === 0 || code.indexOf("managed-work.unavailable") === 0)
    return "unavailable"
  return "failed"
}

function failureState(previous, errorValue) {
  var next = cloneState(previous)
  var error = isObject(errorValue) ? errorValue : structuredError("agent-center.failed", "Agent Center query failed", String(errorValue || "Unknown Fabric failure."))
  next.phase = phaseForError(error)
  next.error = error
  next.requestId = ""
  next.appending = false
  next.recoveryActions = copyArray(error.recoveryActions)
  if (next.phase === "offline") {
    next.items = []
    next.summary = {}
    next.nextCursor = null
    next.availability = null
    next.partial = false
    next.clipped = false
  }
  return next
}

function acceptedState(previous, response, appending, requestCursor) {
  var invalid = validateResponse(previous.view, response)
  if (invalid !== "") return failureState(previous, responseError(invalid))
  if (appending && requestCursor && response.nextCursor === requestCursor)
    return failureState(previous, responseError("The pagination cursor did not advance."))

  var combined = appending ? copyArray(previous.items) : []
  var identities = Object.create(null)
  for (var i = 0; i < combined.length; i++) identities[itemIdentity(previous.view, combined[i])] = true
  for (var j = 0; j < response.items.length; j++) {
    var identity = itemIdentity(previous.view, response.items[j])
    if (identities[identity]) return failureState(previous, responseError("A pagination page repeated an already visible record."))
    identities[identity] = true
    combined.push(response.items[j])
  }
  var clipped = combined.length >= MAX_VISIBLE_ITEMS && response.nextCursor !== null
  if (combined.length > MAX_VISIBLE_ITEMS) {
    combined = combined.slice(0, MAX_VISIBLE_ITEMS)
    clipped = true
  }

  var next = cloneState(previous)
  next.items = combined
  next.summary = response.summary
  next.availability = response.availability
  next.nextCursor = clipped ? null : response.nextCursor
  next.partial = response.partial
  next.clipped = clipped
  next.appending = false
  next.requestId = ""
  next.error = null
  next.recoveryActions = []
  if (!response.availability.available) next.phase = "unavailable"
  else if (response.partial) next.phase = "partial"
  else if (combined.length === 0 && previous.view !== "agent.overview") next.phase = "empty"
  else next.phase = "ready"
  return next
}

function QueryController(options) {
  var settings = options || {}
  this.send = typeof settings.send === "function" ? settings.send : function() { return "" }
  this.cancel = typeof settings.cancel === "function" ? settings.cancel : function() { return false }
  this.publish = typeof settings.onState === "function" ? settings.onState : function() {}
  this.connected = false
  this.generation = 0
  this.activeRequestId = ""
  this.pending = Object.create(null)
  this.sending = false
  this.synchronousFailure = null
  this.state = baseState("agent.overview", {}, "offline")
}

QueryController.prototype._setState = function(state) {
  this.state = state
  this.publish(cloneState(state))
}

QueryController.prototype._cancelSuperseded = function() {
  var requestId = this.activeRequestId
  if (requestId === "") return
  delete this.pending[requestId]
  this.activeRequestId = ""
  this.cancel(requestId)
}

QueryController.prototype._start = function(appending) {
  var cursor = appending ? this.state.nextCursor : null
  var params
  try {
    params = requestParameters(this.state.view, {
      entityType: this.state.entityType,
      entityId: this.state.entityId
    }, cursor)
  } catch (error) {
    this._setState(failureState(this.state, responseError(String(error))))
    return false
  }
  var loading = cloneState(this.state)
  if (!appending) {
    loading.items = []
    loading.summary = {}
    loading.availability = null
    loading.nextCursor = null
    loading.partial = false
    loading.clipped = false
  }
  loading.phase = "loading"
  loading.appending = appending
  loading.requestId = ""
  loading.error = null
  loading.recoveryActions = []
  this._setState(loading)

  this.sending = true
  this.synchronousFailure = null
  var requestId = String(this.send(QUERY_METHOD, params) || "")
  this.sending = false
  if (requestId === "") {
    var error = this.synchronousFailure || structuredError(
      "agent-center.request-rejected",
      "Agent Center request rejected",
      "The constrained Fabric client did not accept the managed-work query.",
      "",
      ["fabric.reconnect"]
    )
    this.synchronousFailure = null
    this._setState(failureState(this.state, error))
    return false
  }
  this.activeRequestId = requestId
  this.pending[requestId] = {
    generation: this.generation,
    view: this.state.view,
    appending: appending,
    cursor: cursor
  }
  var waiting = cloneState(this.state)
  waiting.requestId = requestId
  this._setState(waiting)
  return true
}

QueryController.prototype.setConnected = function(connected) {
  var value = connected === true
  if (value === this.connected) return false
  this.connected = value
  this.generation++
  if (!value) {
    this._cancelSuperseded()
    this.pending = Object.create(null)
    this._setState(baseState(this.state.view, {
      entityType: this.state.entityType,
      entityId: this.state.entityId
    }, "offline"))
    return true
  }
  this._cancelSuperseded()
  return this._start(false)
}

QueryController.prototype.activate = function(view, argumentsValue) {
  this.generation++
  this._cancelSuperseded()
  var next
  try {
    var entity = normalizedArguments(view, argumentsValue)
    if (!validView(view)) throw new Error("The Agent Center view is invalid.")
    next = baseState(view, entity, this.connected ? "loading" : "offline")
  } catch (error) {
    next = baseState(String(view || ""), {}, "failed")
    next = failureState(next, responseError(String(error)))
  }
  this._setState(next)
  if (!this.connected || next.phase === "failed") return false
  return this._start(false)
}

QueryController.prototype.refresh = function() {
  if (!this.connected) {
    this._setState(baseState(this.state.view, {
      entityType: this.state.entityType,
      entityId: this.state.entityId
    }, "offline"))
    return false
  }
  this.generation++
  this._cancelSuperseded()
  return this._start(false)
}

QueryController.prototype.loadMore = function() {
  if (!this.connected || this.activeRequestId !== "" || !this.state.nextCursor || this.state.clipped) return false
  return this._start(true)
}

QueryController.prototype.receiveResult = function(requestId, result) {
  var id = String(requestId || "")
  var ticket = this.pending[id]
  if (!ticket || id !== this.activeRequestId || ticket.generation !== this.generation || ticket.view !== this.state.view)
    return false
  delete this.pending[id]
  this.activeRequestId = ""
  this._setState(acceptedState(this.state, result, ticket.appending, ticket.cursor))
  return true
}

QueryController.prototype.receiveFailure = function(requestId, error) {
  var id = String(requestId || "")
  if (id === "" && this.sending) {
    this.synchronousFailure = error
    return true
  }
  var ticket = this.pending[id]
  if (!ticket || id !== this.activeRequestId || ticket.generation !== this.generation || ticket.view !== this.state.view)
    return false
  delete this.pending[id]
  this.activeRequestId = ""
  this._setState(failureState(this.state, error))
  return true
}

function createController(options) {
  return new QueryController(options)
}

function clippedText(value, maximum) {
  var limit = typeof maximum === "number" && maximum > 0 ? Math.floor(maximum) : MAX_DISPLAY_TEXT
  var text = value === null || value === undefined ? "" : String(value)
  text = text.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
  if (text.length <= limit) return text
  return text.slice(0, Math.max(1, limit - 1)) + "\u2026"
}

function compactJson(value) {
  try {
    return clippedText(JSON.stringify(value), MAX_DISPLAY_TEXT)
  } catch (_) {
    return "Unrepresentable structured value"
  }
}

function timestampText(value) {
  var number = Number(value)
  if (!isFinite(number) || number < 0) return "Unknown time"
  try {
    return new Date(number * 1000).toISOString().replace("T", " ").replace(".000Z", " UTC")
  } catch (_) {
    return "Unknown time"
  }
}

function detail(label, value) {
  return { label: String(label), value: clippedText(value) }
}

function toneForState(state) {
  var value = String(state || "").toLowerCase()
  if (["available", "succeeded", "active", "enabled", "ok", "complete", "recovered", "undone"].indexOf(value) >= 0) return "success"
  if (["failed", "denied", "revoked", "rollback-failed", "recovery-failed", "undo-failed", "incompatible"].indexOf(value) >= 0) return "danger"
  if (["degraded", "pending", "awaiting-consent", "awaiting-authentication", "running", "waiting", "retrying", "interrupted", "needs-attention", "partial", "unknown", "unavailable", "not-registered"].indexOf(value) >= 0) return "warning"
  return "info"
}

function taskPresentation(item) {
  var task = item.task
  var run = item.run
  if (item.entityType === "run") {
    return {
      title: "Run " + clippedText(run.runId, 180),
      subtitle: "Task " + clippedText(run.taskId, 180),
      status: String(run.state || "unknown"),
      tone: toneForState(run.state),
      body: run.manifest ? "Provider " + clippedText(run.manifest.provider) + " \u00b7 model " + clippedText(run.manifest.model) : "",
      details: [
        detail("Revision", run.revision),
        detail("Updated", timestampText(run.updatedAt)),
        detail("Steps", Array.isArray(run.steps) ? run.steps.length : 0),
        detail("Manifest", run.manifestHash || "Unknown")
      ],
      recoveryActions: run.state === "interrupted" ? ["Review durable history before retrying elsewhere"] : []
    }
  }
  var details = [
    detail("Task ID", task.taskId || "Unknown"),
    detail("Revision", task.revision),
    detail("Updated", timestampText(task.updatedAt)),
    detail("Latest run", run ? run.runId : "No run recorded")
  ]
  if (task.budget) {
    details.push(detail("Time budget", task.budget.timeSeconds + " seconds"))
    details.push(detail("Output budget", task.budget.outputBytes + " bytes"))
    details.push(detail("Network", task.budget.network ? "Granted in manifest" : "Denied"))
  }
  return {
    title: clippedText(task.title || task.taskId || "Managed task"),
    subtitle: "Managed task",
    status: String(task.state || "unknown"),
    tone: toneForState(task.state),
    body: task.intent ? compactJson(task.intent) : "",
    details: details,
    recoveryActions: task.state === "interrupted" ? ["Review the latest run and durable history"] : []
  }
}

function triggerText(trigger) {
  if (!isObject(trigger)) return "Unknown trigger"
  if (trigger.kind === "interval") return "Every " + trigger.seconds + " seconds"
  if (trigger.kind === "event") return "Event " + clippedText(trigger.topic)
  if (trigger.kind === "calendar") {
    var hour = String(trigger.hour)
    var minute = String(trigger.minute)
    return (hour.length < 2 ? "0" + hour : hour) + ":" +
      (minute.length < 2 ? "0" + minute : minute) + " " + clippedText(trigger.timeZone)
  }
  return clippedText(trigger.kind || "Unknown trigger")
}

function presentation(view, item) {
  if (view === "agent.tasks") return taskPresentation(item)
  if (view === "agent.approvals") return {
    title: clippedText(item.summary || item.approvalId),
    subtitle: clippedText(item.capability || "Approval projection"),
    status: String(item.state || "pending"), tone: toneForState(item.state), body: "",
    details: [detail("Risk", item.risk), detail("Operation", item.operationId), detail("Requested", timestampText(item.requestedAt)), detail("Expires", timestampText(item.expiresAt))],
    recoveryActions: []
  }
  if (view === "agent.automations") return {
    title: clippedText(item.name || item.automationId),
    subtitle: triggerText(item.trigger),
    status: String(item.state || "unknown"), tone: toneForState(item.state),
    body: item.taskTemplate ? clippedText(item.taskTemplate.title || "") : "",
    details: [detail("Automation ID", item.automationId), detail("Revision", item.revision), detail("Next due", item.nextDueAt === null ? "Not scheduled" : timestampText(item.nextDueAt)), detail("Recent firings", Array.isArray(item.firings) ? item.firings.length : 0), detail("Missed-run policy", item.policy && item.policy.missedRun || "Unknown")],
    recoveryActions: []
  }
  if (view === "agent.activity") return {
    title: clippedText(item.summary || item.operationId),
    subtitle: clippedText(item.capability || "Durable operation"),
    status: String(item.status || "unknown"), tone: toneForState(item.status), body: "",
    details: [detail("Operation ID", item.operationId), detail("Change state", item.changeState), detail("Task", item.taskId || "Not linked"), detail("Run", item.runId || "Not linked"), detail("Legacy provenance", item.legacyOwner ? "Yes" : "No"), detail("Updated", timestampText(item.updatedAt))],
    recoveryActions: item.recoveryEligible ? ["Recovery is eligible through the authoritative operation path"] : []
  }
  if (view === "agent.history") return {
    title: clippedText(item.topic || "Managed-work event"),
    subtitle: clippedText(item.entityId || "No entity"),
    status: "recorded", tone: "info", body: compactJson(item.payload || {}),
    details: [detail("Event ID", item.eventId), detail("Recorded", timestampText(item.createdAt))], recoveryActions: []
  }
  if (view === "agent.context") {
    var revoked = item.revokedAt !== null && item.revokedAt !== undefined
    return {
      title: clippedText(item.source || item.contextId), subtitle: String(item.sensitivity || "context") + " context",
      status: revoked ? "revoked" : "live", tone: revoked ? "danger" : "success", body: compactJson(item.content),
      details: [detail("Context ID", item.contextId), detail("Scope", item.access && item.access.scope || "Unknown"), detail("Expires", timestampText(item.expiresAt)), detail("Redacted", item.redaction && item.redaction.applied ? "Yes" : "No"), detail("Revision", item.revision)], recoveryActions: []
    }
  }
  if (view === "agent.permissions") return {
    title: clippedText(item.capability || item.grantId), subtitle: clippedText(item.resource || "Permission projection"),
    status: String(item.state || "unknown"), tone: toneForState(item.state), body: "",
    details: [detail("Grant ID", item.grantId), detail("Risk ceiling", item.riskCeiling), detail("Issued", timestampText(item.issuedAt)), detail("Expires", item.expiresAt === null ? "No expiry" : timestampText(item.expiresAt))], recoveryActions: []
  }
  if (view === "agent.usage") return {
    title: clippedText(item.provider || "Provider") + " \u00b7 " + clippedText(item.metric || "usage"), subtitle: clippedText(item.usageId || "Usage record"),
    status: "recorded", tone: "info", body: "",
    details: [detail("Quantity", item.quantity + " " + item.unit), detail("Cost", item.costMicrounits + " microunits"), detail("Task", item.taskId || "Not linked"), detail("Run", item.runId || "Not linked"), detail("Recorded", timestampText(item.recordedAt))], recoveryActions: []
  }
  if (view === "agent.providers") return {
    title: clippedText(item.providerId || "Provider"), subtitle: "Version " + clippedText(item.providerVersion || "unknown"),
    status: String(item.state || "unknown"), tone: toneForState(item.state), body: clippedText(item.explanation || ""),
    details: [detail("Installed", item.installed ? "Yes" : "No"), detail("Read usable", item.available ? "Yes" : "No"), detail("Registration order", item.registrationOrder), detail("Registry generation", item.registryGeneration), detail("Revision", item.sourceRevision), detail("Changed", timestampText(item.changedAt))], recoveryActions: item.available ? [] : ["Provider execution remains unavailable"]
  }
  if (view === "agent.artifacts") return {
    title: clippedText(item.label || item.artifactId), subtitle: clippedText(item.mediaType || "Managed artifact"),
    status: String(item.scope || "task"), tone: "info", body: "",
    details: [detail("Artifact ID", item.artifactId), detail("Handle", item.handle), detail("Bytes", item.byteLength), detail("Task", item.taskId), detail("Run", item.runId || "Not linked"), detail("Hash", item.contentHash), detail("Created", timestampText(item.createdAt))], recoveryActions: []
  }
  if (view === "agent.troubleshooting") return {
    title: "Managed-work database", subtitle: "Schema " + String(item.databaseSchema),
    status: String(item.databaseIntegrity || "unknown"), tone: toneForState(item.databaseIntegrity),
    body: "Execution is unavailable by contract. Diagnostics are owner-scoped and read-only.",
    details: [detail("Foreign-key violations", item.foreignKeyViolations), detail("Restart recoveries", item.restartRecoveries), detail("History pruned through", item.historyPrunedThrough), detail("Owned records", compactJson(item.ownerCounts || {})), detail("Capacity", compactJson(item.capacities || {}))],
    recoveryActions: copyArray(item.recoveryActions)
  }
  return { title: "Managed-work record", subtitle: view, status: "unknown", tone: "warning", body: "", details: [], recoveryActions: [] }
}

function overviewMetrics(summary) {
  if (!isObject(summary)) return []
  return [
    { label: "Active tasks", value: Number(summary.activeTasks || 0) },
    { label: "Pending approvals", value: Number(summary.pendingApprovals || 0) },
    { label: "Enabled automations", value: Number(summary.enabledAutomations || 0) },
    { label: "Unavailable firings", value: Number(summary.pendingUnavailableFirings || 0) },
    { label: "Live contexts", value: Number(summary.liveContexts || 0) }
  ]
}

function stateTitle(state) {
  if (!state) return "Agent Center"
  if (state.phase === "loading") return state.appending ? "Loading more records" : "Loading current managed work"
  if (state.phase === "offline") return "Fabric is offline"
  if (state.phase === "empty") return state.entityId ? "Requested record is absent" : "No records in this view"
  if (state.phase === "unavailable") return "This view is unavailable"
  if (state.phase === "denied") return "Access denied"
  if (state.phase === "interrupted") return "The read was interrupted"
  if (state.phase === "failed") return "The managed-work read failed"
  if (state.phase === "partial") return "Partial managed-work result"
  return "Current managed-work state"
}

function stateExplanation(state) {
  if (!state) return ""
  if (state.phase === "loading") return state.appending
    ? "The next bounded page is loading; already verified records remain visible."
    : "Agent Center is reading this owner-scoped view from the connected Fabric daemon."
  if (state.phase === "offline") return "No cached records are shown while the owner-scoped Fabric connection is unavailable."
  if (state.phase === "empty") return state.entityId
    ? "The backend returned no record for this stable deep link."
    : "The backend returned a valid current page with no records."
  if (state.phase === "unavailable") return state.error && state.error.explanation
    ? clippedText(state.error.explanation) : "The backend explicitly marked this query unavailable; no substitute data is shown."
  if (state.phase === "denied") return state.error && state.error.explanation
    ? clippedText(state.error.explanation) : "The authenticated account is not allowed to read this record."
  if (state.phase === "interrupted") return "The client stopped waiting before a complete response arrived. Refresh to establish current state."
  if (state.phase === "failed") return state.error && state.error.explanation
    ? clippedText(state.error.explanation) : "Fabric did not return a usable closed v0 response."
  if (state.phase === "partial") return "Fabric marked this result partial. Only the returned records are shown, and the state is not presented as complete."
  if (state.clipped) return "The local display bound of " + MAX_VISIBLE_ITEMS + " records was reached. Refresh or follow a stable entity link for a narrower read."
  if (state.view === "agent.overview") return "Counts come from the stable account owner. Managed execution remains unavailable by contract."
  return state.items.length + " current record" + (state.items.length === 1 ? " is" : "s are") + " visible from the managed-work query plane."
}

function phaseBadge(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "ready") return "CURRENT"
  if (phase === "empty") return "EMPTY"
  if (phase === "loading") return "LOADING"
  if (phase === "partial") return "PARTIAL"
  if (phase === "denied") return "DENIED"
  if (phase === "failed") return "FAILED"
  if (phase === "interrupted") return "INTERRUPTED"
  if (phase === "unavailable") return "UNAVAILABLE"
  return "OFFLINE"
}

function phaseTone(state) {
  var phase = String(state && state.phase || "offline")
  if (phase === "ready" || phase === "empty") return "success"
  if (phase === "failed" || phase === "denied") return "danger"
  if (phase === "loading") return "info"
  return "warning"
}

function selectedIdentity(view, item, entityType, entityId) {
  if (!entityId) return false
  if (view === "agent.tasks") {
    if (entityType === "run") return item && item.run && item.run.runId === entityId
    return item && item.task && item.task.taskId === entityId
  }
  if (view === "agent.activity") return item && item.operationId === entityId
  if (view === "agent.providers") return item && item.providerId === entityId
  return false
}

if (typeof module !== "undefined") {
  module.exports = {
    QUERY_METHOD: QUERY_METHOD,
    QUERY_VERSION: QUERY_VERSION,
    QUERY_VIEWS: QUERY_VIEWS,
    PAGE_SIZE: PAGE_SIZE,
    MAX_VISIBLE_ITEMS: MAX_VISIBLE_ITEMS,
    MAX_CURSOR_LENGTH: MAX_CURSOR_LENGTH,
    requestParameters: requestParameters,
    validateResponse: validateResponse,
    acceptedState: acceptedState,
    failureState: failureState,
    baseState: baseState,
    createController: createController,
    clippedText: clippedText,
    compactJson: compactJson,
    timestampText: timestampText,
    presentation: presentation,
    overviewMetrics: overviewMetrics,
    stateTitle: stateTitle,
    stateExplanation: stateExplanation,
    phaseBadge: phaseBadge,
    phaseTone: phaseTone,
    selectedIdentity: selectedIdentity
  }
}
