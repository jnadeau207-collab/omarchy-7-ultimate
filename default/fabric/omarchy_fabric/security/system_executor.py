"""Fixed typed interface for the root-journaled system executor.

This module validates protocol requests only. It performs no privileged work and
does not treat the consent correlation nonce as authorization.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from types import MappingProxyType
from typing import Any, Callable, Mapping

from .errors import SecurityValidationError
from .normalize import normalize_json

_STABLE_TOKEN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,159}$")
_LOWER_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_PROHIBITED_FIELD = re.compile(r"(?:^|_)(?:command|cmd|shell|executable|binary|argv|env|path|directory|helper)(?:$|_)")

@dataclass(frozen=True)
class ActionContract:
    polkit_action: str
    required: frozenset[str]
    optional: frozenset[str]
    validators: Mapping[str, Callable[[Any], Any]]

def _stable(value: Any) -> str:
    if not isinstance(value, str) or not _STABLE_TOKEN.fullmatch(value) or "/" in value or "\\" in value:
        raise SecurityValidationError("executor.identifier", "Executor target identifiers must be opaque stable IDs.")
    return value

def _boolean(value: Any) -> bool:
    if not isinstance(value, bool):
        raise SecurityValidationError("executor.boolean", "Expected a boolean argument.")
    return value

def _integer(minimum: int, maximum: int) -> Callable[[Any], int]:
    def validate(value: Any) -> int:
        if not isinstance(value, int) or isinstance(value, bool) or not minimum <= value <= maximum:
            raise SecurityValidationError("executor.integer", f"Expected an integer from {minimum} through {maximum}.")
        return value

    return validate

def _choice(*choices: str) -> Callable[[Any], str]:
    allowed = frozenset(choices)

    def validate(value: Any) -> str:
        if not isinstance(value, str) or value not in allowed:
            raise SecurityValidationError("executor.choice", "Executor argument is not an allowed fixed value.")
        return str(value)

    return validate

def _package_ids(value: Any) -> tuple[str, ...]:
    if not isinstance(value, list) or not value or len(value) > 256:
        raise SecurityValidationError("executor.package-list", "Package IDs must be a non-empty bounded list.")
    normalized = tuple(_stable(item) for item in value)
    if len(set(normalized)) != len(normalized):
        raise SecurityValidationError("executor.package-list", "Package IDs must be unique.")
    return normalized

def _label(value: Any) -> str:
    if not isinstance(value, str) or len(value) > 64 or "\x00" in value or "\n" in value or "\r" in value:
        raise SecurityValidationError("executor.label", "Label is invalid.")
    return value

def _confirmation(value: Any) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= 160 or "\x00" in value:
        raise SecurityValidationError("executor.confirmation", "Explicit confirmation text is required.")
    return value

SYSTEM_ACTIONS: Mapping[str, ActionContract] = MappingProxyType(
    {
        "packages.install": ActionContract(
            "org.omarchy.fabric.packages.install",
            frozenset({"package_ids"}),
            frozenset(),
            {"package_ids": _package_ids},
        ),
        "packages.remove": ActionContract(
            "org.omarchy.fabric.packages.remove",
            frozenset({"package_ids", "preserve_data"}),
            frozenset(),
            {"package_ids": _package_ids, "preserve_data": _boolean},
        ),
        "system.update": ActionContract(
            "org.omarchy.fabric.system.update",
            frozenset({"channel", "allow_without_restore_point"}),
            frozenset(),
            {
                "channel": _choice("stable", "candidate"),
                "allow_without_restore_point": _boolean,
            },
        ),
        "storage.format": ActionContract(
            "org.omarchy.fabric.storage.format",
            frozenset({"device_id", "filesystem", "label", "confirmation"}),
            frozenset(),
            {
                "device_id": _stable,
                "filesystem": _choice("btrfs", "ext4", "exfat", "fat32", "ntfs"),
                "label": _label,
                "confirmation": _confirmation,
            },
        ),
        "account.delete": ActionContract(
            "org.omarchy.fabric.account.delete",
            frozenset({"account_uid", "home_disposition", "confirmation"}),
            frozenset({"archive_id"}),
            {
                "account_uid": _integer(1, 2**31 - 1),
                "home_disposition": _choice("preserve", "archive", "delete"),
                "archive_id": _stable,
                "confirmation": _confirmation,
            },
        ),
        "firewall.apply": ActionContract(
            "org.omarchy.fabric.firewall.apply",
            frozenset({"profile_id", "rollback_seconds"}),
            frozenset({"keep_connection_id"}),
            {
                "profile_id": _stable,
                "rollback_seconds": _integer(30, 600),
                "keep_connection_id": _stable,
            },
        ),
        "firmware.update": ActionContract(
            "org.omarchy.fabric.firmware.update",
            frozenset({"device_id", "release_id"}),
            frozenset(),
            {"device_id": _stable, "release_id": _stable},
        ),
        "recovery.restore": ActionContract(
            "org.omarchy.fabric.recovery.restore",
            frozenset({"restore_point_id", "confirmation"}),
            frozenset(),
            {"restore_point_id": _stable, "confirmation": _confirmation},
        ),
        "system.factory-reset": ActionContract(
            "org.omarchy.fabric.system.factory-reset",
            frozenset({"baseline_id", "scope", "confirmation"}),
            frozenset(),
            {
                "baseline_id": _stable,
                "scope": _choice("system", "system-and-user-data"),
                "confirmation": _confirmation,
            },
        ),
        "device.authorize": ActionContract(
            "org.omarchy.fabric.device.authorize",
            frozenset({"device_id", "authorized"}),
            frozenset(),
            {"device_id": _stable, "authorized": _boolean},
        ),
    }
)

@dataclass(frozen=True)
class SystemExecutorRequest:
    request_id: str
    operation_id: str
    action: str
    polkit_action: str
    arguments: Mapping[str, Any]
    provider_version: str
    state_revision: str
    approval_binding: str
    consent_nonce: str

def validate_system_executor_request(document: Mapping[str, Any]) -> SystemExecutorRequest:
    """Validate a request without granting authorization.

    ``consentNonce`` correlates the user-Fabric consent record with root audit. The
    system executor must still perform its own state validation and Polkit check.
    """

    if not isinstance(document, Mapping):
        raise SecurityValidationError("executor.request", "Executor request must be an object.")
    required = {
        "schemaVersion",
        "requestId",
        "operationId",
        "action",
        "arguments",
        "providerVersion",
        "stateRevision",
        "approvalBinding",
        "consentNonce",
    }
    keys = set(document)
    if keys != required:
        raise SecurityValidationError("executor.fields", "Executor request fields do not match the fixed protocol.")
    if document["schemaVersion"] != "v0":
        raise SecurityValidationError("executor.version", "Unsupported system-executor request version.")
    action = document["action"]
    if not isinstance(action, str) or action not in SYSTEM_ACTIONS:
        raise SecurityValidationError("executor.action", "System executor action is not a fixed supported verb.")
    contract = SYSTEM_ACTIONS[action]
    arguments = document["arguments"]
    if not isinstance(arguments, Mapping):
        raise SecurityValidationError("executor.arguments", "Executor arguments must be an object.")
    argument_keys = set(arguments)
    if any(_PROHIBITED_FIELD.search(str(key)) for key in argument_keys):
        raise SecurityValidationError("executor.arbitrary-execution", "Commands, paths, executables, argv, and env are forbidden.")
    if not contract.required.issubset(argument_keys) or not argument_keys.issubset(
        contract.required | contract.optional
    ):
        raise SecurityValidationError("executor.argument-fields", "Arguments do not match the action's fixed contract.")
    normalized_arguments = {
        key: contract.validators[key](arguments[key])
        for key in sorted(argument_keys)
    }
    for identifier in ("requestId", "operationId"):
        if not isinstance(document[identifier], str) or not _LOWER_UUID.fullmatch(document[identifier]):
            raise SecurityValidationError("executor.uuid", f"{identifier} must be a lowercase UUID.")
    for field in ("providerVersion", "stateRevision"):
        value = document[field]
        if not isinstance(value, str) or not 1 <= len(value) <= 256 or "\x00" in value:
            raise SecurityValidationError("executor.binding-field", f"{field} is invalid.")
    if not isinstance(document["approvalBinding"], str) or not _DIGEST.fullmatch(document["approvalBinding"]):
        raise SecurityValidationError("executor.approval-binding", "Approval binding must be a SHA-256 digest.")
    if not isinstance(document["consentNonce"], str) or not _LOWER_UUID.fullmatch(document["consentNonce"]):
        raise SecurityValidationError("executor.nonce", "Consent correlation nonce must be a lowercase UUID.")
    return SystemExecutorRequest(
        request_id=document["requestId"],
        operation_id=document["operationId"],
        action=action,
        polkit_action=contract.polkit_action,
        arguments=MappingProxyType(normalize_json(normalized_arguments)),
        provider_version=document["providerVersion"],
        state_revision=document["stateRevision"],
        approval_binding=document["approvalBinding"],
        consent_nonce=document["consentNonce"],
    )
