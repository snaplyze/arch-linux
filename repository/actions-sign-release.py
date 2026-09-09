#!/usr/bin/python3 -I
"""Import an Actions signing subkey into a disposable, network-isolated launcher operation."""

from __future__ import annotations

import argparse
import base64
import ctypes
import grp
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import pwd
import re
import resource
import select
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import time
from typing import BinaryIO


sys.dont_write_bytecode = True
ACCOUNT = "arch-linux-signing"
ROOT_ENV = {"HOME": "/root", "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/usr/sbin"}
PUBLIC_ENV = {"HOME": "/nonexistent", "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin"}
MAGIC = b"ALISIGN1"
READY = b"ALI_READY1\n"
KEY_LIMIT = 32768
PASSPHRASE_LIMIT = 4096
SOURCE_OPTIONS = ("source_commit", "source_tree", "source_tree_sha256")
SNAPSHOT_OPTIONS = ("unsigned", "installer", "output", "release_version",
                    "build_metadata_sha256", "unsigned_manifest_sha256")
FINALIZE_OPTIONS = ("phase_a", "output", "release_version", "build_metadata_sha256",
                    "unsigned_manifest_sha256", "snapshot_sha256", "minimal_run", "stock_run", "marble_run")


class SigningError(ValueError):
    pass


def fail(message: str) -> None:
    raise SigningError(message)


def harden() -> None:
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    if ctypes.CDLL(None, use_errno=True).prctl(4, 0, 0, 0, 0) != 0:
        fail("cannot disable process dumpability")
    os.umask(0o077)


def bind_parent(expected_parent: int) -> None:
    if (ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGKILL, 0, 0, 0) != 0
            or os.getppid() != expected_parent):
        os._exit(125)


def run(arguments: list[str], *, environment: dict[str, str] | None = None,
        payload: bytes | None = None, descriptors: tuple[int, ...] = (), timeout: int = 300,
        label: str = "required isolated command") -> bytes:
    parent_pid = os.getpid()
    completed = subprocess.run(arguments, input=payload, stdin=subprocess.DEVNULL if payload is None else None,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ROOT_ENV if environment is None else environment,
                               pass_fds=descriptors, timeout=timeout, check=False,
                               preexec_fn=None if parent_pid == 1 else lambda: bind_parent(parent_pid))
    if completed.returncode != 0:
        if label == "sealed launcher operation":
            source_line = re.search(rb"command failed at source line ([0-9]+)", completed.stderr)
            if source_line:
                fail(f"sealed launcher operation failed at source line {int(source_line[1])}")
        fail(f"{label} failed")
    return completed.stdout


def valid_passphrase(value: bytes) -> bool:
    return 0 < len(value) <= PASSPHRASE_LIMIT and not any(byte in value for byte in (0, 10, 13))


def encode_request(key: bytes, passphrase: bytes) -> bytes:
    if not 0 < len(key) <= KEY_LIMIT or not valid_passphrase(passphrase):
        fail("secret input has invalid size or framing")
    return MAGIC + struct.pack(">II", len(key), len(passphrase)) + key + passphrase


def read_exact(stream: BinaryIO, size: int) -> bytes:
    result = bytearray()
    while len(result) < size:
        block = stream.read(size - len(result))
        if not block:
            fail("secret request is truncated")
        result.extend(block)
    return bytes(result)


def read_request(stream: BinaryIO, *, require_eof: bool = True) -> tuple[bytes, bytes]:
    header = read_exact(stream, 16)
    if header[:8] != MAGIC:
        fail("secret request protocol differs")
    key_size, passphrase_size = struct.unpack(">II", header[8:])
    if not 0 < key_size <= KEY_LIMIT or not 0 < passphrase_size <= PASSPHRASE_LIMIT:
        fail("secret request exceeds its bound")
    key, passphrase = read_exact(stream, key_size), read_exact(stream, passphrase_size)
    if (require_eof and stream.read(1)) or not valid_passphrase(passphrase):
        fail("secret request has trailing or invalid data")
    return key, passphrase


