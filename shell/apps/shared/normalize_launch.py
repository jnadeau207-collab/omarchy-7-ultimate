#!/usr/bin/python
"""Normalize one standalone product-app invocation into a bounded v1 envelope."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, unquote, urlsplit

CATALOGS = {
    "settings": "ultimate-settings/routes-v1.json",
    "agent-center": "ultimate-agent-center/routes-v1.json",
    "files": "ultimate-files/routes-v1.json",
    "software": "ultimate-software/routes-v1.json",
    "compatibility": "ultimate-compatibility/routes-v1.json",
}
APP_IDS = {
    "settings": "org.omarchy.Settings",
    "agent-center": "org.omarchy.AgentCenter",
    "files": "org.omarchy.Files",
    "software": "org.omarchy.Software",
    "compatibility": "org.omarchy.Compatibility",
}
SCHEMES = {
    "settings": "omarchy-settings",
    "agent-center": "omarchy-agent",
    "files": "omarchy-files",
    "software": "omarchy-software",
    "compatibility": "omarchy-compatibility",
}
SOURCES = frozenset({"cli", "desktop", "shell", "notification", "automation"})
STABLE_ID = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
OPAQUE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$")
APP_ID = re.compile(r"^[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)+$")
SCHEME = re.compile(r"^[a-z][a-z0-9-]{1,62}$")
DEEP_LINK_HOST = re.compile(r"^[a-z][a-z0-9-]{0,62}$")
DEEP_LINK_PATH = re.compile(r"^[a-z0-9-]*(?:/[a-z0-9-]+)*$")
ROUTE_REQUIRED_FIELDS = frozenset(
    {"id", "section", "title", "description", "keywords", "providerId", "argumentSchema"}
)
ROUTE_OPTIONAL_FIELDS = frozenset({"deepLink"})
OPTION_NAMES = frozenset(
    {"--route", "--args-json", "--screen", "--anchor", "--seat", "--focus-return", "--source"}
)
MAX_ENVELOPE_BYTES = 4096
MAX_LINK_BYTES = 2048

class LaunchError(ValueError):
    pass

def require_object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise LaunchError(f"{label} must be a JSON object")
    return value

def require_exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = ", ".join(sorted(expected - actual))
        extra = ", ".join(sorted(actual - expected))
        detail = "; ".join(part for part in (f"missing: {missing}" if missing else "", f"extra: {extra}" if extra else "") if part)
        raise LaunchError(f"{label} has unexpected fields ({detail})")

def require_closed_keys(
    value: dict[str, Any], required: frozenset[str], optional: frozenset[str], label: str
) -> None:
    actual = set(value)
    missing = required - actual
    extra = actual - required - optional
    if missing or extra:
        detail = "; ".join(
            part
            for part in (
                f"missing: {', '.join(sorted(missing))}" if missing else "",
                f"extra: {', '.join(sorted(extra))}" if extra else "",
            )
            if part
        )
        raise LaunchError(f"{label} has unexpected fields ({detail})")

def require_stable_id(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) > 128 or STABLE_ID.fullmatch(value) is None:
        raise LaunchError(f"{label} must be a stable dotted identifier")
    return value

def require_opaque_id(value: Any, label: str) -> str:
    if not isinstance(value, str) or OPAQUE_ID.fullmatch(value) is None:
        raise LaunchError(f"{label} must be a bounded non-secret identifier")
    return value

def validate_argument(value: Any, contract: dict[str, Any], label: str) -> Any:
    kind = contract.get("type")
    if kind == "stable-id":
        return require_stable_id(value, label)
    if kind == "opaque-id":
        return require_opaque_id(value, label)
    if kind == "boolean":
        if not isinstance(value, bool):
            raise LaunchError(f"{label} must be a boolean")
        return value
    if kind == "integer":
        if isinstance(value, bool) or not isinstance(value, int):
            raise LaunchError(f"{label} must be an integer")
        return value
    if kind == "enum":
        values = contract.get("values")
        if not isinstance(values, list) or value not in values:
            raise LaunchError(f"{label} is not an allowed value")
        return value
    if kind == "text":
        maximum = contract.get("maxLength")
        if not isinstance(value, str) or not isinstance(maximum, int) or isinstance(maximum, bool):
            raise LaunchError(f"{label} must be bounded text")
        if len(value) > maximum or any(ord(character) < 32 or ord(character) == 127 for character in value):
            raise LaunchError(f"{label} is outside its bounded text contract")
        return value
    raise LaunchError(f"{label} uses an unsupported argument type")

def validate_catalog(candidate: Any, application: str) -> dict[str, Any]:
    expected_app_id = APP_IDS.get(application)
    expected_scheme = SCHEMES.get(application)
    if expected_app_id is None or expected_scheme is None:
        raise LaunchError("unknown standalone application")
    catalog = require_object(candidate, "route catalog")
    require_exact_keys(
        catalog,
        {"schemaVersion", "application", "appId", "scheme", "defaultRoute", "routes", "entityDeepLinks"},
        "route catalog",
    )
    if catalog["schemaVersion"] != "omarchy.product-routes/v1" or catalog["application"] != application:
        raise LaunchError("route catalog identity is incompatible")
    if (
        not isinstance(catalog["appId"], str)
        or len(catalog["appId"]) > 255
        or APP_ID.fullmatch(catalog["appId"]) is None
        or catalog["appId"] != expected_app_id
    ):
        raise LaunchError("route catalog application ID is incompatible")
    if (
        not isinstance(catalog["scheme"], str)
        or SCHEME.fullmatch(catalog["scheme"]) is None
        or catalog["scheme"] != expected_scheme
    ):
        raise LaunchError("route catalog scheme is incompatible")
    default_route = require_stable_id(catalog["defaultRoute"], "route catalog default")
    if not isinstance(catalog["routes"], list) or not 1 <= len(catalog["routes"]) <= 128:
        raise LaunchError("route catalog has an invalid route count")
    route_index: dict[str, dict[str, Any]] = {}
    link_index: dict[tuple[str, str], str] = {}
    for raw_route in catalog["routes"]:
        route = require_object(raw_route, "route")
        require_closed_keys(route, ROUTE_REQUIRED_FIELDS, ROUTE_OPTIONAL_FIELDS, "route")
        route_id = require_stable_id(route.get("id"), "route ID")
        if route_id in route_index:
            raise LaunchError(f"route catalog repeats {route_id}")
        if not isinstance(route["section"], str) or not 1 <= len(route["section"]) <= 80:
            raise LaunchError(f"{route_id} section is invalid")
        if not isinstance(route["title"], str) or not 1 <= len(route["title"]) <= 120:
            raise LaunchError(f"{route_id} title is invalid")
        if not isinstance(route["description"], str) or not 1 <= len(route["description"]) <= 320:
            raise LaunchError(f"{route_id} description is invalid")
        if not isinstance(route["keywords"], list) or len(route["keywords"]) > 32:
            raise LaunchError(f"{route_id} keywords are invalid")
        if any(not isinstance(keyword, str) or not 1 <= len(keyword) <= 80 for keyword in route["keywords"]):
            raise LaunchError(f"{route_id} contains an invalid keyword")
        provider_id = route["providerId"]
        if not isinstance(provider_id, str) or (provider_id != "" and require_stable_id(provider_id, "provider ID") != provider_id):
            raise LaunchError(f"{route_id} provider identity is invalid")
        argument_schema = require_object(route.get("argumentSchema"), f"{route_id} argument schema")
        for name, raw_contract in argument_schema.items():
            if re.fullmatch(r"[a-z][A-Za-z0-9]{0,47}", name) is None:
                raise LaunchError(f"{route_id} contains an invalid argument name")
            contract = require_object(raw_contract, f"{route_id}.{name} contract")
            kind = contract.get("type")
            if kind not in {"stable-id", "opaque-id", "boolean", "integer", "enum", "text"}:
                raise LaunchError(f"{route_id}.{name} uses an unsupported argument type")
            if kind == "enum":
                expected_contract_fields = {"type", "values"}
            elif kind == "text":
                expected_contract_fields = {"type", "maxLength"}
            else:
                expected_contract_fields = {"type"}
            if "optional" in contract:
                expected_contract_fields.add("optional")
            require_exact_keys(contract, expected_contract_fields, f"{route_id}.{name} contract")
            if "optional" in contract and not isinstance(contract["optional"], bool):
                raise LaunchError(f"{route_id}.{name} optional flag must be boolean")
            if kind == "enum":
                values = contract["values"]
                if not isinstance(values, list) or not 1 <= len(values) <= 32:
                    raise LaunchError(f"{route_id}.{name} enum values are invalid")
                if any(not isinstance(value, str) or not 1 <= len(value) <= 128 for value in values):
                    raise LaunchError(f"{route_id}.{name} enum values must be bounded strings")
                if len(set(values)) != len(values):
                    raise LaunchError(f"{route_id}.{name} repeats an enum value")
            elif kind == "text":
                maximum = contract["maxLength"]
                if isinstance(maximum, bool) or not isinstance(maximum, int) or not 1 <= maximum <= 512:
                    raise LaunchError(f"{route_id}.{name} text bound is invalid")
        if "deepLink" in route:
            deep_link = route["deepLink"]
            deep_link = require_object(deep_link, f"{route_id} deep link")
            require_exact_keys(deep_link, {"host", "path"}, f"{route_id} deep link")
            host = deep_link["host"]
            path = deep_link["path"]
            if not isinstance(host, str) or DEEP_LINK_HOST.fullmatch(host) is None:
                raise LaunchError(f"{route_id} deep link host is invalid")
            if not isinstance(path, str) or len(path) > 256 or DEEP_LINK_PATH.fullmatch(path) is None:
                raise LaunchError(f"{route_id} deep link path is invalid")
            key = (host, path)
            if key in link_index:
                raise LaunchError("route catalog contains a duplicate deep link")
            link_index[key] = route_id
        route_index[route_id] = route
    if default_route not in route_index:
        raise LaunchError("route catalog default is not registered")
    entity_links = catalog["entityDeepLinks"]
    if not isinstance(entity_links, list) or len(entity_links) > 32:
        raise LaunchError("entity deep link table is invalid")
    entity_index: dict[str, dict[str, Any]] = {}
    for raw_link in entity_links:
        link = require_object(raw_link, "entity deep link")
        require_exact_keys(link, {"host", "routeId", "entityType"}, "entity deep link")
        host = link["host"]
        route_id = link["routeId"]
        if not isinstance(host, str) or DEEP_LINK_HOST.fullmatch(host) is None:
            raise LaunchError("entity deep link host is invalid")
        require_stable_id(route_id, "entity deep link route")
        if host in entity_index or route_id not in route_index:
            raise LaunchError("entity deep link table is inconsistent")
        require_stable_id(link["entityType"], "entity type")
        entity_index[host] = link
    validated_catalog = dict(catalog)
    validated_catalog["_routeIndex"] = route_index
    validated_catalog["_linkIndex"] = link_index
    validated_catalog["_entityIndex"] = entity_index
    return validated_catalog

def load_catalog(application: str) -> dict[str, Any]:
    relative = CATALOGS.get(application)
    if relative is None:
        raise LaunchError("unknown standalone application")
    path = Path(__file__).resolve().parent.parent / relative
    try:
        candidate = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise LaunchError(f"route catalog could not be loaded: {error}") from error
    return validate_catalog(candidate, application)

def parse_options(arguments: list[str]) -> dict[str, Any]:
    parsed: dict[str, Any] = {
        "route": None,
        "argsJson": None,
        "screen": None,
        "anchor": None,
        "seat": None,
        "focusReturn": None,
        "source": "cli",
        "target": None,
    }
    seen: set[str] = set()
    index = 0
    while index < len(arguments):
        token = arguments[index]
        if token == "--":
            index += 1
            if index < len(arguments):
                if parsed["target"] is not None or index + 1 != len(arguments):
                    raise LaunchError("exactly one route or deep link may be supplied")
                parsed["target"] = arguments[index]
            break
        if token.startswith("--"):
            name, separator, attached = token.partition("=")
            if name not in OPTION_NAMES:
                raise LaunchError(f"unknown option: {name}")
            if name in seen:
                raise LaunchError(f"option may only be supplied once: {name}")
            seen.add(name)
            if separator:
                value = attached
            else:
                index += 1
                if index >= len(arguments):
                    raise LaunchError(f"option requires a value: {name}")
                value = arguments[index]
            key = {
                "--route": "route",
                "--args-json": "argsJson",
                "--screen": "screen",
                "--anchor": "anchor",
                "--seat": "seat",
                "--focus-return": "focusReturn",
                "--source": "source",
            }[name]
            parsed[key] = value
        else:
            if parsed["target"] is not None:
                raise LaunchError("exactly one route or deep link may be supplied")
            parsed["target"] = token
        index += 1
    if parsed["route"] is not None and parsed["target"] is not None:
        raise LaunchError("use either --route or a positional route/deep link, not both")
    return parsed

def parse_anchor(raw: str | None) -> dict[str, int] | None:
    if raw is None:
        return None
    parts = raw.split(",")
    if len(parts) != 4:
        raise LaunchError("--anchor must be x,y,width,height")
    try:
        x, y, width, height = (int(part, 10) for part in parts)
    except ValueError as error:
        raise LaunchError("--anchor must contain decimal integers") from error
    if any(abs(value) > 100000 for value in (x, y, width, height)) or width < 1 or height < 1:
        raise LaunchError("--anchor is outside the bounded positive-size contract")
    return {"x": x, "y": y, "width": width, "height": height}

def arguments_for_route(route: dict[str, Any], raw_arguments: Any) -> dict[str, Any]:
    arguments = require_object(raw_arguments, "route arguments")
    schema = route["argumentSchema"]
    for name in arguments:
        if name not in schema:
            raise LaunchError(f"{route['id']} does not accept argument {name}")
        arguments[name] = validate_argument(arguments[name], schema[name], f"argument {name}")
    for name, contract in schema.items():
        if contract.get("optional") is not True and name not in arguments:
            raise LaunchError(f"{route['id']} requires argument {name}")
    return arguments

def route_from_link(catalog: dict[str, Any], raw_link: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if len(raw_link.encode("utf-8")) > MAX_LINK_BYTES:
        raise LaunchError("deep link is too long")
    try:
        link = urlsplit(raw_link)
    except ValueError as error:
        raise LaunchError(f"deep link is malformed: {error}") from error
    try:
        port = link.port
    except ValueError as error:
        raise LaunchError(f"deep link port is malformed: {error}") from error
    if link.scheme != catalog["scheme"] or link.username is not None or link.password is not None or port is not None:
        raise LaunchError(f"deep link must use {catalog['scheme']} with no authority credentials or port")
    if link.fragment:
        raise LaunchError("deep links may not contain fragments")
    host = link.hostname or ""
    path = unquote(link.path).strip("/")
    route_id = catalog["_linkIndex"].get((host, path))
    if route_id is not None:
        route = catalog["_routeIndex"][route_id]
        try:
            pairs = parse_qsl(link.query, keep_blank_values=True, strict_parsing=True)
        except ValueError as error:
            raise LaunchError(f"deep link query is malformed: {error}") from error
        query: dict[str, Any] = {}
        for name, value in pairs:
            if name in query:
                raise LaunchError(f"deep link repeats argument {name}")
            query[name] = value
        return route, arguments_for_route(route, query)
    entity = catalog["_entityIndex"].get(host)
    if entity is None:
        raise LaunchError("deep link does not match a registered route")
    if link.query or "/" in path or not path:
        raise LaunchError("entity deep links require exactly one path identifier and no query")
    route = catalog["_routeIndex"][entity["routeId"]]
    return route, arguments_for_route(
        route,
        {"entityType": entity["entityType"], "entityId": require_opaque_id(path, "entity ID")},
    )

def normalize(application: str, raw_arguments: list[str]) -> dict[str, Any]:
    catalog = load_catalog(application)
    options = parse_options(raw_arguments)
    target = options["route"] or options["target"] or catalog["defaultRoute"]
    if not isinstance(target, str) or not target:
        raise LaunchError("route is empty")
    is_link = "://" in target
    if is_link:
        if options["argsJson"] is not None:
            raise LaunchError("--args-json cannot be combined with a deep link")
        route, route_arguments = route_from_link(catalog, target)
    else:
        route = catalog["_routeIndex"].get(require_stable_id(target, "route"))
        if route is None:
            raise LaunchError(f"unknown route: {target}")
        if options["argsJson"] is None:
            raw_route_arguments: Any = {}
        else:
            try:
                raw_route_arguments = json.loads(options["argsJson"])
            except json.JSONDecodeError as error:
                raise LaunchError(f"--args-json is malformed: {error.msg}") from error
        route_arguments = arguments_for_route(route, raw_route_arguments)
    source = options["source"]
    if source not in SOURCES:
        raise LaunchError("--source is not an allowed invocation source")
    context = {
        "screen": require_opaque_id(options["screen"], "screen") if options["screen"] is not None else None,
        "anchor": parse_anchor(options["anchor"]),
        "seat": require_opaque_id(options["seat"], "seat") if options["seat"] is not None else None,
        "focusReturn": require_opaque_id(options["focusReturn"], "focus return target") if options["focusReturn"] is not None else None,
        "source": source,
    }
    return {
        "schemaVersion": "omarchy.product-launch/v1",
        "application": application,
        "routeId": route["id"],
        "arguments": route_arguments,
        "context": context,
    }

def main() -> int:
    if len(sys.argv) < 2:
        print("normalize_launch.py requires an application identity", file=sys.stderr)
        return 2
    try:
        envelope = normalize(sys.argv[1], sys.argv[2:])
        encoded = json.dumps(envelope, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
        if len(encoded.encode("ascii")) > MAX_ENVELOPE_BYTES:
            raise LaunchError("normalized launch envelope exceeds 4096 bytes")
    except LaunchError as error:
        print(f"Launch rejected: {error}", file=sys.stderr)
        return 2
    print(encoded)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
