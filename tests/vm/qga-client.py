#!/usr/bin/python3 -I

import json
import os
import socket
import stat
import struct
import sys
import time


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 4:
    fail("usage: qga-client.py UNIX_SOCKET EXPECTED_QEMU_PID EXPECTED_SOCKET_IDENTITY < REQUEST.json")

socket_path = sys.argv[1]
try:
    expected_pid = int(sys.argv[2], 10)
except ValueError:
    fail("expected QEMU pid is malformed")
expected_identity = sys.argv[3]
if expected_pid <= 0 or not expected_identity.replace(":", "", 1).isdigit():
    fail("expected QEMU or socket identity is malformed")
try:
    metadata = os.lstat(socket_path)
except OSError as error:
    fail(f"cannot inspect QGA socket: {error}")
if not stat.S_ISSOCK(metadata.st_mode):
    fail("QGA path is not a Unix socket")
if metadata.st_uid != os.getuid():
    fail("QGA socket has an unexpected owner")
if f"{metadata.st_dev}:{metadata.st_ino}" != expected_identity:
    fail("QGA socket identity differs from the accepted runtime socket")

request_text = sys.stdin.read(1_048_577)
if not request_text or len(request_text) > 1_048_576:
    fail("QGA request is empty or exceeds one MiB")
try:
    request = json.loads(request_text)
except json.JSONDecodeError as error:
    fail(f"invalid QGA request JSON: {error}")
if not isinstance(request, dict) or "execute" not in request or "id" in request:
    fail("QGA request must be an execute object without a caller-supplied id")

sync_id = (time.time_ns() ^ os.getpid()) & 0x7FFFFFFF
request_id = f"acceptance-{os.getpid()}-{time.time_ns()}"
request["id"] = request_id

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
    connection.settimeout(30)
    connection.connect(socket_path)
    peer_pid, peer_uid, _ = struct.unpack(
        "3i",
        connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")),
    )
    if peer_pid != expected_pid or peer_uid != os.getuid():
        fail("QGA peer is not the exact accepted QEMU process")
    current_metadata = os.lstat(socket_path)
    if (
        not stat.S_ISSOCK(current_metadata.st_mode)
        or f"{current_metadata.st_dev}:{current_metadata.st_ino}" != expected_identity
    ):
        fail("QGA socket changed while the exact peer was connected")
    stream = connection.makefile("rwb", buffering=0)
    sync = {"execute": "guest-sync-delimited", "arguments": {"id": sync_id}}
    stream.write(json.dumps(sync, separators=(",", ":")).encode() + b"\n")
    while True:
        raw = stream.readline(1_048_577)
        if not raw:
            fail("QGA disconnected while synchronizing")
        if len(raw) > 1_048_576:
            fail("QGA synchronization response is too large")
        raw = raw.lstrip(b"\xff")
        try:
            response = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if response.get("return") == sync_id:
            break

    stream.write(json.dumps(request, separators=(",", ":")).encode() + b"\n")
    while True:
        raw = stream.readline(16_777_217)
        if not raw:
            fail("QGA disconnected before the correlated response")
        if len(raw) > 16_777_216:
            fail("QGA response exceeds 16 MiB")
        raw = raw.lstrip(b"\xff")
        try:
            response = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if response.get("id") == request_id:
            print(json.dumps(response, separators=(",", ":")))
            break
