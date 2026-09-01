#!/usr/bin/env python3

"""Serve one immutable disposable repository over loopback TLS for QEMU slirp."""

from __future__ import annotations

import http.server
import os
from pathlib import Path
import ssl
import sys
import urllib.parse


def fail(message: str) -> "NoReturn":
    raise SystemExit(message)


if len(sys.argv) != 5:
    fail("usage: https-server.py ROOT CERT KEY READY_FILE")

root, certificate, private_key, ready_file = map(Path, sys.argv[1:])
for path in (root, certificate, private_key, ready_file.parent):
    if not path.is_absolute():
        fail(f"path is not absolute: {path}")
if not root.is_dir() or root.is_symlink():
    fail("repository root is unsafe")
for path in (certificate, private_key):
    if not path.is_file() or path.is_symlink():
        fail(f"TLS input is unsafe: {path}")
if ready_file.exists() or ready_file.is_symlink():
    fail("readiness file already exists")


class RepositoryHandler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *args: object, **kwargs: object) -> None:
        super().__init__(*args, directory=os.fspath(root), **kwargs)

    def list_directory(self, path: str) -> None:
        self.send_error(http.HTTPStatus.FORBIDDEN)
        return None

    def translate_path(self, path: str) -> str:
        parsed = urllib.parse.urlsplit(path)
        if parsed.query or parsed.fragment or "\\" in parsed.path:
            return os.fspath(root / ".invalid-request")
        translated = Path(super().translate_path(parsed.path))
        try:
            translated.relative_to(root)
        except ValueError:
            return os.fspath(root / ".invalid-request")
        return os.fspath(translated)

    def do_POST(self) -> None:
        self.send_error(http.HTTPStatus.METHOD_NOT_ALLOWED)

    def do_PUT(self) -> None:
        self.send_error(http.HTTPStatus.METHOD_NOT_ALLOWED)

    def do_DELETE(self) -> None:
        self.send_error(http.HTTPStatus.METHOD_NOT_ALLOWED)

    def log_message(self, message: str, *args: object) -> None:
        sys.stderr.write("VM_REPOSITORY_HTTPS " + (message % args) + "\n")
        sys.stderr.flush()


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RepositoryHandler)
server.daemon_threads = True
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_2
context.load_cert_chain(certificate, private_key)
server.socket = context.wrap_socket(server.socket, server_side=True)

ready_fd = os.open(ready_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(ready_fd, "w", encoding="ascii") as stream:
    stream.write(f"{server.server_port}\n")
    stream.flush()
    os.fsync(stream.fileno())

server.serve_forever(poll_interval=0.25)
