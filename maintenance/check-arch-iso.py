#!/usr/bin/env python3
"""Detect official Arch x86_64 installation-media drift without changing accepted state."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import os
import pathlib
import re
import stat
import sys
import urllib.error
import urllib.parse
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parent.parent
OFFICIAL_METADATA_SOURCE = "https://archlinux.org/api/v1/releng/releases/"
OFFICIAL_ISO_ORIGIN = "https://geo.mirror.pkgbuild.com"
DEFAULT_STATE = ROOT / "maintenance" / "accepted-arch-iso.json"
MAXIMUM_INPUT_BYTES = 2 * 1024 * 1024
VERSION = re.compile(r"[0-9]{4}\.[0-9]{2}\.[0-9]{2}\Z")
DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}\Z")
SHA256 = re.compile(r"[a-f0-9]{64}\Z")
QEMU_NEW_ISO = (
    "Minimal real-QEMU + Stock real-QEMU are required before updating accepted state."
)


class DetectorError(ValueError):
    """One bounded detector input failed validation."""


@dataclasses.dataclass(frozen=True)
class ArchIso:
    source: str
    version: str
    release_date: str
    iso_name: str
    iso_url: str
    sha256: str

    def output(self, prefix: str) -> dict[str, str]:
        return {
            f"{prefix}_version": self.version,
            f"{prefix}_release_date": self.release_date,
            f"{prefix}_iso_name": self.iso_name,
            f"{prefix}_iso_url": self.iso_url,
            f"{prefix}_sha256": self.sha256,
        }


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise DetectorError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def decode_json(data: bytes, description: str) -> object:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise DetectorError(f"{description} is not UTF-8") from error
    try:
        return json.loads(
            text,
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=lambda value: (_ for _ in ()).throw(
                DetectorError(f"non-finite JSON number: {value}")
            ),
        )
    except (json.JSONDecodeError, DetectorError) as error:
        raise DetectorError(f"invalid {description}: {error}") from error


def read_regular_file(path: pathlib.Path, description: str) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise DetectorError(f"cannot open {description}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise DetectorError(f"{description} is not a single-link regular file")
        if before.st_size > MAXIMUM_INPUT_BYTES:
            raise DetectorError(f"{description} exceeds the size limit")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(65536, MAXIMUM_INPUT_BYTES + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > MAXIMUM_INPUT_BYTES:
                raise DetectorError(f"{description} exceeds the size limit")
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    identity = lambda value: (
        value.st_dev,
        value.st_ino,
        value.st_mode,
        value.st_nlink,
        value.st_size,
        value.st_mtime_ns,
        value.st_ctime_ns,
    )
    if identity(before) != identity(after) or total != before.st_size:
        raise DetectorError(f"{description} changed while it was read")
    return b"".join(chunks)


def validate_source(source: str) -> None:
    parsed = urllib.parse.urlsplit(source)
    if (
        source != OFFICIAL_METADATA_SOURCE
        or parsed.scheme != "https"
        or parsed.netloc != "archlinux.org"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise DetectorError("metadata source is not the exact official Arch HTTPS API")


def fetch_metadata(source: str) -> bytes:
    validate_source(source)
    request = urllib.request.Request(
        source,
        headers={"Accept": "application/json", "User-Agent": "arch-linux-maintenance/1"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200 or response.geturl() != source:
                raise DetectorError("official metadata response redirected or was not HTTP 200")
            content_type = response.headers.get_content_type()
            if content_type != "application/json":
                raise DetectorError("official metadata response is not application/json")
            declared_size = response.headers.get("Content-Length")
            if declared_size is not None:
                try:
                    parsed_size = int(declared_size, 10)
                except ValueError as error:
                    raise DetectorError("official metadata has malformed Content-Length") from error
                if parsed_size < 1 or parsed_size > MAXIMUM_INPUT_BYTES:
                    raise DetectorError("official metadata Content-Length is outside bounds")
            data = response.read(MAXIMUM_INPUT_BYTES + 1)
    except (OSError, urllib.error.URLError) as error:
        raise DetectorError("cannot read official Arch metadata") from error
    if not data or len(data) > MAXIMUM_INPUT_BYTES:
        raise DetectorError("official metadata body is empty or too large")
    return data


def validate_calendar(version: str, release_date: str) -> None:
    if VERSION.fullmatch(version) is None or DATE.fullmatch(release_date) is None:
        raise DetectorError("release version/date format is malformed")
    if version.replace(".", "-") != release_date:
        raise DetectorError("release version and date disagree")
    try:
        parsed = dt.date.fromisoformat(release_date)
    except ValueError as error:
        raise DetectorError("release date is not a calendar date") from error
    if parsed.isoformat() != release_date:
        raise DetectorError("release date is not canonical")


def require_text(mapping: dict[str, object], key: str, description: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        raise DetectorError(f"{description} {key} is missing or not text")
    return value


def validate_iso(
    *, source: str, version: str, release_date: str, iso_path: str, sha256: str
) -> ArchIso:
    validate_source(source)
    validate_calendar(version, release_date)
    expected_name = f"archlinux-{version}-x86_64.iso"
    expected_path = f"/iso/{version}/{expected_name}"
    if iso_path != expected_path:
        raise DetectorError("latest ISO path/name/architecture is not canonical")
    if SHA256.fullmatch(sha256) is None:
        raise DetectorError("latest ISO SHA-256 is malformed")
    iso_url = f"{OFFICIAL_ISO_ORIGIN}{iso_path}"
    parsed_iso = urllib.parse.urlsplit(iso_url)
    if (
        parsed_iso.scheme != "https"
        or parsed_iso.netloc != "geo.mirror.pkgbuild.com"
        or parsed_iso.path != expected_path
        or parsed_iso.query
        or parsed_iso.fragment
    ):
        raise DetectorError("latest ISO HTTPS URL is malformed")
    return ArchIso(
        source=source,
        version=version,
        release_date=release_date,
        iso_name=expected_name,
        iso_url=iso_url,
        sha256=sha256,
    )


def parse_official_metadata(data: bytes, source: str) -> ArchIso:
    document = decode_json(data, "official release metadata")
    if not isinstance(document, dict):
        raise DetectorError("official release metadata root is not an object")
    if set(document) != {"version", "releases", "latest_version"}:
        raise DetectorError("official release metadata top-level fields differ")
    if type(document["version"]) is not int or document["version"] != 1:
        raise DetectorError("official release metadata schema is not version 1")
    latest_version = require_text(document, "latest_version", "metadata")
    if VERSION.fullmatch(latest_version) is None:
        raise DetectorError("latest_version is malformed")
    releases = document["releases"]
    if not isinstance(releases, list) or not 1 <= len(releases) <= 512:
        raise DetectorError("official release list is empty or outside bounds")
    candidates: list[dict[str, object]] = []
    modern_versions: list[str] = []
    for release in releases:
        if not isinstance(release, dict):
            raise DetectorError("official release entry is not an object")
        version_value = release.get("version")
        if isinstance(version_value, str) and VERSION.fullmatch(version_value):
            modern_versions.append(version_value)
        if version_value == latest_version:
            candidates.append(release)
    if len(candidates) != 1:
        raise DetectorError("latest_version does not identify exactly one release")
    if not modern_versions or max(modern_versions) != latest_version:
        raise DetectorError("latest_version is not the greatest calendar release")
    release = candidates[0]
    if release.get("available") is not True:
        raise DetectorError("latest release is not explicitly available")
    version = require_text(release, "version", "latest release")
    release_date = require_text(release, "release_date", "latest release")
    iso_path = require_text(release, "iso_url", "latest release")
    sha256 = require_text(release, "sha256_sum", "latest release")
    return validate_iso(
        source=source,
        version=version,
        release_date=release_date,
        iso_path=iso_path,
        sha256=sha256,
    )


def parse_accepted_state(data: bytes) -> ArchIso:
    document = decode_json(data, "accepted Arch ISO state")
    if not isinstance(document, dict):
        raise DetectorError("accepted state root is not an object")
    expected_keys = {
        "schema",
        "source",
        "version",
        "releaseDate",
        "isoName",
        "isoUrl",
        "sha256",
    }
    if set(document) != expected_keys or document.get("schema") != 1:
        raise DetectorError("accepted state fields/schema differ")
    source = require_text(document, "source", "accepted state")
    version = require_text(document, "version", "accepted state")
    release_date = require_text(document, "releaseDate", "accepted state")
    iso_name = require_text(document, "isoName", "accepted state")
    iso_url = require_text(document, "isoUrl", "accepted state")
    sha256 = require_text(document, "sha256", "accepted state")
    expected = validate_iso(
        source=source,
        version=version,
        release_date=release_date,
        iso_path=f"/iso/{version}/{iso_name}",
        sha256=sha256,
    )
    if iso_name != expected.iso_name or iso_url != expected.iso_url:
        raise DetectorError("accepted state ISO name/URL differs from its version")
    return expected


def write_github_output(path: pathlib.Path, output: dict[str, str]) -> None:
    for key, value in output.items():
        if not re.fullmatch(r"[a-z0-9_]+", key) or "\n" in value or "\r" in value:
            raise DetectorError("unsafe GitHub output field")
    with path.open("a", encoding="utf-8", newline="\n") as stream:
        for key, value in output.items():
            stream.write(f"{key}={value}\n")


def build_output(accepted: ArchIso, detected: ArchIso) -> dict[str, str]:
    status = "unchanged" if accepted == detected else "changed"
    output = {
        "status": status,
        "authoritative_source": detected.source,
        "qemu_requirement": "none" if status == "unchanged" else QEMU_NEW_ISO,
    }
    output.update(accepted.output("old"))
    output.update(detected.output("new"))
    return output


def print_output(output: dict[str, str]) -> None:
    headline = (
        "Arch ISO detector: unchanged"
        if output["status"] == "unchanged"
        else "Arch ISO detector: CHANGE DETECTED"
    )
    print(headline)
    for key in (
        "authoritative_source",
        "old_version",
        "old_release_date",
        "old_iso_name",
        "old_iso_url",
        "old_sha256",
        "new_version",
        "new_release_date",
        "new_iso_name",
        "new_iso_url",
        "new_sha256",
        "qemu_requirement",
    ):
        print(f"{key}={output[key]}")
    print("automatic_trust_update=forbidden")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--metadata",
        type=pathlib.Path,
        help="read a deterministic metadata fixture instead of the network",
    )
    parser.add_argument(
        "--source-url",
        default=OFFICIAL_METADATA_SOURCE,
        help="declared authoritative source (must equal the official API)",
    )
    parser.add_argument("--state", type=pathlib.Path, default=DEFAULT_STATE)
    parser.add_argument("--github-output", type=pathlib.Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        validate_source(arguments.source_url)
        state_data = read_regular_file(arguments.state, "accepted state")
        accepted = parse_accepted_state(state_data)
        if arguments.metadata is None:
            metadata_data = fetch_metadata(arguments.source_url)
        else:
            metadata_data = read_regular_file(arguments.metadata, "metadata fixture")
        detected = parse_official_metadata(metadata_data, arguments.source_url)
        if detected.version < accepted.version:
            raise DetectorError("official latest release predates accepted state")
        output = build_output(accepted, detected)
        print_output(output)
        if arguments.github_output is not None:
            write_github_output(arguments.github_output, output)
    except DetectorError as error:
        print(f"Arch ISO detector failed closed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
