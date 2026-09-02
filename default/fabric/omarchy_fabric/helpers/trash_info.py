"""Freedesktop .trashinfo record format shared by the session helper and the Files adapter."""

from __future__ import annotations

import os
import pathlib
import urllib.parse

__all__ = ["parse_trash_info_path", "trash_info_document"]


def trash_info_document(original: pathlib.Path, deleted_at: str) -> str:
    quoted = urllib.parse.quote(str(original), safe="/")
    return f"[Trash Info]\nPath={quoted}\nDeletionDate={deleted_at}\n"


def parse_trash_info_path(text: str) -> str:
    path = ""
    for line in text.splitlines():
        if line.startswith("Path="):
            path = urllib.parse.unquote(line[len("Path="):])
    if not os.path.isabs(path) or "\x00" in path:
        raise ValueError("The Trash record does not name an absolute original path.")
    return path
