"""Resolve Omarchy theme inputs into the versioned semantic token contract.

This module intentionally uses only the Python standard library.  The public
entry point is bin/omarchy-theme-resolve-tokens; keeping the implementation
here makes the resolver importable by the hermetic contract tests without
inventing a second implementation.
"""

from __future__ import annotations

import argparse
import ast
import colorsys
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile
import tomllib
from typing import Any


SCHEMA_VERSION = "omarchy.design-tokens.v0"
DEFAULTS_VERSION = "omarchy.design-defaults.v0"
COLOR_RE = re.compile(r"^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")
KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")
SECTION_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
NUMBER_RE = re.compile(r"^-?(?:\d+(?:\.\d+)?|\.\d+)$")
BARE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]*$")
WIDTHS_RE = re.compile(r"^-?\d+(?:\.\d+)?(?:\s+-?\d+(?:\.\d+)?){1,3}$")


class TokenError(ValueError):
    """A user-actionable token resolution error."""


def canonical_color(value: Any, label: str) -> str:
    if not isinstance(value, str) or not COLOR_RE.fullmatch(value.strip()):
        raise TokenError(f"{label} must be #rrggbb or Qt #aarrggbb")
    return value.strip().lower()


def color_channels(value: str) -> tuple[int, int, int, int]:
    value = canonical_color(value, "color")
    raw = value[1:]
    if len(raw) == 6:
        return 255, int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16)
    return int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16), int(raw[6:8], 16)


def opaque_color(value: str) -> str:
    _, red, green, blue = color_channels(value)
    return f"#{red:02x}{green:02x}{blue:02x}"


def with_alpha(value: str, alpha: float) -> str:
    if not math.isfinite(alpha) or alpha < 0 or alpha > 1:
        raise TokenError(f"alpha must be between 0 and 1, got {alpha!r}")
    _, red, green, blue = color_channels(value)
    byte = math.floor(alpha * 255 + 0.5)
    if byte == 255:
        return f"#{red:02x}{green:02x}{blue:02x}"
    return f"#{byte:02x}{red:02x}{green:02x}{blue:02x}"


def q_round(value: float) -> int:
    """Match Math.round/QColor's positive-channel rounding."""
    return math.floor(value + 0.5)


def q_lighter(value: str, factor: float) -> str:
    """Match QColor::lighter for the opaque theme colors used by Tokens.qml."""
    _, red, green, blue = color_channels(value)
    hue, saturation, brightness = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
    brightness *= factor
    if brightness > 1:
        saturation = max(0.0, saturation - (brightness - 1))
        brightness = 1.0
    out = colorsys.hsv_to_rgb(hue, saturation, brightness)
    return "#" + "".join(f"{max(0, min(255, q_round(channel * 255))):02x}" for channel in out)


def q_darker(value: str, factor: float) -> str:
    if factor <= 0:
        raise TokenError("darkening factor must be positive")
    _, red, green, blue = color_channels(value)
    hue, saturation, brightness = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
    out = colorsys.hsv_to_rgb(hue, saturation, max(0.0, brightness / factor))
    return "#" + "".join(f"{max(0, min(255, q_round(channel * 255))):02x}" for channel in out)


def composite(foreground: str, background: str) -> tuple[float, float, float]:
    alpha, red, green, blue = color_channels(foreground)
    _, back_red, back_green, back_blue = color_channels(background)
    a = alpha / 255
    return (
        (red * a + back_red * (1 - a)) / 255,
        (green * a + back_green * (1 - a)) / 255,
        (blue * a + back_blue * (1 - a)) / 255,
    )


def compositor_hex(foreground: str, background: str) -> str:
    red, green, blue = composite(foreground, background)
    return f"#{q_round(red * 255):02x}{q_round(green * 255):02x}{q_round(blue * 255):02x}"


def relative_luminance(channels: tuple[float, float, float]) -> float:
    def linear(channel: float) -> float:
        return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

    red, green, blue = (linear(channel) for channel in channels)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def mix_opaque(start: str, target: str, amount: float) -> str:
    _, start_red, start_green, start_blue = color_channels(opaque_color(start))
    _, target_red, target_green, target_blue = color_channels(opaque_color(target))
    amount = max(0.0, min(1.0, amount))
    return "#{:02x}{:02x}{:02x}".format(
        q_round(start_red + (target_red - start_red) * amount),
        q_round(start_green + (target_green - start_green) * amount),
        q_round(start_blue + (target_blue - start_blue) * amount),
    )


def contrasting_ink(background: str) -> str:
    back = composite(opaque_color(background), "#ffffff")
    return "#000000" if relative_luminance(back) > 0.5 else "#ffffff"


def lift_contrast(foreground: str, background: str, target: str, minimum: float) -> str:
    if contrast_ratio(foreground, background) + 1e-9 >= minimum:
        return foreground
    lo = 0.0
    hi = 1.0
    best = target
    for _ in range(24):
        mid = (lo + hi) / 2
        candidate = mix_opaque(foreground, target, mid)
        if contrast_ratio(candidate, background) + 1e-9 >= minimum:
            best = candidate
            hi = mid
        else:
            lo = mid
    if contrast_ratio(best, background) + 1e-9 < minimum:
        return target
    return best


def contrast_ratio(foreground: str, background: str) -> float:
    # Token contrast is measured against the token's RGB stop. Translucent
    # glass is composited by the compositor over arbitrary wallpaper; treating
    # its alpha as white here would report dark glass as pale gray and make the
    # same locked caption pair pass/fail according to an invented backdrop.
    back = composite(opaque_color(background), "#ffffff")
    fore = composite(foreground, opaque_from_channels(back))
    first = relative_luminance(fore)
    second = relative_luminance(back)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)


