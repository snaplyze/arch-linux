#!/usr/bin/env python3
"""Validate the committed package closure without executing PKGBUILD code."""

from __future__ import annotations

import hashlib
import os
import pathlib
import posixpath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import unicodedata
from collections import defaultdict
from typing import NoReturn
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKAGES = ROOT / "packages"
PACKAGE_SET = ROOT / "repository" / "package-set"
TRUST = ROOT / "repository" / "trust"
EXPECTED_PACKAGE_SET = [
    "arch-linux-keyring",
    "arch-linux-marble-shell",
    "arch-linux-colloid-gtk3",
    "arch-linux-colloid-icons",
    "arch-linux-marble-profile",
    "arch-linux-marble-gdm",
]
EXPECTED_LICENSES = {
    package: ["GPL-3.0-only"] for package in EXPECTED_PACKAGE_SET
}
EXPECTED_LICENSES["arch-linux-marble-gdm"] = [
    "GPL-3.0-only AND GPL-2.0-or-later AND LGPL-2.1-only"
]
EXPECTED_INSTALL = {
    "arch-linux-keyring": ["arch-linux-keyring.install"],
    "arch-linux-marble-profile": ["arch-linux-marble-profile.install"],
    "arch-linux-marble-gdm": ["arch-linux-marble-gdm.install"],
}
EXPECTED_DEPENDENCIES = {
    "arch-linux-keyring": ["pacman"],
    "arch-linux-marble-shell": [],
    "arch-linux-colloid-gtk3": ["gtk3"],
    "arch-linux-colloid-icons": ["hicolor-icon-theme", "gtk-update-icon-cache"],
    "arch-linux-marble-profile": [
        "arch-linux-keyring>=1.0.0",
        "arch-linux-marble-shell>=50.0.0",
        "arch-linux-colloid-gtk3>=20260808",
        "arch-linux-colloid-icons>=20260817",
        "bash",
        "coreutils",
        "dconf",
        "gnome-shell",
        "gnome-shell-extensions",
        "grep",
        "pacman",
    ],
    "arch-linux-marble-gdm": [
        "arch-linux-colloid-icons>=20260817",
        "arch-linux-keyring>=1.0.0",
        "arch-linux-marble-profile>=1.0.0",
        "arch-linux-marble-shell>=50.0.0",
        "bash",
        "coreutils",
        "dconf",
        "gdm",
        "glib2",
        "gjs",
        "gnome-shell",
        "gsettings-desktop-schemas",
        "pacman",
        "systemd",
    ],
}
EXPECTED_SOURCE_ALIASES = {
    "arch-linux-colloid-gtk3": [
        "arch-linux-colloid-gtk3-6c2dc65865628bda9fdc8157a30cd5eda6fd41f9.tar.gz"
    ],
    "arch-linux-colloid-icons": [
        "arch-linux-colloid-icons-ceac6608ecd0e40025cbc2ebbd32bf0e0f4ebc6a.tar.gz"
    ],
    "arch-linux-keyring": [
        "arch-linux.gpg",
        "primary-fingerprint",
        "signing-subkey-fingerprint",
        "arch-linux-keyring.install",
        "LICENSE-project",
    ],
    "arch-linux-marble-shell": [
        "Marble-shell-filled-50.zip",
        "Marble-LICENSE-df788bc3d9d2147bcdeaedb907b90ced64f0ad48",
    ],
    "arch-linux-marble-profile": [
        "arch-linux-marble-profile.install",
        "update-compatibility",
        "supported-gnome-majors",
        "90-arch-linux-marble-profile.hook",
        "LICENSE-project",
    ],
    "arch-linux-marble-gdm": [
        "Marble-shell-filled-50.zip",
        "Marble-source-df788bc3d9d2147bcdeaedb907b90ced64f0ad48.tar.gz",
        "gnome-shell-1_50.4-1-x86_64.pkg.tar.zst",
        "GNOME-Shell-source-dcda6594b153aa179d92cc62e2414d84a43ab82c.tar.gz",
        "SPDX-LGPL-2.1-only-c4a7237ec8f4654e867546f9f409749300f1bf4c.txt",
        "build-combined-css.py",
        "verify-license-provenance.py",
        "update-compatibility",
        "known-gnome-50.sha256",
        "known-colloid-icons.sha256",
        "assets.sha256",
        "dconf-profile",
        "00-arch-linux-marble-gdm-icons",
        "icon-theme.lock",
        "50-arch-linux-marble-gdm.conf",
        "40-arch-linux-marble-gdm-pre.hook",
        "zz-arch-linux-marble-gdm-post.hook",
        "arch-linux-marble-gdm.install",
        "LICENSE-Marble",
        "COPYING-GNOME-Shell",
        "COPYING-GNOME-Shell-Sass",
        "LICENSE-LGPL-2.1-only",
        "NOTICE-GNOME-Shell-common.scss",
        "LICENSE-project",
        "THIRD-PARTY-NOTICES",
    ],
}
NAME = re.compile(r"^[a-z0-9][a-z0-9+._-]*$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"(?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f])")
ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"
PACKAGE_METADATA_PATHS = {".PKGINFO", ".BUILDINFO", ".MTREE"}
COLLOID_LICENSE_SHA256 = "605e9047a563c5c8396ffb18232aa4304ec56586aee537c45064c6fb425e44ad"

