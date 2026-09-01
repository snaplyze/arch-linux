#!/usr/bin/env python3
"""Safely extract the deterministic repository archive below repo/x86_64."""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import stat
import subprocess
import tarfile
import tempfile
from typing import NoReturn

ALLOWED_DIRECTORIES = {"repo", "repo/x86_64"}
PREFIX = pathlib.PurePosixPath("repo/x86_64")
MAX_FILES = 200
MAX_FILE_SIZE = 1024 * 1024 * 1024
MAX_TOTAL_SIZE = 4 * 1024 * 1024 * 1024
MAX_TAR_SIZE = MAX_TOTAL_SIZE + (MAX_FILES + 2) * 1024 * 1024


def die(message: str) -> NoReturn:
    raise SystemExit(f"snapshot extraction error: {message}")


def validate_member_name(name: str, is_directory: bool) -> pathlib.PurePosixPath:
    if not name or name.startswith("/") or "\\" in name or "\x00" in name:
        die(f"unsafe archive member name: {name!r}")
    stripped = name.rstrip("/")
    pure = pathlib.PurePosixPath(stripped)
    if pure.is_absolute() or any(part in {"", ".", ".."} for part in pure.parts):
        die(f"unsafe archive member path: {name!r}")
    normalized = pure.as_posix()
    if is_directory:
        if normalized not in ALLOWED_DIRECTORIES:
            die(f"unexpected archive directory: {name!r}")
    else:
        if pure.parent != PREFIX or len(pure.parts) != 3:
            die(f"archive file is outside repo/x86_64: {name!r}")
        filename = pure.name
        if not filename or any(ch not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+._-" for ch in filename):
            die(f"unsafe repository filename: {filename!r}")
    return pure


def extract(archive: pathlib.Path, destination: pathlib.Path) -> None:
    if not archive.is_file() or archive.is_symlink() or archive.stat().st_nlink != 1:
        die(f"archive is missing, linked, or not regular: {archive}")
    if not archive.name.endswith(".tar.zst"):
        die("archive name must end in .tar.zst")
    zstd = shutil.which("zstd")
    if zstd is None:
        die("zstd is unavailable")
    if destination.exists() or destination.is_symlink():
        die(f"destination already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.mkdir(mode=0o755)
    temporary_tar: pathlib.Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=".arch-linux-snapshot.", suffix=".tar", dir=destination.parent, delete=False
        ) as target:
            temporary_tar = pathlib.Path(target.name)
            process = subprocess.Popen(
                [zstd, "--decompress", "--quiet", "--stdout", "--", str(archive)],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
            if process.stdout is None:
                process.kill()
                process.wait()
                die("cannot read zstd output")
            written = 0
            try:
                for chunk in iter(lambda: process.stdout.read(1024 * 1024), b""):
                    written += len(chunk)
                    if written > MAX_TAR_SIZE:
                        process.kill()
                        die("decompressed tar size limit exceeded")
                    target.write(chunk)
            except BaseException:
                process.kill()
                process.wait()
                raise
            finally:
                process.stdout.close()
            if process.wait() != 0:
                die("zstd decompression failed")
        os.chmod(temporary_tar, 0o600)

        with tarfile.open(temporary_tar, mode="r:") as stream:
            members: list[tarfile.TarInfo] = []
            seen: set[str] = set()
            count = 0
            total = 0
            for member in stream:
                pure = validate_member_name(member.name, member.isdir())
                normalized = pure.as_posix()
                if normalized in seen:
                    die(f"duplicate archive member: {normalized}")
                seen.add(normalized)
                if member.isdir():
                    if stat.S_IMODE(member.mode) != 0o755:
                        die(f"unsafe directory mode: {normalized}")
                    members.append(member)
                    continue
                if not member.isfile() or member.issym() or member.islnk() or member.isdev() or member.isfifo():
                    die(f"link or special archive member: {normalized}")
                if stat.S_IMODE(member.mode) != 0o644:
                    die(f"unsafe file mode: {normalized}")
                if member.size <= 0 or member.size > MAX_FILE_SIZE:
                    die(f"unsafe file size: {normalized}")
                count += 1
                total += member.size
                if count > MAX_FILES or total > MAX_TOTAL_SIZE:
                    die("archive size/file-count limit exceeded")
                members.append(member)
            if count == 0:
                die("archive contains no files")

            for member in members:
                pure = validate_member_name(member.name, member.isdir())
                output = destination.joinpath(*pure.parts)
                if member.isdir():
                    output.mkdir(parents=True, exist_ok=True)
                    os.chmod(output, 0o755)
                    continue
                output.parent.mkdir(parents=True, exist_ok=True)
                source = stream.extractfile(member)
                if source is None:
                    die(f"cannot read archive member: {member.name}")
                fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
                with source, os.fdopen(fd, "wb") as target:
                    shutil.copyfileobj(source, target, length=1024 * 1024)
                os.chmod(output, 0o644)
    except Exception:
        shutil.rmtree(destination, ignore_errors=True)
        raise
    finally:
        if temporary_tar is not None:
            temporary_tar.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    extract(args.archive.resolve(), args.destination.resolve(strict=False))


if __name__ == "__main__":
    main()
