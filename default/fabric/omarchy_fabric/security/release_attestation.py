"""Code-owned admission of exact release-verified document revisions.

A catalog or recipe document cannot self-assert release verification. Its
canonical revision must appear in this metadata before PackageCatalog or
RecipeCatalog will accept ``assurance: release-verified``.
"""

from __future__ import annotations

import json
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from .errors import SecurityValidationError

MAX_ATTESTATION_BYTES = 64 * 1024
ATTESTATION_KINDS = frozenset({"packages-catalog", "compatibility-recipes"})
REVISION_PREFIX = "sha256."


def _schema_path() -> Path:
    return Path(__file__).resolve().parents[2] / "schema" / "security-release-attestation-v0.json"


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON constant: {value}")


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    document: dict[str, Any] = {}
    for key, value in pairs:
        if key in document:
            raise ValueError("duplicate JSON object key")
        document[key] = value
    return document


@dataclass(frozen=True)
class ReleaseAttestation:
    attestation_id: str
    revisions_by_kind: Mapping[str, frozenset[str]]

    def admitted_revisions(self, kind: str) -> frozenset[str]:
        if kind not in ATTESTATION_KINDS:
            raise SecurityValidationError(
                "release-attestation.kind",
                "Release attestation kind is not recognized.",
            )
        return self.revisions_by_kind.get(kind, frozenset())


def _load_json_object(raw: bytes, *, label: str) -> dict[str, Any]:
    if len(raw) > MAX_ATTESTATION_BYTES:
        raise SecurityValidationError(
            "release-attestation.too-large",
            "Release attestation metadata exceeds its bounded contract.",
        )
    try:
        document = json.loads(
            raw,
            object_pairs_hook=_reject_duplicate_pairs,
            parse_constant=_reject_json_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise SecurityValidationError(
            "release-attestation.invalid",
            f"{label} is not finite UTF-8 JSON.",
        ) from error
    if not isinstance(document, dict):
        raise SecurityValidationError(
            "release-attestation.invalid",
            f"{label} must be a JSON object.",
        )
    return document


def _attestation_validator(schema: Mapping[str, Any]) -> Draft202012Validator:
    common_path = _schema_path().with_name("common-v0.json")
    try:
        with common_path.open("rb") as stream:
            common = _load_json_object(stream.read(MAX_ATTESTATION_BYTES + 1), label="Common schema")
    except OSError as error:
        raise SecurityValidationError(
            "release-attestation.unavailable",
            "Code-owned common schema could not be opened.",
        ) from error
    document = dict(schema)
    resources = Registry().with_resources(
        (
            (common["$id"], Resource.from_contents(common)),
            ("common-v0.json", Resource.from_contents(common)),
            (document.get("$id", "security-release-attestation-v0.json"), Resource.from_contents(document)),
        )
    )
    return Draft202012Validator(document, registry=resources)


def parse_release_attestation(
    document: Mapping[str, Any],
    *,
    schema: Mapping[str, Any] | None = None,
    schema_path: Path | None = None,
) -> ReleaseAttestation:
    if schema is None:
        try:
            with (schema_path or _schema_path()).open("rb") as stream:
                schema = _load_json_object(stream.read(MAX_ATTESTATION_BYTES + 1), label="Release attestation schema")
        except OSError as error:
            raise SecurityValidationError(
                "release-attestation.unavailable",
                "Code-owned release attestation schema could not be opened.",
            ) from error
    if not isinstance(document, Mapping) or not isinstance(schema, Mapping):
        raise SecurityValidationError(
            "release-attestation.invalid",
            "Release attestation metadata and schema must be objects.",
        )
    payload = deepcopy(dict(document))
    validation_error = next(iter(_attestation_validator(schema).iter_errors(payload)), None)
    if validation_error is not None:
        raise SecurityValidationError(
            "release-attestation.invalid",
            "Release attestation metadata does not match its closed schema.",
        )
    seen: set[tuple[str, str]] = set()
    grouped: dict[str, set[str]] = {kind: set() for kind in ATTESTATION_KINDS}
    for entry in payload["admittedRevisions"]:
        key = (entry["kind"], entry["revision"])
        if key in seen or not entry["revision"].startswith(REVISION_PREFIX):
            raise SecurityValidationError(
                "release-attestation.duplicate",
                "Each admitted revision may appear once per document kind.",
            )
        seen.add(key)
        grouped[entry["kind"]].add(entry["revision"])
    return ReleaseAttestation(
        attestation_id=payload["attestationId"],
        revisions_by_kind=MappingProxyType({kind: frozenset(values) for kind, values in grouped.items()}),
    )


def load_release_attestation(path: Path, *, schema_path: Path | None = None) -> ReleaseAttestation:
    try:
        with path.open("rb") as stream:
            raw = stream.read(MAX_ATTESTATION_BYTES + 1)
    except OSError as error:
        raise SecurityValidationError(
            "release-attestation.unavailable",
            "Code-owned release attestation metadata could not be opened.",
        ) from error
    return parse_release_attestation(
        _load_json_object(raw, label="Release attestation metadata"),
        schema_path=schema_path,
    )


def default_release_attestation(root: Path) -> ReleaseAttestation:
    return load_release_attestation(root / "ultimate" / "release-attestation-v0.json")
