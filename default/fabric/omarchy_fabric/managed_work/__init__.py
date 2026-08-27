"""Durable read-only Agent Center plane with no execution authority.

The daemon exposes its twelve views through one closed ``managed-work.query``
RPC. Importing the package has no side effects and grants no mutation or
execution authority.
"""

from .errors import ManagedWorkError
from .ownership import AccountOwner, StableOwnerSessionStore
from .plane import ManagedWorkPlane
from .projections import DaemonProjectionBridge
from .store import CURRENT_SCHEMA, MAX_READABLE_SCHEMA, MIN_READABLE_SCHEMA
from .types import Actor, CapacityLimits

__all__ = (
    "AccountOwner",
    "Actor",
    "CapacityLimits",
    "CURRENT_SCHEMA",
    "DaemonProjectionBridge",
    "MAX_READABLE_SCHEMA",
    "MIN_READABLE_SCHEMA",
    "ManagedWorkError",
    "ManagedWorkPlane",
    "StableOwnerSessionStore",
)
