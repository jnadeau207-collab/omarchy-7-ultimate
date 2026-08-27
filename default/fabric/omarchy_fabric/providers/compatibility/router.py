"""Deterministic, fail-closed compatibility route decisions."""

from __future__ import annotations

from copy import deepcopy
from typing import Any, Mapping
from urllib.parse import urlsplit

from omarchy_fabric.providers.packages.identity import revision, stable_id

from .recipes import RecipeCatalog

ROUTE_ORDER = ("native", "pwa", "known-good-recipe", "game-proton", "isolated-app", "vm")
PWA_PERMISSIONS = {"network", "audio", "camera", "microphone", "notifications"}


def _https_url(value: object) -> bool:
    if not isinstance(value, str) or any(character.isspace() or ord(character) < 32 or ord(character) == 127 for character in value):
        return False
    try:
        parsed = urlsplit(value)
    except ValueError:
        return False
    return parsed.scheme == "https" and bool(parsed.hostname) and parsed.username is None and parsed.password is None


class CompatibilityRouter:
    def __init__(self, recipes: RecipeCatalog) -> None:
        self.recipes = recipes

    def decide(self, request: Mapping[str, Any], host: Mapping[str, Any]) -> dict[str, Any]:
        request = deepcopy(dict(request))
        host = deepcopy(dict(host))
        request["permissions"] = sorted(request["permissions"])
        considered: list[dict[str, str]] = []
        route: str | None = None
        recipe_id: str | None = None
        reason_code = "compatibility.unsupported"
        explanation = "No route can satisfy the workload and host constraints without weakening isolation or trust."

        def consider(candidate: str, eligible: bool, reason: str) -> bool:
            considered.append({"route": candidate, "status": "eligible" if eligible else "ineligible", "reason": reason})
            return eligible

        artifact = request["artifact"]
        pinned_artifact = _https_url(artifact["origin"]) and isinstance(artifact["digest"], str)
        architecture_matches = request["architecture"] in {"any", host["architecture"]}
        native = request["workloadType"] == "desktop" and artifact["kind"] == "native-package" and pinned_artifact and architecture_matches
        if consider("native", native, "A pinned host-compatible native package is available." if native else "The workload is not a pinned host-compatible native desktop package."):
            route, reason_code, explanation = "native", "compatibility.native", "Use the native package route with adapter-side signature verification."

        pwa = (
            request["workloadType"] == "web"
            and artifact["kind"] == "web-url"
            and _https_url(artifact["origin"])
            and request["constraints"]["acceptsBrowser"]
            and not request["constraints"]["offlineRequired"]
            and not request["constraints"]["requiresKernelDriver"]
            and not request["constraints"]["requiresAdmin"]
            and set(request["permissions"]) <= PWA_PERMISSIONS
            and host["browserAvailable"]
            and "browser" in host["availableRuntimes"]
        )
        if route is None and consider("pwa", pwa, "The workload is browser-compatible and online." if pwa else "Browser, origin, or offline requirements rule out a PWA."):
            route, reason_code, explanation = "pwa", "compatibility.pwa", "Use the browser-isolated PWA route."
        elif route is not None:
            consider("pwa", False, "A higher-priority native route was selected.")

        recipe = self.recipes.by_workload.get(request["id"])
        requirements = recipe["hostRequirements"] if recipe is not None else None
        runtime_available = requirements is not None and requirements["runtime"] in host["availableRuntimes"]
        if requirements is not None and requirements["runtime"] == "browser":
            runtime_available = runtime_available and host["browserAvailable"]
        elif requirements is not None and requirements["runtime"] == "proton":
            runtime_available = runtime_available and host["protonAvailable"]
        elif requirements is not None and requirements["runtime"] == "container":
            runtime_available = runtime_available and host["isolationAvailable"]
        recipe_eligible = (
            recipe is not None
            and runtime_available
            and host["memoryMiB"] >= requirements["minimumMemoryMiB"]
            and host["diskMiB"] >= requirements["minimumDiskMiB"]
            and recipe["architecture"] in {"any", host["architecture"]}
            and architecture_matches
            and set(request["permissions"]) <= set(recipe["permissions"])
            and artifact["origin"] == recipe["artifact"]["origin"]
            and artifact["digest"] == recipe["artifact"]["digest"]
            and not request["constraints"]["requiresKernelDriver"]
            and not request["constraints"]["requiresAdmin"]
            and request["constraints"]["antiCheat"] not in {"blocked", "unknown"}
        )
        assurance_label = "contract-seed" if self.recipes.assurance == "contract-seed" else "release-verified"
        if route is None and consider("known-good-recipe", recipe_eligible, f"An admissible {assurance_label} recipe matches artifact, host resources, runtime, architecture, and permissions." if recipe_eligible else "No admissible recipe matches the exact artifact, host requirements, constraints, permissions, and architecture."):
            route, recipe_id, reason_code, explanation = "known-good-recipe", recipe["id"], "compatibility.known-good-recipe", f"Use the pinned {assurance_label} compatibility recipe plan."
        elif route is not None:
            consider("known-good-recipe", False, "A higher-priority route was selected.")

        anti_cheat = request["constraints"]["antiCheat"]
        proton = (
            request["workloadType"] == "windows-game"
            and artifact["kind"] == "windows-executable"
            and pinned_artifact
            and host["architecture"] == "x86_64"
            and architecture_matches
            and host["protonAvailable"]
            and "proton" in host["availableRuntimes"]
            and anti_cheat in {"none", "supported"}
            and not request["constraints"]["requiresKernelDriver"]
            and not request["constraints"]["requiresAdmin"]
        )
        if route is None and consider("game-proton", proton, "The game and anti-cheat contract are Proton-compatible." if proton else "Proton, driver, or anti-cheat requirements are unsupported."):
            route, reason_code, explanation = "game-proton", "compatibility.game-proton", "Use the pinned game Proton runtime."
        elif route is not None:
            consider("game-proton", False, "A higher-priority route was selected.")

        isolated = artifact["kind"] == "portable" and pinned_artifact and architecture_matches and host["isolationAvailable"] and "container" in host["availableRuntimes"] and not request["constraints"]["requiresKernelDriver"] and not request["constraints"]["requiresAdmin"] and "devices" not in request["permissions"]
        if route is None and consider("isolated-app", isolated, "The portable workload fits the declared isolation boundary." if isolated else "The artifact or requested privileges exceed portable isolation."):
            route, reason_code, explanation = "isolated-app", "compatibility.isolated-app", "Use the isolated portable application route."
        elif route is not None:
            consider("isolated-app", False, "A higher-priority route was selected.")

        vm = request["workloadType"] in {"windows-app", "windows-game"} and artifact["kind"] == "windows-executable" and pinned_artifact and architecture_matches and host["virtualizationAvailable"] and host["architecture"] == "x86_64"
        if route is None and consider("vm", vm, "A Windows workload can run in the available VM boundary." if vm else "A supported x86_64 virtualization boundary is unavailable."):
            route, reason_code, explanation = "vm", "compatibility.vm", "Use a Windows VM because the workload cannot safely run in a thinner boundary."
        elif route is not None:
            consider("vm", False, "A higher-priority route was selected.")

        eligibility = "supported" if route is not None else "unsupported"
        core = {
            "schemaVersion": "v0", "provider": "compatibility.provider",
            "decisionId": stable_id("decision.compatibility", request["id"], self.recipes.revision, revision(host), revision(request)),
            "recipeRevision": self.recipes.revision, "recipeAssurance": self.recipes.assurance, "eligibility": eligibility, "selectedRoute": route,
            "recipeId": recipe_id, "reasonCode": reason_code, "explanation": explanation,
            "requiredPermissions": request["permissions"], "considered": considered,
        }
        core["revision"] = revision({**core, "revision": "sha256." + "0" * 64})
        return core
