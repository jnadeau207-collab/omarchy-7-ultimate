#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

application="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"

grep -Fq 'readonly property bool profileMutationAuthorized: false' "$application" ||
  fail "Settings does not authorize LIVE power profile mutation"
grep -Fq 'if (!root.profileMutationAuthorized || !host || operationBusy) return' "$application" ||
  fail "Settings refuses power mutation when unauthorized"
grep -Fq 'visible: root.profileMutationAuthorized' "$application" ||
  fail "Settings hides power profile buttons while mutation is unauthorized"
grep -Fq 'text: root.profileMutationAuthorized' "$application" ||
  fail "Settings gates the Power pane LIVE CONTROL badge on profileMutationAuthorized"
grep -Fq '"CHANGES UNAVAILABLE"' "$application" ||
  fail "Settings names CHANGES UNAVAILABLE on the unauthorized Power pane"
grep -Fq 'org.freedesktop.UPower.PowerProfiles.switch-profile' "$application" ||
  fail "Settings Power honesty names the polkit action"
grep -Fq 'app.slice' "$application" ||
  fail "Settings Power honesty names the fabric daemon app.slice residual"
if grep -Fq 'omarchy-powerprofiles-set' "$application"; then
  fail "Settings assembles a legacy shell string instead of the typed verb"
fi
grep -Fq 'session_operable=False' "$ROOT/default/fabric/omarchy_fabric/providers/power/provider.py" ||
  fail "the real power provider stays session_operable=False"
grep -Fq 'SESSION_OPERABLE_DOMAINS = frozenset({"audio", "display", "input", "network", "process"})' "$ROOT/test/fabric/providers/test_leaf_providers.py" ||
  fail "leaf provider tests name the session-operable domains without power"
if grep -Fq 'org.freedesktop.UPower.PowerProfiles' "$ROOT/default/polkit-1/actions/org.omarchy.fabric.policy"; then
  fail "Omarchy polkit policy does not invent a PowerProfiles authorization"
fi
pass "Settings does not offer LIVE power profile mutation"

grep -Fq 'provider: "display.provider"' "$application" || fail "Settings sets brightness through display.provider"
grep -Fq 'action: "brightness.set"' "$application" || fail "Settings uses the typed brightness.set action"
grep -Fq 'if (queryState.records[i].brightnessAvailable) return queryState.records[i]' "$application" ||
  fail "Settings offers brightness only for an output that reports a controllable backlight"
pass "Settings drives brightness.set through the typed operation plane only"

grep -Fq 'provider: "input.provider"' "$application" || fail "Settings sets the layout through input.provider"
grep -Fq 'action: "keyboard-layout.set"' "$application" || fail "Settings uses the typed keyboard-layout.set action"
grep -Fq 'if (!(index >= 0 && index < record.layouts.length)) return' "$application" ||
  fail "Settings refuses a layout index outside the reported list"
if grep -Fq 'switchxkblayout' "$application"; then
  fail "Settings assembles a compositor shell string instead of the typed verb"
fi
pass "Settings drives keyboard-layout.set through the typed operation plane only"

grep -Fq 'provider: "network.provider"' "$application" || fail "Settings switches the radio through network.provider"
grep -Fq 'action: "wifi.set-enabled"' "$application" || fail "Settings uses the typed wifi.set-enabled action"
grep -Fq 'if (enabled && record.radioBlocked) return' "$application" ||
  fail "Settings refuses to enable a radio the hardware is holding off"
if grep -Eq 'nmcli|rfkill' "$application"; then
  fail "Settings assembles a network shell string instead of the typed verb"
fi
pass "Settings drives wifi.set-enabled through the typed operation plane only"

grep -Fq 'provider: "defaults.provider"' "$application" || fail "Settings sets the browser through defaults.provider"
grep -Fq 'action: "protocol.set"' "$application" || fail "Settings uses the typed protocol.set action"
grep -Fq 'if (!record || record.candidateAppIds.indexOf(appId) < 0) return' "$application" ||
  fail "Settings refuses an application the association does not list as a candidate"
grep -Fq 'return record && record.writable ? record : null' "$application" ||
  fail "Settings offers the browser control only for a writable association"
if grep -Eq 'xdg-mime|xdg-settings' "$application"; then
  fail "Settings assembles a defaults shell string instead of the typed verb"
fi
pass "Settings drives protocol.set through the typed operation plane only"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

assertDeepEqual(Model.POWER_PROFILES, ['power-saver', 'balanced', 'performance'], 'the profile vocabulary is code owned')

