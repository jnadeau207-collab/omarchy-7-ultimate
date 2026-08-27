#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const Transport = requireFromRoot('shell/services/FabricTransport.js')

function wire(message) {
  return JSON.stringify(message) + '\n'
}

function helloResult(client, version = 0) {
  return {
    connectionId: '11111111-2222-3333-4444-555555555555',
    client,
    protocol: Transport.PROTOCOL_NAME,
    version,
    databaseSchema: 3,
    principal: {
      id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      sessionId: 'ffffffff-1111-2222-3333-444444444444',
      endpoint: 'fabric.owner-rpc',
      kind: 'shell'
    }
  }
}

function remoteError(code = 'provider.failed') {
  return {
    code,
    title: 'Provider failed',
    explanation: 'The fake provider reported a controlled failure.',
    detail: '',
    retryable: false,
    changeState: 'none',
    recoveryActions: ['provider.retry']
  }
}

function event(sequence, topic = 'test.changed') {
  return {
    sequence,
    id: `00000000-0000-0000-0000-${String(sequence).padStart(12, '0')}`,
    topic,
    payload: { sequence },
    createdAt: sequence
  }
}

class FakeSocketHarness {
  constructor(options = {}) {
    this.now = 0
    this.writes = []
    this.connects = 0
    this.closes = 0
    this.states = []
    this.results = []
    this.errors = []
    this.events = []
    this.protocolErrors = []
    this.late = []
    this.reconnects = []
    this.engine = Transport.createEngine({
      clientName: options.clientName || 'qml-test',
      allowedMethods: options.allowedMethods || ['health', 'version', 'events.subscribe'],
      maxPending: options.maxPending || 8,
      eventBacklog: options.eventBacklog || 8,
      requestTimeoutMs: options.requestTimeoutMs || 1000,
      reconnectBaseMs: options.reconnectBaseMs || 100,
      reconnectMaxMs: options.reconnectMaxMs || 400,
      callbacks: {
        onState: snapshot => this.states.push(snapshot),
        onConnectNeeded: () => { this.connects++ },
        onCloseNeeded: () => { this.closes++ },
        onReconnectScheduled: (delay, attempt) => this.reconnects.push({ delay, attempt }),
        sendFrame: frame => {
          this.writes.push(frame)
          return true
        },
        onRequestResult: (id, result) => this.results.push({ id, result }),
        onRequestError: (id, error) => this.errors.push({ id, error }),
        onEvent: incoming => this.events.push(incoming),
        onProtocolError: error => this.protocolErrors.push(error),
        onLateResponse: (id, kind) => this.late.push({ id, kind })
      }
    })
  }

  start() {
    this.engine.start(this.now)
  }

  open() {
    this.engine.transportOpened(this.now)
    return this.takeWrite()
  }

  takeWrite() {
    const frame = this.writes.shift()
    return frame === undefined ? null : Transport.strictParseJson(frame.slice(0, -1))
  }

  receive(text) {
    this.engine.receiveChunk(text, this.now)
  }

  reply(id, result) {
    this.receive(wire({ protocol: Transport.PROTOCOL_NAME, id, result }))
  }

  fail(id, error = remoteError()) {
    this.receive(wire({ protocol: Transport.PROTOCOL_NAME, id, error }))
  }

  tick(now) {
    this.now = now
    this.engine.tick(now)
  }

  disconnect(reason = null) {
    this.engine.transportClosed(reason, this.now)
  }

  becomeReady() {
    this.start()
    const hello = this.open()
    this.reply(hello.id, helloResult(hello.params.client))
    return hello
  }
}

assertEqual(Transport.WIRE_CHARACTER_SET, 'us-ascii', 'provisional QML wire subset is explicitly US-ASCII')
assertEqual(Transport.utf8ByteLength('ascii'), 5, 'byte-accounting utility handles the supported ASCII subset')
assertDeepEqual(Transport.strictParseJson('{"safe":{"value":1}}'), { safe: { value: 1 } }, 'strict JSON parser preserves nested objects')
assertThrows = function(fn, description) {
  let threw = false
  try { fn() } catch (_) { threw = true }
  assert(threw, description)
}
assertThrows(
  () => Transport.strictParseJson('{"safe":1,"safe":2}'),
  'strict JSON parser rejects duplicate object keys'
)

