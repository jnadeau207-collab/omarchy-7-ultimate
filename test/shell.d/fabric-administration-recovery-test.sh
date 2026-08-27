#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python
require_command rg

domains=(process device storage printer account firewall service schedule update recovery backup diagnostics)
for domain in "${domains[@]}"; do
  [[ -f $ROOT/default/fabric/omarchy_fabric/providers/$domain/provider.py ]] || fail "$domain provider implementation exists"
  [[ -f $ROOT/default/fabric/omarchy_fabric/providers/$domain/__init__.py ]] || fail "$domain provider package exists"
done
pass "all twelve administration and recovery provider packages exist"

schemas=(admin-inventory-v0.json update-plan-v0.json recovery-point-v0.json backup-plan-v0.json diagnostics-bundle-v0.json)
for schema in "${schemas[@]}"; do
  [[ -f $ROOT/default/fabric/schema/$schema ]] || fail "$schema exists"
done
pass "all public administration and recovery schemas exist"

python - "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
catalog = json.loads((root / "default/ultimate/administration/provider-catalog-v0.json").read_text())
policy = json.loads((root / "default/ultimate/recovery/policy-v0.json").read_text())
assert catalog["executionBoundary"] == "plan-only"
assert catalog["authorizationBoundary"] == "central-fabric"
assert len(catalog["providers"]) == 8
assert all(provider["realMutation"] is False for provider in catalog["providers"])
assert policy["restore"]["scope"] == "system"
assert policy["restore"]["preserveHome"] is True
assert policy["restore"]["exactConfirmation"] is True
assert policy["restore"]["verifiedHealthyRequired"] is True
assert policy["restore"]["verifiedReadOnlyRequired"] is True
assert policy["restore"]["realMutation"] is False
assert policy["backup"]["scope"] == "home"
assert policy["backup"]["verifiedSnapshotPathsRequired"] is True
assert policy["update"]["privateJournalRequired"] is True
assert policy["update"]["crossProcessLockRequired"] is True
assert policy["diagnostics"]["structuredEvidenceOnly"] is True
assert policy["diagnostics"]["upload"] is False
for name in ("admin-inventory-v0.json", "update-plan-v0.json", "recovery-point-v0.json", "backup-plan-v0.json", "diagnostics-bundle-v0.json"):
    schema = json.loads((root / "default/fabric/schema" / name).read_text())
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["x-omarchy-version"] == "v0"
    assert schema["additionalProperties"] is False
PY
pass "plan-only catalogs and closed schema identities are pinned"

provider_roots=("${domains[@]/#/$ROOT/default/fabric/omarchy_fabric/providers/}")
if rg -n 'shell\s*=\s*True|os\.system\s*\(|/usr/bin/(sudo|pkexec)|subprocess\.(run|Popen)\s*\(' "${provider_roots[@]}"; then
  fail "administration and recovery providers contain no shell, generic privilege, or direct subprocess escape"
fi
pass "providers contain no shell, generic privilege, or direct subprocess escape"

fixed_count=$(rg -l 'FixedArgvCommand\(' "${provider_roots[@]}" | wc -l)
(( fixed_count >= 12 )) || fail "each real provider family declares fixed argv probes" "found $fixed_count provider files with fixed argv"
pass "real inventory probes are code-owned fixed argv"

rg -q 'ReadOnlyProbeBackend' "${provider_roots[@]}" || fail "real providers use the shared read-only probe backend"
rg -q 'FakeBackend' "${provider_roots[@]}" || fail "providers expose hermetic fake lifecycle adapters"
pass "real mutation stays unavailable while fake lifecycle coverage uses the central engine"
