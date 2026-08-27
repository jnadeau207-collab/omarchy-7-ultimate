#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

checker="$ROOT/bin/omarchy-dev-quality-baseline"
quality_dir="$ROOT/default/ultimate/quality"
gallery="$ROOT/shell/plugins/dev-gallery/QualityMatrix.qml"
semantic_fixture="$ROOT/shell/plugins/dev-gallery/SemanticFixture.qml"
panel="$ROOT/shell/plugins/dev-gallery/GalleryPanel.qml"
operation_status="$ROOT/shell/Ui/OperationStatus.qml"
progress_ring="$ROOT/shell/Ui/ProgressRing.qml"
card="$ROOT/shell/Ui/Card.qml"
checkbox="$ROOT/shell/Ui/Checkbox.qml"
radio_button="$ROOT/shell/Ui/RadioButton.qml"
shell_root="$ROOT/shell/shell.qml"
acceptance="$ROOT/test/acceptance.d/ultimate-accessibility-performance-test.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

run_checker() {
  OMARCHY_PATH="$ROOT" \
    OMARCHY_QUALITY_DIR="${1:-$quality_dir}" \
    OMARCHY_QUALITY_GALLERY="${2:-$gallery}" \
    OMARCHY_QUALITY_GALLERY_PANEL="${3:-$panel}" \
    bash "$checker" check
}

baseline_output=$(run_checker)
[[ $baseline_output == "quality baseline valid: 5 contracts, 10 metrics, 8 states, 4 presentation cases, 4 AT-SPI classes, 0 blocking/1 resolved incidents" ]] ||
  fail "quality checker accepts the canonical provisional baseline" "$baseline_output"
pass "quality checker accepts the canonical provisional baseline"

python3 - "$quality_dir/gallery-matrix-v0.json" <<'PY'
import json
import sys

matrix = json.load(open(sys.argv[1], encoding="utf-8"))
assert matrix["operationStates"] == ["success", "no-op", "progress", "denial", "failure", "cancel", "restart", "recovery"]
assert matrix["semanticRequirements"] == ["name", "role", "value", "action"]
assert matrix["semanticImplementation"] == {
    "name": "attached",
    "role": "attached",
    "value": "description-fallback-blocked",
    "action": "attached",
}
assert matrix["strategy"] == "exhaustive-operation-states-plus-pairwise-presentation-profiles"
assert matrix["fixtureImplementation"] == "shared-controls-with-opt-in-semantic-profiles"
assert matrix["automatedChecks"] == {
    "minimumNormalTextContrast": 4.5,
    "minimumLargeTextAndControlContrast": 3.0,
    "minimumPointerTargetPx": 24,
    "minimumTouchTargetPx": 44,
    "finiteLayoutBounds": True,
    "colorIndependentStateSymbols": True,
    "reducedMotionDurationMs": 0,
    "destructiveDefaultAction": "cancel",
}
PY
pass "gallery contract fixes exhaustive states and pairwise presentation coverage"

python3 - "$quality_dir/atspi-feasibility-v0.json" <<'PY'
import json
import sys

contract = json.load(open(sys.argv[1], encoding="utf-8"))
shell = next(entry for entry in contract["surfaceClasses"] if entry["id"] == "shell")
assert shell["status"] == "blocked"
assert shell["latestProbe"]["result"] == "blocked-zero-exported-children"
assert {row["name"]: row["children"] for row in shell["latestProbe"]["applications"]}["quickshell"] == 0
assert "not observable by an assistive client" in shell["evidence"]
PY
pass "AT-SPI contract records the fresh zero-child export blocker without claiming proof"

grep -Fq 'OperationStatus {' "$gallery" || fail "quality gallery executes the shared operation primitive"
grep -Fq 'SemanticFixture {' "$gallery" || fail "quality gallery executes the shared presentation fixture"
grep -Fq 'OperationDialog {' "$gallery" || fail "quality gallery executes the common operation dialog"
grep -Fq 'DestructiveDialog {' "$gallery" || fail "quality gallery executes the destructive dialog"
for control in 'Button {' 'TextField {' 'Checkbox {' 'ToggleSwitch {' 'ProgressBar {'; do
  grep -Fq "$control" "$semantic_fixture" || fail "semantic fixture executes shared control: $control"
done
grep -Fq 'definition.symbol' "$operation_status" || fail "operation status communicates state without color alone"
pass "quality gallery uses executable shared controls and color-independent operation states"

