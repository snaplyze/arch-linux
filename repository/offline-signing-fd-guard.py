#!/usr/bin/python3 -I
"""Close or reject inherited descriptors before offline signing.

Only stdio, the retained home and passphrase objects, and the exact directory lock may cross.
Error messages deliberately omit descriptor targets because they may contain private paths.
"""

from __future__ import annotations

import os
import fcntl
import errno
from pathlib import Path
import re
import stat
import sys


ALLOWED_ENVIRONMENT = (
    "ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT",
    "ARCH_LINUX_OFFLINE_ACCEPTED_TREE",
    "ARCH_LINUX_OFFLINE_ACCEPTED_TREE_SHA256",
    "ARCH_LINUX_OFFLINE_BROKER_PARENT",
    "ARCH_LINUX_OFFLINE_BROKER_PARENT_START",
    "ARCH_LINUX_OFFLINE_CODE_ROOT",
    "ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY",
    "ARCH_LINUX_OFFLINE_LAUNCHER",
    "ARCH_LINUX_OFFLINE_LAUNCHER_IDENTITY",
    "ARCH_LINUX_CALLER_MNTNS_INODE",
    "ARCH_LINUX_CALLER_NETNS_INODE",
    "ARCH_LINUX_CALLER_PIDNS_INODE",
    "ARCH_LINUX_CALLER_USERNS_INODE",
    "ARCH_LINUX_SIGNING_HOME_IDENTITY",
    "ARCH_LINUX_SIGNING_HOST_GID",
    "ARCH_LINUX_SIGNING_HOST_UID",
    "ARCH_LINUX_PASSPHRASE_IDENTITY",
    "HOME",
    "LANG",
    "LC_ALL",
    "PATH",
    "TMPDIR",
)
HOME_DESCRIPTOR = 6
PASSPHRASE_DESCRIPTOR = 7
LOCK_DESCRIPTOR = 9
PASSPHRASE_MAX = 4096
PASSPHRASE_SEALS = (
    fcntl.F_SEAL_WRITE | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_SEAL
)
FINGERPRINT = re.compile(r"[A-F0-9]{40}\Z")
SIGNING_SELECTOR = re.compile(r"[A-F0-9]{40}!\Z")
PRIVATE_RUNTIME_ROOT = Path("/run/user/0/arch-linux-offline")
RENAME_NOREPLACE = 1


class GuardError(ValueError):
    pass


def fail(message: str) -> None:
    raise GuardError(message)


def descriptor_numbers() -> set[int]:
    result: set[int] = set()
    for name in os.listdir("/proc/self/fd"):
        if name.isdigit():
            descriptor = int(name)
            try:
                os.fstat(descriptor)
            except OSError:
                continue
            result.add(descriptor)
    return result


def descriptor_metadata(descriptor: int) -> os.stat_result:
    try:
        return os.fstat(descriptor)
    except OSError as error:
        fail(f"required descriptor {descriptor} is unavailable: {error.strerror}")


def assert_stdio_is_not_socket() -> None:
    for descriptor in (0, 1, 2):
        metadata = descriptor_metadata(descriptor)
        if stat.S_ISSOCK(metadata.st_mode):
            fail("a standard stream is a socket")


def object_identity(metadata: os.stat_result) -> str:
    return f"{metadata.st_dev}:{metadata.st_ino}"


def assert_home_descriptor() -> os.stat_result:
    home = descriptor_metadata(HOME_DESCRIPTOR)
    if (
        not stat.S_ISDIR(home.st_mode)
        or stat.S_IMODE(home.st_mode) != 0o700
        or home.st_uid != os.getuid()
        or home.st_gid != os.getgid()
    ):
        fail("the signing-home descriptor metadata is invalid")
    expected = os.environ.get("ARCH_LINUX_SIGNING_HOME_IDENTITY", "")
    if expected != object_identity(home):
        fail("the signing-home descriptor identity differs")
    return home