def public_inventory(root: Path) -> dict[str, tuple[int, str]]:
    result: dict[str, tuple[int, str]] = {}
    pending = [root]
    while pending:
        path = pending.pop()
        metadata = path.lstat()
        if metadata.st_uid != 0 or metadata.st_gid != 0 or os.listxattr(path, follow_symlinks=False):
            fail("accepted input ownership or extended authority differs")
        if stat.S_ISDIR(metadata.st_mode):
            if stat.S_IMODE(metadata.st_mode) != 0o755:
                fail("accepted input directory mode differs")
            pending.extend(path.iterdir())
        elif stat.S_ISREG(metadata.st_mode):
            if stat.S_IMODE(metadata.st_mode) != 0o644 or metadata.st_nlink != 1:
                fail("accepted input file metadata differs")
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            after = path.lstat()
            if any(getattr(metadata, field) != getattr(after, field) for field in (
                "st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns"
            )):
                fail("accepted input changed during capture")
            result[str(path.relative_to(root))] = (metadata.st_size, digest)
        else:
            fail("accepted input contains a link or special object")
        if len(result) + len(pending) > 20000:
            fail("accepted input exceeds its file bound")
    return result


def safe_ancestors(path: Path) -> None:
    if not path.is_absolute() or path.resolve(strict=True) != path:
        fail("public path is not canonical")
    for current in (path, *path.parents):
        metadata = current.lstat()
        if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_gid != 0
                or stat.S_IMODE(metadata.st_mode) & 0o022
                or os.listxattr(current, follow_symlinks=False)):
            fail("public path has unsafe ancestors")


def captured_source_bytes(path: Path, expected_metadata: os.stat_result | None = None) -> bytes:
    before = path.lstat()
    if (not stat.S_ISREG(before.st_mode) or before.st_uid != 0 or before.st_gid != 0
            or before.st_nlink != 1 or stat.S_IMODE(before.st_mode) not in (0o644, 0o755)
            or before.st_size > 128 * 1024 * 1024 or os.listxattr(path, follow_symlinks=False)):
        fail("canonical source metadata differs")
    fields = ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns")
    expected = tuple(getattr(before, field) for field in fields)
    if expected_metadata is not None and tuple(getattr(expected_metadata, field) for field in fields) != expected:
        fail("canonical source changed before capture")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    with os.fdopen(descriptor, "rb") as stream:
        if tuple(getattr(os.fstat(stream.fileno()), field) for field in fields) != expected:
            fail("canonical source changed before capture")
        data = stream.read(128 * 1024 * 1024 + 1)
        if tuple(getattr(os.fstat(stream.fileno()), field) for field in fields) != expected:
            fail("canonical source changed while capturing bytes")
    if len(data) != before.st_size or tuple(getattr(path.lstat(), field) for field in fields) != expected:
        fail("canonical source changed after capture")
    return data


def source_root() -> Path:
    entry = Path(__file__)
    if not entry.is_absolute() or entry.resolve(strict=True) != entry:
        fail("adapter entry is not canonical")
    root = entry.parent.parent
    safe_ancestors(entry.parent)
    metadata = entry.lstat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_gid != 0
            or stat.S_IMODE(metadata.st_mode) not in (0o644, 0o755, 0o444, 0o555)
            or metadata.st_nlink != 1 or os.listxattr(entry, follow_symlinks=False)):
        fail("adapter entry is not protected source")
    return root


def initial_root() -> None:
    if (os.getuid() != 0 or os.geteuid() != 0 or os.getgid() != 0
            or Path("/proc/self/uid_map").read_text().split() != ["0", "0", "4294967295"]):
        fail("initial host root is required")
    if dict(os.environ) != ROOT_ENV:
        fail("root broker environment is not exact and empty-derived")


