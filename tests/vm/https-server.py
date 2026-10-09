#!/usr/bin/env python3

"""Serve one immutable disposable repository over loopback TLS for QEMU slirp."""

from __future__ import annotations

import http.server
import os
from pathlib import Path
import ssl
import sys
import tempfile
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

    def send_head(self):
        # A previous baseline can have a newer extraction mtime than this frozen
        # snapshot. Always transfer the candidate bytes for GET and HEAD.
        if "If-Modified-Since" in self.headers:
            del self.headers["If-Modified-Since"]
        return super().send_head()

    def send_header(self, keyword: str, value: str) -> None:
        # libcurl also checks Last-Modified itself, even after HTTP 200. Omitting
        # only the request condition would still leave the old pacman database
        # beside a newly downloaded signature from the candidate snapshot.
        if keyword.lower() != "last-modified":
            super().send_header(keyword, value)

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

# Consumers treat existence as readiness, so publish only the complete port bytes.
# A same-directory hard link is atomic and rejects an existing file or symlink.
ready_fd, temporary_ready = tempfile.mkstemp(prefix=f".{ready_file.name}.", dir=ready_file.parent)
try:
    with os.fdopen(ready_fd, "w", encoding="ascii") as stream:
        ready_fd = -1  # fdopen now owns the descriptor, including exceptional exits.
        stream.write(f"{server.server_port}\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.link(temporary_ready, ready_file)
finally:
    if ready_fd >= 0:
        os.close(ready_fd)
    os.unlink(temporary_ready)

server.serve_forever(poll_interval=0.25)
