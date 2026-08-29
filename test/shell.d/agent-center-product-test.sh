#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const Model = requireFromRoot('shell/apps/ultimate-agent-center/AgentCenterModel.js')

const routes = JSON.parse(fs.readFileSync(path.join(root, 'shell/apps/ultimate-agent-center/routes-v1.json'), 'utf8'))
assertDeepEqual(
  routes.routes.map(route => route.id),
  Model.QUERY_VIEWS,
  'Agent Center route order exactly matches all twelve managed-work views'
)
assertEqual(new Set(Model.QUERY_VIEWS).size, 12, 'Agent Center view registry has no duplicates')

assertDeepEqual(
  Model.requestParameters('agent.overview', {}, null),
  { version: 'v0', view: 'agent.overview' },
  'overview sends the exact unpaged v0 query parameters'
)
assertDeepEqual(
  Model.requestParameters('agent.troubleshooting', {}, null),
  { version: 'v0', view: 'agent.troubleshooting' },
  'troubleshooting sends the exact unpaged v0 query parameters'
)
for (const view of Model.QUERY_VIEWS.filter(view => !['agent.overview', 'agent.troubleshooting'].includes(view))) {
  assertDeepEqual(
    Model.requestParameters(view, {}, null),
    { version: 'v0', view, limit: Model.PAGE_SIZE },
    `${view} sends one bounded initial page`
  )
}
assertDeepEqual(
  Model.requestParameters('agent.tasks', { entityType: 'task', entityId: 'task.one' }, null),
  { version: 'v0', view: 'agent.tasks', entityType: 'task', entityId: 'task.one' },
  'task deep links send an exact unpaged entity query'
)
assertDeepEqual(
  Model.requestParameters('agent.tasks', { entityType: 'run', entityId: 'run.one' }, null),
  { version: 'v0', view: 'agent.tasks', entityType: 'run', entityId: 'run.one' },
  'run deep links send an exact unpaged entity query'
)
assertDeepEqual(
  Model.requestParameters('agent.activity', { entityType: 'operation', entityId: '00000000-0000-0000-0000-000000000001' }, null),
  { version: 'v0', view: 'agent.activity', entityType: 'operation', entityId: '00000000-0000-0000-0000-000000000001' },
  'operation deep links send an exact unpaged entity query'
)
assertDeepEqual(
  Model.requestParameters('agent.providers', { entityType: 'provider', entityId: 'network.provider' }, null),
  { version: 'v0', view: 'agent.providers', entityType: 'provider', entityId: 'network.provider' },
  'provider deep links send an exact unpaged entity query'
)
assertDeepEqual(
  Model.requestParameters('agent.history', {}, 'cursor.one'),
  { version: 'v0', view: 'agent.history', limit: Model.PAGE_SIZE, cursor: 'cursor.one' },
  'load-more sends only the opaque cursor and bounded v0 page fields'
)

function assertThrows(fn, description) {
  let threw = false
  try { fn() } catch (_) { threw = true }
  assert(threw, description)
}

assertThrows(
  () => Model.requestParameters('agent.permissions', { entityType: 'task', entityId: 'task.one' }, null),
  'routes without an entity contract reject entity selectors'
)
assertThrows(
  () => Model.requestParameters('agent.providers', { entityType: 'provider', entityId: 'provider.one' }, 'cursor.one'),
  'entity queries reject pagination cursors'
)
assertThrows(
  () => Model.requestParameters('agent.tasks', { entityType: 'task' }, null),
  'entity type without entity ID fails closed'
)
assertThrows(
  () => Model.requestParameters('agent.not-real', {}, null),
  'unknown Agent Center routes fail closed before transport'
)

const execution = {
  schemaVersion: 'v0', kind: 'managed-execution-status', available: false,
  code: 'sandbox.unavailable', explanation: 'Execution is unavailable.',
  legacyInteractiveIncluded: false, networkDefault: 'denied'
}

function summaryFor(view) {
  if (view === 'agent.overview') return {
    activeTasks: 1, pendingApprovals: 2, enabledAutomations: 3,
    pendingUnavailableFirings: 4, liveContexts: 5, execution
  }
  if (view === 'agent.history') return { prunedThrough: 7 }
  if (view === 'agent.usage') return { costMicrounits: 11, recordCount: 13 }
  return {}
}

function result(view, items = [], options = {}) {
  return {
    schemaVersion: 'v0',
    kind: 'agent-center-query',
    view,
    items,
    nextCursor: options.nextCursor === undefined ? null : options.nextCursor,
    partial: options.partial === true,
    availability: {
      available: options.available !== false,
      code: options.code || (options.available === false ? 'provider.unavailable' : 'managed-work.query-ready'),
      executionAvailable: false
    },
    summary: options.summary || summaryFor(view)
  }
}

