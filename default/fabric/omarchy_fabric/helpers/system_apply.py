"""Code-owned root apply helper for privileged Fabric intents."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
from typing import Any, Iterable, Mapping

from ..providers.packages.catalog import PackageCatalog
from ..security.errors import SecurityValidationError
from ..security.release_attestation import default_release_attestation
from ..security.system_executor import SYSTEM_ACTIONS, validate_system_executor_request

PACMAN = "/usr/bin/pacman"
MAX_PAYLOAD_BYTES = 65536
COMMAND_TIMEOUT_SECONDS = 900
PACMAN_SOURCE_TYPES = frozenset({"curated", "signed-repo"})


class ApplyError(Exception):
    def __init__(self, code: str, explanation: str) -> None:
        super().__init__(explanation)
        self.code = code
        self.explanation = explanation


def read_document(stream: Any) -> Mapping[str, Any]:
    raw = stream.read(MAX_PAYLOAD_BYTES + 1)
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", errors="replace")
    if not raw or len(raw) > MAX_PAYLOAD_BYTES:
        raise ApplyError("payload.bounds", "The executor request is empty or exceeds its fixed bound.")
    try:
        document = json.loads(raw)
    except ValueError as error:
        raise ApplyError("payload.invalid", "The executor request is not valid JSON.") from error
    if not isinstance(document, dict):
        raise ApplyError("payload.invalid", "The executor request must be an object.")
    return document


def require_action(document: Mapping[str, Any], action: str) -> Any:
    if action not in SYSTEM_ACTIONS:
        raise ApplyError("action.unknown", "The requested system action is not code owned.")
    try:
        request = validate_system_executor_request(document)
    except SecurityValidationError as error:
        raise ApplyError(error.code, str(error)) from error
    if request.action != action:
        raise ApplyError("action.mismatch", "The request action does not match the code-owned entry point.")
    return request


def load_catalog() -> PackageCatalog:
    root = pathlib.Path(__file__).resolve().parents[3]
    attestation = default_release_attestation(root)
    return PackageCatalog.load(
        root / "ultimate" / "software" / "catalog-v0.json",
        verified_catalog_revisions=attestation.admitted_revisions("packages-catalog"),
    )


def resolve_package_refs(package_ids: Iterable[str], catalog: PackageCatalog) -> tuple[str, ...]:
    by_id = {entry["id"]: entry for entry in catalog.entries}
    refs: list[str] = []
    for package_id in package_ids:
        entry = by_id.get(package_id)
        if entry is None:
            raise ApplyError("package.unknown", "A requested package is not admitted by the code-owned catalog.")
        if entry["sourceType"] not in PACMAN_SOURCE_TYPES:
            raise ApplyError("package.source-unsupported", "This source channel has no code-owned root install path yet.")
        refs.append(entry["packageRef"])
    if not refs:
        raise ApplyError("package.empty", "No package was named.")
    return tuple(refs)


def run_fixed(argv: tuple[str, ...]) -> str:
    try:
        completed = subprocess.run(
            list(argv),
            capture_output=True,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
            check=False,
        )
    except FileNotFoundError as error:
        raise ApplyError("command.unavailable", "The code-owned system command is not installed.") from error
    except subprocess.TimeoutExpired as error:
        raise ApplyError("command.timeout", "The system command did not finish within its deadline.") from error
    if completed.returncode != 0:
        raise ApplyError("command.failed", completed.stderr.strip()[:480] or "The system command reported a failure.")
    return completed.stdout.strip()[:480]


def apply_packages_install(request: Any) -> Mapping[str, Any]:
    refs = resolve_package_refs(request.arguments["package_ids"], load_catalog())
    output = run_fixed((PACMAN, "-S", "--noconfirm", "--needed", "--") + refs)
    return {"action": request.action, "packages": list(refs), "output": output}


def apply_packages_remove(request: Any) -> Mapping[str, Any]:
    refs = resolve_package_refs(request.arguments["package_ids"], load_catalog())
    mode = "-R" if request.arguments["preserve_data"] else "-Rns"
    output = run_fixed((PACMAN, mode, "--noconfirm", "--") + refs)
    return {"action": request.action, "packages": list(refs), "output": output}


ACTIONS = {
    "packages.install": apply_packages_install,
    "packages.remove": apply_packages_remove,
}


def audit(request: Any, outcome: str, code: str) -> None:
    try:
        import syslog
    except ImportError:
        return
    record = json.dumps(
        {
            "requestId": request.request_id,
            "operationId": request.operation_id,
            "action": request.action,
            "polkitAction": request.polkit_action,
            "approvalBinding": request.approval_binding,
            "consentNonce": request.consent_nonce,
            "outcome": outcome,
            "code": code,
        },
        separators=(",", ":"),
        sort_keys=True,
    )
    syslog.openlog("omarchy-fabric-system-executor", syslog.LOG_PID, syslog.LOG_AUTHPRIV)
    syslog.syslog(syslog.LOG_NOTICE, record)
    syslog.closelog()


def main(argv: list[str], stdin: Any = None, stdout: Any = None) -> int:
    stdin = stdin if stdin is not None else sys.stdin
    stdout = stdout if stdout is not None else sys.stdout
    request = None
    try:
        if len(argv) != 1:
            raise ApplyError("action.argv", "The system executor takes exactly one code-owned action.")
        document = read_document(stdin)
        request = require_action(document, argv[0])
        handler = ACTIONS.get(request.action)
        if handler is None:
            raise ApplyError("action.unimplemented", "This system action has no code-owned root implementation yet.")
        result = handler(request)
    except ApplyError as error:
        if request is not None:
            audit(request, "refused", error.code)
        json.dump({"ok": False, "code": error.code, "explanation": error.explanation}, stdout)
        stdout.write("\n")
        return 1
    audit(request, "applied", "ok")
    json.dump({"ok": True, **result}, stdout)
    stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