def opaque_from_channels(channels: tuple[float, float, float]) -> str:
    return "#" + "".join(f"{max(0, min(255, q_round(channel * 255))):02x}" for channel in channels)


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def read_required(path: Path, label: str) -> bytes:
    try:
        return path.read_bytes()
    except OSError as error:
        raise TokenError(f"cannot read {label} {path}: {error.strerror or error}") from error


def load_defaults(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = read_required(path, "design defaults")
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise TokenError(f"invalid design defaults {path}: {error}") from error
    if not isinstance(value, dict) or value.get("schemaVersion") != DEFAULTS_VERSION:
        raise TokenError(f"design defaults {path} must use {DEFAULTS_VERSION}")
    for mode in ("dark", "light"):
        profile = value.get("chromeProfiles", {}).get(mode)
        if not isinstance(profile, dict):
            raise TokenError(f"design defaults are missing chromeProfiles.{mode}")
        for key, item in profile.items():
            if key.endswith("Alpha"):
                require_float(item, f"chromeProfiles.{mode}.{key}", 0, 1)
            else:
                canonical_color(item, f"chromeProfiles.{mode}.{key}")
    accessibility = value.get("accessibility")
    if not isinstance(accessibility, dict):
        raise TokenError("design defaults are missing accessibility")
    parse_bool(accessibility.get("largeText"), "accessibility.largeText")
    require_float(accessibility.get("textScale"), "accessibility.textScale", 1, 2)
    return value, raw


def load_colors(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = read_required(path, "colors file")
    try:
        value = tomllib.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        raise TokenError(f"invalid colors file {path}: {error}") from error
    if not isinstance(value, dict):
        raise TokenError(f"colors file {path} must contain a TOML table")
    return value, raw


def strip_inline_comment(line: str) -> str:
    quote = ""
    escaped = False
    out: list[str] = []
    for char in line:
        if escaped:
            out.append(char)
            escaped = False
            continue
        if char == "\\" and quote == '"':
            out.append(char)
            escaped = True
            continue
        if char in ("'", '"'):
            if quote == char:
                quote = ""
            elif not quote:
                quote = char
            out.append(char)
            continue
        if char == "#" and not quote:
            break
        out.append(char)
    if quote:
        raise TokenError("unterminated quoted shell value")
    return "".join(out).strip()


def parse_shell_value(raw: str, label: str) -> Any:
    if not raw:
        raise TokenError(f"{label} has no value")
    if raw[0] in ("'", '"'):
        try:
            value = ast.literal_eval(raw)
        except (SyntaxError, ValueError) as error:
            raise TokenError(f"{label} has an invalid quoted value") from error
        if not isinstance(value, str):
            raise TokenError(f"{label} must be a string, number, or boolean")
        return value
    lowered = raw.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if NUMBER_RE.fullmatch(raw):
        return float(raw) if "." in raw else int(raw)
    if BARE_RE.fullmatch(raw) or WIDTHS_RE.fullmatch(raw):
        return raw
    raise TokenError(f"{label} has unsupported shell.toml syntax: {raw!r}")


def load_shell(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = read_required(path, "shell file")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise TokenError(f"shell file {path} is not UTF-8: {error}") from error
    section = ""
    values: dict[str, Any] = {}
    for number, original in enumerate(text.splitlines(), 1):
        try:
            line = strip_inline_comment(original)
        except TokenError as error:
            raise TokenError(f"invalid shell file {path}:{number}: {error}") from error
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            candidate = line[1:-1].strip()
            if not SECTION_RE.fullmatch(candidate):
                raise TokenError(f"invalid shell section in {path}:{number}: {candidate!r}")
            section = candidate.lower()
            # Hyphenated token sections remain valid input to the existing
            # QML shell parser (which intentionally accepts no dotted table
            # names) while resolving to the nested semantic namespace here.
            if section.startswith("tokens-"):
                section = "tokens." + section[len("tokens-"):]
            continue
        if not section or "=" not in line:
            raise TokenError(f"invalid shell entry in {path}:{number}: {original.strip()!r}")
        key, raw_value = (part.strip() for part in line.split("=", 1))
        if not KEY_RE.fullmatch(key):
            raise TokenError(f"invalid shell key in {path}:{number}: {key!r}")
        full_key = f"{section}.{key.lower()}"
        if full_key in values:
            raise TokenError(f"duplicate shell key in {path}:{number}: {full_key}")
        try:
            values[full_key] = parse_shell_value(raw_value, full_key)
        except TokenError as error:
            raise TokenError(f"invalid shell file {path}:{number}: {error}") from error
    return values, raw


def require_float(value: Any, label: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool):
        raise TokenError(f"{label} must be a number between {minimum} and {maximum}")
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise TokenError(f"{label} must be a number between {minimum} and {maximum}") from error
    if not math.isfinite(number) or number < minimum or number > maximum:
        raise TokenError(f"{label} must be between {minimum} and {maximum}, got {value!r}")
    return number


def require_int(value: Any, label: str, minimum: int, maximum: int) -> int:
    number = require_float(value, label, minimum, maximum)
    if number != math.floor(number):
        raise TokenError(f"{label} must be a whole number, got {value!r}")
    return int(number)


def parse_px(value: Any, label: str, minimum: int = 0, maximum: int = 4096) -> int:
    if isinstance(value, str) and value.lower().endswith("px"):
        value = value[:-2].strip()
    return require_int(value, label, minimum, maximum)


def parse_duration(value: Any, label: str) -> int:
    if isinstance(value, str) and value.lower().endswith("ms"):
        value = value[:-2].strip()
    return require_int(value, label, 0, 60000)


def parse_bool(value: Any, label: str) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)) and value in (0, 1):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in ("true", "1", "yes", "on"):
            return True
        if lowered in ("false", "0", "no", "off"):
            return False
    raise TokenError(f"{label} must be true or false")


def palette_value(colors: dict[str, Any], label: str, keys: tuple[str, ...], fallback: str | None = None) -> str:
    for key in keys:
        if key in colors:
            return canonical_color(colors[key], f"colors.{key}")
    if fallback is not None:
        return canonical_color(fallback, label)
    raise TokenError(f"colors.toml is missing {label} ({', '.join(keys)})")


def palette_from(colors: dict[str, Any]) -> tuple[str, dict[str, str]]:
    mode_raw = colors.get("mode", "dark")
    if not isinstance(mode_raw, str) or mode_raw.lower() not in ("dark", "light"):
        raise TokenError('colors.mode must be "dark" or "light"')
    mode = mode_raw.lower()
    background = palette_value(colors, "background", ("background", "bg", "color0"))
    foreground = palette_value(colors, "foreground", ("foreground", "fg", "color7"))
    accent = palette_value(colors, "accent", ("accent", "color4", "blue"), foreground)
    muted = palette_value(colors, "muted", ("muted", "color8", "dark_foreground", "dark_fg"), foreground)
    red = palette_value(colors, "red", ("red", "color1"), accent)
    yellow = palette_value(colors, "yellow", ("yellow", "color3"), red)
    green = palette_value(colors, "green", ("green", "color2"), accent)
    selection = palette_value(colors, "selection", ("selection", "selection_background"), accent)
    bright = palette_value(colors, "bright foreground", ("bright_foreground", "bright_fg"), foreground)
    return mode, {
        "background": background,
        "foreground": foreground,
        "accent": accent,
        "muted": muted,
        "red": red,
        "yellow": yellow,
        "green": green,
        "selection": selection,
        "brightForeground": bright,
    }


def merged_shell(layers: list[dict[str, Any]]) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for layer in layers:
        merged.update(layer)
    return merged


def shell_number(shell: dict[str, Any], key: str, fallback: float, minimum: float, maximum: float) -> float:
    if key not in shell:
        return fallback
    return require_float(shell[key], key, minimum, maximum)


def shell_bool(shell: dict[str, Any], key: str, fallback: bool) -> bool:
    if key not in shell:
        return fallback
    return parse_bool(shell[key], key)


def scaled_spacing(shell: dict[str, Any], key: str, fallback: int, scale: float) -> int:
    full_key = f"spacing.{key}"
    if full_key in shell:
        return parse_px(shell[full_key], full_key)
    if fallback <= 0:
        return 0
    return max(1, q_round(fallback * scale))


def state_color(shell: dict[str, Any], palette: dict[str, str], key: str, fallback_role: str) -> str:
    value = shell.get(f"controls.{key}", shell.get(f"style.{key}", fallback_role))
    if not isinstance(value, str):
        raise TokenError(f"controls.{key} must be a palette role or color")
    return resolve_color(value, palette, f"controls.{key}")


def resolve_color(value: Any, palette: dict[str, str], label: str) -> str:
    if not isinstance(value, str):
        raise TokenError(f"{label} must be a palette role or color")
    role = value.strip()
    lowered = role.lower().replace("-", "")
    role_map = {
        "background": "background",
        "foreground": "foreground",
        "text": "foreground",
        "accent": "accent",
        "muted": "muted",
        "urgent": "red",
        "danger": "red",
        "red": "red",
        "yellow": "yellow",
        "warning": "yellow",
        "green": "green",
        "success": "green",
        "selection": "selection",
        "brightforeground": "brightForeground",
    }
    if lowered in role_map:
        return palette[role_map[lowered]]
    return canonical_color(role, label)


def set_path(payload: dict[str, Any], dotted: str, value: Any) -> None:
    parts = dotted.split(".")
    cursor: dict[str, Any] = payload
    for part in parts[:-1]:
        next_value = cursor.get(part)
        if not isinstance(next_value, dict):
            raise TokenError(f"internal token path is not an object: {dotted}")
        cursor = next_value
    if parts[-1] not in cursor:
        raise TokenError(f"unknown semantic token override: tokens.{dotted}")
    cursor[parts[-1]] = value


COLOR_OVERRIDES = {
    "surface.canvas": "surface.canvas",
    "surface.base": "surface.base",
    "surface.raised": "surface.raised",
    "surface.glass": "surface.glass",
    "surface.overlay": "surface.overlay",
    "text.primary": "text.primary",
    "text.secondary": "text.secondary",
    "text.disabled": "text.disabled",
    "accent.primary": "accent.primary",
    "accent.hover": "accent.hover",
    "accent.pressed": "accent.pressed",
    "selection.background": "selection.background",
    "selection.foreground": "selection.foreground",
    "state.success": "state.success",
    "state.warning": "state.warning",
    "state.danger": "state.danger",
    "state.info": "state.info",
    "focus.ring": "focus.ring",
    "border.subtle": "border.subtle",
    "border.strong": "border.strong",
    "chrome.glass": "chrome.glass",
    "chrome.menu": "chrome.menu",
    "chrome.hover": "chrome.hover",
    "chrome.active": "chrome.active",
    "chrome.pressed": "chrome.pressed",
    "chrome.glow": "chrome.glow",
    "chrome.start": "chrome.start",
    "chrome.edge": "chrome.edge",
    "caption.bar": "caption.bar",
    "caption.text": "caption.text",
    "caption.close-background": "caption.close.background",
    "caption.close-foreground": "caption.close.foreground",
    "caption.maximize-background": "caption.maximize.background",
    "caption.maximize-foreground": "caption.maximize.foreground",
    "caption.minimize-background": "caption.minimize.background",
    "caption.minimize-foreground": "caption.minimize.foreground",
    "effects.shadow-color": "effects.shadow.color",
}

PX_OVERRIDES = {
    "focus.ring-width": "focus.ringWidthPx",
    "focus.ring-offset": "focus.ringOffsetPx",
    "radii.small": "radii.small",
    "radii.medium": "radii.medium",
    "radii.large": "radii.large",
    "elevation.none": "elevation.none",
    "elevation.low": "elevation.low",
    "elevation.medium": "elevation.medium",
    "elevation.high": "elevation.high",
    "effects.blur-radius": "effects.blur.radiusPx",
    "effects.blur-passes": "effects.blur.passes",
    "effects.shadow-radius": "effects.shadow.radiusPx",
    "effects.shadow-offset-x": "effects.shadow.offsetXPx",
    "effects.shadow-offset-y": "effects.shadow.offsetYPx",
}

BOOL_OVERRIDES = {
    "effects.blur-enabled": "effects.blur.enabled",
    "effects.shadow-enabled": "effects.shadow.enabled",
    "accessibility.reduced-motion": "accessibility.reducedMotion",
    "accessibility.high-contrast": "accessibility.highContrast",
    "accessibility.large-text": "accessibility.largeText",
}


def apply_explicit_overrides(payload: dict[str, Any], shell: dict[str, Any], palette: dict[str, str]) -> None:
    known: set[str] = set()
    for source, target in COLOR_OVERRIDES.items():
        full = f"tokens.{source}"
        known.add(full)
        if full in shell:
            set_path(payload, target, resolve_color(shell[full], palette, full))
    for source, target in PX_OVERRIDES.items():
        full = f"tokens.{source}"
        known.add(full)
        if full in shell:
            minimum = -4096 if source.endswith(("offset-x", "offset-y")) else 0
            set_path(payload, target, parse_px(shell[full], full, minimum))
    for source, target in BOOL_OVERRIDES.items():
        full = f"tokens.{source}"
        known.add(full)
        if full in shell:
            set_path(payload, target, parse_bool(shell[full], full))

    for name in payload["typography"]["sizesPx"]:
        full = f"tokens.typography.{name}"
        known.add(full)
        if full in shell:
            payload["typography"]["sizesPx"][name] = parse_px(shell[full], full, 1)
    for name in payload["icons"]["sizesPx"]:
        full = f"tokens.icons.{name}"
        known.add(full)
        if full in shell:
            payload["icons"]["sizesPx"][name] = parse_px(shell[full], full, 1)
    for name in payload["hitTargets"]:
        full = f"tokens.hit-targets.{name}"
        known.add(full)
        if full in shell:
            payload["hitTargets"][name] = parse_px(shell[full], full, 1)
    for name in payload["components"]:
        kebab = re.sub(r"(?<!^)(?=[A-Z])", "-", name).lower()
        full = f"tokens.components.{kebab}"
        known.add(full)
        if full in shell:
            payload["components"][name] = parse_px(shell[full], full)

    for name, target in (("fast", "fastMs"), ("normal", "normalMs"), ("slow", "slowMs")):
        full = f"tokens.motion.{name}"
        known.add(full)
        if full in shell:
            payload["motion"][target] = parse_duration(shell[full], full)
    known.add("tokens.motion.easing")
    if "tokens.motion.easing" in shell:
        easing = shell["tokens.motion.easing"]
        if not isinstance(easing, str) or not easing.strip() or len(easing) > 64:
            raise TokenError("tokens.motion.easing must be a non-empty string of at most 64 characters")
        payload["motion"]["easing"] = easing.strip()

    known.update(("tokens.density.mode", "tokens.density.scale", "tokens.accessibility.text-scale", "tokens.typography.family", "tokens.icons.family"))
    if "tokens.density.mode" in shell:
        mode = shell["tokens.density.mode"]
        if mode not in ("compact", "comfortable", "touch"):
            raise TokenError("tokens.density.mode must be compact, comfortable, or touch")
        payload["density"]["mode"] = mode
    if "tokens.density.scale" in shell:
        payload["density"]["scale"] = require_float(shell["tokens.density.scale"], "tokens.density.scale", 0.5, 3)
    if "tokens.accessibility.text-scale" in shell:
        payload["accessibility"]["textScale"] = require_float(
            shell["tokens.accessibility.text-scale"], "tokens.accessibility.text-scale", 1, 2
        )
    for full, group in (("tokens.typography.family", "typography"), ("tokens.icons.family", "icons")):
        if full in shell:
            family = shell[full]
            if not isinstance(family, str) or not family.strip() or len(family) > 256:
                raise TokenError(f"{full} must be a non-empty string of at most 256 characters")
            payload[group]["family"] = family.strip()

    for full in shell:
        if full.startswith("tokens.") and full not in known:
            raise TokenError(f"unknown semantic token override: {full}")

    reduced = payload["accessibility"]["reducedMotion"]
    payload["motion"]["reduced"] = reduced
    if reduced:
        payload["motion"]["fastMs"] = 0
        payload["motion"]["normalMs"] = 0
        payload["motion"]["slowMs"] = 0
    if payload["accessibility"]["highContrast"]:
        payload["border"]["strong"] = payload["text"]["primary"]
        payload["focus"]["ringWidthPx"] = max(2, payload["focus"]["ringWidthPx"])
        payload["text"]["secondary"] = lift_contrast(
            payload["text"]["secondary"],
            payload["surface"]["base"],
            payload["text"]["primary"],
            4.5,
        )
        payload["selection"]["foreground"] = lift_contrast(
            payload["selection"]["foreground"],
            payload["selection"]["background"],
            contrasting_ink(payload["selection"]["background"]),
            4.5,
        )


def build_payload(
    colors: dict[str, Any],
    colors_raw: bytes,
    shell_layers: list[dict[str, Any]],
    shell_raw: list[bytes],
    defaults: dict[str, Any],
    defaults_raw: bytes,
    corner_radius: int,
) -> dict[str, Any]:
    mode, palette = palette_from(colors)
    shell = merged_shell(shell_layers)
    base_size = require_int(shell.get("font.base-size", 12), "font.base-size", 1, 512)
    spacing_scale = shell_number(shell, "spacing.scale", 1.0, 0, 10)
    spacing_with_font = shell_bool(shell, "spacing.scale-with-font", True)
    effective_spacing = spacing_scale * (base_size / 12 if spacing_with_font else 1)
    bar_with_font = shell_bool(shell, "bar.scale-with-font", True)
    bar_scale = base_size / 12 if bar_with_font else 1

    def font_size(key: str, multiplier: float) -> int:
        full = f"font.{key}"
        if full in shell:
            return require_int(shell[full], full, 1, 512)
        return max(1, q_round(base_size * multiplier))

    sizes = {
        "caption": font_size("caption", 0.833),
        "bodySmall": font_size("body-small", 0.917),
        "body": font_size("body", 1.0),
        "subtitle": font_size("subtitle", 1.083),
        "title": font_size("title", 1.167),
        "heading": font_size("heading", 1.333),
        "display": font_size("display", 2.0),
        "displayLarge": font_size("display-large", 2.333),
    }
    icon_sizes = {
        "small": font_size("icon-small", sizes["bodySmall"] / base_size),
        "default": font_size("icon", sizes["title"] / base_size),
        "large": font_size("icon-large", 1.5),
    }
    components = {
        "controlGap": scaled_spacing(shell, "control-gap", 8, effective_spacing),
        "controlPaddingX": scaled_spacing(shell, "control-padding-x", 10, effective_spacing),
        "controlPaddingY": scaled_spacing(shell, "control-padding-y", 6, effective_spacing),
        "inputPaddingY": scaled_spacing(shell, "input-padding-y", 7, effective_spacing),
        "controlHeight": scaled_spacing(shell, "control-height", 28, effective_spacing),
        "popupRowHeight": scaled_spacing(shell, "popup-row-height", 28, effective_spacing),
        "rowGap": scaled_spacing(shell, "row-gap", 8, effective_spacing),
        "rowPaddingX": scaled_spacing(shell, "row-padding-x", 12, effective_spacing),
        "labelGap": scaled_spacing(shell, "label-gap", 4, effective_spacing),
        "panelGap": scaled_spacing(shell, "panel-gap", 14, effective_spacing),
        "panelPadding": scaled_spacing(shell, "panel-padding", 18, effective_spacing),
        "popupPadding": scaled_spacing(shell, "popup-padding", 14, effective_spacing),
        "dropdownWidth": scaled_spacing(shell, "dropdown-width", 240, effective_spacing),
        "searchableDropdownWidth": scaled_spacing(shell, "searchable-dropdown-width", 260, effective_spacing),
        "numberFieldWidth": scaled_spacing(shell, "number-field-width", 120, effective_spacing),
        "searchablePopupMinHeight": scaled_spacing(shell, "searchable-popup-min-height", 220, effective_spacing),
    }
    bar_height_base = require_float(shell.get("bar.size-horizontal", 26), "bar.size-horizontal", 1, 4096)
    bar_height = max(1, q_round(bar_height_base * bar_scale))
    components["taskbarHeight"] = max(48, bar_height + 22)

    profile = defaults["chromeProfiles"][mode]
    interaction = defaults["chromeInteraction"]
    glass = with_alpha(profile["glass"], require_float(profile["glassAlpha"], "glassAlpha", 0, 1))
    menu = with_alpha(profile["glass"], require_float(profile["menuAlpha"], "menuAlpha", 0, 1))
    caption_metrics = defaults["captionMetricsPx"]
    components.update({
        "captionHeight": require_int(caption_metrics["height"], "captionMetricsPx.height", 1, 4096),
        "captionButtonSize": require_int(caption_metrics["buttonSize"], "captionMetricsPx.buttonSize", 1, 4096),
        "captionButtonPadding": require_int(caption_metrics["buttonPadding"], "captionMetricsPx.buttonPadding", 0, 4096),
        "captionHorizontalPadding": require_int(caption_metrics["horizontalPadding"], "captionMetricsPx.horizontalPadding", 0, 4096),
    })

    focus_color = state_color(shell, palette, "focus-color", "foreground")
    focus_alpha = shell_number(shell, "controls.focus-border-alpha", 0.25, 0, 1)
    focus_width = require_int(shell.get("controls.focus-border-width", defaults["focus"]["ringWidthPx"]), "controls.focus-border-width", 0, 64)
    density_mode = shell.get("tokens.density.mode", defaults["density"]["default"])
    if density_mode not in defaults["density"]["scales"]:
        raise TokenError("tokens.density.mode must be compact, comfortable, or touch")
    accessibility_defaults = defaults["accessibility"]
    large_text = shell_bool(
        shell,
        "tokens.accessibility.large-text",
        parse_bool(accessibility_defaults["largeText"], "accessibility.largeText"),
    )
    large_text_scale = require_float(accessibility_defaults["textScale"], "accessibility.textScale", 1, 2)
    density_scale = defaults["density"]["scales"][density_mode]

    motion = defaults["motion"]
    effects = defaults["effects"]
    payload: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "mode": mode,
        "source": {
            "colorsSha256": digest(colors_raw),
            "shellSha256": [digest(raw) for raw in shell_raw],
            "defaultsSha256": digest(defaults_raw),
        },
        "surface": {
            "canvas": palette["background"],
            "base": q_lighter(palette["background"], 1.08),
            "raised": q_lighter(palette["background"], 1.16),
            "glass": with_alpha(palette["background"], 0.82),
            "overlay": with_alpha(palette["background"], 0.6),
        },
        "text": {
            "primary": palette["foreground"],
            "secondary": palette["muted"],
            "disabled": with_alpha(palette["foreground"], 0.4),
        },
        "accent": {
            "primary": palette["accent"],
            "hover": q_lighter(palette["accent"], 1.1),
            "pressed": q_darker(palette["accent"], 1.1),
        },
        "selection": {
            "background": palette["selection"],
            "foreground": palette["brightForeground"],
        },
        "state": {
            "success": palette["accent"],
            "warning": palette["red"],
            "danger": palette["red"],
            "info": palette["accent"],
        },
        "focus": {
            "ring": with_alpha(focus_color, focus_alpha),
            "ringWidthPx": focus_width,
            "ringOffsetPx": require_int(defaults["focus"]["ringOffsetPx"], "focus.ringOffsetPx", 0, 64),
        },
        "border": {
            "subtle": with_alpha(palette["foreground"], 0.15),
            "strong": with_alpha(palette["foreground"], 0.3),
        },
        "chrome": {
            "glass": glass,
            "menu": menu,
            "hover": with_alpha(interaction["color"], require_float(interaction["hoverAlpha"], "hoverAlpha", 0, 1)),
            "active": with_alpha(interaction["color"], require_float(interaction["activeAlpha"], "activeAlpha", 0, 1)),
            "pressed": with_alpha(interaction["color"], require_float(interaction["pressedAlpha"], "pressedAlpha", 0, 1)),
            "glow": canonical_color(profile["glow"], "chrome.glow"),
            "start": canonical_color(profile["start"], "chrome.start"),
            "edge": canonical_color(profile["edge"], "chrome.edge"),
        },
        "caption": {
            "bar": glass,
            "text": canonical_color(profile["text"], "caption.text"),
            "close": {
                "background": canonical_color(profile["closeBackground"], "caption.close.background"),
                "foreground": canonical_color(profile["closeForeground"], "caption.close.foreground"),
            },
            "maximize": {
                "background": canonical_color(profile["maximizeBackground"], "caption.maximize.background"),
                "foreground": canonical_color(profile["maximizeForeground"], "caption.maximize.foreground"),
            },
            "minimize": {
                "background": canonical_color(profile["minimizeBackground"], "caption.minimize.background"),
                "foreground": canonical_color(profile["minimizeForeground"], "caption.minimize.foreground"),
            },
        },
        "typography": {
            "family": "Liberation Sans",
            "sizesPx": sizes,
            "weights": {"regular": 400, "medium": 500, "semibold": 600, "bold": 700},
        },
        "icons": {"family": "monospace", "sizesPx": icon_sizes},
        "hitTargets": {
            key: require_int(value, f"hitTargetsPx.{key}", 1, 4096)
            for key, value in defaults["hitTargetsPx"].items()
        },
        "density": {"mode": density_mode, "scale": density_scale},
        "radii": {
            "small": max(4, q_round(corner_radius * 0.5)),
            "medium": corner_radius,
            "large": q_round(corner_radius * 1.5),
        },
        "elevation": {
            key: require_int(value, f"elevationPx.{key}", 0, 4096)
            for key, value in defaults["elevationPx"].items()
        },
        "effects": {
            "blur": {
                "enabled": parse_bool(effects["blurEnabled"], "effects.blurEnabled"),
                "radiusPx": require_int(effects["blurRadiusPx"], "effects.blurRadiusPx", 0, 4096),
                "passes": require_int(effects["blurPasses"], "effects.blurPasses", 0, 16),
            },
            "shadow": {
                "enabled": parse_bool(effects["shadowEnabled"], "effects.shadowEnabled"),
                "color": canonical_color(effects["shadowColor"], "effects.shadowColor"),
                "radiusPx": require_int(effects["shadowRadiusPx"], "effects.shadowRadiusPx", 0, 4096),
                "offsetXPx": require_int(effects["shadowOffsetXPx"], "effects.shadowOffsetXPx", -4096, 4096),
                "offsetYPx": require_int(effects["shadowOffsetYPx"], "effects.shadowOffsetYPx", -4096, 4096),
            },
        },
        "motion": {
            "fastMs": require_int(motion["fastMs"], "motion.fastMs", 0, 60000),
            "normalMs": require_int(motion["normalMs"], "motion.normalMs", 0, 60000),
            "slowMs": require_int(motion["slowMs"], "motion.slowMs", 0, 60000),
            "easing": str(motion["easing"]),
            "reduced": False,
        },
        "accessibility": {
            "reducedMotion": shell_bool(shell, "tokens.accessibility.reduced-motion", False),
            "highContrast": shell_bool(shell, "tokens.accessibility.high-contrast", False),
            "largeText": large_text,
            "textScale": shell_number(shell, "tokens.accessibility.text-scale", large_text_scale, 1, 2)
            if large_text else 1.0,
            "minimumTextContrast": 4.5,
            "minimumLargeTextContrast": 3.0,
            "contrast": {},
        },
        "components": components,
    }
    apply_explicit_overrides(payload, shell, palette)
    annotate_contrast(payload)
    validate_payload(payload)
    return payload


