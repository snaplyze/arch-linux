#!/usr/bin/env python3
"""Exercise legacy extension migration using disposable user/system trees."""
import hashlib
from contextlib import redirect_stderr
import importlib.machinery
import importlib.util
import json
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parents[1]
HELPER = REPO_ROOT / 'packages/arch-linux-gnome-extensions/extension-session'
UUID = 'no-screenshot-box@screenshot'


def load_helper():
    loader = importlib.machinery.SourceFileLoader('extension_session', str(HELPER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class MigrationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='marble-extension-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = self.root / 'custom-data'
        self.local = self.data / 'gnome-shell/extensions' / UUID
        self.system = self.root / 'system'
        self.global_copy = self.system / UUID
        for directory in (self.local, self.global_copy):
            (directory / 'schemas').mkdir(parents=True)
        self.legacy = self.root / 'legacy.sha256'
        self.manifest = self.root / 'extensions.sha256'
        self.old = {'metadata.json': json.dumps({'uuid': UUID, 'version': 6,
                    'shell-version': ['45', '46', '47', '48', '49', '50']}).encode(),
                    'extension.js': b'legacy extension\n', 'schemas/gschemas.compiled': b'compiled\0'}
        self.new = dict(self.old, **{'metadata.json': json.dumps({'uuid': UUID,
                    'version': 6, 'shell-version': ['51']}).encode(),
                    'extension.js': b'reviewed system port\n'})
        for path, files in ((self.local, self.old), (self.global_copy, self.new)):
            for name, content in files.items():
                (path / name).write_bytes(content)
        self.write_manifest(self.legacy, self.old)
        self.write_manifest(self.manifest, self.new, UUID + '/')
        self.helper = load_helper()

    def write_manifest(self, path, files, prefix=''):
        path.write_text(''.join(hashlib.sha256(content).hexdigest() + '  ' + prefix + name + '\n'
                                for name, content in sorted(files.items())))

    def run_migration(self):
        return self.helper.migrate(self.data, self.system, self.legacy, self.manifest,
                                   uid=os.getuid(), system_uid=os.getuid())

    def test_exact_legacy_retired_as_original_tree_and_idempotent(self):
        original_inode = self.local.stat().st_ino
        self.assertEqual(self.run_migration()[0], 'migrated')
        self.assertFalse(self.local.exists())
        self.assertEqual((self.global_copy / 'extension.js').read_bytes(), self.new['extension.js'])
        retained = list(self.local.parent.parent.glob('.arch-linux-marble-custody-*'))
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0].stat().st_mode & 0o777, 0o700)
        self.assertEqual((retained[0] / UUID).stat().st_ino, original_inode)
        for name, content in self.old.items():
            self.assertEqual((retained[0] / UUID / name).read_bytes(), content)
        self.assertEqual(self.run_migration()[0], 'system')
        self.assertEqual(list(self.local.parent.parent.glob('.arch-linux-marble-custody-*')), retained)
        self.assertFalse(list(self.local.parent.glob('.arch-linux-marble-custody-*')))

    def test_absent_system_after_retirement_leaves_retained_original(self):
        self.assertEqual(self.run_migration()[0], 'migrated')
        retained = next(self.local.parent.parent.glob('.arch-linux-marble-custody-*'))
        (self.global_copy / 'extension.js').unlink()
        self.assertEqual(self.run_migration()[0], 'system')
        self.assertFalse(self.local.exists())
        for name, content in self.old.items():
            self.assertEqual((retained / UUID / name).read_bytes(), content)

    def test_held_descriptor_edit_after_final_read_retained_outside_extensions(self):
        held = os.open(self.local / 'extension.js', os.O_RDWR)
        self.addCleanup(os.close, held)
        unlink = os.unlink
        changed = False
        def concurrent_edit(name, *args, **kwargs):
            nonlocal changed
            if name == 'extension.js' and not self.local.exists() and not changed:
                # Write after the helper has captured the final bytes/identity.
                os.pwrite(held, b'concurrent customization', 0)
                os.ftruncate(held, len(b'concurrent customization'))
                changed = True
            return unlink(name, *args, **kwargs)
        with patch.object(self.helper.os, 'unlink', side_effect=concurrent_edit):
            status, message = self.run_migration()
        if not changed:
            # The fixed helper has no unlink boundary; exercise the held FD later.
            os.pwrite(held, b'concurrent customization', 0)
            os.ftruncate(held, len(b'concurrent customization'))
        self.assertEqual(status, 'migrated')
        retained = list(self.local.parent.parent.glob('.arch-linux-marble-custody-*'))
        self.assertEqual(len(retained), 1, 'original extension tree must retain a pathname outside extension discovery')
        leaf = retained[0] / UUID / 'extension.js'
        self.assertEqual(leaf.read_bytes(), b'concurrent customization')
        self.assertEqual(leaf.stat().st_ino, os.fstat(held).st_ino)
        os.pwrite(held, b'later update', 0)
        os.ftruncate(held, len(b'later update'))
        self.assertEqual(leaf.read_bytes(), b'later update')
        self.assertIn(str(retained[0]), message)
        self.assertFalse(list(self.local.parent.glob('.arch-linux-marble-custody-*')))

    def test_modified_copy_preserved(self):
        (self.local / 'extension.js').write_bytes(b'user edit')
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertEqual((self.local / 'extension.js').read_bytes(), b'user edit')

    def test_newer_local_version_preserved(self):
        metadata = json.loads(self.old['metadata.json'])
        metadata['version'] = 7
        content = json.dumps(metadata).encode()
        (self.local / 'metadata.json').write_bytes(content)
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertEqual((self.local / 'metadata.json').read_bytes(), content)

    def test_foreign_owned_tree_preserved(self):
        status, _ = self.helper.migrate(self.data, self.system, self.legacy, self.manifest,
                                        uid=os.getuid() + 1, system_uid=os.getuid())
        self.assertEqual(status, 'shadowed')
        self.assertTrue(self.local.exists())

    def test_extra_file_or_empty_directory_preserved(self):
        for kind in ('file', 'directory'):
            with self.subTest(kind=kind):
                extra = self.local / 'foreign'
                extra.write_text('user data') if kind == 'file' else extra.mkdir()
                self.assertEqual(self.run_migration()[0], 'shadowed')
                self.assertTrue(extra.exists())
                extra.unlink() if kind == 'file' else extra.rmdir()

    def test_symlink_file_and_directory_preserved(self):
        file = self.local / 'extension.js'
        file.unlink()
        file.symlink_to(self.global_copy / 'extension.js')
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(file.is_symlink())
        file.unlink()
        file.write_bytes(self.old['extension.js'])
        directory = self.local / 'schemas'
        (directory / 'gschemas.compiled').unlink()
        directory.rmdir()
        directory.symlink_to(self.global_copy / 'schemas', target_is_directory=True)
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(directory.is_symlink())

    def test_missing_or_unsupported_system_preserves_local(self):
        metadata = self.global_copy / 'metadata.json'
        metadata.unlink()
        self.assertEqual(self.run_migration()[0], 'shadowed')
        for value in ({'uuid': UUID, 'shell-version': ['50']},
                      {'uuid': 'foreign', 'shell-version': ['51']}):
            self.new['metadata.json'] = json.dumps(value).encode()
            metadata.write_bytes(self.new['metadata.json'])
            self.write_manifest(self.manifest, self.new, UUID + '/')
            self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(self.local.exists())

    def test_global_hash_mismatch_preserves_local(self):
        (self.global_copy / 'extension.js').write_bytes(b'unreviewed system bytes')
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(self.local.exists())

    def test_malformed_metadata_preserved(self):
        for metadata in ([], {'uuid': UUID, 'shell-version': '151'},
                         {'uuid': UUID, 'shell-version': None}):
            with self.subTest(metadata=metadata):
                self.new['metadata.json'] = json.dumps(metadata).encode()
                (self.global_copy / 'metadata.json').write_bytes(self.new['metadata.json'])
                self.write_manifest(self.manifest, self.new, UUID + '/')
                self.assertEqual(self.run_migration()[0], 'shadowed')
                self.assertTrue(self.local.exists())

    def test_special_file_preserved(self):
        fifo = self.local / 'foreign-fifo'
        os.mkfifo(fifo)
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(fifo.exists())

    def test_hardlinked_leaf_preserved(self):
        os.link(self.local / 'extension.js', self.root / 'outside-hardlink')
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertEqual((self.root / 'outside-hardlink').read_bytes(), self.old['extension.js'])

    def test_writable_leaf_preserved(self):
        (self.local / 'extension.js').chmod(0o666)
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(self.local.exists())

    def test_symlink_local_root_preserved(self):
        other = self.local.with_name('foreign')
        self.local.rename(other)
        self.local.symlink_to(other, target_is_directory=True)
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(self.local.is_symlink())
        self.assertEqual((other / 'extension.js').read_bytes(), self.old['extension.js'])

    def test_symlink_parent_preserved(self):
        parent = self.local.parent
        other = parent.with_name('foreign-extensions')
        parent.rename(other)
        parent.symlink_to(other, target_is_directory=True)
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(self.local.exists())

    def test_system_symlink_and_manifest_symlink_preserved(self):
        original_manifest = self.manifest.with_suffix('.original')
        self.manifest.rename(original_manifest)
        self.manifest.symlink_to(original_manifest)
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.manifest.unlink()
        original_manifest.rename(self.manifest)
        (self.global_copy / 'extension.js').unlink()
        (self.global_copy / 'extension.js').symlink_to(self.local / 'extension.js')
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(self.local.exists())

    def test_duplicate_manifest_preserved(self):
        with self.legacy.open('a') as stream:
            stream.write(self.legacy.read_text().splitlines()[0] + '\n')
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(self.local.exists())

    def test_foreign_global_uuid_allowed_but_unsafe_manifest_rejected(self):
        with self.manifest.open('a') as stream:
            stream.write('0' * 64 + '  other@example/extension.js\n')
        self.assertEqual(self.run_migration()[0], 'migrated')

    def test_manifest_traversal_rejected(self):
        with self.manifest.open('a') as stream:
            stream.write('0' * 64 + '  other@example/../extension.js\n')
        self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(self.local.exists())

    def test_change_after_rename_restored(self):
        rename = os.rename
        def concurrent_change(src, dst, **kwargs):
            rename(src, dst, **kwargs)
            custody = next(self.local.parent.parent.glob('.arch-linux-marble-custody-*'))
            (custody / UUID / 'extension.js').write_bytes(b'concurrent edit')
        with patch.object(self.helper.os, 'rename', side_effect=concurrent_change):
            self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertEqual((self.local / 'extension.js').read_bytes(), b'concurrent edit')
        self.assertFalse(list(self.local.parent.parent.glob('.arch-linux-marble-custody-*')))

    def test_recreated_destination_and_changed_custody_both_preserved(self):
        rename = os.rename
        def concurrent_change(src, dst, **kwargs):
            rename(src, dst, **kwargs)
            self.local.mkdir()
            (self.local / 'extension.js').write_bytes(b'recreated destination')
            custody = next(self.local.parent.parent.glob('.arch-linux-marble-custody-*'))
            (custody / UUID / 'extension.js').write_bytes(b'concurrent edit')
        with patch.object(self.helper.os, 'rename', side_effect=concurrent_change):
            status, message = self.run_migration()
        self.assertEqual(status, 'shadowed')
        self.assertEqual((self.local / 'extension.js').read_bytes(), b'recreated destination')
        custody = next(self.local.parent.parent.glob('.arch-linux-marble-custody-*'))
        self.assertEqual((custody / UUID / 'extension.js').read_bytes(), b'concurrent edit')
        self.assertIn(str(custody), message)

    def test_system_change_after_rename_restores_local(self):
        rename = os.rename
        def concurrent_change(src, dst, **kwargs):
            rename(src, dst, **kwargs)
            (self.global_copy / 'extension.js').write_bytes(b'concurrent system update')
        with patch.object(self.helper.os, 'rename', side_effect=concurrent_change):
            self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertEqual((self.local / 'extension.js').read_bytes(), self.old['extension.js'])

    def test_recreated_destination_preserves_both_even_if_custody_unchanged(self):
        rename = os.rename
        def concurrent_change(src, dst, **kwargs):
            rename(src, dst, **kwargs)
            self.local.mkdir()
            (self.local / 'user-new').write_bytes(b'new copy')
        with patch.object(self.helper.os, 'rename', side_effect=concurrent_change):
            self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertEqual((self.local / 'user-new').read_bytes(), b'new copy')
        custody = next(self.local.parent.parent.glob('.arch-linux-marble-custody-*'))
        self.assertEqual((custody / UUID / 'extension.js').read_bytes(), self.old['extension.js'])

    def test_concurrent_helper_lock_preserves_local(self):
        import fcntl
        lock_path = self.local.parent / '.arch-linux-marble-extensions.lock'
        with lock_path.open('w') as lock:
            lock_path.chmod(0o600)
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.run_migration()[0], 'shadowed')
        self.assertTrue(self.local.exists())

    def test_xdg_data_home_used(self):
        with patch.dict(os.environ, {'XDG_DATA_HOME': str(self.data)}):
            self.assertEqual(self.helper.data_home(), self.data)

    def test_root_entry_refuses_without_filesystem_access(self):
        with patch.object(self.helper.os, 'geteuid', return_value=0), redirect_stderr(io.StringIO()):
            self.assertNotEqual(self.helper.main(), 0)
        self.assertTrue(self.local.exists())


if __name__ == '__main__':
    unittest.main()
