"""Durable, owner-bound mutation coordination for Fabric providers."""

from .contracts import (
    ExecutorIntent,
    OperationDefinition,
    OperationPlan,
    OperationState,
    ProviderBinding,
    ResourceBinding,
)
from .coordinator import OperationCoordinator
from .executor import (
    ExecutorApplyResult,
    ExecutorReconcileResult,
    FakeResourceExecutor,
    IntentCatalog,
    IntentDefinition,
    UnavailableProductionExecutor,
)
from .registry_gateway import RegistryOperationGateway
from .store import OperationStore

__all__ = [
    "ExecutorApplyResult",
    "ExecutorIntent",
    "ExecutorReconcileResult",
    "FakeResourceExecutor",
    "IntentCatalog",
    "IntentDefinition",
    "OperationCoordinator",
    "OperationDefinition",
    "OperationPlan",
    "OperationState",
    "OperationStore",
    "ProviderBinding",
    "RegistryOperationGateway",
    "ResourceBinding",
    "UnavailableProductionExecutor",
]
