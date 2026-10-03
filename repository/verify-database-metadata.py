#!/usr/bin/env python3
"""Bind already signature/payload-verified repository databases to package bytes.

This is the public semantic gate, not a substitute for verify-signed-repository.sh
signature, source identity, or package payload verification.
"""
from __future__ import annotations

import base64
import gzip
import io
import pathlib
import re
import runpy
import signal
import stat
import sys
import tarfile
import tempfile
import time
from types import SimpleNamespace

ROOT = pathlib.Path(__file__).resolve().parent.parent
metadata = SimpleNamespace(**runpy.run_path(str(ROOT / 'repository/verify-package-metadata.py')))
# Six current records use <3 MiB expanded, largest files record <3 MiB.
MAX_DATABASE_BYTES = 16 * 1024 * 1024
MAX_DATABASE_EXPANDED_BYTES = 32 * 1024 * 1024
MAX_DATABASE_MEMBER_BYTES = 8 * 1024 * 1024
PKGINFO_FIELDS = {
    'pkgbase': 'BASE', 'pkgdesc': 'DESC', 'size': 'ISIZE', 'url': 'URL',
    'license': 'LICENSE', 'builddate': 'BUILDDATE', 'packager': 'PACKAGER',
    'replaces': 'REPLACES', 'group': 'GROUPS', 'conflict': 'CONFLICTS',
    'provides': 'PROVIDES', 'depend': 'DEPENDS', 'optdepend': 'OPTDEPENDS',
    'makedepend': 'MAKEDEPENDS', 'checkdepend': 'CHECKDEPENDS',
}


def fail(message: str) -> None:
    raise SystemExit(f'repository database check failed: {message}')


def regular(path: pathlib.Path, maximum: int) -> None:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        fail(f'not a single-link regular file: {path.name}')
    if info.st_size > maximum:
        fail(f'compressed size limit exceeded: {path.name}')


def fields(data: bytes, label: str) -> dict[str, list[str]]:
    lines = data.decode('utf-8').splitlines()
    result: dict[str, list[str]] = {}
    current = None
    for line in lines:
        if not line:
            current = None
        elif re.fullmatch(r'%[A-Z][A-Z0-9_]*%', line):
            if current is not None:
                fail(f'missing field separator: {label}')
            current = line[1:-1]
            if current in result:
                fail(f'duplicate %{current}% field: {label}')
            result[current] = []
        elif current is None or metadata.has_control(line):
            fail(f'malformed field value: {label}')
        else:
            result[current].append(line)
    return result


def database_records(path: pathlib.Path, count: int, files: bool) -> dict[str, dict[str, bytes]]:
    regular(path, MAX_DATABASE_BYTES)
    with gzip.open(path, 'rb') as source:
        data = source.read(MAX_DATABASE_EXPANDED_BYTES + 1)
    if len(data) > MAX_DATABASE_EXPANDED_BYTES:
        fail(f'expanded size limit exceeded: {path.name}')
    seen = set()
    directories = set()
    records: dict[str, dict[str, bytes]] = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:', tarinfo=metadata.BoundedTarInfo) as archive:
        for index, member in enumerate(archive, 1):
            if index > count * 4:
                fail(f'database member count limit exceeded: {path.name}')
            name = metadata.safe_member_name(member)
            if name in seen:
                fail(f'duplicate archive path: {name}')
            seen.add(name)
            parts = name.split('/')
            if member.isdir() and len(parts) == 1:
                directories.add(name)
                continue
            if (not member.isfile() or len(parts) != 2 or
                    parts[1] not in ({'desc', 'files'} if files else {'desc'})):
                fail(f'unexpected database archive member: {name}')
            if member.size < 0 or member.size > MAX_DATABASE_MEMBER_BYTES:
                fail(f'database member size limit exceeded: {name}')
            records.setdefault(parts[0], {})[parts[1]] = metadata.read_member(archive, member)
    if set(records) != directories or len(records) != count:
        fail(f'database record/directory closure differs: {path.name}')
    expected = {'desc', 'files'} if files else {'desc'}
    if any(set(record) != expected for record in records.values()):
        fail(f'database record content closure differs: {path.name}')
    return records


