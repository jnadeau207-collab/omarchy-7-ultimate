#!/usr/bin/python3
import json
import os
import pathlib


def desktop_dirs() -> list[pathlib.Path]:
    dirs = []
    omarchy = os.environ.get("OMARCHY_PATH")
    if omarchy:
        dirs.append(pathlib.Path(omarchy) / "applications")
    dirs.extend([
        pathlib.Path.home() / ".local" / "share" / "applications",
        pathlib.Path("/usr/share/applications"),
    ])
    extra = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    for raw in extra.split(":"):
        if raw:
            dirs.append(pathlib.Path(raw) / "applications")
    seen = set()
    unique = []
    for path in dirs:
        resolved = str(path)
        if resolved in seen:
            continue
        seen.add(resolved)
        unique.append(path)
    return unique


def normalize_id(name: str) -> str:
    value = name[:-8] if name.endswith(".desktop") else name
    return value


def parse_actions(text: str) -> list[dict[str, str]]:
    wanted: list[str] = []
    sections: dict[str, dict[str, str]] = {}
    current = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, {})
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        sections.setdefault(current, {})[key] = value
        if current == "Desktop Entry" and key == "Actions":
            wanted = [part for part in value.split(";") if part]
    out = []
    seen = set()
    for action_id in wanted:
        section = sections.get(f"Desktop Action {action_id}", {})
        name = (section.get("Name") or action_id).strip()
        command = (section.get("Exec") or "").strip()
        if not command or not name or action_id in seen:
            continue
        seen.add(action_id)
        out.append({"id": action_id, "name": name, "command": command, "kind": "desktop-action"})
    return out


def main() -> None:
    index = {}
    for directory in desktop_dirs():
        if not directory.is_dir():
            continue
        for path in directory.glob("*.desktop"):
            desktop_id = normalize_id(path.name)
            if index.get(desktop_id):
                continue
            try:
                actions = parse_actions(path.read_text(encoding="utf-8"))
            except OSError:
                continue
            if actions:
                index[desktop_id] = actions
    if "google-chrome" not in index:
        for alias in ("google-chrome-stable", "chromium"):
            if index.get(alias):
                index["google-chrome"] = index[alias]
                break
    print(json.dumps(index, separators=(",", ":")))


if __name__ == "__main__":
    main()
