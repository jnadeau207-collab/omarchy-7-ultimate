"""Registry-admissible Compatibility Center provider."""

from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping

from jsonschema import Draft202012Validator, ValidationError

from omarchy_fabric.models import FabricError
from omarchy_fabric.provider_registry import ProviderAvailability
from omarchy_fabric.security.principal import EndpointPrincipal

from .contracts import CONTRACTS
from .engine import CompatibilityEngine, FakeCompatibilityAdapter
from .recipes import RecipeCatalog
from .router import ROUTE_ORDER

MAX_POLICY_BYTES = 128 * 1024
PLAN_ONLY_DETAIL = "The code-owned Compatibility Center recipes are contract seeds; reads and preflights are available, but live compatibility deployment is not admitted."

class CompatibilityProvider:
    def __init__(
        self,
        recipes: RecipeCatalog,
        engine: CompatibilityEngine,
        *,
        plan_only: bool = False,
        availability: ProviderAvailability | None = None,
    ) -> None:
        self.recipes = recipes
        self.engine = engine
        self.plan_only = plan_only
        if availability is not None:
            self.availability = availability
        self.manifest = json.loads(Path(__file__).with_name("manifest-v0.json").read_text(encoding="utf-8"))
        self.schemas = deepcopy(CONTRACTS)
        self._validators = {schema_id: Draft202012Validator(schema) for schema_id, schema in self.schemas.items()}

    def _action(self, action: str, mode: str) -> Mapping[str, Any]:
        definition = self.manifest["actions"].get(action)
        if definition is None:
            raise FabricError("compatibility.action-unavailable", "Compatibility action is unavailable", "The typed Compatibility Center provider does not expose this action.", detail=str(action)[:160])
        if definition["mode"] != mode:
            raise FabricError("compatibility.action-mode-invalid", "Compatibility action mode is invalid", f"The action cannot execute through the {mode} seam.", detail=action)
        return definition

    def _validate(self, reference: Mapping[str, Any], value: Any, label: str) -> None:
        try:
            self._validators[reference["id"]].validate(value)
        except (KeyError, ValidationError) as error:
            detail = ".".join(str(part) for part in getattr(error, "absolute_path", ()))
            raise FabricError("compatibility.contract-invalid", "Compatibility provider value is invalid", "The value does not satisfy its closed typed contract.", detail=f"{label}{'.' + detail if detail else ''}") from error

    async def read(self, action: str, arguments: Mapping[str, Any]) -> Mapping[str, Any]:
        definition = self._action(action, "read")
        self._validate(definition["arguments"], arguments, "arguments")
        if action == "route.decide":
            result = self.engine.router.decide(arguments["request"], arguments["host"])
        elif action == "deployments.inspect":
            result = self.engine.deployments()
        else:
            raise AssertionError(action)
        self._validate(definition["result"], result, "result")
        return result

    async def preflight(self, action: str, arguments: Mapping[str, Any], principal: EndpointPrincipal) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        self._validate(definition["arguments"], arguments, "arguments")
        result = self.engine.preflight(action, arguments, principal)
        result.pop("_targetDeployment", None)
        self._validate(definition["preflight"], result, "preflight")
        return result

    async def apply(self, action: str, normalized_arguments: Mapping[str, Any], expected_revision: str) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        self._require_live_execution()
        self._validate(definition["arguments"], normalized_arguments, "arguments")
        result = await self.engine.apply(action, normalized_arguments, expected_revision)
        self._validate(definition["result"], result, "result")
        return result

    async def validate(self, action: str, normalized_arguments: Mapping[str, Any], expected_state: Mapping[str, Any]) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        self._require_live_execution()
        self._validate(definition["arguments"], normalized_arguments, "arguments")
        self._validate(definition["state"], expected_state, "expectedState")
        operation = self.engine._operations.get(expected_state["operationId"])
        if (
            operation is None
            or operation["action"] != action
            or operation["plan"]["normalizedArguments"] != dict(normalized_arguments)
            or self.engine._result(operation)["state"] != dict(expected_state)
        ):
            raise FabricError("compatibility.validation-failed", "Compatibility operation state drifted", "Durable compatibility state does not match the expected exact revision.", retryable=True, change_state="unknown", recovery_actions=("compatibility.reconcile",))
        return deepcopy(dict(expected_state))

    async def rollback(self, action: str, prior_state: Mapping[str, Any], expected_revision: str) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        self._require_live_execution()
        if not definition["supportsRollback"]:
            raise FabricError("compatibility.rollback-unavailable", "Compatibility rollback is unavailable", "The action contract does not permit rollback.")
        self._validate(definition["state"], prior_state, "priorState")
        operation = self.engine._operations.get(prior_state["operationId"])
        if operation is None or operation["action"] != action or self.engine._result(operation)["state"] != dict(prior_state):
            raise FabricError("compatibility.rollback-state-invalid", "Compatibility rollback state is invalid", "Rollback requires the exact current state from the matching action.")
        result = await self.engine.rollback(prior_state["operationId"], expected_revision)
        self._validate(definition["result"], result, "result")
        return result

    def _require_live_execution(self) -> None:
        if self.plan_only:
            raise FabricError(
                "compatibility.execution-unavailable",
                "Compatibility execution is unavailable",
                "The production Compatibility Center provider is registered for contract-seed reads and preflights only; no live route adapter is admitted.",
                recovery_actions=("compatibility.release-recipes.install",),
            )