def package_record(path: pathlib.Path, deadline: float) -> tuple[str, dict[str, list[str]], list[str]]:
    regular(path, metadata.MAX_COMPRESSED_BYTES)
    regular(path.with_name(path.name + '.sig'), 16384)
    with tempfile.TemporaryFile() as output:
        if metadata.run_zstd_bounded(['zstd', '-q', '-d', '-c', '--', str(path)], deadline, output) != 0:
            fail(f'cannot decompress verified package: {path.name}')
        output.seek(0)
        pkginfo = None
        payload = []
        seen = set()
        aggregate = 0
        with tarfile.open(fileobj=output, mode='r:', tarinfo=metadata.BoundedTarInfo) as archive:
            for index, member in enumerate(archive, 1):
                name = metadata.safe_member_name(member)
                if name in seen or index > metadata.MAX_MEMBERS:
                    fail(f'duplicate path or member count limit: {path.name}')
                seen.add(name)
                aggregate += member.size
                if (member.size < 0 or member.size > metadata.MAX_MEMBER_BYTES or
                        aggregate > metadata.MAX_PAYLOAD_BYTES):
                    fail(f'package payload size limit exceeded: {path.name}')
                if name == '.PKGINFO':
                    pkginfo = metadata.parse_pkginfo(metadata.read_member(archive, member))
                if not name.startswith('.'):
                    payload.append(name + ('/' if member.isdir() else ''))
    if pkginfo is None:
        fail(f'package metadata absent: {path.name}')
    for key in ('pkgname', 'pkgver', 'arch'):
        if len(pkginfo.get(key, [])) != 1:
            fail(f'package identity field differs: {key}')
    package, version, arch = (pkginfo[key][0] for key in ('pkgname', 'pkgver', 'arch'))
    if path.name != f'{package}-{version.split(":", 1)[-1]}-{arch}.pkg.tar.zst':
        fail(f'package filename/identity differs: {path.name}')
    expected = {
        'FILENAME': [path.name], 'NAME': [package], 'VERSION': [version], 'ARCH': [arch],
        'CSIZE': [str(path.stat().st_size)], 'SHA256SUM': [metadata.file_sha(path)],
        'PGPSIG': [base64.b64encode(path.with_name(path.name + '.sig').read_bytes()).decode('ascii')],
    }
    expected.update({field: [re.sub(r'[ \t]+', ' ', value) for value in pkginfo[key]]
                     for key, field in PKGINFO_FIELDS.items() if key in pkginfo})
    return f'{package}-{version}', expected, sorted(payload)


def verify(database: pathlib.Path, files_archive: pathlib.Path, names: list[str]) -> None:
    if not names or len(names) != len(set(names)):
        fail('expected package filename closure differs')
    deadline = time.monotonic() + metadata.MAX_INSPECTION_SECONDS
    db = database_records(database, len(names), False)
    file_db = database_records(files_archive, len(names), True)
    if set(db) != set(file_db):
        fail('db/files package identity closure differs')
    expected_directories = set()
    for name in names:
        if pathlib.PurePath(name).name != name:
            fail(f'unsafe expected package filename: {name!r}')
        directory, expected, payload = package_record(database.parent / name, deadline)
        if directory in expected_directories:
            fail(f'duplicate package identity: {directory}')
        expected_directories.add(directory)
        if directory not in db:
            fail(f'database package identity differs: {directory}')
        desc = fields(db[directory]['desc'], directory)
        files_desc = fields(file_db[directory]['desc'], directory + '/files-desc')
        if desc != files_desc:
            fail(f'db/files desc correspondence differs: {directory}')
        if desc != expected:
            different = sorted(key for key in desc.keys() | expected.keys()
                               if desc.get(key) != expected.get(key))
            fail(f'database fields differ from verified package: {directory}: {different!r}')
        listing = fields(file_db[directory]['files'], directory + '/files')
        if set(listing) != {'FILES'}:
            fail(f'files list field closure differs: {directory}')
        paths = listing['FILES']
        if len(paths) != len(set(paths)) or sorted(paths) != payload:
            fail(f'files payload list differs from verified package: {directory}')
    if set(db) != expected_directories:
        fail('database package closure differs')


def main() -> None:
    def timed_out(_signum, _frame):
        fail('database inspection time limit exceeded')
    signal.signal(signal.SIGALRM, timed_out)
    signal.setitimer(signal.ITIMER_REAL, metadata.MAX_INSPECTION_SECONDS)
    try:
        verify(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3:])
    except (OSError, UnicodeError, tarfile.TarError, EOFError, ValueError) as error:
        fail(f'invalid database or package stream: {error}')
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)


if __name__ == '__main__':
    main()
