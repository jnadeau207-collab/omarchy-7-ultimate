"""Closed Draft 2020-12 package provider contracts."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

DIALECT = "https://json-schema.org/draft/2020-12/schema"
VERSION = "v0"
REVISION = r"^sha256\.[0-9a-f]{64}$"
STABLE = r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$"
DIGEST = r"^sha256:[0-9a-f]{64}$"
SOURCE_TYPES = ["curated", "signed-repo", "flatpak", "reviewed-aur", "appimage", "web-app"]

def _doc(name: str, properties: dict[str, Any], required: list[str]) -> dict[str, Any]:
    return {
        "$schema": DIALECT,
        "$id": f"urn:omarchy:fabric:provider:packages:{name}:v0",
        "x-omarchy-version": VERSION,
        "type": "object",
        "required": required,
        "properties": properties,
        "additionalProperties": False,
    }

def ref(name: str) -> dict[str, str]:
    return {"id": f"urn:omarchy:fabric:provider:packages:{name}:v0", "version": VERSION}

PROVENANCE = {
    "type": "object",
    "required": ["assurance", "publisher", "origin", "artifactDigest", "reviewRevision", "trustLevel", "signature"],
    "properties": {
        "assurance": {"type": "string", "enum": ["contract-seed", "release-verified"]},
        "publisher": {"type": "string", "minLength": 1, "maxLength": 160},
        "origin": {"type": "string", "pattern": "^https://", "minLength": 1, "maxLength": 500},
        "artifactDigest": {"type": "string", "pattern": DIGEST},
        "reviewRevision": {"type": "string", "pattern": DIGEST},
        "trustLevel": {"type": "string", "enum": ["core", "signed", "reviewed", "sandboxed"]},
        "signature": {
            "type": "object", "required": ["status", "keyId"],
            "properties": {"status": {"type": "string", "enum": ["declared", "verified", "reviewed", "not-applicable"]}, "keyId": {"type": ["string", "null"], "pattern": STABLE, "maxLength": 160}},
            "additionalProperties": False,
        },
    },
    "additionalProperties": False,
}
ENTRY = {
    "type": "object",
    "required": ["id", "sourceId", "sourceType", "packageRef", "displayName", "summary", "version", "architecture", "keywords", "provenance", "install"],
    "properties": {
        "id": {"type": "string", "pattern": STABLE, "maxLength": 160},
        "sourceId": {"type": "string", "pattern": STABLE, "maxLength": 160},
        "sourceType": {"type": "string", "enum": SOURCE_TYPES},
        "packageRef": {"type": "string", "minLength": 1, "maxLength": 300},
        "displayName": {"type": "string", "minLength": 1, "maxLength": 160},
        "summary": {"type": "string", "minLength": 1, "maxLength": 500},
        "version": {"type": "string", "minLength": 1, "maxLength": 100},
        "architecture": {"type": "string", "enum": ["any", "x86_64", "aarch64"]},
        "keywords": {"type": "array", "maxItems": 20, "uniqueItems": True, "items": {"type": "string", "minLength": 1, "maxLength": 80}},
        "provenance": deepcopy(PROVENANCE),
        "install": {
            "type": "object", "required": ["requiredBytes", "permissions", "conflicts"],
            "properties": {
                "requiredBytes": {"type": "integer", "minimum": 0, "maximum": 1099511627776},
                "permissions": {"type": "array", "maxItems": 32, "uniqueItems": True, "items": {"type": "string", "enum": ["network", "audio", "camera", "microphone", "notifications", "filesystem-home", "filesystem-removable", "devices", "session"]}},
                "conflicts": {"type": "array", "maxItems": 32, "uniqueItems": True, "items": {"type": "string", "pattern": STABLE, "maxLength": 160}},
            }, "additionalProperties": False,
        },
    },
    "additionalProperties": False,
}
ITEM = {
    "type": "object",
    "required": ["id", "catalogId", "sourceType", "packageRef", "installedVersion", "artifactDigest", "adopted", "state", "configPaths", "dataPaths"],
    "properties": {
        "id": {"type": "string", "pattern": STABLE, "maxLength": 160}, "catalogId": {"type": "string", "pattern": STABLE, "maxLength": 160},
        "sourceType": {"type": "string", "enum": SOURCE_TYPES}, "packageRef": {"type": "string", "minLength": 1, "maxLength": 300}, "installedVersion": {"type": "string", "minLength": 1, "maxLength": 100},
        "artifactDigest": {"type": "string", "pattern": DIGEST}, "adopted": {"type": "boolean"}, "state": {"type": "string", "enum": ["installed", "partial", "broken", "foreign"]},
        "configPaths": {"type": "array", "maxItems": 64, "uniqueItems": True, "items": {"type": "string", "pattern": "^/[^\\u0000]{0,499}$"}},
        "dataPaths": {"type": "array", "maxItems": 64, "uniqueItems": True, "items": {"type": "string", "pattern": "^/[^\\u0000]{0,499}$"}},
    }, "additionalProperties": False,
}
OP_STATE = {
    "type": "object", "required": ["operationId", "revision", "status", "inventoryRevision", "targetState"],
    "properties": {
        "operationId": {"type": "string", "pattern": STABLE, "maxLength": 160}, "revision": {"type": "string", "pattern": REVISION},
        "status": {"type": "string", "enum": ["running", "succeeded", "failed", "cancelled", "needs-reconcile", "rolled-back"]},
        "inventoryRevision": {"type": "string", "pattern": REVISION}, "targetState": {"type": "string", "enum": ["installed", "absent"]},
    }, "additionalProperties": False,
}
CHECKPOINT_ARRAY = {
    "type": "array",
    "maxItems": 5,
    "prefixItems": [{"const": value} for value in ["verify-provenance", "stage-payload", "apply", "validate", "commit"]],
    "items": False,
}
OP_RECORD = {
    "type": "object", "required": ["operationId", "requestId", "action", "status", "checkpoints", "inventoryRevision", "revision", "error"],
    "properties": {
        "operationId": {"type": "string", "pattern": STABLE}, "requestId": {"type": "string", "pattern": STABLE}, "action": {"type": "string", "enum": ["install", "remove", "adopt", "recover"]},
        "status": {"type": "string", "enum": ["running", "succeeded", "failed", "cancelled", "needs-reconcile", "rolled-back"]}, "checkpoints": deepcopy(CHECKPOINT_ARRAY),
        "inventoryRevision": {"type": "string", "pattern": REVISION}, "revision": {"type": "string", "pattern": REVISION}, "error": {"type": ["string", "null"], "maxLength": 1000},
    }, "additionalProperties": False,
}
OP_ARGS = {
    "requestId": {"type": "string", "pattern": STABLE, "maxLength": 160}, "appId": {"type": "string", "pattern": STABLE, "maxLength": 160},
    "catalogRevision": {"type": "string", "pattern": REVISION}, "expectedInventoryRevision": {"type": "string", "pattern": REVISION}, "preserveUserData": {"type": "boolean"},
}

CONTRACTS: dict[str, dict[str, Any]] = {}
for document in (
    _doc("catalog-search-arguments", {"query": {"type": "string", "maxLength": 120}, "sourceTypes": {"type": "array", "maxItems": 6, "uniqueItems": True, "items": {"type": "string", "enum": SOURCE_TYPES}}}, ["query", "sourceTypes"]),
    _doc("catalog-search-result", {"schemaVersion": {"const": VERSION}, "provider": {"const": "packages.provider"}, "assurance": {"type": "string", "enum": ["contract-seed", "release-verified"]}, "revision": {"type": "string", "pattern": REVISION}, "entries": {"type": "array", "maxItems": 4096, "items": deepcopy(ENTRY)}}, ["schemaVersion", "provider", "assurance", "revision", "entries"]),
    _doc("inventory-arguments", {"includeUnmanaged": {"type": "boolean"}}, ["includeUnmanaged"]),
    _doc("inventory-result", {"schemaVersion": {"const": VERSION}, "provider": {"const": "packages.provider"}, "revision": {"type": "string", "pattern": REVISION}, "items": {"type": "array", "maxItems": 4096, "items": deepcopy(ITEM)}}, ["schemaVersion", "provider", "revision", "items"]),
    _doc("empty-arguments", {}, []),
    _doc("adoption-result", {"schemaVersion": {"const": VERSION}, "provider": {"const": "packages.provider"}, "revision": {"type": "string", "pattern": REVISION}, "items": {"type": "array", "maxItems": 4096, "items": {"type": "object", "required": ["installedId", "catalogId", "state", "reason"], "properties": {"installedId": {"type": "string", "pattern": STABLE}, "catalogId": {"type": ["string", "null"], "pattern": STABLE}, "state": {"type": "string", "enum": ["managed", "unmanaged", "adoptable", "conflict"]}, "reason": {"type": "string", "minLength": 1, "maxLength": 500}}, "additionalProperties": False}}}, ["schemaVersion", "provider", "revision", "items"]),
    _doc("operations-result", {"schemaVersion": {"const": VERSION}, "provider": {"const": "packages.provider"}, "revision": {"type": "string", "pattern": REVISION}, "operations": {"type": "array", "maxItems": 4096, "items": deepcopy(OP_RECORD)}}, ["schemaVersion", "provider", "revision", "operations"]),
    _doc("operation-arguments", deepcopy(OP_ARGS), list(OP_ARGS)),
    _doc("operation-state", deepcopy(OP_STATE["properties"]), list(OP_STATE["required"])),
    _doc("operation-result", {
        "schemaVersion": {"const": VERSION}, "provider": {"const": "packages.provider"}, "providerVersion": {"const": VERSION}, "action": {"type": "string", "enum": ["install", "remove", "adopt", "recover"]},
        "operationId": {"type": "string", "pattern": STABLE}, "status": OP_STATE["properties"]["status"], "changed": {"type": "boolean"}, "changeState": {"type": "string", "enum": ["none", "complete", "unknown"]},
        "checkpoints": deepcopy(OP_RECORD["properties"]["checkpoints"]), "inventoryRevision": {"type": "string", "pattern": REVISION}, "state": deepcopy(OP_STATE), "error": {"type": ["string", "null"], "maxLength": 1000},
    }, ["schemaVersion", "provider", "providerVersion", "action", "operationId", "status", "changed", "changeState", "checkpoints", "inventoryRevision", "state", "error"]),
):
    CONTRACTS[document["$id"]] = document

PREFLIGHT_PROPERTIES = {
    "schemaVersion": {"const": VERSION}, "provider": {"const": "packages.provider"}, "providerVersion": {"const": VERSION}, "action": {"type": "string", "enum": ["install", "remove", "adopt", "recover"]},
    "operationId": {"type": "string", "pattern": STABLE}, "resource": {"type": "object", "required": ["kind", "id"], "properties": {"kind": {"const": "software"}, "id": {"type": "string", "pattern": STABLE}}, "additionalProperties": False},
    "normalizedArguments": {"type": "object", "required": list(OP_ARGS), "properties": deepcopy(OP_ARGS), "additionalProperties": False},
    "catalogRevision": {"type": "string", "pattern": REVISION}, "inventoryRevision": {"type": "string", "pattern": REVISION}, "changed": {"type": "boolean"}, "summary": {"type": "string", "minLength": 1, "maxLength": 500},
    "risk": {"type": "string", "enum": ["consequential", "destructive"]}, "effects": {"type": "array", "minItems": 1, "maxItems": 2, "uniqueItems": True, "items": {"type": "string", "enum": ["mutating", "download", "destructive"]}},
    "provenance": deepcopy(PROVENANCE), "steps": {"type": "array", "minItems": 5, "maxItems": 5, "items": {"type": "object", "required": ["id", "ordinal", "mutationBoundary"], "properties": {"id": {"type": "string", "enum": ["verify-provenance", "stage-payload", "apply", "validate", "commit"]}, "ordinal": {"type": "integer", "minimum": 1, "maximum": 5}, "mutationBoundary": {"type": "boolean"}}, "additionalProperties": False}},
    "adapter": {"type": "object", "required": ["adapterId", "executable", "argv", "inputDigestOnly"], "properties": {"adapterId": {"type": "string", "pattern": STABLE}, "executable": {"type": "string", "pattern": "^/", "maxLength": 300}, "argv": {"type": "array", "maxItems": 12, "items": {"type": "string", "maxLength": 100}}, "inputDigestOnly": {"const": True}}, "additionalProperties": False},
    "recovery": {"type": "object", "required": ["mode", "priorItem", "preserveUserData", "dataDisposition"], "properties": {"mode": {"const": "restore-prior-item"}, "priorItem": {"oneOf": [deepcopy(ITEM), {"type": "null"}]}, "preserveUserData": {"type": "boolean"}, "dataDisposition": {"type": "object", "required": ["preserve", "delete"], "properties": {"preserve": {"type": "array", "maxItems": 128, "uniqueItems": True, "items": {"type": "string", "pattern": "^/[^\\u0000]{0,499}$"}}, "delete": {"type": "array", "maxItems": 128, "uniqueItems": True, "items": {"type": "string", "pattern": "^/[^\\u0000]{0,499}$"}}}, "additionalProperties": False}}, "additionalProperties": False},
    "planRevision": {"type": "string", "pattern": REVISION},
}
preflight = _doc("operation-preflight", PREFLIGHT_PROPERTIES, list(PREFLIGHT_PROPERTIES))
CONTRACTS[preflight["$id"]] = preflight
