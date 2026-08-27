"""Strict known-good compatibility recipe inventory and trust validation."""

from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping

from jsonschema import Draft202012Validator

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.packages.identity import canonical_json, revision

MAX_RECIPE_BYTES = 2 * 1024 * 1024


def _schema_path() -> Path:
    return Path(__file__).resolve().parents[3] / "schema" / "compatibility-recipes-v0.json"


class RecipeCatalog:
    def __init__(
        self,
        document: Mapping[str, Any],
        *,
        trusted_keys: frozenset[str] = frozenset({"omarchy-compat-review-v1"}),
        verified_recipe_revisions: frozenset[str] = frozenset(),
    ) -> None:
        try:
            payload = canonical_json(document).encode("utf-8")
        except (TypeError, ValueError) as error:
            raise FabricError("compatibility.recipes-invalid", "Compatibility recipes are invalid", "Recipe data is not finite canonical JSON.", detail=type(error).__name__) from error
        if len(payload) > MAX_RECIPE_BYTES:
            raise FabricError("compatibility.recipes-too-large", "Compatibility recipes are too large", "The recipe inventory exceeds its bounded contract.")
        schema = json.loads(_schema_path().read_text(encoding="utf-8"))
        error = next(iter(Draft202012Validator(schema).iter_errors(document)), None)
        if error is not None:
            path = ".".join(str(part) for part in error.absolute_path)
            raise FabricError("compatibility.recipes-invalid", "Compatibility recipes are invalid", "Recipe data does not satisfy its closed schema.", detail=path or error.message)
        unsigned = deepcopy(dict(document))
        unsigned["revision"] = "sha256." + "0" * 64
        expected = revision(unsigned)
        if document["revision"] != expected:
            raise FabricError("compatibility.recipes-revision-invalid", "Compatibility recipe revision is invalid", "The declared recipe inventory revision does not match its canonical contents.")
        if document["assurance"] == "release-verified" and document["revision"] not in verified_recipe_revisions:
            raise FabricError("compatibility.recipes-unattested", "Compatibility recipes are not release-attested", "A recipe document cannot self-assert release verification; its exact revision must be admitted by code-owned release metadata.")
        assurance = document["assurance"]
        recipes: dict[str, dict[str, Any]] = {}
        workloads: set[str] = set()
        allowed_by_phase = {
            "install": {"verify-artifact", "create-prefix", "install-runtime", "apply-permissions", "create-launcher"},
            "validate": {"validate-launch"},
            "remove": {"remove-runtime", "remove-launcher"},
            "export": {"export-data"},
        }
        for recipe in document["recipes"]:
            if recipe["id"] in recipes or recipe["workloadId"] in workloads:
                raise FabricError("compatibility.recipes-invalid", "Compatibility recipes are invalid", "Recipe and workload identities must be unique.")
            required_status = "declared" if assurance == "contract-seed" else "verified"
            if recipe["signature"]["status"] != required_status or recipe["signature"]["keyId"] not in trusted_keys:
                raise FabricError("compatibility.recipe-untrusted", "Compatibility recipe assurance is invalid", "Recipe signature status and key identity must match the inventory assurance.", detail=recipe["id"])
            step_ids: set[str] = set()
            for phase, steps in recipe["lifecycle"].items():
                for step in steps:
                    if step["action"] not in allowed_by_phase[phase] or step["id"] in step_ids:
                        raise FabricError("compatibility.recipe-action-invalid", "Compatibility recipe action is invalid", "Recipe actions must belong to their lifecycle phase and step identities must be unique.", detail=recipe["id"])
                    step_ids.add(step["id"])
            if recipe["lifecycle"]["install"][0]["action"] != "verify-artifact":
                raise FabricError("compatibility.recipe-action-invalid", "Compatibility recipe action is invalid", "Recipe installation must verify the pinned artifact before every other action.", detail=recipe["id"])
            recipes[recipe["id"]] = deepcopy(recipe)
            workloads.add(recipe["workloadId"])
        self.document = deepcopy(dict(document))
        self.revision = document["revision"]
        self.assurance = assurance
        self.recipes = recipes
        self.by_workload = {recipe["workloadId"]: recipe for recipe in recipes.values()}

    @classmethod
    def load(cls, path: Path, *, trusted_keys: frozenset[str] = frozenset({"omarchy-compat-review-v1"}), verified_recipe_revisions: frozenset[str] = frozenset()) -> "RecipeCatalog":
        with path.open("rb") as stream:
            raw = stream.read(MAX_RECIPE_BYTES + 1)
        if len(raw) > MAX_RECIPE_BYTES:
            raise FabricError("compatibility.recipes-too-large", "Compatibility recipes are too large", "The recipe inventory exceeds its bounded contract.")
        try:
            document = json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise FabricError("compatibility.recipes-corrupt", "Compatibility recipes are corrupt", "Recipe data is not UTF-8 JSON.", detail=type(error).__name__) from error
        if not isinstance(document, dict):
            raise FabricError("compatibility.recipes-invalid", "Compatibility recipes are invalid", "The recipe root must be an object.")
        return cls(document, trusted_keys=trusted_keys, verified_recipe_revisions=verified_recipe_revisions)
