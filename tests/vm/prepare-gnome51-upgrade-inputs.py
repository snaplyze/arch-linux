#!/usr/bin/env python3
"""Prepare real, signed 1.0.6 and installer-created GNOME migration inputs.

No signing authority is accepted. Recipes execute only as builder in the pinned
2 CPU / 4 GiB disposable container; host root consumes verified archive bytes.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import pathlib
import re
import shlex
import shutil
import stat
import subprocess
import tarfile
import tempfile
import time
import sys
import urllib.request
import uuid
import zipfile

MAX_PACKAGE = 512 * 1024 * 1024
RELEASE_API = 'https://api.github.com/repos/snaplyze/arch-linux/releases/tags/1.0.6'


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def run(args, **kwargs):
    if not kwargs.get('capture_output') and 'stdout' not in kwargs:
        kwargs['stdout'] = sys.stderr
    return subprocess.run(args, check=True, timeout=kwargs.pop('timeout', 120), **kwargs)


def load_pins(source_root):
    return json.loads((pathlib.Path(source_root) / 'tests/vm/gnome51-upgrade-baseline.json').read_bytes())


def source_identity(root):
    root = pathlib.Path(root).resolve(strict=True)
    if run(['git', '-C', str(root), 'status', '--porcelain', '--untracked-files=all'], capture_output=True).stdout:
        raise ValueError('migration preparation requires a clean source root')
    commit = run(['git', '-C', str(root), 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
    tree = run(['git', '-C', str(root), 'rev-parse', 'HEAD^{tree}'], capture_output=True, text=True).stdout.strip()
    if not re.fullmatch('[0-9a-f]{40}', commit) or not re.fullmatch('[0-9a-f]{40}', tree):
        raise ValueError('source identity is invalid')
    return commit, tree


def installer_call(root, expression, *args, **kwargs):
    return run(['bash', '--noprofile', '--norc', '-c',
                'set -euo pipefail; source "$1/arch-linux-installer.sh"; shift; ' + expression,
                'gnome51-inputs', str(root), *map(str, args)], **kwargs)


def check_installer_pins(root, pins):
    for row in pins['aur']:
        actual = installer_call(root, 'aur_review_metadata "$1"', row['name'], capture_output=True, text=True).stdout.split()
        expected = [row[k] for k in ('recipeCommit', 'recipeArchiveSha256', 'srcinfoSha256', 'patchedPKGBUILDSha256')]
        if actual != expected:
            raise ValueError('installer recipe pins differ: ' + row['name'])
        actual_uuid = installer_call(root, 'aur_extension_uuid "$1"', row['name'], capture_output=True, text=True).stdout
        if actual_uuid != row['uuid']:
            raise ValueError('installer UUID differs')


def file_map(directory):
    directory = pathlib.Path(directory)
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('input root is not a regular directory')
    result = {}
    for count, path in enumerate(directory.rglob('*'), start=1):
        if count > 19:
            raise ValueError('input entry count limit exceeded')
        name = path.relative_to(directory).as_posix()
        info = path.lstat()
        if stat.S_ISDIR(info.st_mode):
            if name not in {'release', 'aur', 'local'}:
                raise ValueError('unexpected input directory: ' + name)
            continue
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or not re.fullmatch('[A-Za-z0-9._+:/-]+', name):
            raise ValueError('linked, special or unsafe input: ' + name)
        if name == 'manifest.json':
            if info.st_size > 1024 * 1024:
                raise ValueError('manifest size limit exceeded')
            continue
        if info.st_size > MAX_PACKAGE:
            raise ValueError('input size limit exceeded')
        data = path.read_bytes()
        result[name] = {'size': len(data), 'sha256': digest(data)}
    return result


def verify_signature(root, payload, signature):
    trust = pathlib.Path(root) / 'repository/trust'
    signing = (trust / 'signing-subkey-fingerprint').read_text().strip()
    primary = (trust / 'primary-fingerprint').read_text().strip()
    run(['bash', '--noprofile', '--norc', '-c',
         'set -euo pipefail; source "$1/repository/lib/common.sh"; repository_verify_signature "$2" "$3" "$4" "$5" "$6"',
         'verify-input', str(root), str(trust / 'arch-linux.gpg'), str(signature), str(payload), signing, primary])


def pkginfo(archive):
    raw = run(['bsdtar', '-xOf', str(archive), '.PKGINFO'], capture_output=True).stdout
    if len(raw) > 262144:
        raise ValueError('package metadata size limit exceeded')
    entries = {}
    for line in raw.decode().splitlines():
        if line and not line.startswith('#'):
            if ' = ' not in line:
                raise ValueError('malformed package metadata')
            key, value = line.split(' = ', 1)
            entries.setdefault(key, []).append(value)
    return entries


def package_identity(archive, name, version):
    info = pkginfo(archive)
    if info.get('pkgname') != [name] or info.get('pkgver') != [version] or info.get('arch') != ['any']:
        raise ValueError('package identity differs: ' + name)
    return info


def verify_release(root, directory, pins):
    directory = pathlib.Path(directory)
    if {p.name for p in directory.iterdir()} != set(pins['release']):
        raise ValueError('legacy release closure differs')
    for name, expected in pins['release'].items():
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.stat().st_nlink != 1:
            raise ValueError('unsafe release asset')
        data = path.read_bytes()
        if {'size': len(data), 'sha256': digest(data)} != expected:
            raise ValueError('legacy release digest differs: ' + name)
    for name in ('arch-linux.gpg', 'primary-fingerprint', 'signing-subkey-fingerprint'):
        if (directory / name).read_bytes() != (pathlib.Path(root) / 'repository/trust' / name).read_bytes():
            raise ValueError('legacy public trust differs')
    archive = directory / 'arch-linux-repository-1.0.6.tar.zst'
    verify_signature(root, directory / 'RELEASE-SHA256SUMS', directory / 'RELEASE-SHA256SUMS.sig')
    verify_signature(root, archive, pathlib.Path(str(archive) + '.sig'))
    sums = (directory / 'RELEASE-SHA256SUMS').read_text().splitlines()
    for name in set(pins['release']) - {'RELEASE-SHA256SUMS', 'RELEASE-SHA256SUMS.sig'}:
        if sums.count(pins['release'][name]['sha256'] + ' *' + name) != 1:
            raise ValueError('signed sums omit legacy asset')
    if pathlib.Path(str(archive) + '.sha256').read_text() != pins['baseline']['snapshotSha256'] + ' *' + archive.name + '\n':
        raise ValueError('legacy sidecar differs')
    build_raw = (directory / 'BUILD-METADATA.json').read_bytes()
    build = json.loads(build_raw)
    if build_raw != canonical(build) or build.get('schema') != 2:
        raise ValueError('legacy build metadata is not canonical schema2')
    for key in ('sourceCommit', 'sourceTree', 'unsignedManifestSha256'):
        if build.get(key) != pins['baseline'][key]:
            raise ValueError('legacy build source binding differs')
    with tempfile.TemporaryDirectory(prefix='arch-linux-g51-release-') as temporary:
        extracted = pathlib.Path(temporary) / 'snapshot'
        run(['python3', str(pathlib.Path(root) / 'repository/safe-extract-snapshot.py'), str(archive), str(extracted)])
        repo = extracted / 'repo/x86_64'
        raw = (repo / 'repository-manifest.json').read_bytes(); manifest = json.loads(raw)
        if digest(raw) != pins['baseline']['repositoryManifestSha256'] or digest((repo / 'repository-manifest.json.sig').read_bytes()) != pins['baseline']['repositoryManifestSignatureSha256']:
            raise ValueError('original legacy manifest bytes differ')
        verify_signature(root, repo / 'repository-manifest.json', repo / 'repository-manifest.json.sig')
        if raw != canonical(manifest) or manifest.get('schema') != 2 or manifest.get('releaseVersion') != '1.0.6':
            raise ValueError('legacy repository manifest differs')
        for key in ('sourceCommit', 'sourceTree', 'installerSha256', 'packageSetSha256', 'sourceDateEpoch', 'unsignedManifestSha256'):
            if manifest.get(key) != build.get(key):
                raise ValueError('legacy manifest/build binding differs')
        if manifest.get('buildMetadataSha256') != pins['baseline']['buildMetadataSha256']:
            raise ValueError('legacy manifest/build digest differs')
        entries = {r['name']: r for r in manifest['files']}
        if len(entries) != len(manifest['files']) or set(p.name for p in repo.iterdir()) != set(entries) | {'repository-manifest.json', 'repository-manifest.json.sig'}:
            raise ValueError('legacy repository object closure differs')
        for name, row in entries.items():
            data = (repo / name).read_bytes()
            if row != {'name': name, 'size': len(data), 'sha256': digest(data)}:
                raise ValueError('legacy repository file differs')
        packages = {}
        for name in build['packages']:
            path = repo / name
            verify_signature(root, path, pathlib.Path(str(path) + '.sig'))
            info = pkginfo(path)
            if len(info.get('pkgname', [])) != 1 or len(info.get('pkgver', [])) != 1:
                raise ValueError('legacy package metadata differs')
            package_name = info['pkgname'][0]
            if package_name in packages:
                raise ValueError('duplicate baseline package')
            packages[package_name] = info['pkgver'][0]
        if packages != pins['baseline']['packages']:
            raise ValueError('legacy package versions differ')
        for name in ('arch-linux.db', 'arch-linux.db.tar.gz', 'arch-linux.files', 'arch-linux.files.tar.gz'):
            verify_signature(root, repo / name, repo / (name + '.sig'))
        for name in ('arch-linux.db', 'arch-linux.files'):
            for suffix in ('', '.sig'):
                if (repo / (name + suffix)).read_bytes() != (repo / (name + '.tar.gz' + suffix)).read_bytes():
                    raise ValueError('legacy database alias differs')


def package_filename(row):
    # makepkg omits the epoch from archive names.
    return row['name'] + '-' + row['version'].split(':')[-1] + '-any.pkg.tar.zst'


def verify_aur_package(root, path, row):
    with tempfile.TemporaryDirectory(prefix='arch-linux-g51-guard-') as temporary:
        installer_call(root, 'SCRIPT_TMP_DIR="$1"; aur_package_archive_is_safe "$2" "$3"', temporary, row['name'], path)
    info = package_identity(path, row['name'], row['version'])
    expected_dependencies = ['gnome-shell>=46.0'] if row['name'].endswith('-clipboard-indicator') else ['gnome-shell']
    if info.get('depend') != expected_dependencies:
        raise ValueError('legacy package runtime dependencies differ')
    if any(key in info for key in ('replaces', 'conflict', 'provides', 'install')):
        raise ValueError('legacy package grants unexpected metadata authority')


def check_local(path, pins):
    data = pathlib.Path(path).read_bytes()
    if digest(data) != pins['local']['sha256']:
        raise ValueError('legacy local archive differs')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or len(names) > 10000:
            raise ValueError('legacy local archive closure differs')
        for member in archive.infolist():
            pure = pathlib.PurePosixPath(member.filename)
            if pure.is_absolute() or '..' in pure.parts or '\\' in member.filename or stat.S_ISLNK(member.external_attr >> 16) or member.file_size > MAX_PACKAGE:
                raise ValueError('unsafe legacy local archive')
        metadata = json.loads(archive.read('metadata.json'))
        if metadata.get('uuid') != 'no-screenshot-box@screenshot':
            raise ValueError('legacy local UUID differs')


def verify_inputs(source_root, directory, expected_manifest_sha256):
    root = pathlib.Path(source_root).resolve(strict=True); directory = pathlib.Path(directory)
    pins = load_pins(root); check_installer_pins(root, pins)
    actual = file_map(directory)
    manifest_path = directory / 'manifest.json'
    raw = manifest_path.read_bytes()
    if not isinstance(expected_manifest_sha256, str) or not re.fullmatch('[0-9a-f]{64}', expected_manifest_sha256) or digest(raw) != expected_manifest_sha256:
        raise ValueError('input manifest differs from independently supplied preparation receipt')
    manifest = json.loads(raw)
    if raw != canonical(manifest) or set(manifest) != {'schema', 'baseline', 'sourceCommit', 'sourceTree', 'files', 'aur', 'local'} or manifest['schema'] != 1:
        raise ValueError('input manifest schema/canonical bytes differ')
    commit, tree = source_identity(root)
    if manifest['sourceCommit'] != commit or manifest['sourceTree'] != tree or manifest['baseline'] != pins['baseline']:
        raise ValueError('input source/baseline identity differs')
    expected_aur = [row | {'filename': 'aur/' + package_filename(row)} for row in pins['aur']]
    expected_local = {key: pins['local'][key] for key in ('filename', 'sha256')}
    expected_names = {'release/' + name for name in pins['release']} | {row['filename'] for row in expected_aur} | {pins['local']['filename']}
    if manifest['aur'] != expected_aur or manifest['local'] != expected_local or manifest['files'] != actual or set(actual) != expected_names:
        raise ValueError('input closure/provenance differs')
    verify_release(root, directory / 'release', pins)
    for row in expected_aur:
        verify_aur_package(root, directory / row['filename'], row)
    check_local(directory / pins['local']['filename'], pins)
    if file_map(directory) != actual or manifest_path.read_bytes() != raw or source_identity(root) != (commit, tree):
        raise ValueError('inputs/source changed during verification')
    return manifest


def download(url, maximum, expected=None, headers=None):
    request = urllib.request.Request(url, headers={'User-Agent': 'arch-linux-migration-inputs', **(headers or {})})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(maximum + 1)
    if len(data) > maximum or expected is not None and digest(data) != expected:
        raise ValueError('download size/digest differs')
    return data


def canonical_recipe(data, commit):
    """Remove codeload's prefix, preserving git archive headers and global commit.

    The result MUST match the already reviewed installer git-archive SHA256;
    this transformation confers no trust on a codeload archive by itself.
    """
    with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
        raw = stream.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024 or raw[:100].split(b'\0')[0] != b'pax_global_header' or raw[512:564] != ('52 comment=' + commit + '\n').encode():
        raise ValueError('unexpected codeload archive header')
    prefix = ('aur-' + commit + '/').encode()
    if raw[1024:1124].split(b'\0')[0] != prefix or raw[1024 + 156:1024 + 157] != b'5':
        raise ValueError('unexpected codeload root')
    result = bytearray(raw[:1024]); offset = 1536
    while offset + 512 <= len(raw) and raw[offset:offset + 512].strip(b'\0'):
        header = bytearray(raw[offset:offset + 512]); name = header[:100].split(b'\0')[0]
        if not name.startswith(prefix) or header[156:157] not in (b'0', b'5') or header[345:500].strip(b'\0'):
            raise ValueError('unsupported recipe tar object')
        name = name[len(prefix):]
        header[:100] = name + b'\0' * (100 - len(name))
        header[148:156] = b' ' * 8
        header[148:156] = ('%07o\0' % sum(header)).encode()
        size = int(header[124:136].strip(b'\0 '), 8); padded = (size + 511) // 512 * 512
        if offset + 512 + padded > len(raw):
            raise ValueError('truncated recipe archive')
        result += header + raw[offset + 512:offset + 512 + padded]
        offset += 512 + padded
    result += b'\0' * (-len(result) % 10240)
    return bytes(result)


def patch_pkgbuild(raw, row):
    text = raw.decode()
    suffix = row['name'].removeprefix('gnome-shell-extension-')
    substitutions = {'blur-my-shell': ('#tag=v$pkgver', '#commit=444df605b34529dfab7be77d0f434bf54a6dd4cc'),
                     'just-perfection-desktop': ('#tag=$pkgver.0', '#commit=ae48fd2d75a5747bbda1bdb2b039e9a3384ddf4c')}
    if suffix in substitutions:
        old, new = substitutions[suffix]
        if old not in text: raise ValueError('recipe patch context differs')
        text = text.replace(old, new)
    if suffix == 'clipboard-indicator':
        old = '  rm -f "$pkgdir/usr/share/glib-2.0/schemas/gschemas.compiled"\n'
        if text.count(old) != 1: raise ValueError('recipe patch context differs')
        text = text.replace(old, '  rm -f "$pkgdir/usr/share/gnome-shell/extensions/$_uuid/locale/fr_FR/LC_MESSAGES/clipboard-indicator.po~"\n' + old)
    result = (text + '\noptions+=(!debug)\n').encode()
    if digest(result) != row['patchedPKGBUILDSha256']:
        raise ValueError('patched recipe hash differs')
    return result


def prepare_recipes(root, directory, pins):
    for row in pins['aur']:
        commit = row['recipeCommit']
        data = canonical_recipe(download('https://codeload.github.com/archlinux/aur/tar.gz/' + commit, 4 * 1024 * 1024), commit)
        if digest(data) != row['recipeArchiveSha256']:
            raise ValueError('canonical recipe archive hash differs')
        target = directory / row['name']; target.mkdir()
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:') as archive:
            for member in archive:
                pure = pathlib.PurePosixPath(member.name)
                if pure.is_absolute() or '..' in pure.parts or not re.fullmatch('[A-Za-z0-9._+/-]+', member.name):
                    raise ValueError('unsafe recipe path')
                path = target / pure
                if member.isdir(): path.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(archive.extractfile(member).read()); path.chmod(0o755 if member.mode & 0o111 else 0o644)
                else: raise ValueError('unsupported recipe object')
        srcinfo = target / '.SRCINFO'
        if digest(srcinfo.read_bytes()) != row['srcinfoSha256']:
            raise ValueError('recipe SRCINFO hash differs')
        installer_call(root, 'srcinfo="$(cat -- "$2")"; aur_srcinfo_identity_matches "$1" "$srcinfo"; test "$(aur_srcinfo_dependencies "$1" <<<"$srcinfo")" = "$(aur_reviewed_dependencies "$1")"', row['name'], srcinfo)
        fields = {}
        for line in srcinfo.read_text().splitlines():
            if ' = ' in line:
                key, value = line.strip().split(' = ', 1); fields.setdefault(key, []).append(value)
        version = (fields.get('epoch', [''])[0] + ':' if 'epoch' in fields else '') + fields['pkgver'][0] + '-' + fields['pkgrel'][0]
        if version != row['version']: raise ValueError('recipe version differs')
        path = target / 'PKGBUILD'; path.write_bytes(patch_pkgbuild(path.read_bytes(), row))


def container_command(root, recipes, name):
    return ['docker', 'run', '--detach', '--pull=never', '--name', name, '--cpus=2', '--memory=4g', '--memory-swap=4g', '--pids-limit=256',
            '--security-opt', 'no-new-privileges', '--label', 'arch-linux.gnome51-input=' + name,
            '--mount', f'type=bind,source={recipes},target=/recipes,readonly', '--tmpfs', '/work:rw,nosuid,nodev,size=2g',
            load_pins(root)['container'], 'sleep', '1800']


def builder_script(pins):
    names = [row['name'] for row in pins['aur']]
    # This fixed allowlist is deliberately independent of executing recipe code.
    script = '''set -euo pipefail
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm --needed archlinux-keyring
pacman -Syu --noconfirm --needed git jq gettext sassc gnome-shell
useradd --create-home --home-dir /work/home --shell /bin/bash builder
install -d -o builder -g builder -m 0755 /out /work/build
'''
    for name in names:
        script += f'cp -a /recipes/{name} /work/build/{name}\nchown -R builder:builder /work/build/{name}\n'
        script += 'runuser -u builder -- env -i HOME=/work/home PATH=/usr/bin LANG=C LC_ALL=C XDG_CACHE_HOME=/work/build/cache bash --noprofile --norc -c ' + shlex.quote('set -euo pipefail; test "$(id -u)" -ne 0; cd /work/build/' + name + '; makepkg --printsrcinfo > /out/' + name + '.srcinfo; makepkg --nodeps --noconfirm; cp -- ' + package_filename(next(r for r in pins['aur'] if r['name'] == name)) + ' /out/') + '\n'
    script += 'pkill -KILL -u builder || test "$?" -eq 1\nif pgrep -u builder >/dev/null; then exit 1; fi\n'
    return script


def build_aur(root, recipes, output, pins):
    name = 'arch-linux-g51-input-' + uuid.uuid4().hex[:16]
    try:
        run(container_command(root, recipes, name), capture_output=True)
        run(['docker', 'exec', '-i', name, 'bash', '--noprofile', '--norc'], input=builder_script(pins).encode(), stdout=sys.stderr, timeout=1200)
        for row in pins['aur']:
            filename = package_filename(row)
            generated = run(['docker', 'exec', name, 'cat', '--', '/out/' + row['name'] + '.srcinfo'], capture_output=True).stdout
            if len(generated) > 262144:
                raise ValueError('generated recipe metadata size limit exceeded')
            metadata = recipes / (row['name'] + '.generated-srcinfo')
            metadata.write_bytes(generated)
            installer_call(root, 'srcinfo="$(cat -- "$2")"; aur_srcinfo_identity_matches "$1" "$srcinfo"; test "$(aur_srcinfo_dependencies "$1" <<<"$srcinfo")" = "$(aur_reviewed_dependencies "$1")"', row['name'], metadata)
            size = int(run(['docker', 'exec', name, 'stat', '-c', '%s', '--', '/out/' + filename], capture_output=True, text=True).stdout)
            if not 0 < size <= MAX_PACKAGE: raise ValueError('builder output size differs')
            path = output / filename
            with path.open('xb') as stream:
                run(['docker', 'exec', name, 'head', '-c', str(MAX_PACKAGE + 1), '--', '/out/' + filename], stdout=stream)
            if path.stat().st_size != size: raise ValueError('builder output copy differs')
            verify_aur_package(root, path, row)
    finally:
        failed = sys.exc_info()[0] is not None
        try:
            cleanup_container(name)
        except BaseException as error:
            if not failed:
                raise
            print(f'GNOME51 owned container cleanup failed: {name}: {error}', file=sys.stderr)


def cleanup_container(name):
    # A unique per-invocation label binds cleanup even if docker run timed out
    # after the daemon created the container but before the client returned.
    for attempt in range(3):
        result = subprocess.run(['docker', 'inspect', '--format', '{{ index .Config.Labels "arch-linux.gnome51-input" }}', name], capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            if result.stdout.strip() != name:
                raise ValueError('refusing cleanup of a container without this invocation ownership label')
            run(['docker', 'rm', '--force', name], capture_output=True, timeout=30)
            return
        if 'No such object' not in result.stderr and 'No such container' not in result.stderr:
            raise ValueError('cannot establish owned container cleanup state')
        if attempt < 2:
            time.sleep(0.2)


def prepare(root, output):
    root = pathlib.Path(root).resolve(strict=True); output = pathlib.Path(output).absolute()
    commit, tree = source_identity(root)
    pins = load_pins(root); check_installer_pins(root, pins)
    if output.exists() or output.is_symlink(): raise ValueError('output must be absent')
    output.mkdir(mode=0o700)
    try:
        for sub in ('release', 'aur', 'local'): (output / sub).mkdir()
        assets = json.loads(download(RELEASE_API, 2 * 1024 * 1024))
        by_name = {row['name']: row for row in assets['assets']}
        for name, expected in pins['release'].items():
            row = by_name[name]
            if row['size'] != expected['size'] or row['url'] != 'https://api.github.com/repos/snaplyze/arch-linux/releases/assets/' + str(row['id']):
                raise ValueError('release API asset identity differs')
            (output / 'release' / name).write_bytes(download(row['url'], expected['size'], expected['sha256'], {'Accept': 'application/octet-stream'}))
        verify_release(root, output / 'release', pins)
        local = output / pins['local']['filename']
        local.write_bytes(download(pins['local']['url'], 16 * 1024 * 1024, pins['local']['sha256'])); check_local(local, pins)
        with tempfile.TemporaryDirectory(prefix='arch-linux-g51-recipes-') as temporary:
            recipes = pathlib.Path(temporary)
            prepare_recipes(root, recipes, pins)
            build_aur(root, recipes, output / 'aur', pins)
        if source_identity(root) != (commit, tree): raise ValueError('source changed during preparation')
        value = {'schema': 1, 'baseline': pins['baseline'], 'sourceCommit': commit, 'sourceTree': tree,
                 'files': file_map(output), 'aur': [row | {'filename': 'aur/' + package_filename(row)} for row in pins['aur']],
                 'local': {key: pins['local'][key] for key in ('filename', 'sha256')}}
        (output / 'manifest.json').write_bytes(canonical(value))
        verify_inputs(root, output, digest(canonical(value)))
        return value
    except BaseException:
        # Only this newly created bounded output is owned by this invocation.
        shutil.rmtree(output)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', required=True, type=pathlib.Path)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    args = parser.parse_args()
    try:
        value = prepare(args.source_root, args.output)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'GNOME51 migration inputs: {error}\n')
    # The sole stdout receipt is transported separately from the input directory.
    print(digest(canonical(value)))


if __name__ == '__main__':
    main()
