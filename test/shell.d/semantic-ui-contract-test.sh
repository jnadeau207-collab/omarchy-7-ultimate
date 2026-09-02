#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const metricsPath = path.join(root, 'shell/Commons/SemanticMetrics.js')
const source = fs.readFileSync(metricsPath, 'utf8').replace(/^\.pragma library\s*/m, '')
const metrics = {}
vm.createContext(metrics)
vm.runInContext(source, metrics, { filename: metricsPath })

assertDeepEqual(
  Array.from(metrics.operationIds()),
  ['success', 'no-op', 'progress', 'denial', 'failure', 'cancel', 'restart', 'recovery'],
  'semantic operation vocabulary is exhaustive and ordered'
)

for (const id of metrics.operationIds()) {
  const definition = metrics.operationDefinition(id)
  assert(
    definition.id === id && definition.label && definition.message && definition.symbol && definition.primaryAction,
    `operation ${id} has label, explanation, symbol, tone, and recovery action`
  )
}

assertEqual(metrics.minimumTarget({ densityMode: 'compact' }), 28, 'compact density guarantees a 28 px pointer target')
assertEqual(metrics.minimumTarget({ densityMode: 'comfortable' }), 32, 'comfortable density guarantees a 32 px pointer target')
assertEqual(metrics.minimumTarget({ densityMode: 'touch' }), 44, 'touch density guarantees a 44 px target')
assertEqual(metrics.duration(300, { reducedMotion: true }), 0, 'reduced motion removes nonessential duration')
assertEqual(metrics.scaledFont(12, { largeText: true, textScale: 1.25 }), 15, 'large text scales shared typography')

const pseudo = metrics.pseudoLocalize('Apply %1 to {target}')
assert(pseudo.length > 'Apply %1 to {target}'.length, 'pseudo localization expands visible copy')
assert(pseudo.includes('%1') && pseudo.includes('{target}'), 'pseudo localization preserves placeholders')
assertDeepEqual(
  JSON.parse(JSON.stringify(metrics.logicalEdges(true, 6, 18))),
  { left: 18, right: 6 },
  'RTL swaps logical leading and trailing edges'
)

const palettePairs = [
  ['#ffffff', '#17191d'], ['#d5d9e1', '#17191d'],
  ['#101318', '#f7f8fa'], ['#303844', '#f7f8fa'],
  ['#73d69c', '#17191d'], ['#ffd166', '#17191d'], ['#ff8a80', '#17191d'], ['#8fc7ff', '#17191d'],
  ['#126b35', '#f7f8fa'], ['#714700', '#f7f8fa'], ['#9b261f', '#f7f8fa'], ['#005fcc', '#f7f8fa']
]
for (const [foreground, background] of palettePairs) {
  const ratio = metrics.contrastRatio(foreground, background)
  assert(ratio >= 4.5, `${foreground} on ${background} passes 4.5:1 contrast`, String(ratio))
}

const cases = [
  { densityMode: 'comfortable', scaleFactor: 1 },
  { densityMode: 'compact', scaleFactor: 1.25, highContrast: true, reducedMotion: true, largeText: true, textScale: 1.25, pseudoLocale: true },
  { densityMode: 'touch', scaleFactor: 1.5, highContrast: true, reducedMotion: true, largeText: true, textScale: 1.25, locale: 'long', rtl: true },
  { densityMode: 'comfortable', scaleFactor: 2, rtl: true }
]
for (const profile of cases) {
  const audit = metrics.auditFixture(profile, 320, 'Restart required', 'Restart the service to finish applying the change.', 2)
  assert(audit.pointerTargetPass, 'presentation fixture passes pointer target minimum')
  assert(audit.touchTargetPass, 'presentation fixture passes touch target minimum when applicable')
  assert(Number.isFinite(audit.requiredHeight) && audit.requiredHeight > 0, 'presentation fixture produces finite layout bounds')
}

const requiredFiles = [
  'shell/Ui/Button.qml', 'shell/Ui/IconButton.qml', 'shell/Ui/TextField.qml',
  'shell/Ui/Checkbox.qml', 'shell/Ui/RadioButton.qml', 'shell/Ui/Toggle.qml', 'shell/Ui/ToggleSwitch.qml',
  'shell/Ui/ProgressBar.qml', 'shell/Ui/ProgressRing.qml', 'shell/Ui/OperationStatus.qml'
]
for (const relative of requiredFiles) {
  const qml = fs.readFileSync(path.join(root, relative), 'utf8')
  assert(qml.includes('semanticProfile'), `${relative} exposes the opt-in semantic profile seam`)
  assert(qml.includes('Accessible.'), `${relative} declares assistive semantics`)
}

const badge = fs.readFileSync(path.join(root, 'shell/Ui/Badge.qml'), 'utf8')
assert(badge.includes('property var semanticProfile: null')
  && badge.includes('Semantics.text(root.semanticProfile, root.text)'),
  'Badge localizes authored chrome through the opt-in semantic profile seam')

