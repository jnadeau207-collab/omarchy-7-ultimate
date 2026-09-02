"""Freedesktop .trashinfo record format shared by the session helper and the Files adapter."""

from __future__ import annotations

import pathlib
import urllib.parse

from omarchy_fabric.providers.files._trashinfo import parse_trash_info_path

__all__ = ["parse_trash_info_path", "trash_info_document"]


def trash_info_document(original: pathlib.Path, deleted_at: str) -> str:
    quoted = urllib.parse.quote(str(original), safe="/")
    return f"[Trash Info]\nPath={quoted}\nDeletionDate={deleted_at}\n"