def signing_account(*, provision: bool = False) -> tuple[int, int]:
    try:
        account = pwd.getpwnam(ACCOUNT)
    except KeyError:
        if not provision:
            fail("dedicated signing account is absent")
        try:
            grp.getgrnam(ACCOUNT)
        except KeyError:
            pass
        else:
            fail("partial signing account must not be modified")
        run(["/usr/bin/useradd", "--system", "--user-group", "--no-create-home", "--home-dir",
             "/nonexistent", "--shell", "/usr/sbin/nologin", "--password", "!", ACCOUNT])
        account = pwd.getpwnam(ACCOUNT)
    group = grp.getgrgid(account.pw_gid)
    if (account.pw_uid <= 0 or account.pw_gid <= 0 or account.pw_dir != "/nonexistent"
            or account.pw_shell != "/usr/sbin/nologin" or group.gr_name != ACCOUNT or group.gr_mem
            or os.getgrouplist(ACCOUNT, account.pw_gid) != [account.pw_gid]):
        fail("dedicated signing account policy differs")
    return account.pw_uid, account.pw_gid


def as_signer(uid: int, gid: int, arguments: list[str]) -> list[str]:
    return ["/usr/bin/setpriv", f"--reuid={uid}", f"--regid={gid}", "--clear-groups", "--", *arguments]


def verify_sealed(root: Path, args: argparse.Namespace, uid: int, gid: int) -> None:
    verifier = root / "repository/verify-sealed-offline-code.py"
    command = ["/usr/bin/python3", "-I", str(verifier), str(root),
               args.source_commit, args.source_tree, args.source_tree_sha256]
    if os.getuid() == 0:
        command = as_signer(uid, gid, command)
    run(command, environment=PUBLIC_ENV)


def prepare(args: argparse.Namespace) -> None:
    initial_root()
    root = source_root()
    git = ["/usr/bin/git", "-C", str(root)]
    if (run([*git, "rev-parse", "HEAD^{commit}"]).decode().strip() != args.source_commit
            or run([*git, "rev-parse", "HEAD^{tree}"]).decode().strip() != args.source_tree
            or run([*git, "status", "--porcelain=v1", "--untracked-files=all"])):
        fail("canonical source is not the exact clean accepted commit and tree")
    rows = []
    accepted_sealer = None
    for raw_name in run([*git, "ls-files", "-z"]).split(b"\0"):
        if not raw_name:
            continue
        name = raw_name.decode("utf-8")
        path = root / name
        safe_ancestors(path.parent)
        metadata = path.lstat()
        captured = captured_source_bytes(path, metadata)
        rows.append(f"{stat.S_IMODE(metadata.st_mode):04o} {hashlib.sha256(captured).hexdigest()} *{name}\n")
        if name == "repository/seal-offline-signing-code.py":
            accepted_sealer = captured
    if hashlib.sha256("".join(sorted(rows)).encode()).hexdigest() != args.source_tree_sha256:
        fail("canonical source hash differs")
    if accepted_sealer is None:
        fail("accepted source omits the sealer")
    signing_account(provision=True)
    runtime = Path("/run/user")
    if not runtime.exists():
        safe_ancestors(runtime.parent)
        runtime.mkdir(mode=0o755)
    safe_ancestors(runtime)
    destination = Path(args.sealed_root)
    safe_ancestors(destination.parent)
    if destination.exists() or destination.is_symlink():
        fail("sealed destination already exists")
    sealer = root / "repository/seal-offline-signing-code.py"
    accepted_hash = hashlib.sha256(accepted_sealer).hexdigest()
    if captured_source_bytes(sealer) != accepted_sealer:
        fail("accepted sealer changed after source capture")
    with tempfile.TemporaryDirectory(prefix="arch-linux-sealer-", dir="/root") as temporary:
        copied = Path(temporary) / "sealer"
        copied.write_bytes(accepted_sealer)
        copied.chmod(0o500)
        if hashlib.sha256(copied.read_bytes()).hexdigest() != accepted_hash:
            fail("bootstrapped sealer hash differs")
        run(["/usr/bin/python3", "-I", str(copied), str(root), args.source_commit,
             args.source_tree, args.source_tree_sha256, str(destination)])
    print("Actions signing source: sealed and tree-bound")