PACKAGE_PREFIXES = {
    "arch-linux-keyring": [],
    "arch-linux-marble-shell": [
        "usr/share/arch-linux-marble/shell/50.0.0/Marble-blue-dark/",
    ],
    "arch-linux-colloid-gtk3": ["usr/share/themes/Colloid-Dark/"],
    "arch-linux-colloid-icons": [
        "usr/share/icons/Colloid/",
        "usr/share/icons/Colloid-Light/",
        "usr/share/icons/Colloid-Dark/",
    ],
    "arch-linux-marble-profile": [],
    "arch-linux-marble-gdm": ["usr/share/arch-linux-marble-gdm/"],
}

PACKAGE_EXACT_PATHS = {
    "arch-linux-keyring": {
        "usr/share/pacman/keyrings/arch-linux.gpg",
        "usr/share/arch-linux-keyring/primary-fingerprint",
        "usr/share/arch-linux-keyring/signing-subkey-fingerprint",
        "usr/share/licenses/arch-linux-keyring/LICENSE-project",
    },
    "arch-linux-marble-shell": {
        "usr/share/licenses/arch-linux-marble-shell/LICENSE",
    },
    "arch-linux-colloid-gtk3": {
        "usr/share/licenses/arch-linux-colloid-gtk3/LICENSE",
    },
    "arch-linux-colloid-icons": {
        "usr/share/licenses/arch-linux-colloid-icons/LICENSE",
    },
    "arch-linux-marble-profile": {
        "usr/lib/arch-linux-marble-profile/update-compatibility",
        "usr/share/arch-linux-marble/supported-gnome-majors",
        "usr/share/libalpm/hooks/90-arch-linux-marble-profile.hook",
        "usr/share/licenses/arch-linux-marble-profile/LICENSE-project",
    },
    "arch-linux-marble-gdm": {
        "usr/lib/arch-linux-marble-gdm/update-compatibility",
        "usr/share/libalpm/hooks/40-arch-linux-marble-gdm-pre.hook",
        "usr/share/libalpm/hooks/zz-arch-linux-marble-gdm-post.hook",
        "usr/share/licenses/arch-linux-marble-gdm/COPYING-GNOME-Shell",
        "usr/share/licenses/arch-linux-marble-gdm/COPYING-GNOME-Shell-Sass",
        "usr/share/licenses/arch-linux-marble-gdm/LICENSE-LGPL-2.1-only",
        "usr/share/licenses/arch-linux-marble-gdm/LICENSE-Marble",
        "usr/share/licenses/arch-linux-marble-gdm/LICENSE-project",
        "usr/share/licenses/arch-linux-marble-gdm/NOTICE-GNOME-Shell-common.scss",
        "usr/share/licenses/arch-linux-marble-gdm/THIRD-PARTY-NOTICES",
    },
}

PACKAGE_REQUIRED_PATHS = {
    package: set(paths) for package, paths in PACKAGE_EXACT_PATHS.items()
}
PACKAGE_REQUIRED_PATHS["arch-linux-marble-shell"].update(
    {
        "usr/share/arch-linux-marble/shell/50.0.0/Marble-blue-dark/gnome-shell/gnome-shell.css",
        "usr/share/arch-linux-marble/shell/50.0.0/Marble-blue-dark/gnome-shell/calendar-event-disabled.svg",
        "usr/share/arch-linux-marble/shell/50.0.0/Marble-blue-dark/gnome-shell/calendar-event-today.svg",
        "usr/share/arch-linux-marble/shell/50.0.0/Marble-blue-dark/gnome-shell/calendar-event.svg",
        "usr/share/arch-linux-marble/shell/50.0.0/Marble-blue-dark/gnome-shell/workspace-placeholder.svg",
    }
)
PACKAGE_REQUIRED_PATHS["arch-linux-colloid-gtk3"].update(
    {
        "usr/share/themes/Colloid-Dark/index.theme",
        "usr/share/themes/Colloid-Dark/gtk-3.0/gtk.css",
        "usr/share/themes/Colloid-Dark/gtk-3.0/gtk-dark.css",
    }
)
PACKAGE_REQUIRED_PATHS["arch-linux-colloid-icons"].update(
    {
        "usr/share/icons/Colloid/index.theme",
        "usr/share/icons/Colloid-Light/index.theme",
        "usr/share/icons/Colloid-Dark/index.theme",
    }
)

