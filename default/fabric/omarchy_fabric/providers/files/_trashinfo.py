"""Parse a Freedesktop Trash Info Path= line into an absolute original path."""

from __future__ import annotations

from urllib.parse import unquote


def parse_trash_info_path(text: str) -> str:
    path = ""
    for line in text.splitlines():
        if line.startswith("Path="):
            path = unquote(line[len("Path="):])
    if not path.startswith("/") or "\x00" in path:
        raise ValueError("The Trash record does not name an absolute original path.")
    return path
