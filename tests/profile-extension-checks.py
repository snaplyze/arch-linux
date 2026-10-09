#!/usr/bin/env python3
"""Check bounded extension preparation, without executing extension code."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
PROFILE = ROOT / 'packages/arch-linux-gnome-extensions'
INPUTS = None

class ExtensionChecks(unittest.TestCase):
    def setUp(self):
        helper = PROFILE / 'prepare-extensions.py'
        self.assertTrue(helper.is_file(), 'bounded extension preparer is missing')
        spec = importlib.util.spec_from_file_location('prepare_extensions', helper)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temporary = tempfile.TemporaryDirectory(prefix='profile-extension-check-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def zip(self, entries):
        path = self.root / 'fixture.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            for name, data in entries:
                archive.writestr(name, data)
        return path

    def test_regular_archive_reads_only_bounded_safe_members(self):
        path = self.zip([('schemas/', b''), ('extension.js', b'export default class {}')])
        self.assertEqual(self.module.read_archive(path, 'zip', ''), {'extension.js': b'export default class {}'})

    def test_traversal_duplicates_and_links_are_refused(self):
        for name in ('../escape', '/absolute', 'a/../escape', 'a//b', 'a\\b'):
            with self.subTest(name=name):
                path = self.zip([(name, b'bad')])
                with self.assertRaises(ValueError): self.module.read_archive(path, 'zip', '')
        path = self.zip([('same', b'one'), ('same', b'two')])
        with self.assertRaises(ValueError): self.module.read_archive(path, 'zip', '')
        entry = zipfile.ZipInfo('link')
        entry.create_system = 3
        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
        path = self.zip([(entry, b'outside')])
        with self.assertRaises(ValueError): self.module.read_archive(path, 'zip', '')
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE):
            path = self.root / 'fixture.tar.gz'
            with tarfile.open(path, 'w:gz') as archive:
                member = tarfile.TarInfo('root/link')
                member.type, member.linkname = kind, '../outside'
                archive.addfile(member)
            with self.assertRaises(ValueError): self.module.read_archive(path, 'tar.gz', 'root')

    def test_archive_limits_and_prefix_are_refused(self):
        path = self.zip([('one', b'123'), ('two', b'456')])
        for key, limit in (('MAX_ENTRIES', 1), ('MAX_FILE', 2), ('MAX_TOTAL', 5), ('MAX_COMPRESSED', 1)):
            with self.subTest(limit=key), patch.object(self.module, key, limit):
                with self.assertRaises(ValueError): self.module.read_archive(path, 'zip', '')
        path = self.root / 'fixture.tar.gz'
        with tarfile.open(path, 'w:gz') as archive:
            member = tarfile.TarInfo('foreign/file'); member.size = 1
            archive.addfile(member, io.BytesIO(b'x'))
        with self.assertRaises(ValueError): self.module.read_archive(path, 'tar.gz', 'expected')

    def test_hash_uuid_and_shell_metadata_are_bound(self):
        row = {'archive': 'fixture.zip', 'format': 'zip', 'prefix': '', 'uuid': 'fixture@example.invalid',
               'sha256': '0' * 64, 'license_file': 'LICENSE', 'version': 1, 'project_port': False}
        metadata = {'uuid': row['uuid'], 'shell-version': ['50', '51'], 'version': 1}
        path = self.zip([('metadata.json', json.dumps(metadata)), ('extension.js', b'code'), ('LICENSE', b'grant')])
        with self.assertRaises(ValueError): self.module.source_payload(self.root, row)
        row['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.assertIn('extension.js', self.module.source_payload(self.root, row))
        for change in ({'uuid': 'foreign'}, {'shell-version': ['50']}, {'shell-version': ['51']}, {'version': 2}):
            with self.subTest(change=change):
                payload = dict(metadata, **change)
                path = self.zip([('metadata.json', json.dumps(payload)), ('extension.js', b'code'), ('LICENSE', b'grant')])
                row['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
                with self.assertRaises(ValueError): self.module.source_payload(self.root, row)

    def test_pinned_five_payloads_match_committed_inventory(self):
        if INPUTS is None: self.skipTest('provide --input-dir for pinned upstream payload acceptance')
        output = self.root / 'prepared'
        self.module.prepare(Path(INPUTS), output)
        expected = (PROFILE / 'extensions.sha256').read_text()
        self.assertEqual(self.module.inventory(output), expected)
        self.assertEqual(len(list(output.iterdir())), 5)
        self.assertFalse(any(path.suffix in {'.po', '.zip', '.gz'} for path in output.rglob('*')))
        for path in output.glob('*/metadata.json'):
            self.assertTrue({'50', '51'} <= set(json.loads(path.read_text())['shell-version']))
        ns = json.loads((output / 'no-screenshot-box@screenshot/metadata.json').read_text())
        self.assertEqual(ns['version'], 6)
        self.assertEqual(ns['version-name'], '6-arch-linux-gnome51-port')
        second = self.root / 'repeat'
        self.module.prepare(Path(INPUTS), second)
        self.assertEqual(self.module.inventory(second), expected)
        with self.assertRaises(FileExistsError): self.module.prepare(Path(INPUTS), output)

    def test_makepkg_symlink_inputs_prepare_as_regular_verified_archives(self):
        if INPUTS is None: self.skipTest('provide --input-dir for makepkg source integration')
        srcdir = self.root / 'src'
        srcdir.mkdir()
        for path in PROFILE.iterdir():
            if path.is_file(): (srcdir / path.name).symlink_to(path)
        for path in Path(INPUTS).iterdir():
            if path.is_file(): (srcdir / path.name).symlink_to(path.resolve())
        subprocess.run(['bash', '-c', 'set -euo pipefail; source "$1"; srcdir="$2"; prepare',
                        'prepare-check', str(PROFILE / 'PKGBUILD'), str(srcdir)], check=True)
        self.assertEqual(self.module.inventory(srcdir / 'extensions'),
                         (PROFILE / 'extensions.sha256').read_text())
        self.assertTrue(all(not p.is_symlink() for p in (srcdir / 'extension-inputs').iterdir()))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input-dir')
    args, remaining = parser.parse_known_args()
    INPUTS = args.input_dir
    unittest.main(argv=[sys.argv[0], *remaining])
