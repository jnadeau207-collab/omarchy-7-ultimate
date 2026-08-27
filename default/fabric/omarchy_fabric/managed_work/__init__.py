"""Provisional durable managed-work plane.

The package is intentionally not wired into daemon RPC yet. Importing it has no
side effects and grants no execution authority.
"""

from .errors import ManagedWorkError
from .plane import ManagedWorkPlane
from .store import CURRENT_SCHEMA, MAX_READABLE_SCHEMA, MIN_READABLE_SCHEMA
from .types import Actor, CapacityLimits

__all__ = (
    "Actor",
    "CapacityLimits",
    "CURRENT_SCHEMA",
    "MAX_READABLE_SCHEMA",
    "MIN_READABLE_SCHEMA",
    "ManagedWorkError",
    "ManagedWorkPlane",
)
