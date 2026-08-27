"""Strict catalog, provenance, inventory, and adoption model."""

from __future__ import annotations

import json
import re
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import urlsplit

from jsonschema import Draft202012Validator, FormatChecker

from omarchy_fabric.models import FabricError

from .adapters import SOURCE_TYPES
from .identity import SHA256_RE, canonical_json, require_digest, require_stable_id, revision

MAX_CATALOG_BYTES = 2 * 1024 * 1024
TRUST_LEVELS = {"core", "signed", "reviewed", "sandboxed"}
PACKAGE_REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9@._+:-]*$")


def _https_url(value: object) -> bool:
    if not isinstance(value, str) or any(character.isspace() or ord(character) < 32 or ord(character) == 127 for character in value):
        return False
    try:
        parsed = urlsplit(value)
    except ValueError:
        return False
    return parsed.scheme == "https" and bool(parsed.hostname) and parsed.username is None and parsed.password is None


def _schema_path() -> Path:
    return Path(__file__).resolve().parents[3] / "schema" / "packages-catalog-v0.json"


class PackageCatalog:
    def __init__(self, document: Mapping[str, Any], *, schema_path: Path | None = None, verified_catalog_revisions: frozenset[str] = frozenset()) -> None:
        try:
            payload = canonical_json(document).encode("utf-8")
        except (TypeError, ValueError) as error:
            raise FabricError("packages.catalog-invalid", "Software catalog is invalid", "The catalog is not finite canonical JSON.", detail=type(error).__name__) from error
        if len(payload) > MAX_CATALOG_BYTES:
            raise FabricError("packages.catalog-too-large", "Software catalog is too large", "The catalog exceeds the bounded Software Center contract.")
        schema = json.loads((schema_path or _schema_path()).read_text(encoding="utf-8"))
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        error = next(iter(validator.iter_errors(document)), None)
        if error is not None:
            path = ".".join(str(part) for part in error.absolute_path)
            raise FabricError("packages.catalog-invalid", "Software catalog is invalid", "The catalog does not satisfy its closed schema.", detail=path or error.message)
        self.document = deepcopy(dict(document))
        self.entries = tuple(sorted((deepcopy(entry) for entry in document["entries"]), key=lambda entry: entry["id"]))
        self.by_id = {entry["id"]: entry for entry in self.entries}
        if len(self.by_id) != len(self.entries):
            raise FabricError("packages.catalog-invalid", "Software catalog is invalid", "Catalog IDs must be unique.")
        sources = {source["id"]: source for source in document["sources"]}
        if len(sources) != len(document["sources"]):
            raise FabricError("packages.catalog-invalid", "Software catalog is invalid", "Catalog source IDs must be unique.")
        self.assurance = document["assurance"]
        for entry in self.entries:
            self._validate_entry_trust(entry, sources, self.assurance)
        package_keys = {(entry["sourceType"], entry["packageRef"]) for entry in self.entries}
        if len(package_keys) != len(self.entries):
            raise FabricError("packages.catalog-invalid", "Software catalog is invalid", "A source package reference cannot map to multiple catalog entries.")
        declared = document["revision"]
        unsigned = deepcopy(dict(document))
        unsigned["revision"] = "sha256." + "0" * 64
        computed = revision(unsigned)
        if declared != computed:
            raise FabricError("packages.catalog-revision-invalid", "Software catalog revision is invalid", "The declared catalog revision does not match its canonical contents.", detail=f"declared={declared}; computed={computed}")
        if self.assurance == "release-verified" and declared not in verified_catalog_revisions:
            raise FabricError("packages.catalog-unattested", "Software catalog is not release-attested", "A document cannot self-assert release verification; its exact revision must be admitted by code-owned release metadata.")
        self.revision = declared

    @staticmethod
    def _validate_entry_trust(entry: Mapping[str, Any], sources: Mapping[str, Mapping[str, Any]], assurance: str) -> None:
        source = sources.get(entry["sourceId"])
        if source is None:
            raise FabricError("packages.provenance-invalid", "Software provenance is invalid", "A catalog entry names an unknown source.", detail=entry["id"])
        provenance = entry["provenance"]
        require_digest(provenance["artifactDigest"], "artifact digest")
        require_digest(provenance["reviewRevision"], "review revision")
        trust = provenance["trustLevel"]
        signature = provenance["signature"]
        source_type = entry["sourceType"]
        if trust not in TRUST_LEVELS or source_type not in SOURCE_TYPES:
            raise FabricError("packages.provenance-invalid", "Software provenance is invalid", "The source trust vocabulary is not recognized.", detail=entry["id"])
        if provenance["assurance"] != assurance:
            raise FabricError("packages.provenance-invalid", "Software provenance is invalid", "Entry assurance must exactly match its catalog assurance.", detail=entry["id"])
        required_status = "declared" if assurance == "contract-seed" else ("reviewed" if source_type == "reviewed-aur" else "verified")
        if signature["status"] != required_status or not signature["keyId"]:
            raise FabricError("packages.provenance-unverified", "Software provenance assurance is invalid", "The signature status must match the catalog assurance and source channel.", detail=entry["id"])
        if source_type == "reviewed-aur" and trust != "reviewed":
            raise FabricError("packages.provenance-unverified", "Software provenance is not reviewed", "AUR entries require an explicit reviewed snapshot.", detail=entry["id"])
        if source_type in {"appimage", "web-app"} and trust not in {"signed", "sandboxed"}:
            raise FabricError("packages.provenance-unverified", "Software provenance is not isolated", "Portable and web software must be signed or sandboxed.", detail=entry["id"])
        if source_type != source["type"] or trust != source["trustLevel"] or signature["keyId"] != source["signatureKeyId"]:
            raise FabricError("packages.provenance-invalid", "Software provenance is invalid", "Entry provenance must exactly match its declared catalog source.", detail=entry["id"])
        expected_trust = {"curated": {"core"}, "signed-repo": {"signed"}, "flatpak": {"signed"}, "reviewed-aur": {"reviewed"}, "appimage": {"signed", "sandboxed"}, "web-app": {"signed", "sandboxed"}}[source_type]
        package_ref = entry["packageRef"]
        if trust not in expected_trust or not _https_url(provenance["origin"]):
            raise FabricError("packages.provenance-invalid", "Software provenance is invalid", "Source trust and artifact origin must match the source channel policy.", detail=entry["id"])
        if source_type == "web-app":
            valid_reference = _https_url(package_ref)
        else:
            valid_reference = isinstance(package_ref, str) and PACKAGE_REF_RE.fullmatch(package_ref) is not None
        if not valid_reference:
            raise FabricError("packages.package-reference-invalid", "Software package reference is invalid", "Package references must use the closed channel-specific identifier form.", detail=entry["id"])

    @classmethod
    def load(cls, path: Path, *, verified_catalog_revisions: frozenset[str] = frozenset()) -> "PackageCatalog":
        with path.open("rb") as stream:
            raw = stream.read(MAX_CATALOG_BYTES + 1)
        if len(raw) > MAX_CATALOG_BYTES:
            raise FabricError("packages.catalog-too-large", "Software catalog is too large", "The catalog exceeds the bounded Software Center contract.")
        try:
            document = json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise FabricError("packages.catalog-corrupt", "Software catalog is corrupt", "The catalog cannot be decoded as UTF-8 JSON.", detail=type(error).__name__) from error
        if not isinstance(document, dict):
            raise FabricError("packages.catalog-invalid", "Software catalog is invalid", "The catalog root must be an object.")
        return cls(document, verified_catalog_revisions=verified_catalog_revisions)

    def search(self, query: str, source_types: list[str]) -> list[dict[str, Any]]:
        normalized = query.strip().casefold()
        allowed = set(source_types) if source_types else set(SOURCE_TYPES)
        if not allowed <= set(SOURCE_TYPES):
            raise FabricError("packages.query-invalid", "Software search is invalid", "The query names an unknown source type.")
        matches = []
        for entry in self.entries:
            haystack = " ".join((entry["id"], entry["displayName"], entry["summary"], *entry["keywords"])).casefold()
            if entry["sourceType"] in allowed and (not normalized or normalized in haystack):
                matches.append(deepcopy(entry))
        return matches

    def adoption(self, inventory: list[Mapping[str, Any]]) -> list[dict[str, Any]]:
        by_ref = {(entry["sourceType"], entry["packageRef"]): entry for entry in self.entries}
        output: list[dict[str, Any]] = []
        for installed in sorted(inventory, key=lambda item: item["id"]):
            match = by_ref.get((installed["sourceType"], installed["packageRef"]))
            if match is None:
                state, reason = "unmanaged", "No trusted catalog entry matches this installation."
            elif installed["artifactDigest"] != match["provenance"]["artifactDigest"]:
                state, reason = "conflict", "The installed artifact digest differs from the trusted catalog revision."
            elif installed["adopted"]:
                state, reason = "managed", "The installation is already managed by Software Center."
            else:
                state, reason = "adoptable", "The installed artifact exactly matches a trusted catalog entry."
            output.append({"installedId": installed["id"], "catalogId": match["id"] if match else None, "state": state, "reason": reason})
        return output


def catalog_revision(document: Mapping[str, Any]) -> str:
    normalized = deepcopy(dict(document))
    normalized["revision"] = "sha256." + "0" * 64
    return revision(normalized)
