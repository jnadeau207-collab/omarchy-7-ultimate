"""Secret discovery and irreversible redaction for records, errors, and logs."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Iterable

REDACTED = "[REDACTED]"

_SENSITIVE_KEY_NAMES = (
    "password",
    "passphrase",
    "secret",
    "token",
    "authorization",
    "cookie",
    "credential",
    "apikey",
    "privatekey",
    "clientsecret",
    "refreshtoken",
)
_TEXT_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("authorization", re.compile(r"(?i)\b(?:authorization\s*:\s*)?(?:bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}")),
    ("private-key", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----")),
    ("github-token", re.compile(r"\bgh[oprsu]_[A-Za-z0-9]{20,}\b")),
    ("aws-access-key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    (
        "assignment",
        re.compile(
            r"(?i)\b(password|passphrase|secret|token|access[_-]?token|refresh[_-]?token|api[_-]?key|client[_-]?secret)\s*[=:]\s*([^\s,;]+)"
        ),
    ),
    ("url-credential", re.compile(r"(?i)\bhttps?://[^\s/@:]+:[^\s/@]+@")),
)

@dataclass(frozen=True)
class SecretFinding:
    path: str
    kind: str

def _pointer(parent: str, key: str | int) -> str:
    escaped = str(key).replace("~", "~0").replace("/", "~1")
    return f"{parent}/{escaped}"

def _is_sensitive_key(key: Any) -> bool:
    compact = re.sub(r"[^a-z0-9]", "", str(key).lower())
    return any(name in compact for name in _SENSITIVE_KEY_NAMES)

def scan_for_secrets(value: Any, *, explicit_paths: Iterable[str] = ()) -> tuple[SecretFinding, ...]:
    """Report secret locations and kinds without ever returning secret values."""

    explicit = frozenset(explicit_paths)
    findings: list[SecretFinding] = []

    def visit(current: Any, path: str) -> None:
        if path in explicit:
            findings.append(SecretFinding(path or "/", "explicit"))
            return
        if isinstance(current, dict):
            for key, item in current.items():
                child = _pointer(path, key)
                if _is_sensitive_key(key):
                    findings.append(SecretFinding(child, "sensitive-key"))
                else:
                    visit(item, child)
        elif isinstance(current, (list, tuple)):
            for index, item in enumerate(current):
                visit(item, _pointer(path, index))
        elif isinstance(current, str):
            for kind, pattern in _TEXT_PATTERNS:
                if pattern.search(current):
                    findings.append(SecretFinding(path or "/", kind))
                    break

    visit(value, "")
    return tuple(findings)

def redact_text(text: str) -> str:
    result = str(text)
    for kind, pattern in _TEXT_PATTERNS:
        if kind == "assignment":
            result = pattern.sub(lambda match: f"{match.group(1)}={REDACTED}", result)
        elif kind == "url-credential":
            result = pattern.sub("https://" + REDACTED + "@", result)
        else:
            result = pattern.sub(REDACTED, result)
    return result

def redact(value: Any, *, explicit_paths: Iterable[str] = ()) -> Any:
    explicit = frozenset(explicit_paths)

    def visit(current: Any, path: str) -> Any:
        if path in explicit:
            return REDACTED
        if isinstance(current, dict):
            output: dict[Any, Any] = {}
            for key, item in current.items():
                child = _pointer(path, key)
                output[key] = REDACTED if _is_sensitive_key(key) else visit(item, child)
            return output
        if isinstance(current, list):
            return [visit(item, _pointer(path, index)) for index, item in enumerate(current)]
        if isinstance(current, tuple):
            return tuple(visit(item, _pointer(path, index)) for index, item in enumerate(current))
        if isinstance(current, str):
            return redact_text(current)
        return current

    return visit(value, "")
