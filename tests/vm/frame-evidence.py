#!/usr/bin/env python3
"""Optional, bounded QMP screenshots for real-VM diagnostics; never a product verdict."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import socket
import stat
import struct
import sys
import tempfile
import time
from pathlib import Path

MAX_PPM = 64 * 1024 * 1024
QMP_TIMEOUT_SECONDS = 30


class CaptureError(RuntimeError):
    """A diagnostic screenshot could not be captured safely."""


def demand(condition, message):
    if not condition:
        raise CaptureError(message)


def safe_dir(path):
    meta = path.lstat()
    demand(path.is_absolute() and path.resolve(strict=True) == path
           and stat.S_ISDIR(meta.st_mode) and meta.st_uid == os.getuid()
           and stat.S_IMODE(meta.st_mode) == 0o700, "unsafe screenshot directory")


def safe_file(path):
    meta = path.lstat()
    demand(stat.S_ISREG(meta.st_mode) and meta.st_uid == os.getuid()
           and meta.st_nlink == 1 and stat.S_IMODE(meta.st_mode) == 0o600,
           "unsafe screenshot file")
    return meta


def parse_ppm_data(data):
    demand(len(data) <= MAX_PPM, "PPM byte bound exceeded")
    match = re.match(rb"\AP6\n([1-9][0-9]{0,4}) ([1-9][0-9]{0,4})\n255\n", data)
    demand(match is not None, "PPM header is not strict P6")
    width, height = int(match.group(1)), int(match.group(2))
    demand(width <= 8192 and height <= 8192
           and len(data) - match.end() == width * height * 3, "PPM dimensions or payload differ")
    return width, height, hashlib.sha256(data).hexdigest()


def exact_qemu(pid, start):
    try:
        root = Path("/proc") / str(pid)
        fields = (root / "stat").read_text(encoding="ascii").rsplit(") ", 1)[1].split()
        return fields[19] == start and root.stat().st_uid == os.getuid() and (
            root / "exe").resolve(strict=True) == Path("/usr/bin/qemu-system-x86_64").resolve()
    except (OSError, IndexError):
        return False


class QMP:
    def __init__(self, path, pid, start):
        meta = path.lstat()
        demand(stat.S_ISSOCK(meta.st_mode) and meta.st_uid == os.getuid(), "QMP socket identity")
        demand(exact_qemu(pid, start), "QEMU process identity")
        self.connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.reader = None
        self.deadline = time.monotonic() + QMP_TIMEOUT_SECONDS
        try:
            self.connection.settimeout(QMP_TIMEOUT_SECONDS)
            self.connection.connect(str(path))
            peer = struct.unpack("3i", self.connection.getsockopt(
                socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")))
            demand(peer[:2] == (pid, os.getuid()) and exact_qemu(pid, start), "QMP peer identity")
            self.reader = self.connection.makefile("rb", buffering=0)
            demand("QMP" in self.read(), "QMP greeting missing")
            self.execute("qmp_capabilities", {})
        except BaseException:
            self.close()
            raise

    def close(self):
        if self.reader is not None:
            self.reader.close()
        self.connection.close()

    def read(self):
        while True:
            remaining = self.deadline - time.monotonic()
            demand(remaining > 0, "screenshot QMP deadline")
            self.connection.settimeout(remaining)
            line = self.reader.readline(1024 * 1024 + 1)
            demand(0 < len(line) <= 1024 * 1024, "QMP response missing or oversized")
            value = json.loads(line)
            demand(isinstance(value, dict), "QMP response is not an object")
            if "event" not in value:
                return value

    def execute(self, command, arguments):
        demand(command in ("qmp_capabilities", "screendump"), "unsupported screenshot command")
        self.connection.sendall(json.dumps({"execute": command, "arguments": arguments}).encode() + b"\r\n")
        response = self.read()
        demand("error" not in response and "return" in response, "QMP screenshot command failed")


def capture(args):
    root = Path(args.run_root)
    safe_dir(root)
    safe_dir(root / "evidence")
    demand(re.fullmatch(r"[a-z0-9][a-z0-9-]{0,95}", args.name) is not None, "screenshot name")
    demand(args.qemu_pid > 0 and re.fullmatch(r"[1-9][0-9]*", args.qemu_start), "QEMU identity arguments")
    destination = root / "evidence" / (args.name + ".ppm")
    demand(not os.path.lexists(destination), "screenshot already exists")
    qmp = None
    try:
        qmp = QMP(Path(args.qmp_socket), args.qemu_pid, args.qemu_start)
        qmp.execute("screendump", {"filename": str(destination), "device": "display0", "head": 0, "format": "ppm"})
        before = safe_file(destination)
        demand(before.st_size <= MAX_PPM, "screenshot byte bound")
        with destination.open("rb") as stream:
            data = stream.read(MAX_PPM + 1)
            after = os.fstat(stream.fileno())
        identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
        demand(identity(before) == identity(after) == identity(safe_file(destination)), "screenshot changed")
        width, height, digest = parse_ppm_data(data)
        demand(exact_qemu(args.qemu_pid, args.qemu_start), "QEMU exited during screenshot")
        print(f"SCREENSHOT_CAPTURED name={destination.name} width={width} height={height} sha256={digest}")
    except BaseException:
        if os.path.lexists(destination):
            try:
                safe_file(destination)
                destination.unlink()
            except (OSError, CaptureError):
                pass
        raise
    finally:
        if qmp is not None:
            qmp.close()


def self_test():
    good = b"P6\n2 1\n255\n" + bytes(range(6))
    assert parse_ppm_data(good)[:2] == (2, 1)
    for bad in (b"", good + b"x", good[:-1], good.replace(b"P6", b"P3"),
                good.replace(b"255", b"256"), b"P6\n99999 1\n255\n"):
        try:
            parse_ppm_data(bad)
        except CaptureError:
            pass
        else:
            raise AssertionError("malformed screenshot accepted")
    assert not exact_qemu(os.getpid(), "1")
    with tempfile.TemporaryDirectory(prefix="screenshot-check-") as temporary:
        root = Path(temporary)
        safe_dir(root)
        link = root / "link"
        link.symlink_to(root)
        try:
            safe_dir(link)
        except CaptureError:
            pass
        else:
            raise AssertionError("symlink directory accepted")
    print("screenshot helper self-test passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    commands = parser.add_subparsers(dest="command")
    screenshot = commands.add_parser("capture")
    screenshot.add_argument("--run-root", required=True)
    screenshot.add_argument("--qmp-socket", required=True)
    screenshot.add_argument("--qemu-pid", required=True, type=int)
    screenshot.add_argument("--qemu-start", required=True)
    screenshot.add_argument("--name", required=True)
    args = parser.parse_args()
    if args.self_test and args.command is None:
        self_test()
    elif args.command == "capture" and not args.self_test:
        capture(args)
    else:
        parser.error("choose capture or --self-test")


if __name__ == "__main__":
    try:
        main()
    except (CaptureError, OSError, ValueError) as error:
        print(f"SCREENSHOT_WARNING: {error}", file=sys.stderr)
        raise SystemExit(1)