const dormant = Transport.createEngine({ allowedMethods: [] })
assertEqual(
  dormant.request('health', {}, null, 0).error.code,
  'client.method-denied',
  'empty allowlist denies a method even while the transport is disconnected'
)
dormant.setAllowedMethods(['health'])
assertEqual(
  dormant.request('health', {}, null, 0).error.code,
  'daemon.disconnected',
  'an allowed method reports disconnected only after the allowlist check passes'
)

const duplex = new FakeSocketHarness()
duplex.start()
assertEqual(duplex.connects, 1, 'start requests an immediate socket connection')
const hello = duplex.open()
assertDeepEqual(
  hello,
  {
    protocol: Transport.PROTOCOL_NAME,
    id: hello.id,
    method: 'hello',
    params: { client: 'qml-test', minVersion: 0, maxVersion: 0 }
  },
  'first newline JSON request is the fixed version-negotiating hello'
)
assert(duplex.writes.length === 0, 'fake socket consumes one complete newline frame')
const helloReply = wire({ protocol: Transport.PROTOCOL_NAME, id: hello.id, result: helloResult('qml-test') })
duplex.receive(helloReply.slice(0, 11))
assert(!duplex.engine.ready, 'fragmented hello reply waits for its newline frame')
duplex.receive(helloReply.slice(11))
assert(duplex.engine.ready, 'correlated hello reply makes the client ready')

const health = duplex.engine.request('health', {}, null, duplex.now)
const version = duplex.engine.request('version', {}, null, duplex.now)
const healthWire = duplex.takeWrite()
const versionWire = duplex.takeWrite()
assertEqual(health.id, healthWire.id, 'health request ID is present on the wire')
assertEqual(version.id, versionWire.id, 'version request ID is present on the wire')
duplex.receive(
  wire({ protocol: Transport.PROTOCOL_NAME, id: version.id, result: { version: 0 } }) +
  wire({ protocol: Transport.PROTOCOL_NAME, id: health.id, result: { status: 'ok' } })
)
assertDeepEqual(
  duplex.results.slice(-2).map(entry => [entry.id, entry.result]),
  [[version.id, { version: 0 }], [health.id, { status: 'ok' }]],
  'coalesced out-of-order replies remain correlated to their request IDs'
)
assertEqual(duplex.engine.snapshot().pendingCount, 0, 'successful replies remove pending correlation state')

const failedRequest = duplex.engine.request('health', {}, null, duplex.now)
duplex.takeWrite()
duplex.fail(failedRequest.id)
assertEqual(duplex.errors.at(-1).error.code, 'provider.failed', 'valid structured remote errors reach the correlated caller')
assert(duplex.engine.ready, 'a valid remote application error does not poison the connection')

duplex.receive(wire({ protocol: Transport.PROTOCOL_NAME, event: event(1) }))
assertEqual(duplex.events.length, 1, 'unsolicited validated events are delivered independently of replies')
assertDeepEqual(duplex.engine.takeEvent(), event(1), 'validated events remain available in the bounded consumer queue')
assertEqual(duplex.engine.snapshot().eventCount, 0, 'taking an event releases its queue slot')

const denied = duplex.engine.request(
  'provider.invoke',
  { provider: 'fake.demo', action: 'echo', arguments: {}, idempotencyKey: 'denied' },
  null,
  duplex.now
)
assertEqual(denied.error.code, 'client.method-denied', 'method allowlist denies ungranted consequence paths locally')
assertEqual(duplex.writes.length, 0, 'denied methods never reach the socket')
const readyConnects = duplex.connects
assert(!duplex.engine.retry(duplex.now), 'retry rejects an already-ready connection')
assert(duplex.engine.ready && duplex.engine.state === 'ready', 'rejected ready retry leaves readiness and state coherent')
assertEqual(duplex.connects, readyConnects, 'rejected ready retry opens no extra connection')

