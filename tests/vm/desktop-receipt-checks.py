#!/usr/bin/env python3
"""Offline positive/negative custody fixtures; never access a host session bus."""
import copy
import contextlib
import hashlib
import io
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('desktop_receipt', ROOT / 'guest/desktop-receipt.py')
receipt = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(receipt)
RUN = 'marble-20261010T123456Z-1234abcd'


class ReceiptChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='arch-linux-desktop-custody-')
        self.root = Path(self.tmp.name)
        self.uid = os.getuid() or 1000
        self.root_uid = os.getuid()
        self.state = self.root / 'state'
        self.trusted = self.root / 'trusted'
        self.sources = self.root / 'sources'
        self.proc = self.root / 'proc'
        self.code = self.root / 'code' / RUN / 'upgrade'
        self.code.parent.parent.mkdir(mode=0o755)
        self.code.parent.mkdir(mode=0o755)
        self.code.mkdir(mode=0o755)
        for path in (self.state, self.trusted, self.sources, self.proc):
            path.mkdir(mode=0o700)
        if os.geteuid() == 0:
            os.chown(self.state, self.uid, -1)
        self.context = {'schema': 1, 'runId': RUN, 'round': 'upgrade', 'uid': self.uid,
                        'shellPid': 123, 'session': 'c2', 'bootId': '11111111-2222-3333-4444-555555555555'}
        boot = self.proc / 'sys/kernel/random/boot_id'
        boot.parent.mkdir(parents=True)
        boot.write_text(self.context['bootId'] + '\n')
        self.write(self.trusted / 'context.json', self.context, self.root_uid)
        self.settings_actual = {key: '' for key in receipt.SETTING_PATHS}
        self.snapshot = [{'path': key, 'value': value} for key, value in self.settings_actual.items()]
        self.write(self.trusted / 'settings.json', self.snapshot, self.root_uid)
        self.write(self.trusted / 'original-state.json',
                   {'blur': True, 'panel': True, 'panelInOverview': False, 'theme': receipt.THEME}, self.root_uid)
        self.checker = self.root / 'custody-checker.py'
        self.write(self.checker, (ROOT / 'guest/desktop-receipt.py').read_bytes(), self.root_uid, 0o500)
        self.hashes = {}
        self.metadata = {}
        for kind, names in receipt.SOURCES.items():
            hashes = {}
            for name, key in zip(names[:2], ('probeSha256', names[2])):
                source = ('// ' + name + '\n').encode()
                self.write(self.sources / ('arch-linux-qemu-' + name), source, self.root_uid, 0o500)
                self.write(self.code / name, source, self.root_uid, 0o555)
                hashes[key] = hashlib.sha256(source).hexdigest()
            self.hashes[kind] = hashes
            metadata = {'schema': 1, 'runId': RUN, 'round': 'upgrade', 'uid': self.uid, **hashes}
            metadata.update({'shellPid': 123, 'monitorCount': 1, 'themePath': receipt.THEME} if kind == 'shell' else {'expectedFlags': 8})
            self.metadata[kind] = metadata
            for directory, owner in ((self.state, self.uid), (self.trusted, self.root_uid)):
                self.write(directory / ('desktop-' + kind + '-metadata.json'), metadata, owner)
        self.process('shell', 123)
        self.process('service', 124)
        self.custody = receipt.Custody(self.state, self.trusted, self.uid, RUN, 'upgrade',
                                       self.sources, self.proc, self.root_uid, lambda ctx: self.assertEqual(ctx, self.context),
                                       lambda path: self.settings_actual[path], self.code)

    def tearDown(self):
        self.custody.close()
        self.tmp.cleanup()

    def write(self, path, value, uid, mode=0o600):
        if path.exists() and not path.is_symlink():
            path.chmod(0o600)
        path.write_bytes(value if isinstance(value, bytes) else (json.dumps(value) + '\n').encode())
        path.chmod(mode)
        if os.geteuid() == 0:
            os.chown(path, uid, -1)

    def process(self, kind, pid):
        path = self.proc / str(pid)
        path.mkdir()
        if os.geteuid() == 0:
            os.chown(path, self.uid, -1)
        fields = ['S'] + ['0'] * 18 + ['9999'] + ['0'] * 4
        (path / 'stat').write_text(f'{pid} (process name) ' + ' '.join(fields))
        argv = ['/usr/bin/gnome-shell', '--wayland'] if kind == 'shell' else [
            '/usr/bin/gjs', '-m', str(self.code / 'desktop-service-runner.js'), str(self.state), RUN, 'upgrade']
        (path / 'cmdline').write_bytes(('\0'.join(argv) + '\0').encode())
        (path / 'environ').write_bytes(b'XDG_SESSION_ID=c2\0')
        (path / 'exe').symlink_to(Path('/usr/bin/gnome-shell' if kind == 'shell' else '/usr/bin/gjs').resolve())

    def emit(self, kind, sequence, stage, code, facts, **changes):
        value = {'schema': 1, 'runId': RUN, 'round': 'upgrade', 'uid': self.uid,
                 'pid': 123 if kind == 'shell' else 124, 'sequence': sequence, 'stage': stage,
                 'status': 'ready', 'code': code, 'facts': facts, **self.hashes[kind]}
        value.update(changes)
        name = f'desktop-{kind}-ready.json' if sequence == 0 else f'desktop-{kind}-{sequence}-{stage}.json'
        self.write(self.state / name, value, self.uid)
        if sequence:
            command = {'schema': 1, 'runId': RUN, 'round': 'upgrade', 'sequence': sequence, 'stage': stage}
            self.write(self.trusted / (kind + '-command.json'), command, self.root_uid)
            self.write(self.state / ('desktop-' + kind + '-command.json'), command, self.uid)
        return self.state / name

    def ready(self, kind='shell'):
        self.emit(kind, 0, 'ready', 'observer-started', {'unsafeMode': False} if kind == 'shell' else {})
        return self.custody.verify(kind, 0, 'ready')

    def cleanup(self):
        receipt.cleanup_files(self.state, self.uid, self.code, self.sources, self.root_uid)

    def test_cleanup_removes_only_validated_owned_closures(self):
        self.cleanup()
        self.assertFalse(self.state.exists())
        self.assertFalse(self.code.exists())
        self.assertTrue(self.trusted.is_dir())
        self.assertEqual(len(list(self.sources.iterdir())), 4)

    def test_cleanup_state_path_replacement_preserves_foreign_files(self):
        foreign = self.root / 'foreign'
        foreign.mkdir(mode=0o700)
        names = os.listdir(self.state)
        for name in names:
            self.write(foreign / name, b'foreign receipt', self.uid)
        retained = self.root / 'retained-state'
        original_unlink = os.unlink
        calls = []
        def replace_then_unlink(name, *, dir_fd=None):
            if not calls:
                self.state.rename(retained)
                self.state.symlink_to(foreign, target_is_directory=True)
            calls.append((name, dir_fd))
            return original_unlink(name, dir_fd=dir_fd)
        with mock.patch.object(receipt.os, 'unlink', side_effect=replace_then_unlink):
            with self.assertRaises(ValueError): self.cleanup()
        self.assertTrue(self.state.is_symlink())
        self.assertTrue(retained.is_dir())
        self.assertEqual(list(retained.iterdir()), [])
        self.assertEqual(set(os.listdir(foreign)), set(names))
        self.assertTrue(all((foreign / name).read_bytes() == b'foreign receipt' for name in names))
        self.assertTrue(all(fd is not None for _, fd in calls))

    def test_cleanup_invalid_entries_fail_before_any_deletion(self):
        bad = self.state / 'unexpected.txt'
        for invalid in ('unexpected', 'symlink', 'mutable-file', 'changed-source', 'extra-code'):
            with self.subTest(invalid=invalid):
                target = self.state / 'desktop-shell-metadata.json'
                original = target.read_bytes()
                source = self.code / 'desktop-shell-probe.js'
                original_source = source.read_bytes()
                if invalid == 'unexpected': self.write(bad, b'foreign', self.uid)
                elif invalid == 'symlink':
                    target.unlink(); target.symlink_to(self.trusted / 'desktop-shell-metadata.json')
                elif invalid == 'mutable-file': source.chmod(0o755)
                elif invalid == 'changed-source': self.write(source, b'changed', self.root_uid, 0o555)
                else: self.write(self.code / 'extra.js', b'foreign', self.root_uid, 0o555)
                with mock.patch.object(receipt.os, 'unlink', wraps=os.unlink) as unlink:
                    with self.assertRaises((ValueError, OSError)): self.cleanup()
                    unlink.assert_not_called()
                if bad.exists(): bad.unlink()
                if target.is_symlink(): target.unlink()
                self.write(target, original, self.uid)
                self.write(source, original_source, self.root_uid, 0o555)
                extra = self.code / 'extra.js'
                if extra.exists(): extra.unlink()

    def test_failed_constructor_closes_retained_descriptors(self):
        self.code.chmod(0o777)
        before = set(os.listdir('/proc/self/fd'))
        with self.assertRaises(ValueError):
            receipt.Custody(self.state, self.trusted, self.uid, RUN, 'upgrade',
                self.sources, self.proc, self.root_uid, code_root=self.code)
        self.assertEqual(set(os.listdir('/proc/self/fd')), before)
        self.code.chmod(0o755)

    def test_native_ready_and_exact_facts(self, include_restoration=True):
        self.ready()
        stages = [
            ('blur-on', 'blur-applied', {'monitorCountMatches': True, 'enabled': True, 'attached': True,
             'overviewVisible': True, 'widgetCount': 1, 'managerCount': 1, 'activeWidgets': 1}),
            ('blur-off', 'blur-removed', {'monitorCountMatches': True, 'disabled': True, 'detached': True,
             'widgetCount': 0, 'managerCount': 0}),
            ('panel-shown', 'panel-applied', {'chromeParent': True, 'overviewParent': False,
             'zeroOffset': True, 'hiddenTopOffset': False, 'visible': True, 'mapped': True, 'overviewVisible': False}),
            ('panel-hidden', 'panel-applied', {'chromeParent': False, 'overviewParent': True,
             'zeroOffset': False, 'hiddenTopOffset': True, 'visible': True, 'mapped': False, 'overviewVisible': False}),
            ('panel-overview-only', 'panel-applied', {'chromeParent': False, 'overviewParent': True,
             'zeroOffset': True, 'hiddenTopOffset': False, 'visible': True, 'mapped': True, 'overviewVisible': True}),
            ('panel-shown', 'panel-applied', {'chromeParent': True, 'overviewParent': False,
             'zeroOffset': True, 'hiddenTopOffset': False, 'visible': True, 'mapped': True, 'overviewVisible': True}),
            ('theme-stock', 'theme-applied', {'selectedMatches': True, 'loadedMatches': True}),
            ('theme-marble', 'theme-applied', {'selectedMatches': True, 'loadedMatches': True}),
        ]
        if include_restoration:
            stages += [stages[0], stages[5], stages[7]]
        stages.append(('stop', 'observer-stopped', {}))
        for sequence, (stage, code, facts) in enumerate(stages, 1):
            self.emit('shell', sequence, stage, code, facts)
            self.custody.verify('shell', sequence, stage)
            self.custody.verify('shell', sequence, stage)  # Identical readback is harmless.

    def test_service_transitions(self):
        self.ready('service')
        values = [('indicator-register', 'indicator-registered', {'registered': True, 'signal': True}, 'any'),
                  ('indicator-remove', 'indicator-removed', {'absent': True, 'signal': True}, 'any'),
                  ('caffeine-observe', 'inhibitor-observed', {'count': 2, 'matchingCount': 0, 'found': False}, 'off'),
                  ('caffeine-observe', 'inhibitor-observed', {'count': 2, 'matchingCount': 1, 'found': True}, 'on'),
                  ('caffeine-observe', 'inhibitor-observed', {'count': 0, 'matchingCount': 0, 'found': False}, 'off'),
                  ('stop', 'observer-stopped', {'closed': True}, 'any')]
        for sequence, (stage, code, facts, expected) in enumerate(values, 1):
            self.emit('service', sequence, stage, code, facts)
            self.custody.verify('service', sequence, stage, expected)

    def test_bad_ready_identities(self):
        for changes in ({'round': 'postreboot'}, {'runId': RUN[:-1] + 'e'}, {'pid': 124},
                        {'uid': self.uid + 1}, {'schema': True}, {'sequence': True},
                        {'probeSha256': '0' * 64}, {'status': 'failure'}, {'code': 'unsafe-mode'},
                        {'facts': {'unsafeMode': True}}, {'facts': {'unsafeMode': 0}}, {'extra': True}):
            with self.subTest(changes=changes):
                path = self.emit('shell', 0, 'ready', 'observer-started', {'unsafeMode': False})
                value = json.loads(path.read_text()); value.update(changes)
                self.write(path, value, self.uid)
                with self.assertRaises(ValueError):
                    self.custody.verify('shell', 0, 'ready')

    def test_symlink_and_oversize_receipts(self):
        path = self.emit('shell', 0, 'ready', 'observer-started', {'unsafeMode': False})
        original = path.read_bytes()
        path.unlink()
        target = self.root / 'foreign.json'
        self.write(target, original, self.uid)
        path.symlink_to(target)
        with self.assertRaises(OSError): self.custody.verify('shell', 0, 'ready')
        path.unlink()
        self.write(path, b' ' * 16385, self.uid)
        with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')

    def test_wrong_mode_and_hardlink(self):
        path = self.emit('shell', 0, 'ready', 'observer-started', {'unsafeMode': False})
        path.chmod(0o644)
        with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')
        path.chmod(0o600)
        os.link(path, self.state / 'alias.json')
        with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')

    def test_user_state_source_substitution_is_ignored(self):
        self.write(self.state / 'desktop-shell-probe.js', b'// substitute\n', self.uid, 0o555)
        self.ready()
        self.assertEqual(self.custody.hashes('shell'), self.hashes['shell'])

    def test_code_ancestors_reject_writable_or_symlinked_paths(self):
        for parent in (self.code, self.code.parent, self.code.parent.parent):
            parent.chmod(0o777)
            with self.assertRaises(ValueError):
                receipt.Custody(self.state, self.trusted, self.uid, RUN, 'upgrade',
                    self.sources, self.proc, self.root_uid, lambda _: None, lambda _: '', self.code)
            parent.chmod(0o755)
        linked = self.root / 'linked-code'; linked.symlink_to(self.code, target_is_directory=True)
        with self.assertRaises(ValueError):
            receipt.Custody(self.state, self.trusted, self.uid, RUN, 'upgrade',
                self.sources, self.proc, self.root_uid, lambda _: None, lambda _: '', linked)

    def test_changed_source_or_metadata(self):
        self.emit('shell', 0, 'ready', 'observer-started', {'unsafeMode': False})
        path = self.code / 'desktop-shell-probe.js'
        original = path.read_bytes()
        self.write(path, b'// altered\n', self.root_uid, 0o555)
        with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')
        self.write(path, original, self.root_uid, 0o555)
        value = copy.deepcopy(self.metadata['shell']); value['monitorCount'] = 2
        self.write(self.state / 'desktop-shell-metadata.json', value, self.uid)
        with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')

    def test_process_reuse_and_shell_session(self):
        self.ready()
        self.emit('shell', 1, 'stop', 'observer-stopped', {})
        path = self.proc / '123' / 'stat'
        path.write_text(path.read_text().replace('9999', '10000'))
        with self.assertRaises(ValueError): self.custody.verify('shell', 1, 'stop')
        path.write_text(path.read_text().replace('10000', '9999'))
        (self.proc / '123' / 'environ').write_bytes(b'XDG_SESSION_ID=c3\0')
        with self.assertRaises(ValueError): self.custody.verify('shell', 1, 'stop')

    def test_service_wrong_arguments_and_executable(self):
        self.emit('service', 0, 'ready', 'observer-started', {})
        path = self.proc / '124' / 'cmdline'
        original = path.read_bytes()
        path.write_bytes(original.replace(b'upgrade', b'postreboot'))
        with self.assertRaises(ValueError): self.custody.verify('service', 0, 'ready')
        path.write_bytes(original)
        exe = self.proc / '124' / 'exe'; exe.unlink(); exe.symlink_to('/usr/bin/python3')
        with self.assertRaises(ValueError): self.custody.verify('service', 0, 'ready')

    def test_mutable_source_copy_rejected(self):
        self.emit('shell', 0, 'ready', 'observer-started', {'unsafeMode': False})
        path = self.code / 'desktop-shell-probe.js'
        path.chmod(0o755)
        with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')
        path.chmod(0o555)
        if os.geteuid() == 0:
            os.chown(path, self.uid, -1)
            with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')

    def test_reordered_and_changed_completed_receipt(self):
        self.ready()
        self.emit('shell', 2, 'stop', 'observer-stopped', {})
        with self.assertRaises(ValueError): self.custody.verify('shell', 2, 'stop')
        path = self.emit('shell', 1, 'stop', 'observer-stopped', {})
        self.custody.verify('shell', 1, 'stop')
        self.write(path, path.read_bytes() + b' ', self.uid)
        with self.assertRaises(ValueError): self.custody.verify('shell', 1, 'stop')

    def test_foreign_inhibitor_and_invalid_counts(self):
        self.ready('service')
        for facts in ({'count': 1, 'matchingCount': 0, 'found': False},
                      {'count': 0, 'matchingCount': 1, 'found': True},
                      {'count': 1, 'matchingCount': True, 'found': True},
                      {'count': 129, 'matchingCount': 1, 'found': True}):
            self.emit('service', 1, 'caffeine-observe', 'inhibitor-observed', facts)
            with self.assertRaises(ValueError): self.custody.verify('service', 1, 'caffeine-observe', 'on')

    def test_duplicate_json_keys(self):
        path = self.emit('shell', 0, 'ready', 'observer-started', {'unsafeMode': False})
        data = path.read_bytes().replace(b'{"schema": 1', b'{"schema": 1, "schema": 1', 1)
        self.write(path, data, self.uid)
        with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')

    def test_live_session_mismatch(self):
        self.emit('shell', 0, 'ready', 'observer-started', {'unsafeMode': False})
        def reject(_): raise ValueError('invalid-custody')
        self.custody.session_check = reject
        with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')

    def test_completion_requires_both_controls(self):
        self.test_native_ready_and_exact_facts()
        self.test_service_transitions()
        output = io.StringIO()
        with contextlib.redirect_stdout(output): self.custody.completion()
        self.assertEqual(len(output.getvalue().splitlines()), 5)
        self.assertIn('feature=caffeine', output.getvalue())
        self.assertIn('probe_sha256=' + self.hashes['service']['serviceSha256'], output.getvalue())
        path = self.trusted / 'desktop-service-4-caffeine-observe.json'
        value = json.loads(path.read_text()); value['facts'] = {'count': 0, 'matchingCount': 0, 'found': False}
        self.write(path, value, self.root_uid)
        output = io.StringIO()
        with contextlib.redirect_stdout(output), self.assertRaises(ValueError): self.custody.completion()
        self.assertEqual(output.getvalue(), '')

    def test_unmapped_panel_and_counter_spoof_rejected(self):
        self.ready()
        self.emit('shell', 1, 'panel-shown', 'panel-applied', {'chromeParent': True, 'overviewParent': False,
                  'zeroOffset': True, 'hiddenTopOffset': False, 'visible': True, 'mapped': False, 'overviewVisible': False})
        with self.assertRaises(ValueError): self.custody.verify('shell', 1, 'panel-shown')
        self.emit('shell', 1, 'blur-on', 'blur-applied', {'monitorCountMatches': True, 'enabled': True,
                  'attached': True, 'overviewVisible': True, 'widgetCount': True, 'managerCount': 1, 'activeWidgets': 1})
        with self.assertRaises(ValueError): self.custody.verify('shell', 1, 'blur-on')

    def test_shell_without_legacy_session_environment(self):
        (self.proc / '123' / 'environ').write_bytes(b'WAYLAND_DISPLAY=wayland-0\0')
        self.ready()

    def test_altered_user_command_rejected(self):
        self.ready()
        self.emit('shell', 1, 'stop', 'observer-stopped', {})
        path = self.state / 'desktop-shell-command.json'
        self.write(path, path.read_bytes() + b' ', self.uid)
        with self.assertRaises(ValueError): self.custody.verify('shell', 1, 'stop')

    def test_scoped_dconf_restores_unset_without_touching_other_keys(self):
        values = dict(self.settings_actual)
        values['/org/gnome/shell/extensions/just-perfection/panel'] = 'false'
        values['/org/gnome/shell/extensions/user-theme/name'] = "''"
        self.write(self.trusted / 'settings.json',
                   [{'path': key, 'value': value} for key, value in values.items()], self.root_uid)
        script = r'''
set -euo pipefail
source "$1"
desktop_native_uid=1000
desktop_native_trusted="$2"
desktop_native_checker="$3"
declare -A scoped=(
 [/org/gnome/shell/extensions/caffeine/user-enabled]=true
 [/org/gnome/shell/extensions/just-perfection/panel]=true
 [/org/gnome/shell/extensions/user-theme/name]="'temporary'"
 [/org/gnome/desktop/interface/clock-show-weekday]=true
)
run_in_user_session() {
 local operation="$3" path="$4"
 case "$operation" in
 read) printf '%s' "${scoped[$path]-}" ;;
 write) scoped["$path"]="$5" ;;
 reset) unset 'scoped[$path]' ;;
 *) return 1 ;;
 esac
}
desktop_native_restore_settings
[[ ! -v scoped[/org/gnome/shell/extensions/caffeine/user-enabled] ]]
[[ "${scoped[/org/gnome/shell/extensions/just-perfection/panel]}" = false ]]
[[ "${scoped[/org/gnome/shell/extensions/user-theme/name]}" = "''" ]]
[[ "${scoped[/org/gnome/desktop/interface/clock-show-weekday]}" = true ]]
'''
        result = subprocess.run(['bash', '-c', script, 'desktop-restoration-check',
                                 str(ROOT / 'guest/desktop-native.sh'), str(self.trusted), str(self.checker)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unreadable_or_malformed_snapshot_cannot_report_restoration(self):
        script = r'''
set -euo pipefail
source "$1"
desktop_native_uid=1000
desktop_native_trusted="$2"
desktop_native_checker="$3"
run_in_user_session() { printf 'SETTING_WRITE_ATTEMPT\n'; }
desktop_native_restore_settings
printf 'RESTORE_RESULT=success\n'
'''
        path = self.trusted / 'settings.json'
        for value in (None, b'{malformed', b'[]'):
            if path.exists(): path.unlink()
            if value is not None: self.write(path, value, self.root_uid)
            result = subprocess.run(['bash', '-c', script, 'desktop-restoration-negative',
                                     str(ROOT / 'guest/desktop-native.sh'), str(self.trusted), str(self.checker)],
                                    capture_output=True, text=True, timeout=10)
            with self.subTest(value=value):
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('SETTING_WRITE_ATTEMPT', result.stdout)
                self.assertNotIn('RESTORE_RESULT=success', result.stdout)

    def test_completion_rejects_original_preferences_mismatch(self):
        self.test_native_ready_and_exact_facts()
        self.test_service_transitions()
        self.write(self.trusted / 'original-state.json',
                   {'blur': True, 'panel': False, 'panelInOverview': False, 'theme': None}, self.root_uid)
        output = io.StringIO()
        with contextlib.redirect_stdout(output), self.assertRaises(ValueError):
            self.custody.completion()
        self.assertEqual(output.getvalue(), '')

    def test_completion_rejects_missing_native_restoration_tail(self):
        self.test_native_ready_and_exact_facts(include_restoration=False)
        self.test_service_transitions()
        output = io.StringIO()
        with contextlib.redirect_stdout(output), self.assertRaises(ValueError): self.custody.completion()
        self.assertEqual(output.getvalue(), '')

    def test_completion_rejects_changed_raw_user_setting(self):
        self.test_native_ready_and_exact_facts()
        self.test_service_transitions()
        self.settings_actual[receipt.SETTING_PATHS[6]] = 'false'
        output = io.StringIO()
        with contextlib.redirect_stdout(output), self.assertRaises(ValueError): self.custody.completion()
        self.assertEqual(output.getvalue(), '')

    def test_changed_boot_identity_rejected(self):
        self.emit('shell', 0, 'ready', 'observer-started', {'unsafeMode': False})
        (self.proc / 'sys/kernel/random/boot_id').write_text('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n')
        with self.assertRaises(ValueError): self.custody.verify('shell', 0, 'ready')

    def test_snapshot_requires_all_exact_scoped_keys(self):
        for values in (self.snapshot[:-1], self.snapshot + [self.snapshot[0]],
                       [self.snapshot[1], self.snapshot[0], *self.snapshot[2:]],
                       [dict(self.snapshot[0], path='/org/gnome/desktop/interface/clock-show-weekday'), *self.snapshot[1:]]):
            self.write(self.trusted / 'settings.json', values, self.root_uid)
            with self.assertRaises(ValueError): receipt.settings_snapshot(self.trusted, self.root_uid)


if __name__ == '__main__':
    unittest.main()
