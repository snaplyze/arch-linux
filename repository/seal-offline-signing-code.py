#!/usr/bin/python3 -I
"""Create a root-owned, immutable offline-signing code closure without private inputs."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import grp
import pwd
import re
import stat
import struct
import subprocess
import sys


SHA1 = re.compile(r"[a-f0-9]{40}\Z")
SHA256 = re.compile(r"[a-f0-9]{64}\Z")
SAFE_PATH = re.compile(r"[A-Za-z0-9.][A-Za-z0-9._+/-]{0,255}\Z")
FORBIDDEN_ENVIRONMENT = {
    "GNUPGHOME",
    "OFFLINE_SIGN_PASSPHRASE_FILE",
    "GPG_AGENT_INFO",
    "SSH_AUTH_SOCK",
}
GENERATED_LAUNCHER = "repository/offline-signing-launcher"
MANIFEST_NAME = ".offline-signing-code.json"
SIGNING_ACCOUNT = "arch-linux-signing"
MAX_CAPTURED_ENTRIES = 8_192
MAX_CAPTURED_FILES = 4_096
MAX_CAPTURED_DIRECTORIES = 4_096
MAX_CAPTURED_BYTES = 512 * 1024 * 1024
MAX_CAPTURED_DEPTH = 16


class SealError(ValueError):
    pass


def fail(message: str) -> None:
    raise SealError(message)


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


def assert_bootstrapped_entrypoint() -> None:
    """Reject execution from a mutable checkout or through an inherited authority."""

    entrypoint = Path(__file__)
    if not entrypoint.is_absolute() or entrypoint.resolve(strict=True) != entrypoint:
        fail("offline sealer entrypoint is not canonical")
    metadata = entrypoint.lstat()
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_gid != 0
        or stat.S_IMODE(metadata.st_mode) != 0o500
        or metadata.st_nlink != 1
        or os.listxattr(entrypoint, follow_symlinks=False)
    ):
        fail("offline sealer was not bootstrapped into a private root-owned file")
    parent = entrypoint.parent
    parent_metadata = parent.lstat()
    if (
        not stat.S_ISDIR(parent_metadata.st_mode)
        or parent_metadata.st_uid != 0
        or parent_metadata.st_gid != 0
        or stat.S_IMODE(parent_metadata.st_mode) != 0o700
        or os.listxattr(parent, follow_symlinks=False)
    ):
        fail("offline sealer bootstrap directory is unsafe")
    for descriptor_name in os.listdir("/proc/self/fd"):
        if not descriptor_name.isdecimal() or int(descriptor_name, 10) <= 2:
            continue
        try:
            os.fstat(int(descriptor_name, 10))
        except OSError:
            continue
        fail("offline sealer inherited an unexpected descriptor")
    expected_environment = {
        "HOME": "/root",
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": "/usr/bin:/usr/sbin",
    }
    if dict(os.environ) != expected_environment:
        fail("offline sealer environment is not exact and empty-derived")


def assert_dedicated_signing_account() -> tuple[int, int]:
    try:
        account = pwd.getpwnam(SIGNING_ACCOUNT)
        group = grp.getgrgid(account.pw_gid)
    except KeyError:
        fail("dedicated offline signing account is unavailable")
    passwd_records = pwd.getpwall()
    name_records = [record for record in passwd_records if record.pw_name == SIGNING_ACCOUNT]
    uid_records = [record for record in passwd_records if record.pw_uid == account.pw_uid]
    group_records = grp.getgrall()
    group_name_records = [record for record in group_records if record.gr_name == SIGNING_ACCOUNT]
    group_gid_records = [record for record in group_records if record.gr_gid == account.pw_gid]
    if (
        len(name_records) != 1
        or len(uid_records) != 1
        or name_records[0] != uid_records[0]
        or account.pw_passwd != "x"
        or len(group_name_records) != 1
        or len(group_gid_records) != 1
        or group_name_records[0] != group_gid_records[0]
        or group.gr_passwd != "x"
        or account.pw_uid <= 0
        or account.pw_gid <= 0
        or account.pw_dir != "/nonexistent"
        or account.pw_shell != "/usr/sbin/nologin"
        or group.gr_name != SIGNING_ACCOUNT
        or group.gr_mem
        or os.getgrouplist(SIGNING_ACCOUNT, account.pw_gid) != [account.pw_gid]
    ):
        fail("dedicated offline signing account policy differs")
    shadow_path = Path("/etc/shadow")
    before = shadow_path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_uid != 0 or before.st_nlink != 1:
        fail("dedicated offline signing account lock database is unsafe")
    shadow_data = shadow_path.read_text(encoding="utf-8")
    after = shadow_path.lstat()
    if source_identity(before) != source_identity(after):
        fail("dedicated offline signing account lock database changed")
    matches = [line.split(":", 2)[1] for line in shadow_data.splitlines() if line.startswith(f"{SIGNING_ACCOUNT}:")]
    if len(matches) != 1 or not matches[0].startswith(("!", "*")):
        fail("dedicated offline signing account is not password-locked")
    return account.pw_uid, account.pw_gid


def directory_authority_identity(metadata: os.stat_result) -> tuple[int, ...]:
    """Return fields that must not change when a child directory is created."""

    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_uid,
        metadata.st_gid,
        stat.S_IFMT(metadata.st_mode),
        stat.S_IMODE(metadata.st_mode),
    )


def assert_safe_parent(destination: Path) -> tuple[Path, tuple[int, ...]]:
    parent = destination.parent.resolve(strict=True)
    if parent != destination.parent:
        fail("sealed destination parent is not canonical")
    current = parent
    while True:
        metadata = current.lstat()
        if (
            not stat.S_ISDIR(metadata.st_mode)
            or metadata.st_uid != 0
            or metadata.st_gid != 0
            or stat.S_IMODE(metadata.st_mode) & 0o022
        ):
            fail("sealed destination has an unsafe ancestor")
        extended = set(os.listxattr(current, follow_symlinks=False))
        if extended & {"system.posix_acl_access", "system.posix_acl_default", "security.capability"}:
            fail("sealed destination ancestor has extended write or execution authority")
        if current.parent == current:
            break
        current = current.parent
    return parent, directory_authority_identity(parent.lstat())


def write_exclusive(path: Path, data: bytes, mode: int) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, mode)
    try:
        view = memoryview(data)
        while view:
            written = os.write(descriptor, view)
            if written <= 0:
                fail("sealed code write was incomplete")
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def source_identity(metadata: os.stat_result) -> tuple[int, ...]:
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


def git_object(kind: bytes, data: bytes) -> bytes:
    return hashlib.sha1(kind + b" " + str(len(data)).encode("ascii") + b"\0" + data).digest()


def source_tree_sha256(files: dict[str, dict[str, str]]) -> str:
    rows = [
        f"{'0755' if record['mode'] == '0555' else '0644'} {record['sha256']} *{name}\n"
        for name, record in files.items()
    ]
    return hashlib.sha256("".join(sorted(rows)).encode("utf-8")).hexdigest()


def read_source_file(source_directory: int, name: str) -> tuple[bytes, int]:
    before = os.stat(name, dir_fd=source_directory, follow_symlinks=False)
    if (
        not stat.S_ISREG(before.st_mode)
        or before.st_nlink != 1
        or stat.S_IMODE(before.st_mode) not in {0o644, 0o755}
        or before.st_size > 128 * 1024 * 1024
    ):
        fail("accepted source contains a file with unsafe metadata")
    descriptor = os.open(
        name,
        os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0),
        dir_fd=source_directory,
    )
    data = bytearray()
    try:
        opened = os.fstat(descriptor)
        if source_identity(opened) != source_identity(before):
            fail("accepted source file changed before capture")
        while True:
            chunk = os.read(descriptor, 131_072)
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > 128 * 1024 * 1024:
                fail("accepted source file exceeds its capture bound")
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    current = os.stat(name, dir_fd=source_directory, follow_symlinks=False)
    if (
        len(data) != before.st_size
        or source_identity(after) != source_identity(before)
        or source_identity(current) != source_identity(before)
    ):
        fail("accepted source file changed during capture")
    return bytes(data), 0o555 if stat.S_IMODE(before.st_mode) == 0o755 else 0o444


def capture_directory(
    source_directory: int,
    destination: Path,
    prefix: str,
    files: dict[str, dict[str, str]],
    budget: dict[str, int],
    depth: int,
    root_level: bool,
) -> bytes:
    if depth > MAX_CAPTURED_DEPTH:
        fail("accepted source exceeds its bounded directory depth")
    before = os.fstat(source_directory)
    if not stat.S_ISDIR(before.st_mode):
        fail("accepted source directory is unsafe")
    entries: list[tuple[bytes, bool, bytes, bytes]] = []
    names: list[str] = []
    seen_names: set[str] = set()
    with os.scandir(source_directory) as iterator:
        for entry in iterator:
            name = entry.name
            if root_level and name == ".git":
                continue
            if SAFE_PATH.fullmatch(name) is None or "/" in name or name in {".", "..", ".git"}:
                fail("accepted source contains an unsafe pathname")
            if name in seen_names:
                fail("accepted source directory contains ambiguous names")
            budget["entries"] += 1
            if budget["entries"] > MAX_CAPTURED_ENTRIES:
                fail("accepted source exceeds its bounded entry closure")
            seen_names.add(name)
            names.append(name)
    names.sort()
    for name in names:
        relative = f"{prefix}/{name}" if prefix else name
        if len(relative.encode("utf-8")) > 256:
            fail("accepted source contains an overlong relative pathname")
        metadata = os.stat(name, dir_fd=source_directory, follow_symlinks=False)
        encoded_name = name.encode("utf-8", errors="strict")
        if stat.S_ISDIR(metadata.st_mode):
            budget["directories"] += 1
            if budget["directories"] > MAX_CAPTURED_DIRECTORIES:
                fail("accepted source exceeds its bounded directory closure")
            child = os.open(
                name,
                os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=source_directory,
            )
            child_destination = destination / name
            child_destination.mkdir(mode=0o700)
            try:
                if source_identity(os.fstat(child)) != source_identity(metadata):
                    fail("accepted source directory changed before capture")
                child_hash = capture_directory(
                    child, child_destination, relative, files, budget, depth + 1, False
                )
            finally:
                os.close(child)
            current = os.stat(name, dir_fd=source_directory, follow_symlinks=False)
            if source_identity(current) != source_identity(metadata):
                fail("accepted source directory changed during capture")
            entries.append((encoded_name, True, b"40000", child_hash))
        elif stat.S_ISREG(metadata.st_mode):
            data, sealed_mode = read_source_file(source_directory, name)
            budget["files"] += 1
            budget["bytes"] += len(data)
            if budget["files"] > MAX_CAPTURED_FILES or budget["bytes"] > MAX_CAPTURED_BYTES:
                fail("accepted source exceeds its bounded file closure")
            write_exclusive(destination / name, data, 0o700)
            files[relative] = {
                "mode": f"{sealed_mode:04o}",
                "sha256": hashlib.sha256(data).hexdigest(),
            }
            git_mode = b"100755" if sealed_mode == 0o555 else b"100644"
            entries.append((encoded_name, False, git_mode, git_object(b"blob", data)))
        else:
            fail("accepted source contains a link or special object")
    after = os.fstat(source_directory)
    if source_identity(after) != source_identity(before):
        fail("accepted source directory changed during full capture")
    payload = bytearray()
    for name, is_directory, mode, object_id in sorted(
        entries,
        key=lambda item: item[0] + (b"/" if item[1] else b""),
    ):
        payload.extend(mode + b" " + name + b"\0" + object_id)
    return git_object(b"tree", bytes(payload))


def assert_static_pie(data: bytes) -> None:
    if len(data) < 64 or data[:6] != b"\x7fELF\x02\x01":
        fail("trusted offline launcher is not a 64-bit little-endian ELF")
    header = struct.unpack_from("<HHIQQQIHHHHHH", data, 16)
    object_type, machine = header[0], header[1]
    program_offset, program_entry_size, program_count = header[4], header[8], header[9]
    if object_type != 3 or machine != 62 or program_entry_size < 56 or program_count == 0:
        fail("trusted offline launcher is not an x86-64 position-independent executable")
    if program_offset + program_entry_size * program_count > len(data):
        fail("trusted offline launcher program headers are truncated")
    for index in range(program_count):
        program_type = struct.unpack_from("<I", data, program_offset + index * program_entry_size)[0]
        if program_type == 3:
            fail("trusted offline launcher unexpectedly has a dynamic interpreter")


def seal(
    source: Path,
    expected_commit: str,
    expected_tree: str,
    expected_tree_sha256: str,
    destination: Path,
) -> None:
    assert_bootstrapped_entrypoint()
    if os.getuid() != 0 or os.geteuid() != 0 or not initial_user_namespace():
        fail("sealing requires host root in the initial user namespace")
    if any(os.environ.get(name) for name in FORBIDDEN_ENVIRONMENT):
        fail("private signing state is forbidden during code sealing")
    if os.environ.get("CI", "false").lower() == "true" or os.environ.get("GITHUB_ACTIONS", "false").lower() == "true":
        fail("offline code sealing is forbidden in CI")
    if SHA1.fullmatch(expected_commit) is None or SHA1.fullmatch(expected_tree) is None:
        fail("accepted Git identity is malformed")
    if SHA256.fullmatch(expected_tree_sha256) is None:
        fail("accepted source-tree SHA-256 is malformed")
    signing_uid, signing_gid = assert_dedicated_signing_account()
    source = source.resolve(strict=True)
    if not source.is_dir() or source.is_symlink():
        fail("accepted source root is unsafe")
    if not destination.is_absolute() or destination.exists() or destination.is_symlink():
        fail("sealed destination must be a missing absolute path")
    destination_parent, destination_parent_identity = assert_safe_parent(destination)
    destination.mkdir(mode=0o700)
    created = True
    try:
        files: dict[str, dict[str, str]] = {}
        budget = {"bytes": 0, "directories": 1, "entries": 0, "files": 0}
        source_descriptor = os.open(
            source,
            os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0),
        )
        try:
            captured_tree = capture_directory(
                source_descriptor, destination, "", files, budget, 0, True
            ).hex()
        finally:
            os.close(source_descriptor)
        if captured_tree != expected_tree:
            fail("captured source bytes differ from the independently accepted Git tree")
        if source_tree_sha256(files) != expected_tree_sha256:
            fail("captured source bytes differ from the independently accepted SHA-256 tree")
        required = {
            "arch-linux-installer.sh",
            "install.sh",
            "maintenance/accepted-arch-iso.json",
            "repository/acceptance-manifest.py",
            "repository/lib/common.sh",
            "repository/offline-finalize-release.sh",
            "repository/offline-sign-release.sh",
            "repository/offline-signing-fd-guard.py",
            "repository/offline-signing-launcher.c",
            "repository/offline-signing-namespace.sh",
            "repository/package-set",
            "repository/run-offline-signing.sh",
            "repository/safe-extract-snapshot.py",
            "repository/snapshot-manifest.py",
            "repository/source-date-epoch",
            "repository/trust/arch-linux.gpg",
            "repository/trust/primary-fingerprint",
            "repository/trust/signing-subkey-fingerprint",
            "repository/verify-package-metadata.py",
            "repository/verify-release-assets.sh",
            "repository/verify-signed-repository.sh",
            "repository/verify-sealed-offline-code.py",
            "repository/verify-unsigned-build.sh",
        }
        if not required.issubset(files):
            fail("accepted tree omits required offline-signing code")

        launcher_source = destination / "repository/offline-signing-launcher.c"
        launcher = destination / GENERATED_LAUNCHER
        completed = subprocess.run(
            [
                "/usr/bin/cc",
                "-std=c17",
                "-O2",
                "-static-pie",
                "-fstack-protector-strong",
                "-D_FORTIFY_SOURCE=3",
                "-Wall",
                "-Wextra",
                "-Werror",
                f'-DALI_ACCEPTED_COMMIT_SHA="{expected_commit}"',
                f'-DALI_ACCEPTED_TREE_SHA="{expected_tree}"',
                f'-DALI_ACCEPTED_TREE_SHA256="{expected_tree_sha256}"',
                f"-DALI_SIGNING_UID={signing_uid}",
                f"-DALI_SIGNING_GID={signing_gid}",
                "-o",
                str(launcher),
                str(launcher_source),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            cwd="/",
            env={"HOME": "/root", "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/usr/sbin"},
        )
        if completed.returncode != 0:
            fail("trusted offline launcher compilation failed")
        launcher_data = launcher.read_bytes()
        assert_static_pie(launcher_data)
        files[GENERATED_LAUNCHER] = {"mode": "0555", "sha256": hashlib.sha256(launcher_data).hexdigest()}

        manifest = {
            "files": files,
            "schemaVersion": 1,
            "signingAccount": {
                "gid": signing_gid,
                "name": SIGNING_ACCOUNT,
                "uid": signing_uid,
            },
            "sourceCommitSha": expected_commit,
            "sourceTreeSha": expected_tree,
            "sourceTreeSha256": expected_tree_sha256,
        }
        manifest_data = (json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode()
        write_exclusive(destination / MANIFEST_NAME, manifest_data, 0o400)

        for directory, directories, filenames in os.walk(destination, topdown=False, followlinks=False):
            directory_path = Path(directory)
            for filename in filenames:
                path = directory_path / filename
                relative = str(path.relative_to(destination))
                mode = 0o444 if relative == MANIFEST_NAME else int(files[relative]["mode"], 8)
                os.chown(path, 0, 0, follow_symlinks=False)
                os.chmod(path, mode, follow_symlinks=False)
            for child in directories:
                path = directory_path / child
                os.chown(path, 0, 0, follow_symlinks=False)
                os.chmod(path, 0o555, follow_symlinks=False)
        os.chown(destination, 0, 0, follow_symlinks=False)
        os.chmod(destination, 0o555, follow_symlinks=False)
        if directory_authority_identity(destination_parent.lstat()) != destination_parent_identity:
            fail("sealed destination ancestor changed during creation")
        if destination.lstat().st_dev != destination_parent.lstat().st_dev or os.path.ismount(destination):
            fail("sealed destination was shadowed by another mount")
        for directory, directories, filenames in os.walk(destination, topdown=False, followlinks=False):
            directory_path = Path(directory)
            if os.listxattr(directory_path, follow_symlinks=False):
                fail("sealed code directory has an extended attribute")
            for filename in filenames:
                if os.listxattr(directory_path / filename, follow_symlinks=False):
                    fail("sealed code file has an extended attribute")
            for child in directories:
                if os.listxattr(directory_path / child, follow_symlinks=False):
                    fail("sealed code directory has an extended attribute")
        created = False
    finally:
        if created and destination.exists() and not destination.is_symlink():
            os.chmod(destination, 0o700)
            for directory, directories, filenames in os.walk(destination, topdown=False, followlinks=False):
                directory_path = Path(directory)
                os.chmod(directory_path, 0o700)
                for filename in filenames:
                    (directory_path / filename).unlink(missing_ok=True)
                for child in directories:
                    (directory_path / child).rmdir()
            destination.rmdir()


def main() -> int:
    if len(sys.argv) != 6:
        print("ERROR: offline code sealer usage error", file=sys.stderr)
        return 2
    try:
        seal(Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], Path(sys.argv[5]))
    except (OSError, SealError):
        print("ERROR: offline code sealing failed", file=sys.stderr)
        return 1
    print("Offline signing code closure: sealed and tree-bound")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
