from __future__ import annotations

import sys
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parents[3]
FABRIC_ROOT = ROOT / "default" / "fabric"
if str(FABRIC_ROOT) not in sys.path:
    sys.path.insert(0, str(FABRIC_ROOT))

from omarchy_fabric.models import FixedArgvCommand
from omarchy_fabric.operations.contracts import OperationDefinition, ProviderBinding
from omarchy_fabric.operations.coordinator import OperationCoordinator
from omarchy_fabric.operations.executor import (
    FakeResourceExecutor,
    IntentCatalog,
    IntentDefinition,
    boolean,
    stable_token,
)
from omarchy_fabric.operations.store import OperationStore
from omarchy_fabric.security.approval import ApprovalAuthority
from omarchy_fabric.security.policy import PolicyEngine
from omarchy_fabric.security.principal import EndpointAdmission, PrincipalKind, SessionBindingStore

class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 8, 27, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.now

class FakeGateway:
    def __init__(self, executor: FakeResourceExecutor) -> None:
        self.executor = executor
        self.version = "provider.v0"
        self.fingerprint = "a" * 64
        self.generation = 1
        self.state = "available"
        self.preflight_calls = 0

    async def preflight(self, provider_id, action, arguments, principal):
        self.preflight_calls += 1
        if provider_id != "test.settings" or action != "settings.set":
            raise ValueError("unknown fake action")
        if not isinstance(arguments, Mapping) or set(arguments) != {"resourceId", "desired"}:
            raise ValueError("fake arguments are closed")
        if not isinstance(arguments["desired"], bool):
            raise ValueError("desired must be boolean")
        current = self.executor.state(arguments["resourceId"])
        proposed = {
            "resourceId": arguments["resourceId"],
            "revision": "proposal.unapplied",
            "value": arguments["desired"],
        }
        inner = {
            "schemaVersion": "v0",
            "provider": provider_id,
            "providerVersion": self.version,
            "action": action,
            "capability": "settings.configure",
            "resource": {"kind": "setting", "id": arguments["resourceId"]},
            "normalizedArguments": dict(arguments),
            "stateRevision": current["revision"],
            "currentState": current,
            "proposedState": proposed,
            "changed": current["value"] != proposed["value"],
            "summary": "Set a hermetic fake setting.",
            "risk": "consequential",
            "effects": ["settings.changed"],
            "recovery": {"mode": "rollback", "priorState": current},
        }
        return {
            "provider": provider_id,
            "providerVersion": self.version,
            "providerFingerprint": self.fingerprint,
            "generation": self.generation,
            "action": action,
            "capability": "settings.configure",
            "risk": "consequential",
            "effects": ["settings.changed"],
            "preflight": inner,
            "observedAt": self.preflight_calls,
        }

    def assert_current(self, binding: ProviderBinding) -> None:
        if (
            binding.provider_id != "test.settings"
            or binding.version != self.version
            or binding.fingerprint != self.fingerprint
            or binding.generation != self.generation
            or self.state not in {"available", "degraded"}
        ):
            from omarchy_fabric.operations.contracts import operation_error

            raise operation_error("operation.provider-stale", "Fake provider binding changed.")

def fake_intents() -> IntentCatalog:
    executable = (
        "/usr/libexec/omarchy-fabric-fake-executor"
        if os.name != "nt"
        else str(Path(sys.executable).resolve())
    )
    return IntentCatalog(
        (
            IntentDefinition(
                "test.settings.set",
                FixedArgvCommand(
                    executable,
                    ("settings-set", "--typed-stdin-v0"),
                ),
                {"resourceId": stable_token, "desired": boolean},
            ),
        )
    )

class Harness:
    def __init__(
        self,
        *,
        resources: Mapping[str, Any] | None = None,
        faults: Mapping[str, str] | None = None,
        delay_seconds: float = 0.0,
        checkpoint_hook=None,
        stage_hook=None,
        queue_timeout_seconds: float = 0.2,
        execution_timeout_seconds: float = 0.5,
        max_concurrent: int = 2,
        store_kwargs: Mapping[str, Any] | None = None,
    ) -> None:
        self.temp = TemporaryDirectory()
        self.clock = Clock()
        self.sessions = SessionBindingStore(clock=self.clock)
        self.principal, self.credential = self.sessions.issue(
            1000,
            EndpointAdmission("endpoint.shell", PrincipalKind.SHELL),
            lifetime=timedelta(hours=2),
        )
        self.approvals = ApprovalAuthority(clock=self.clock)
        self.policy_revision = "policy.revision.1"
        self.intents = fake_intents()
        self.executor = FakeResourceExecutor(
            self.intents,
            resources or {"setting.primary": False, "setting.secondary": False},
            faults=faults,
            delay_seconds=delay_seconds,
            stage_hook=stage_hook,
        )
        self.gateway = FakeGateway(self.executor)
        self.store_path = Path(self.temp.name) / "private" / "operations.db"
        self.store = OperationStore(self.store_path, clock=self.clock, **dict(store_kwargs or {}))
        self.store.open()
        self.coordinator = self.make_coordinator(
            checkpoint_hook=checkpoint_hook,
            queue_timeout_seconds=queue_timeout_seconds,
            execution_timeout_seconds=execution_timeout_seconds,
            max_concurrent=max_concurrent,
        )

    def make_coordinator(self, **overrides) -> OperationCoordinator:
        options = {
            "store": self.store,
            "gateway": self.gateway,
            "definitions": (
                OperationDefinition(
                    "test.settings",
                    "settings.set",
                    "test.settings.set",
                    lambda preflight: {
                        "resourceId": preflight["resource"]["id"],
                        "desired": preflight["proposedState"]["value"],
                    },
                ),
            ),
            "intents": self.intents,
            "executor": self.executor,
            "session_resolver": self.sessions.require_active,
            "policy_revision": lambda: self.policy_revision,
            "policy": PolicyEngine(),
            "clock": self.clock,
            "queue_timeout_seconds": 0.2,
            "execution_timeout_seconds": 0.5,
            "max_concurrent": 2,
        }
        options.update(overrides)
        return OperationCoordinator(**options)

    async def preflight(
        self,
        *,
        resource_id: str = "setting.primary",
        desired: bool = True,
        key: str = "operation.key.1",
        principal=None,
    ) -> str:
        result = await self.coordinator.preflight(
            principal or self.principal,
            provider_id="test.settings",
            action="settings.set",
            arguments={"resourceId": resource_id, "desired": desired},
            idempotency_key=key,
        )
        return result["operationId"]

    def approval(self, operation_id: str, *, principal=None):
        principal = principal or self.principal
        request = self.coordinator.approval_request(principal, operation_id)
        return self.approvals.issue(
            principal,
            request,
            expires_at=self.clock.now + timedelta(minutes=5),
        )

    async def start(self, operation_id: str, approval=None, *, principal=None):
        principal = principal or self.principal
        approval = approval or self.approval(operation_id, principal=principal)
        return await self.coordinator.start(
            principal,
            operation_id,
            approval_id=approval.approval_id,
            approvals=self.approvals,
        )

    def replacement_session(self, uid: int = 1000):
        return self.sessions.issue(
            uid,
            EndpointAdmission("endpoint.shell", PrincipalKind.SHELL),
            lifetime=timedelta(hours=2),
        )[0]

    def close(self) -> None:
        self.store.close()
        self.temp.cleanup()