EXPECTED_FILE_SOURCES = {
    "arch-linux-keyring": {
        ".INSTALL": PACKAGES / "arch-linux-keyring" / "arch-linux-keyring.install",
        "usr/share/pacman/keyrings/arch-linux.gpg": TRUST / "arch-linux.gpg",
        "usr/share/arch-linux-keyring/primary-fingerprint": TRUST / "primary-fingerprint",
        "usr/share/arch-linux-keyring/signing-subkey-fingerprint": TRUST / "signing-subkey-fingerprint",
        "usr/share/licenses/arch-linux-keyring/LICENSE-project": PACKAGES / "arch-linux-keyring" / "LICENSE-project",
    },
    "arch-linux-marble-shell": {
        "usr/share/licenses/arch-linux-marble-shell/LICENSE": PACKAGES / "arch-linux-marble-gdm" / "LICENSE-Marble",
    },
    "arch-linux-colloid-gtk3": {},
    "arch-linux-colloid-icons": {},
    "arch-linux-marble-profile": {
        ".INSTALL": PACKAGES / "arch-linux-marble-profile" / "arch-linux-marble-profile.install",
        "usr/lib/arch-linux-marble-profile/update-compatibility": PACKAGES / "arch-linux-marble-profile" / "update-compatibility",
        "usr/share/arch-linux-marble/supported-gnome-majors": PACKAGES / "arch-linux-marble-profile" / "supported-gnome-majors",
        "usr/share/libalpm/hooks/90-arch-linux-marble-profile.hook": PACKAGES / "arch-linux-marble-profile" / "90-arch-linux-marble-profile.hook",
        "usr/share/licenses/arch-linux-marble-profile/LICENSE-project": PACKAGES / "arch-linux-marble-profile" / "LICENSE-project",
    },
    "arch-linux-marble-gdm": {
        ".INSTALL": PACKAGES / "arch-linux-marble-gdm" / "arch-linux-marble-gdm.install",
        "usr/lib/arch-linux-marble-gdm/update-compatibility": PACKAGES / "arch-linux-marble-gdm" / "update-compatibility",
        "usr/share/libalpm/hooks/40-arch-linux-marble-gdm-pre.hook": PACKAGES / "arch-linux-marble-gdm" / "40-arch-linux-marble-gdm-pre.hook",
        "usr/share/libalpm/hooks/zz-arch-linux-marble-gdm-post.hook": PACKAGES / "arch-linux-marble-gdm" / "zz-arch-linux-marble-gdm-post.hook",
        "usr/share/arch-linux-marble-gdm/assets.sha256": PACKAGES / "arch-linux-marble-gdm" / "assets.sha256",
        "usr/share/arch-linux-marble-gdm/known-gnome-50.sha256": PACKAGES / "arch-linux-marble-gdm" / "known-gnome-50.sha256",
        "usr/share/arch-linux-marble-gdm/known-colloid-icons.sha256": PACKAGES / "arch-linux-marble-gdm" / "known-colloid-icons.sha256",
        "usr/share/arch-linux-marble-gdm/50.0.0/dconf/profile": PACKAGES / "arch-linux-marble-gdm" / "dconf-profile",
        "usr/share/arch-linux-marble-gdm/50.0.0/dconf/source/00-arch-linux-marble-gdm-icons": PACKAGES / "arch-linux-marble-gdm" / "00-arch-linux-marble-gdm-icons",
        "usr/share/arch-linux-marble-gdm/50.0.0/dconf/source/locks/icon-theme": PACKAGES / "arch-linux-marble-gdm" / "icon-theme.lock",
        "usr/share/arch-linux-marble-gdm/systemd/50-arch-linux-marble-gdm.conf": PACKAGES / "arch-linux-marble-gdm" / "50-arch-linux-marble-gdm.conf",
        **{
            f"usr/share/licenses/arch-linux-marble-gdm/{name}": PACKAGES / "arch-linux-marble-gdm" / name
            for name in (
                "COPYING-GNOME-Shell",
                "COPYING-GNOME-Shell-Sass",
                "LICENSE-LGPL-2.1-only",
                "LICENSE-Marble",
                "LICENSE-project",
                "NOTICE-GNOME-Shell-common.scss",
                "THIRD-PARTY-NOTICES",
            )
        },
    },
}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"package metadata check failed: {message}")


