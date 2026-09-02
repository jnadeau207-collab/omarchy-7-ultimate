#!/usr/bin/python3
import json
import os
import pathlib

def desktop_dir() -> pathlib.Path:
    home = pathlib.Path.home()
    fallback = home / "Desktop"
    candidates = []
    configured = os.environ.get("XDG_DESKTOP_DIR", "").strip()
    if configured:
        candidates.append(pathlib.Path(configured))
    user_dirs = home / ".config" / "user-dirs.dirs"
    if user_dirs.is_file():
        for line in user_dirs.read_text(encoding="utf-8").splitlines():
            if line.startswith("XDG_DESKTOP_DIR="):
                raw = line.split("=", 1)[1].strip().strip('"')
                raw = raw.replace("$HOME", str(home))
                if raw:
                    candidates.append(pathlib.Path(raw))
    candidates.append(fallback)
    for path in candidates:
        try:
            resolved = path.expanduser().resolve()
        except OSError:
            continue
        if resolved == home.resolve():
            continue
        return resolved
    return fallback

def desktop_fields(path: pathlib.Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    if path.suffix != ".desktop":
        return fields
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if "=" not in line or line.startswith("#") or line.startswith("["):
                continue
            key, value = line.split("=", 1)
            if key in {"Name", "Icon", "Exec"} and key not in fields:
                fields[key] = value.strip()
    except OSError:
        return {}
    return fields

def desktop_command(exec_line: str) -> list[str]:
    command = []
    for part in exec_line.split():
        if part.startswith("%"):
            continue
        command.append(part)
    return command

def desktop_icon(path: pathlib.Path) -> str:
    icon = desktop_fields(path).get("Icon", "")
    if icon:
        return icon
    if path.suffix == ".desktop":
        return "application-x-executable"
    if path.is_dir():
        return "folder"
    return "text-x-generic"

def desktop_name(path: pathlib.Path) -> str:
    name = desktop_fields(path).get("Name", "")
    if name:
        return name
    return path.name

def main() -> None:
    root = desktop_dir()
    if not root.exists() and root == pathlib.Path.home() / "Desktop":
        root.mkdir(parents=True, exist_ok=True)
    items = []
    if root.is_dir():
        for path in sorted(root.iterdir(), key=lambda p: p.name.casefold()):
            if path.name.startswith("."):
                continue
            fields = desktop_fields(path)
            command = desktop_command(fields.get("Exec", "")) if fields.get("Exec") else []
            items.append({
                "name": desktop_name(path),
                "path": str(path),
                "icon": desktop_icon(path),
                "kind": "application" if path.suffix == ".desktop" else "directory" if path.is_dir() else "file",
                "command": command,
            })
    print(json.dumps({"directory": str(root), "items": items}, separators=(",", ":")))

if __name__ == "__main__":
    main()