for marker in 'Accessible.name' 'Accessible.role' 'Accessible.description' 'Accessible.onPressAction'; do
  grep -Fq "$marker" "$gallery" || fail "quality gallery declares semantic $marker"
done
if grep -Fq 'Accessible.value' "$gallery"; then
  fail "quality gallery must not claim the unsupported Accessible.value property"
fi
grep -Fq 'Numeric AT-SPI value export is not yet available.' "$gallery" ||
  fail "quality gallery carries numeric state through its declared fallback"
grep -Fq 'QualityMatrix {' "$panel" || fail "dev gallery mounts the quality matrix"
pass "quality gallery declares name, role, action, and an honest blocked value fallback"

grep -Fq 'onPhaseChanged: canvas.requestPaint()' "$progress_ring" ||
  fail "quality gallery progress ring repaints from its animated phase"
if grep -Fq 'onValueChanged: canvas.requestPaint()' "$progress_ring"; then
  fail "quality gallery progress ring must not attach a nonexistent NumberAnimation value handler"
fi
pass "quality gallery progress ring uses a valid animation change handler"

grep -Fq 'signal hovered(bool on)' "$card" ||
  fail "interactive cards publish their hover contract"
grep -Fq 'onContainsMouseChanged: root.hovered(containsMouse)' "$card" ||
  fail "interactive cards drive the hover contract from the pointer area"
pass "quality gallery cards expose the hover signal consumed by the live fixture"

for choice_control in "$checkbox" "$radio_button"; do
  if grep -Eq 'label\.implicit(Width|Height)' "$choice_control"; then
    fail "choice control sizing must not dereference the string-valued label property" "$choice_control"
  fi
done
grep -Fq 'implicitWidth: box.implicitWidth' "$checkbox" || fail "checkbox sizing comes from its content row"
grep -Fq 'implicitWidth: circle.implicitWidth' "$radio_button" || fail "radio sizing comes from its content row"
pass "quality gallery choice controls have finite, non-circular implicit geometry"

if grep -Fq 'var detail = errorString' "$shell_root"; then
  fail "shell Loader error handlers must not reference a nonexistent errorString property"
fi
grep -Fq 'failed to load from " + panelEntry.sourceUrl' "$shell_root" ||
  fail "panel Loader failures retain their source URL"
grep -Fq 'failed to load from " + shell.activeBarSourceUrl' "$shell_root" ||
  fail "bar Loader failures retain their source URL"
pass "shell Loader failures report sources without throwing a second ReferenceError"

if OMARCHY_PATH="$ROOT" bash "$checker" probe-surfaces-once >"$tmp_dir/gate.out" 2>"$tmp_dir/gate.err"; then
  fail "surface probe refuses the active development session"
fi
grep -Fq 'restricted to a disposable VM' "$tmp_dir/gate.err" ||
  fail "surface probe refusal explains the disposable-VM policy" "$(cat "$tmp_dir/gate.err")"
pass "surface probe refuses the active development session"

grep -Fq 'MAX_SURFACE_CYCLES=1' "$checker" || fail "surface probe is hard-capped at one cycle"
grep -Fq 'stopOnCompositorPidChange' "$quality_dir/reliability-incidents-v0.json" || fail "incident contract stops on compositor changes"
grep -Fq 'stopOnNewCoredump' "$quality_dir/reliability-incidents-v0.json" || fail "incident contract stops on new coredumps"
pass "bounded probe caps churn and aborts on compositor or coredump change"

python3 - "$quality_dir/reliability-incidents-v0.json" <<'PY'
import json
import sys

incident = json.load(open(sys.argv[1], encoding="utf-8"))["incidents"][0]
verification = incident["resolution"]["verification"]
assert incident["status"] == "resolved"
assert verification["hyprlandPidUnchanged"] is True
assert verification["newCrashReport"] is False
assert verification["newCoredump"] is False
assert verification["maximizeRestoreCloseRaceCycles"] >= 30
assert set(verification["chromiumScreenshotSha256"]) == set(verification["chromiumStates"])
PY
pass "resolved compositor incident carries stress, crash-set, and hashed visual evidence"