def parse_srcinfo(path: pathlib.Path) -> dict[str, list[str]]:
    data: dict[str, list[str]] = defaultdict(list)
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if " = " not in line:
            fail(f"{path.relative_to(ROOT)}:{number}: malformed .SRCINFO line")
        key, value = line.split(" = ", 1)
        if not key or not value:
            fail(f"{path.relative_to(ROOT)}:{number}: empty .SRCINFO key/value")
        data[key].append(value)
    return dict(data)


def alias_and_locator(source: str) -> tuple[str, str]:
    if "::" in source:
        alias, locator = source.split("::", 1)
        return alias, locator
    return pathlib.PurePosixPath(source).name, source


def assert_immutable_url(package: str, source: str, url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        fail(f"{package}: remote source is not an ordinary HTTPS URL: {url}")
    if parsed.fragment:
        fail(f"{package}: remote source contains a fragment: {url}")
    lower = url.lower()
    if any(token in lower for token in ("/main/", "/master/", "/latest/", "?ref=main", "?ref=master")):
        fail(f"{package}: mutable branch/latest source: {url}")

    immutable = bool(COMMIT.search(url))
    immutable |= bool(
        parsed.netloc == "api.github.com"
        and re.fullmatch(r"/repos/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/releases/assets/[1-9][0-9]*", parsed.path)
    )
    immutable |= bool(
        parsed.netloc == "archive.archlinux.org"
        and re.fullmatch(
            r"/packages/[a-z0-9]/[a-z0-9@._+-]+/[A-Za-z0-9@._+:-]+-[0-9][A-Za-z0-9@._+~:-]*-[0-9]+-(?:any|x86_64)\.pkg\.tar\.zst",
            parsed.path,
        )
    )
    if not immutable:
        fail(f"{package}: source is not pinned to an immutable object: {source}")


def file_sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_file(path: pathlib.Path, label: str) -> None:
    if not path.is_file() or path.is_symlink():
        fail(f"{label} is missing or linked: {path.relative_to(ROOT)}")
    info = path.stat()
    if info.st_nlink != 1:
        fail(f"{label} is hard-linked: {path.relative_to(ROOT)}")
    if info.st_mode & 0o022:
        fail(f"{label} is group/other writable: {path.relative_to(ROOT)}")


def has_control(value: str) -> bool:
    return any(unicodedata.category(character).startswith("C") for character in value)


def safe_member_name(member: tarfile.TarInfo) -> str:
    raw = member.name
    if member.isdir():
        raw = raw.rstrip("/")
    if (
        not raw
        or raw.startswith("/")
        or "\\" in raw
        or has_control(raw)
        or "//" in raw
        or posixpath.normpath(raw) != raw
        or any(part in {"", ".", ".."} for part in raw.split("/"))
    ):
        fail(f"unsafe archive path: {member.name!r}")
    return raw


def safe_link_target(name: str, target: str) -> str:
    if not target or target.startswith("/") or "\\" in target or has_control(target):
        fail(f"unsafe symlink target for {name}: {target!r}")
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
    if resolved in {"", ".", ".."} or resolved.startswith("../") or resolved.startswith("/"):
        fail(f"unsafe symlink target for {name}: {target!r}")
    return resolved


def parse_hash_manifest(path: pathlib.Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if "  " not in line:
            fail(f"{path.relative_to(ROOT)}:{number}: malformed hash manifest line")
        digest, name = line.split("  ", 1)
        if not SHA256.fullmatch(digest) or not name or name.startswith("/"):
            fail(f"{path.relative_to(ROOT)}:{number}: invalid hash manifest entry")
        if posixpath.normpath(name) != name or any(part in {"", ".", ".."} for part in name.split("/")):
            fail(f"{path.relative_to(ROOT)}:{number}: unsafe hash manifest path")
        if name in result:
            fail(f"{path.relative_to(ROOT)}:{number}: duplicate hash manifest path")
        result[name] = digest
    if not result:
        fail(f"{path.relative_to(ROOT)} is empty")
    return result


def expected_payload_hashes(package: str) -> dict[str, str]:
    gdm = PACKAGES / "arch-linux-marble-gdm"
    assets = parse_hash_manifest(gdm / "assets.sha256")
    if package == "arch-linux-marble-gdm":
        return {
            f"usr/share/arch-linux-marble-gdm/{name}": digest
            for name, digest in assets.items()
        }
    if package == "arch-linux-marble-shell":
        shell_root = "usr/share/arch-linux-marble/shell/50.0.0/Marble-blue-dark/gnome-shell"
        source_names = {
            "gnome-shell.css": "50.0.0/reviewed/gnome-shell.css",
            "calendar-event-disabled.svg": "50.0.0/theme/calendar-event-disabled.svg",
            "calendar-event-today.svg": "50.0.0/theme/calendar-event-today.svg",
            "calendar-event.svg": "50.0.0/theme/calendar-event.svg",
            "workspace-placeholder.svg": "50.0.0/theme/workspace-placeholder.svg",
        }
        return {f"{shell_root}/{name}": assets[source] for name, source in source_names.items()}
    if package == "arch-linux-colloid-gtk3":
        return {
            "usr/share/themes/Colloid-Dark/gtk-3.0/gtk.css":
                "4a13cedd0b7ada1903ce517f9d7c7998d5d683cb0d644a3862efe9a9ea86f128",
            "usr/share/themes/Colloid-Dark/gtk-3.0/gtk-dark.css":
                "4a13cedd0b7ada1903ce517f9d7c7998d5d683cb0d644a3862efe9a9ea86f128",
            "usr/share/licenses/arch-linux-colloid-gtk3/LICENSE": COLLOID_LICENSE_SHA256,
        }
    if package == "arch-linux-colloid-icons":
        hashes = {
            f"usr/share/icons/Colloid-Dark/{name}": digest
            for name, digest in parse_hash_manifest(gdm / "known-colloid-icons.sha256").items()
        }
        # New application artwork in the reviewed 2026-08-29 input. Dark uses
        # the existing Light/apps/scalable alias, so these regular files bind both.
        additions = {
            "google-messages.svg": "0de28a70c76baeea863b005a1c199dd550fde6e3782aa5ee69117ff0a71b1ec3",
            "google-tasks.svg": "38b8878adbf7e42cceec6de9cfb6fd687d980533f0407bdca46d83fa38a1e1f1",
            "kingom-hearts-1-5-2-5.svg": "0f5de361e9ae68232800c4f9a7d24d0084f750c23b8b2fc11f5bf3412174314d",
            "kingom-hearts-2-8.svg": "13c1ea4b386ce86ab61b1af6d91cb3d263d9299c63297321d4f64595ec831ff8",
            "kingom-hearts-3.svg": "3603fa4c592b8328cc3595a418a7755ff8ea171e4dfc23eec966836be995f04c",
            "zcode.svg": "bdab7ababf45f4aea395e10a3c399a4fe1f83cbb6b43940badadd321d400564e",
        }
        hashes.update({f"usr/share/icons/Colloid-Light/apps/scalable/{name}": digest
                       for name, digest in additions.items()})
        hashes["usr/share/licenses/arch-linux-colloid-icons/LICENSE"] = COLLOID_LICENSE_SHA256
        return hashes
    return {}


def package_path_allowed(package: str, name: str, is_directory: bool) -> bool:
    metadata = set(PACKAGE_METADATA_PATHS)
    if package in EXPECTED_INSTALL:
        metadata.add(".INSTALL")
    if name in metadata:
        return True

    exact = PACKAGE_EXACT_PATHS[package]
    prefixes = [prefix.rstrip("/") for prefix in PACKAGE_PREFIXES[package]]
    if not is_directory:
        return name in exact or any(name.startswith(f"{prefix}/") for prefix in prefixes)

    if any(path.startswith(f"{name}/") for path in exact):
        return True
    return any(
        name == prefix or name.startswith(f"{prefix}/") or prefix.startswith(f"{name}/")
        for prefix in prefixes
    )


def assert_gdm_path_boundary(name: str) -> None:
    forbidden_prefixes = (
        "etc/",
        "home/",
        "root/",
        "usr/lib/environment.d/",
        "usr/lib/systemd/user/",
        "usr/lib/systemd/user-environment-generators/",
        "usr/share/dconf/",
        "usr/share/gdm/",
        "usr/share/glib-2.0/schemas/",
        "usr/share/gnome-shell/",
        "usr/share/themes/",
        "var/",
    )
    parts = name.lower().split("/")
    if name.startswith(forbidden_prefixes):
        fail(f"arch-linux-marble-gdm: forbidden vendor, home, or environment path: {name}")
    if "gtk-4.0" in parts or "libadwaita" in parts:
        fail(f"arch-linux-marble-gdm: forbidden GTK4/libadwaita path: {name}")
    if "environment.d" in parts or "environment" in parts:
        fail(f"arch-linux-marble-gdm: forbidden environment path: {name}")
    if ".cache" in parts or "cache" in parts or parts[-1] in {"gschemas.compiled", "icon-theme.cache"}:
        fail(f"arch-linux-marble-gdm: forbidden cache path: {name}")


def read_member(archive: tarfile.TarFile, member: tarfile.TarInfo) -> bytes:
    if not member.isfile():
        fail(f"required payload is not a regular file: {member.name}")
    source = archive.extractfile(member)
    if source is None:
        fail(f"cannot read package payload: {member.name}")
    data = source.read()
    if len(data) != member.size:
        fail(f"truncated package payload: {member.name}")
    return data


def member_sha256(archive: tarfile.TarFile, member: tarfile.TarInfo) -> str:
    if not member.isfile():
        fail(f"required payload is not a regular file: {member.name}")
    source = archive.extractfile(member)
    if source is None:
        fail(f"cannot read package payload: {member.name}")
    digest = hashlib.sha256()
    while chunk := source.read(1024 * 1024):
        digest.update(chunk)
    return digest.hexdigest()


def assert_no_absolute_svg_export_path(archive: tarfile.TarFile, member: tarfile.TarInfo) -> None:
    if re.search(rb"\binkscape:export-filename\s*=\s*['\"]/", read_member(archive, member)):
        fail(f"absolute SVG export metadata is forbidden: {member.name}")


def resolve_internal_regular_member(
    members: dict[str, tarfile.TarInfo], name: str, *, maximum_links: int = 16
) -> tarfile.TarInfo:
    """Resolve a bounded, already path-validated in-package symlink chain."""
    current = name
    seen: set[str] = set()
    for _ in range(maximum_links + 1):
        if current in seen:
            fail(f"symlink cycle in package closure: {name}")
        seen.add(current)
        member = members.get(current)
        if member is None:
            fail(f"symlink target is absent from package closure: {name} -> {current}")
        if member.islnk():
            fail(f"hardlink is forbidden: {current}")
        if member.issym():
            current = safe_link_target(current, member.linkname)
            continue
        if not member.isfile():
            fail(f"symlink target is not a regular file: {name} -> {current}")
        return member
    fail(f"symlink chain is too deep: {name}")


def parse_pkginfo(data: bytes) -> dict[str, list[str]]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        fail(f".PKGINFO is not UTF-8: {error}")
    result: dict[str, list[str]] = defaultdict(list)
    for number, line in enumerate(text.splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        if " = " not in line:
            fail(f".PKGINFO:{number}: malformed line")
        key, value = line.split(" = ", 1)
        if not key or not value or has_control(value):
            fail(f".PKGINFO:{number}: invalid key/value")
        result[key].append(value)
    return dict(result)


def expected_pkgver(package: str) -> str:
    source = parse_srcinfo(PACKAGES / package / ".SRCINFO")
    if len(source.get("pkgver", [])) != 1 or len(source.get("pkgrel", [])) != 1:
        fail(f"{package}: .SRCINFO version closure differs")
    prefix = f"{source['epoch'][0]}:" if source.get("epoch") else ""
    return f"{prefix}{source['pkgver'][0]}-{source['pkgrel'][0]}"


def verify_pkginfo(package: str, data: bytes) -> None:
    info = parse_pkginfo(data)
    expected_singletons = {
        "pkgname": package,
        "pkgver": expected_pkgver(package),
        "arch": parse_srcinfo(PACKAGES / package / ".SRCINFO")["arch"][0],
    }
    for key, expected in expected_singletons.items():
        if info.get(key) != [expected]:
            fail(f"{package}: .PKGINFO {key} differs")
    if info.get("license", []) != EXPECTED_LICENSES[package]:
        fail(f"{package}: .PKGINFO license differs")
    if info.get("depend", []) != EXPECTED_DEPENDENCIES[package]:
        fail(f"{package}: .PKGINFO dependencies differ")


def verify_package_tar(archive: tarfile.TarFile, package: str) -> None:
    members: dict[str, tarfile.TarInfo] = {}
    for member in archive.getmembers():
        name = safe_member_name(member)
        if name in members:
            fail(f"duplicate archive path: {name}")
        if package == "arch-linux-marble-gdm":
            assert_gdm_path_boundary(name)
        if member.uid != 0 or member.gid != 0:
            fail(f"archive uid/gid differs from 0: {name}")
        if member.islnk():
            fail(f"hardlink is forbidden: {name}")
        if member.isdir():
            expected_mode = 0o755
        elif member.isfile():
            expected_mode = 0o755 if name in {
                "usr/lib/arch-linux-marble-profile/update-compatibility",
                "usr/lib/arch-linux-marble-gdm/update-compatibility",
            } else 0o644
        elif member.issym():
            expected_mode = 0o777
        else:
            fail(f"special archive object is forbidden: {name}")
        if stat.S_IMODE(member.mode) != expected_mode:
            fail(f"archive mode differs for {name}: {stat.S_IMODE(member.mode):04o}")
        if not package_path_allowed(package, name, member.isdir()):
            fail(f"{package}: unexpected package path: {name}")
        if package == "arch-linux-colloid-icons" and member.isfile() and name.endswith(".svg"):
            assert_no_absolute_svg_export_path(archive, member)
        members[name] = member

    required = set(PACKAGE_METADATA_PATHS) | PACKAGE_REQUIRED_PATHS[package]
    required.update(EXPECTED_FILE_SOURCES[package])
    hashes = expected_payload_hashes(package)
    required.update(hashes)
    if package in EXPECTED_INSTALL:
        required.add(".INSTALL")
    missing = sorted(required - members.keys())
    if missing:
        fail(f"{package}: required package path is absent: {missing[0]}")

    for name, member in members.items():
        if not member.issym():
            continue
        target = safe_link_target(name, member.linkname)
        if target not in members and not any(path.startswith(f"{target}/") for path in members):
            fail(f"symlink target is outside the package closure: {name} -> {member.linkname}")
    symlink_hash_paths = {
        "usr/share/icons/Colloid-Dark/status/symbolic/network-wireless-signal-excellent-symbolic.svg",
        "usr/share/icons/Colloid-Dark/status/symbolic/battery-level-100-symbolic.svg",
        "usr/share/icons/Colloid-Dark/apps/symbolic/org.gnome.Settings-accessibility-symbolic.svg",
    } if package == "arch-linux-colloid-icons" else set()
    for name in required - symlink_hash_paths:
        if not members[name].isfile():
            fail(f"{package}: required package path is not regular: {name}")

    if package == "arch-linux-marble-gdm":
        license_root = "usr/share/licenses/arch-linux-marble-gdm/"
        expected_licenses = {
            path for path in PACKAGE_EXACT_PATHS[package] if path.startswith(license_root)
        }
        actual_licenses = {
            name for name, member in members.items()
            if name.startswith(license_root) and not member.isdir()
        }
        if actual_licenses != expected_licenses or len(actual_licenses) != 7:
            fail("arch-linux-marble-gdm: license payload must contain exactly seven reviewed files")

    verify_pkginfo(package, read_member(archive, members[".PKGINFO"]))
    for name, source in EXPECTED_FILE_SOURCES[package].items():
        checked_file(source, "reviewed package payload source")
        if read_member(archive, members[name]) != source.read_bytes():
            fail(f"{package}: payload bytes differ from reviewed source: {name}")
    for name, expected in hashes.items():
        member = members[name]
        if name in symlink_hash_paths:
            member = resolve_internal_regular_member(members, name)
        if member_sha256(archive, member) != expected:
            fail(f"{package}: payload SHA-256 differs: {name}")


def verify_package_archive(path: pathlib.Path, package: str) -> None:
    if package not in EXPECTED_PACKAGE_SET:
        fail(f"unknown expected package: {package}")
    try:
        info = path.lstat()
    except FileNotFoundError:
        fail(f"package archive is absent: {path}")
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        fail(f"package archive is not a single-link regular file: {path}")
    with path.open("rb") as source:
        if source.read(4) != ZSTD_MAGIC:
            fail(f"package archive is not a Zstandard frame: {path}")
    zstd = shutil.which("zstd")
    if not zstd:
        fail("zstd is required for package payload verification")
    tested = subprocess.run(
        [zstd, "-q", "--test", "--", os.fspath(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
    )
    if tested.returncode != 0:
        fail(f"zstd integrity check failed for package archive: {path}")

    with tempfile.TemporaryDirectory(prefix="arch-linux-package-", dir=os.environ.get("RUNNER_TEMP")) as work:
        tar_path = pathlib.Path(work) / "payload.tar"
        with tar_path.open("xb") as output:
            decoded = subprocess.run(
                [zstd, "-q", "-d", "-c", "--", os.fspath(path)],
                stdin=subprocess.DEVNULL,
                stdout=output,
                stderr=subprocess.PIPE,
                check=False,
            )
        if decoded.returncode != 0:
            fail(f"cannot decompress package archive: {path}")
        try:
            with tarfile.open(tar_path, mode="r:") as archive:
                verify_package_tar(archive, package)
        except tarfile.TarError as error:
            fail(f"invalid package tar stream: {error}")
    print(f"package payload checks passed: package={package} archive={path.name}")


def verify_metadata(report: bool = True) -> None:
    package_names = [line.strip() for line in PACKAGE_SET.read_text(encoding="utf-8").splitlines() if line.strip()]
    if package_names != EXPECTED_PACKAGE_SET:
        fail("repository/package-set differs from the reviewed build order")
    if any(not NAME.fullmatch(name) for name in package_names):
        fail("repository/package-set contains an invalid package name")
    directories = sorted(path.name for path in PACKAGES.iterdir() if path.is_dir())
    if sorted(package_names) != directories:
        fail("package directories differ from repository/package-set")

    project_dependencies: dict[str, set[str]] = {}
    for package in package_names:
        directory = PACKAGES / package
        pkgbuild = directory / "PKGBUILD"
        srcinfo = directory / ".SRCINFO"
        checked_file(pkgbuild, "PKGBUILD")
        checked_file(srcinfo, ".SRCINFO")
        text = pkgbuild.read_text(encoding="utf-8")
        if re.search(r"(?<![A-Za-z0-9_])sudo(?![A-Za-z0-9_])", text):
            fail(f"{package}: PKGBUILD invokes sudo")
        if re.search(r"(?<![A-Za-z0-9_])pacman\s+-U(?![A-Za-z0-9_])", text):
            fail(f"{package}: PKGBUILD installs packages")

        info = parse_srcinfo(srcinfo)
        for required in ("pkgbase", "pkgname", "pkgver", "pkgrel", "arch", "license"):
            if not info.get(required):
                fail(f"{package}: .SRCINFO lacks {required}")
        if info["pkgbase"] != [package] or info["pkgname"] != [package]:
            fail(f"{package}: pkgbase/pkgname differs from directory")
        if info["license"] != EXPECTED_LICENSES[package]:
            fail(f"{package}: license expression differs from the reviewed package contract")
        if info.get("depends", []) != EXPECTED_DEPENDENCIES[package]:
            fail(f"{package}: dependency closure or order differs from the reviewed package contract")
        if info.get("install", []) != EXPECTED_INSTALL.get(package, []):
            fail(f"{package}: install-script contract differs")
        if any(value == "SKIP" for value in info.get("sha256sums", [])):
            fail(f"{package}: checksum bypass is forbidden")
        sources = info.get("source", [])
        sums = info.get("sha256sums", [])
        if len(sources) != len(sums) or not sources:
            fail(f"{package}: source/checksum closure differs")

        source_names: list[str] = []
        for source, checksum in zip(sources, sums, strict=True):
            if not SHA256.fullmatch(checksum):
                fail(f"{package}: invalid SHA-256 for {source}")
            alias, locator = alias_and_locator(source)
            if not alias or pathlib.PurePosixPath(alias).name != alias:
                fail(f"{package}: unsafe source alias: {alias!r}")
            source_names.append(alias)
            if locator.startswith(("https://", "http://")):
                assert_immutable_url(package, source, locator)
                continue
            if package == "arch-linux-keyring" and alias in {
                "arch-linux.gpg", "primary-fingerprint", "signing-subkey-fingerprint"
            }:
                local = TRUST / alias
            else:
                local = directory / alias
            checked_file(local, "local package source")
            if file_sha(local) != checksum:
                fail(f"{package}: local source checksum differs: {alias}")

        if len(source_names) != len(set(source_names)):
            fail(f"{package}: duplicate source output name")
        if source_names != EXPECTED_SOURCE_ALIASES[package]:
            fail(f"{package}: immutable source-name/pin closure differs")
        install_values = info.get("install", [])
        if len(install_values) > 1:
            fail(f"{package}: multiple install scripts")
        if install_values and install_values[0] not in source_names:
            fail(f"{package}: install script is outside the source checksum closure")

        deps = {re.split(r"[<>=]", value, maxsplit=1)[0] for value in info.get("depends", [])}
        project_dependencies[package] = deps & set(package_names)

    expected_edges = {
        "arch-linux-marble-profile": {
            "arch-linux-keyring",
            "arch-linux-marble-shell",
            "arch-linux-colloid-gtk3",
            "arch-linux-colloid-icons",
        },
        "arch-linux-marble-gdm": {
            "arch-linux-keyring",
            "arch-linux-marble-shell",
            "arch-linux-colloid-icons",
            "arch-linux-marble-profile",
        },
    }
    for package, required in expected_edges.items():
        if not required <= project_dependencies.get(package, set()):
            fail(f"{package}: project package dependency boundary differs")
    if "arch-linux-marble-gdm" in project_dependencies["arch-linux-marble-profile"]:
        fail("Marble GDM must remain a separate opt-in package")

    keyring = parse_srcinfo(PACKAGES / "arch-linux-keyring" / ".SRCINFO")
    source_to_sum = {
        alias_and_locator(source)[0]: checksum
        for source, checksum in zip(keyring["source"], keyring["sha256sums"], strict=True)
    }
    for name in ("arch-linux.gpg", "primary-fingerprint", "signing-subkey-fingerprint"):
        if source_to_sum.get(name) != file_sha(TRUST / name):
            fail(f"keyring package is not bound to repository/trust/{name}")

    if report:
        print(f"package metadata checks passed: packages={len(package_names)}")


def main() -> None:
    if len(sys.argv) == 1:
        verify_metadata()
        return
    if len(sys.argv) == 4 and sys.argv[1] == "--verify-package":
        verify_metadata(report=False)
        verify_package_archive(pathlib.Path(sys.argv[2]), sys.argv[3])
        return
    print(f"Usage: {sys.argv[0]} [--verify-package ARCHIVE EXPECTED_PACKAGE]", file=sys.stderr)
    raise SystemExit(2)


if __name__ == "__main__":
    main()