const reconnect = new FakeSocketHarness({ reconnectBaseMs: 100, reconnectMaxMs: 400 })
reconnect.becomeReady()
reconnect.writes = []
const abandoned = reconnect.engine.request('health', {}, null, reconnect.now)
reconnect.takeWrite()
reconnect.disconnect()
assertEqual(reconnect.errors.at(-1).id, abandoned.id, 'disconnect fails every pending request explicitly')
assertEqual(reconnect.errors.at(-1).error.changeState, 'unknown', 'disconnect never guesses remote change state')
reconnect.tick(99)
assertEqual(reconnect.connects, 1, 'reconnect waits for the first backoff deadline')
reconnect.tick(100)
assertEqual(reconnect.connects, 2, 'reconnect starts at the bounded base delay')
reconnect.disconnect()
reconnect.tick(299)
assertEqual(reconnect.connects, 2, 'second reconnect doubles the backoff delay')
reconnect.tick(300)
assertEqual(reconnect.connects, 3, 'second reconnect runs at the doubled deadline')
const reconnectHello = reconnect.open()
reconnect.reply(reconnectHello.id, helloResult('qml-test'))
reconnect.disconnect()
reconnect.tick(399)
assertEqual(reconnect.connects, 3, 'successful hello resets but still observes the base delay')
reconnect.tick(400)
assertEqual(reconnect.connects, 4, 'successful hello resets exponential backoff to its base')

const mismatch = new FakeSocketHarness()
mismatch.start()
const mismatchHello = mismatch.open()
mismatch.reply(mismatchHello.id, helloResult('qml-test', 1))
assertEqual(mismatch.engine.state, 'incompatible', 'unsupported selected protocol version fails the handshake closed')
assert(mismatch.engine.compatibilityBlocked, 'protocol mismatch blocks automatic reconnect')
mismatch.tick(100000)
assertEqual(mismatch.connects, 1, 'protocol mismatch does not spin in a reconnect loop')
mismatch.disconnect()
assert(!mismatch.engine.disconnectExpected, 'socket close feedback completes the incompatible disconnect')
mismatch.engine.retry(100001)
assertEqual(mismatch.connects, 2, 'an explicit post-update retry clears the compatibility block')

const stopped = new FakeSocketHarness()
stopped.becomeReady()
stopped.engine.stop(stopped.now)
assertEqual(stopped.engine.state, 'disabled', 'explicit stop moves directly to disabled state')
assert(stopped.engine.disconnectExpected, 'explicit stop models the expected asynchronous socket close feedback')
assertEqual(stopped.engine.lastError, null, 'explicit stop is not recorded as a daemon failure')
stopped.disconnect({
  code: 'daemon.disconnected',
  title: 'late close',
  explanation: 'async close feedback',
  detail: '',
  retryable: true,
  changeState: 'unknown'
})
assertEqual(stopped.engine.state, 'disabled', 'expected asynchronous close feedback preserves disabled state')
assertEqual(stopped.engine.lastError, null, 'expected asynchronous close feedback does not overwrite lastError')
assert(!stopped.engine.disconnectExpected, 'expected close feedback is consumed exactly once')
stopped.disconnect({
  code: 'daemon.socket-error',
  title: 'duplicate close',
  explanation: 'duplicate asynchronous close feedback',
  detail: '',
  retryable: true,
  changeState: 'unknown'
})
assertEqual(stopped.engine.lastError, null, 'duplicate expected close feedback is suppressed until another connection attempt')

const stoppedDuringBackoff = new FakeSocketHarness()
stoppedDuringBackoff.becomeReady()
stoppedDuringBackoff.disconnect()
stoppedDuringBackoff.engine.stop(stoppedDuringBackoff.now)
stoppedDuringBackoff.disconnect({
  code: 'daemon.socket-error',
  title: 'late backoff close',
  explanation: 'late feedback after stop during reconnect backoff',
  detail: '',
  retryable: true,
  changeState: 'unknown'
})
assertEqual(stoppedDuringBackoff.engine.state, 'disabled', 'stop during reconnect backoff remains disabled after late feedback')
assertEqual(stoppedDuringBackoff.engine.lastError, null, 'late feedback after stop during reconnect backoff is ignored')