def operation_arguments(args: argparse.Namespace) -> list[str]:
    names = SNAPSHOT_OPTIONS if args.operation == "snapshot" else FINALIZE_OPTIONS
    return [args.operation, *(part for name in names for part in ("--" + name.replace("_", "-"), getattr(args, name)))]


def accepted_arguments(args: argparse.Namespace) -> list[str]:
    return [*operation_arguments(args), *(part for name in SOURCE_OPTIONS
                                          for part in ("--" + name.replace("_", "-"), getattr(args, name)))]


def public_environment(root: Path, args: argparse.Namespace) -> dict[str, str]:
    return PUBLIC_ENV | {"ARCH_LINUX_PUBLIC_CODE_ROOT": str(root),
                         "ARCH_LINUX_PUBLIC_ACCEPTED_COMMIT": args.source_commit,
                         "ARCH_LINUX_PUBLIC_ACCEPTED_TREE": args.source_tree,
                         "ARCH_LINUX_PUBLIC_ACCEPTED_TREE_SHA256": args.source_tree_sha256}


def verify_inputs(root: Path, args: argparse.Namespace, uid: int, gid: int) -> dict[str, dict[str, tuple[int, str]]]:
    paths = [args.unsigned] if args.operation == "snapshot" else [args.phase_a, args.minimal_run, args.stock_run, args.marble_run]
    inventories = {}
    for raw_path in paths:
        path = Path(raw_path)
        safe_ancestors(path)
        if root == path or root in path.parents or path in root.parents:
            fail("accepted input overlaps sealed source")
        inventories[raw_path] = public_inventory(path)
    input_root = Path(paths[0])
    if run(as_signer(uid, gid, ["/usr/bin/bash", str(root / "arch-linux-installer.sh"), "--version"]),
           environment=PUBLIC_ENV).decode().strip() != args.release_version:
        fail("sealed installer version differs")
    run(as_signer(uid, gid, ["/usr/bin/bash", "-c",
                            'source "$1"; repository_assert_public_certificate "$2" "$3" "$4" 15552000',
                            "public-certificate-check", str(root / "repository/lib/common.sh"),
                            str(root / "repository/trust/arch-linux.gpg"),
                            str(root / "repository/trust/primary-fingerprint"),
                            str(root / "repository/trust/signing-subkey-fingerprint")]), environment=PUBLIC_ENV)
    for name, expected in (("BUILD-METADATA.json", args.build_metadata_sha256),
                           ("UNSIGNED-SHA256SUMS", args.unsigned_manifest_sha256)):
        if inventories[paths[0]].get(name, (0, ""))[1] != expected:
            fail("accepted build manifest hash differs")
    if args.operation == "snapshot":
        if args.installer != str(root / "arch-linux-installer.sh"):
            fail("installer is not the exact sealed installer")
        command = ["/usr/bin/bash", str(root / "repository/verify-unsigned-build.sh"),
                   "--sealed-public-root", args.unsigned]
    else:
        archive = f"arch-linux-repository-{args.release_version}.tar.zst"
        if inventories[paths[0]].get(archive, (0, ""))[1] != args.snapshot_sha256:
            fail("accepted snapshot hash differs")
        command = ["/usr/bin/bash", str(root / "repository/verify-release-assets.sh"), args.phase_a,
                   "--phase-a", "--sealed-public-root", "--release-version", args.release_version,
                   "--source-commit", args.source_commit, "--source-tree", args.source_tree,
                   "--source-tree-sha256", args.source_tree_sha256,
                   "--build-metadata-sha256", args.build_metadata_sha256,
                   "--unsigned-manifest-sha256", args.unsigned_manifest_sha256]
    run(as_signer(uid, gid, command), environment=public_environment(root, args), timeout=900)
    if args.operation == "finalize":
        spec = importlib.util.spec_from_file_location("sealed_acceptance", root / "repository/acceptance-manifest.py")
        if spec is None or spec.loader is None:
            fail("sealed acceptance verifier is unavailable")
        acceptance = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = acceptance
        spec.loader.exec_module(acceptance)
        contract = acceptance.snapshot_contract(input_root, args.release_version, args.source_commit,
                                                 args.source_tree, args.build_metadata_sha256,
                                                 args.unsigned_manifest_sha256)
        expected = {"buildMetadataSha256": args.build_metadata_sha256,
                    "unsignedManifestSha256": args.unsigned_manifest_sha256,
                    "repositorySnapshotSha256": args.snapshot_sha256,
                    "releaseSha256sumsSha256": inventories[paths[0]]["RELEASE-SHA256SUMS"][1]}
        for raw_path, scenario in zip(paths[1:], acceptance.SCENARIOS, strict=True):
            acceptance.directory_run(Path(raw_path), scenario, args.source_commit, args.source_tree,
                                     args.release_version, expected, contract,
                                     inventories[paths[0]]["install.sh"][1])
    for raw_path, inventory in inventories.items():
        if public_inventory(Path(raw_path)) != inventory:
            fail("accepted input changed during public verification")
    output = Path(args.output)
    if not output.is_absolute() or output.name in ("", ".", "..") or output.exists() or output.is_symlink():
        fail("signing output is not an absent canonical destination")
    parent = output.parent
    safe_ancestors(parent.parent)
    for candidate in [root, *(Path(value) for value in paths)]:
        if parent == candidate or parent in candidate.parents or candidate in parent.parents:
            fail("signing output overlaps accepted source or inputs")
    if not parent.exists():
        parent.mkdir(mode=0o700)
        os.chown(parent, uid, gid)
    metadata = parent.lstat()
    if (not stat.S_ISDIR(metadata.st_mode) or parent.resolve() != parent or metadata.st_uid != uid
            or metadata.st_gid != gid or stat.S_IMODE(metadata.st_mode) != 0o700
            or os.listxattr(parent, follow_symlinks=False)):
        fail("signing output parent metadata differs")
    return inventories


