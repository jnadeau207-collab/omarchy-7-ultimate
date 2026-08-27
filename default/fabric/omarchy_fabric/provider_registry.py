"""Fail-closed registry for code-owned typed Fabric providers.

The provisional fake-provider registry in :mod:`omarchy_fabric.daemon` exists
only for transport tests.  This registry is the product-facing boundary: the
daemon admits provider objects selected by its own code, validates their
closed manifests and schemas, negotiates protocol compatibility, and permits
only typed read actions until the durable operation coordinator owns mutation.
"""

from __future__ import annotations

import asyncio
import hashlib
import inspect
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping, Protocol, runtime_checkable

from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError, ValidationError
from referencing import Registry, Resource
from referencing.exceptions import Unresolvable

from .models import MAX_FRAME_BYTES, PROTOCOL_VERSION, FabricError


MANIFEST_SCHEMA_ID = "urn:omarchy:fabric:schema:provider-manifest-v0"
SCHEMA_DIALECT = "https://json-schema.org/draft/2020-12/schema"
MAX_PROVIDER_DOCUMENT_BYTES = 256 * 1024
MAX_PROVIDER_VALUE_BYTES = MAX_FRAME_BYTES - 8192
MAX_PROVIDER_READ_SECONDS = 8.0
MAX_PROVIDER_PREFLIGHT_SECONDS = 8.0


@runtime_checkable
class TypedProvider(Protocol):
    """Narrow leaf-provider adapter consumed by the central registry."""

    manifest: Mapping[str, Any]
    schemas: Mapping[str, Mapping[str, Any]]

    async def read(self, action: str, arguments: Mapping[str, Any]) -> Any:
        """Return the typed, side-effect-free result for one read action."""


@dataclass(frozen=True)
class ProviderRegistration:
    provider_id: str
    provider_version: str
    generation: int
    disposition: str
    state: str


@dataclass
class _ProviderRecord:
    provider: TypedProvider
    manifest: dict[str, Any]
    fingerprint: str
    validators: dict[tuple[str, str], Draft202012Validator]
    generation: int
    state: str
    detail: str
    registered_at: float
    changed_at: float


def _schema_directory() -> Path:
    return Path(__file__).resolve().parent.parent / "schema"


