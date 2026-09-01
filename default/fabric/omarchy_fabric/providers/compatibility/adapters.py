"""Fixed-argv Compatibility Center route adapters."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

ROUTES = ("native", "pwa", "known-good-recipe", "game-proton", "isolated-app", "vm")

@dataclass(frozen=True)
class CompatibilityAdapterPlan:
    adapter_id: str
    command: FixedArgvCommand
    typed_input: Mapping[str, Any]

    def public(self) -> dict[str, Any]:
        return {"adapterId": self.adapter_id, "executable": self.command.executable, "argv": list(self.command.arguments), "inputDigestOnly": True}

_ROUTE_COMMANDS: dict[str, tuple[str, FixedArgvCommand]] = {
    "native": ("compatibility.native", FixedArgvCommand("/usr/bin/omarchy-pkg-add", ("--fabric-json",))),
    "pwa": ("compatibility.pwa", FixedArgvCommand("/usr/bin/omarchy-webapp-install", ("--fabric-json",))),
    "known-good-recipe": ("compatibility.recipe", FixedArgvCommand("/usr/bin/omarchy-compat-apply", ("--fabric-json",))),
    "game-proton": ("compatibility.proton", FixedArgvCommand("/usr/bin/umu-run", ("--fabric-json",))),
    "isolated-app": ("compatibility.isolated", FixedArgvCommand("/usr/bin/bwrap", ("--args-from-stdin",))),
    "vm": ("compatibility.vm", FixedArgvCommand("/usr/bin/omarchy-windows-vm", ("--fabric-json",))),
}

def route_adapter(route: str, typed_input: Mapping[str, Any]) -> CompatibilityAdapterPlan:
    definition = _ROUTE_COMMANDS.get(route)
    if definition is None or not isinstance(typed_input, Mapping):
        raise ValueError("compatibility route has no fixed adapter")
    return CompatibilityAdapterPlan(definition[0], definition[1], dict(typed_input))

def command_matrix() -> tuple[FixedArgvCommand, ...]:
    return tuple(value[1] for _, value in sorted(_ROUTE_COMMANDS.items()))