function record(state) {
  return Model.normalizeLeafResource({
    id: 'power.profile.current',
    label: 'Power profile',
    kind: 'profile',
    battery: null,
    state: state
  }, 0)
}

const healthy = record({ source: 'ac', activeProfile: 'balanced', availableProfiles: ['balanced', 'performance', 'power-saver'] })
assertDeepEqual(healthy.profiles, ['balanced', 'performance', 'power-saver'], 'available profiles survive as structured options')
assertEqual(healthy.activeProfile, 'balanced', 'the active profile survives as a structured value')

const injected = record({ source: 'ac', activeProfile: 'balanced', availableProfiles: ['balanced', 'rm -rf /', 'turbo'] })
assertDeepEqual(injected.profiles, ['balanced'], 'a profile outside the code-owned vocabulary never becomes an option')

const duplicated = record({ source: 'ac', activeProfile: 'balanced', availableProfiles: ['balanced', 'balanced'] })
assertDeepEqual(duplicated.profiles, ['balanced'], 'a duplicated profile is offered once')

const spoofedActive = record({ source: 'ac', activeProfile: 'ludicrous', availableProfiles: ['balanced'] })
assertEqual(spoofedActive.activeProfile, '', 'an unrecognized active profile is reported as unknown, not echoed')

const missing = record({ source: 'battery' })
assertDeepEqual(missing.profiles, [], 'a host reporting no profiles offers no control')
assertEqual(missing.activeProfile, '', 'a host reporting no active profile claims none')

const wrongTypes = record({ source: 'ac', activeProfile: 7, availableProfiles: 'balanced' })
assertDeepEqual(wrongTypes.profiles, [], 'a non-array profile list is refused')
assertEqual(wrongTypes.activeProfile, '', 'a non-string active profile is refused')

const powerQuery = Model.queryForRoute('settings.power.overview')
assert(powerQuery.coverage.indexOf('profile.set') >= 0, 'the power coverage note names the unavailable verb')
assert(powerQuery.coverage.indexOf('does not offer LIVE profile mutation') >= 0, 'the power coverage note refuses LIVE profile mutation')
assert(powerQuery.coverage.indexOf('polkit') >= 0, 'the power coverage note names the polkit residual')
assert(powerQuery.coverage.indexOf('app.slice') >= 0, 'the power coverage note names the fabric daemon cgroup residual')
assert(powerQuery.coverage.indexOf('Sleep, lock, and lid changes remain unavailable') >= 0, 'the power coverage note still refuses what Settings cannot do')

function displayRecord(state) {
  return Model.normalizeLeafResource({ id: 'display.output.abc', label: 'eDP-1', kind: 'output', state: state }, 0)
}

const controllable = displayRecord({ available: true, percent: 40 })
assertEqual(controllable.brightnessAvailable, true, 'a controllable backlight is offered')
assertEqual(controllable.brightnessPercent, 40, 'the current brightness survives as a structured value')
assertEqual(displayRecord({ available: false, percent: 40 }).brightnessAvailable, false, 'an output without a backlight offers no slider')
assertEqual(displayRecord({ available: true, percent: 900 }).brightnessAvailable, false, 'an out-of-range percent is refused')
assertEqual(displayRecord({ available: true, percent: '40' }).brightnessAvailable, false, 'a non-numeric percent is refused')
assertEqual(displayRecord({}).brightnessPercent, -1, 'a host reporting no brightness claims none')

const browserAssoc = Model.normalizeAssociation({ id: 'defaults.association.a', kind: 'protocol', key: 'https', status: 'configured', defaultAppId: 'defaults.app.x', writable: true, candidateAppIds: ['defaults.app.x', 'defaults.app.y'] }, 0)
const browserApps = [
  Model.normalizeApplication({ id: 'defaults.app.x', name: 'Firefox', state: 'available', desktopId: 'firefox.desktop' }, 1),
  Model.normalizeApplication({ id: 'defaults.app.y', name: 'Uninstalled', state: 'missing', desktopId: 'gone.desktop' }, 2)
]
const browserRecords = [browserAssoc].concat(browserApps)

assertEqual(Model.browserAssociation(browserRecords), browserAssoc, 'the https protocol association is the browser row')
assertDeepEqual(Model.browserCandidates(browserAssoc, browserRecords), [{ id: 'defaults.app.x', label: 'Firefox' }], 'only an installed candidate is offered as a browser')
assertDeepEqual(Model.browserCandidates(browserAssoc, []), [], 'no records means no browser candidates')

