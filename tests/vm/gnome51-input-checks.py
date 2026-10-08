#!/usr/bin/env python3
"""Offline unit tests for the real migration input trust boundary."""
import importlib.machinery
import pathlib
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
M = importlib.machinery.SourceFileLoader('gnome51_inputs', str(ROOT / 'tests/vm/prepare-gnome51-upgrade-inputs.py')).load_module()

class InputChecks(unittest.TestCase):
    def test_pins_match_installer(self):
        M.check_installer_pins(ROOT, M.load_pins(ROOT))

    def test_pins_exact_baseline(self):
        pins = M.load_pins(ROOT)
        self.assertEqual(pins['baseline']['packages']['arch-linux-colloid-gtk'], '20260808-10')
        self.assertEqual({r['version'] for r in pins['aur']}, {'72-1', '71-1', '1:106-1', '37-1'})
        self.assertEqual(len(pins['release']), 10)

    def test_unsafe_closure_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            (root / 'link').symlink_to('/etc/passwd')
            with self.assertRaises(ValueError): M.file_map(root)
            (root / 'link').unlink()
            (root / 'file').write_text('x')
            import os
            os.link(root / 'file', root / 'alias')
            with self.assertRaises(ValueError): M.file_map(root)

    def test_extra_directory_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t); (root / 'extra').mkdir()
            with self.assertRaises(ValueError): M.file_map(root)

    def test_changed_release_digest_rejected_before_signature(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            for name in M.load_pins(ROOT)['release']: (root / name).write_bytes(b'tampered')
            with mock.patch.object(M, 'verify_signature') as signature:
                with self.assertRaises(ValueError): M.verify_release(ROOT, root, M.load_pins(ROOT))
                signature.assert_not_called()

    def test_builder_boundary(self):
        cmd = M.container_command(ROOT, pathlib.Path('/tmp/recipes'), 'arch-linux-g51-test')
        self.assertIn('--cpus=2', cmd); self.assertIn('--memory=4g', cmd)
        self.assertIn('--pids-limit=256', cmd)
        self.assertIn('no-new-privileges', cmd)
        mounts = [cmd[index + 1] for index, argument in enumerate(cmd) if argument == '--mount']
        self.assertEqual(mounts, ['type=bind,source=/tmp/recipes,target=/recipes,readonly'])
        script = M.builder_script(M.load_pins(ROOT))
        self.assertIn('runuser -u builder --', script)
        self.assertNotIn('sudo', script)
        self.assertNotIn('makepkg --skip', script)
        self.assertIn('makepkg --nodeps --noconfirm', script)

    def test_container_trust_sequence_and_failure_propagation(self):
        # Execute the generated script with an isolated command fixture. None of
        # its package-manager, user-management or recipe commands reach the host.
        import subprocess
        with tempfile.TemporaryDirectory() as t:
            directory=pathlib.Path(t); commands=directory/'bin';commands.mkdir()
            record=directory/'commands'
            stub='#!/bin/sh\nprintf "%s" "${0##*/}" >> "$COMMAND_RECORD"\nfor arg do printf " %s" "$arg" >> "$COMMAND_RECORD"; done\nprintf "\\n" >> "$COMMAND_RECORD"\ncase "${0##*/}:$*" in\n  "pacman-key:--init") [ "$FAIL_STEP" != init ] || exit 17 ;;\n  "pacman-key:--populate archlinux") [ "$FAIL_STEP" != populate ] || exit 18 ;;\n  "pacman:-Sy --noconfirm --needed archlinux-keyring") [ "$FAIL_STEP" != keyring ] || exit 19 ;;\n  pkill:*|pgrep:*) exit 1 ;;\nesac\nexit 0\n'
            for name in ('pacman-key','pacman','useradd','install','cp','chown','runuser','pkill','pgrep'):
                path=commands/name;path.write_text(stub);path.chmod(0o755)
            for failure, expected_code, expected_prefix in (
                ('none',0,['pacman-key --init','pacman-key --populate archlinux','pacman -Sy --noconfirm --needed archlinux-keyring','pacman -Syu --noconfirm --needed git jq gettext sassc gnome-shell']),
                ('init',17,['pacman-key --init']),
                ('populate',18,['pacman-key --init','pacman-key --populate archlinux']),
                ('keyring',19,['pacman-key --init','pacman-key --populate archlinux','pacman -Sy --noconfirm --needed archlinux-keyring'])):
                if record.exists(): record.unlink()
                result=subprocess.run(['/usr/bin/bash','--noprofile','--norc'],input=M.builder_script(M.load_pins(ROOT)),text=True,capture_output=True,
                    env={'PATH':str(commands),'COMMAND_RECORD':str(record),'FAIL_STEP':failure})
                self.assertEqual(result.returncode,expected_code,result.stderr)
                lines=record.read_text().splitlines()
                self.assertEqual(lines[:len(expected_prefix)],expected_prefix)
                if failure!='none': self.assertEqual(lines,expected_prefix)

    def test_cli_stdout_is_only_independent_receipt(self):
        import contextlib,io
        value={'schema':1,'files':{}}
        stdout=io.StringIO()
        with mock.patch.object(M,'prepare',return_value=value), mock.patch.object(M.sys,'argv',['prepare','--source-root',str(ROOT),'--output','/tmp/absent']), contextlib.redirect_stdout(stdout):
            M.main()
        self.assertEqual(stdout.getvalue(),M.digest(M.canonical(value))+'\n')
        with mock.patch.object(M.subprocess,'run') as child:
            M.run(['example'])
            self.assertIs(child.call_args.kwargs['stdout'],M.sys.stderr)

    def test_cleanup_requires_invocation_label(self):
        import subprocess
        response=subprocess.CompletedProcess([],0,stdout='foreign\n',stderr='')
        with mock.patch.object(M.subprocess,'run',return_value=response), mock.patch.object(M,'run') as remove:
            with self.assertRaises(ValueError): M.cleanup_container('owned')
            remove.assert_not_called()

    def test_failed_start_still_cleans_owned_container(self):
        import subprocess
        failure=subprocess.TimeoutExpired('docker',1)
        with mock.patch.object(M,'run',side_effect=failure), mock.patch.object(M,'cleanup_container') as cleanup:
            with self.assertRaises(subprocess.TimeoutExpired):
                M.build_aur(ROOT,pathlib.Path('/tmp/recipes'),pathlib.Path('/tmp/out'),M.load_pins(ROOT))
            cleanup.assert_called_once()
            self.assertTrue(cleanup.call_args.args[0].startswith('arch-linux-g51-input-'))

    def test_dirty_source_stops_before_output_or_container(self):
        with tempfile.TemporaryDirectory() as t:
            target=pathlib.Path(t)/'absent'
            with mock.patch.object(M,'source_identity',side_effect=ValueError('dirty')), mock.patch.object(M,'build_aur') as builder:
                with self.assertRaises(ValueError): M.prepare(ROOT,target)
                self.assertFalse(target.exists()); builder.assert_not_called()

    def test_package_runtime_authority_rejected(self):
        row=M.load_pins(ROOT)['aur'][0]
        info={'pkgname':[row['name']], 'pkgver':[row['version']], 'arch':['any'], 'depend':['gnome-shell'], 'provides':['unexpected']}
        with mock.patch.object(M,'installer_call'), mock.patch.object(M,'pkginfo',return_value=info):
            with self.assertRaises(ValueError): M.verify_aur_package(ROOT,pathlib.Path('/tmp/test.pkg.tar.zst'),row)
            del info['provides']; info['depend']=['bash']
            with self.assertRaises(ValueError): M.verify_aur_package(ROOT,pathlib.Path('/tmp/test.pkg.tar.zst'),row)

    def test_local_pin_is_mandatory(self):
        with tempfile.TemporaryDirectory() as t:
            p=pathlib.Path(t)/'local.zip';p.write_bytes(b'tampered')
            with self.assertRaises(ValueError): M.check_local(p,M.load_pins(ROOT))

    def test_patch_requires_original_context_and_exact_hash(self):
        row=M.load_pins(ROOT)['aur'][0]
        with self.assertRaises(ValueError): M.patch_pkgbuild(b'not a recipe',row)
        with self.assertRaises(ValueError): M.patch_pkgbuild(b'#tag=v$pkgver\n',row)

    def test_manifest_closure_and_pin_tamper(self):
        pins=M.load_pins(ROOT)
        with tempfile.TemporaryDirectory() as t:
            d=pathlib.Path(t)
            for sub in ('release','aur','local'): (d/sub).mkdir()
            for name in pins['release']: (d/'release'/name).write_bytes(b'x')
            aur=[r | {'filename': 'aur/'+M.package_filename(r)} for r in pins['aur']]
            for r in aur: (d/r['filename']).write_bytes(b'package')
            (d/pins['local']['filename']).write_bytes(b'zip')
            value={'schema':1,'baseline':pins['baseline'],'sourceCommit':'a'*40,'sourceTree':'b'*40,'files':M.file_map(d),'aur':aur,'local':{'filename':pins['local']['filename'],'sha256':pins['local']['sha256']}}
            (d/'manifest.json').write_bytes(M.canonical(value))
            with mock.patch.object(M,'source_identity',return_value=('a'*40,'b'*40)), mock.patch.object(M,'verify_release'), mock.patch.object(M,'verify_aur_package'), mock.patch.object(M,'check_local'):
                original_receipt=M.digest(M.canonical(value))
                self.assertEqual(M.verify_inputs(ROOT,d,original_receipt),value)
                (d/aur[0]['filename']).write_bytes(b'changed package bytes')
                value['files']=M.file_map(d)
                (d/'manifest.json').write_bytes(M.canonical(value))
                with self.assertRaises(ValueError): M.verify_inputs(ROOT,d,original_receipt)
                value['aur'][0]['recipeCommit']='f'*40
                (d/'manifest.json').write_bytes(M.canonical(value))
                with self.assertRaises(ValueError): M.verify_inputs(ROOT,d,original_receipt)

if __name__ == '__main__': unittest.main()