def packet_bodies(armored: bytes) -> list[tuple[int, bytes]]:
    try:
        lines = armored.decode("ascii").strip().splitlines()
        label = "PGP " + "PRIVATE KEY BLOCK"
        if lines[0] != f"-----BEGIN {label}-----" or lines[-1] != f"-----END {label}-----":
            fail("signing transfer is not one armored secret export")
        middle = lines[1:-1]
        while middle and middle[0]:
            if not re.fullmatch(r"(?:Version|Comment): [ -~]*", middle.pop(0)):
                fail("signing transfer armor headers differ")
        if not middle:
            fail("signing transfer armor separator is absent")
        middle.pop(0)
        if middle and middle[-1].startswith("="):
            middle.pop()
        raw = base64.b64decode("".join(middle), validate=True)
    except (IndexError, UnicodeError, ValueError) as error:
        raise SigningError("signing transfer armor is malformed") from error
    result = []
    stream = io.BytesIO(raw)
    while header := stream.read(1):
        value = header[0]
        if not value & 0x80:
            fail("signing transfer packet header differs")
        if value & 0x40:
            tag = value & 0x3F
            length = read_exact(stream, 1)[0]
            if 192 <= length <= 223:
                length = ((length - 192) << 8) + read_exact(stream, 1)[0] + 192
            elif length == 255:
                length = int.from_bytes(read_exact(stream, 4), "big")
            elif length > 223:
                fail("partial signing transfer packets are forbidden")
        else:
            tag, kind = (value >> 2) & 0xF, value & 3
            if kind == 3:
                fail("unbounded signing transfer packets are forbidden")
            length = int.from_bytes(read_exact(stream, 1 << kind), "big")
        if length > KEY_LIMIT or tag not in (2, 5, 7, 13):
            fail("signing transfer packet closure differs")
        result.append((tag, read_exact(stream, length)))
    return result