make_case() {
  local name="$1"
  local case_dir="$tmp_dir/$name"
  mkdir -p "$case_dir/quality"
  cp "$quality_dir"/*.json "$case_dir/quality/"
  cp "$gallery" "$case_dir/QualityMatrix.qml"
  cp "$panel" "$case_dir/GalleryPanel.qml"
  printf '%s\n' "$case_dir"
}

expect_corruption_failure() {
  local description="$1" case_dir="$2"
  if run_checker "$case_dir/quality" "$case_dir/QualityMatrix.qml" "$case_dir/GalleryPanel.qml" >"$case_dir/out" 2>"$case_dir/err"; then
    fail "$description" "checker accepted generated corruption"
  fi
  pass "$description"
}

case_dir=$(make_case missing-state)
python3 - "$case_dir/quality/gallery-matrix-v0.json" <<'PY'
import json
import sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["operationStates"].remove("recovery")
open(path, "w", encoding="utf-8").write(json.dumps(value))
PY
expect_corruption_failure "checker rejects a missing operation state" "$case_dir"

case_dir=$(make_case invalid-unit)
python3 - "$case_dir/quality/performance-baseline-v0.json" <<'PY'
import json
import sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["metrics"][0]["unit"] = "fast-enough"
open(path, "w", encoding="utf-8").write(json.dumps(value))
PY
expect_corruption_failure "checker rejects an invented performance unit" "$case_dir"

case_dir=$(make_case invalid-threshold)
python3 - "$case_dir/quality/performance-baseline-v0.json" <<'PY'
import json
import sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["metrics"][0]["threshold"] = 0
open(path, "w", encoding="utf-8").write(json.dumps(value))
PY
expect_corruption_failure "checker rejects a non-positive performance threshold" "$case_dir"

case_dir=$(make_case dishonest-proof)
python3 - "$case_dir/quality/atspi-feasibility-v0.json" <<'PY'
import json
import sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["surfaceClasses"][2]["status"] = "proved"
open(path, "w", encoding="utf-8").write(json.dumps(value))
PY
expect_corruption_failure "checker rejects dishonest AT-SPI proof" "$case_dir"

case_dir=$(make_case missing-provenance)
python3 - "$case_dir/quality/reference-hardware-v0.json" <<'PY'
import json
import sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["provenance"]["commands"] = []
open(path, "w", encoding="utf-8").write(json.dumps(value))
PY
expect_corruption_failure "checker rejects reference hardware without command provenance" "$case_dir"

case_dir=$(make_case forbidden-v1)
python3 - "$case_dir/quality/gallery-matrix-v0.json" <<'PY'
import json
import sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["schemaVersion"] = "v1"
open(path, "w", encoding="utf-8").write(json.dumps(value))
PY
expect_corruption_failure "checker rejects a v1 quality contract" "$case_dir"

case_dir=$(make_case missing-gallery-state)
python3 - "$case_dir/QualityMatrix.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
assert 'id: "recovery"' in text
open(path, "w", encoding="utf-8").write(text.replace('id: "recovery"', 'id: "recovered"', 1))
PY
expect_corruption_failure "checker rejects gallery QML missing a contracted state" "$case_dir"

case_dir=$(make_case unbalanced-gallery-panel)
python3 - "$case_dir/GalleryPanel.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
assert text.rstrip().endswith("}")
open(path, "w", encoding="utf-8").write(text.rstrip()[:-1] + "\n")
PY
expect_corruption_failure "checker rejects an unbalanced gallery panel" "$case_dir"

case_dir=$(make_case dishonest-resolution)
python3 - "$case_dir/quality/reliability-incidents-v0.json" <<'PY'
import json
import sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["incidents"][0]["resolution"]["verification"]["newCrashReport"] = True
open(path, "w", encoding="utf-8").write(json.dumps(value))
PY
expect_corruption_failure "checker rejects a resolved incident with new crash evidence" "$case_dir"

case_dir=$(make_case missing-visual-proof)
python3 - "$case_dir/quality/reliability-incidents-v0.json" <<'PY'
import json
import sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
del value["incidents"][0]["resolution"]["verification"]["chromiumScreenshotSha256"]["maximize"]
open(path, "w", encoding="utf-8").write(json.dumps(value))
PY
expect_corruption_failure "checker rejects a resolved incident missing visual proof" "$case_dir"

for surface_class in shell secure-lock oobe polkit; do
  grep -Fq "\"$surface_class\"" "$acceptance" || fail "acceptance gate names $surface_class"
done
grep -Fq 'failures+=' "$acceptance" || fail "acceptance gate accumulates feasibility failures"
if grep -Eq 'skip|SKIP' "$acceptance"; then
  fail "acceptance gate never skips missing accessibility tooling or semantics"
fi
pass "acceptance gate explicitly covers all surface classes without skips"

bash -n "$checker"
bash -n "$acceptance"
pass "quality checker and disposable-VM acceptance entry pass bash syntax"