def assert_passphrase_descriptor() -> None:
    passphrase_metadata = descriptor_metadata(PASSPHRASE_DESCRIPTOR)
    actual_passphrase = (
        f"{passphrase_metadata.st_dev}:{passphrase_metadata.st_ino}:{passphrase_metadata.st_size}"
    )
    if (
        not stat.S_ISREG(passphrase_metadata.st_mode)
        or stat.S_IMODE(passphrase_metadata.st_mode) != 0o600
        or passphrase_metadata.st_uid != os.getuid()
        or passphrase_metadata.st_gid != os.getgid()
        or passphrase_metadata.st_nlink != 0
        or not 0 < passphrase_metadata.st_size <= PASSPHRASE_MAX
        or os.environ.get("ARCH_LINUX_PASSPHRASE_IDENTITY", "") != actual_passphrase
        or fcntl.fcntl(PASSPHRASE_DESCRIPTOR, fcntl.F_GET_SEALS) != PASSPHRASE_SEALS
    ):
        fail("the sealed passphrase descriptor metadata is invalid")


def assert_lock_descriptor(home: os.stat_result | None = None) -> None:
    lock = descriptor_metadata(LOCK_DESCRIPTOR)
    expected = os.environ.get("ARCH_LINUX_SIGNING_HOME_IDENTITY", "")
    if (
        not stat.S_ISDIR(lock.st_mode)
        or stat.S_IMODE(lock.st_mode) != 0o700
        or lock.st_uid != os.getuid()
        or lock.st_gid != os.getgid()
        or object_identity(lock) != expected
        or (home is not None and object_identity(lock) != object_identity(home))
    ):
        fail("the signing-home lock descriptor identity differs")


def assert_private_descriptors(mode: str) -> None:
    if mode in {"assert-bootstrap", "assert-sealed", "assert-runtime", "exec-clean"}:
        home = assert_home_descriptor()
        assert_passphrase_descriptor()
        if mode != "assert-bootstrap":
            assert_lock_descriptor(home)
        return
    if mode == "assert-supervisor":
        assert_passphrase_descriptor()
        assert_lock_descriptor()
        return
    if mode in {"assert-signer", "exec-signing-gpg", "exec-private-gpg"}:
        assert_passphrase_descriptor()
        return
    if mode in {"assert-public", "exec-public", "atomic-publish"}:
        return
    fail("unknown descriptor-guard mode")


def allowed_descriptors(mode: str) -> set[int]:
    if mode == "assert-bootstrap":
        return {0, 1, 2, HOME_DESCRIPTOR, PASSPHRASE_DESCRIPTOR}
    if mode in {"assert-sealed", "assert-runtime", "exec-clean"}:
        return {0, 1, 2, HOME_DESCRIPTOR, PASSPHRASE_DESCRIPTOR, LOCK_DESCRIPTOR}
    if mode == "assert-supervisor":
        return {0, 1, 2, PASSPHRASE_DESCRIPTOR, LOCK_DESCRIPTOR}
    if mode in {"assert-signer", "exec-signing-gpg", "exec-private-gpg"}:
        return {0, 1, 2, PASSPHRASE_DESCRIPTOR}
    if mode in {"assert-public", "exec-public", "atomic-publish"}:
        return {0, 1, 2}
    fail("unknown descriptor-guard mode")


def close_unexpected(mode: str) -> None:
    for descriptor in sorted(descriptor_numbers() - allowed_descriptors(mode), reverse=True):
        try:
            os.close(descriptor)
        except OSError:
            pass
    if descriptor_numbers() - allowed_descriptors(mode):
        fail("an inherited descriptor survived closure")


