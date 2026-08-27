"""Leaf-owned typed system providers.

Provider discovery and RPC dispatch are deliberately owned by the central
Fabric registry.  Domain packages expose only their fixed ``build_provider``
entry point and never import a provider name from request data.
"""