def annotate_contrast(payload: dict[str, Any]) -> None:
    caption = payload["caption"]
    payload["accessibility"]["contrast"] = {
        "primaryText": round(contrast_ratio(payload["text"]["primary"], payload["surface"]["base"]), 3),
        "secondaryText": round(contrast_ratio(payload["text"]["secondary"], payload["surface"]["base"]), 3),
        "selectionText": round(contrast_ratio(payload["selection"]["foreground"], payload["selection"]["background"]), 3),
        "captionText": round(contrast_ratio(caption["text"], caption["bar"]), 3),
        "captionClose": round(contrast_ratio(caption["close"]["foreground"], caption["close"]["background"]), 3),
        "captionMaximize": round(contrast_ratio(caption["maximize"]["foreground"], caption["maximize"]["background"]), 3),
        "captionMinimize": round(contrast_ratio(caption["minimize"]["foreground"], caption["minimize"]["background"]), 3),
    }


def validate_payload(payload: dict[str, Any]) -> None:
    if payload.get("schemaVersion") != SCHEMA_VERSION:
        raise TokenError(f"payload must use {SCHEMA_VERSION}")
    required_groups = (
        "surface", "text", "accent", "selection", "state", "focus", "border", "chrome", "caption",
        "typography", "icons", "hitTargets", "density", "radii", "elevation", "effects", "motion",
        "accessibility", "components",
    )
    for group in required_groups:
        if not isinstance(payload.get(group), dict):
            raise TokenError(f"resolved payload is missing object {group}")

    def walk(value: Any, path: str) -> None:
        if isinstance(value, dict):
            for key, item in value.items():
                walk(item, f"{path}.{key}" if path else key)
        elif isinstance(value, list):
            for index, item in enumerate(value):
                walk(item, f"{path}[{index}]")
        elif path.split(".")[-1] in {
            "canvas", "base", "raised", "glass", "overlay", "primary", "secondary", "disabled",
            "hover", "pressed", "background", "foreground", "success", "warning", "danger", "info",
            "ring", "subtle", "strong", "menu", "active", "glow", "start", "edge", "bar", "text", "color",
        } and (path.startswith(("surface.", "text.", "accent.", "selection.", "state.", "focus.", "border.", "chrome.", "caption.", "effects.shadow."))):
            canonical_color(value, path)

    walk(payload, "")

    for group in ("hitTargets", "radii", "elevation", "components"):
        for key, value in payload[group].items():
            require_int(value, f"{group}.{key}", 0, 4096)
    for key, value in payload["typography"]["sizesPx"].items():
        require_int(value, f"typography.sizesPx.{key}", 1, 4096)
    for key, value in payload["icons"]["sizesPx"].items():
        require_int(value, f"icons.sizesPx.{key}", 1, 4096)
    for key in ("fastMs", "normalMs", "slowMs"):
        require_int(payload["motion"][key], f"motion.{key}", 0, 60000)
    require_float(payload["density"]["scale"], "density.scale", 0.5, 3)
    require_float(payload["accessibility"]["textScale"], "accessibility.textScale", 1, 2)
    if payload["density"]["mode"] not in ("compact", "comfortable", "touch"):
        raise TokenError("density.mode must be compact, comfortable, or touch")

    contrast = payload["accessibility"].get("contrast")
    if not isinstance(contrast, dict):
        raise TokenError("accessibility.contrast must contain measured ratios")
    enforced = {"primaryText": 4.5, "captionText": 4.5, "captionClose": 3.0, "captionMaximize": 3.0, "captionMinimize": 3.0}
    if payload["accessibility"]["highContrast"]:
        enforced.update({"secondaryText": 4.5, "selectionText": 4.5})
    for label, minimum in enforced.items():
        ratio = require_float(contrast.get(label), f"accessibility.contrast.{label}", 1, 21)
        if ratio + 1e-9 < minimum:
            raise TokenError(f"{label} contrast is {ratio:.2f}:1; minimum is {minimum:.1f}:1")


