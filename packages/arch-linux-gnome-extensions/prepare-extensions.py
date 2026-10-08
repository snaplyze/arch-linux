#!/usr/bin/env python3
"""Prepare hash-pinned GNOME payloads without running upstream build scripts."""
from __future__ import annotations
import argparse
import hashlib
import gzip
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent
MAX_COMPRESSED = 8 * 1024 * 1024
MAX_ENTRIES = 1024
MAX_TOTAL = 32 * 1024 * 1024
MAX_FILE = 4 * 1024 * 1024


def regular_bytes(path: Path) -> bytes:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_COMPRESSED:
            raise ValueError('input must be a bounded regular archive')
        raw = source.read(MAX_COMPRESSED + 1)
        if len(raw) != info.st_size:
            raise ValueError('archive size changed or exceeds compressed limit')
        return raw


def read_archive(path: Path, kind: str, prefix: str) -> dict[str, bytes]:
    raw = regular_bytes(path)
    files, seen, total, count = {}, set(), 0, 0

    def add(name, is_dir, size, read):
        nonlocal total, count
        count += 1
        name = name[:-1] if name.endswith('/') else name
        if (count > MAX_ENTRIES or not name or name.startswith('/') or '\\' in name or
                any(part in ('', '.', '..') for part in name.split('/')) or
                any(ord(char) < 32 or ord(char) == 127 for char in name) or name in seen):
            raise ValueError('unsafe, duplicate or excessive archive member')
        seen.add(name)
        if size < 0 or size > MAX_FILE or (is_dir and size):
            raise ValueError('archive member exceeds regular file limit')
        total += size
        if total > MAX_TOTAL:
            raise ValueError('archive exceeds expanded size limit')
        if prefix:
            if name == prefix and is_dir:
                return
            if not name.startswith(prefix + '/'):
                raise ValueError('archive member outside pinned prefix')
            name = name[len(prefix) + 1:]
        if not is_dir:
            payload = read(size + 1)
            if len(payload) != size:
                raise ValueError('archive member length differs')
            files[name] = payload

    try:
        if kind == 'zip':
            if prefix:
                raise ValueError('ZIP payload must use its root')
            with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                if len(archive.infolist()) > MAX_ENTRIES:
                    raise ValueError('archive exceeds member limit')
                for member in archive.infolist():
                    mode = stat.S_IFMT(member.external_attr >> 16)
                    if mode not in (0, stat.S_IFREG, stat.S_IFDIR) or member.flag_bits & 1:
                        raise ValueError('archive links, special files and encryption are forbidden')
                    with archive.open(member) as source:
                        add(member.orig_filename, member.is_dir(), member.file_size, source.read)
        elif kind == 'tar.gz':
            if not prefix or '/' in prefix or prefix in ('.', '..'):
                raise ValueError('tar payload requires a pinned root directory')
            with gzip.GzipFile(fileobj=io.BytesIO(raw)) as compressed:
                expanded = compressed.read(MAX_TOTAL + 1)
            if len(expanded) > MAX_TOTAL:
                raise ValueError('tar stream exceeds expanded size limit')
            with tarfile.open(fileobj=io.BytesIO(expanded), mode='r:') as archive:
                for member in archive:
                    if not (member.isdir() or member.isreg()):
                        raise ValueError('archive links and special files are forbidden')
                    if member.isdir():
                        add(member.name, True, member.size, lambda _: b'')
                    else:
                        with archive.extractfile(member) as source:
                            add(member.name, False, member.size, source.read)
        else:
            raise ValueError('unsupported archive format')
    except (zipfile.BadZipFile, tarfile.TarError, EOFError, RuntimeError) as error:
        raise ValueError('malformed archive') from error
    for name in files:
        if any(str(parent) in files for parent in PurePosixPath(name).parents if str(parent) != '.'):
            raise ValueError('archive file is also a directory ancestor')
    return files


