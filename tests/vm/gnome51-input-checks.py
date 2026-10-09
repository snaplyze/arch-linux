#!/usr/bin/env python3
"""Offline unit tests for the real migration input trust boundary."""
import importlib.machinery
import pathlib
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
M = importlib.machinery.SourceFileLoader('gnome51_inputs', str(ROOT / 'tests/vm/prepare-gnome51-upgrade-inputs.py')).load_module()

# Exact public recipe metadata fixtures; SHA-256 checked against reviewed pins.
REVIEWED_SRCINFO = {
    'gnome-shell-extension-blur-my-shell': b'pkgbase = gnome-shell-extension-blur-my-shell\n\tpkgdesc = Extension that adds a blur look to different parts of the GNOME Shell\n\tpkgver = 72\n\tpkgrel = 1\n\turl = https://github.com/aunetx/blur-my-shell\n\tarch = any\n\tlicense = MIT\n\tmakedepends = git\n\tmakedepends = jq\n\tdepends = gnome-shell\n\toptdepends = gnome-rounded-blur: help fix the corners issue found while using dynamic blur\n\tsource = git+https://github.com/aunetx/blur-my-shell.git#tag=v72\n\tsha256sums = 75e1519568d201220a598933b3084a15fea9166dade317cb9ffb54afaf1df2c0\n\npkgname = gnome-shell-extension-blur-my-shell\n',
    'gnome-shell-extension-clipboard-indicator': b'pkgbase = gnome-shell-extension-clipboard-indicator\n\tpkgdesc = Adds a clipboard indicator to the top panel, and caches clipboard history\n\tpkgver = 71\n\tpkgrel = 1\n\turl = https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator\n\tarch = any\n\tlicense = MIT\n\tdepends = gnome-shell>=46.0\n\tconflicts = gnome-shell-extension-clipboard-history\n\tsource = gnome-shell-extension-clipboard-indicator-71.tar.gz::https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator/archive/v71.tar.gz\n\tsha256sums = 31d6c3694889b0f1c257b113926643e6a37610495f501cbd810eb2c14b9ebd85\n\npkgname = gnome-shell-extension-clipboard-indicator\n',
    'gnome-shell-extension-dash-to-dock': b'pkgbase = gnome-shell-extension-dash-to-dock\n\tpkgdesc = Move the dash out of the overview transforming it in a dock\n\tpkgver = 106\n\tpkgrel = 1\n\tepoch = 1\n\turl = https://micheleg.github.io/dash-to-dock/\n\tarch = any\n\tlicense = GPL-2.0-or-later\n\tmakedepends = gettext\n\tmakedepends = git\n\tmakedepends = sassc\n\tdepends = gnome-shell\n\tsource = git+https://github.com/micheleg/dash-to-dock.git#commit=a7b19816b7277e41c18ea5c3ff165e493a14e0d4\n\tsha256sums = SKIP\n\npkgname = gnome-shell-extension-dash-to-dock\n',
    'gnome-shell-extension-just-perfection-desktop': b'pkgbase = gnome-shell-extension-just-perfection-desktop\n\tpkgdesc = Just Perfection GNOME Shell Desktop\n\tpkgver = 37\n\tpkgrel = 1\n\turl = https://gitlab.gnome.org/jrahmatzadeh/just-perfection\n\tarch = any\n\tlicense = GPL3\n\tmakedepends = git\n\tdepends = gnome-shell\n\tsource = gnome-shell-extension-just-perfection-desktop::git+https://gitlab.gnome.org/jrahmatzadeh/just-perfection.git#tag=37.0\n\tmd5sums = SKIP\n\npkgname = gnome-shell-extension-just-perfection-desktop\n',
}

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

    def test_archive_guard_never_runs_on_host(self):
        row=M.load_pins(ROOT)['aur'][0]
        info={'pkgname':[row['name']],'pkgver':[row['version']],'arch':['any'],'depend':['gnome-shell']}
        with mock.patch.object(M,'installer_call',side_effect=AssertionError('Arch oracle must not run on Ubuntu host')), mock.patch.object(M,'pkginfo',return_value=info):
            M.verify_aur_package(ROOT,pathlib.Path('/tmp/public.pkg.tar.zst'),row)

    def test_dedicated_verifier_setup_isolation_and_cleanup_fail_closed(self):
        import subprocess
        self.assertTrue(hasattr(M,'verify_aur_archives'),'all archive guards need the dedicated Arch verifier')
        for failure in ('none','start','setup','disconnect','network','guard','changed-input'):
            with self.subTest(failure=failure),tempfile.TemporaryDirectory() as t:
                directory=pathlib.Path(t); archives=[]
                for row in M.load_pins(ROOT)['aur']:
                    path=directory/M.package_filename(row);path.write_bytes(b'public package fixture');archives.append((path,row))
                calls=[]
                def execute(args,**kwargs):
                    calls.append((args,kwargs))
                    text=kwargs.get('input',b'');text=text.decode() if isinstance(text,bytes) else text
                    stage=('start' if args[:2]==['docker','run'] else
                           'disconnect' if args[:3]==['docker','network','disconnect'] else
                           'setup' if 'pacman-key --init' in text else
                           'guard' if 'aur_package_archive_is_safe' in text else None)
                    if failure==stage: raise subprocess.CalledProcessError(43,args)
                    if stage=='guard' and failure=='changed-input': archives[0][0].write_bytes(b'changed')
                    output='{"bridge":{}}' if failure=='network' else '{}'
                    return subprocess.CompletedProcess(args,0,stdout=output,stderr='')
                with mock.patch.object(M,'run',side_effect=execute),mock.patch.object(M,'cleanup_container') as cleanup:
                    if failure=='none': M.verify_aur_archives(ROOT,archives)
                    else:
                        with self.assertRaises((ValueError,subprocess.SubprocessError)): M.verify_aur_archives(ROOT,archives)
                    cleanup.assert_called_once();self.assertTrue(cleanup.call_args.args[0].startswith('arch-linux-g51-verifier-'))
                command=calls[0][0]
                self.assertIn('--cpus=2',command);self.assertIn('--memory=4g',command);self.assertIn('--pids-limit=256',command)
                self.assertIn('--network=bridge',command);self.assertIn('no-new-privileges',command)
                mounts=[command[i+1] for i,arg in enumerate(command) if arg=='--mount']
                self.assertEqual(len(mounts),1);self.assertTrue(mounts[0].endswith('target=/inputs,readonly'))
                scripts=[kwargs.get('input',b'').decode() for _,kwargs in calls if kwargs.get('input')]
                guard=[text for text in scripts if 'aur_package_archive_is_safe' in text]
                if failure in ('start','setup','disconnect','network'): self.assertFalse(guard)
                if failure=='none':
                    self.assertEqual(len(guard),1);self.assertEqual(guard[0].count('aur_package_archive_is_safe'),4)
                    self.assertIn('socket.if_nameindex()',guard[0]);self.assertIn('source /inputs/arch-linux-installer.sh',guard[0])
                    self.assertNotIn('makepkg',guard[0]);self.assertNotIn('recipes',guard[0])
                    self.assertLess(next(i for i,(args,_) in enumerate(calls) if args[:3]==['docker','network','disconnect']),
                                    next(i for i,(_,kwargs) in enumerate(calls) if 'aur_package_archive_is_safe' in str(kwargs.get('input'))))

    def test_builder_is_removed_before_one_batched_archive_verifier(self):
        import subprocess
        pins=M.load_pins(ROOT); events=[]
        with tempfile.TemporaryDirectory() as t:
            root=pathlib.Path(t);recipes=root/'recipes';recipes.mkdir();output=root/'out';output.mkdir()
            def execute(args,**kwargs):
                if 'cat' in args: return subprocess.CompletedProcess(args,0,stdout=b'public source metadata')
                if 'stat' in args: return subprocess.CompletedProcess(args,0,stdout='7')
                if 'head' in args: kwargs['stdout'].write(b'package')
                return subprocess.CompletedProcess(args,0,stdout=b'container')
            def verify(source,archives):
                self.assertEqual(events,['cleanup']);self.assertEqual(len(archives),4)
                self.assertTrue(all(path.read_bytes()==b'package' for path,_ in archives));events.append('guard')
            with mock.patch.object(M,'run',side_effect=execute),mock.patch.object(M,'installer_call'), \
                    mock.patch.object(M,'cleanup_container',side_effect=lambda name: events.append('cleanup')), \
                    mock.patch.object(M,'verify_aur_archives',side_effect=verify), \
                    mock.patch.object(M,'verify_aur_package',side_effect=lambda *args: events.append('metadata')):
                M.build_aur(ROOT,recipes,output,pins)
            self.assertEqual(events,['cleanup','guard']+['metadata']*4)

    def test_verifier_bootstrap_executes_authenticated_sequence(self):
        import subprocess
        self.assertTrue(hasattr(M,'verifier_setup_script'))
        with tempfile.TemporaryDirectory() as t:
            directory=pathlib.Path(t);bins=directory/'bin';bins.mkdir();trace=directory/'trace'
            stub='#!/bin/sh\nprintf "%s %s\n" "${0##*/}" "$*" >>"$TRACE"\n[ "${0##*/}:$*" != "$FAIL_AT" ] || exit 43\n'
            for name in ('pacman-key','pacman','gpgconf'):
                path=bins/name;path.write_text(stub);path.chmod(0o755)
            script=M.verifier_setup_script()
            for fail_at in ('none','pacman-key:--init','pacman-key:--populate archlinux','pacman:-Sy --noconfirm --needed archlinux-keyring','pacman:-Syu --noconfirm --needed bash coreutils libarchive python'):
                if trace.exists(): trace.unlink()
                result=subprocess.run(['/usr/bin/bash','-c',script],env={'PATH':str(bins),'TRACE':str(trace),'FAIL_AT':fail_at},capture_output=True,text=True)
                self.assertEqual(result.returncode,0 if fail_at=='none' else 43,result.stderr)
                calls=trace.read_text().splitlines()
                if fail_at=='none':
                    self.assertEqual(calls[:4],['pacman-key --init','pacman-key --populate archlinux','pacman -Sy --noconfirm --needed archlinux-keyring','pacman -Syu --noconfirm --needed bash coreutils libarchive python'])
                    self.assertEqual(calls[4],'gpgconf --homedir /etc/pacman.d/gnupg --kill all')
                else: self.assertEqual(calls[-1],fail_at.replace(':',' ',1))

    def test_builder_boundary(self):
        cmd = M.container_command(ROOT, pathlib.Path('/tmp/recipes'), 'arch-linux-g51-test')
        self.assertIn('--cpus=2', cmd); self.assertIn('--memory=4g', cmd)
        self.assertIn('--pids-limit=256', cmd)
        self.assertIn('--init', cmd)
        self.assertIn('no-new-privileges', cmd)
        mounts = [cmd[index + 1] for index, argument in enumerate(cmd) if argument == '--mount']
        self.assertEqual(mounts, ['type=bind,source=/tmp/recipes,target=/recipes,readonly'])
        script = M.builder_script(M.load_pins(ROOT))
        self.assertIn('runuser -u builder --', script)
        self.assertNotIn('sudo', script)
        self.assertNotIn('makepkg --skip', script)
        self.assertIn('makepkg --nodeps --noconfirm', script)

    def test_epoch_archive_handoff_retains_canonical_input_name(self):
        pins=M.load_pins(ROOT)
        dash=next(row for row in pins['aur'] if row['name'].endswith('-dash-to-dock'))
        self.assertEqual(M.package_filename(dash),'gnome-shell-extension-dash-to-dock-106-1-any.pkg.tar.zst')
        script=M.builder_script(pins)
        command='cp -- gnome-shell-extension-dash-to-dock-1:106-1-any.pkg.tar.zst /out/gnome-shell-extension-dash-to-dock-106-1-any.pkg.tar.zst'
        self.assertIn(command,script)
        import subprocess
        with tempfile.TemporaryDirectory() as t:
            work=pathlib.Path(t);(work/'out').mkdir()
            produced=work/'gnome-shell-extension-dash-to-dock-1:106-1-any.pkg.tar.zst'
            raw=b'\x00exact package byte fixture\xff';produced.write_bytes(raw)
            subprocess.run(['/usr/bin/bash','--noprofile','--norc','-c',command.replace('/out/',str(work/'out')+'/')],cwd=work,check=True)
            self.assertEqual((work/'out'/M.package_filename(dash)).read_bytes(),raw)
        info={'pkgname':[dash['name']],'pkgver':['1:106-1'],'arch':['any']}
        with mock.patch.object(M,'pkginfo',return_value=info):
            M.package_identity(pathlib.Path('/tmp/canonical.pkg.tar.zst'),dash['name'],dash['version'])
            info['pkgver']=['106-1']
            with self.assertRaises(ValueError):
                M.package_identity(pathlib.Path('/tmp/canonical.pkg.tar.zst'),dash['name'],dash['version'])

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

    def test_real_reviewed_metadata_and_unexpected_conflicts(self):
        for row in M.load_pins(ROOT)['aur']:
            raw=REVIEWED_SRCINFO[row['name']]
            self.assertEqual(M.digest(raw),row['srcinfoSha256'])
            fields={}
            for line in raw.decode().splitlines():
                if ' = ' in line:
                    key,value=line.strip().split(' = ',1);fields.setdefault(key,[]).append(value)
            fullver=(fields['epoch'][0]+':' if 'epoch' in fields else '')+fields['pkgver'][0]+'-'+fields['pkgrel'][0]
            info={'pkgname':fields['pkgname'],'pkgver':[fullver],'arch':fields['arch'],'depend':fields['depends']}
            if 'conflicts' in fields: info['conflict']=fields['conflicts']
            for field in ('provides','replaces','install'): self.assertNotIn(field,fields)
            with mock.patch.object(M,'installer_call'),mock.patch.object(M,'pkginfo',return_value=info):
                # Namespace parsing and PKGINFO extraction are stubbed using real
                # reviewed SRCINFO; actual archive acceptance remains a required
                # full preparer integration check.
                M.verify_aur_package(ROOT,pathlib.Path('/tmp/reviewed.pkg.tar.zst'),row)
                for unexpected in (['unrelated-package'],['gnome-shell-extension-clipboard-history','unrelated-package'],['gnome-shell-extension-clipboard-history','gnome-shell-extension-clipboard-history']):
                    with mock.patch.object(M,'pkginfo',return_value=info|{'conflict':unexpected}):
                        with self.assertRaises(ValueError): M.verify_aur_package(ROOT,pathlib.Path('/tmp/reviewed.pkg.tar.zst'),row)
                if 'conflict' in info:
                    no_conflict=dict(info);del no_conflict['conflict']
                    with mock.patch.object(M,'pkginfo',return_value=no_conflict):
                        with self.assertRaises(ValueError): M.verify_aur_package(ROOT,pathlib.Path('/tmp/reviewed.pkg.tar.zst'),row)
                for field in ('provides','replaces','install'):
                    with mock.patch.object(M,'pkginfo',return_value=info|{field:['unexpected']}):
                        with self.assertRaises(ValueError): M.verify_aur_package(ROOT,pathlib.Path('/tmp/reviewed.pkg.tar.zst'),row)

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
            with mock.patch.object(M,'source_identity',return_value=('a'*40,'b'*40)), mock.patch.object(M,'verify_release'), mock.patch.object(M,'verify_aur_package'), mock.patch.object(M,'verify_aur_archives') as archive_guard, mock.patch.object(M,'check_local'):
                original_receipt=M.digest(M.canonical(value))
                self.assertEqual(M.verify_inputs(ROOT,d,original_receipt),value)
                archive_guard.assert_called_once()
                self.assertEqual(len(archive_guard.call_args.args[1]),4)
                (d/aur[0]['filename']).write_bytes(b'changed package bytes')
                value['files']=M.file_map(d)
                (d/'manifest.json').write_bytes(M.canonical(value))
                with self.assertRaises(ValueError): M.verify_inputs(ROOT,d,original_receipt)
                value['aur'][0]['recipeCommit']='f'*40
                (d/'manifest.json').write_bytes(M.canonical(value))
                with self.assertRaises(ValueError): M.verify_inputs(ROOT,d,original_receipt)

if __name__ == '__main__': unittest.main()
