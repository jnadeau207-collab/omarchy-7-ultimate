#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
export PYTHONDONTWRITEBYTECODE=1

PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}" \
  python3 -m unittest discover -s "$ROOT/test/fabric/packages" -p 'test_*.py' -v
pass "Software Center catalog, provenance, adoption, lifecycle, cancellation, restart, and reconciliation contracts pass"

PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}" \
  python3 -m unittest discover -s "$ROOT/test/fabric/compatibility" -p 'test_*.py' -v
pass "Compatibility Center routing, recipe trust, permission, lifecycle, export, removal, and unsupported-state contracts pass"

provider_modules=(
  "$ROOT"/default/fabric/omarchy_fabric/providers/packages/*.py
  "$ROOT"/default/fabric/omarchy_fabric/providers/compatibility/*.py
)
(( ${#provider_modules[@]} >= 12 )) || fail "Software and compatibility provider module set is incomplete"

python3 - "${provider_modules[@]}" <<'PY'
import pathlib
import sys

for value in sys.argv[1:]:
    path = pathlib.Path(value)
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
pass "Software and compatibility provider Python modules compile"

if grep -En 'create_subprocess_shell|shell[[:space:]]*=[[:space:]]*True|os\.system|subprocess\.(run|Popen|call|check_call|check_output)|bash[[:space:]]+-c|eval\(|exec\(' "${provider_modules[@]}"; then
  fail "Software and compatibility providers contain no live process, shell, or dynamic-code execution path"
fi
pass "Software and compatibility foundations expose planning only through fixed-argv declarations"

python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

root = pathlib.Path(sys.argv[1])
common = json.loads((root / "default/fabric/schema/common-v0.json").read_text(encoding="utf-8"))
common_registry = Registry().with_resources(
    (
        (common["$id"], Resource.from_contents(common)),
        ("common-v0.json", Resource.from_contents(common)),
    )
)
schema_paths = sorted((root / "default/fabric/schema").glob("packages-*.json")) + sorted((root / "default/fabric/schema").glob("compatibility-*.json"))
assert len(schema_paths) >= 6
for path in schema_paths:
    schema = json.loads(path.read_text(encoding="utf-8"))
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"].startswith("urn:omarchy:fabric:schema:")
    Draft202012Validator.check_schema(schema)
    def visit(value, location=()):
        if isinstance(value, dict):
            if value.get("type") == "object" or "properties" in value:
                assert value.get("additionalProperties") is False, f"{path}:{'.'.join(location)}"
            for key, child in value.items():
                visit(child, (*location, key))
        elif isinstance(value, list):
            for index, child in enumerate(value):
                visit(child, (*location, str(index)))
    visit(schema)

for path in (
    root / "default/fabric/omarchy_fabric/providers/packages/manifest-v0.json",
    root / "default/fabric/omarchy_fabric/providers/compatibility/manifest-v0.json",
    root / "default/ultimate/software/catalog-v0.json",
    root / "default/ultimate/compatibility/recipes-v0.json",
):
    assert isinstance(json.loads(path.read_text(encoding="utf-8")), dict)

policy_pairs = (
    (root / "default/fabric/schema/packages-source-policy-v0.json", root / "default/ultimate/software/source-policy-v0.json"),
    (root / "default/fabric/schema/compatibility-routing-policy-v0.json", root / "default/ultimate/compatibility/routing-policy-v0.json"),
    (root / "default/fabric/schema/security-release-attestation-v0.json", root / "default/ultimate/release-attestation-v0.json"),
)
for schema_path, document_path in policy_pairs:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    document = json.loads(document_path.read_text(encoding="utf-8"))
    Draft202012Validator(schema, registry=common_registry).validate(document)
PY
pass "Software and compatibility schemas, manifests, catalog, and recipes are closed valid JSON documents"