def source_payload(input_dir: Path, row: dict) -> dict[str, bytes]:
    name = row['archive']
    if not re.fullmatch(r'[a-z0-9-]+\.(zip|tar\.gz)', name):
        raise ValueError('invalid archive alias')
    raw = regular_bytes(input_dir / name)
    if hashlib.sha256(raw).hexdigest() != row['sha256']:
        raise ValueError('archive hash differs from reviewed source')
    # Parse the same accepted bytes, not a second pathname lookup.
    with tempfile.TemporaryDirectory(prefix='marble-extension-input-') as temporary:
        frozen = Path(temporary) / name
        frozen.write_bytes(raw)
        files = read_archive(frozen, row['format'], row['prefix'])
    try:
        metadata = json.loads(files['metadata.json'])
    except (KeyError, ValueError, UnicodeError) as error:
        raise ValueError('extension metadata is missing or malformed') from error
    majors = metadata.get('shell-version') if isinstance(metadata, dict) else None
    required = {'50'} if row.get('project_port') else {'50', '51'}
    if (not isinstance(metadata, dict) or metadata.get('uuid') != row['uuid'] or
            not isinstance(majors, list) or not all(isinstance(major, str) for major in majors) or
            not required <= set(majors) or
            (row.get('version') is not None and metadata.get('version') != row['version']) or
            'extension.js' not in files or row['license_file'] not in files):
        raise ValueError('extension UUID, major versions, version or license differs')
    if row.get('project_port'):
        if row['uuid'] != 'no-screenshot-box@screenshot' or metadata.get('version') != 6:
            raise ValueError('unreviewed metadata port')
        metadata['shell-version'] = list(dict.fromkeys(majors + ['51']))
        metadata['version-name'] = '6-arch-linux-gnome51-port'
        files['metadata.json'] = (json.dumps(metadata, sort_keys=True, indent=2) + '\n').encode()
    if row['format'] == 'tar.gz':
        files = {name: data for name, data in files.items() if (
            ('/' not in name and (name.endswith('.js') or name in ('metadata.json', 'stylesheet.css', row['license_file'], 'README.md', 'README.rst'))) or
            re.fullmatch(r'schemas/[^/]+\.xml', name) or
            re.fullmatch(r'locale/[^/]+/LC_MESSAGES/[^/]+\.(po|mo)', name))}
    return {name: data for name, data in files.items()
            if name != 'schemas/gschemas.compiled' and not name.endswith(('~', '.bak'))}


def materialize(output: Path, files: dict[str, bytes]) -> None:
    output.mkdir(mode=0o755)
    with tempfile.TemporaryDirectory(prefix='marble-extension-locales-') as temporary:
        for name, data in sorted(files.items()):
            if name.endswith('.po'):
                continue
            target = output / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            target.chmod(0o644)
        for name, data in sorted(files.items()):
            if not name.endswith('.po'):
                continue
            source = Path(temporary) / 'translation.po'
            source.write_bytes(data)
            target = output / (name[:-3] + '.mo')
            target.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['msgfmt', str(source), '-o', str(target)], check=True, timeout=30)
            target.chmod(0o644)
    schemas = output / 'schemas'
    if schemas.is_dir():
        subprocess.run(['glib-compile-schemas', '--strict', str(schemas)], check=True, timeout=30)
        (schemas / 'gschemas.compiled').chmod(0o644)


def inventory(output: Path) -> str:
    return ''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(output).as_posix()}\n'
                   for path in sorted(output.rglob('*')) if path.is_file())


def prepare(input_dir: Path, output: Path) -> None:
    manifest = json.loads((ROOT / 'extension-sources.json').read_text())
    rows = manifest['extensions']
    if manifest.get('schema') != 1 or len(rows) != 5 or len({row['uuid'] for row in rows}) != 5:
        raise ValueError('reviewed extension closure is malformed')
    for row in rows:
        if not re.fullmatch(r'[a-zA-Z0-9@._-]+', row['uuid']) or row['uuid'] in ('.', '..'):
            raise ValueError('unsafe extension UUID')
    if output.exists() or output.is_symlink():
        raise FileExistsError('output directory must not exist')
    payloads = [(row['uuid'], source_payload(input_dir, row)) for row in rows]
    output.mkdir(mode=0o755)
    for uuid, files in payloads:
        materialize(output / uuid, files)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    try:
        prepare(args.input_dir, args.output_dir)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'extension preparation failed: {error}\n')

if __name__ == '__main__':
    main()