def legacy_chrome_adapter(payload: dict[str, Any]) -> dict[str, str]:
    validate_payload(payload)
    alpha, red, green, blue = color_channels(payload["chrome"]["glass"])
    return {
        "_readme": "Generated compatibility adapter. Source of truth: omarchy.design-tokens.v0.",
        "_schemaVersion": "omarchy.chrome-adapter.v0",
        "_sourceSchemaVersion": payload["schemaVersion"],
        "_mode": payload["mode"],
        "glassRed": str(red),
        "glassGreen": str(green),
        "glassBlue": str(blue),
        "glassAlphaPct": str(q_round(alpha / 255 * 100)),
        "hyprbarsTextHex": opaque_color(payload["caption"]["text"]),
        "chromeGlowHex": opaque_color(payload["chrome"]["glow"]),
        "chromeStartHex": opaque_color(payload["chrome"]["start"]),
        "chromeEdgeHex": payload["chrome"]["edge"],
        "captionCloseBgHex": opaque_color(payload["caption"]["close"]["background"]),
        "captionCloseFgHex": opaque_color(payload["caption"]["close"]["foreground"]),
        "captionMaxBgHex": opaque_color(payload["caption"]["maximize"]["background"]),
        "captionMaxFgHex": opaque_color(payload["caption"]["maximize"]["foreground"]),
        "captionMinBgHex": opaque_color(payload["caption"]["minimize"]["background"]),
        "captionMinFgHex": opaque_color(payload["caption"]["minimize"]["foreground"]),
        "borderActiveHex": compositor_hex(payload["border"]["strong"], payload["surface"]["canvas"]),
        "borderInactiveHex": compositor_hex(payload["border"]["subtle"], payload["surface"]["canvas"]),
    }