const exactFrame = new FakeSocketHarness()
exactFrame.becomeReady()
exactFrame.writes = []
const exactRequest = exactFrame.engine.request('health', {}, null, exactFrame.now)
exactFrame.takeWrite()
const exactEnvelope = { protocol: Transport.PROTOCOL_NAME, id: exactRequest.id, result: { padding: '' } }
const baseBytes = Transport.utf8ByteLength(JSON.stringify(exactEnvelope))
exactEnvelope.result.padding = 'x'.repeat(Transport.MAX_FRAME_BYTES - baseBytes)
const exactLine = JSON.stringify(exactEnvelope)
assertEqual(Transport.utf8ByteLength(exactLine), Transport.MAX_FRAME_BYTES, 'test fixture reaches the exact incoming frame limit')
exactFrame.receive(exactLine + '\n')
assertEqual(exactFrame.results.at(-1).id, exactRequest.id, 'exact-limit incoming frame is accepted')

const oversizedIncoming = new FakeSocketHarness()
oversizedIncoming.becomeReady()
oversizedIncoming.receive('x'.repeat(Transport.MAX_FRAME_BYTES + 1))
assertEqual(oversizedIncoming.protocolErrors.at(-1).code, 'rpc.frame-too-large', 'oversized partial frame closes before a newline arrives')
assertEqual(oversizedIncoming.engine.state, 'reconnecting', 'oversized frame fails the connection closed')

const oversizedOutgoing = new FakeSocketHarness()
oversizedOutgoing.becomeReady()
oversizedOutgoing.writes = []
const outgoing = oversizedOutgoing.engine.request(
  'health',
  { padding: 'x'.repeat(Transport.MAX_FRAME_BYTES) },
  null,
  oversizedOutgoing.now
)
assertEqual(outgoing.error.code, 'rpc.frame-too-large', 'oversized outgoing request is rejected before write')
assertEqual(oversizedOutgoing.writes.length, 0, 'oversized outgoing request writes no partial frame')
assertEqual(oversizedOutgoing.engine.snapshot().pendingCount, 0, 'oversized outgoing request releases its pending slot')

const pending = new FakeSocketHarness({ maxPending: 2 })
pending.becomeReady()
pending.writes = []
const pendingOne = pending.engine.request('health', {}, null, pending.now)
const pendingTwo = pending.engine.request('version', {}, null, pending.now)
const pendingThree = pending.engine.request('health', {}, null, pending.now)
assert(pendingOne.ok && pendingTwo.ok, 'pending request limit admits requests through its bound')
assertEqual(pendingThree.error.code, 'rpc.pending-limit', 'pending request limit rejects the first request beyond its bound')
assertEqual(pending.engine.snapshot().pendingCount, 2, 'pending request storage never exceeds its configured bound')

const backlog = new FakeSocketHarness({ eventBacklog: 2 })
backlog.becomeReady()
backlog.receive(wire({ protocol: Transport.PROTOCOL_NAME, event: event(1) }))
backlog.receive(wire({ protocol: Transport.PROTOCOL_NAME, event: event(2) }))
backlog.receive(wire({ protocol: Transport.PROTOCOL_NAME, event: event(3) }))
assertEqual(backlog.events.length, 2, 'event delivery stops at the configured backlog bound')
assertEqual(backlog.protocolErrors.at(-1).code, 'events.client-overflow', 'event overflow is explicit and requires reconnect plus replay')
assertEqual(backlog.engine.state, 'reconnecting', 'event overflow fails the connection closed instead of dropping silently')

const deadlines = new FakeSocketHarness({ requestTimeoutMs: 50 })
deadlines.becomeReady()
deadlines.writes = []
const timed = deadlines.engine.request('health', {}, null, deadlines.now)
deadlines.takeWrite()
deadlines.tick(49)
assertEqual(deadlines.engine.snapshot().pendingCount, 1, 'request remains correlated before its deadline')
deadlines.tick(50)
assertEqual(deadlines.errors.at(-1).error.code, 'rpc.timeout', 'deadline expires with a structured timeout')
assertEqual(deadlines.engine.snapshot().pendingCount, 0, 'timeout releases pending correlation state')
deadlines.reply(timed.id, { tooLate: true })
assertDeepEqual(deadlines.late.at(-1), { id: timed.id, kind: 'result' }, 'late timeout reply is ignored and identified')
const cancelled = deadlines.engine.request('health', {}, null, deadlines.now)
deadlines.takeWrite()
assert(deadlines.engine.cancel(cancelled.id), 'local cancellation accepts a live request ID')
assertEqual(deadlines.errors.at(-1).error.code, 'rpc.cancelled', 'local cancellation reports an explicit error')
assertEqual(deadlines.errors.at(-1).error.changeState, 'unknown', 'local cancellation does not claim remote cancellation')
assertEqual(deadlines.engine.snapshot().pendingCount, 0, 'cancellation releases pending correlation state')

