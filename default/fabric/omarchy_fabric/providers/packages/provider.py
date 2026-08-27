"""Registry-admissible Software Center provider."""

from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping

from jsonschema import Draft202012Validator, ValidationError

from omarchy_fabric.models import FabricError
from omarchy_fabric.security.principal import EndpointPrincipal

from .catalog import PackageCatalog
from .contracts import CONTRACTS, ref
from .engine import FakeExecutionAdapter, PackageOperationEngine, inventory_revision


def _manifest_path() -> Path:
    return Path(__file__).with_name("manifest-v0.json")


class PackageProvider:
    def __init__(self, catalog: PackageCatalog, engine: PackageOperationEngine) -> None:
        self.catalog = catalog
        self.engine = engine
        self.manifest = json.loads(_manifest_path().read_text(encoding="utf-8"))
        self.schemas = deepcopy(CONTRACTS)
        self._validators = {schema_id: Draft202012Validator(schema) for schema_id, schema in self.schemas.items()}

    def _action(self, action: str, mode: str) -> Mapping[str, Any]:
        definition = self.manifest["actions"].get(action)
        if definition is None:
            raise FabricError("packages.action-unavailable", "Software action is unavailable", "The typed Software Center provider does not expose this action.", detail=str(action)[:160])
        if definition["mode"] != mode:
            raise FabricError("packages.action-mode-invalid", "Software action mode is invalid", f"The action cannot execute through the {mode} seam.", detail=action)
        return definition

    def _validate(self, reference: Mapping[str, Any], value: Any, label: str) -> None:
        try:
            self._validators[reference["id"]].validate(value)
        except (KeyError, ValidationError) as error:
            detail = ".".join(str(part) for part in getattr(error, "absolute_path", ()))
            raise FabricError("packages.contract-invalid", "Software provider value is invalid", "The value does not satisfy its closed typed contract.", detail=f"{label}{'.' + detail if detail else ''}") from error

    async def read(self, action: str, arguments: Mapping[str, Any]) -> Mapping[str, Any]:
        definition = self._action(action, "read")
        self._validate(definition["arguments"], arguments, "arguments")
        if action == "catalog.search":
            result = {"schemaVersion": "v0", "provider": "packages.provider", "assurance": self.catalog.assurance, "revision": self.catalog.revision, "entries": self.catalog.search(arguments["query"], arguments["sourceTypes"])}
        elif action == "inventory.inspect":
            result = self.engine.inventory(include_unmanaged=arguments["includeUnmanaged"])
        elif action == "adoption.inspect":
            inventory = self.engine.inventory(include_unmanaged=True)
            result = {"schemaVersion": "v0", "provider": "packages.provider", "revision": inventory["revision"], "items": self.catalog.adoption(inventory["items"])}
        elif action == "operations.inspect":
            result = self.engine.operations()
        else:
            raise AssertionError(action)
        self._validate(definition["result"], result, "result")
        return result

    async def preflight(self, action: str, arguments: Mapping[str, Any], principal: EndpointPrincipal) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        self._validate(definition["arguments"], arguments, "arguments")
        result = self.engine.preflight(action, arguments, principal)
        result.pop("_targetItem", None)
        self._validate(definition["preflight"], result, "preflight")
        return result

    async def apply(self, action: str, normalized_arguments: Mapping[str, Any], expected_revision: str) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        self._validate(definition["arguments"], normalized_arguments, "arguments")
        result = await self.engine.apply(action, normalized_arguments, expected_revision)
        self._validate(definition["result"], result, "result")
        return result

    async def validate(self, action: str, normalized_arguments: Mapping[str, Any], expected_state: Mapping[str, Any]) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        self._validate(definition["arguments"], normalized_arguments, "arguments")
        self._validate(definition["state"], expected_state, "expectedState")
        operation = self.engine._operations.get(expected_state["operationId"])
        if (
            operation is None
            or operation["action"] != action
            or operation["plan"]["normalizedArguments"] != dict(normalized_arguments)
            or self.engine._result(operation)["state"] != dict(expected_state)
        ):
            raise FabricError("packages.validation-failed", "Software operation state drifted", "Durable operation state does not match the expected exact revision.", retryable=True, change_state="unknown", recovery_actions=("packages.reconcile",))
        return deepcopy(dict(expected_state))

    async def rollback(self, action: str, prior_state: Mapping[str, Any], expected_revision: str) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        self._validate(definition["state"], prior_state, "priorState")
        operation = self.engine._operations.get(prior_state["operationId"])
        if operation is None or operation["action"] != action or self.engine._result(operation)["state"] != dict(prior_state):
            raise FabricError("packages.rollback-state-invalid", "Software rollback state is invalid", "Rollback requires the exact current state from the matching action.")
        result = await self.engine.rollback(prior_state["operationId"], expected_revision)
        self._validate(definition["result"], result, "result")
        return result


def build_fake_provider(
    catalog_document: Mapping[str, Any],
    inventory: list[Mapping[str, Any]],
    *,
    state_path: Path | None = None,
    adapter: FakeExecutionAdapter | None = None,
) -> PackageProvider:
    catalog = PackageCatalog(catalog_document)
    engine = PackageOperationEngine(catalog, inventory, state_path=state_path, adapter=adapter)
    return PackageProvider(catalog, engine)
