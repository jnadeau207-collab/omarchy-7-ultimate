"""Stable fail-closed errors for the provisional managed-work boundary."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

@dataclass
class ManagedWorkError(Exception):
    """An error safe to project into a future typed Fabric response."""

    code: str
    explanation: str
    retryable: bool = False
    detail: str = ""
    recovery_actions: tuple[str, ...] = field(default_factory=tuple)

    def __str__(self) -> str:
        return f"{self.code}: {self.explanation}"

    def as_dict(self) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "managed-work-error",
            "code": self.code,
            "explanation": self.explanation,
            "retryable": self.retryable,
            "detail": self.detail,
            "recoveryActions": list(self.recovery_actions),
        }