def clean_environment() -> dict[str, str]:
    environment = {
        name: os.environ[name]
        for name in ALLOWED_ENVIRONMENT
        if name in os.environ
    }
    required = {
        "ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT",
        "ARCH_LINUX_OFFLINE_ACCEPTED_TREE",
        "ARCH_LINUX_OFFLINE_ACCEPTED_TREE_SHA256",
        "ARCH_LINUX_OFFLINE_BROKER_PARENT",
        "ARCH_LINUX_OFFLINE_BROKER_PARENT_START",
        "ARCH_LINUX_OFFLINE_CODE_ROOT",
        "ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY",
        "ARCH_LINUX_OFFLINE_LAUNCHER",
        "ARCH_LINUX_OFFLINE_LAUNCHER_IDENTITY",
        "ARCH_LINUX_SIGNING_HOME_IDENTITY",
        "ARCH_LINUX_SIGNING_HOST_GID",
        "ARCH_LINUX_SIGNING_HOST_UID",
        "ARCH_LINUX_PASSPHRASE_IDENTITY",
        "HOME",
        "LANG",
        "LC_ALL",
        "PATH",
        "TMPDIR",
    }
    if not required.issubset(environment):
        fail("the signing environment is incomplete")
    if environment["PATH"] != "/usr/bin:/bin":
        fail("the signing command path is not trusted")
    if environment["LC_ALL"] != "C" or environment["LANG"] != "C":
        fail("the signing locale is not deterministic")
    for name in ("ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT", "ARCH_LINUX_OFFLINE_ACCEPTED_TREE"):
        if len(environment[name]) != 40 or any(
            character not in "0123456789abcdef" for character in environment[name]
        ):
            fail("the accepted offline Git identity is malformed")
    if len(environment["ARCH_LINUX_OFFLINE_ACCEPTED_TREE_SHA256"]) != 64 or any(
        character not in "0123456789abcdef"
        for character in environment["ARCH_LINUX_OFFLINE_ACCEPTED_TREE_SHA256"]
    ):
        fail("the accepted offline source-tree SHA-256 is malformed")
    for name in ("ARCH_LINUX_SIGNING_HOST_UID", "ARCH_LINUX_SIGNING_HOST_GID"):
        if not environment[name].isdecimal() or int(environment[name]) == 0:
            fail("the dedicated signing host identity is malformed")
    identity = environment["ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY"]
    if len(identity.split(":")) != 2 or any(
        not component.isdecimal() for component in identity.split(":")
    ):
        fail("the sealed offline source identity is malformed")
    if not environment["ARCH_LINUX_OFFLINE_BROKER_PARENT_START"].isdecimal():
        fail("the launcher start identity is malformed")
    launcher_identity = environment["ARCH_LINUX_OFFLINE_LAUNCHER_IDENTITY"]
    if len(launcher_identity.split(":")) != 7 or any(
        not component.isdecimal() for component in launcher_identity.split(":")
    ):
        fail("the launcher object identity is malformed")
    return environment


def public_environment() -> dict[str, str]:
    return {
        "HOME": "/nonexistent",
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": "/usr/bin:/bin",
        "TMPDIR": "/tmp",
    }


def signing_environment() -> dict[str, str]:
    if os.environ.get("GNUPGHOME") != str(PRIVATE_RUNTIME_ROOT / "gnupg"):
        fail("the fixed signing home differs")
    return {
        "GNUPGHOME": str(PRIVATE_RUNTIME_ROOT / "gnupg"),
        "HOME": "/nonexistent",
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": "/usr/bin:/bin",
        "TMPDIR": "/tmp",
    }


def paths_overlap(left: Path, right: Path) -> bool:
    return left == right or left in right.parents or right in left.parents


def assert_signing_gpg(arguments: list[str]) -> None:
    if len(arguments) != 15:
        fail("the signing GPG command shape differs")
    expected = [
        "/usr/bin/gpg",
        "--batch",
        "--no-options",
        "--no-autostart",
        "--no-tty",
        "--pinentry-mode",
        "loopback",
        "--passphrase-file",
        "/proc/self/fd/7",
        "--local-user",
    ]
    if arguments[:10] != expected or SIGNING_SELECTOR.fullmatch(arguments[10]) is None:
        fail("the signing GPG command prefix differs")
    if arguments[11] != "--detach-sign" or arguments[12] != "--output" or arguments[14] != "--":
        fail("the signing GPG command operation differs")
    # The payload follows the explicit option terminator and makes the exact argv 16 entries.


