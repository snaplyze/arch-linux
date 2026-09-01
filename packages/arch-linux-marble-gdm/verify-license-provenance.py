#!/usr/bin/env python3

"""Verify the exact GNOME-to-Marble asset and license-notice provenance."""

from __future__ import annotations

import colorsys
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import NoReturn


SVG = "{http://www.w3.org/2000/svg}"
EXPECTED_CALENDAR_GEOMETRY = ("32", "32", "16", "28", "2")
MARBLE_SELECTED_INPUT_DIGEST = "425884874e3bc1cc8f8cca6185b77f09b53e3082fe5a4545093cf01d52227226"
GNOME_SELECTED_INPUT_DIGEST = "228a1f891154b2bd8bde1cb0e69032b07870290c690ec3af02830d5d8fc8b267"
BASE_CSS = (
    "apps.css",
    "controls.css",
    "datemenu.css",
    "entries.css",
    "keyboard.css",
    "loginlock.css",
    "lookingglass.css",
    "messages.css",
    "modal.css",
    "osd.css",
    "overview.css",
    "panel.css",
    "popovers.css",
    "quick-settings.css",
    "screenshot.css",
    "search.css",
)
VERSION_47_CSS = ("buttons.css", "checkbox.css", "toggle.css")
VERSION_48_CSS = ("messages.css",)
MARBLE_SVGS = (
    "calendar-event-disabled.svg",
    "calendar-event-today.svg",
    "calendar-event.svg",
    "workspace-placeholder.svg",
)
FILLED_SUBSTITUTIONS = (
    ("BUTTON-COLOR", "ACCENT-FILLED-COLOR"),
    ("BUTTON_HOVER", "ACCENT-FILLED_HOVER"),
    ("BUTTON_ACTIVE", "ACCENT-FILLED_ACTIVE"),
    ("BUTTON_INSENSITIVE", "ACCENT-FILLED_INSENSITIVE"),
    ("BUTTON-TEXT-COLOR", "TEXT-BLACK-COLOR"),
    ("BUTTON-TEXT_SECONDARY", "TEXT-BLACK_SECONDARY"),
)
MARBLE_RELEASE_SHA256 = {
    "calendar-event-disabled.svg": "af5447861215e4a01617ce2e9dd329f9fc029ecf60a5b067d0abdd46b209b0c8",
    "calendar-event-today.svg": "a3250a2d1bf8c1cde2a3130b6d4343029f0ec7a88d54526117a6911c998c9827",
    "calendar-event.svg": "3bed96bb050cb646d77f2cd12427249b4aa10fb4d32b1e9f9a8851079e5d8f78",
    "gnome-shell.css": "eba48c15d2f9bd578f691df052fa543f4f2d9801b73dd4af37c005282712a67c",
    "workspace-placeholder.svg": "7ce9aab6a382710de04d1e867db910c77df9bbece61d5aa5d211d2676c1a141c",
}
MARBLE_SUBSTITUTIONS = {
    "calendar-event-disabled.svg": (
        b"TEXT-DISABLED-COLOR",
        b"rgba(234, 242, 251, 0.38)",
    ),
    "calendar-event-today.svg": (
        b"BUTTON-TEXT-COLOR",
        b"rgba(35, 51, 67, 1)",
    ),
    "calendar-event.svg": (
        b"TEXT-SECONDARY-COLOR",
        b"rgba(234, 242, 251, 0.67)",
    ),
    "workspace-placeholder.svg": (
        b"ACCENT-SECONDARY-COLOR",
        b"rgba(179, 191, 204, 1)",
    ),
}
IMPORT_RE = re.compile(r"^\s*@import\s+['\"]([^'\"]+)['\"];", re.MULTILINE)
LICENSE_NOTICE_RE = re.compile(
    r"GNU (?:Lesser )?General Public License|SPDX-License-Identifier|Creative Commons"
)


def die(message: str) -> NoReturn:
    raise SystemExit(message)


