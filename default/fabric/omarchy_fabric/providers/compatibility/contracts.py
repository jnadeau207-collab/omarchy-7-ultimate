"""Closed Draft 2020-12 Compatibility Center provider contracts."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

DIALECT = "https://json-schema.org/draft/2020-12/schema"
VERSION = "v0"
STABLE = r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$"
REVISION = r"^sha256\.[0-9a-f]{64}$"
DIGEST = r"^sha256:[0-9a-f]{64}$"
ROUTES = ["native", "pwa", "known-good-recipe", "game-proton", "isolated-app", "vm"]
PERMISSIONS = ["network", "audio", "camera", "microphone", "notifications", "filesystem-home", "filesystem-removable", "devices", "session"]


def _doc(name: str, properties: dict[str, Any], required: list[str]) -> dict[str, Any]:
    return {"$schema": DIALECT, "$id": f"urn:omarchy:fabric:provider:compatibility:{name}:v0", "x-omarchy-version": VERSION, "type": "object", "required": required, "properties": properties, "additionalProperties": False}


REQUEST = {
    "type": "object", "required": ["id", "name", "workloadType", "architecture", "artifact", "permissions", "constraints"],
    "properties": {
        "id": {"type": "string", "pattern": STABLE, "maxLength": 160}, "name": {"type": "string", "minLength": 1, "maxLength": 160},
        "workloadType": {"type": "string", "enum": ["desktop", "web", "windows-game", "windows-app", "portable"]}, "architecture": {"type": "string", "enum": ["any", "x86_64", "aarch64"]},
        "artifact": {
            "type": "object", "required": ["kind", "origin", "digest"],
            "properties": {"kind": {"type": "string", "enum": ["native-package", "web-url", "windows-executable", "portable", "none"]}, "origin": {"type": ["string", "null"], "pattern": "^https://", "maxLength": 500}, "digest": {"type": ["string", "null"], "pattern": DIGEST}},
            "allOf": [
                {"if": {"properties": {"kind": {"enum": ["native-package", "windows-executable", "portable"]}}}, "then": {"properties": {"origin": {"type": "string", "minLength": 1, "maxLength": 500}, "digest": {"type": "string", "pattern": DIGEST}}}},
                {"if": {"properties": {"kind": {"const": "web-url"}}}, "then": {"properties": {"origin": {"type": "string", "minLength": 1, "maxLength": 500}, "digest": {"type": ["string", "null"], "pattern": DIGEST}}}},
                {"if": {"properties": {"kind": {"const": "none"}}}, "then": {"properties": {"origin": {"type": "null"}, "digest": {"type": "null"}}}},
            ],
            "additionalProperties": False,
        },
        "permissions": {"type": "array", "maxItems": 16, "uniqueItems": True, "items": {"type": "string", "enum": PERMISSIONS}},
        "constraints": {"type": "object", "required": ["requiresKernelDriver", "requiresAdmin", "antiCheat", "offlineRequired", "acceptsBrowser"], "properties": {"requiresKernelDriver": {"type": "boolean"}, "requiresAdmin": {"type": "boolean"}, "antiCheat": {"type": "string", "enum": ["none", "supported", "blocked", "unknown"]}, "offlineRequired": {"type": "boolean"}, "acceptsBrowser": {"type": "boolean"}}, "additionalProperties": False},
    }, "additionalProperties": False,
}
HOST = {
    "type": "object", "required": ["architecture", "virtualizationAvailable", "protonAvailable", "isolationAvailable", "browserAvailable", "availableRuntimes", "memoryMiB", "diskMiB"],
    "properties": {
        "architecture": {"type": "string", "enum": ["x86_64", "aarch64"]}, "virtualizationAvailable": {"type": "boolean"}, "protonAvailable": {"type": "boolean"}, "isolationAvailable": {"type": "boolean"}, "browserAvailable": {"type": "boolean"},
        "availableRuntimes": {"type": "array", "maxItems": 5, "uniqueItems": True, "items": {"type": "string", "enum": ["wine", "proton", "container", "browser", "native"]}},
        "memoryMiB": {"type": "integer", "minimum": 128, "maximum": 262144}, "diskMiB": {"type": "integer", "minimum": 1, "maximum": 1048576},
    },
    "additionalProperties": False,
}
CONSIDERED = {"type": "object", "required": ["route", "status", "reason"], "properties": {"route": {"type": "string", "enum": ROUTES}, "status": {"type": "string", "enum": ["eligible", "ineligible"]}, "reason": {"type": "string", "minLength": 1, "maxLength": 500}}, "additionalProperties": False}
CONSIDERED_ARRAY = {"type": "array", "minItems": 6, "maxItems": 6, "prefixItems": [{**deepcopy(CONSIDERED), "properties": {**deepcopy(CONSIDERED["properties"]), "route": {"const": route}}} for route in ROUTES], "items": False}
CHECKPOINT_ARRAY = {"type": "array", "maxItems": 5, "prefixItems": [{"const": value} for value in ["verify-route", "prepare", "apply", "validate", "commit"]], "items": False}
DECISION_PROPERTIES = {
    "schemaVersion": {"const": VERSION}, "provider": {"const": "compatibility.provider"}, "decisionId": {"type": "string", "pattern": STABLE, "maxLength": 160}, "recipeRevision": {"type": "string", "pattern": REVISION}, "recipeAssurance": {"type": "string", "enum": ["contract-seed", "release-verified"]},
    "eligibility": {"type": "string", "enum": ["supported", "unsupported"]}, "selectedRoute": {"type": ["string", "null"], "enum": [*ROUTES, None]}, "recipeId": {"type": ["string", "null"], "pattern": STABLE, "maxLength": 160},
    "reasonCode": {"type": "string", "pattern": STABLE, "maxLength": 160}, "explanation": {"type": "string", "minLength": 1, "maxLength": 1000}, "requiredPermissions": {"type": "array", "maxItems": 16, "uniqueItems": True, "items": {"type": "string", "enum": PERMISSIONS}},
    "considered": deepcopy(CONSIDERED_ARRAY), "revision": {"type": "string", "pattern": REVISION},
}
DECISION = {"type": "object", "required": list(DECISION_PROPERTIES), "properties": deepcopy(DECISION_PROPERTIES), "additionalProperties": False}
DEPLOYMENT = {
    "type": "object", "required": ["id", "workloadId", "displayName", "decisionId", "decisionRevision", "route", "recipeId", "state", "permissions", "dataArtifacts"],
    "properties": {"id": {"type": "string", "pattern": STABLE, "maxLength": 160}, "workloadId": {"type": "string", "pattern": STABLE, "maxLength": 160}, "displayName": {"type": "string", "minLength": 1, "maxLength": 160}, "decisionId": {"type": "string", "pattern": STABLE, "maxLength": 160}, "decisionRevision": {"type": "string", "pattern": REVISION}, "route": {"type": "string", "enum": ROUTES}, "recipeId": {"type": ["string", "null"], "pattern": STABLE, "maxLength": 160}, "state": {"type": "string", "enum": ["installed", "partial", "broken"]}, "permissions": {"type": "array", "maxItems": 16, "uniqueItems": True, "items": {"type": "string", "enum": PERMISSIONS}}, "dataArtifacts": {"type": "array", "maxItems": 64, "uniqueItems": True, "items": {"type": "string", "pattern": STABLE, "maxLength": 160}}},
    "additionalProperties": False,
}
OP_ARGS = {"requestId": {"type": "string", "pattern": STABLE, "maxLength": 160}, "request": deepcopy(REQUEST), "host": deepcopy(HOST), "recipeRevision": {"type": "string", "pattern": REVISION}, "expectedDeploymentRevision": {"type": "string", "pattern": REVISION}, "preserveData": {"type": "boolean"}}
STATE = {
    "type": "object", "required": ["operationId", "revision", "status", "deploymentRevision", "targetState"],
    "properties": {"operationId": {"type": "string", "pattern": STABLE, "maxLength": 160}, "revision": {"type": "string", "pattern": REVISION}, "status": {"type": "string", "enum": ["running", "succeeded", "failed", "cancelled", "needs-reconcile", "rolled-back"]}, "deploymentRevision": {"type": "string", "pattern": REVISION}, "targetState": {"type": "string", "enum": ["installed", "absent", "exported"]}},
    "additionalProperties": False,
}

CONTRACTS: dict[str, dict[str, Any]] = {}
documents = [
    _doc("route-arguments", {"request": deepcopy(REQUEST), "host": deepcopy(HOST)}, ["request", "host"]),
    _doc("route-result", deepcopy(DECISION_PROPERTIES), list(DECISION_PROPERTIES)),
    _doc("empty-arguments", {}, []),
    _doc("deployments-result", {"schemaVersion": {"const": VERSION}, "provider": {"const": "compatibility.provider"}, "revision": {"type": "string", "pattern": REVISION}, "deployments": {"type": "array", "maxItems": 2048, "items": deepcopy(DEPLOYMENT)}}, ["schemaVersion", "provider", "revision", "deployments"]),
    _doc("operation-arguments", deepcopy(OP_ARGS), list(OP_ARGS)),
    _doc("operation-state", deepcopy(STATE["properties"]), list(STATE["required"])),
]
for document in documents:
    CONTRACTS[document["$id"]] = document

PREFLIGHT_PROPERTIES = {
    "schemaVersion": {"const": VERSION}, "provider": {"const": "compatibility.provider"}, "providerVersion": {"const": VERSION}, "action": {"type": "string", "enum": ["deploy", "remove", "export"]},
    "operationId": {"type": "string", "pattern": STABLE, "maxLength": 160}, "normalizedArguments": {"type": "object", "required": list(OP_ARGS), "properties": deepcopy(OP_ARGS), "additionalProperties": False},
    "decision": deepcopy(DECISION), "deploymentRevision": {"type": "string", "pattern": REVISION}, "changed": {"type": "boolean"}, "summary": {"type": "string", "minLength": 1, "maxLength": 500},
    "risk": {"type": "string", "enum": ["low", "consequential", "destructive"]}, "effects": {"type": "array", "minItems": 1, "maxItems": 2, "uniqueItems": True, "items": {"type": "string", "enum": ["mutating", "download", "destructive"]}},
    "adapter": {"type": "object", "required": ["adapterId", "executable", "argv", "inputDigestOnly"], "properties": {"adapterId": {"type": "string", "pattern": STABLE}, "executable": {"type": "string", "pattern": "^/", "maxLength": 300}, "argv": {"type": "array", "maxItems": 12, "items": {"type": "string", "maxLength": 100}}, "inputDigestOnly": {"const": True}}, "additionalProperties": False},
    "lifecycle": {"type": "object", "required": ["checkpoints", "permissions"], "properties": {"checkpoints": {"type": "array", "minItems": 5, "maxItems": 5, "items": {"type": "string", "enum": ["verify-route", "prepare", "apply", "validate", "commit"]}}, "permissions": {"type": "array", "maxItems": 16, "uniqueItems": True, "items": {"type": "string", "enum": PERMISSIONS}}}, "additionalProperties": False},
    "recovery": {"type": "object", "required": ["priorDeployment", "preserveData", "removalPlan", "exportArtifact"], "properties": {"priorDeployment": {"oneOf": [deepcopy(DEPLOYMENT), {"type": "null"}]}, "preserveData": {"type": "boolean"}, "removalPlan": {"type": "object", "required": ["preserve", "delete"], "properties": {"preserve": {"type": "array", "maxItems": 64, "uniqueItems": True, "items": {"type": "string", "pattern": STABLE}}, "delete": {"type": "array", "maxItems": 64, "uniqueItems": True, "items": {"type": "string", "pattern": STABLE}}}, "additionalProperties": False}, "exportArtifact": {"oneOf": [{"type": "object", "required": ["id", "format", "contentRevision"], "properties": {"id": {"type": "string", "pattern": STABLE}, "format": {"const": "compatibility-export-v0"}, "contentRevision": {"type": "string", "pattern": REVISION}}, "additionalProperties": False}, {"type": "null"}]}}, "additionalProperties": False},
    "planRevision": {"type": "string", "pattern": REVISION},
}
preflight = _doc("operation-preflight", PREFLIGHT_PROPERTIES, list(PREFLIGHT_PROPERTIES))
CONTRACTS[preflight["$id"]] = preflight

RESULT_PROPERTIES = {
    "schemaVersion": {"const": VERSION}, "provider": {"const": "compatibility.provider"}, "providerVersion": {"const": VERSION}, "action": {"type": "string", "enum": ["deploy", "remove", "export"]},
    "operationId": {"type": "string", "pattern": STABLE, "maxLength": 160}, "status": STATE["properties"]["status"], "changed": {"type": "boolean"}, "changeState": {"type": "string", "enum": ["none", "complete", "unknown"]},
    "checkpoints": deepcopy(CHECKPOINT_ARRAY),
    "deploymentRevision": {"type": "string", "pattern": REVISION}, "state": deepcopy(STATE), "error": {"type": ["string", "null"], "maxLength": 1000},
    "exportArtifact": PREFLIGHT_PROPERTIES["recovery"]["properties"]["exportArtifact"],
}
result = _doc("operation-result", RESULT_PROPERTIES, list(RESULT_PROPERTIES))
CONTRACTS[result["$id"]] = result


def ref(name: str) -> dict[str, str]:
    return {"id": f"urn:omarchy:fabric:provider:compatibility:{name}:v0", "version": VERSION}