function taskItem(id, state = 'running') {
  return {
    entityType: 'task',
    task: {
      kind: 'managed-task', taskId: id, title: `Task ${id}`, state, revision: 1,
      updatedAt: 1, intent: { goal: 'bounded' },
      budget: { timeSeconds: 60, outputBytes: 1024, costMicrounits: 0, network: false }
    },
    run: null
  }
}

const itemFixtures = {
  'agent.tasks': taskItem('task.one'),
  'agent.approvals': { kind: 'approval-projection', approvalId: 'approval.one', operationId: 'operation.one', capability: 'test.read', state: 'pending', risk: 'consequential', summary: 'Review exact change', requestedAt: 1, expiresAt: 2 },
  'agent.automations': { kind: 'managed-automation', automationId: 'automation.one', name: 'Daily review', state: 'enabled', revision: 1, trigger: { kind: 'interval', seconds: 60 }, taskTemplate: { title: 'Review' }, nextDueAt: 2, firings: [], policy: { missedRun: 'skip' } },
  'agent.activity': { kind: 'operation-link', operationId: 'operation.one', capability: 'test.change', summary: 'Exact operation', status: 'interrupted', changeState: 'unknown', recoveryEligible: true, legacyOwner: false, taskId: null, runId: null, updatedAt: 2 },
  'agent.history': { kind: 'managed-work-event', eventId: 'event.one', topic: 'task.created', entityId: 'task.one', payload: { state: 'draft' }, createdAt: 1 },
  'agent.context': { kind: 'context-snapshot', contextId: 'context.one', source: 'shell.selection', sensitivity: 'private', revokedAt: null, access: { scope: 'principal' }, expiresAt: 2, redaction: { applied: true }, revision: 1, content: { text: '[redacted]' } },
  'agent.permissions': { kind: 'permission-projection', grantId: 'grant.one', capability: 'test.read', resource: 'resource.one', state: 'active', riskCeiling: 'low', issuedAt: 1, expiresAt: null },
  'agent.usage': { kind: 'usage-record', usageId: 'usage.one', provider: 'test.provider', metric: 'tokens.input', quantity: 10, unit: 'tokens', costMicrounits: 3, taskId: 'task.one', runId: null, recordedAt: 1 },
  'agent.providers': { kind: 'managed-provider-readiness', providerId: 'test.provider', providerVersion: 'v0', state: 'degraded', installed: true, available: true, explanation: 'Reads remain usable.', registrationOrder: 1, registryGeneration: 2, sourceRevision: 3, changedAt: 1 },
  'agent.artifacts': { kind: 'managed-artifact', artifactId: 'artifact.one', label: 'Report', mediaType: 'text/plain', scope: 'task', handle: 'artifact.handle', byteLength: 42, taskId: 'task.one', runId: null, contentHash: 'a'.repeat(64), createdAt: 1 },
  'agent.troubleshooting': { kind: 'managed-work-diagnostics', databaseSchema: 4, databaseIntegrity: 'ok', foreignKeyViolations: 0, restartRecoveries: 1, historyPrunedThrough: 0, ownerCounts: { tasks: 1 }, capacities: { page_size: 100 }, execution, recoveryActions: ['managed-work.reconcile'] }
}

assertEqual(Model.validateResponse('agent.overview', result('agent.overview')), '', 'overview accepts its closed summary-only result')
for (const [view, item] of Object.entries(itemFixtures)) {
  assertEqual(Model.validateResponse(view, result(view, [item])), '', `${view} accepts only its real backend item shape`)
  const card = Model.presentation(view, item)
  assert(card.title.length > 0 && card.status.length > 0 && Array.isArray(card.details), `${view} has a bounded human presentation`)
}
assert(
  Model.presentation('agent.activity', itemFixtures['agent.activity']).recoveryActions.length === 1,
  'interrupted recovery-eligible operations expose recovery status without a mutation control'
)
const calendarAutomation = {
  ...itemFixtures['agent.automations'],
  trigger: { kind: 'calendar', hour: 7, minute: 5, timeZone: 'America/New_York' }
}
assertEqual(
  Model.presentation('agent.automations', calendarAutomation).subtitle,
  '07:05 America/New_York',
  'calendar automation schedules render without relying on optional JavaScript padding helpers'
)

