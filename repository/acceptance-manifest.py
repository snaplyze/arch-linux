#!/usr/bin/python3 -I
"""Create and verify the schema-1 exact-14/18 release acceptance manifest."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tarfile
from typing import Callable


HEX40 = re.compile(r"[a-f0-9]{40}\Z")
HEX64 = re.compile(r"[a-f0-9]{64}\Z")
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+\Z")
RUN_ID = re.compile(r"[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}\Z")
SAFE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9+._-]*\Z")
MAX_EVIDENCE = 500 * 1024 * 1024
MAX_OBJECTS = 20_000
MAX_FILE = 64 * 1024 * 1024
MAX_JSON = 8 * 1024 * 1024
MAX_TEXT = 16 * 1024 * 1024
SCENARIOS = (
    "minimal-ext4-systemdboot",
    "stock-gnome-btrfs-luks2-plymouth-grub",
    "marble-gnome-btrfs-luks2-plymouth-systemdboot",
)
PREFIXES = {SCENARIOS[0]: "minimal", SCENARIOS[1]: "luksgrub", SCENARIOS[2]: "marble"}
PHASES = ("firstboot", "postreboot")
RUN_FILES = {
    "OVMF_VARS.final.sha256", "OVMF_VARS.initial.sha256", "assertions.tsv",
    "evidence-size.txt", "harness.sha256", "identity.txt", "payload.iso.sha256",
    "qemu-version.txt", "result.json", "runtime-inputs.sha256",
}
EVIDENCE_FIXED = {
    "scenario.log.gz", "final-qemu-img-check.txt", "no-qemu-process.txt",
    "repository-manifest.json", "repository-manifest.json.sig", "repository-objects.tsv",
    "firstboot-qemu.identity", "postreboot-qemu.identity", "preseal-harness-check.txt",
}
HARNESS_FILES = (
    "tests/vm/run.sh", "tests/vm/frame-evidence.py", "tests/vm/qga-client.py",
    "tests/vm/https-server.py", "tests/vm/prepare-marble-repository.sh",
    "tests/vm/guest/bootstrap.sh", "tests/vm/guest/verify.sh",
)
EXPECTED_ASSERTIONS = {
    SCENARIOS[0]: (
        "accepted-official-arch-iso", "actual-installer-executes", "install-completes",
        "uefi-gpt-ext4-systemd-boot", "minimal-tty-profile", "installed-tty-boot",
        "network-works", "failed-units-zero-firstboot", "pacman-syu",
        "reboot-and-tty-return", "failed-units-zero-postreboot", "clean-shutdown",
        "qemu-exits", "qemu-img-check-and-no-process",
    ),
    SCENARIOS[1]: (
        "accepted-official-arch-iso", "actual-installer-executes",
        "uefi-gpt-luks2-btrfs-grub", "stock-plymouth-no-repair",
        "luks-partition-mapper-binding", "encrypted-btrfs-subvolumes-fstab",
        "systemd-sd-encrypt-plymouth-grub-initramfs", "grub-efi-archlinux-target",
        "grub-config-encrypted-root-contract", "first-grub-plymouth-luks-framebuffer",
        "first-luks-unlock-to-gdm", "real-gdm-password-login-first",
        "stock-network-dns-zero-failures", "luks2-btrfs-health",
        "locale-keyboard-formats-shortcuts", "lock-password-unlock", "pacman-syu",
        "grub-regeneration-idempotent-qkk", "reboot-and-second-grub-plymouth-luks",
        "second-unlock-gdm-login", "reboot-preserves-encrypted-grub-contract",
        "clean-shutdown-image-no-qemu",
    ),
    SCENARIOS[2]: (
        "accepted-iso-exact-installer", "encrypted-btrfs-systemdboot-marble-optin",
        "experimental-gdm-stock-fallback", "graphical-plymouth-unlock",
        "gdm-user-password-no-autologin", "first-gdm-login-wayland", "marble-shell-active",
        "colloid-gtk3-icons-bibata-gtk4-stock", "user-themes-extension-profile",
        "gdm-process-scoped-overlays", "user-shell-overlay-isolation", "vendor-paths-clean",
        "project-packages-qkk-clean", "lock-password-unlock", "update-hooks-safe",
        "reboot-plymouth-gdm-reactivation", "second-gdm-login-wayland",
        "gdm-stock-fallback-and-restore", "marble-package-removal-stock", "marble-package-reinstall",
        "clean-poweroff-image-health-hygiene",
    ),
}
SNAPSHOT_MANIFEST_KEYS = {
    "schema", "repository", "architecture", "releaseVersion", "sourceCommit", "sourceTree",
    "installerSha256", "packageSetSha256", "sourceDateEpoch", "buildMetadataSha256",
    "unsignedManifestSha256", "files",
}
BUILD_METADATA_KEYS = {
    "schema", "sourceCommit", "sourceTree", "installerSha256", "packageSetSha256",
    "sourceDateEpoch", "unsignedManifestSha256", "packages",
}
RESULT_KEYS = set(
    "assertions buildMetadataSha256 exitStatus failedPhase harnessSha256 "
    "inputMode installerSha256 isoSha256 "
    "releaseSha256sumsSha256 releaseVersion repositoryDatabaseSha256 "
    "repositoryDatabaseSignatureSha256 repositoryFilesSha256 repositoryFilesSignatureSha256 "
    "repositoryManifestSha256 repositoryManifestSignatureSha256 repositoryObjects "
    "repositoryPackageSetSha256 repositoryPrimaryFingerprint repositoryPublicKeySha256 "
    "repositorySigningFingerprint repositorySnapshotSha256 retainedEvidenceBytes runId scenario "
    "screenshots snapshotVerification sourceCommit sourceTree status targetSerial "
    "unsignedManifestSha256".split()
)
MANIFEST_KEYS = {
    "schema", "status", "releaseVersion", "sourceCommit", "sourceTree", "sourceTreeSha256",
    "buildMetadataSha256", "unsignedManifestSha256", "repositorySnapshotSha256",
    "phaseAManifestSha256", "phaseAAggregateSha256", "phaseAAssets",
    "evidenceArchiveSha256", "evidenceArchiveSizeBytes", "qemu", "deferred",
}
SECRET_MARKERS = (
    b"-----BEGIN PGP " b"PRIVATE KEY BLOCK-----",
    b"-----BEGIN OPENSSH " b"PRIVATE KEY-----",
    b"-----BEGIN RSA " b"PRIVATE KEY-----",
    b"-----BEGIN EC " b"PRIVATE KEY-----",
)
SECRET_MARKER_OVERLAP = max(len(marker) for marker in SECRET_MARKERS) - 1


class ManifestError(ValueError):
    pass


def fail(message: str) -> None:
    raise ManifestError(message)


def exact_keys(value: object, keys: set[str], label: str) -> dict[str, object]:
    if not isinstance(value, dict) or set(value) != keys:
        fail(f"{label} schema differs")
    return value


def safe_file(path: Path, limit: int | None = None) -> os.stat_result:
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or metadata.st_size <= 0:
        fail(f"unsafe regular file: {path.name}")
    if limit is not None and metadata.st_size > limit:
        fail(f"oversized regular file: {path.name}")
    return metadata


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_json_bytes(raw: bytes, label: str) -> dict[str, object]:
    if not 0 < len(raw) <= MAX_JSON:
        fail(f"{label} is empty or oversized")
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{label} JSON is invalid: {error}")
    if not isinstance(value, dict):
        fail(f"{label} is not one object")
    if raw != (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode():
        fail(f"{label} JSON is not canonical")
    return value


def canonical_json(path: Path, label: str) -> dict[str, object]:
    metadata = safe_file(path, MAX_JSON)
    with path.open("rb") as stream:
        return canonical_json_bytes(stream.read(metadata.st_size + 1), label)


def phase_a_names(version: str) -> tuple[str, ...]:
    archive = f"arch-linux-repository-{version}.tar.zst"
    return tuple(sorted((
        "BUILD-METADATA.json", "RELEASE-SHA256SUMS", "RELEASE-SHA256SUMS.sig",
        "UNSIGNED-SHA256SUMS", "arch-linux-installer.sh", "arch-linux-installer.sh.sha256",
        "arch-linux-installer.sh.sig", "arch-linux.gpg", "install.sh", "primary-fingerprint",
        "signing-subkey-fingerprint", archive, f"{archive}.sha256", f"{archive}.sig",
    )))


def phase_a_map(root: Path, version: str) -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for name in phase_a_names(version):
        path = root / name
        metadata = safe_file(path)
        result[name] = {"sha256": sha256(path), "size": metadata.st_size}
    return result


def phase_a_aggregate(assets: dict[str, dict[str, object]]) -> str:
    digest = hashlib.sha256()
    for name in sorted(assets):
        record = assets[name]
        digest.update(name.encode("ascii") + b"\0")
        digest.update(str(record["sha256"]).encode("ascii") + b"\0")
        digest.update(str(record["size"]).encode("ascii") + b"\n")
    return digest.hexdigest()


def exact_int(value: object, minimum: int = 0) -> bool:
    return type(value) is int and value >= minimum


def ppm_geometry(prefix: bytes, size: int) -> tuple[int, int]:
    match = re.match(rb"\AP6\n([1-9][0-9]{0,4}) ([1-9][0-9]{0,4})\n255\n", prefix)
    if match is None:
        fail("PPM header is not exact strict P6")
    width, height = int(match.group(1)), int(match.group(2))
    if width > 8192 or height > 8192 or size != match.end() + width * height * 3:
        fail("PPM dimensions or payload size differ")
    return width, height


def file_ppm_geometry(path: Path) -> tuple[int, int]:
    metadata = safe_file(path, MAX_FILE)
    with path.open("rb") as stream:
        prefix = stream.read(96)
    return ppm_geometry(prefix, metadata.st_size)


def sha256_rows(raw: bytes, expected_names: tuple[str, ...], label: str) -> dict[str, str]:
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        fail(f"{label} is not UTF-8: {error}")
    if len(lines) != len(expected_names):
        fail(f"{label} row closure differs")
    result: dict[str, str] = {}
    for line, expected in zip(lines, expected_names, strict=True):
        match = re.fullmatch(r"([a-f0-9]{64})  (.+)", line)
        if match is None or match.group(2) != expected or match.group(1) == "0" * 64:
            fail(f"{label} row differs")
        result[expected] = match.group(1)
    return result


def snapshot_contract(root: Path, version: str, commit: str, tree: str,
                      build_hash: str, unsigned_hash: str) -> dict[str, object]:
    archive_name = f"arch-linux-repository-{version}.tar.zst"
    archive_path = root / archive_name
    safe_file(archive_path, MAX_EVIDENCE)
    process = subprocess.Popen(
        ["/usr/bin/zstd", "--decompress", "--stdout", "--", str(archive_path)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert process.stdout is not None
    mapping: dict[str, dict[str, object]] = {}
    retained: dict[str, bytes] = {}
    total = 0
    expected_mtime = source_epoch()
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
            for member in archive:
                original = member.name.rstrip("/")
                pure = PurePosixPath(original)
                if (not original or member.name.startswith("/") or "\\" in member.name or
                        any(part in ("", ".", "..") for part in pure.parts) or
                        pure.as_posix() != original or original in mapping):
                    fail("repository snapshot archive path differs")
                if (member.uid != 0 or member.gid != 0 or member.mtime != expected_mtime or
                        member.pax_headers):
                    fail("repository snapshot archive metadata differs")
                mode = member.mode & 0o7777
                if member.isdir():
                    if mode != 0o755 or member.size != 0:
                        fail("repository snapshot directory metadata differs")
                    mapping[original] = {"type": "directory", "mode": mode, "size": 0}
                elif member.isreg() and member.type == tarfile.REGTYPE:
                    if mode != 0o644 or not 0 < member.size <= MAX_FILE:
                        fail("repository snapshot file metadata differs")
                    source = archive.extractfile(member)
                    if source is None:
                        fail("repository snapshot object cannot be read")
                    digest = hashlib.sha256()
                    chunks: list[bytes] = []
                    read = 0
                    while True:
                        chunk = source.read(min(1024 * 1024, member.size - read + 1))
                        if not chunk:
                            break
                        read += len(chunk)
                        if read > member.size:
                            fail("repository snapshot member exceeds its header")
                        digest.update(chunk)
                        if member.size <= MAX_JSON:
                            chunks.append(chunk)
                    if read != member.size:
                        fail("repository snapshot member is truncated")
                    mapping[original] = {
                        "type": "file", "mode": mode, "size": member.size,
                        "sha256": digest.hexdigest(),
                    }
                    if chunks:
                        retained[original] = b"".join(chunks)
                    total += member.size
                else:
                    fail("repository snapshot contains a link or special object")
                if len(mapping) > 64 or total > MAX_EVIDENCE:
                    fail("repository snapshot archive exceeds its bound")
    except (tarfile.TarError, OSError) as error:
        fail(f"repository snapshot archive is invalid: {error}")
    finally:
        process.stdout.close()
    stderr = process.stderr.read(MAX_TEXT + 1) if process.stderr is not None else b""
    if process.wait() != 0 or len(stderr) > MAX_TEXT:
        fail("repository snapshot archive decompression failed")
    if {name for name, item in mapping.items() if item["type"] == "directory"} != {
            "repo", "repo/x86_64"}:
        fail("repository snapshot directory closure differs")
    prefix = "repo/x86_64/"
    manifest_name = prefix + "repository-manifest.json"
    signature_name = manifest_name + ".sig"
    manifest_raw = retained.get(manifest_name)
    signature_raw = retained.get(signature_name)
    if manifest_raw is None or signature_raw is None:
        fail("repository snapshot manifest evidence is unavailable")
    manifest = canonical_json_bytes(manifest_raw, "repository snapshot manifest")
    exact_keys(manifest, SNAPSHOT_MANIFEST_KEYS, "repository snapshot manifest")
    if (manifest.get("schema") != 2 or manifest.get("repository") != "arch-linux" or
            manifest.get("architecture") != "x86_64" or manifest.get("releaseVersion") != version or
            manifest.get("sourceCommit") != commit or manifest.get("sourceTree") != tree or
            manifest.get("buildMetadataSha256") != build_hash or
            manifest.get("unsignedManifestSha256") != unsigned_hash or
            manifest.get("sourceDateEpoch") != expected_mtime):
        fail("repository snapshot manifest identity differs")
    for field in ("installerSha256", "packageSetSha256"):
        if not isinstance(manifest.get(field), str) or HEX64.fullmatch(str(manifest[field])) is None:
            fail("repository snapshot manifest source hash differs")
    build = canonical_json(root / "BUILD-METADATA.json", "Phase-A build metadata")
    exact_keys(build, BUILD_METADATA_KEYS, "Phase-A build metadata")
    if (sha256(root / "BUILD-METADATA.json") != build_hash or build.get("schema") != 2 or
            build.get("sourceCommit") != commit or build.get("sourceTree") != tree or
            build.get("installerSha256") != manifest.get("installerSha256") or
            build.get("packageSetSha256") != manifest.get("packageSetSha256") or
            build.get("sourceDateEpoch") != expected_mtime or
            build.get("unsignedManifestSha256") != unsigned_hash):
        fail("Phase-A build metadata identity differs")
    packages = build.get("packages")
    if (not isinstance(packages, list) or not packages or
            any(not isinstance(name, str) or SAFE_NAME.fullmatch(name) is None or
                not name.endswith(".pkg.tar.zst") for name in packages) or
            packages != sorted(set(packages))):
        fail("Phase-A build package closure differs")
    expected_objects = {
        "arch-linux.db", "arch-linux.db.sig", "arch-linux.db.tar.gz",
        "arch-linux.db.tar.gz.sig", "arch-linux.files", "arch-linux.files.sig",
        "arch-linux.files.tar.gz", "arch-linux.files.tar.gz.sig", "arch-linux.gpg",
        "primary-fingerprint", "signing-subkey-fingerprint",
        *(str(name) for name in packages), *(f"{name}.sig" for name in packages),
    }
    records = manifest.get("files")
    if not isinstance(records, list):
        fail("repository snapshot object closure is not a list")
    names: list[str] = []
    for record in records:
        exact_keys(record, {"name", "sha256", "size"}, "repository snapshot object")
        name, digest, size = record.get("name"), record.get("sha256"), record.get("size")
        if (not isinstance(name, str) or SAFE_NAME.fullmatch(name) is None or
                not isinstance(digest, str) or HEX64.fullmatch(digest) is None or
                not exact_int(size, 1)):
            fail("repository snapshot object record differs")
        item = mapping.get(prefix + name)
        if not isinstance(item, dict) or item.get("type") != "file" or item.get("sha256") != digest or item.get("size") != size:
            fail("repository snapshot object bytes differ from its manifest")
        names.append(name)
    if names != sorted(expected_objects):
        fail("repository snapshot object ordering differs")
    actual_files = {name[len(prefix):] for name, item in mapping.items()
                    if name.startswith(prefix) and item["type"] == "file"}
    if actual_files != set(names) | {"repository-manifest.json", "repository-manifest.json.sig"}:
        fail("repository snapshot file closure differs")
    object_map = {str(item["name"]): item for item in records}
    required = {
        "arch-linux.db.tar.gz", "arch-linux.db.tar.gz.sig", "arch-linux.files.tar.gz",
        "arch-linux.files.tar.gz.sig", "arch-linux.gpg", "primary-fingerprint",
        "signing-subkey-fingerprint",
    }
    if not required <= set(object_map):
        fail("repository snapshot required objects are absent")
    primary = (root / "primary-fingerprint").read_text(encoding="ascii").strip()
    signing = (root / "signing-subkey-fingerprint").read_text(encoding="ascii").strip()
    if (re.fullmatch(r"[A-F0-9]{40}", primary) is None or re.fullmatch(r"[A-F0-9]{40}", signing) is None or
            primary == signing):
        fail("Phase-A fingerprint files differ")
    phase_key_hash = sha256(root / "arch-linux.gpg")
    for name, expected in (("arch-linux.gpg", phase_key_hash),
                           ("primary-fingerprint", sha256(root / "primary-fingerprint")),
                           ("signing-subkey-fingerprint", sha256(root / "signing-subkey-fingerprint"))):
        if object_map[name]["sha256"] != expected:
            fail("repository snapshot trust differs from Phase A")
    return {
        "objects": records, "manifestRaw": manifest_raw, "manifestSignatureRaw": signature_raw,
        "manifestSha256": sha256_bytes(manifest_raw),
        "manifestSignatureSha256": sha256_bytes(signature_raw),
        "installerSha256": manifest["installerSha256"],
        "packageSetSha256": manifest["packageSetSha256"],
        "publicKeySha256": phase_key_hash, "primaryFingerprint": primary,
        "signingFingerprint": signing,
        "databaseSha256": object_map["arch-linux.db.tar.gz"]["sha256"],
        "databaseSignatureSha256": object_map["arch-linux.db.tar.gz.sig"]["sha256"],
        "filesSha256": object_map["arch-linux.files.tar.gz"]["sha256"],
        "filesSignatureSha256": object_map["arch-linux.files.tar.gz.sig"]["sha256"],
        "isoSha256": accepted_iso_sha256(),
    }


def inspect_binary_secret_markers(name: str, stream: object) -> None:
    tail = b""
    while True:
        chunk = stream.read(1024 * 1024)
        if not chunk:
            break
        payload = tail + chunk
        if any(marker in payload for marker in SECRET_MARKERS):
            fail(f"private key material appears in acceptance evidence: {name}")
        tail = payload[-SECRET_MARKER_OVERLAP:]


def inspect_secret_markers(name: str, raw: bytes) -> None:
    payload = raw
    if name.endswith("scenario.log.gz"):
        try:
            with gzip.GzipFile(fileobj=io.BytesIO(raw)) as stream:
                payload = stream.read(MAX_TEXT + 1)
        except (OSError, EOFError) as error:
            fail(f"scenario log gzip is invalid: {error}")
        if len(payload) > MAX_TEXT:
            fail("scenario log expands beyond its bound")
    if any(marker in payload for marker in SECRET_MARKERS):
        fail("private key material appears in acceptance evidence")
    if name.endswith(".ppm") or name.endswith(".sig"):
        return
    if re.search(rb"(?im)^(?:passphrase|password|recovery(?:[-_ ]?share)?|secret|token)\s*=", payload):
        fail("credential assignment appears in acceptance evidence")


def source_epoch() -> int:
    raw = (Path(__file__).resolve().parent / "source-date-epoch").read_text(encoding="ascii").strip()
    if not raw.isdigit():
        fail("source-date-epoch is invalid")
    return int(raw)


def accepted_iso_sha256() -> str:
    path = Path(__file__).resolve().parent.parent / "maintenance/accepted-arch-iso.json"
    metadata = safe_file(path, MAX_JSON)
    try:
        pairs = json.loads(
            path.read_bytes()[:metadata.st_size + 1].decode("utf-8"),
            object_pairs_hook=lambda value: value,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"accepted Arch ISO record is invalid: {error}")
    if not isinstance(pairs, list) or any(not isinstance(item, tuple) or len(item) != 2 for item in pairs):
        fail("accepted Arch ISO record is not one object")
    keys = [str(item[0]) for item in pairs]
    expected = {"schema", "source", "version", "releaseDate", "isoName", "isoUrl", "sha256"}
    if len(keys) != len(set(keys)) or set(keys) != expected:
        fail("accepted Arch ISO record closure differs")
    value = dict(pairs)
    digest = value.get("sha256")
    if (type(value.get("schema")) is not int or value.get("schema") != 1 or
            not isinstance(digest, str) or HEX64.fullmatch(digest) is None or
            not isinstance(value.get("isoName"), str) or value["isoName"] !=
            f"archlinux-{value.get('version')}-x86_64.iso" or
            not isinstance(value.get("isoUrl"), str) or not value["isoUrl"].startswith("https://")):
        fail("accepted Arch ISO record identity differs")
    return digest


def tree_map(root: Path, public_modes: bool = True) -> tuple[dict[str, dict[str, object]], int]:
    root_meta = root.lstat()
    if not stat.S_ISDIR(root_meta.st_mode) or stat.S_ISLNK(root_meta.st_mode):
        fail("evidence staging root is unsafe")
    result: dict[str, dict[str, object]] = {
        "evidence": {"type": "directory", "mode": stat.S_IMODE(root_meta.st_mode), "size": 0}
    }
    total = 0
    count = 1
    for current, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        current_path = Path(current)
        for name in directories:
            path = current_path / name
            metadata = path.lstat()
            if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                fail("evidence tree contains a linked or special directory")
            relative = PurePosixPath("evidence", *path.relative_to(root).parts).as_posix()
            mode = stat.S_IMODE(metadata.st_mode)
            if (public_modes and mode != 0o755) or (not public_modes and mode & 0o022):
                fail("evidence directory mode differs")
            result[relative] = {"type": "directory", "mode": mode, "size": 0}
            count += 1
        for name in files:
            path = current_path / name
            metadata = safe_file(path, MAX_FILE)
            mode = stat.S_IMODE(metadata.st_mode)
            if (public_modes and mode != 0o644) or (not public_modes and mode & 0o022):
                fail("evidence staged file mode differs")
            relative = PurePosixPath("evidence", *path.relative_to(root).parts).as_posix()
            result[relative] = {"type": "file", "mode": mode, "size": metadata.st_size,
                                "sha256": sha256(path)}
            with path.open("rb") as stream:
                inspect_binary_secret_markers(relative, stream)
            total += metadata.st_size
            count += 1
            if count > MAX_OBJECTS or total > MAX_EVIDENCE:
                fail("evidence tree exceeds its object or byte budget")
            if metadata.st_size <= MAX_TEXT and not name.endswith(".ppm"):
                inspect_secret_markers(relative, path.read_bytes())
    root_mode = stat.S_IMODE(root_meta.st_mode)
    result["evidence"]["mode"] = root_mode
    if ((public_modes and root_mode != 0o755) or (not public_modes and root_mode & 0o022) or
            (public_modes and any(item["mode"] != 0o755 for item in result.values()
                                  if item["type"] == "directory"))):
        fail("evidence staged directory mode differs")
    return result, total


def tree_identity(args: argparse.Namespace) -> None:
    mapping, total = tree_map(Path(args.root), public_modes=False)
    payload = json.dumps({"map": mapping, "total": total}, sort_keys=True,
                         separators=(",", ":")).encode()
    print(hashlib.sha256(payload).hexdigest())


def archive_readback(path: Path) -> tuple[
        dict[str, dict[str, object]], dict[str, bytes], dict[str, tuple[int, int]], int]:
    safe_file(path, MAX_EVIDENCE)
    process = subprocess.Popen(
        ["/usr/bin/zstd", "--decompress", "--stdout", "--", str(path)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert process.stdout is not None
    result: dict[str, dict[str, object]] = {}
    retained: dict[str, bytes] = {}
    ppm_dimensions: dict[str, tuple[int, int]] = {}
    total = 0
    names: list[str] = []
    expected_mtime = source_epoch()
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
            for member in archive:
                original = member.name.rstrip("/")
                pure = PurePosixPath(original)
                if (not original or member.name.startswith("/") or "\\" in member.name or
                        any(part in ("", ".", "..") for part in pure.parts) or pure.as_posix() != original):
                    fail("acceptance archive path is unsafe")
                name = pure.as_posix()
                if name in result:
                    fail("acceptance archive member repeats")
                if member.uid != 0 or member.gid != 0 or member.mtime != expected_mtime or member.pax_headers:
                    fail("acceptance archive ownership, time, or extension metadata differs")
                mode = member.mode & 0o7777
                if member.isdir():
                    if mode != 0o755 or member.size != 0:
                        fail("acceptance archive directory metadata differs")
                    result[name] = {"type": "directory", "mode": mode, "size": 0}
                elif member.isreg() and member.type == tarfile.REGTYPE:
                    if mode != 0o644 or not 0 < member.size <= MAX_FILE:
                        fail("acceptance archive file metadata differs")
                    stream = archive.extractfile(member)
                    if stream is None:
                        fail("acceptance archive file cannot be read")
                    digest = hashlib.sha256()
                    chunks: list[bytes] = []
                    prefix = bytearray()
                    marker_tail = b""
                    read = 0
                    while True:
                        chunk = stream.read(min(1024 * 1024, member.size - read + 1))
                        if not chunk:
                            break
                        read += len(chunk)
                        if read > member.size:
                            fail("acceptance archive member expands beyond its header")
                        digest.update(chunk)
                        marker_payload = marker_tail + chunk
                        if any(marker in marker_payload for marker in SECRET_MARKERS):
                            fail(f"private key material appears in acceptance evidence: {name}")
                        marker_tail = marker_payload[-SECRET_MARKER_OVERLAP:]
                        if name.endswith(".ppm") and len(prefix) < 96:
                            prefix.extend(chunk[:96 - len(prefix)])
                        if member.size <= MAX_TEXT and not name.endswith(".ppm"):
                            chunks.append(chunk)
                    if read != member.size:
                        fail("acceptance archive member is truncated")
                    raw = b"".join(chunks)
                    if raw:
                        inspect_secret_markers(name, raw)
                        retained[name] = raw
                    if name.endswith(".ppm"):
                        ppm_dimensions[name] = ppm_geometry(bytes(prefix), member.size)
                    result[name] = {"type": "file", "mode": mode, "size": member.size,
                                    "sha256": digest.hexdigest()}
                    total += member.size
                else:
                    fail("acceptance archive contains a link, sparse member, or special object")
                names.append(name)
                if len(names) > MAX_OBJECTS or total > MAX_EVIDENCE:
                    fail("acceptance archive exceeds its object or byte budget")
    except (tarfile.TarError, OSError) as error:
        fail(f"acceptance archive is invalid: {error}")
    finally:
        process.stdout.close()
    stderr = process.stderr.read(MAX_TEXT + 1) if process.stderr is not None else b""
    status = process.wait()
    if status != 0 or len(stderr) > MAX_TEXT:
        fail("acceptance archive decompression failed")
    if names != sorted(names) or not names or names[0] != "evidence":
        fail("acceptance archive ordering or root differs")
    return result, retained, ppm_dimensions, total


def expected_run_names(read: Callable[[str, int], bytes], scenario: str) -> tuple[set[str], dict[str, object]]:
    result = canonical_json_bytes(read("result.json", MAX_JSON), "QEMU result")
    screenshots = result.get("screenshots")
    if (not isinstance(screenshots, list) or
            not all(isinstance(name, str) and SAFE_NAME.fullmatch(name) and name.endswith(".ppm")
                    for name in screenshots) or screenshots != sorted(set(screenshots))):
        fail("QEMU diagnostic screenshot closure differs")
    top = set(RUN_FILES)
    if scenario == SCENARIOS[2]:
        top.add("repository-runtime.sha256")
    names = top | {f"evidence/{name}" for name in EVIDENCE_FIXED | set(screenshots)}
    return names, result


def parse_identity(raw: bytes, phase: str) -> dict[str, str]:
    try:
        lines = raw.decode("ascii").splitlines()
    except UnicodeDecodeError as error:
        fail(f"QEMU identity is not ASCII: {error}")
    values: dict[str, str] = {}
    for line in lines:
        if line.count("=") != 1:
            fail("QEMU identity syntax differs")
        key, value = line.split("=", 1)
        if key in values:
            fail("QEMU identity field repeats")
        values[key] = value
    expected = {"phase", "pid", "start_time", "qga_identity", "qmp_identity"}
    socket = re.compile(r"[1-9][0-9]*:[1-9][0-9]*\Z")
    socket_values = tuple(values.get(key, "") for key in
                          ("qga_identity", "qmp_identity"))
    socket_devices = {value.split(":", 1)[0] for value in socket_values if socket.fullmatch(value)}
    if (set(values) != expected or values.get("phase") != phase or not values["pid"].isdigit() or
            int(values["pid"]) <= 1 or not values["start_time"].isdigit() or
            int(values["start_time"]) <= 0 or
            not all(socket.fullmatch(value) for value in socket_values) or
            len(set(socket_values)) != 2 or len(socket_devices) != 1):
        fail("QEMU process/socket identity differs")
    return values


def validate_repository_objects(result: dict[str, object], read: Callable[[str, int], bytes],
                                contract: dict[str, object]) -> None:
    objects = result.get("repositoryObjects")
    if not isinstance(objects, list) or objects != contract["objects"]:
        fail("QEMU repository object closure differs")
    names: list[str] = []
    rows: list[str] = []
    for item in objects:
        exact_keys(item, {"name", "sha256", "size"}, "QEMU repository object")
        name, digest, size = item.get("name"), item.get("sha256"), item.get("size")
        if (not isinstance(name, str) or SAFE_NAME.fullmatch(name) is None or
                not isinstance(digest, str) or HEX64.fullmatch(digest) is None or
                type(size) is not int or size <= 0):
            fail("QEMU repository object metadata differs")
        names.append(name)
        rows.append(f"{name}\t{digest}\t{size}\n")
    if names != sorted(set(names)) or read("evidence/repository-objects.tsv", MAX_JSON) != "".join(rows).encode("ascii"):
        fail("QEMU repository object evidence differs")
    if (read("evidence/repository-manifest.json", MAX_JSON) != contract["manifestRaw"] or
            read("evidence/repository-manifest.json.sig", MAX_JSON) != contract["manifestSignatureRaw"]):
        fail("QEMU repository manifest differs from the Phase-A snapshot")


def single_sha256_row(raw: bytes, suffix: str, run_id: str, label: str) -> tuple[str, str]:
    try:
        line = raw.decode("utf-8").rstrip("\n")
    except UnicodeDecodeError as error:
        fail(f"{label} is not UTF-8: {error}")
    match = re.fullmatch(r"([a-f0-9]{64})  (/.+)", line)
    if (match is None or match.group(1) == "0" * 64 or not match.group(2).endswith(f"/{run_id}/{suffix}")):
        fail(f"{label} row differs")
    return match.group(1), match.group(2)


def validate_identity_record(raw: bytes, result: dict[str, object], scenario: str, run_id: str,
                             version: str, expected: dict[str, str], contract: dict[str, object],
                             bootstrap_sha256: str) -> None:
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        fail(f"QEMU identity is not UTF-8: {error}")
    serial_letters = {SCENARIOS[0]: "M", SCENARIOS[1]: "G", SCENARIOS[2]: "A"}
    models = {SCENARIOS[0]: "MIN", SCENARIOS[1]: "GRB", SCENARIOS[2]: "MAR"}
    base = (
        ("scenario", scenario), ("input_mode", "staged"), ("release_version", version),
        ("run_id", run_id), ("source_commit", str(result["sourceCommit"])),
        ("source_tree", str(result["sourceTree"])),
        ("installer_sha256", str(contract["installerSha256"])),
        ("bootstrap_sha256", bootstrap_sha256), ("harness_sha256", str(result["harnessSha256"])),
        ("iso_sha256", str(result["isoSha256"])), ("snapshot_sha256", expected["repositorySnapshotSha256"]),
        ("build_metadata_sha256", expected["buildMetadataSha256"]),
        ("unsigned_manifest_sha256", expected["unsignedManifestSha256"]),
        ("target_serial", str(result["targetSerial"])), ("target_vendor", "SNAPLYZE"),
    )
    if len(lines) < len(base) + 1:
        fail("QEMU identity row closure differs")
    for line, pair in zip(lines, base, strict=False):
        if line != f"{pair[0]}={pair[1]}":
            fail("QEMU identity base binding differs")
    model_line = lines[len(base)]
    if re.fullmatch(rf"target_model=ALI_{models[scenario]}_[A-F0-9]{{8}}", model_line) is None:
        fail("QEMU target model differs")
    cursor = len(base) + 1
    repository_rows = (
        ("repository_public_key_sha256", contract["publicKeySha256"]),
        ("repository_primary_fingerprint", contract["primaryFingerprint"]),
        ("repository_signing_fingerprint", contract["signingFingerprint"]),
        ("repository_package_set_sha256", contract["packageSetSha256"]),
        ("repository_manifest_sha256", contract["manifestSha256"]),
        ("repository_manifest_signature_sha256", contract["manifestSignatureSha256"]),
        ("repository_database_sha256", contract["databaseSha256"]),
        ("repository_database_signature_sha256", contract["databaseSignatureSha256"]),
        ("repository_files_sha256", contract["filesSha256"]),
        ("repository_files_signature_sha256", contract["filesSignatureSha256"]),
        ("release_sha256sums_sha256", expected["releaseSha256sumsSha256"]),
    )
    for key, value in repository_rows:
        if cursor >= len(lines) or lines[cursor] != f"{key}={value}":
            fail("QEMU identity repository binding differs")
        cursor += 1
    for item in contract["objects"]:
        row = f"repository_object_sha256={item['sha256']} name={item['name']} size={item['size']}"
        if cursor >= len(lines) or lines[cursor] != row:
            fail("QEMU identity repository-object binding differs")
        cursor += 1
    if scenario == SCENARIOS[2]:
        if cursor >= len(lines) or re.fullmatch(r"repository_server_port=[1-9][0-9]{3,4}", lines[cursor]) is None:
            fail("Marble repository runtime port binding differs")
        port = int(lines[cursor].split("=", 1)[1])
        if port > 65535:
            fail("Marble repository runtime port is out of range")
        cursor += 1
    if cursor != len(lines):
        fail("QEMU identity contains an unexpected row")
    if re.fullmatch(rf"ALI100{serial_letters[scenario]}[A-F0-9]{{12}}", str(result["targetSerial"])) is None:
        fail("QEMU target serial differs from its scenario")


def validate_runtime_markers(read: Callable[[str, int], bytes], result: dict[str, object],
                             scenario: str, run_id: str) -> dict[str, str]:
    harness_raw = read("harness.sha256", MAX_JSON)
    harness = sha256_rows(harness_raw, HARNESS_FILES, "QEMU harness manifest")
    source_root = Path(__file__).resolve().parent.parent
    for name in HARNESS_FILES:
        if harness[name] != sha256(source_root.joinpath(*PurePosixPath(name).parts)):
            fail("QEMU harness does not bind the current accepted source")
    expected_readback = "".join(f"{name}: OK\n" for name in HARNESS_FILES).encode("ascii")
    if read("evidence/preseal-harness-check.txt", MAX_JSON) != expected_readback:
        fail("QEMU pre-seal harness readback differs")
    if result.get("harnessSha256") != sha256_bytes(harness_raw):
        fail("QEMU harness digest binding differs")
    runtime_paths = (
        "/usr/bin/qemu-system-x86_64", "/usr/bin/qemu-img", "/usr/share/OVMF/OVMF_CODE_4M.fd",
        "/usr/share/OVMF/OVMF_VARS_4M.fd",
    )
    sha256_rows(read("runtime-inputs.sha256", MAX_JSON), runtime_paths, "QEMU runtime-input manifest")
    try:
        qemu_version = read("qemu-version.txt", 4096).decode("utf-8")
    except UnicodeDecodeError as error:
        fail(f"QEMU version record is invalid: {error}")
    if (re.match(r"\AQEMU emulator version [0-9]+(?:\.[0-9]+)+", qemu_version) is None or
            "synthetic" in qemu_version.lower()):
        fail("QEMU version record differs")
    initial, initial_path = single_sha256_row(
        read("OVMF_VARS.initial.sha256", 4096), "OVMF_VARS.fd", run_id, "initial OVMF VARS")
    final, final_path = single_sha256_row(
        read("OVMF_VARS.final.sha256", 4096), "OVMF_VARS.fd", run_id, "final OVMF VARS")
    if initial_path != final_path:
        fail("OVMF VARS path identity differs")
    payload, _ = single_sha256_row(
        read("payload.iso.sha256", 4096), "payload.iso", run_id, "payload ISO")
    try:
        image_check = read("evidence/final-qemu-img-check.txt", MAX_JSON).decode("utf-8")
        no_process = read("evidence/no-qemu-process.txt", 4096).decode("utf-8")
    except UnicodeDecodeError as error:
        fail(f"QEMU final marker is invalid: {error}")
    if ("No errors were found on the image." not in image_check or
            re.search(r"(?im)^(?:error|corrupt|leak)", image_check) is not None):
        fail("final qemu-img health marker differs")
    if no_process != f"no matching QEMU process remains for {run_id}\n":
        fail("final QEMU process-absence marker differs")
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(read("evidence/scenario.log.gz", MAX_TEXT))) as stream:
            log = stream.read(MAX_TEXT + 1).decode("utf-8")
    except (OSError, EOFError, UnicodeDecodeError) as error:
        fail(f"QEMU scenario log is invalid: {error}")
    markers = {SCENARIOS[0]: "MINIMAL", SCENARIOS[1]: "LUKSGRUB", SCENARIOS[2]: "MARBLE"}
    if (len(log.encode()) > MAX_TEXT or f"{markers[scenario]}_QEMU_INSTALLER_EXIT status=0" not in log or
            f"{markers[scenario]}_QEMU_INSTALL_COMPLETE" not in log or
            re.search(r"QEMU_HOST_FAIL|_QEMU_GUEST_FAIL|exit_status=[1-9]", log)):
        fail("QEMU compact scenario log lacks success or contains failure")
    if scenario == SCENARIOS[2]:
        expected_suffixes = (
            "/repository/repository.env", "/repository.contract", "/repository-ca.crt",
            "/repository-server.crt",
        )
        raw = read("repository-runtime.sha256", MAX_JSON)
        try:
            rows = raw.decode("utf-8").splitlines()
        except UnicodeDecodeError as error:
            fail(f"Marble repository runtime manifest is invalid: {error}")
        if len(rows) != len(expected_suffixes):
            fail("Marble repository runtime closure differs")
        for row, suffix in zip(rows, expected_suffixes, strict=True):
            match = re.fullmatch(r"([a-f0-9]{64})  (/.+)", row)
            if match is None or match.group(1) == "0" * 64 or not match.group(2).endswith(suffix):
                fail("Marble repository runtime binding differs")
    return {
        "ovmfInitialSha256": initial,
        "ovmfFinalSha256": final,
        "payloadIsoSha256": payload,
    }


def validate_run_process_chronology(identities: dict[str, dict[str, str]]) -> None:
    if int(identities["firstboot"]["start_time"]) >= int(identities["postreboot"]["start_time"]):
        fail("firstboot/postreboot QEMU process chronology differs")
    if len({identity["qga_identity"].split(":", 1)[0] for identity in identities.values()}) != 1:
        fail("firstboot/postreboot QEMU socket device differs")


def run_record(read: Callable[[str, int], bytes],
               geometry_of: Callable[[str], tuple[int, int]], names: set[str], scenario: str,
               commit: str, tree: str, version: str, expected: dict[str, str],
               contract: dict[str, object], bootstrap_sha256: str, stored_bytes: int) -> dict[str, object]:
    expected_names, result = expected_run_names(read, scenario)
    if names != expected_names | {"evidence"}:
        fail("QEMU retained evidence closure differs")
    result_raw = read("result.json", MAX_JSON)
    exact_keys(result, RESULT_KEYS, "QEMU result")
    identity = (commit, tree, scenario)
    if tuple(result.get(key) for key in ("sourceCommit", "sourceTree", "scenario")) != identity:
        fail("QEMU result source/scenario identity differs")
    run_id = result.get("runId")
    if not isinstance(run_id, str) or RUN_ID.fullmatch(run_id) is None or not run_id.startswith(PREFIXES[scenario] + "-"):
        fail("QEMU run ID differs")
    if (result.get("status") != "PASS" or
            type(result.get("exitStatus")) is not int or result.get("exitStatus") != 0 or
            result.get("failedPhase") is not None or
            result.get("inputMode") != "staged" or result.get("snapshotVerification") != "INDEPENDENT_PASS" or
            result.get("releaseVersion") != version):
        fail("QEMU staged-result state differs")
    sha_fields = (
        "buildMetadataSha256", "harnessSha256", "installerSha256", "isoSha256",
        "releaseSha256sumsSha256", "repositoryDatabaseSha256",
        "repositoryDatabaseSignatureSha256", "repositoryFilesSha256",
        "repositoryFilesSignatureSha256", "repositoryManifestSha256",
        "repositoryManifestSignatureSha256", "repositoryPackageSetSha256",
        "repositoryPublicKeySha256", "repositorySnapshotSha256", "unsignedManifestSha256",
    )
    if any(not isinstance(result.get(field), str) or HEX64.fullmatch(str(result[field])) is None or
           result[field] == "0" * 64 for field in sha_fields):
        fail("QEMU result SHA-256 field differs")
    repository_bindings = {
        "installerSha256": contract["installerSha256"],
        "isoSha256": contract["isoSha256"],
        "repositoryDatabaseSha256": contract["databaseSha256"],
        "repositoryDatabaseSignatureSha256": contract["databaseSignatureSha256"],
        "repositoryFilesSha256": contract["filesSha256"],
        "repositoryFilesSignatureSha256": contract["filesSignatureSha256"],
        "repositoryManifestSha256": contract["manifestSha256"],
        "repositoryManifestSignatureSha256": contract["manifestSignatureSha256"],
        "repositoryPackageSetSha256": contract["packageSetSha256"],
        "repositoryPublicKeySha256": contract["publicKeySha256"],
        "repositoryPrimaryFingerprint": contract["primaryFingerprint"],
        "repositorySigningFingerprint": contract["signingFingerprint"],
    }
    if any(result.get(field) != value for field, value in repository_bindings.items()):
        fail("QEMU result differs from the Phase-A repository contract")
    reported = result.get("retainedEvidenceBytes")
    try:
        size_record = int(read("evidence-size.txt", 64).decode("ascii").strip())
    except (UnicodeDecodeError, ValueError) as error:
        fail(f"QEMU evidence-size record differs: {error}")
    if type(reported) is not int or not 0 <= reported <= MAX_EVIDENCE or size_record != reported:
        fail("QEMU retained evidence counter differs")
    identities = {phase: parse_identity(read(f"evidence/{phase}-qemu.identity", 4096), phase)
                  for phase in PHASES}
    validate_run_process_chronology(identities)
    for name in result["screenshots"]:
        geometry_of(f"evidence/{name}")  # Optional diagnostics still obey safe strict-P6 structure.
    assertions = result.get("assertions")
    if not isinstance(assertions, list) or len(assertions) != len(EXPECTED_ASSERTIONS[scenario]):
        fail("QEMU assertion closure differs")
    assertion_rows: list[str] = []
    assertion_ids: list[str] = []
    for item in assertions:
        exact_keys(item, {"id", "status", "detail"}, "QEMU assertion")
        identifier = item.get("id")
        if (not isinstance(identifier, str) or re.fullmatch(r"[a-z0-9][a-z0-9.-]{0,127}", identifier) is None or
                identifier in assertion_ids or item.get("status") != "PASS" or
                not isinstance(item.get("detail"), str) or not item["detail"] or
                "\t" in item["detail"] or "\n" in item["detail"]):
            fail("QEMU assertion differs")
        assertion_ids.append(identifier)
        assertion_rows.append(f"{identifier}\tPASS\t{item['detail']}\n")
    if (tuple(assertion_ids) != EXPECTED_ASSERTIONS[scenario] or
            read("assertions.tsv", MAX_TEXT) != "".join(assertion_rows).encode("utf-8")):
        fail("QEMU exact scenario assertion sequence differs")
    validate_repository_objects(result, read, contract)
    validate_identity_record(read("identity.txt", MAX_TEXT), result, scenario, run_id, version,
                             expected, contract, bootstrap_sha256)
    marker_values = validate_runtime_markers(read, result, scenario, run_id)
    for field, value in expected.items():
        if result.get(field) != value:
            fail(f"QEMU result differs for {field}")
    return {"status": "PASS", "runId": run_id, "resultSha256": sha256_bytes(result_raw),
            "retainedEvidenceBytes": stored_bytes,
            "isoSha256": result["isoSha256"], "harnessSha256": result["harnessSha256"],
            "targetSerial": result["targetSerial"], "qemuIdentities": identities,
            **marker_values}


def directory_run(root: Path, scenario: str, commit: str, tree: str, version: str,
                  expected: dict[str, str], contract: dict[str, object],
                  bootstrap_sha256: str) -> dict[str, object]:
    if root.name != scenario or not root.is_dir() or root.is_symlink():
        fail("staged QEMU scenario directory differs")
    files: set[str] = set()
    directories: set[str] = set()
    stored = 0
    for current, dirnames, names in os.walk(root, topdown=True, followlinks=False):
        dirnames.sort()
        names.sort()
        relative_dir = Path(current).relative_to(root)
        for name in dirnames:
            path = Path(current) / name
            if path.is_symlink() or not path.is_dir():
                fail("QEMU scenario contains a linked or special directory")
            directories.add(PurePosixPath(*relative_dir.parts, name).as_posix())
        for name in names:
            path = Path(current) / name
            metadata = safe_file(path, MAX_FILE)
            files.add(PurePosixPath(*relative_dir.parts, name).as_posix())
            stored += metadata.st_size
    if directories != {"evidence"}:
        fail("QEMU scenario directory closure differs")
    def read(name: str, limit: int) -> bytes:
        path = root.joinpath(*PurePosixPath(name).parts)
        safe_file(path, limit)
        return path.read_bytes()
    def geometry_of(name: str) -> tuple[int, int]:
        return file_ppm_geometry(root.joinpath(*PurePosixPath(name).parts))
    return run_record(read, geometry_of, files | directories, scenario, commit, tree,
                      version, expected, contract, bootstrap_sha256, stored)


def archive_runs(contents: dict[str, bytes], geometries: dict[str, tuple[int, int]],
                 mapping: dict[str, dict[str, object]], commit: str, tree: str, version: str,
                 expected: dict[str, str], contract: dict[str, object],
                 bootstrap_sha256: str) -> dict[str, dict[str, object]]:
    expected_directories = {"evidence"}
    consumed_files: set[str] = set()
    qemu: dict[str, dict[str, object]] = {}
    for scenario in SCENARIOS:
        scenario_prefix = f"evidence/{scenario}"
        expected_directories.update({scenario_prefix, f"{scenario_prefix}/evidence"})
        prefix = scenario_prefix + "/"
        names = {name[len(prefix):] for name, item in mapping.items()
                 if name.startswith(prefix) and item["type"] == "file"}
        consumed_files.update(prefix + name for name in names)
        stored = sum(int(item["size"]) for name, item in mapping.items()
                     if name.startswith(prefix) and item["type"] == "file")
        def read(name: str, limit: int, *, _prefix: str = prefix) -> bytes:
            raw = contents.get(_prefix + name)
            if raw is None or len(raw) > limit:
                fail("required acceptance archive member is absent or oversized")
            return raw
        def geometry_of(name: str, *, _prefix: str = prefix) -> tuple[int, int]:
            value = geometries.get(_prefix + name)
            if value is None:
                fail("required acceptance PPM geometry is unavailable")
            return value
        qemu[scenario] = run_record(read, geometry_of, names | {"evidence"}, scenario,
                                    commit, tree, version, expected, contract,
                                    bootstrap_sha256, stored)
    directories = {name for name, item in mapping.items() if item["type"] == "directory"}
    if directories != expected_directories:
        fail("acceptance archive directory closure differs")
    if consumed_files != {name for name, item in mapping.items() if item["type"] == "file"}:
        fail("acceptance archive contains a file outside the scenario closure")
    validate_cross_scenario_records(list(qemu.values()))
    return qemu


def validate_cross_scenario_records(records: list[dict[str, object]]) -> None:
    if (len({str(item["runId"]) for item in records}) != len(SCENARIOS) or
            len({str(item["targetSerial"]) for item in records}) != len(SCENARIOS) or
            len({str(item["payloadIsoSha256"]) for item in records}) != len(SCENARIOS) or
            len({str(item["isoSha256"]) for item in records}) != 1 or
            len({str(item["harnessSha256"]) for item in records}) != 1):
        fail("cross-scenario QEMU input identity differs")
    process_identities: set[tuple[str, str]] = set()
    for record in records:
        identities = record["qemuIdentities"]
        for phase in PHASES:
            identity = identities[phase]
            pair = (identity["pid"], identity["start_time"])
            if pair in process_identities:
                fail("QEMU process identity repeats across accepted boots")
            process_identities.add(pair)


def create_archive(args: argparse.Namespace) -> None:
    root = Path(args.evidence_root)
    output = Path(args.output_tar)
    if (not root.is_absolute() or root.resolve(strict=True) != root or root.name != "evidence" or
            not output.is_absolute() or output.exists() or output.is_symlink()):
        fail("acceptance archive input or output path differs")
    parent = output.parent.resolve(strict=True)
    parent_metadata = parent.lstat()
    if (parent != output.parent or not stat.S_ISDIR(parent_metadata.st_mode) or
            parent_metadata.st_uid != os.getuid() or stat.S_IMODE(parent_metadata.st_mode) & 0o022):
        fail("acceptance archive output parent is unsafe")
    mapping, _ = tree_map(root)
    paths = [root, *root.rglob("*")]
    paths.sort(key=lambda path: PurePosixPath("evidence", *path.relative_to(root).parts).as_posix())
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        os.fchmod(descriptor, 0o644)
        with os.fdopen(descriptor, "wb", closefd=False) as stream:
            with tarfile.open(fileobj=stream, mode="w", format=tarfile.USTAR_FORMAT) as archive:
                for path in paths:
                    name = PurePosixPath("evidence", *path.relative_to(root).parts).as_posix()
                    record = mapping.get(name)
                    if record is None:
                        fail("acceptance archive source closure changed")
                    info = tarfile.TarInfo(name)
                    info.uid = 0
                    info.gid = 0
                    info.uname = ""
                    info.gname = ""
                    info.mtime = source_epoch()
                    if record["type"] == "directory":
                        if not path.is_dir() or path.is_symlink():
                            fail("acceptance archive source directory changed")
                        info.type = tarfile.DIRTYPE
                        info.mode = 0o755
                        info.size = 0
                        archive.addfile(info)
                    else:
                        metadata = safe_file(path, MAX_FILE)
                        if (stat.S_IMODE(metadata.st_mode) != 0o644 or metadata.st_size != record["size"] or
                                sha256(path) != record["sha256"]):
                            fail("acceptance archive source file changed before capture")
                        info.type = tarfile.REGTYPE
                        info.mode = 0o644
                        info.size = metadata.st_size
                        with path.open("rb") as source:
                            archive.addfile(info, source)
                        if sha256(path) != record["sha256"]:
                            fail("acceptance archive source file changed during capture")
            stream.flush()
            os.fsync(descriptor)
    except BaseException:
        try:
            output.unlink()
        except OSError:
            pass
        raise
    finally:
        os.close(descriptor)


def create(args: argparse.Namespace) -> None:
    version, commit, tree = args.release_version, args.source_commit, args.source_tree
    if VERSION.fullmatch(version) is None or HEX40.fullmatch(commit) is None or HEX40.fullmatch(tree) is None:
        fail("acceptance release or Git identity is malformed")
    for value in (args.source_tree_sha256, args.build_metadata_sha256,
                  args.unsigned_manifest_sha256, args.snapshot_sha256):
        if HEX64.fullmatch(value) is None:
            fail("acceptance SHA-256 identity is malformed")
    phase_root, evidence_root = Path(args.phase_a), Path(args.evidence_root)
    evidence_archive = Path(args.evidence_archive)
    assets = phase_a_map(phase_root, version)
    archive_name = f"arch-linux-repository-{version}.tar.zst"
    if assets["BUILD-METADATA.json"]["sha256"] != args.build_metadata_sha256:
        fail("Phase-A build metadata differs")
    if assets["UNSIGNED-SHA256SUMS"]["sha256"] != args.unsigned_manifest_sha256:
        fail("Phase-A unsigned manifest differs")
    if assets[archive_name]["sha256"] != args.snapshot_sha256:
        fail("Phase-A repository snapshot differs")
    manifest_sha = sha256(phase_root / "RELEASE-SHA256SUMS")
    expected = {"buildMetadataSha256": args.build_metadata_sha256,
                "unsignedManifestSha256": args.unsigned_manifest_sha256,
                "repositorySnapshotSha256": args.snapshot_sha256,
                "releaseSha256sumsSha256": manifest_sha}
    contract = snapshot_contract(phase_root, version, commit, tree,
                                 args.build_metadata_sha256, args.unsigned_manifest_sha256)
    bootstrap_sha256 = sha256(phase_root / "install.sh")
    if contract["installerSha256"] != sha256(phase_root / "arch-linux-installer.sh"):
        fail("Phase-A installer differs from the repository snapshot")
    staged_map, staged_total = tree_map(evidence_root)
    archive_map, contents, geometries, archive_total = archive_readback(evidence_archive)
    if staged_map != archive_map or staged_total != archive_total:
        fail("acceptance evidence archive differs from its staged tree")
    qemu = {scenario: directory_run(evidence_root / scenario, scenario, commit, tree, version,
                                     expected, contract, bootstrap_sha256)
            for scenario in SCENARIOS}
    if qemu != archive_runs(contents, geometries, archive_map, commit, tree, version, expected,
                            contract, bootstrap_sha256):
        fail("acceptance evidence archive verdict differs from staged evidence")
    value = {"schema": 1, "status": "PASS", "releaseVersion": version,
             "sourceCommit": commit, "sourceTree": tree, "sourceTreeSha256": args.source_tree_sha256,
             "buildMetadataSha256": args.build_metadata_sha256,
             "unsignedManifestSha256": args.unsigned_manifest_sha256,
             "repositorySnapshotSha256": args.snapshot_sha256,
             "phaseAManifestSha256": manifest_sha, "phaseAAggregateSha256": phase_a_aggregate(assets),
             "phaseAAssets": assets, "evidenceArchiveSha256": sha256(evidence_archive),
             "evidenceArchiveSizeBytes": safe_file(evidence_archive, MAX_EVIDENCE).st_size,
             "qemu": qemu, "deferred": []}
    output = Path(args.output)
    if output.exists() or output.is_symlink():
        fail("acceptance manifest output already exists")
    output.write_bytes((json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode())
    os.chmod(output, 0o644)


def verify(args: argparse.Namespace) -> None:
    root, manifest_path = Path(args.assets), Path(args.manifest)
    value = canonical_json(manifest_path, "release acceptance manifest")
    if (set(value) != MANIFEST_KEYS or type(value.get("schema")) is not int or
            value.get("schema") != 1 or value.get("status") != "PASS"):
        fail("acceptance manifest schema or status differs")
    version = value.get("releaseVersion")
    if not isinstance(version, str) or VERSION.fullmatch(version) is None:
        fail("acceptance release version differs")
    if (value.get("sourceCommit") != args.source_commit or value.get("sourceTree") != args.source_tree or
            value.get("sourceTreeSha256") != args.source_tree_sha256 or value.get("deferred") != []):
        fail("acceptance source or deferred identity differs")
    assets = phase_a_map(root, version)
    if value.get("phaseAAssets") != assets or value.get("phaseAAggregateSha256") != phase_a_aggregate(assets):
        fail("acceptance Phase-A byte map differs")
    if value.get("phaseAManifestSha256") != sha256(root / "RELEASE-SHA256SUMS"):
        fail("acceptance Phase-A manifest binding differs")
    evidence = root / f"arch-linux-acceptance-evidence-{version}.tar.zst"
    if (value.get("evidenceArchiveSha256") != sha256(evidence) or
            value.get("evidenceArchiveSizeBytes") != safe_file(evidence, MAX_EVIDENCE).st_size):
        fail("acceptance evidence archive binding differs")
    archive = f"arch-linux-repository-{version}.tar.zst"
    if (value.get("buildMetadataSha256") != assets["BUILD-METADATA.json"]["sha256"] or
            value.get("unsignedManifestSha256") != assets["UNSIGNED-SHA256SUMS"]["sha256"] or
            value.get("repositorySnapshotSha256") != assets[archive]["sha256"]):
        fail("acceptance source-build binding differs")
    contract = snapshot_contract(root, version, args.source_commit, args.source_tree,
                                 str(value["buildMetadataSha256"]), str(value["unsignedManifestSha256"]))
    bootstrap_sha256 = sha256(root / "install.sh")
    if contract["installerSha256"] != sha256(root / "arch-linux-installer.sh"):
        fail("finalized installer differs from its repository snapshot")
    archive_map, contents, geometries, _ = archive_readback(evidence)
    expected = {"buildMetadataSha256": str(value["buildMetadataSha256"]),
                "unsignedManifestSha256": str(value["unsignedManifestSha256"]),
                "repositorySnapshotSha256": str(value["repositorySnapshotSha256"]),
                "releaseSha256sumsSha256": str(value["phaseAManifestSha256"])}
    qemu = archive_runs(contents, geometries, archive_map, args.source_commit, args.source_tree,
                        version, expected, contract, bootstrap_sha256)
    if value.get("qemu") != qemu:
        fail("acceptance QEMU closure differs")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    commands = result.add_subparsers(dest="command", required=True)
    create_parser = commands.add_parser("create")
    for name in ("phase-a", "evidence-root", "evidence-archive", "release-version", "source-commit",
                 "source-tree", "source-tree-sha256", "build-metadata-sha256",
                 "unsigned-manifest-sha256", "snapshot-sha256", "output"):
        create_parser.add_argument(f"--{name}", required=True)
    verify_parser = commands.add_parser("verify")
    for name in ("assets", "manifest", "source-commit", "source-tree", "source-tree-sha256"):
        verify_parser.add_argument(f"--{name}", required=True)
    tree_parser = commands.add_parser("tree-identity")
    tree_parser.add_argument("--root", required=True)
    archive_parser = commands.add_parser("create-archive")
    archive_parser.add_argument("--evidence-root", required=True)
    archive_parser.add_argument("--output-tar", required=True)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        {"create": create, "verify": verify, "tree-identity": tree_identity,
         "create-archive": create_archive}[args.command](args)
    except (OSError, ManifestError, subprocess.SubprocessError) as error:
        print(f"ERROR: release acceptance manifest failed: {error}", file=os.sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
