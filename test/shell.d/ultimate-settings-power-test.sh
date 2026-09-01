#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

application="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"

grep -Fq 'provider: "power.provider"' "$application" || fail "Settings sets the profile through power.provider"
grep -Fq 'action: "profile.set"' "$application" || fail "Settings uses the typed profile.set action"
grep -Fq 'if (!record || SettingsModel.POWER_PROFILES.indexOf(profile) < 0) return' "$application" ||
  fail "Settings refuses a profile outside the code-owned set"
grep -Fq 'if (record.profiles.indexOf(profile) < 0) return' "$application" ||
  fail "Settings refuses a profile the host does not report as available"
if grep -Fq 'omarchy-powerprofiles-set' "$application"; then
  fail "Settings assembles a legacy shell string instead of the typed verb"
fi
pass "Settings drives profile.set through the typed operation plane only"

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
assert(powerQuery.coverage.indexOf('profile.set') >= 0, 'the power coverage note names the settable verb')
assert(powerQuery.coverage.indexOf('Sleep, lock, and lid changes remain unavailable') >= 0, 'the power coverage note still refuses what Settings cannot do')
JS
pass "the power profile option set is closed, deduplicated, and refuses spoofed host values"