def public_key_end(body: bytes) -> int:
    if len(body) < 8 or body[0] != 4:
        fail("signing transfer must use version-four public keys")
    algorithm, cursor = body[5], 6
    if algorithm in (19, 22):
        cursor += 1 + body[cursor]
        fields = 1
    elif algorithm in (1, 2, 3):
        fields = 2
    elif algorithm == 17:
        fields = 4
    else:
        fail("signing transfer algorithm is unsupported")
    for _ in range(fields):
        if cursor + 2 > len(body):
            fail("signing transfer public key is truncated")
        size = int.from_bytes(body[cursor:cursor + 2], "big")
        cursor += 2 + (size + 7) // 8
    if cursor >= len(body):
        fail("signing transfer secret-key fields are missing")
    return cursor


def assert_signing_transfer(key: bytes, primary: str, signing: str) -> None:
    packets = packet_bodies(key)
    for tag, fingerprint in ((5, primary), (7, signing)):
        records = [body for kind, body in packets if kind == tag]
        if len(records) != 1:
            fail("signing transfer must contain exactly one primary and one subkey")
        body = records[0]
        end = public_key_end(body)
        actual = hashlib.sha1(b"\x99" + end.to_bytes(2, "big") + body[:end]).hexdigest().upper()
        if actual != fingerprint:
            fail("signing transfer fingerprint differs from pinned public trust")
        if tag == 5 and body[end:] != bytes.fromhex("ff006500474e5501"):
            fail("certification-primary private material is forbidden in Actions")
        if tag == 7 and (body[end] not in (254, 255) or body[end:] == bytes.fromhex("ff006500474e5501")):
            fail("signing subkey must be available and passphrase-protected")


def account_processes(uid: int) -> list[int]:
    result = []
    for path in Path("/proc").glob("[0-9]*/status"):
        try:
            match = re.search(r"^Uid:\s+(\d+)", path.read_text(), re.M)
        except (FileNotFoundError, ProcessLookupError):
            continue
        if match and int(match[1]) == uid:
            result.append(int(path.parent.name))
    return result


def quiesce(uid: int, gid: int, home: Path) -> None:
    run(as_signer(uid, gid, ["/usr/bin/gpgconf", "--homedir", str(home), "--kill", "all"]),
        environment=PUBLIC_ENV)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            while os.waitpid(-1, os.WNOHANG)[0]:
                pass
        except ChildProcessError:
            pass
        if not account_processes(uid):
            return
        time.sleep(0.05)
    fail("signing account did not become quiescent")


def watch_broker() -> None:
    """Terminate namespace PID 1 if its broker closes or extends the request pipe."""
    try:
        os.read(0, 1)
    finally:
        os._exit(1)