def serialized(value: Any) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False, sort_keys=False) + "\n").encode("utf-8")


def stage_atomic(path: Path, content: bytes) -> tuple[Path | None, bool]:
    try:
        if path.read_bytes() == content:
            return None, False
    except FileNotFoundError:
        pass
    except OSError as error:
        raise TokenError(f"cannot read existing output {path}: {error.strerror or error}") from error
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        handle, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        with os.fdopen(handle, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        return Path(temporary), True
    except OSError as error:
        raise TokenError(f"cannot stage output {path}: {error.strerror or error}") from error


def write_outputs(outputs: list[tuple[Path, bytes]]) -> bool:
    paths = [path.resolve(strict=False) for path, _ in outputs]
    if len(paths) != len(set(paths)):
        raise TokenError("resolved and compatibility outputs must use different paths")
    staged: list[tuple[Path, Path]] = []
    changed = False
    try:
        for path, content in outputs:
            temporary, item_changed = stage_atomic(path, content)
            changed = changed or item_changed
            if temporary is not None:
                staged.append((path, temporary))
        for path, temporary in staged:
            os.replace(temporary, path)
            try:
                directory_fd = os.open(path.parent, os.O_RDONLY)
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
            except OSError:
                pass
    except OSError as error:
        raise TokenError(f"cannot publish token output: {error.strerror or error}") from error
    finally:
        for _, temporary in staged:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
    return changed


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description="Resolve Omarchy semantic design tokens")
    source = value.add_mutually_exclusive_group(required=True)
    source.add_argument("--active", action="store_true", help="resolve the active theme and user shell override")
    source.add_argument("--colors", type=Path, help="colors.toml input")
    value.add_argument("--shell", action="append", type=Path, default=[], help="shell.toml layer; repeat in precedence order")
    value.add_argument("--corner-radius", type=int, default=0, help="resolved compositor corner radius in px")
    value.add_argument("--output", type=Path, help="resolved JSON output (required unless --stdout)")
    value.add_argument("--chrome-output", type=Path, help="legacy chrome adapter output")
    value.add_argument("--stdout", action="store_true", help="write the resolved payload to stdout")
    return value


