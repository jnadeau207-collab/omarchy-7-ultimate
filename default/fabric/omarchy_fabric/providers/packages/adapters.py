"""Code-owned, fixed-argv package adapter declarations.

RPC input is carried only as a typed stdin document.  It is never interpolated
into argv, environment, a shell fragment, or an executable path.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .identity import require_stable_id

SOURCE_TYPES = (
    "curated",
    "signed-repo",
    "flatpak",
    "reviewed-aur",
    "appimage",
    "web-app",
)


@dataclass(frozen=True)
class AdapterPlan:
    adapter_id: str
    command: FixedArgvCommand
    stdin_payload: Mapping[str, Any]

    def public(self) -> dict[str, Any]:
        return {
            "adapterId": self.adapter_id,
            "executable": self.command.executable,
            "argv": list(self.command.arguments),
            "inputDigestOnly": True,
        }


_COMMANDS: dict[tuple[str, str], tuple[str, FixedArgvCommand]] = {
    ("curated", "install"): ("packages.pacman.install", FixedArgvCommand("/usr/bin/omarchy-pkg-add", ("--fabric-json",))),
    ("curated", "remove"): ("packages.pacman.remove", FixedArgvCommand("/usr/bin/omarchy-pkg-drop", ("--fabric-json",))),
    ("signed-repo", "install"): ("packages.pacman.install", FixedArgvCommand("/usr/bin/omarchy-pkg-add", ("--fabric-json",))),
    ("signed-repo", "remove"): ("packages.pacman.remove", FixedArgvCommand("/usr/bin/omarchy-pkg-drop", ("--fabric-json",))),
    ("reviewed-aur", "install"): ("packages.aur.install", FixedArgvCommand("/usr/bin/omarchy-pkg-add", ("--fabric-json",))),
    ("reviewed-aur", "remove"): ("packages.aur.remove", FixedArgvCommand("/usr/bin/omarchy-pkg-drop", ("--fabric-json",))),
    ("flatpak", "install"): ("packages.flatpak.install", FixedArgvCommand("/usr/bin/flatpak", ("install", "--noninteractive", "--assumeyes", "--from-json"))),
    ("flatpak", "remove"): ("packages.flatpak.remove", FixedArgvCommand("/usr/bin/flatpak", ("uninstall", "--noninteractive", "--assumeyes", "--from-json"))),
    ("appimage", "install"): ("packages.appimage.install", FixedArgvCommand("/usr/bin/omarchy-appimage-install", ("--fabric-json",))),
    ("appimage", "remove"): ("packages.appimage.remove", FixedArgvCommand("/usr/bin/omarchy-appimage-remove", ("--fabric-json",))),
    ("web-app", "install"): ("packages.web-app.install", FixedArgvCommand("/usr/bin/omarchy-webapp-install", ("--fabric-json",))),
    ("web-app", "remove"): ("packages.web-app.remove", FixedArgvCommand("/usr/bin/omarchy-webapp-remove", ("--fabric-json",))),
}
_ADOPTION_COMMAND = ("packages.adoption", FixedArgvCommand("/usr/bin/omarchy-software-adopt", ("--fabric-json",)))


def plan_adapter(source_type: str, intent: str, payload: Mapping[str, Any]) -> AdapterPlan:
    if not isinstance(payload, Mapping):
        raise ValueError("adapter payload must be an object")
    definition = _ADOPTION_COMMAND if intent == "adopt" and source_type in SOURCE_TYPES else _COMMANDS.get((source_type, intent))
    if definition is None:
        raise ValueError("source and intent have no fixed adapter")
    adapter_id, command = definition
    require_stable_id(adapter_id, "adapter ID")
    return AdapterPlan(adapter_id, command, dict(payload))


def command_matrix() -> tuple[FixedArgvCommand, ...]:
    return (*tuple(definition[1] for _, definition in sorted(_COMMANDS.items())), _ADOPTION_COMMAND[1])
