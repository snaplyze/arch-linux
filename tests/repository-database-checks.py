#!/usr/bin/env python3
"""Faithful repo-add fixtures and semantic rejection tests (no production keys)."""
import base64
import gzip
import io
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


def package_metadata(path):
    decoded = subprocess.run(['zstd', '-q', '-d', '-c', '--', str(path)],
                             check=True, stdout=subprocess.PIPE).stdout
    with tarfile.open(fileobj=io.BytesIO(decoded), mode='r:') as archive:
        info = {}
        for line in archive.extractfile('.PKGINFO').read().decode().splitlines():
            if line and not line.startswith('#'):
                key, value = line.split(' = ', 1)
                info.setdefault(key, []).append(value)
        # repo-add --exclude='^.*' lists directories with a trailing slash.
        payload = sorted(m.name.rstrip('/') + ('/' if m.isdir() else '')
                         for m in archive if not m.name.startswith('.'))
    return info, payload


def create(snapshot, names):
    records = []
    mapping = {'pkgbase': 'BASE', 'pkgdesc': 'DESC', 'size': 'ISIZE', 'url': 'URL',
               'license': 'LICENSE', 'builddate': 'BUILDDATE', 'packager': 'PACKAGER',
               'replaces': 'REPLACES', 'group': 'GROUPS', 'conflict': 'CONFLICTS',
               'provides': 'PROVIDES', 'depend': 'DEPENDS', 'optdepend': 'OPTDEPENDS',
               'makedepend': 'MAKEDEPENDS', 'checkdepend': 'CHECKDEPENDS'}
    import hashlib
    for name in names:
        path = snapshot / name
        info, payload = package_metadata(path)
        fields = {'FILENAME': [name], 'NAME': info['pkgname'], 'VERSION': info['pkgver'],
                  'ARCH': info['arch'], 'CSIZE': [str(path.stat().st_size)],
                  'SHA256SUM': [hashlib.sha256(path.read_bytes()).hexdigest()],
                  'PGPSIG': [base64.b64encode(path.with_name(name + '.sig').read_bytes()).decode()]}
        fields.update({field: info[key] for key, field in mapping.items() if key in info})
        desc = ''.join('%' + field + '%\n' + '\n'.join(values) + '\n\n'
                       for field, values in fields.items()).encode()
        directory = info['pkgname'][0] + '-' + info['pkgver'][0]
        records.append((directory, desc, ('%FILES%\n' + '\n'.join(payload) + '\n').encode()))
    for name, with_files in (('arch-linux.db.tar.gz', False), ('arch-linux.files.tar.gz', True)):
        with (snapshot / name).open('wb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode='w', format=tarfile.USTAR_FORMAT) as archive:
                for directory, desc, files in records:
                    entry = tarfile.TarInfo(directory)
                    entry.type = tarfile.DIRTYPE
                    entry.mode = 0o755
                    archive.addfile(entry)
                    for suffix, data in [('desc', desc)] + ([('files', files)] if with_files else []):
                        entry = tarfile.TarInfo(directory + '/' + suffix)
                        entry.mode = 0o644
                        entry.size = len(data)
                        archive.addfile(entry, io.BytesIO(data))


def mutate(snapshot, kind, field='', operation=''):
    names = ('arch-linux.db.tar.gz', 'arch-linux.files.tar.gz') if kind == 'field' else ('arch-linux.files.tar.gz',)
    for name in names:
        path = snapshot / name
        with tarfile.open(path) as archive:
            records = [(member, archive.extractfile(member).read() if member.isfile() else None)
                       for member in archive]
        changed = False
        with tarfile.open(path, 'w:gz') as archive:
            for member, data in records:
                if not changed and member.name.endswith('/' + ('files' if kind == 'list' else 'desc')):
                    if kind == 'field':
                        pattern = rb'%' + field.encode() + rb'%\n[^\n]*\n(?:\n|$)'
                        match = re.search(pattern, data)
                        assert match, (field, member.name)
                        block = match.group()
                        replacement = (block + block if operation == 'duplicate' else
                                       b'' if operation == 'missing' else
                                       b'%' + field.encode() + b'%\nwrong\n\n')
                        data = data.replace(block, replacement, 1)
                    elif kind == 'identity':
                        data = data.replace(b'%NAME%\n', b'%NAME%\nwrong-', 1)
                    elif kind == 'list':
                        lines = data.splitlines()
                        if operation == 'missing':
                            del lines[1]
                        elif operation == 'extra':
                            lines.append(b'usr/share/unexpected')
                        elif operation == 'duplicate':
                            lines.append(lines[1])
                        elif operation == 'unsafe':
                            lines.append(b'../escape')
                        data = b'\n'.join(lines) + b'\n'
                    changed = True
                if data is not None:
                    member.size = len(data)
                archive.addfile(member, io.BytesIO(data) if data is not None else None)
        assert changed


def checks(snapshot, verifier):
    source = verifier.read_text()
    function = re.search(r'^inspect_database_archives\(\) \{.*?^\}', source, re.M | re.S).group()
    names = sorted(path.name for path in snapshot.glob('*.pkg.tar.zst'))
    def inspect(target):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\nscript_dir="$1"\n' + function +
                               '\nshift\ninspect_database_archives "$@"', 'database-check',
                               str(verifier.parent), str(target / 'arch-linux.db.tar.gz'),
                               str(target / 'arch-linux.files.tar.gz'), *names],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    positive = inspect(snapshot)
    assert positive.returncode == 0, positive.stderr
    failures = []
    cases = [('field', field, operation) for field in
             ('FILENAME', 'NAME', 'VERSION', 'ARCH', 'CSIZE', 'SHA256SUM', 'PGPSIG')
             for operation in ('wrong', 'missing', 'duplicate')]
    cases += [('identity', '', '')] + [('list', '', operation) for operation in
                                      ('missing', 'extra', 'duplicate', 'unsafe')]
    with tempfile.TemporaryDirectory(prefix='database-semantics-') as work:
        for index, (kind, field, operation) in enumerate(cases):
            target = pathlib.Path(work) / str(index)
            target.mkdir()
            for path in snapshot.iterdir():
                if path.is_file():
                    shutil.copyfile(path, target / path.name)
            mutate(target, kind, field, operation)
            result = inspect(target)
            label = ':'.join((kind, field, operation))
            if result.returncode == 0:
                failures.append(label)
            elif 'repository database check failed:' not in result.stderr:
                raise AssertionError(f'{label} wrong rejection: {result.stderr}')
    assert not failures, 'semantic negative fixtures accepted: ' + ', '.join(failures)
    print(f'repository database semantic checks passed: positive=1 negatives={len(cases)}')


if __name__ == '__main__':
    if sys.argv[1] == 'create':
        create(pathlib.Path(sys.argv[2]), sys.argv[3:])
    elif sys.argv[1] == 'mutate':
        mutate(pathlib.Path(sys.argv[2]), *sys.argv[3:])
    else:
        checks(pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]))
