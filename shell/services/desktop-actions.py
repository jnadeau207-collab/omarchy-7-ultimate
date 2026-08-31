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


CHROME_FAMILY = {
    "chromium",
    "google-chrome",
    "google-chrome-beta",
    "google-chrome-stable",
    "google-chrome-unstable",
}


def parse_desktop(text: str) -> tuple[list[dict[str, str]], str]:
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
    exec_line = (sections.get("Desktop Entry") or {}).get("Exec", "").strip()
    return out, exec_line


def parse_actions(text: str) -> list[dict[str, str]]:
    return parse_desktop(text)[0]


def strip_exec_codes(command: str) -> str:
    parts = []
    for part in command.split():
        if part.startswith("%") and len(part) <= 2:
            continue
        parts.append(part)
    return " ".join(parts)


def is_chrome_family(desktop_id: str) -> bool:
    value = desktop_id.lower()
    return value in CHROME_FAMILY or value.startswith("google-chrome")


def synthesize_chrome_actions(exec_line: str) -> list[dict[str, str]]:
    base = strip_exec_codes(exec_line)
    if not base:
        return []
    tokens = f" {base} "
    private = base if " --incognito " in tokens or base.endswith(" --incognito") else f"{base} --incognito"
    return [
        {"id": "new-window", "name": "New Window", "command": base, "kind": "desktop-action"},
        {"id": "new-private-window", "name": "New Incognito Window", "command": private, "kind": "desktop-action"},
    ]


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
                actions, exec_line = parse_desktop(path.read_text(encoding="utf-8"))
            except OSError:
                continue
            if not actions and is_chrome_family(desktop_id):
                actions = synthesize_chrome_actions(exec_line)
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