def regular_bytes(path: Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        die(f"immutable provenance input is missing or unsafe: {path}")
    try:
        return path.read_bytes()
    except OSError as error:
        die(f"cannot read immutable provenance input {path}: {error}")


def utf8_text(path: Path) -> str:
    raw = regular_bytes(path)
    if b"\r" in raw:
        die(f"immutable text input contains a carriage return: {path}")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as error:
        die(f"immutable text input is not UTF-8 {path}: {error}")


def exact_directory(path: Path, files: set[str], directories: set[str]) -> None:
    if path.is_symlink() or not path.is_dir():
        die(f"immutable provenance directory is missing or unsafe: {path}")
    actual_files: set[str] = set()
    actual_directories: set[str] = set()
    for member in path.iterdir():
        if member.is_symlink():
            die(f"immutable provenance directory contains a symbolic link: {member}")
        if member.is_file():
            actual_files.add(member.name)
        elif member.is_dir():
            actual_directories.add(member.name)
        else:
            die(f"immutable provenance directory contains a special entry: {member}")
    if actual_files != files or actual_directories != directories:
        die(f"immutable provenance directory closure differs: {path}")


def canonical_digest(root: Path, paths: set[Path] | list[Path]) -> str:
    if root.is_symlink() or not root.is_dir():
        die(f"immutable provenance digest root is missing or unsafe: {root}")
    resolved_root = root.resolve()
    unique_paths = set(paths)
    if len(unique_paths) != len(paths):
        die("immutable provenance digest input contains a duplicate path")
    normalized: list[tuple[str, Path]] = []
    for path in unique_paths:
        try:
            relative = path.relative_to(root).as_posix()
            path.resolve().relative_to(resolved_root)
        except ValueError:
            die(f"immutable provenance digest input escapes its root: {path}")
        normalized.append((relative, path))
    digest = hashlib.sha256()
    for relative, path in sorted(normalized, key=lambda value: value[0].encode("utf-8")):
        file_digest = hashlib.sha256(regular_bytes(path)).hexdigest()
        digest.update(relative.encode("utf-8") + b"\0")
        digest.update(file_digest.encode("ascii") + b"\n")
    return digest.hexdigest()


def no_duplicate_json_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            die(f"Marble colors.json contains a duplicate key: {key}")
        result[key] = value
    return result


def reject_json_constant(value: str) -> NoReturn:
    die(f"Marble colors.json contains a non-finite number: {value}")


def reproduce_marble_release(marble_source_theme: Path, marble_release_theme: Path) -> None:
    source_root = marble_source_theme.parents[1]
    colors_path = source_root / "colors.json"
    css_root = marble_source_theme / ".css"
    versions_root = marble_source_theme / ".versions"
    version_47_root = versions_root / "47.."
    version_48_root = versions_root / "48.."
    version_47_css_root = version_47_root / ".css"
    version_48_css_root = version_48_root / ".css"

    exact_directory(marble_source_theme, set(MARBLE_SVGS), {".css", ".versions"})
    exact_directory(css_root, set(BASE_CSS), set())
    exact_directory(versions_root, set(), {"..46", "..47", "47..", "48.."})
    exact_directory(version_47_root, set(), {".css"})
    exact_directory(version_48_root, set(), {".css"})
    exact_directory(version_47_css_root, set(VERSION_47_CSS), set())
    exact_directory(version_48_css_root, set(VERSION_48_CSS), set())

    css_paths = [css_root / name for name in BASE_CSS]
    css_paths.extend(version_47_css_root / name for name in VERSION_47_CSS)
    css_paths.extend(version_48_css_root / name for name in VERSION_48_CSS)
    svg_paths = [marble_source_theme / name for name in MARBLE_SVGS]
    selected_inputs = [colors_path, *css_paths, *svg_paths]
    if len(selected_inputs) != 25 or canonical_digest(source_root, selected_inputs) != MARBLE_SELECTED_INPUT_DIGEST:
        die("Marble blue/dark/filled source closure differs from the reviewed 25 inputs")

    payload: dict[str, str] = {
        "gnome-shell.css": "".join(utf8_text(path) + "\n" for path in css_paths)
    }
    payload.update({path.name: utf8_text(path) for path in svg_paths})
    for name, content in payload.items():
        for old, new in FILLED_SUBSTITUTIONS:
            content = content.replace(old, new)
        payload[name] = content

    try:
        colors_document = json.loads(
            utf8_text(colors_path),
            object_pairs_hook=no_duplicate_json_keys,
            parse_constant=reject_json_constant,
        )
    except json.JSONDecodeError as error:
        die(f"cannot parse immutable Marble colors.json: {error}")
    if not isinstance(colors_document, dict):
        die("Marble colors.json root is not an object")
    elements = colors_document.get("elements")
    if not isinstance(elements, dict) or not elements:
        die("Marble colors.json lacks its ordered element map")

    replacements: list[tuple[str, str]] = []
    for token, raw_definition in elements.items():
        if not isinstance(token, str) or not isinstance(raw_definition, dict):
            die("Marble colors.json contains an invalid element definition")
        raw_color = raw_definition.get("dark")
        if raw_color is None:
            default = raw_definition.get("default")
            if not isinstance(default, str) or default not in elements:
                die(f"Marble color element lacks one exact dark/default definition: {token}")
            default_definition = elements[default]
            if not isinstance(default_definition, dict):
                die(f"Marble default color definition is not an object: {default}")
            raw_color = default_definition.get("dark")
        if not isinstance(raw_color, dict):
            die(f"Marble dark color definition is not an object: {token}")
        saturation_raw = raw_color.get("s")
        lightness_raw = raw_color.get("l")
        alpha = raw_color.get("a")
        if (
            not isinstance(saturation_raw, int)
            or isinstance(saturation_raw, bool)
            or not isinstance(lightness_raw, int)
            or isinstance(lightness_raw, bool)
            or not isinstance(alpha, (int, float))
            or isinstance(alpha, bool)
        ):
            die(f"Marble dark color components have invalid types: {token}")
        saturation = saturation_raw / 100
        lightness = lightness_raw / 100
        if not 0 <= saturation <= 1 or not 0 <= lightness <= 1 or not 0 <= alpha <= 1:
            die(f"Marble dark color components are outside their exact range: {token}")
        rgb = tuple(
            round(channel * 255)
            for channel in colorsys.hls_to_rgb(210 / 360, lightness, saturation)
        )
        replacements.append((token, f"rgba({rgb[0]}, {rgb[1]}, {rgb[2]}, {alpha})"))

    for name, content in payload.items():
        for old, new in replacements:
            content = content.replace(old, new)
        payload[name] = content

    exact_directory(marble_release_theme, set(MARBLE_RELEASE_SHA256), set())
    for name, expected_digest in MARBLE_RELEASE_SHA256.items():
        reproduced = payload[name].encode("utf-8")
        if hashlib.sha256(reproduced).hexdigest() != expected_digest:
            die(f"reproduced Marble release asset digest differs: {name}")
        if reproduced != regular_bytes(marble_release_theme / name):
            die(f"Marble release asset is not the exact source-derived byte stream: {name}")


def calendar_geometry(path: Path) -> tuple[str, str, str, str, str]:
    try:
        root = ET.fromstring(regular_bytes(path))
    except ET.ParseError as error:
        die(f"cannot parse SVG {path}: {error}")
    circles = root.findall(f"{SVG}circle")
    if len(circles) != 1:
        die(f"calendar provenance SVG must contain exactly one circle: {path}")
    circle = circles[0]
    return (
        root.attrib.get("width", ""),
        root.attrib.get("height", ""),
        circle.attrib.get("cx", ""),
        circle.attrib.get("cy", ""),
        circle.attrib.get("r", ""),
    )


def resolve_sass_import(source: Path, target: str, theme_root: Path) -> Path:
    base = source.parent / target
    candidates = [base] if base.suffix == ".scss" else [
        base.with_suffix(".scss"),
        base.parent / f"_{base.name}.scss",
    ]
    matches = [
        candidate.resolve()
        for candidate in candidates
        if candidate.is_file() and not candidate.is_symlink()
    ]
    if len(matches) != 1:
        die(f"cannot resolve one exact Sass import {target!r} from {source}")
    resolved = matches[0]
    try:
        resolved.relative_to(theme_root.resolve())
    except ValueError:
        die(f"Sass import escapes the exact GNOME theme source: {resolved}")
    return resolved


def imported_sass_closure(entrypoint: Path, theme_root: Path) -> set[Path]:
    pending = [entrypoint.resolve()]
    visited: set[Path] = set()
    while pending:
        source = pending.pop()
        if source in visited:
            continue
        visited.add(source)
        content = utf8_text(source)
        if re.search(r"^\s*@(use|forward)\b", content, re.MULTILINE):
            die(f"unreviewed Sass module directive in exact GNOME source: {source}")
        for target in IMPORT_RE.findall(content):
            pending.append(resolve_sass_import(source, target, theme_root))
    visited.remove(entrypoint.resolve())
    return visited


def main(argv: list[str]) -> int:
    if len(argv) != 6:
        die(
            "usage: verify-license-provenance.py GNOME_THEME_ROOT "
            "MARBLE_SOURCE_THEME MARBLE_RELEASE_THEME REVIEWED_LICENSE_ROOT "
            "SPDX_LGPL_2_1_ONLY"
        )

    (
        gnome_theme_root,
        marble_source_theme,
        marble_release_theme,
        reviewed_license_root,
        spdx_lgpl_text,
    ) = map(Path, argv[1:])
    sass_root = gnome_theme_root / "gnome-shell-sass"
    common_scss = sass_root / "_common.scss"
    sass_readme = sass_root / "README.md"
    gnome_calendar = gnome_theme_root / "calendar-today.svg"
    gnome_workspace = gnome_theme_root / "workspace-placeholder.svg"

    exact_license_sources = {
        "LICENSE-Marble": marble_source_theme.parents[1] / "LICENSE",
        "COPYING-GNOME-Shell": gnome_theme_root.parents[1] / "COPYING",
        "COPYING-GNOME-Shell-Sass": sass_root / "COPYING",
        "LICENSE-LGPL-2.1-only": spdx_lgpl_text,
        "NOTICE-GNOME-Shell-common.scss": common_scss,
    }
    exact_directory(
        reviewed_license_root,
        {
            "COPYING-GNOME-Shell",
            "COPYING-GNOME-Shell-Sass",
            "LICENSE-LGPL-2.1-only",
            "LICENSE-Marble",
            "LICENSE-project",
            "NOTICE-GNOME-Shell-common.scss",
            "THIRD-PARTY-NOTICES",
        },
        set(),
    )
    for reviewed_name, upstream_path in exact_license_sources.items():
        reviewed_path = reviewed_license_root / reviewed_name
        try:
            matches = regular_bytes(reviewed_path) == regular_bytes(upstream_path)
        except OSError as error:
            die(f"cannot compare reviewed license source {reviewed_name}: {error}")
        if not matches:
            die(f"reviewed license source differs from immutable upstream: {reviewed_name}")

    common_notice = utf8_text(common_scss)
    for required in (
        "Copyright 2009, 2015 Red Hat, Inc.",
        "Copyright 2009 Intel Corporation",
        "GNU Lesser General Public License,\n * version 2.1",
    ):
        if required not in common_notice:
            die(f"GNOME Shell _common.scss notice differs: missing {required!r}")

    readme = utf8_text(sass_readme)
    if (
        "GNOME Shell Sass is distributed under the terms of the GNU General Public\n"
        "License, version 2 or later."
    ) not in readme:
        die("GNOME Shell Sass GPL-2.0-or-later notice differs")

    sass_closure = imported_sass_closure(
        gnome_theme_root / "gnome-shell-dark.scss", gnome_theme_root
    )
    expected_sass_closure = {
        path.resolve()
        for path in sass_root.rglob("*.scss")
        if path.name != "_high-contrast-colors.scss"
    }
    if sass_closure != expected_sass_closure or len(sass_closure) != 38:
        die("GNOME dark CSS Sass/widget import closure differs from the reviewed 38 files")
    explicit_notices = {
        path
        for path in sass_closure
            if LICENSE_NOTICE_RE.search(utf8_text(path))
    }
    if explicit_notices != {common_scss.resolve()}:
        die("GNOME dark CSS has an unreviewed per-file license notice")

    gnome_source_root = gnome_theme_root.parents[1]
    gnome_selected_inputs = set(sass_closure)
    gnome_selected_inputs.update(
        {
            gnome_source_root / "COPYING",
            gnome_theme_root / "gnome-shell-dark.scss",
            sass_root / "COPYING",
            sass_readme,
            gnome_calendar,
            gnome_workspace,
        }
    )
    if len(gnome_selected_inputs) != 44 or canonical_digest(
        gnome_source_root, gnome_selected_inputs
    ) != GNOME_SELECTED_INPUT_DIGEST:
        die("GNOME audited theme source differs from the reviewed 44-file closure")

    marble_source_workspace = marble_source_theme / "workspace-placeholder.svg"
    expected_source_workspace = regular_bytes(gnome_workspace).replace(
        b"#ffffff", b"ACCENT-SECONDARY-COLOR"
    )
    if expected_source_workspace != regular_bytes(marble_source_workspace):
        die("Marble workspace source is not the exact reviewed GNOME substitution")

    for asset in (
        gnome_calendar,
        *(marble_source_theme / name for name in MARBLE_SUBSTITUTIONS if "calendar" in name),
    ):
        if calendar_geometry(asset) != EXPECTED_CALENDAR_GEOMETRY:
            die(f"calendar asset geometry differs from the GNOME baseline: {asset}")

    for name, (token, replacement) in MARBLE_SUBSTITUTIONS.items():
        source_asset = marble_source_theme / name
        release_asset = marble_release_theme / name
        source_bytes = regular_bytes(source_asset)
        if source_bytes.count(token) < 1:
            die(f"Marble source asset lacks its reviewed substitution token: {source_asset}")
        if source_bytes.replace(token, replacement) != regular_bytes(release_asset):
            die(f"Marble release asset is not the exact reviewed substitution: {name}")

    reproduce_marble_release(marble_source_theme, marble_release_theme)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
