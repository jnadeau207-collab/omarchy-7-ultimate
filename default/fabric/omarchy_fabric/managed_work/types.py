"""Immutable caller and capacity contracts for managed work."""

from __future__ import annotations

from dataclasses import dataclass

from .validation import stable_id

@dataclass(frozen=True)
class Actor:
    principal_id: str
    session_id: str

    def __post_init__(self) -> None:
        stable_id(self.principal_id, field="principal ID")
        stable_id(self.session_id, field="session ID")

    def as_dict(self) -> dict[str, str]:
        return {"principalId": self.principal_id, "sessionId": self.session_id}

@dataclass(frozen=True)
class CapacityLimits:
    active_tasks: int = 256
    total_tasks: int = 10_000
    total_runs: int = 20_000
    active_automations: int = 128
    total_automations: int = 2_000
    live_contexts: int = 512
    total_contexts: int = 10_000
    artifacts: int = 2048
    usage_records: int = 10_000
    operation_links: int = 256
    approval_projections: int = 1024
    permission_projections: int = 1024
    provider_projections: int = 2048
    event_firings: int = 4096
    idempotency_records: int = 50_000
    history_events: int = 20_000
    page_size: int = 100

    def __post_init__(self) -> None:
        for name, value in self.__dict__.items():
            if isinstance(value, bool) or not isinstance(value, int) or value < 1 or value > 100_000:
                raise ValueError(f"{name} capacity must be an integer between 1 and 100000")
