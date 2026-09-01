"""Typed validation errors used at the Fabric trust boundary."""

class SecurityValidationError(ValueError):
    """A fail-closed validation error with a stable machine-readable code."""

    def __init__(self, code: str, explanation: str) -> None:
        super().__init__(explanation)
        self.code = code
        self.explanation = explanation