def _default_root() -> Path:
    return Path(__file__).resolve().parents[4]

def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON constant: {value}")

def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    document: dict[str, Any] = {}
    for key, value in pairs:
        if key in document:
            raise ValueError("duplicate JSON object key")
        document[key] = value
    return document

def _load_routing_policy(path: Path, schema_path: Path) -> Mapping[str, Any]:
    try:
        with path.open("rb") as stream:
            raw = stream.read(MAX_POLICY_BYTES + 1)
        with schema_path.open("rb") as stream:
            schema_raw = stream.read(MAX_POLICY_BYTES + 1)
    except OSError as error:
        raise FabricError(
            "compatibility.policy-unavailable",
            "Compatibility routing policy is unavailable",
            "The code-owned Compatibility Center routing policy or schema could not be opened.",
        ) from error
    if len(raw) > MAX_POLICY_BYTES or len(schema_raw) > MAX_POLICY_BYTES:
        raise FabricError(
            "compatibility.policy-too-large",
            "Compatibility routing policy is too large",
            "The code-owned Compatibility Center routing policy or schema exceeds its bounded contract.",
        )
    try:
        document = json.loads(
            raw,
            object_pairs_hook=_reject_duplicate_pairs,
            parse_constant=_reject_json_constant,
        )
        schema = json.loads(
            schema_raw,
            object_pairs_hook=_reject_duplicate_pairs,
            parse_constant=_reject_json_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise FabricError(
            "compatibility.policy-invalid",
            "Compatibility routing policy is invalid",
            "The code-owned Compatibility Center routing policy or schema is not finite UTF-8 JSON.",
        ) from error
    if not isinstance(document, dict) or not isinstance(schema, dict):
        raise FabricError(
            "compatibility.policy-invalid",
            "Compatibility routing policy is invalid",
            "The Compatibility Center policy and schema must be JSON objects.",
        )
    validation_error = next(iter(Draft202012Validator(schema).iter_errors(document)), None)
    if validation_error is not None or document.get("routeOrder") != list(ROUTE_ORDER):
        raise FabricError(
            "compatibility.policy-invalid",
            "Compatibility routing policy is invalid",
            "The code-owned Compatibility Center routing policy does not match the closed production contract.",
        )
    return deepcopy(document)

def build_provider() -> CompatibilityProvider:
    """Build the code-owned, contract-seed production provider without a live adapter."""

    root = _default_root()
    policy = _load_routing_policy(
        root / "ultimate" / "compatibility" / "routing-policy-v0.json",
        root / "fabric" / "schema" / "compatibility-routing-policy-v0.json",
    )
    recipes = RecipeCatalog.load(
        root / "ultimate" / "compatibility" / "recipes-v0.json",
        trusted_keys=frozenset(policy["recipeTrustKeyIds"]),
    )
    if recipes.assurance != "contract-seed":
        raise FabricError(
            "compatibility.recipes-assurance-unavailable",
            "Compatibility recipe assurance is unavailable",
            "Production registration admits the checked-in recipes only as contract seeds until an external release revision is configured.",
        )
    engine = CompatibilityEngine(recipes)
    return CompatibilityProvider(
        recipes,
        engine,
        plan_only=True,
        availability=ProviderAvailability("degraded", PLAN_ONLY_DETAIL),
    )

def build_fake_provider(recipe_document: Mapping[str, Any], *, deployments: list[Mapping[str, Any]] | None = None, state_path: Path | None = None, adapter: FakeCompatibilityAdapter | None = None) -> CompatibilityProvider:
    recipes = RecipeCatalog(recipe_document)
    engine = CompatibilityEngine(recipes, deployments=deployments, state_path=state_path, adapter=adapter)
    return CompatibilityProvider(recipes, engine)