def isolated(root: Path, args: argparse.Namespace, uid: int, gid: int) -> None:
    if os.getpid() != 1 or {line.split(":")[0].strip() for line in Path("/proc/net/dev").read_text().splitlines()[2:]} != {"lo"}:
        fail("import requires a fresh PID and loopback-only network namespace")
    if account_processes(uid):
        fail("signing account has ambient processes")
    run(["/usr/bin/mount", "-t", "tmpfs", "-o", "mode=1777,nosuid,nodev,noexec,size=16m", "tmpfs", "/dev/shm"])
    run(["/usr/bin/mount", "-t", "tmpfs", "-o", "mode=0755,nosuid,nodev,noexec,size=4m", "tmpfs", "/run/user"])
    runtime = Path(f"/run/user/{uid}")
    runtime.mkdir(mode=0o700)
    os.chown(runtime, uid, gid)
    work = Path(tempfile.mkdtemp(prefix="arch-linux-actions-", dir="/dev/shm"))
    work.chmod(0o711)
    home, pass_file = work / "gnupg", work / "passphrase"
    home.mkdir(mode=0o700)
    os.chown(home, uid, gid)
    try:
        with os.fdopen(os.dup(0), "rb", buffering=0) as stream:
            key, passphrase = read_request(stream, require_eof=False)
        # The broker keeps this pipe open until completion. EOF means its supervisor died;
        # any extra byte means the exact request was violated. Exiting PID 1 destroys every
        # process and both private tmpfs mounts, including on an uncatchable broker death.
        threading.Thread(target=watch_broker, daemon=True).start()
        primary = (root / "repository/trust/primary-fingerprint").read_text().strip()
        signing = (root / "repository/trust/signing-subkey-fingerprint").read_text().strip()
        assert_signing_transfer(key, primary, signing)
        descriptor = os.open(pass_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(passphrase + b"\n")
        os.chown(pass_file, uid, gid)
        passphrase = b""
        with pass_file.open("rb") as secret_stream:
            gpg = ["/usr/bin/gpg", "--batch", "--no-options", "--no-tty", "--homedir", str(home),
                   "--pinentry-mode", "loopback", "--passphrase-fd", str(secret_stream.fileno())]
            run(as_signer(uid, gid, [*gpg, "--import"]), environment=PUBLIC_ENV,
                payload=(root / "repository/trust/arch-linux.gpg").read_bytes(), descriptors=(secret_stream.fileno(),),
                label="public certificate import")
            secret_stream.seek(0)
            run(as_signer(uid, gid, [*gpg, "--import"]), environment=PUBLIC_ENV,
                payload=key, descriptors=(secret_stream.fileno(),), label="signing subkey import")
        key = b""
        quiesce(uid, gid, home)
        request = f"{home}\n{pass_file}\n".encode()
        run([str(root / "repository/offline-signing-launcher"), *operation_arguments(args)],
            environment={}, payload=request, timeout=1800, label="sealed launcher operation")
    finally:
        try:
            quiesce(uid, gid, home)
        finally:
            for pid in account_processes(uid):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            shutil.rmtree(work)


def root_broker(args: argparse.Namespace) -> None:
    initial_root()
    if not stat.S_ISFIFO(os.fstat(0).st_mode):
        fail("root broker requires pipe stdin")
    root = source_root()
    uid, gid = signing_account()
    verify_sealed(root, args, uid, gid)
    if args.entry == "isolated":
        verify_inputs(root, args, uid, gid)
        isolated(root, args, uid, gid)
        return
    if account_processes(uid):
        fail("signing account has ambient processes")
    verify_inputs(root, args, uid, gid)
    # Check the same nonroot namespace primitive the compiled launcher needs before reading stdin.
    run(as_signer(uid, gid, ["/usr/bin/unshare", "--user", "--map-root-user", "--net", "--pid",
                            "--mount-proc", "--fork", "--kill-child=SIGKILL", "/usr/bin/true"]), environment=PUBLIC_ENV)
    sys.stdout.buffer.write(READY)
    sys.stdout.buffer.flush()
    command = ["/usr/bin/unshare", "--net", "--mount", "--pid", "--mount-proc", "--propagation", "private",
               "--fork", "--kill-child=SIGKILL", "/usr/bin/python3", "-I", str(Path(__file__)),
               "--entry", "isolated", *accepted_arguments(args)]
    parent_pid = os.getpid()
    completed = subprocess.run(command, env=ROOT_ENV, stdin=sys.stdin.buffer, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=2100, check=False,
                               preexec_fn=lambda: bind_parent(parent_pid))
    if completed.returncode:
        source_line = re.fullmatch(rb"ERROR: Actions signing boundary failed: sealed launcher operation failed at source line ([0-9]+)\n", completed.stderr)
        if source_line:
            fail(f"sealed launcher operation failed at source line {int(source_line[1])}")
        for detail in ("public certificate import", "signing subkey import", "sealed launcher operation"):
            if completed.stderr == f"ERROR: Actions signing boundary failed: {detail} failed\n".encode():
                fail(f"{detail} failed")
        fail("isolated signing operation failed")


def broker(args: argparse.Namespace) -> None:
    if os.getuid() != 0 or os.geteuid() != 0:
        fail("host root signing job is required")
    root = source_root()
    uid, gid = signing_account()
    verify_sealed(root, args, uid, gid)
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("GITHUB_REF") != "refs/heads/main":
        fail("secret broker requires the main-branch Actions context")
    command = ["/usr/bin/python3", "-I", str(Path(__file__)), "--entry", "root", *accepted_arguments(args)]
    process = subprocess.Popen(command, env=ROOT_ENV, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    writer = process.stdin
    try:
        assert process.stdout is not None
        if not select.select([process.stdout], [], [], 1200)[0] or process.stdout.read(len(READY)) != READY:
            fail("root broker did not verify accepted inputs before secret handoff")
        key = os.environ.pop("ARCH_LINUX_SIGNING_KEY", "").encode()
        phrase = os.environ.pop("ARCH_LINUX_SIGNING_PASSPHRASE", "").encode()
        request = encode_request(key, phrase)
        key = phrase = b""
        assert writer is not None
        writer.write(request)
        writer.flush()
        process.stdin = None
        output, _error = process.communicate(timeout=2400)
        request = b""
        if process.returncode or output:
            source_line = re.fullmatch(rb"ERROR: Actions signing boundary failed: sealed launcher operation failed at source line ([0-9]+)\n", _error)
            if source_line:
                fail(f"sealed launcher operation failed at source line {int(source_line[1])}")
            for detail in ("public certificate import", "signing subkey import", "sealed launcher operation"):
                if _error == f"ERROR: Actions signing boundary failed: {detail} failed\n".encode():
                    fail(f"{detail} failed")
            fail("isolated signing operation failed")
    finally:
        if writer is not None:
            writer.close()
        if process.poll() is None:
            process.kill()
        process.wait()
    print(f"Actions signing completed: operation={args.operation}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--entry", choices=("broker", "root", "isolated"), default="broker", help=argparse.SUPPRESS)
    operations = result.add_subparsers(dest="operation", required=True)
    for operation in ("prepare", "snapshot", "finalize"):
        command = operations.add_parser(operation)
        for name in SOURCE_OPTIONS:
            command.add_argument("--" + name.replace("_", "-"), required=True)
        if operation == "prepare":
            command.add_argument("--sealed-root", required=True)
        else:
            for name in SNAPSHOT_OPTIONS if operation == "snapshot" else FINALIZE_OPTIONS:
                command.add_argument("--" + name.replace("_", "-"), required=True)
    return result


def main() -> int:
    try:
        harden()
        args = parser().parse_args()
        for name in SOURCE_OPTIONS:
            if re.fullmatch(r"[a-f0-9]{64}" if name.endswith("sha256") else r"[a-f0-9]{40}", getattr(args, name)) is None:
                fail("accepted source identity is malformed")
        if args.operation != "prepare":
            if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.release_version) is None:
                fail("release version is malformed")
            for name in ("build_metadata_sha256", "unsigned_manifest_sha256", *(["snapshot_sha256"] if args.operation == "finalize" else [])):
                if re.fullmatch(r"[a-f0-9]{64}", getattr(args, name)) is None:
                    fail("accepted artifact hash is malformed")
        def interrupted(_signum: int, _frame: object) -> None:
            raise SigningError("operation interrupted")
        for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            signal.signal(signum, interrupted)
        if args.operation == "prepare":
            prepare(args)
        elif args.entry == "broker":
            broker(args)
        else:
            root_broker(args)
    except SigningError as error:
        print(f"ERROR: Actions signing boundary failed: {error}", file=sys.stderr)
        return 1
    except (OSError, ValueError, subprocess.SubprocessError):
        print("ERROR: Actions signing boundary failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