const mimeAssoc = Model.normalizeAssociation({ id: 'defaults.association.b', kind: 'mime', key: 'text/html', status: 'configured', defaultAppId: null, writable: true, candidateAppIds: [] }, 0)
assertEqual(Model.browserAssociation([mimeAssoc]), null, 'a MIME association is not the browser row')
assertEqual(Model.normalizeAssociation({ id: 'defaults.association.c', kind: 'protocol', key: 'https', status: 'configured', defaultAppId: null, writable: false, candidateAppIds: [] }, 0).writable, false, 'a read-only association reports itself read-only')

const appsQuery = Model.queryForRoute('settings.apps.overview')
assert(appsQuery.coverage.indexOf('protocol.set') >= 0, 'the apps coverage note names the settable verb')
assert(appsQuery.coverage.indexOf('startup, and background application inventory remain unavailable') >= 0, 'the apps coverage note still refuses what Settings cannot do')

function radioRecord(state) {
  return Model.normalizeLeafResource({ id: 'network.radio.wifi', label: 'Wi-Fi', kind: 'radio', state: state }, 0)
}

const radioOn = radioRecord({ managerRunning: true, hardwareEnabled: true, enabled: true })
assertEqual(radioOn.radioControllable, true, 'a running manager exposes a controllable radio')
assertEqual(radioOn.radioEnabled, true, 'the radio state survives as a structured value')
assertEqual(radioOn.radioBlocked, false, 'an unblocked radio is not reported as blocked')

const blocked = radioRecord({ managerRunning: true, hardwareEnabled: false, enabled: false })
assertEqual(blocked.radioBlocked, true, 'a hardware-blocked radio is reported as blocked')

const managerDown = radioRecord({ managerRunning: false, hardwareEnabled: true, enabled: true })
assertEqual(managerDown.radioControllable, false, 'a stopped network manager offers no control')
assertEqual(managerDown.radioEnabled, false, 'a stopped manager never claims the radio is on')

assertEqual(radioRecord({}).radioControllable, false, 'an interface record is not mistaken for the radio')
assertEqual(radioRecord({ managerRunning: true, hardwareEnabled: true, enabled: 'yes' }).radioControllable, false, 'a non-boolean radio state is refused')

const networkQuery = Model.queryForRoute('settings.network.overview')
assert(networkQuery.coverage.indexOf('wifi.set-enabled') >= 0, 'the network coverage note names the settable verb')
assert(networkQuery.coverage.indexOf('Joining a network and per-connection changes remain unavailable') >= 0, 'the network coverage note still refuses what Settings cannot do')

function keyboardRecord(state) {
  return Model.normalizeLeafResource({ id: 'input.keyboard.abc', label: 'Internal keyboard', kind: 'keyboard', main: true, state: state }, 0)
}

const twoLayouts = keyboardRecord({ activeIndex: 1, activeKeymap: 'German', layouts: ['us', 'de'], switchable: true })
assertDeepEqual(twoLayouts.layouts, ['us', 'de'], 'a switchable keyboard offers its layouts')
assertEqual(twoLayouts.activeLayoutIndex, 1, 'the active layout index survives as a structured value')
assertDeepEqual(keyboardRecord({ activeIndex: 0, activeKeymap: 'English', layouts: ['us'], switchable: false }).layouts, [], 'a single-layout keyboard offers no control')
assertDeepEqual(keyboardRecord({ activeIndex: 0, activeKeymap: 'x', layouts: ['us', 'de'], switchable: false }).layouts, [], 'a keyboard the compositor calls unswitchable offers no control')
assertEqual(keyboardRecord({ activeIndex: 9, activeKeymap: 'x', layouts: ['us', 'de'], switchable: true }).activeLayoutIndex, -1, 'an out-of-range active index is refused')
assertDeepEqual(keyboardRecord({ activeIndex: 0, activeKeymap: 'x', layouts: ['us', 123], switchable: true }).layouts, [], 'a non-string layout name voids the whole list')

const inputQuery = Model.queryForRoute('settings.input.overview')
assert(inputQuery.coverage.indexOf('keyboard-layout.set') >= 0, 'the input coverage note names the settable verb')
assert(inputQuery.coverage.indexOf('Pointer, repeat rate, and accessibility input changes remain unavailable') >= 0, 'the input coverage note still refuses what Settings cannot do')

const displayQuery = Model.queryForRoute('settings.display.overview')
assert(displayQuery.coverage.indexOf('brightness.set') >= 0, 'the display coverage note names the settable verb')
assert(displayQuery.coverage.indexOf('Resolution, scale, and arrangement changes remain unavailable') >= 0, 'the display coverage note still refuses what Settings cannot do')
JS
pass "the power profile option set is closed, deduplicated, and refuses spoofed host values"