function malformedCase(makeFrame, description) {
  const harness = new FakeSocketHarness()
  harness.becomeReady()
  harness.writes = []
  const request = harness.engine.request('health', {}, null, harness.now)
  harness.takeWrite()
  harness.receive(makeFrame(request.id))
  assert(
    harness.protocolErrors.length === 1 && harness.engine.state === 'reconnecting' && harness.closes === 1,
    description
  )
}

malformedCase(
  id => `{"protocol":"${Transport.PROTOCOL_NAME}","protocol":"${Transport.PROTOCOL_NAME}","id":"${id}","result":{}}\n`,
  'duplicate envelope keys fail the connection closed'
)
malformedCase(
  id => wire({ protocol: Transport.PROTOCOL_NAME, id, result: {}, extra: true }),
  'unknown response fields fail the connection closed'
)
malformedCase(
  id => wire({ protocol: Transport.PROTOCOL_NAME, id, result: {}, error: remoteError() }),
  'response containing both result and error fails closed'
)
malformedCase(
  id => wire({ protocol: Transport.PROTOCOL_NAME, id, error: { code: 'broken' } }),
  'malformed structured error fails the connection closed'
)
malformedCase(
  id => wire({ protocol: Transport.PROTOCOL_NAME, id, error: { ...remoteError(), changeState: 'toString' } }),
  'inherited Object prototype names are not accepted as change states'
)
malformedCase(
  id => '{not-json}\n',
  'invalid JSON fails the connection closed'
)
malformedCase(
  id => wire([Transport.PROTOCOL_NAME, id]),
  'non-object envelope fails the connection closed'
)
malformedCase(
  id => wire({ protocol: Transport.PROTOCOL_NAME, event: { ...event(1), sequence: true } }),
  'malformed unsolicited event fails the connection closed'
)

const wrongProtocol = new FakeSocketHarness()
wrongProtocol.start()
const wrongProtocolHello = wrongProtocol.open()
wrongProtocol.receive(wire({ protocol: 'omarchy.fabric.rpc/v99', id: wrongProtocolHello.id, result: helloResult('qml-test') }))
assertEqual(wrongProtocol.engine.state, 'incompatible', 'envelope protocol mismatch is a non-retrying compatibility failure')

const replacement = new FakeSocketHarness()
replacement.becomeReady()
replacement.receive('\ufffd')
assertEqual(replacement.protocolErrors.at(-1).code, 'rpc.unsupported-character-set', 'split non-ASCII decoder replacement fails closed under the ASCII contract')
assertEqual(replacement.engine.state, 'incompatible', 'non-ASCII wire input blocks reconnect instead of corrupting framing')

const unicodeOutgoing = new FakeSocketHarness()
unicodeOutgoing.becomeReady()
unicodeOutgoing.writes = []
const unicodeRequest = unicodeOutgoing.engine.request('health', { label: 'café' }, null, unicodeOutgoing.now)
assertEqual(unicodeRequest.error.code, 'rpc.unsupported-character-set', 'Unicode request values cannot activate the ASCII-only adapter')
assertEqual(unicodeOutgoing.writes.length, 0, 'Unicode request values write no bytes')
assert(unicodeOutgoing.engine.ready, 'locally rejected Unicode request leaves the ASCII connection ready')

const unicodeIncoming = new FakeSocketHarness()
unicodeIncoming.becomeReady()
unicodeIncoming.writes = []
const unicodePending = unicodeIncoming.engine.request('health', {}, null, unicodeIncoming.now)
unicodeIncoming.takeWrite()
unicodeIncoming.receive(wire({ protocol: Transport.PROTOCOL_NAME, id: unicodePending.id, result: { label: 'café' } }))
assertEqual(unicodeIncoming.protocolErrors.at(-1).code, 'rpc.unsupported-character-set', 'raw Unicode response fails the ASCII-only adapter closed')
assertEqual(unicodeIncoming.engine.state, 'incompatible', 'raw Unicode response blocks automatic reconnect')

