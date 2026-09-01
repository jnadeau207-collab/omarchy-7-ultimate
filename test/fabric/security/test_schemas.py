from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCHEMA_DIR = ROOT / "default" / "fabric" / "schema"
SECURITY_SCHEMAS = tuple(sorted(SCHEMA_DIR.glob("security-*.json")))
FORBIDDEN_EXECUTOR_FIELDS = re.compile(r"(?:command|cmd|shell|executable|binary|argv|env|path|directory|helper)", re.I)

def walk(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)

def resolve_pointer(document, pointer: str):
    current = document
    for part in pointer.removeprefix("/").split("/") if pointer else ():
        current = current[part.replace("~1", "/").replace("~0", "~")]
    return current

class SecuritySchemaTests(unittest.TestCase):
    def test_all_security_schemas_are_parseable_closed_draft_2020_contracts(self) -> None:
        self.assertGreaterEqual(len(SECURITY_SCHEMAS), 6)
        for path in SECURITY_SCHEMAS:
            with self.subTest(path=path.name):
                document = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(document["$schema"], "https://json-schema.org/draft/2020-12/schema")
                self.assertTrue(document["$id"].startswith("urn:omarchy:fabric:schema:security-"))
                self.assertEqual(document["type"], "object")
                self.assertIs(document["additionalProperties"], False)
                self.assertTrue(document["required"])

    def test_every_local_and_common_reference_resolves(self) -> None:
        common = json.loads((SCHEMA_DIR / "common-v0.json").read_text(encoding="utf-8"))
        for path in SECURITY_SCHEMAS:
            document = json.loads(path.read_text(encoding="utf-8"))
            for node in walk(document):
                if not isinstance(node, dict) or "$ref" not in node:
                    continue
                ref = node["$ref"]
                with self.subTest(path=path.name, ref=ref):
                    if ref.startswith("#/"):
                        resolve_pointer(document, ref[1:])
                    elif ref.startswith("common-v0.json#/"):
                        resolve_pointer(common, ref.split("#", 1)[1])
                    else:
                        self.fail(f"unapproved schema reference: {ref}")

    def test_every_security_schema_pattern_compiles(self) -> None:
        for path in SECURITY_SCHEMAS:
            document = json.loads(path.read_text(encoding="utf-8"))
            for node in walk(document):
                if isinstance(node, dict) and "pattern" in node:
                    with self.subTest(path=path.name, pattern=node["pattern"]):
                        re.compile(node["pattern"])

    def test_executor_schema_has_only_fixed_typed_arguments(self) -> None:
        document = json.loads((SCHEMA_DIR / "security-system-executor-v0.json").read_text(encoding="utf-8"))
        self.assertIn("correlates consent and audit only", document["description"])
        self.assertGreaterEqual(len(document["properties"]["action"]["enum"]), 8)
        for name, definition in document["$defs"].items():
            if not isinstance(definition, dict) or definition.get("type") != "object":
                continue
            self.assertIs(definition.get("additionalProperties"), False, name)
            for field in definition.get("properties", {}):
                self.assertIsNone(FORBIDDEN_EXECUTOR_FIELDS.search(field), f"{name}.{field}")

    def test_sandbox_schema_hard_codes_all_sensitive_exposure_off(self) -> None:
        document = json.loads((SCHEMA_DIR / "security-sandbox-profile-v0.json").read_text(encoding="utf-8"))
        exposure = document["properties"]["exposure"]
        expected = {
            "home",
            "wayland",
            "sessionBus",
            "sshAgent",
            "browserProfiles",
            "keyring",
            "mainFabricSocket",
            "hostNetwork",
        }
        self.assertEqual(set(exposure["required"]), expected)
        for field in expected:
            self.assertIs(exposure["properties"][field]["const"], False)

    def test_grant_schema_forbids_persistent_high_risk_and_shell_consequence(self) -> None:
        text = (SCHEMA_DIR / "security-grant-v0.json").read_text(encoding="utf-8")
        document = json.loads(text)
        self.assertIn("persistent", text)
        self.assertIn("high", text)
        self.assertIn("shell", text)
        self.assertEqual(document["properties"]["maximumRisk"]["enum"], ["low", "consequential", "high"])
        self.assertGreaterEqual(len(document["allOf"]), 3)

    def test_owned_contracts_do_not_advertise_a_frozen_version_one(self) -> None:
        forbidden = "v" + "1"
        roots = (
            ROOT / "default" / "fabric" / "omarchy_fabric" / "security",
            ROOT / "default" / "fabric" / "sandbox",
            ROOT / "default" / "fabric" / "schema",
            ROOT / "test" / "fabric" / "security",
        )
        files = [
            path
            for root in roots
            for path in root.rglob("*")
            if path.is_file()
            and path.suffix in {".json", ".py"}
            and (root.name != "schema" or path.name.startswith("security-"))
        ]
        files.append(ROOT / "docs" / "agent-fabric-threat-model.md")
        files.append(ROOT / "test" / "acceptance.d" / "agent-sandbox-test.sh")
        for path in files:
            with self.subTest(path=path):
                self.assertNotIn(forbidden, path.name.lower())
                self.assertNotIn(forbidden, path.read_text(encoding="utf-8").lower())

if __name__ == "__main__":
    unittest.main()