const dialog = fs.readFileSync(path.join(root, 'shell/Ui/OperationDialog.qml'), 'utf8')
assert(/property int selectedIndex:\s*0/.test(dialog), 'operation dialogs default to the cancel action')
assert(dialog.includes('Qt.Key_Escape') && dialog.includes('root.canceled()'), 'operation dialogs provide deterministic Escape cancellation')

const destructive = fs.readFileSync(path.join(root, 'shell/Ui/DestructiveDialog.qml'), 'utf8')
assert(destructive.includes('destructive: true') && destructive.includes('recoveryText:'), 'destructive dialogs expose consequence and recovery semantics')

const toggle = fs.readFileSync(path.join(root, 'shell/Ui/Toggle.qml'), 'utf8')
const toggleSwitch = fs.readFileSync(path.join(root, 'shell/Ui/ToggleSwitch.qml'), 'utf8')
assert(toggle.includes('Accessible.role: Accessible.CheckBox')
  && toggle.includes('Accessible.checked: root.checked'),
  'labeled toggle row retains its accessible checkbox state')
assert(toggle.includes('interactive: false') && toggle.includes('accessibleIgnored: true')
  && toggleSwitch.includes('Accessible.ignored: root.accessibleIgnored'),
  'labeled toggle exports one accessible node by ignoring its presentation-only switch')
assert(toggleSwitch.includes('property bool accessibleIgnored: !interactive'),
  'standalone switches stay accessible while non-interactive indicators are ignored by default')

const gallery = fs.readFileSync(path.join(root, 'shell/plugins/dev-gallery/QualityMatrix.qml'), 'utf8')
assert(gallery.includes('OperationStatus {') && gallery.includes('SemanticFixture {'), 'gallery matrix executes shared operation and control primitives')
assert(gallery.includes('OperationDialog {') && gallery.includes('DestructiveDialog {'), 'gallery matrix executes common and destructive dialog primitives')
assert(!/delegate\s*:\s*Rectangle\s*\{/.test(gallery), 'gallery matrix contains no rectangle-only mock delegates')

const galleryPanel = fs.readFileSync(path.join(root, 'shell/plugins/dev-gallery/GalleryPanel.qml'), 'utf8')
assert(gallery.includes('property alias focusAnchor: titleLabel')
  && galleryPanel.includes('root.ensureCursorVisible(qualityMatrix.focusAnchor)'),
  'gallery section navigation lands at the executable matrix heading')

const fixture = fs.readFileSync(path.join(root, 'shell/plugins/dev-gallery/SemanticFixture.qml'), 'utf8')
assert(fixture.includes('Button {') && fixture.includes('TextField {') && fixture.includes('Checkbox {')
  && fixture.includes('Toggle {') && fixture.includes('ToggleSwitch {') && fixture.includes('ProgressBar {'),
  'each presentation fixture executes the shared interactive control stack')
assert(fixture.includes('LayoutMirroring.enabled: profile.rtl')
  && fixture.includes('layoutDirection: profile.rtl'),
  'presentation fixture exercises actual RTL layout direction')
assert(fixture.includes('labelMaximumWidth:'), 'long presentation copy is constrained through the shared choice-control seam')
assert(fixture.includes('readonly property bool targetSizesPass')
  && fixture.includes('readonly property bool contentFits'),
  'presentation fixture publishes executable target and clipping audits')
JS

require_compositor "semantic UI QML runtime contract"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping semantic UI QML runtime contract"
  exit 0
fi

tmp_dir=$(mktemp -d)
cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

ln -s "$ROOT/shell/Ui" "$tmp_dir/Ui"
ln -s "$ROOT/shell/Commons" "$tmp_dir/Commons"
ln -s "$ROOT/shell/plugins/dev-gallery" "$tmp_dir/Gallery"
cp "$ROOT/test/shell.d/fixtures/semantic-ui/shell.qml" "$tmp_dir/shell.qml"

if ! output=$(timeout 15 quickshell -p "$tmp_dir" --no-color 2>&1); then
  printf '%s\n' "$output" >&2
  fail "semantic UI QML runtime fixture exits cleanly"
fi

if ! grep -Fq "RESULT pass" <<<"$output"; then
  printf '%s\n' "$output" >&2
  fail "semantic UI QML runtime fixture validates targets, motion, direction, state, and geometry"
fi

if grep -Eiq 'Unable to assign|binding loop|Cannot specify .* anchors' <<<"$output"; then
  printf '%s\n' "$output" >&2
  fail "semantic UI QML runtime fixture emits no binding or layout warnings"
fi

pass "semantic UI QML runtime fixture validates targets, motion, direction, state, and geometry"
pass "semantic UI QML runtime fixture emits no binding or layout warnings"