const escapedUnicode = new FakeSocketHarness()
escapedUnicode.becomeReady()
escapedUnicode.writes = []
const escapedPending = escapedUnicode.engine.request('health', {}, null, escapedUnicode.now)
escapedUnicode.takeWrite()
escapedUnicode.receive(`{"protocol":"${Transport.PROTOCOL_NAME}","id":"${escapedPending.id}","result":{"label":"\\u00e9"}}\n`)
assertEqual(escapedUnicode.protocolErrors.at(-1).code, 'rpc.unsupported-character-set', 'escaped semantic Unicode is also rejected rather than enabling a Unicode consumer')

const truncated = new FakeSocketHarness()
truncated.becomeReady()
truncated.receive('{"protocol":"omarchy.fabric.rpc/v0"')
truncated.disconnect()
assertEqual(truncated.protocolErrors.at(-1).code, 'rpc.truncated-frame', 'disconnect with a partial response reports a truncated frame')
assertEqual(truncated.engine.state, 'reconnecting', 'truncated response reconnects without trusting the partial envelope')

const qml = fs.readFileSync(path.join(root, 'shell/services/FabricClient.qml'), 'utf8')
const shell = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')
const docs = fs.readFileSync(path.join(root, 'docs/fabric-qml-transport.md'), 'utf8')
assert(/^Item \{/m.test(qml) && /^  Socket \{/m.test(qml), 'QML adapter keeps its Quickshell Unix Socket behind component scope')
assert(/SplitParser\s*\{[\s\S]*?splitMarker: ""/.test(qml), 'QML adapter receives arbitrary chunks for bounded newline framing')
assert(/wire\.write\(frame\)[\s\S]*?wire\.flush\(\)/.test(qml), 'QML adapter writes and flushes each complete bounded frame')
assert(/root\._engine\.receiveChunk\(data, Date\.now\(\)\)/.test(qml), 'QML adapter routes socket chunks through the tested state machine')
assert(/readonly property string wireCharacterSet: "us-ascii"/.test(qml) && /readonly property bool supportsUnicode: false/.test(qml), 'QML API makes its Unicode activation limit explicit')
assert(/FabricClient\s*\{[\s\S]*?id: fabricClient[\s\S]*?active: false[\s\S]*?allowedMethods: \[\]/.test(shell), 'running shell privately instantiates Fabric disabled with no public method grant')
assert(!/property FabricClient fabricClient/.test(shell), 'shell does not inject the dormant Fabric transport into plugin-visible service state')
assert(!/provider\.invoke/.test(qml), 'QML adapter contains no hard-coded provider consequence path')
assert(/raw `QByteArray`/.test(docs) && /write\(\)` as `void`/.test(docs), 'Quickshell raw-byte and write-backpressure API gaps are documented honestly')
JS

qml_test_runner=""
if command -v qmltestrunner >/dev/null; then
  qml_test_runner=$(command -v qmltestrunner)
elif [[ -x /usr/lib/qt6/bin/qmltestrunner ]]; then
  qml_test_runner=/usr/lib/qt6/bin/qmltestrunner
fi

quickshell_qml_plugin=""
for candidate in \
  /usr/lib/qt6/qml/Quickshell/libquickshell-coreplugin.so \
  /usr/lib/qt6/qml/Quickshell/quickshell-coreplugin.so; do
  if [[ -f $candidate ]]; then
    quickshell_qml_plugin=$candidate
    break
  fi
done

if [[ -n $qml_test_runner && -n $quickshell_qml_plugin ]] && command -v quickshell >/dev/null; then
  QT_QPA_PLATFORM=offscreen "$qml_test_runner" \
    -input "$ROOT/test/shell.d/fixtures/tst_FabricClient.qml" \
    -import "$ROOT/shell/services" \
    -o -,txt || fail "FabricClient loads in the installed QML and Quickshell runtime"
  pass "FabricClient loads in the installed QML and Quickshell runtime"
else
  pass "standalone Quickshell QML plugin unavailable; deterministic transport suite completed"
fi