const wrongRoute = result('agent.providers', [itemFixtures['agent.providers']])
assert(Model.validateResponse('agent.activity', wrongRoute).includes('does not match'), 'cross-route results fail closed')
const extraField = result('agent.overview')
extraField.privatePayload = 'nope'
assert(Model.validateResponse('agent.overview', extraField).includes('unexpected field'), 'extra result envelope fields fail closed')
const extraExecutionField = result('agent.overview')
extraExecutionField.summary.execution.privatePayload = 'nope'
assert(Model.validateResponse('agent.overview', extraExecutionField).includes('summary'), 'nested execution summary fields fail closed')
const negativeOverviewCount = result('agent.overview')
negativeOverviewCount.summary.activeTasks = -1
assert(Model.validateResponse('agent.overview', negativeOverviewCount).includes('summary'), 'overview counts must be non-negative integers')
const fractionalUsageCount = result('agent.usage')
fractionalUsageCount.summary.recordCount = 1.5
assert(Model.validateResponse('agent.usage', fractionalUsageCount).includes('summary'), 'usage summary counts must be non-negative integers')
const invalidAvailabilityCode = result('agent.tasks')
invalidAvailabilityCode.availability.code = 'NOT STABLE'
assert(Model.validateResponse('agent.tasks', invalidAvailabilityCode).includes('availability'), 'availability codes must use the closed stable identifier vocabulary')
const wrongKind = result('agent.permissions', [{ kind: 'usage-record', grantId: 'grant.one' }])
assert(Model.validateResponse('agent.permissions', wrongKind).includes('does not belong'), 'wrong-view item kinds fail closed')
const cursorLoop = result('agent.history', [], { nextCursor: 'cursor.loop' })
assert(Model.validateResponse('agent.history', cursorLoop).includes('empty page'), 'empty pages cannot create an infinite cursor loop')

let sent = []
let cancelled = []
let published = []
let serial = 0
const controller = Model.createController({
  send: (method, params) => {
    const id = `request.${++serial}`
    sent.push({ id, method, params })
    return id
  },
  cancel: id => { cancelled.push(id); return true },
  onState: state => published.push(state)
})

assert(controller.setConnected(true), 'connecting starts the current overview read')
assertEqual(sent.at(-1).method, 'managed-work.query', 'controller can send only the least-privilege managed-work query')
const staleOverview = sent.at(-1).id
controller.activate('agent.tasks', {})
assertDeepEqual(cancelled, [staleOverview], 'route activation locally cancels the superseded correlation')
const taskRequest = sent.at(-1)
assertDeepEqual(taskRequest.params, { version: 'v0', view: 'agent.tasks', limit: Model.PAGE_SIZE }, 'route activation sends exact task parameters')
assert(!controller.receiveResult(staleOverview, result('agent.overview')), 'late superseded results are ignored')
assertEqual(controller.state.view, 'agent.tasks', 'a stale result cannot replace the current route')

assert(controller.receiveResult(taskRequest.id, result('agent.tasks', [taskItem('task.one')], { nextCursor: 'cursor.two' })), 'current result is accepted')
assertEqual(controller.state.phase, 'ready', 'non-empty current result reaches ready state')
assertEqual(controller.state.items.length, 1, 'first page renders one real backend record')
assert(controller.loadMore(), 'load-more starts only when the backend supplied a cursor')
const pageRequest = sent.at(-1)
assertEqual(pageRequest.params.cursor, 'cursor.two', 'load-more preserves the exact opaque cursor')
assert(controller.receiveResult(pageRequest.id, result('agent.tasks', [taskItem('task.two')], { nextCursor: null })), 'next page is accepted')
assertDeepEqual(controller.state.items.map(item => item.task.taskId), ['task.one', 'task.two'], 'bounded pagination appends records in backend order')
assert(!controller.loadMore(), 'load-more stops when no cursor remains')

controller.refresh()
const duplicateRequest = sent.at(-1)
controller.receiveResult(duplicateRequest.id, result('agent.tasks', [taskItem('task.one')], { nextCursor: 'cursor.next' }))
controller.loadMore()
const duplicatePage = sent.at(-1)
controller.receiveResult(duplicatePage.id, result('agent.tasks', [taskItem('task.one')]))
assertEqual(controller.state.phase, 'failed', 'duplicate pagination identities fail closed')

controller.activate('agent.providers', { entityType: 'provider', entityId: 'missing.provider' })
const unavailableRequest = sent.at(-1)
controller.receiveResult(unavailableRequest.id, result('agent.providers', [], { available: false }))
assertEqual(controller.state.phase, 'unavailable', 'explicit backend unavailability is not presented as an empty success')

controller.activate('agent.history', {})
const partialRequest = sent.at(-1)
controller.receiveResult(partialRequest.id, result('agent.history', [itemFixtures['agent.history']], { partial: true }))
assertEqual(controller.state.phase, 'partial', 'partial backend results remain visibly partial')
assertEqual(controller.state.items.length, 1, 'partial state renders only the real returned records')