def assert_signing_gpg_argv(arguments: list[str]) -> None:
    if len(arguments) != 16:
        fail("the signing GPG command shape differs")
    assert_signing_gpg(arguments[:15])
    signature = Path(arguments[13])
    payload = Path(arguments[15])
    if not signature.is_absolute() or not payload.is_absolute():
        fail("the signing GPG paths are not absolute")
    payload = payload.resolve(strict=True)
    signature_parent = signature.parent.resolve(strict=True)
    if signature.parent != signature_parent or signature.name in {"", ".", ".."}:
        fail("the signing output parent is not canonical")
    signature = signature_parent / signature.name
    if signature.exists() or signature.is_symlink():
        fail("the signing output already exists")
    payload_metadata = payload.lstat()
    parent_metadata = signature_parent.lstat()
    if (
        not stat.S_ISREG(payload_metadata.st_mode)
        or payload_metadata.st_nlink != 1
        or not stat.S_ISDIR(parent_metadata.st_mode)
        or paths_overlap(payload, PRIVATE_RUNTIME_ROOT)
        or paths_overlap(signature, PRIVATE_RUNTIME_ROOT)
    ):
        fail("the signing GPG object boundary differs")
    arguments[13] = str(signature)
    arguments[15] = str(payload)


def assert_private_gpg_argv(arguments: list[str]) -> None:
    secret_prefix = [
        "/usr/bin/gpg",
        "--batch",
        "--no-options",
        "--no-autostart",
        "--with-colons",
        "--with-subkey-fingerprint",
        "--list-secret-keys",
        "--",
    ]
    public_prefix = [
        "/usr/bin/gpg",
        "--batch",
        "--no-options",
        "--no-autostart",
        "--list-keys",
        "--",
    ]
    if (
        len(arguments) == len(secret_prefix) + 1
        and arguments[:-1] == secret_prefix
        and SIGNING_SELECTOR.fullmatch(arguments[-1]) is not None
    ):
        return
    if (
        len(arguments) == len(public_prefix) + 1
        and arguments[:-1] == public_prefix
        and FINGERPRINT.fullmatch(arguments[-1]) is not None
    ):
        return
    fail("the private GPG inspection command shape differs")


def authority_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_uid,
        metadata.st_gid,
        stat.S_IFMT(metadata.st_mode),
        stat.S_IMODE(metadata.st_mode),
    )


def assert_private_directory(path: Path, label: str) -> tuple[int, ...]:
    metadata = path.lstat()
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or metadata.st_gid != os.getgid()
        or stat.S_IMODE(metadata.st_mode) != 0o700
        or os.listxattr(path, follow_symlinks=False)
    ):
        fail(f"the {label} directory authority differs")
    return authority_identity(metadata)


