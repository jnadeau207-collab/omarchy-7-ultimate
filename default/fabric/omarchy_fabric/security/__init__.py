"""Trust primitives for the Omarchy Agent Fabric.

This package deliberately contains no transport or UI authority. The Fabric daemon
binds peer credentials to server-issued sessions, then calls these pure primitives.
"""

from .approval import ApprovalAuthority, ApprovalCheck, ApprovalRecord
from .grants import CapabilityGrant, GrantPersistence
from .policy import PolicyEngine
from .principal import (
    EndpointAdmission,
    EndpointPrincipal,
    PrincipalKind,
    SessionBindingStore,
    SessionCredential,
)
from .release_attestation import (
    ReleaseAttestation,
    default_release_attestation,
    load_release_attestation,
    parse_release_attestation,
)
from .task_admission import (
    TASK_ENDPOINT_ID,
    PeerIdentity,
    TaskAdmissionAuthority,
    TaskEndpointBinding,
    read_peer_identity,
)
from .redaction import SecretFinding, redact, redact_text, scan_for_secrets
from .system_executor import (
    SYSTEM_ACTIONS,
    SystemExecutorRequest,
    validate_system_executor_request,
)
from .types import (
    DecisionKind,
    OperationRequest,
    PolicyDecision,
    ResourceRef,
    RiskLevel,
)

__all__ = [
    "ApprovalAuthority",
    "ApprovalCheck",
    "ApprovalRecord",
    "CapabilityGrant",
    "DecisionKind",
    "EndpointAdmission",
    "EndpointPrincipal",
    "GrantPersistence",
    "OperationRequest",
    "PolicyDecision",
    "PeerIdentity",
    "PolicyEngine",
    "PrincipalKind",
    "ReleaseAttestation",
    "ResourceRef",
    "RiskLevel",
    "TASK_ENDPOINT_ID",
    "TaskAdmissionAuthority",
    "TaskEndpointBinding",
    "SYSTEM_ACTIONS",
    "SecretFinding",
    "SessionBindingStore",
    "SessionCredential",
    "SystemExecutorRequest",
    "redact",
    "redact_text",
    "scan_for_secrets",
    "default_release_attestation",
    "load_release_attestation",
    "parse_release_attestation",
    "read_peer_identity",
    "validate_system_executor_request",
]