def active_paths() -> tuple[Path, list[Path], Path, Path]:
    home = os.environ.get("HOME", "")
    if not home:
        raise TokenError("HOME is required for --active")
    current = Path(home) / ".local/state/omarchy/current"
    theme = current / "theme"
    shells = [path for path in (theme / "shell.toml", Path(home) / ".config/omarchy/shell.toml") if path.is_file()]
    return theme / "colors.toml", shells, current / "design-tokens-v0.json", current / "chrome-tokens-v0.json"


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.corner_radius < 0 or args.corner_radius > 4096:
            raise TokenError("--corner-radius must be between 0 and 4096")
        if args.active:
            colors_path, active_shells, default_output, default_chrome = active_paths()
            if args.shell:
                raise TokenError("--shell cannot be combined with --active")
            shell_paths = active_shells
            output_path = args.output if args.output is not None else (None if args.stdout else default_output)
            chrome_output = args.chrome_output if args.chrome_output is not None else (None if args.stdout else default_chrome)
        else:
            colors_path = args.colors
            shell_paths = args.shell
            output_path = args.output
            chrome_output = args.chrome_output
        if not args.stdout and output_path is None:
            raise TokenError("--output is required unless --stdout is used")

        root = Path(os.environ.get("OMARCHY_PATH", Path(__file__).resolve().parents[3]))
        defaults, defaults_raw = load_defaults(root / "default/ultimate/design-system/defaults-v0.json")
        colors, colors_raw = load_colors(colors_path)
        shell_layers: list[dict[str, Any]] = []
        shell_raw: list[bytes] = []
        for shell_path in shell_paths:
            values, raw = load_shell(shell_path)
            shell_layers.append(values)
            shell_raw.append(raw)
        payload = build_payload(colors, colors_raw, shell_layers, shell_raw, defaults, defaults_raw, args.corner_radius)
        payload_bytes = serialized(payload)
        adapter_bytes = serialized(legacy_chrome_adapter(payload))

        outputs: list[tuple[Path, bytes]] = []
        if output_path is not None:
            outputs.append((output_path, payload_bytes))
        if chrome_output is not None:
            outputs.append((chrome_output, adapter_bytes))
        changed = write_outputs(outputs) if outputs else False
        if args.stdout:
            sys.stdout.buffer.write(payload_bytes)
        elif changed:
            print("changed")
        else:
            print("unchanged")
        return 0
    except TokenError as error:
        print(f"omarchy-theme-resolve-tokens: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