controller.activate('agent.activity', { entityType: 'operation', entityId: 'operation.missing' })
const deniedRequest = sent.at(-1)
controller.receiveFailure(deniedRequest.id, { code: 'access.denied', explanation: 'Operation is not visible.', recoveryActions: [] })
assertEqual(controller.state.phase, 'denied', 'owner-scope denial has an explicit denied state')

controller.refresh()
const interruptedRequest = sent.at(-1)
controller.receiveFailure(interruptedRequest.id, { code: 'rpc.cancelled', explanation: 'Read cancelled.', recoveryActions: ['fabric.reconnect'] })
assertEqual(controller.state.phase, 'interrupted', 'local read cancellation has an explicit interrupted state')
assertDeepEqual(controller.state.recoveryActions, ['fabric.reconnect'], 'structured recovery paths survive read failure presentation')

controller.activate('agent.tasks', {})
const offlineRequest = sent.at(-1)
controller.receiveResult(offlineRequest.id, result('agent.tasks', [taskItem('task.visible')]))
controller.setConnected(false)
assertEqual(controller.state.phase, 'offline', 'disconnect has an explicit offline state')
assertEqual(controller.state.items.length, 0, 'disconnect clears records instead of presenting stale cached state')

const clippedItems = Array.from({ length: Model.MAX_VISIBLE_ITEMS }, (_, index) => taskItem(`task.${index}`))
controller.setConnected(true)
controller.activate('agent.tasks', {})
const clippedRequest = sent.at(-1)
controller.receiveResult(clippedRequest.id, result('agent.tasks', clippedItems, { nextCursor: 'cursor.overflow' }))
assert(controller.state.clipped, 'local visible record accumulation has an explicit hard bound')
assertEqual(controller.state.items.length, Model.MAX_VISIBLE_ITEMS, 'local record bound is never exceeded')
assert(!controller.loadMore(), 'display-bound state cannot issue another accumulating page')

let rejectedController
rejectedController = Model.createController({
  send: () => {
    rejectedController.receiveFailure('', { code: 'client.method-denied', explanation: 'Not allowed.', recoveryActions: [] })
    return ''
  }
})
rejectedController.setConnected(true)
assertEqual(rejectedController.state.phase, 'denied', 'synchronous local allowlist rejection is correlated honestly')

const longText = `prefix\u0000${'x'.repeat(5000)}`
const clipped = Model.clippedText(longText)
assert(clipped.length <= 640 && clipped.endsWith('\u2026') && !clipped.includes('\u0000'), 'display text strips controls and has a hard length bound')
JS

entrypoint="$ROOT/shell/ultimate-agent-center.qml"
application="$ROOT/shell/apps/ultimate-agent-center/AgentCenterApplication.qml"
card="$ROOT/shell/apps/ultimate-agent-center/AgentRecordCard.qml"
host="$ROOT/shell/apps/shared/ProductAppHost.qml"

grep -Fqx '  fabricAllowedMethods: ["managed-work.query"]' "$entrypoint" || fail "Agent Center allowlist is exactly managed-work.query"
if grep -En 'provider\.catalog|reference\.operation|get\(|provider\.read|provider\.invoke' "$entrypoint" "$application" "$card"; then
  fail "Agent Center contains no legacy or mutating Fabric method"
fi
pass "Agent Center allowlist contains only managed-work.query"

grep -Fq 'function cancelFabric(requestId)' "$host" || fail "Product host exposes local correlation cancellation"
grep -Fq 'return fabric.cancel(String(requestId || ""))' "$host" || fail "Product host cancellation delegates only to FabricClient.cancel"
pass "Product host exposes authority-free local request cancellation"

grep -Fq 'focusable: true' "$application" || fail "Agent Center read controls participate in keyboard focus"
grep -Fq 'text: "Load more"' "$application" || fail "Agent Center exposes bounded load-more"
grep -Fq 'Accessible.role:' "$application" || fail "Agent Center state surfaces declare accessibility roles"
grep -Fq 'Accessible.role:' "$card" || fail "Agent Center record cards declare accessibility roles"
pass "Agent Center read controls are keyboard and accessibility complete"

if grep -En '(^|[^A-Za-z])(Process[[:space:]]*\{|Quickshell\.execDetached|execDetached\(|pkexec|sudo|hyprctl|systemctl|approve|operation\.cancel|operation\.start)' \
  "$application" "$card" "$ROOT/shell/apps/ultimate-agent-center/AgentCenterModel.js"; then
  fail "Agent Center presentation contains no command, approval, or operation mutation path"
fi
pass "Agent Center remains command-free and read-only"