def _finite_json_copy(value: Any, *, label: str, maximum: int) -> Any:
    def thaw(candidate: Any) -> Any:
        if isinstance(candidate, Mapping):
            return {key: thaw(item) for key, item in candidate.items()}
        if isinstance(candidate, (list, tuple)):
            return [thaw(item) for item in candidate]
        return candidate

    try:
        encoded = json.dumps(
            thaw(value),
            allow_nan=False,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise FabricError(
            "provider.invalid-json",
            "Fabric provider data is invalid",
            f"The {label} must contain finite JSON values.",
            detail=str(error),
        ) from error
    if len(encoded) > maximum:
        raise FabricError(
            "provider.value-too-large",
            "Fabric provider data is too large",
            f"The {label} exceeds the bounded provider contract.",
            detail=f"{len(encoded)} bytes exceeds {maximum}",
        )
    return json.loads(encoded)


def _validation_detail(error: ValidationError) -> str:
    path = ".".join(str(part) for part in error.absolute_path)
    if path:
        return f"{path}: {error.message}"
    return error.message


def _walk_json(value: Any):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from _walk_json(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_json(child)


def _resolve_json_pointer(document: Any, pointer: str) -> Any:
    if not pointer:
        return document
    if not pointer.startswith("/"):
        raise KeyError("only JSON Pointer fragments are supported")
    current = document
    for raw_part in pointer[1:].split("/"):
        part = raw_part.replace("~1", "/").replace("~0", "~")
        if isinstance(current, dict):
            current = current[part]
        elif isinstance(current, list):
            current = current[int(part)]
        else:
            raise KeyError(part)
    return current


class ProviderRegistry:
    """Own typed provider admission, lifecycle, and read-only dispatch."""

    def __init__(
        self,
        *,
        protocol_version: int = PROTOCOL_VERSION,
        clock: Callable[[], float] = time.time,
        event_sink: Callable[[str, Mapping[str, Any]], None] | None = None,
    ) -> None:
        if isinstance(protocol_version, bool) or not isinstance(protocol_version, int):
            raise TypeError("protocol_version must be an integer")
        self.protocol_version = protocol_version
        self._clock = clock
        self._event_sink = event_sink
        self._records: dict[str, _ProviderRecord] = {}

        directory = _schema_directory()
        manifest = json.loads((directory / "provider-manifest-v0.json").read_text())
        common = json.loads((directory / "common-v0.json").read_text())
        resources = Registry().with_resources(
            [
                (manifest["$id"], Resource.from_contents(manifest)),
                (common["$id"], Resource.from_contents(common)),
                ("common-v0.json", Resource.from_contents(common)),
            ]
        )
        self._manifest_validator = Draft202012Validator(manifest, registry=resources)

    @property
    def provider_count(self) -> int:
        return len(self._records)

    @property
    def available_count(self) -> int:
        return sum(record.state == "available" for record in self._records.values())

    def register(self, provider: TypedProvider) -> ProviderRegistration:
        """Register a code-selected provider or prove an identical registration."""

        manifest, validators, fingerprint = self._admit(provider)
        provider_id = manifest["provider"]
        existing = self._records.get(provider_id)
        if existing is not None:
            if existing.fingerprint != fingerprint:
                raise FabricError(
                    "provider.registration-conflict",
                    "Fabric provider registration conflicts",
                    "The provider ID is already bound to a different manifest or schema set.",
                    detail=provider_id,
                    recovery_actions=("system.update",),
                )
            return ProviderRegistration(
                provider_id,
                manifest["providerVersion"],
                existing.generation,
                "unchanged",
                existing.state,
            )

        now = self._clock()
        state, detail = self._compatibility(manifest)
        record = _ProviderRecord(
            provider=provider,
            manifest=manifest,
            fingerprint=fingerprint,
            validators=validators,
            generation=1,
            state=state,
            detail=detail,
            registered_at=now,
            changed_at=now,
        )
        self._records[provider_id] = record
        self._emit("provider.lifecycle", self._lifecycle_payload(record, "registered"))
        return ProviderRegistration(
            provider_id,
            manifest["providerVersion"],
            record.generation,
            "registered",
            state,
        )

    def reregister(
        self,
        provider: TypedProvider,
        *,
        expected_generation: int,
    ) -> ProviderRegistration:
        """Atomically replace a known provider after an explicit lifecycle handoff."""

        manifest, validators, fingerprint = self._admit(provider)
        provider_id = manifest["provider"]
        existing = self._records.get(provider_id)
        if existing is None:
            raise self._unavailable(provider_id)
        if existing.generation != expected_generation:
            raise FabricError(
                "provider.generation-conflict",
                "Fabric provider generation changed",
                "The provider changed before re-registration could complete.",
                detail=provider_id,
                retryable=True,
                recovery_actions=("provider.refresh",),
            )
        if existing.fingerprint == fingerprint and existing.state == "available":
            return ProviderRegistration(
                provider_id,
                manifest["providerVersion"],
                existing.generation,
                "unchanged",
                existing.state,
            )

        state, detail = self._compatibility(manifest)
        now = self._clock()
        replacement = _ProviderRecord(
            provider=provider,
            manifest=manifest,
            fingerprint=fingerprint,
            validators=validators,
            generation=existing.generation + 1,
            state=state,
            detail=detail,
            registered_at=existing.registered_at,
            changed_at=now,
        )
        self._records[provider_id] = replacement
        self._emit("provider.lifecycle", self._lifecycle_payload(replacement, "reregistered"))
        return ProviderRegistration(
            provider_id,
            manifest["providerVersion"],
            replacement.generation,
            "reregistered",
            state,
        )

    def mark_unavailable(
        self,
        provider_id: str,
        *,
        expected_generation: int,
        detail: str,
    ) -> ProviderRegistration:
        record = self._records.get(provider_id)
        if record is None:
            raise self._unavailable(provider_id)
        if record.generation != expected_generation:
            raise FabricError(
                "provider.generation-conflict",
                "Fabric provider generation changed",
                "The provider changed before its disconnect could be recorded.",
                detail=provider_id,
                retryable=True,
                recovery_actions=("provider.refresh",),
            )
        if not isinstance(detail, str) or not 1 <= len(detail) <= 2000:
            raise FabricError(
                "provider.invalid-lifecycle",
                "Fabric provider lifecycle update is invalid",
                "An unavailable provider requires a bounded explanation.",
            )
        if record.state == "unavailable" and record.detail == detail:
            return ProviderRegistration(
                provider_id,
                record.manifest["providerVersion"],
                record.generation,
                "unchanged",
                record.state,
            )
        record.generation += 1
        record.state = "unavailable"
        record.detail = detail
        record.changed_at = self._clock()
        self._emit("provider.lifecycle", self._lifecycle_payload(record, "disconnected"))
        return ProviderRegistration(
            provider_id,
            record.manifest["providerVersion"],
            record.generation,
            "disconnected",
            record.state,
        )

    def catalog(self) -> list[dict[str, Any]]:
        return [
            {
                "manifest": _finite_json_copy(
                    record.manifest,
                    label="provider manifest",
                    maximum=MAX_PROVIDER_DOCUMENT_BYTES,
                ),
                "fingerprint": record.fingerprint,
                "generation": record.generation,
                "state": record.state,
                "detail": record.detail,
                "registeredAt": record.registered_at,
                "changedAt": record.changed_at,
            }
            for record in sorted(
                self._records.values(),
                key=lambda candidate: candidate.manifest["provider"],
            )
        ]

    async def read(
        self,
        provider_id: str,
        action: str,
        arguments: Mapping[str, Any],
    ) -> dict[str, Any]:
        record = self._records.get(provider_id)
        if record is None:
            raise self._unavailable(provider_id)
        if record.state == "incompatible":
            raise FabricError(
                "provider.incompatible-version",
                "Fabric provider version is incompatible",
                record.detail,
                detail=provider_id,
                recovery_actions=("system.update",),
            )
        if record.state != "available":
            raise self._unavailable(provider_id, detail=record.detail)
        action_contract = record.manifest["actions"].get(action)
        if action_contract is None:
            raise FabricError(
                "provider.action-unavailable",
                "Fabric provider action is unavailable",
                "The typed provider does not expose this action.",
                detail=f"{provider_id}.{action}",
            )
        if action_contract["mode"] != "read":
            raise FabricError(
                "operation.durable-route-required",
                "A durable operation route is required",
                "Mutating provider actions cannot execute through the read-only registry path.",
                detail=f"{provider_id}.{action}",
                recovery_actions=("operation.preflight",),
            )
        if not isinstance(arguments, Mapping):
            raise FabricError(
                "provider.invalid-arguments",
                "Fabric provider arguments are invalid",
                "Provider arguments must be a JSON object.",
            )
        normalized_arguments = _finite_json_copy(
            dict(arguments),
            label="provider arguments",
            maximum=MAX_PROVIDER_VALUE_BYTES,
        )
        self._validate_value(
            record.validators[(action, "arguments")],
            normalized_arguments,
            provider_id=provider_id,
            action=action,
            phase="arguments",
        )
        generation = record.generation
        try:
            value = await asyncio.wait_for(
                record.provider.read(action, normalized_arguments),
                timeout=MAX_PROVIDER_READ_SECONDS,
            )
        except asyncio.TimeoutError as error:
            raise FabricError(
                "provider.timeout",
                "Fabric provider read timed out",
                "The provider did not return read state within its bounded deadline.",
                detail=f"{provider_id}.{action}",
                retryable=True,
                recovery_actions=("provider.retry",),
            ) from error
        except FabricError:
            raise
        except Exception as error:
            raise FabricError(
                "provider.failed",
                "Fabric provider read failed",
                "The provider failed without a structured error.",
                detail=type(error).__name__,
                retryable=True,
                recovery_actions=("provider.retry",),
            ) from error
        current = self._records.get(provider_id)
        if current is not record or record.generation != generation or record.state != "available":
            raise FabricError(
                "provider.changed-during-read",
                "Fabric provider changed during the read",
                "The returned state may belong to an obsolete provider generation and was discarded.",
                detail=provider_id,
                retryable=True,
                recovery_actions=("provider.retry",),
            )
        normalized_result = _finite_json_copy(
            value,
            label="provider result",
            maximum=MAX_PROVIDER_VALUE_BYTES,
        )
        self._validate_value(
            record.validators[(action, "result")],
            normalized_result,
            provider_id=provider_id,
            action=action,
            phase="result",
        )
        return {
            "provider": provider_id,
            "providerVersion": record.manifest["providerVersion"],
            "generation": generation,
            "action": action,
            "capability": action_contract["capability"],
            "value": normalized_result,
            "observedAt": self._clock(),
        }

    async def preflight(
        self,
        provider_id: str,
        action: str,
        arguments: Mapping[str, Any],
        principal: Any,
    ) -> dict[str, Any]:
        """Build and validate a mutation plan without authorizing or applying it.

        This internal seam deliberately does not return an apply handle. A future
        durable operation coordinator must persist and authorize the normalized
        plan before it can call any mutating leaf hook.
        """

        record = self._records.get(provider_id)
        if record is None:
            raise self._unavailable(provider_id)
        if record.state == "incompatible":
            raise FabricError(
                "provider.incompatible-version",
                "Fabric provider version is incompatible",
                record.detail,
                detail=provider_id,
                recovery_actions=("system.update",),
            )
        if record.state != "available":
            raise self._unavailable(provider_id, detail=record.detail)
        action_contract = record.manifest["actions"].get(action)
        if action_contract is None:
            raise FabricError(
                "provider.action-unavailable",
                "Fabric provider action is unavailable",
                "The typed provider does not expose this action.",
                detail=f"{provider_id}.{action}",
            )
        if action_contract["mode"] != "operation":
            raise FabricError(
                "provider.action-mode-invalid",
                "Fabric provider action mode is invalid",
                "Read actions do not have a mutation preflight contract.",
                detail=f"{provider_id}.{action}",
            )
        if not isinstance(arguments, Mapping):
            raise FabricError(
                "provider.invalid-arguments",
                "Fabric provider arguments are invalid",
                "Provider arguments must be a JSON object.",
            )
        normalized_arguments = _finite_json_copy(
            dict(arguments),
            label="provider arguments",
            maximum=MAX_PROVIDER_VALUE_BYTES,
        )
        self._validate_value(
            record.validators[(action, "arguments")],
            normalized_arguments,
            provider_id=provider_id,
            action=action,
            phase="arguments",
        )
        generation = record.generation
        try:
            value = await asyncio.wait_for(
                record.provider.preflight(action, normalized_arguments, principal),
                timeout=MAX_PROVIDER_PREFLIGHT_SECONDS,
            )
        except asyncio.TimeoutError as error:
            raise FabricError(
                "provider.preflight-timeout",
                "Fabric provider preflight timed out",
                "The provider could not freeze current state within its bounded deadline.",
                detail=f"{provider_id}.{action}",
                retryable=True,
                recovery_actions=("provider.retry",),
            ) from error
        except FabricError:
            raise
        except Exception as error:
            raise FabricError(
                "provider.preflight-failed",
                "Fabric provider preflight failed",
                "The provider failed without a structured preflight error.",
                detail=type(error).__name__,
                retryable=True,
                recovery_actions=("provider.retry",),
            ) from error
        current = self._records.get(provider_id)
        if current is not record or record.generation != generation or record.state != "available":
            raise FabricError(
                "provider.changed-during-preflight",
                "Fabric provider changed during preflight",
                "The frozen plan belongs to an obsolete provider generation and was discarded.",
                detail=provider_id,
                retryable=True,
                recovery_actions=("provider.retry",),
            )
        normalized_preflight = _finite_json_copy(
            value,
            label="provider preflight",
            maximum=MAX_PROVIDER_VALUE_BYTES,
        )
        self._validate_value(
            record.validators[(action, "preflight")],
            normalized_preflight,
            provider_id=provider_id,
            action=action,
            phase="preflight",
        )
        return {
            "provider": provider_id,
            "providerVersion": record.manifest["providerVersion"],
            "providerFingerprint": record.fingerprint,
            "generation": generation,
            "action": action,
            "capability": action_contract["capability"],
            "risk": action_contract["risk"],
            "effects": list(action_contract["effects"]),
            "preflight": normalized_preflight,
            "observedAt": self._clock(),
        }

    def _admit(
        self,
        provider: TypedProvider,
    ) -> tuple[
        dict[str, Any],
        dict[tuple[str, str], Draft202012Validator],
        str,
    ]:
        if not isinstance(provider, TypedProvider):
            raise FabricError(
                "provider.invalid-adapter",
                "Fabric provider adapter is invalid",
                "A typed provider must expose manifest, schemas, and an async read method.",
            )
        ensure_async_provider_hooks(provider)
        manifest = _finite_json_copy(
            provider.manifest,
            label="provider manifest",
            maximum=MAX_PROVIDER_DOCUMENT_BYTES,
        )
        manifest_errors = sorted(
            self._manifest_validator.iter_errors(manifest),
            key=lambda error: list(error.absolute_path),
        )
        if manifest_errors:
            raise FabricError(
                "provider.invalid-manifest",
                "Fabric provider manifest is invalid",
                "The provider declaration does not match the closed manifest contract.",
                detail=_validation_detail(manifest_errors[0]),
            )
        if manifest["minFabricProtocol"] > manifest["maxFabricProtocol"]:
            raise FabricError(
                "provider.invalid-manifest",
                "Fabric provider manifest is invalid",
                "The provider protocol range must contain ordered bounds.",
                detail=manifest["provider"],
            )
        capabilities = set(manifest["capabilities"])
        contract_refs: dict[str, str] = {}
        for action, contract in manifest["actions"].items():
            if contract["capability"] not in capabilities:
                raise FabricError(
                    "provider.invalid-manifest",
                    "Fabric provider manifest is invalid",
                    "Every action capability must appear in the provider capability list.",
                    detail=f"{manifest['provider']}.{action}",
                )
            if contract["mode"] == "read":
                if (
                    contract["risk"] != "read-only"
                    or contract["effects"]
                    or contract["preflight"] is not None
                    or contract["state"] is not None
                    or contract["supportsRollback"]
                    or contract["supportsCancellation"]
                ):
                    raise FabricError(
                        "provider.invalid-manifest",
                        "Fabric provider manifest is invalid",
                        "Read actions must be side-effect free and carry no operation lifecycle contract.",
                        detail=f"{manifest['provider']}.{action}",
                    )
            else:
                if (
                    contract["risk"] == "read-only"
                    or "mutating" not in contract["effects"]
                    or contract["preflight"] is None
                    or contract["state"] is None
                ):
                    raise FabricError(
                        "provider.invalid-manifest",
                        "Fabric provider manifest is invalid",
                        "Operation actions require mutating risk, preflight, and state contracts.",
                        detail=f"{manifest['provider']}.{action}",
                    )
                if contract["risk"] == "destructive" and "destructive" not in contract["effects"]:
                    raise FabricError(
                        "provider.invalid-manifest",
                        "Fabric provider manifest is invalid",
                        "Destructive operations must declare the destructive effect.",
                        detail=f"{manifest['provider']}.{action}",
                    )
                if (
                    contract["risk"] != "destructive"
                    and {"destructive", "irreversible"} & set(contract["effects"])
                ):
                    raise FabricError(
                        "provider.invalid-manifest",
                        "Fabric provider manifest is invalid",
                        "Destructive or irreversible effects require destructive risk classification.",
                        detail=f"{manifest['provider']}.{action}",
                    )
                if "irreversible" in contract["effects"] and contract["supportsRollback"]:
                    raise FabricError(
                        "provider.invalid-manifest",
                        "Fabric provider manifest is invalid",
                        "An irreversible operation cannot claim rollback support.",
                        detail=f"{manifest['provider']}.{action}",
                    )
                for hook in ("preflight", "apply", "validate", "rollback"):
                    if not callable(getattr(provider, hook, None)):
                        raise FabricError(
                            "provider.invalid-adapter",
                            "Fabric provider adapter is invalid",
                            "Operation providers must expose the complete durable lifecycle hook set.",
                            detail=f"{manifest['provider']}.{hook}",
                        )
            for phase in ("arguments", "result", "preflight", "state"):
                reference = contract[phase]
                if reference is not None:
                    prior = contract_refs.get(reference["id"])
                    if prior is not None and prior != reference["version"]:
                        raise FabricError(
                            "provider.invalid-manifest",
                            "Fabric provider manifest is invalid",
                            "One schema ID cannot be referenced at multiple versions.",
                            detail=reference["id"],
                        )
                    contract_refs[reference["id"]] = reference["version"]

        raw_schemas = _finite_json_copy(
            provider.schemas,
            label="provider schema set",
            maximum=MAX_PROVIDER_DOCUMENT_BYTES,
        )
        if not isinstance(raw_schemas, dict) or set(raw_schemas) != set(contract_refs):
            missing = sorted(set(contract_refs) - set(raw_schemas))
            extra = sorted(set(raw_schemas) - set(contract_refs))
            raise FabricError(
                "provider.invalid-schemas",
                "Fabric provider schemas are invalid",
                "The provider must expose exactly the schemas referenced by its manifest.",
                detail=f"missing={missing}; extra={extra}",
            )

        common = json.loads((_schema_directory() / "common-v0.json").read_text())
        resources: list[tuple[str, Resource[Any]]] = [
            (common["$id"], Resource.from_contents(common)),
            ("common-v0.json", Resource.from_contents(common)),
        ]
        allowed_references = set(contract_refs) | {
            "",
            common["$id"],
            "common-v0.json",
        }
        for schema_id, version in contract_refs.items():
            schema = raw_schemas[schema_id]
            if not isinstance(schema, dict):
                raise FabricError(
                    "provider.invalid-schemas",
                    "Fabric provider schemas are invalid",
                    "Every provider schema must be a JSON object.",
                    detail=schema_id,
                )
            if (
                schema.get("$schema") != SCHEMA_DIALECT
                or schema.get("$id") != schema_id
                or schema.get("x-omarchy-version") != version
            ):
                raise FabricError(
                    "provider.invalid-schemas",
                    "Fabric provider schemas are invalid",
                    "A provider schema identity or version does not match its manifest reference.",
                    detail=schema_id,
                )
            if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
                raise FabricError(
                    "provider.invalid-schemas",
                    "Fabric provider schemas are invalid",
                    "Every provider contract must be a closed top-level object schema.",
                    detail=schema_id,
                )
            for node in _walk_json(schema):
                if not isinstance(node, dict):
                    continue
                if node.get("type") == "object" and node.get("additionalProperties") is not False:
                    raise FabricError(
                        "provider.invalid-schemas",
                        "Fabric provider schemas are invalid",
                        "Every object inside a provider contract must reject unknown properties.",
                        detail=schema_id,
                    )
                reference = node.get("$ref")
                if reference is None:
                    continue
                if not isinstance(reference, str) or not reference:
                    raise FabricError(
                        "provider.invalid-schemas",
                        "Fabric provider schemas are invalid",
                        "Provider schema references must be non-empty strings.",
                        detail=schema_id,
                    )
                reference_base = reference.split("#", 1)[0]
                if reference_base not in allowed_references:
                    raise FabricError(
                        "provider.invalid-schemas",
                        "Fabric provider schemas are invalid",
                        "Provider contracts may reference only their declared local schema set and common vocabulary.",
                        detail=f"{schema_id}: {reference}",
                    )
                fragment = reference.split("#", 1)[1] if "#" in reference else ""
                if reference_base in {"", schema_id}:
                    target_schema = schema
                elif reference_base in {common["$id"], "common-v0.json"}:
                    target_schema = common
                else:
                    target_schema = raw_schemas[reference_base]
                try:
                    _resolve_json_pointer(target_schema, fragment)
                except (KeyError, IndexError, ValueError, TypeError) as error:
                    raise FabricError(
                        "provider.invalid-schemas",
                        "Fabric provider schemas are invalid",
                        "A provider schema reference does not resolve to a declared contract node.",
                        detail=f"{schema_id}: {reference}",
                    ) from error
            try:
                Draft202012Validator.check_schema(schema)
            except SchemaError as error:
                raise FabricError(
                    "provider.invalid-schemas",
                    "Fabric provider schemas are invalid",
                    "A provider contract is not a valid Draft 2020-12 schema.",
                    detail=f"{schema_id}: {error.message}",
                ) from error
            resources.append((schema_id, Resource.from_contents(schema)))
        registry = Registry().with_resources(resources)
        schema_validators = {
            schema_id: Draft202012Validator(raw_schemas[schema_id], registry=registry)
            for schema_id in contract_refs
        }
        validators: dict[tuple[str, str], Draft202012Validator] = {}
        for action, contract in manifest["actions"].items():
            for phase in ("arguments", "result", "preflight", "state"):
                reference = contract[phase]
                if reference is not None:
                    validators[(action, phase)] = schema_validators[reference["id"]]

        fingerprint_payload = {"manifest": manifest, "schemas": raw_schemas}
        fingerprint = hashlib.sha256(
            json.dumps(
                fingerprint_payload,
                allow_nan=False,
                ensure_ascii=False,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
        ).hexdigest()
        return manifest, validators, fingerprint

    def _compatibility(self, manifest: Mapping[str, Any]) -> tuple[str, str]:
        minimum = manifest["minFabricProtocol"]
        maximum = manifest["maxFabricProtocol"]
        if minimum <= self.protocol_version <= maximum:
            return "available", ""
        return (
            "incompatible",
            f"Provider supports Fabric protocols {minimum} through {maximum}; "
            f"the daemon runs {self.protocol_version}.",
        )

    @staticmethod
    def _validate_value(
        validator: Draft202012Validator,
        value: Any,
        *,
        provider_id: str,
        action: str,
        phase: str,
    ) -> None:
        try:
            error = next(iter(validator.iter_errors(value)), None)
        except Unresolvable as unresolved:
            raise FabricError(
                "provider.invalid-schemas",
                "Fabric provider schemas are invalid",
                "A provider schema reference cannot be resolved.",
                detail=f"{provider_id}.{action}.{phase}: {unresolved}",
            ) from unresolved
        if error is None:
            return
        code = {
            "arguments": "provider.invalid-arguments",
            "result": "provider.invalid-result",
            "preflight": "provider.invalid-preflight",
            "state": "provider.invalid-state",
        }.get(phase, "provider.invalid-value")
        raise FabricError(
            code,
            "Fabric provider value is invalid",
            f"The provider {phase} value does not match its typed contract.",
            detail=f"{provider_id}.{action}: {_validation_detail(error)}",
        )

    @staticmethod
    def _unavailable(provider_id: str, *, detail: str = "") -> FabricError:
        return FabricError(
            "provider.unavailable",
            "Fabric provider is unavailable",
            "The typed provider is not currently available.",
            detail=detail or provider_id,
            retryable=True,
            recovery_actions=("provider.retry",),
        )

    def _lifecycle_payload(self, record: _ProviderRecord, transition: str) -> dict[str, Any]:
        return {
            "provider": record.manifest["provider"],
            "providerVersion": record.manifest["providerVersion"],
            "generation": record.generation,
            "state": record.state,
            "transition": transition,
            "detail": record.detail,
            "fingerprint": record.fingerprint,
        }

    def _emit(self, topic: str, payload: Mapping[str, Any]) -> None:
        if self._event_sink is not None:
            self._event_sink(topic, payload)


def ensure_async_provider_hooks(provider: Any) -> None:
    """Static/testing aid for enforcing asynchronous provider boundaries."""

    for name in ("read", "preflight", "apply", "validate", "rollback"):
        hook = getattr(provider, name, None)
        if hook is not None and not inspect.iscoroutinefunction(hook):
            raise FabricError(
                "provider.invalid-adapter",
                "Fabric provider adapter is invalid",
                "Provider lifecycle hooks must be asynchronous.",
                detail=name,
            )