def atomic_publish(source_argument: str, output_argument: str) -> None:
    import ctypes

    if dict(os.environ) != public_environment():
        fail("the atomic publication environment is not exact")
    source = Path(source_argument)
    output = Path(output_argument)
    if not source.is_absolute() or not output.is_absolute():
        fail("atomic publication paths must be absolute")
    if source.name in {"", ".", ".."} or output.name in {"", ".", ".."}:
        fail("atomic publication basename is invalid")
    source_parent = source.parent.resolve(strict=True)
    output_parent = output.parent.resolve(strict=True)
    if source.parent != source_parent or output.parent != output_parent:
        fail("atomic publication parent is not canonical")
    canonical_source = source.resolve(strict=True)
    if canonical_source != source or paths_overlap(source, PRIVATE_RUNTIME_ROOT):
        fail("atomic publication source is not canonical")
    output = output_parent / output.name
    if output.exists() or output.is_symlink() or paths_overlap(output, PRIVATE_RUNTIME_ROOT):
        fail("atomic publication output is not missing")

    source_identity = assert_private_directory(source, "staged output")
    source_parent_identity = assert_private_directory(source_parent, "staged-output parent")
    output_parent_identity = assert_private_directory(output_parent, "output parent")
    open_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    source_parent_fd = os.open(source_parent, open_flags)
    output_parent_fd = os.open(output_parent, open_flags)
    source_fd = os.open(source, open_flags)
    try:
        if (
            authority_identity(os.fstat(source_parent_fd)) != source_parent_identity
            or authority_identity(os.fstat(output_parent_fd)) != output_parent_identity
            or authority_identity(os.fstat(source_fd)) != source_identity
        ):
            fail("atomic publication authority changed before rename")
        try:
            os.stat(output.name, dir_fd=output_parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            fail("atomic publication output appeared before rename")

        libc = ctypes.CDLL(None, use_errno=True)
        renameat2 = getattr(libc, "renameat2", None)
        if renameat2 is None:
            fail("atomic no-replace rename is unavailable")
        renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        renameat2.restype = ctypes.c_int
        result = renameat2(
            source_parent_fd,
            os.fsencode(source.name),
            output_parent_fd,
            os.fsencode(output.name),
            RENAME_NOREPLACE,
        )
        if result != 0:
            failure = ctypes.get_errno()
            if failure in {errno.EEXIST, errno.ENOTEMPTY}:
                fail("atomic publication refused an existing output")
            fail("atomic no-replace rename failed")
        try:
            os.stat(source.name, dir_fd=source_parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            fail("atomic publication source remains after rename")
        published = os.stat(output.name, dir_fd=output_parent_fd, follow_symlinks=False)
        if authority_identity(published) != source_identity:
            fail("atomic publication output identity differs")
        os.fsync(source_fd)
        os.fsync(source_parent_fd)
        if output_parent_fd != source_parent_fd:
            os.fsync(output_parent_fd)
    finally:
        os.close(source_fd)
        os.close(output_parent_fd)
        os.close(source_parent_fd)


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in {
        "assert-bootstrap", "assert-sealed", "assert-runtime", "assert-supervisor",
        "assert-signer", "assert-public", "exec-clean", "exec-public", "exec-signing-gpg",
        "exec-private-gpg", "atomic-publish"
    }:
        print("ERROR: offline signing descriptor guard usage error", file=sys.stderr)
        return 2
    try:
        assert_stdio_is_not_socket()
        mode = sys.argv[1]
        assert_private_descriptors(mode)
        if mode == "atomic-publish":
            if len(sys.argv) != 4:
                fail("atomic publication command shape differs")
            close_unexpected(mode)
            atomic_publish(sys.argv[2], sys.argv[3])
            return 0
        if mode in {
            "assert-bootstrap", "assert-sealed", "assert-runtime", "assert-supervisor",
            "assert-signer", "assert-public"
        }:
            if len(sys.argv) != 2:
                fail("assert-clean received an unexpected command")
            if descriptor_numbers() != allowed_descriptors(mode):
                fail("an unexpected inherited descriptor is open")
            return 0
        if len(sys.argv) < 3:
            fail("descriptor-guard exec mode requires a command")
        close_unexpected(mode)
        command = sys.argv[2]
        if not command.startswith("/"):
            fail("descriptor-guard exec mode requires an absolute command")
        if mode == "exec-clean":
            for descriptor in (HOME_DESCRIPTOR, PASSPHRASE_DESCRIPTOR, LOCK_DESCRIPTOR):
                os.set_inheritable(descriptor, True)
            environment = clean_environment()
        elif mode == "exec-public":
            environment = public_environment()
        elif mode == "exec-private-gpg":
            assert_private_gpg_argv(sys.argv[2:])
            os.close(PASSPHRASE_DESCRIPTOR)
            if descriptor_numbers() != {0, 1, 2}:
                fail("private GPG inspection retained private descriptors")
            environment = signing_environment()
        else:
            assert_signing_gpg_argv(sys.argv[2:])
            os.set_inheritable(PASSPHRASE_DESCRIPTOR, True)
            environment = signing_environment()
        os.execve(command, sys.argv[2:], environment)
    except (GuardError, OSError):
        print("ERROR: offline signing descriptor hygiene failed", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
