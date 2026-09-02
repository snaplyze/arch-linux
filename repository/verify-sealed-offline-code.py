#!/usr/bin/python3 -I
"""Verify the root-owned immutable code closure used for offline signing."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys


SHA1 = re.compile(r"[a-f0-9]{40}\Z")
SHA256 = re.compile(r"[a-f0-9]{64}\Z")
SAFE_PATH = re.compile(r"[A-Za-z0-9.][A-Za-z0-9._+/-]{0,255}\Z")
MANIFEST_NAME = ".offline-signing-code.json"


class SealError(ValueError):
    pass


def fail(message: str) -> None:
    raise SealError(message)


def identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_uid,
        metadata.st_gid,
        stat.S_IFMT(metadata.st_mode),
        stat.S_IMODE(metadata.st_mode),
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def initial_user_namespace() -> bool:
    try:
        rows = Path("/proc/self/uid_map").read_text(encoding="ascii").splitlines()
    except OSError:
        return False
    parsed: list[tuple[int, int, int]] = []
    for row in rows:
        fields = row.split()
        if len(fields) != 3 or any(not field.isdecimal() for field in fields):
            return False
        parsed.append(tuple(int(field, 10) for field in fields))
    return parsed == [(0, 0, 4_294_967_295)]


def assert_ancestor_chain(root: Path) -> list[tuple[Path, tuple[int, ...]]]:
    chain: list[Path] = []
    current = root
    while True:
        chain.append(current)
        if current.parent == current:
            break
        current = current.parent
    result: list[tuple[Path, tuple[int, ...]]] = []
    for path in reversed(chain):
        metadata = path.lstat()
        if (
            not stat.S_ISDIR(metadata.st_mode)
            or metadata.st_uid != 0
            or metadata.st_gid != 0
            or stat.S_IMODE(metadata.st_mode) & 0o022
        ):
            fail("sealed code has an unsafe ancestor")
        extended = set(os.listxattr(path, follow_symlinks=False))
        if extended & {"system.posix_acl_access", "system.posix_acl_default", "security.capability"}:
            fail("sealed code ancestor has extended write or execution authority")
        result.append((path, identity(metadata)))
    return result


def mount_unescape(value: str) -> str:
    for encoded, decoded in (("\\040", " "), ("\\011", "\t"), ("\\012", "\n"), ("\\134", "\\")):
        value = value.replace(encoded, decoded)
    return value


def assert_no_mount_shadow(root: Path) -> None:
    prefix = f"{root}/"
    try:
        rows = Path("/proc/self/mountinfo").read_text(encoding="utf-8").splitlines()
    except OSError as error:
        fail(f"cannot inspect mount topology: {error.strerror}")
    for row in rows:
        fields = row.split()
        if len(fields) < 10:
            fail("mount topology is malformed")
        mountpoint = mount_unescape(fields[4])
        if mountpoint == str(root) or mountpoint.startswith(prefix):
            fail("sealed code contains a mount shadow")


def canonical_manifest(path: Path) -> tuple[dict[str, object], tuple[int, ...]]:
    before = path.lstat()
    if (
        not stat.S_ISREG(before.st_mode)
        or before.st_uid != 0
        or before.st_gid != 0
        or stat.S_IMODE(before.st_mode) != 0o444
        or before.st_nlink != 1
        or not 0 < before.st_size <= 4 * 1024 * 1024
    ):
        fail("sealed code manifest metadata is invalid")
    if os.listxattr(path, follow_symlinks=False):
        fail("sealed code manifest has an extended attribute")
    flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        opened = os.fstat(descriptor)
        if identity(opened) != identity(before):
            fail("sealed code manifest changed before reading")
        data = bytearray()
        while len(data) <= 4 * 1024 * 1024:
            chunk = os.read(descriptor, 131_072)
            if not chunk:
                break
            data.extend(chunk)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if len(data) != before.st_size or identity(after) != identity(before) or identity(path.lstat()) != identity(before):
        fail("sealed code manifest changed while reading")
    try:
        value = json.loads(bytes(data))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"sealed code manifest is invalid JSON: {error}")
    if not isinstance(value, dict):
        fail("sealed code manifest is not one object")
    canonical = (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode()
    if bytes(data) != canonical:
        fail("sealed code manifest is not canonical JSON")
    return value, identity(before)


def read_stable_file(
    path: Path, expected_mode: int, expected_sha: str, capture: bool = False
) -> tuple[tuple[int, ...], bytes]:
    before = path.lstat()
    if (
        not stat.S_ISREG(before.st_mode)
        or before.st_uid != 0
        or before.st_gid != 0
        or stat.S_IMODE(before.st_mode) != expected_mode
        or before.st_nlink != 1
        or before.st_size > 128 * 1024 * 1024
    ):
        fail("sealed code file metadata is invalid")
    if os.listxattr(path, follow_symlinks=False):
        fail("sealed code file has an extended attribute")
    flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    digest = hashlib.sha256()
    captured = bytearray()
    total = 0
    try:
        opened = os.fstat(descriptor)
        if identity(opened) != identity(before):
            fail("sealed code file changed before reading")
        while True:
            chunk = os.read(descriptor, 131_072)
            if not chunk:
                break
            total += len(chunk)
            if total > 128 * 1024 * 1024:
                fail("sealed code file exceeds its bound")
            digest.update(chunk)
            if capture:
                captured.extend(chunk)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if (
        total != before.st_size
        or digest.hexdigest() != expected_sha
        or identity(after) != identity(before)
        or identity(path.lstat()) != identity(before)
    ):
        fail("sealed code file bytes or identity changed")
    return identity(before), bytes(captured)


def assert_static_launcher(data: bytes) -> None:
    if len(data) < 64 or data[:6] != b"\x7fELF\x02\x01":
        fail("sealed offline launcher is not a 64-bit little-endian ELF")
    header = struct.unpack_from("<HHIQQQIHHHHHH", data, 16)
    object_type, machine = header[0], header[1]
    program_offset, program_entry_size, program_count = header[4], header[8], header[9]
    if object_type != 3 or machine != 62 or program_entry_size < 56 or program_count == 0:
        fail("sealed offline launcher is not an x86-64 position-independent executable")
    if program_offset + program_entry_size * program_count > len(data):
        fail("sealed offline launcher headers are truncated")
    for index in range(program_count):
        if struct.unpack_from("<I", data, program_offset + index * program_entry_size)[0] == 3:
            fail("sealed offline launcher has a dynamic interpreter")


def verify(
    root_argument: str,
    expected_commit: str,
    expected_tree: str,
    expected_tree_sha256: str,
) -> None:
    if os.getuid() == 0 or os.geteuid() == 0:
        fail("offline signer must be host-nonroot")
    if not initial_user_namespace():
        fail("offline signer must start in the initial user namespace")
    if SHA1.fullmatch(expected_commit) is None or SHA1.fullmatch(expected_tree) is None:
        fail("accepted Git identity is malformed")
    if SHA256.fullmatch(expected_tree_sha256) is None:
        fail("accepted source-tree SHA-256 is malformed")
    root = Path(root_argument)
    if not root.is_absolute() or root.resolve(strict=True) != root:
        fail("sealed code root is not an exact canonical path")
    ancestor_state = assert_ancestor_chain(root)
    assert_no_mount_shadow(root)
    manifest, manifest_identity = canonical_manifest(root / MANIFEST_NAME)
    if set(manifest) != {
        "files", "schemaVersion", "signingAccount", "sourceCommitSha", "sourceTreeSha",
        "sourceTreeSha256"
    }:
        fail("sealed code manifest schema is invalid")
    if (
        manifest["schemaVersion"] != 1
        or manifest["sourceCommitSha"] != expected_commit
        or manifest["sourceTreeSha"] != expected_tree
        or manifest["sourceTreeSha256"] != expected_tree_sha256
    ):
        fail("sealed code manifest is not bound to the independently accepted tree")
    account = manifest["signingAccount"]
    if (
        not isinstance(account, dict)
        or set(account) != {"gid", "name", "uid"}
        or account["name"] != "arch-linux-signing"
        or account["uid"] != os.getuid()
        or account["gid"] != os.getgid()
        or os.getgroups()
    ):
        fail("sealed code is not running as the exact dedicated signing account")
    files = manifest["files"]
    if not isinstance(files, dict) or not files:
        fail("sealed code manifest has no exact file closure")

    expected_names = {MANIFEST_NAME}
    expected_directories = {"."}
    file_state: list[tuple[Path, tuple[int, ...]]] = []
    source_digest_rows: list[str] = []
    launcher_data = b""
    for name in sorted(files):
        if not isinstance(name, str) or SAFE_PATH.fullmatch(name) is None:
            fail("sealed code manifest contains an unsafe path")
        pure = Path(name)
        if pure.is_absolute() or ".." in pure.parts or "." in pure.parts:
            fail("sealed code manifest path escapes its root")
        record = files[name]
        if not isinstance(record, dict) or set(record) != {"mode", "sha256"}:
            fail("sealed code file record schema is invalid")
        mode = record["mode"]
        digest = record["sha256"]
        if mode not in {"0444", "0555"} or not isinstance(digest, str) or SHA256.fullmatch(digest) is None:
            fail("sealed code file record is invalid")
        expected_names.add(name)
        for parent in pure.parents:
            if str(parent) == ".":
                break
            expected_directories.add(str(parent))
        if name != "repository/offline-signing-launcher":
            source_mode = "0755" if mode == "0555" else "0644"
            source_digest_rows.append(f"{source_mode} {digest} *{name}\n")
        metadata_identity, captured = read_stable_file(
            root / pure,
            int(mode, 8),
            digest,
            name == "repository/offline-signing-launcher",
        )
        file_state.append((root / pure, metadata_identity))
        if captured:
            launcher_data = captured
    actual_source_tree_sha256 = hashlib.sha256(
        "".join(sorted(source_digest_rows)).encode("utf-8")
    ).hexdigest()
    if actual_source_tree_sha256 != expected_tree_sha256:
        fail("sealed source file closure differs from the independently accepted SHA-256 tree")

    actual_names: set[str] = set()
    actual_directories: set[str] = set()
    directory_state: list[tuple[Path, tuple[int, ...]]] = []
    for directory, directories, filenames in os.walk(root, topdown=True, followlinks=False):
        directory_path = Path(directory)
        relative_directory = str(directory_path.relative_to(root))
        actual_directories.add(relative_directory or ".")
        metadata = directory_path.lstat()
        if (
            not stat.S_ISDIR(metadata.st_mode)
            or metadata.st_uid != 0
            or metadata.st_gid != 0
            or stat.S_IMODE(metadata.st_mode) != 0o555
        ):
            fail("sealed code directory metadata is invalid")
        if os.listxattr(directory_path, follow_symlinks=False):
            fail("sealed code directory has an extended attribute")
        directory_state.append((directory_path, identity(metadata)))
        for child in directories:
            child_path = directory_path / child
            if child_path.is_symlink():
                fail("sealed code contains a linked directory")
        for filename in filenames:
            relative = str((directory_path / filename).relative_to(root))
            actual_names.add(relative)
    if actual_names != expected_names:
        fail("sealed code filesystem differs from its exact manifest closure")
    if actual_directories != expected_directories:
        fail("sealed code directory closure differs from its exact file closure")
    if not launcher_data:
        fail("sealed offline launcher is absent from the exact closure")
    assert_static_launcher(launcher_data)

    if identity((root / MANIFEST_NAME).lstat()) != manifest_identity:
        fail("sealed code manifest changed during verification")
    for path, wanted in file_state + directory_state + ancestor_state:
        if identity(path.lstat()) != wanted:
            fail("sealed code identity changed during full verification")
    assert_no_mount_shadow(root)


def main() -> int:
    if len(sys.argv) != 5:
        print("ERROR: sealed offline code verifier usage error", file=sys.stderr)
        return 2
    try:
        verify(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    except (OSError, SealError):
        print("ERROR: sealed offline code verification failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
