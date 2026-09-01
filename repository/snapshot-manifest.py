#!/usr/bin/env python3
"""Create or verify the exact flat signed-repository manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import stat
from typing import NoReturn

SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]*$")
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_OID = re.compile(r"^[0-9a-f]{40}$")
MANIFEST = "repository-manifest.json"
SIGNATURE = f"{MANIFEST}.sig"
BUILD_KEYS = {
    "schema",
    "sourceCommit",
    "sourceTree",
    "installerSha256",
    "packageSetSha256",
    "sourceDateEpoch",
    "unsignedManifestSha256",
    "packages",
}
MANIFEST_KEYS = {
    "schema",
    "repository",
    "architecture",
    "releaseVersion",
    "sourceCommit",
    "sourceTree",
    "installerSha256",
    "packageSetSha256",
    "sourceDateEpoch",
    "buildMetadataSha256",
    "unsignedManifestSha256",
    "files",
}


def die(message: str) -> NoReturn:
    raise SystemExit(f"snapshot manifest error: {message}")


def digest(path: pathlib.Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def canonical_json(path: pathlib.Path, label: str) -> tuple[dict[str, object], bytes]:
    if not path.is_file() or path.is_symlink() or path.stat().st_nlink != 1:
        die(f"{label} is missing, linked, or not regular")
    if stat.S_IMODE(path.stat().st_mode) != 0o644:
        die(f"{label} mode is not 0644")
    raw = path.read_bytes()
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        die(f"{label} is not valid UTF-8 JSON: {exc}")
    if not isinstance(value, dict):
        die(f"{label} is not a JSON object")
    canonical = json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n"
    if raw != canonical:
        die(f"{label} JSON is not canonical")
    return value, raw


def checked_build_metadata(path: pathlib.Path) -> dict[str, object]:
    data, _ = canonical_json(path, "build metadata")
    if set(data) != BUILD_KEYS:
        die("build metadata closure differs")
    if data["schema"] != 2:
        die("build metadata schema differs")
    if not isinstance(data["sourceCommit"], str) or not GIT_OID.fullmatch(data["sourceCommit"]):
        die("build metadata sourceCommit is invalid")
    if not isinstance(data["sourceTree"], str) or not GIT_OID.fullmatch(data["sourceTree"]):
        die("build metadata sourceTree is invalid")
    for name in ("installerSha256", "packageSetSha256", "unsignedManifestSha256"):
        if not isinstance(data[name], str) or not SHA256.fullmatch(data[name]):
            die(f"build metadata {name} is invalid")
    epoch = data["sourceDateEpoch"]
    if not isinstance(epoch, int) or isinstance(epoch, bool) or epoch <= 0:
        die("build metadata sourceDateEpoch is invalid")
    packages = data["packages"]
    if not isinstance(packages, list) or not packages:
        die("build metadata packages list is empty or invalid")
    previous: bytes | None = None
    for package in packages:
        if not isinstance(package, str) or not SAFE_NAME.fullmatch(package) or not package.endswith(".pkg.tar.zst"):
            die("build metadata package name is invalid")
        encoded = package.encode("utf-8")
        if previous is not None and encoded <= previous:
            die("build metadata packages are not strictly byte-sorted")
        previous = encoded
    return data


def checked_files(root: pathlib.Path, *, omit_manifest: bool) -> list[pathlib.Path]:
    if not root.is_dir() or root.is_symlink():
        die(f"unsafe snapshot directory: {root}")
    files: list[pathlib.Path] = []
    for path in sorted(root.iterdir(), key=lambda item: item.name.encode("utf-8")):
        if omit_manifest and path.name in {MANIFEST, SIGNATURE}:
            continue
        if not SAFE_NAME.fullmatch(path.name):
            die(f"unsafe snapshot object name: {path.name!r}")
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            die(f"snapshot object is not a single-link regular file: {path.name}")
        if stat.S_IMODE(info.st_mode) != 0o644:
            die(f"snapshot object mode is not 0644: {path.name}")
        if info.st_size <= 0:
            die(f"snapshot object is empty: {path.name}")
        files.append(path)
    return files


def create(root: pathlib.Path, version: str, build_metadata: pathlib.Path) -> None:
    if not SEMVER.fullmatch(version):
        die("release version must be a SemVer triplet")
    target = root / MANIFEST
    if target.exists() or target.is_symlink():
        die(f"manifest already exists: {target}")
    records = [
        {"name": path.name, "sha256": digest(path), "size": path.stat().st_size}
        for path in checked_files(root, omit_manifest=True)
    ]
    if not records:
        die("snapshot contains no public files")
    build = checked_build_metadata(build_metadata)
    document = {
        "schema": 2,
        "repository": "arch-linux",
        "architecture": "x86_64",
        "releaseVersion": version,
        "sourceCommit": build["sourceCommit"],
        "sourceTree": build["sourceTree"],
        "installerSha256": build["installerSha256"],
        "packageSetSha256": build["packageSetSha256"],
        "sourceDateEpoch": build["sourceDateEpoch"],
        "buildMetadataSha256": digest(build_metadata),
        "unsignedManifestSha256": build["unsignedManifestSha256"],
        "files": records,
    }
    target.write_text(
        json.dumps(document, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    target.chmod(0o644)


def verify(root: pathlib.Path, expected: dict[str, object]) -> None:
    manifest = root / MANIFEST
    if not manifest.is_file() or manifest.is_symlink() or manifest.stat().st_nlink != 1:
        die("manifest is missing, linked, or not regular")
    if stat.S_IMODE(manifest.stat().st_mode) != 0o644:
        die("manifest mode is not 0644")
    document, _ = canonical_json(manifest, "manifest")
    if set(document) != MANIFEST_KEYS:
        die("manifest top-level closure differs")
    if document["schema"] != 2 or document["repository"] != "arch-linux" or document["architecture"] != "x86_64":
        die("manifest identity differs")
    version = document["releaseVersion"]
    if not isinstance(version, str) or not SEMVER.fullmatch(version):
        die("manifest releaseVersion is invalid")
    for name, value in expected.items():
        if document.get(name) != value:
            die(f"manifest {name} differs")
    if not isinstance(document["sourceCommit"], str) or not GIT_OID.fullmatch(document["sourceCommit"]):
        die("manifest sourceCommit is invalid")
    if not isinstance(document["sourceTree"], str) or not GIT_OID.fullmatch(document["sourceTree"]):
        die("manifest sourceTree is invalid")
    for name in ("installerSha256", "packageSetSha256", "buildMetadataSha256", "unsignedManifestSha256"):
        if not isinstance(document[name], str) or not SHA256.fullmatch(document[name]):
            die(f"manifest {name} is invalid")
    epoch = document["sourceDateEpoch"]
    if not isinstance(epoch, int) or isinstance(epoch, bool) or epoch <= 0:
        die("manifest sourceDateEpoch is invalid")
    records = document["files"]
    if not isinstance(records, list) or not records:
        die("manifest files list is empty or invalid")

    expected_names: list[str] = []
    previous: bytes | None = None
    for record in records:
        if not isinstance(record, dict) or set(record) != {"name", "sha256", "size"}:
            die("manifest file record closure differs")
        name, checksum, size = record["name"], record["sha256"], record["size"]
        if not isinstance(name, str) or not SAFE_NAME.fullmatch(name) or name in {MANIFEST, SIGNATURE}:
            die("manifest contains an unsafe name")
        encoded = name.encode("utf-8")
        if previous is not None and encoded <= previous:
            die("manifest records are not strictly byte-sorted")
        previous = encoded
        if not isinstance(checksum, str) or not SHA256.fullmatch(checksum):
            die(f"manifest checksum is invalid: {name}")
        if not isinstance(size, int) or size <= 0:
            die(f"manifest size is invalid: {name}")
        path = root / name
        if not path.is_file() or path.is_symlink() or path.stat().st_nlink != 1:
            die(f"manifest object is missing, linked, or not regular: {name}")
        if stat.S_IMODE(path.stat().st_mode) != 0o644:
            die(f"manifest object mode is not 0644: {name}")
        if path.stat().st_size != size or digest(path) != checksum:
            die(f"manifest object differs: {name}")
        expected_names.append(name)

    actual_names = [path.name for path in checked_files(root, omit_manifest=True)]
    if actual_names != expected_names:
        die("snapshot file closure differs from manifest")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    create_parser = subparsers.add_parser("create")
    create_parser.add_argument("snapshot", type=pathlib.Path)
    create_parser.add_argument("version")
    create_parser.add_argument("--build-metadata", type=pathlib.Path, required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("snapshot", type=pathlib.Path)
    verify_parser.add_argument("--version", required=True)
    verify_parser.add_argument("--source-commit", required=True)
    verify_parser.add_argument("--source-tree", required=True)
    verify_parser.add_argument("--installer-sha256", required=True)
    verify_parser.add_argument("--package-set-sha256", required=True)
    verify_parser.add_argument("--source-date-epoch", type=int, required=True)
    verify_parser.add_argument("--build-metadata-sha256", required=True)
    verify_parser.add_argument("--unsigned-manifest-sha256", required=True)
    args = parser.parse_args()
    root = args.snapshot.resolve()
    if args.command == "create":
        create(root, args.version, args.build_metadata.resolve())
    else:
        expected = {
            "releaseVersion": args.version,
            "sourceCommit": args.source_commit,
            "sourceTree": args.source_tree,
            "installerSha256": args.installer_sha256,
            "packageSetSha256": args.package_set_sha256,
            "sourceDateEpoch": args.source_date_epoch,
            "buildMetadataSha256": args.build_metadata_sha256,
            "unsignedManifestSha256": args.unsigned_manifest_sha256,
        }
        verify(root, expected)


if __name__ == "__main__":
    main()
