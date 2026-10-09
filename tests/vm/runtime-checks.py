#!/usr/bin/env python3
"""Execute guest runtime guards against bounded filesystem/command fixtures."""
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
VERIFY = ROOT / "tests/vm/guest/verify.sh"
def function(name):
    return re.search(r"^" + name + r"\(\) \{\n.*?^\}", VERIFY.read_text(), re.M | re.S).group(0)
class RuntimeChecks(unittest.TestCase):
    def test_functional_receipt_binds_live_native_probe_and_frozen_source(self):
        import hashlib, json, os, shutil, time
        if not shutil.which('gjs'): self.skipTest('native GJS is not installed')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); state = root / 'state'; state.mkdir(); trusted = root / 'trusted'; trusted.mkdir(mode=0o700)
            source = "import GLib from 'gi://GLib'; new GLib.MainLoop(null,false).run();\n"
            frozen = root / 'frozen.js'; frozen.write_text(source); frozen.chmod(0o500)
            probe = state / 'probe.js'; probe.write_text(source); probe.chmod(0o500)
            digest = hashlib.sha256(source.encode()).hexdigest()
            (state / 'probe.sha256').write_text(digest+'\n')
            identity = 'marble-20261009T010203Z-12345678'
            process = subprocess.Popen(['/usr/bin/gjs','-m',str(probe),str(state),identity,'upgrade'],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
            try:
                time.sleep(.2); self.assertIsNone(process.poll())
                receipt = {'schema':1,'runId':identity,'round':'upgrade','probeSha256':digest,
                           'stage':'dash-ready','valueSha256':'-','pid':process.pid}
                script = ('set -euo pipefail\nprobe_state="$1" username="$2" probe_source="$3" probe_trusted="$4" run_id="$5" probe_round=upgrade\n' +
                    # Only trust-file owner differs in this unprivileged fixture; live exe/argv/starttime remain production checks.
                    function('verify_extension_probe_receipt').replace('trusted_uid = 0','trusted_uid = os.getuid()') +
                    '\nverify_extension_probe_receipt "$6" "$7"\n')
                path = state / 'dash-ready.json'
                def check(stage='dash-ready', expected='-'):
                    return subprocess.run(['bash','-c',script,'fixture',str(state),str(os.getuid()),str(frozen),str(trusted),identity,stage,expected],capture_output=True,text=True)
                self.assertNotEqual(check().returncode,0)
                path.write_text(json.dumps(receipt)); path.chmod(0o600)
                self.assertEqual(check().returncode,0,check().stderr)
                wrong = receipt | {'pid':os.getpid()}; path.write_text(json.dumps(wrong))
                self.assertNotEqual(check().returncode,0,'foreign positive pid must be rejected')
                path.write_text(json.dumps(receipt)); self.assertEqual(check().returncode,0,check().stderr)
                value = hashlib.sha256(b'A').hexdigest(); copied = receipt | {'stage':'pasted-a','valueSha256':value}
                path = state / 'pasted-a.json'; path.write_text(json.dumps(copied)); path.chmod(0o600)
                self.assertEqual(check('pasted-a',value).returncode,0)
                identity_path = trusted / 'identity.json'; saved = identity_path.read_text()
                modified = json.loads(saved); modified['starttime'] += 1; identity_path.write_text(json.dumps(modified))
                self.assertNotEqual(check('pasted-a',value).returncode,0,'reused PID/starttime mismatch')
                identity_path.write_text(saved)
                probe.chmod(0o600); probe.write_text(source+'// changed\n')
                (state / 'probe.sha256').write_text(hashlib.sha256(probe.read_bytes()).hexdigest()+'\n')
                self.assertNotEqual(check('pasted-a',value).returncode,0,'user-rehashed source must not be authority')
                probe.write_text(source); probe.chmod(0o500)
                for key, invalid in [('runId','old'),('round','postreboot'),('probeSha256','b'*64),('stage','copied-a'),('valueSha256','c'*64),('pid',os.getpid())]:
                    path.write_text(json.dumps(copied | {key:invalid}))
                    self.assertNotEqual(check('pasted-a',value).returncode,0,key)
                path.write_text(json.dumps(copied)); process.terminate(); process.wait(timeout=5)
                self.assertNotEqual(check('pasted-a',value).returncode,0,'dead probe must be rejected')
            finally:
                if process.poll() is None: process.terminate(); process.wait(timeout=5)
                process.stderr.close()

    def test_screenshot_observation_rejects_stale_missing_and_wrong_geometry(self):
        import binascii, json, os, struct, zlib
        source = VERIFY.read_text()
        self.assertTrue(re.search(r'(?m)^verify_extension_screenshot\(\) \{', source),
                        'capture-on-release needs actual new PNG observation')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); screenshots = root / 'Screenshots'; screenshots.mkdir()
            (root / 'screenshot-baseline.json').write_text(json.dumps({'directory': str(screenshots), 'names': [], 'identities': []}))
            (root / 'display.json').write_text('{"scale":1,"width":1280,"height":800}')
            script = ('set -euo pipefail\nprobe_state="$1" username="$2"\n' +
                      function('verify_extension_screenshot') + '\nverify_extension_screenshot "$3"\n')
            def check(mode):
                return subprocess.run(['bash', '-c', script, 'fixture', directory, str(os.getuid()), mode],
                                      capture_output=True, text=True)
            self.assertEqual(check('absent').returncode, 0)
            self.assertNotEqual(check('present').returncode, 0)
            def png(width, height):
                def chunk(kind, data):
                    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', binascii.crc32(kind + data) & 0xffffffff)
                header = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
                rows = (b'\0' + b'\0' * (width * 3)) * height
                return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')
            image = screenshots / 'test.png'; image.write_bytes(png(301, 201))
            self.assertEqual(check('present').returncode, 0)
            old_image = image.rename(screenshots / 'old.png'); original = old_image.stat()
            (root / 'screenshot-baseline.json').write_text(json.dumps({'directory':str(screenshots),
                'names':['old.png'],'identities':[[original.st_dev,original.st_ino]]}))
            old_image.rename(image)
            self.assertNotEqual(check('present').returncode,0,'renamed existing PNG must not prove capture')
            (root / 'screenshot-baseline.json').write_text(json.dumps({'directory':str(screenshots),'names':[],'identities':[]}))
            self.assertNotEqual(check('absent').returncode, 0)
            (root / 'screenshot-baseline.json').write_text(json.dumps({'directory': str(screenshots), 'names': ['test.png'], 'identities': []}))
            self.assertNotEqual(check('present').returncode, 0)
            (root / 'screenshot-baseline.json').write_text(json.dumps({'directory': str(screenshots), 'names': [], 'identities': []}))
            image.write_bytes(png(800, 600))
            self.assertNotEqual(check('present').returncode, 0)
            image.write_bytes(png(301, 201)[:-12])
            self.assertNotEqual(check('present').returncode, 0)

    def test_functional_flow_never_asserts_pass_when_any_observation_fails(self):
        body = self.host_function('run_extension_functional_acceptance')
        main = 'marble-gnome-btrfs-luks2-plymouth-systemdboot'
        with tempfile.TemporaryDirectory() as directory:
            script = ('set -euo pipefail\ninput_mode=staged scenario_id=' + main + '\nevidence="$1" fail="$2"\n' + body + r'''
qga_verify(){
  printf 'OBSERVE:%s\n' "$1"
  [ "$1" != "$fail" ] || return 1
  if [[ "$1" = *-dash ]]; then printf 'EXTENSION_PROBE_DISPLAY width=1280 height=800 scale=1\n' >"$evidence/$2.stdout"; fi
}
qmp_extension_input(){ printf 'INPUT:%s\n' "$1"; }
sleep(){ :; }
die(){ return 1; }
record_assertion(){ printf 'ASSERT:%s\n' "$1"; }
run_extension_functional_acceptance upgrade
''')
            for failure in ['', 'extension-upgrade-dash', 'extension-upgrade-history-a', 'extension-upgrade-pasted-b',
                            'extension-upgrade-control-no-capture', 'extension-upgrade-control-captured',
                            'extension-upgrade-positive-captured', 'extension-upgrade-cleanup']:
                result = subprocess.run(['bash', '-c', script, 'fixture', directory, failure],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, failure == '', result.stderr)
                assertions = [line for line in result.stdout.splitlines() if line.startswith('ASSERT:')]
                self.assertEqual(assertions, [] if failure else [
                    'ASSERT:clipboard-history-copy-paste', 'ASSERT:dash-extension-app-activation',
                    'ASSERT:no-screenshot-box-capture-on-release'])
                if not failure:
                    self.assertLess(result.stdout.index('INPUT:next'), result.stdout.index('OBSERVE:extension-upgrade-history-a'))
                    self.assertLess(result.stdout.index('INPUT:previous'), result.stdout.index('OBSERVE:extension-upgrade-history-b'))
                    self.assertLess(result.stdout.index('OBSERVE:extension-upgrade-control-no-capture'), result.stdout.index('INPUT:capture'))
                    self.assertEqual(result.stdout.count('INPUT:capture'), 1)
                    self.assertLess(result.stdout.index('OBSERVE:extension-upgrade-cleanup'), result.stdout.index('ASSERT:'))

    def test_qmp_functional_input_is_bounded_and_preserves_peer_checks(self):
        import json, os, socket, threading
        source = self.host_function('qmp_extension_input')
        code = re.search(r"<<'EXTENSION_INPUT_PY'\n(.*?)\nEXTENSION_INPUT_PY", source, re.S).group(1)
        for operation, fail, accepted in [('dash', False, True), ('drag', False, True),
                                           ('dash', True, False), ('unreviewed', False, False)]:
            with self.subTest(operation=operation, fail=fail), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); path = root / 'qmp.sock'; server = socket.socket(socket.AF_UNIX)
                server.bind(str(path)); server.listen(1); server.settimeout(2); frames = []
                # Real socket credentials/identity, with only unavailable QEMU process identity stubbed.
                module = root / 'boundary.py'
                module.write_text('import importlib.util,sys\n'
                    'spec=importlib.util.spec_from_file_location("real_boundary",' + repr(str(ROOT / 'tests/vm/frame-evidence.py')) + ')\n'
                    'real=importlib.util.module_from_spec(spec);sys.modules[spec.name]=real;spec.loader.exec_module(real)\n'
                    'real.exact_qemu=lambda pid,start: pid==' + str(os.getpid()) + ' and start=="fixture"\n'
                    'QMP=real.QMP;demand=real.demand;exact_qemu=real.exact_qemu\n')
                def serve():
                    try:
                        connection, _ = server.accept()
                        with connection, connection.makefile('rb') as reader:
                            connection.sendall(b'{"QMP":{}}\r\n')
                            while line := reader.readline():
                                frame = json.loads(line); frames.append(frame)
                                rejected = fail and frame['execute'] == 'send-key'
                                connection.sendall((json.dumps({'error': {'class':'fixture'}} if rejected else {'return': {}}) + '\r\n').encode())
                    except (TimeoutError, OSError): pass
                thread = threading.Thread(target=serve); thread.start(); info = path.stat()
                result = subprocess.run(['python3', '-c', code, str(module), str(path),
                    f'{info.st_dev}:{info.st_ino}', str(os.getpid()), 'fixture', operation, '1280', '800'],
                    capture_output=True, text=True, timeout=5)
                thread.join(3); server.close(); self.assertFalse(thread.is_alive())
                self.assertEqual(result.returncode == 0, accepted, result.stderr)
                self.assertTrue(all(frame['execute'] in ('qmp_capabilities','send-key','input-send-event') for frame in frames))
                if operation == 'dash':
                    key = next(frame for frame in frames if frame['execute'] == 'send-key')
                    self.assertEqual([value['data'] for value in key['arguments']['keys']], ['meta_l','f6'])
                elif operation == 'drag':
                    events = [event for frame in frames if frame['execute']=='input-send-event' for event in frame['arguments']['events']]
                    self.assertEqual([event['data']['down'] for event in events if event['type']=='btn'], [True, False])
                    self.assertTrue(all(0 <= event['data']['value'] <= 32767 for event in events if event['type']=='abs'))
                else: self.assertEqual(frames, [])

    def test_native_probe_accepts_canonical_real_run_identity(self):
        import os, shutil
        if not shutil.which('gjs'): self.skipTest('native GJS is not installed')
        source = (ROOT / 'tests/vm/guest/extension-probe.js').read_text()
        self.assertIn('app.run([]);', source)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'probe.js').write_text(source); (root / 'probe.js').chmod(0o500)
            # Native imports/constructors and exact identity validation, without activating GTK or a bus.
            program = source.replace('app.run([]);', 'print("IDENTITY_NATIVE_PASS GUI_NOT_RUN");')
            (root / 'identity.js').write_text(program); (root / 'identity.js').chmod(0o500)
            environment = {'PATH':os.environ.get('PATH','/usr/bin'), 'HOME':directory, 'LANG':'C.UTF-8',
                           'XDG_CONFIG_HOME':directory,'XDG_DATA_HOME':directory,'XDG_CACHE_HOME':directory,
                           'GDK_BACKEND':'wayland'}
            for identity, accepted in [('marble-20261009T010203Z-12345678',True),
                                       ('marble-20261009t010203z-12345678',False), ('fixture',False)]:
                result = subprocess.run(['gjs','-m',str(root / 'identity.js'),directory,identity,'upgrade'],
                    capture_output=True,text=True,env=environment,timeout=10)
                self.assertEqual(result.returncode == 0, accepted, result.stderr)
                if accepted: self.assertIn('IDENTITY_NATIVE_PASS GUI_NOT_RUN',result.stdout)
                else: self.assertIn('Invalid probe identity',result.stderr)

    def test_gnome51_inputs_are_mandatory_only_for_main_staged_marble(self):
        script = ('set -euo pipefail\ninput_mode="$1" scenario_id="$2" gnome51_upgrade_inputs="$3"\n'
                  'gnome51_upgrade_manifest_sha256="$4" gnome51_upgrade_manifest_supplied="$5"\n'
                  'die(){ echo "$*" >&2; return 1; }\n' +
                  self.host_function('validate_gnome51_upgrade_input_scope') +
                  '\nvalidate_gnome51_upgrade_input_scope\n')
        main = 'marble-gnome-btrfs-luks2-plymouth-systemdboot'; digest = 'a' * 64
        with tempfile.TemporaryDirectory() as directory:
            for mode, scenario, supplied, hash_value, flag, accepted in [
                    ('staged', main, directory, digest, 'true', True),
                    ('staged', main, directory, '-', 'false', False),
                    ('staged', main, directory, 'malformed', 'true', False),
                    ('staged', main, '', digest, 'true', False),
                    ('public', main, directory, digest, 'true', False),
                    ('public', main, '', '-', 'false', True),
                    ('public', main, '', digest, 'true', False),
                    ('public', main, '', '-', 'true', False),
                    ('staged', 'stock-gnome-ext4-systemdboot', directory, digest, 'true', False),
                    ('staged', main + '-stock-gdm', directory, digest, 'true', False),
                    ('staged', main, 'relative', digest, 'true', False)]:
                result = subprocess.run(['bash', '-c', script, 'fixture', mode, scenario, supplied, hash_value, flag],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def test_gnome51_loader_passes_external_digest_before_and_after_copy(self):
        import hashlib, json
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); module_dir = root / 'tests/vm'; module_dir.mkdir(parents=True)
            (module_dir / 'prepare-gnome51-upgrade-inputs.py').write_text(
                'import hashlib, pathlib\n'
                'def verify_inputs(root, directory, expected_manifest_sha256):\n'
                '    with (root / "calls.txt").open("a") as output: output.write(str(directory) + "\\n")\n'
                '    raw = (directory / "manifest.json").read_bytes()\n'
                '    assert hashlib.sha256(raw).hexdigest() == expected_manifest_sha256, "trusted digest mismatch"\n')
            inputs = root / 'inputs'; inputs.mkdir(); server = root / 'server'; server.mkdir()
            original = {'files': {'aur/package.pkg.tar.zst': {'sha256': 'a' * 64, 'size': 1}}, 'schema': 1}
            raw = (json.dumps(original, sort_keys=True, separators=(',', ':')) + '\n').encode()
            (inputs / 'manifest.json').write_bytes(raw); digest = hashlib.sha256(raw).hexdigest()
            helper = self.host_function('verify_gnome51_upgrade_inputs')
            program = ('set -euo pipefail\nrepository_root="$1" gnome51_upgrade_manifest_sha256="$3"\n' +
                       helper + '\nverify_gnome51_upgrade_inputs "$2"\n')
            valid = subprocess.run(['bash', '-c', program, 'fixture', directory, str(inputs), digest],
                                   capture_output=True, text=True)
            self.assertEqual(valid.returncode, 0, valid.stderr)
            changed = dict(original); changed['files'] = {'aur/package.pkg.tar.zst': {'sha256': 'b' * 64, 'size': 2}}
            (inputs / 'manifest.json').write_text(json.dumps(changed, sort_keys=True, separators=(',', ':')) + '\n')
            altered = subprocess.run(['bash', '-c', program, 'fixture', directory, str(inputs), digest],
                                     capture_output=True, text=True)
            self.assertNotEqual(altered.returncode, 0)  # A valid rehashed self-manifest cannot replace external authority.
            (inputs / 'manifest.json').write_bytes(raw); (root / 'calls.txt').unlink()
            race = ('set -euo pipefail\nrepository_root="$1" gnome51_upgrade_inputs="$1/inputs" '
                    'repository_server_root="$1/server" gnome51_upgrade_manifest_sha256="$2"\n' + helper + '\n' +
                    self.host_function('prepare_gnome51_upgrade_input') + '\n' +
                    'cp(){ command cp "$@"; python3 - "$gnome51_upgrade_inputs/manifest.json" '
                    '"$repository_server_root/gnome51-inputs/manifest.json" <<\'MUTATE\'\n'
                    'import json,pathlib,sys\n'
                    'for name in sys.argv[1:]:\n'
                    ' p=pathlib.Path(name); value=json.loads(p.read_text()); value["schema"]=2; '
                    'p.write_text(json.dumps(value,sort_keys=True,separators=(",",":"))+"\\n")\n'
                    'MUTATE\n}\nprepare_gnome51_upgrade_input\n')
            result = subprocess.run(['bash', '-c', race, 'fixture', directory, digest], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('trusted digest mismatch', result.stderr)
            self.assertEqual((root / 'calls.txt').read_text().splitlines(),
                             [str(inputs), str(server / 'gnome51-inputs')])
            self.assertFalse((root / 'gnome51-extracted').exists())

    def test_gnome51_production_upgrade_requires_real_baseline_and_plain_syu(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory); (state / 'candidate-repository.conf').write_text('signed candidate\n')
            (state / 'candidate-packages.txt').write_text('arch-linux-gnome-extensions 1.0.0-1\n')
            script = ('set -euo pipefail\ngnome51_migration_state="$1" legacy_repository_file="$1/active.conf"\n'
                      'username=vmtest\n' + function('upgrade_gnome51_baseline') + '\n' +
                      'gnome51_require_platform(){ :; }\n'
                      'gnome51_verify_baseline_packages(){ echo baseline-verified; }\n'
                      'pacman(){ printf "pacman"; printf " %s" "$@"; printf "\\n"; }\n'
                      'marble_project_packages(){ echo arch-linux-gnome-extensions; }\n'
                      'installed_package_record_exact(){ echo "$1 1.0.0-1"; }\n'
                      'gnome51_aur_packages(){ echo old-owner; }\n'
                      'package_installed_exact(){ return 1; }\n'
                      'verify_marble_packages(){ echo candidate-verified; }\n'
                      'id(){ echo 1000; }\nrun_in_user_session(){ echo real-session-logout; }\n'
                      'wait_for_named_user_logout(){ :; }\nsystemctl(){ echo greeter-restart; }\n'
                      'wait_for_greeter(){ echo greeter; }\nverify_marble_greeter(){ echo scoped-gdm-verified; }\n'
                      'emit_marble_action_pass(){ echo phase-pass; }\nupgrade_gnome51_baseline\n')
            absent = subprocess.run(['bash', '-c', script, 'fixture', directory], capture_output=True, text=True)
            self.assertNotEqual(absent.returncode, 0)
            self.assertNotIn('pacman', absent.stdout)
            (state / 'baseline-login-proven').touch()
            result = subprocess.run(['bash', '-c', script, 'fixture', directory], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual([line for line in result.stdout.splitlines() if line.startswith('pacman')],
                             ['pacman -Syu --noconfirm --disable-download-timeout'])
            self.assertTrue((state / 'transaction-proven').is_file())
            self.assertTrue((state / 'candidate-gdm-scoped-proven').is_file())
            self.assertLess(result.stdout.index('baseline-verified'), result.stdout.index('pacman'))
            self.assertLess(result.stdout.index('candidate-verified'), result.stdout.index('phase-pass'))

    def test_gnome51_custody_proof_requires_original_files_and_inodes(self):
        import hashlib, json, os
        source = function('verify_gnome51_recovery_login')
        proof = re.search(r"<<'GNOME51_CUSTODY_PY'\n(.*?)\nGNOME51_CUSTODY_PY", source, re.S).group(1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); active = root / 'extensions/no-screenshot-box@screenshot'
            active.mkdir(parents=True); file = active / 'extension.js'; file.write_bytes(b'original')
            info = file.stat(); receipt = root / 'receipt.json'
            receipt.write_text(json.dumps({'hashes': {'extension.js': hashlib.sha256(b'original').hexdigest()},
                                          'identities': {'extension.js': [info.st_dev, info.st_ino]}}))
            def check():
                return subprocess.run(['python3', '-c', proof, str(root), str(receipt)], capture_output=True)
            self.assertNotEqual(check().returncode, 0)  # Still shadows system extension.
            custody = root / ('.arch-linux-marble-custody-' + 'a' * 32); custody.mkdir()
            moved = custody / active.name; os.rename(active, moved)
            self.assertEqual(check().returncode, 0)
            (moved / 'extension.js').write_bytes(b'changed')
            self.assertNotEqual(check().returncode, 0)
            # Allocate while the original is live: ext4 may immediately reuse a freed inode.
            replacement = moved / '.replacement'; replacement.write_bytes(b'original')
            replacement_info = replacement.stat()
            self.assertNotEqual((replacement_info.st_dev, replacement_info.st_ino),
                                (info.st_dev, info.st_ino))
            os.replace(replacement, moved / 'extension.js')
            self.assertNotEqual(check().returncode, 0)  # Matching bytes in replacement inode are insufficient.

    def test_gnome51_baseline_rejects_bundle_and_missing_aur_owner(self):
        import json
        projects = {'arch-linux-keyring': '1.0.0-8', 'arch-linux-marble-shell': '50.0.0-7',
                    'arch-linux-marble-profile': '1.0.0-10', 'arch-linux-marble-gdm': '50.0.0-8',
                    'arch-linux-colloid-icons': '20260829-6', 'arch-linux-colloid-gtk': '20260808-10'}
        aur = ['gnome-shell-extension-blur-my-shell', 'gnome-shell-extension-clipboard-indicator',
               'gnome-shell-extension-dash-to-dock', 'gnome-shell-extension-just-perfection-desktop']
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / 'manifest.json'
            manifest.write_text(json.dumps({'baseline': {'packages': projects},
                'aur': [{'name': name, 'version': '1-1'} for name in aur]}))
            script = ('set -euo pipefail\ngnome51_migration_manifest="$1" mode="$2"\n' +
                      function('gnome51_verify_baseline_packages') + '\n' + function('gnome51_aur_packages') + '\n' +
                      'package_installed_exact(){ [ "$mode" = bundle ]; }\n'
                      'installed_package_version_exact(){\n'
                      '  if [ "$mode" = missing ] && [ "$1" = gnome-shell-extension-blur-my-shell ]; then return 1; fi\n'
                      '  jq -r --arg name "$1" \'(.baseline.packages[$name] // (.aur[] | select(.name == $name) | .version))\' "$gnome51_migration_manifest"; }\n'
                      'verify_package_qkk_zero(){ :; }\n'
                      'pacman(){ case "$1" in -Qq) jq -r ".baseline.packages | keys[]" "$gnome51_migration_manifest";; '
                      '-Qi) echo "Validated By : Signature";; -Ql) echo "/usr/share/gnome-shell/extensions/owned/extension.js";; esac; }\n'
                      'gnome51_verify_baseline_packages\n')
            for mode, accepted in [('exact', True), ('bundle', False), ('missing', False)]:
                result = subprocess.run(['bash', '-c', script, 'fixture', str(manifest), mode],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def test_gnome51_qga_contract_transport_binds_bytes_without_new_arguments(self):
        import base64, hashlib, json
        body = self.host_function('qga_verify')
        request_code = body[body.index('request="$(jq'):body.index('    printf \'%s\\n\' "${request}"')]
        variables = re.findall(r'\$\{([a-z_0-9]+)(?::[^}]*)?\}', request_code)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'guest').mkdir(); (root / 'guest/verify.sh').write_text('exit 0\n')
            contract = b'{"schema":1}\n'; encoded = base64.b64encode(contract).decode()
            script = ('set -euo pipefail\n' + '\n'.join(name + '=fixture' for name in sorted(set(variables))) +
                      '\nscript_dir="$1"\nprobe_contract=\nprobe_hash=-\nupgrade_contract=' + encoded + '\ngnome51_upgrade_manifest_sha256=' +
                      hashlib.sha256(contract).hexdigest() + '\n' + request_code + '\nprintf %s "$request"')
            result = subprocess.run(['bash', '-c', script, 'fixture', directory], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            request = json.loads(result.stdout); self.assertEqual(len(request['arguments']['arg']), 30)
            payload = base64.b64decode(request['arguments']['input-data']).decode()
            destination = root / 'state/manifest.json'
            payload = payload.replace('/var/lib/arch-linux-marble/gnome51-upgrade-manifest.json', str(destination))
            for attempt in range(2):
                execution = subprocess.run(['bash'], input=payload, capture_output=True, text=True)
                self.assertEqual(execution.returncode, 0, execution.stderr)
                self.assertEqual(destination.read_bytes(), contract)
                self.assertEqual(destination.stat().st_mode & 0o777, 0o400)
            destination.chmod(0o600); destination.write_bytes(b'foreign')
            execution = subprocess.run(['bash'], input=payload, capture_output=True, text=True)
            self.assertNotEqual(execution.returncode, 0)
            self.assertEqual(destination.read_bytes(), b'foreign')

    def test_current_repository_metadata_accepts_exact_seven_package_closure(self):
        packages = ['arch-linux-keyring', 'arch-linux-gnome-extensions', 'arch-linux-marble-shell',
                    'arch-linux-colloid-gtk', 'arch-linux-colloid-icons', 'arch-linux-marble-profile',
                    'arch-linux-marble-gdm']
        keys = ['PUBLIC_KEY_SHA256', 'PACKAGE_SET_SHA256', 'SNAPSHOT_SHA256',
                'BUILD_METADATA_SHA256', 'UNSIGNED_MANIFEST_SHA256', 'REPOSITORY_MANIFEST_SHA256',
                'REPOSITORY_MANIFEST_SIGNATURE_SHA256', 'REPOSITORY_DATABASE_SHA256',
                'REPOSITORY_DATABASE_SIGNATURE_SHA256', 'REPOSITORY_FILES_SHA256',
                'REPOSITORY_FILES_SIGNATURE_SHA256']
        rows = [key + '=' + 'a' * 64 for key in keys]
        rows += ['PRIMARY_FINGERPRINT=' + 'B' * 40, 'SIGNING_SUBKEY_FINGERPRINT=' + 'C' * 40]
        rows += ['PACKAGE_SHA256_' + package.upper().replace('-', '_') + '=' + 'd' * 64
                 for package in packages]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'repository').mkdir()
            (root / 'repository/package-set').write_text('\n'.join(packages) + '\n')
            metadata = root / 'metadata.env'
            script = ('set -euo pipefail\nrepository_root="$1"\n'
                      'snapshot_sha256=' + 'a' * 64 + '\nbuild_metadata_sha256=' + 'a' * 64 +
                      '\nunsigned_manifest_sha256=' + 'a' * 64 +
                      '\ndeclare -A repository_package_hashes=()\ndie(){ echo "$*" >&2; exit 1; }\n' +
                      self.host_function('load_marble_repository_metadata') +
                      '\nload_marble_repository_metadata "$2"\nprintf "%s" "${#repository_package_hashes[@]}"\n')
            for label, contents, accepted in [('exact', rows, True), ('missing', rows[:-1], False),
                    ('duplicate', rows + rows[-1:], False), ('unknown', rows + ['FOREIGN=' + 'a' * 64], False)]:
                with self.subTest(label=label):
                    metadata.write_text('\n'.join(contents) + '\n')
                    result = subprocess.run(['bash', '-c', script, 'fixture', str(root), str(metadata)],
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0, accepted, result.stderr)
                    if accepted: self.assertEqual(result.stdout, '7')

    def test_staged_repository_server_routes_all_graphical_profiles_only(self):
        host = (ROOT / 'tests/vm/run.sh').read_text()
        block = re.search(r'^    if .*?; then\n        start_marble_repository_runtime\n    fi', host, re.M).group(0)
        helpers = self.host_function('is_marble_scenario')
        predicate = re.search(r'^scenario_needs_repository\(\) \{\n.*?^\}', host, re.M | re.S)
        if predicate: helpers += '\n' + predicate.group(0)
        script = ('set -euo pipefail\nscenario_id="$1" input_mode="$2"\n' + helpers +
                  '\nstart_marble_repository_runtime(){ printf served; }\n' + block)
        graphical = ['stock-gnome-ext4-systemdboot', 'stock-gnome-btrfs-systemdboot',
                     'stock-gnome-btrfs-grub', 'stock-gnome-btrfs-luks2-plymouth-systemdboot',
                     'stock-gnome-btrfs-luks2-plymouth-grub',
                     'marble-gnome-btrfs-luks2-plymouth-systemdboot',
                     'marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm']
        for scenario in graphical + ['minimal-ext4-systemdboot', 'minimal-dualboot-ext4-systemdboot',
                                      'stock-gnome-unknown', 'marble-gnome-unknown']:
            for mode in ('staged', 'public'):
                with self.subTest(scenario=scenario, mode=mode):
                    result = subprocess.run(['bash', '-c', script, 'fixture', scenario, mode],
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, 'served' if mode == 'staged' and scenario in graphical else '')

    def test_marble_package_closure_includes_neutral_extension_bundle(self):
        script = 'set -euo pipefail\n' + function('marble_gdm_enabled') + '\n' + function('marble_project_packages')
        for scenario, gdm in [('marble-gnome-btrfs-luks2-plymouth-systemdboot', True),
                              ('marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm', False)]:
            result = subprocess.run(['bash', '-c', script + '\nscenario="$1"\nmarble_project_packages',
                                     'fixture', scenario], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            expected = ['arch-linux-keyring', 'arch-linux-gnome-extensions', 'arch-linux-marble-shell',
                        'arch-linux-colloid-gtk', 'arch-linux-colloid-icons', 'arch-linux-marble-profile']
            if gdm: expected.append('arch-linux-marble-gdm')
            self.assertEqual(result.stdout.splitlines(), expected)

    def test_theme_removal_keeps_keyring_and_neutral_extensions(self):
        branch = function('run_marble_phase').split('    remove-marble)\n', 1)[1].split('        ;;', 1)[0]
        helpers = function('marble_project_packages') + '\n' + function('marble_gdm_enabled')
        candidate = re.search(r'^marble_theme_packages\(\) \{\n.*?^\}', VERIFY.read_text(), re.M | re.S)
        if candidate: helpers += '\n' + candidate.group(0)
        with tempfile.TemporaryDirectory() as temporary:
            branch = branch.replace('/usr/share/arch-linux-marble', temporary + '/absent-theme')
            branch = branch.replace('/home/${username}', temporary + '/absent-home')
            script = ('set -euo pipefail\nscenario=marble-gnome-btrfs-luks2-plymouth-systemdboot\nusername=fixture\n' +
                      helpers + '\n' + '''
pacman(){
 if [ "$1" = -Rns ]; then
  shift 2
  for package in "$@"; do
   case "$package" in arch-linux-keyring | arch-linux-gnome-extensions) return 93 ;; esac
   printf 'REMOVE:%s\n' "$package"
  done
 elif [ "$1" = -Qq ]; then printf '%s\n' arch-linux-keyring arch-linux-gnome-extensions
 else return 1; fi
}
verify_stock_project_packages(){ :; }
verify_package_qkk_zero(){ :; }
restart_gdm_after_profile_transition(){ :; }
emit_marble_action_pass(){ :; }
''' + branch)
            result = subprocess.run(['bash', '-c', script], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['REMOVE:arch-linux-marble-shell',
                'REMOVE:arch-linux-colloid-gtk', 'REMOVE:arch-linux-colloid-icons',
                'REMOVE:arch-linux-marble-profile', 'REMOVE:arch-linux-marble-gdm'])

    def test_vendor_integrity_chooses_reviewed_gdm_manifest_for_installed_shell(self):
        helpers = function('verify_vendor_integrity')
        candidate = re.search(r'^marble_gdm_major\(\) \{\n.*?^\}', VERIFY.read_text(), re.M | re.S)
        if candidate: helpers += '\n' + candidate.group(0)
        script = ('set -euo pipefail\nrun_id=fixture phase=fixture\n' + helpers + '\n' + '''
installed_package_version_exact(){ printf '%s' "$fixture_version"; }
marble_gdm_enabled(){ return 0; }
verify_package_qkk_zero(){ :; }
sha256sum(){ printf 'MANIFEST:%s\n' "$3" >&2; }
pacman(){ if [[ "$2" = */gnome-shell-theme.gresource ]]; then printf 'fixture is owned by gnome-shell 1'; else printf 'fixture is owned by gdm 1'; fi; }
verify_vendor_integrity
''')
        import os
        for version, major in (('1:50.5-1', '50'), ('1:51.0-1', '51'), ('51.0-1', '51'),
                               ('1:52.0-1', '52')):
            with self.subTest(version=version):
                result = subprocess.run(['bash', '-c', script], env={**os.environ, 'fixture_version': version},
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, major in ('50', '51'), result.stderr)
                if major in ('50', '51'):
                    self.assertIn('MANIFEST:/usr/share/arch-linux-marble-gdm/known-gnome-' + major + '.sha256', result.stderr)

    def test_stock_project_package_guard_accepts_bundle_but_rejects_themes(self):
        import hashlib, os
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            extensions = root / 'extensions'; extensions.mkdir()
            (extensions / 'payload').write_bytes(b'reviewed extension fixture')
            manifest = root / 'extensions.sha256'
            manifest.write_text(hashlib.sha256(b'reviewed extension fixture').hexdigest() + '  payload\n')
            helper = function('verify_stock_project_packages').replace('/usr/share/gnome-shell/extensions', str(extensions))
            helper = helper.replace('/usr/share/arch-linux-gnome-extensions/extensions.sha256', str(manifest))
            helpers = '\n'.join(function(name) for name in ('installed_package_record_exact', 'package_installed_exact'))
            script = 'set -euo pipefail\n' + helpers + '\n' + helper + '\n' + '''
pacman(){
 if [ "$1" = -Qq ]; then printf '%s\n' "$fixture_packages"
 elif [ "$1" = -Q ] && [ "$2" = -- ]; then
  grep -Fxq "$3" <<<"$fixture_packages" || return 1
  printf '%s 1.0-1\n' "$3"
 else return 1; fi
}
verify_package_qkk_zero(){ [ "$*" = 'arch-linux-keyring arch-linux-gnome-extensions' ]; }
verify_stock_project_packages
'''
            packages = 'arch-linux-keyring\narch-linux-gnome-extensions'
            for contents, accepted in [(packages, True), (packages + '\narch-linux-marble-shell', False),
                                      (packages + '\narch-linux-marble-gdm', False), ('arch-linux-keyring', False),
                                      (packages + '\narch-linux-foreign', False)]:
                with self.subTest(packages=contents):
                    result = subprocess.run(['bash', '-c', script],
                        env={**os.environ, 'fixture_packages': contents}, capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0, accepted, result.stderr)
            (extensions / 'payload').write_bytes(b'changed extension bytes')
            result = subprocess.run(['bash', '-c', script], env={**os.environ, 'fixture_packages': packages},
                                    capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)

    def test_host_retains_exact_twenty_five_object_seven_package_manifest(self):
        import json
        packages = ['arch-linux-keyring', 'arch-linux-gnome-extensions', 'arch-linux-marble-shell',
                    'arch-linux-colloid-gtk', 'arch-linux-colloid-icons', 'arch-linux-marble-profile',
                    'arch-linux-marble-gdm']
        names = ['arch-linux.db', 'arch-linux.db.sig', 'arch-linux.db.tar.gz', 'arch-linux.db.tar.gz.sig',
                 'arch-linux.files', 'arch-linux.files.sig', 'arch-linux.files.tar.gz', 'arch-linux.files.tar.gz.sig',
                 'arch-linux.gpg', 'primary-fingerprint', 'signing-subkey-fingerprint']
        for package in packages:
            names.extend([package + '-1.0-1-any.pkg.tar.zst', package + '-1.0-1-any.pkg.tar.zst.sig'])
        metadata = {'schema': 2, 'architecture': 'x86_64', 'repository': 'arch-linux', 'releaseVersion': '1.2.3',
                    'sourceCommit': 'a' * 40, 'sourceTree': 'b' * 40, 'sourceDateEpoch': 1}
        for field in ('installerSha256', 'packageSetSha256', 'buildMetadataSha256', 'unsignedManifestSha256'):
            metadata[field] = 'c' * 64
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'repository').mkdir(); (root / 'evidence').mkdir()
            (root / 'repository/package-set').write_text('\n'.join(packages) + '\n')
            manifest = root / 'manifest.json'; signature = root / 'signature'; signature.write_text('fixture signature')
            setup = ('set -euo pipefail\nrepository_root="$1" run_root="$1" evidence="$1/evidence"\n'
                     'release_version=1.2.3 source_commit=' + 'a' * 40 + ' source_tree=' + 'b' * 40 + '\n')
            for field in ('installer_sha256', 'repository_package_set_sha256', 'build_metadata_sha256', 'unsigned_manifest_sha256'):
                setup += field + '=' + 'c' * 64 + '\n'
            setup += ('repository_manifest_sha256=- repository_database_sha256=-\n'
                      'declare -A repository_package_hashes=()\ndie(){ echo "$*" >&2; exit 1; }\n'
                      'verify_retained_manifest_signature(){ :; }\n')
            script = setup + self.host_function('repository_hash_from_tsv_from') + '\n' + self.host_function('retain_repository_manifest')
            script += '\nretain_repository_manifest "$1/manifest.json" "$1/signature"\n'
            metadata['files'] = [{'name': name, 'sha256': 'd' * 64, 'size': 1} for name in sorted(names)]
            manifest.write_text(json.dumps(metadata))
            result = subprocess.run(['bash', '-c', script, 'fixture', temporary], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len((root / 'evidence/repository-objects.tsv').read_text().splitlines()), 25)

    def test_guest_installer_acceptance_environment_routes_graphical_profiles(self):
        bootstrap = (ROOT / 'tests/vm/guest/bootstrap.sh').read_text()
        predicate = re.search(r'^scenario_needs_repository\(\) \{\n.*?^\}', bootstrap, re.M | re.S).group(0)
        stage = bootstrap.split("# Match the official Arch ISO root shell.", 1)[1]
        branch = re.search(r'^        if .*?^        fi', stage, re.M | re.S).group(0)
        script = ('set -euo pipefail\ndeclare -A IDENTITY=([SCENARIO]="$1" [INPUT_MODE]="$2")\n'
                  'work_root=/fixture\n' + predicate + '\n' +
                  'bash(){ printf "%s:%s" "${ARCH_LINUX_QEMU_ACCEPTANCE:-false}" "${ARCH_LINUX_QEMU_REPOSITORY_CONTRACT:-none}"; }\n' + branch)
        for scenario in ('stock-gnome-ext4-systemdboot', 'marble-gnome-btrfs-luks2-plymouth-systemdboot',
                         'minimal-ext4-systemdboot', 'stock-gnome-unknown'):
            for mode in ('staged', 'public'):
                with self.subTest(scenario=scenario, mode=mode):
                    result = subprocess.run(['bash', '-c', script, 'fixture', scenario, mode],
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    repository = mode == 'staged' and scenario in ('stock-gnome-ext4-systemdboot',
                                                                  'marble-gnome-btrfs-luks2-plymouth-systemdboot')
                    self.assertEqual(result.stdout, 'true:/fixture/repository.contract' if repository else 'false:none')

    def test_gdm_process_uses_exact_major_payload_and_rejects_stale_environment(self):
        import os
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            override = root / 'etc/systemd/user/org.gnome.Shell@gdm.service.d/50-arch-linux-marble-gdm.conf'
            override.parent.mkdir(parents=True)
            process = root / 'proc/44'; process.mkdir(parents=True)
            payload_root = root / 'usr/share/arch-linux-marble-gdm'
            (payload_root / 'systemd').mkdir(parents=True)
            helper = root / 'helper'; helper.write_text('#!/bin/sh\nprintf active\n'); helper.chmod(0o755)
            body = function('verify_marble_gdm_process')
            body = body.replace('/usr/lib/arch-linux-marble-gdm/update-compatibility', str(helper))
            for prefix in ('/etc/systemd', '/usr/share/arch-linux-marble-gdm', '/proc/'):
                body = body.replace(prefix, temporary + prefix)
            script = 'set -euo pipefail\n' + function('marble_gdm_major') + '\n' + body + '\n' + '''
installed_package_version_exact(){ printf '1:%s.0-1' "$fixture_major"; }
gdm_shell_pid(){ printf 44; }
gsettings(){ [ "$DCONF_PROFILE" = "$fixture_profile" ]; printf "'Colloid-Dark'"; }
verify_marble_gdm_process active fixture
'''
            for major, environment_major, accepted in [('50', '50', True), ('51', '51', True),
                                                       ('51', '50', False), ('52', '51', False)]:
                with self.subTest(major=major, environment_major=environment_major):
                    payload = payload_root / ('systemd/' + major + '-arch-linux-marble-gdm.conf')
                    payload.write_text('fixture')
                    if override.is_symlink(): override.unlink()
                    override.symlink_to(payload)
                    profile = str(payload_root / (environment_major + '.0.0/dconf/profile'))
                    environment = ('G_RESOURCE_OVERLAYS=/org/gnome/shell/theme=' + str(payload_root / (environment_major + '.0.0/theme')) +
                                   '\0DCONF_PROFILE=' + profile + '\0').encode()
                    (process / 'environ').write_bytes(environment)
                    result = subprocess.run(['bash', '-c', script],
                        env={**os.environ, 'fixture_major': major, 'fixture_profile': profile},
                        capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def qga_partial_transport(self, short_sync=False, peer_mismatch=False):
        import base64, io, json, os, runpy, socket, struct
        from unittest.mock import patch
        client = ROOT / "tests/vm/qga-client.py"
        script_bytes = VERIFY.read_bytes()
        request = {"execute": "guest-exec", "arguments": {"path": "/usr/bin/bash", "arg": ["-c", "exec 3<&0; exec /usr/bin/bash /dev/fd/3"], "input-data": base64.b64encode(script_bytes).decode(), "capture-output": True}}
        frames = []
        class Connection:
            def __init__(self): self.pending = bytearray(); self.responses = []; self.timeouts = []
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def settimeout(self, value): self.timeouts.append(value)
            def connect(self, path): pass
            def getsockopt(self, *args): return struct.pack("3i", os.getpid() + int(peer_mismatch), os.getuid(), os.getgid())
            def makefile(self, *args, **kwargs): return self
            def send(self, data):
                limit = 17 if short_sync else (len(data) if not frames else 4096)
                data = data[:limit]; self.pending.extend(data)
                while b"\n" in self.pending:
                    line, _, remainder = self.pending.partition(b"\n"); self.pending = bytearray(remainder)
                    frame = json.loads(line); frames.append(frame)
                    if frame["execute"] == "guest-sync-delimited": response = {"return": frame["arguments"]["id"]}
                    else: response = {"id": frame["id"], "return": {"pid": 42}}
                    self.responses.append(json.dumps(response).encode() + b"\n")
                return len(data)
            def sendall(self, data):
                while data: data = data[self.send(data):]
            def write(self, data): return self.send(data)
            def readline(self, size):
                if not self.responses: raise TimeoutError("partial frame has no newline")
                return self.responses.pop(0)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "qga.sock"
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                server.bind(str(path)); metadata = path.lstat()
                connection = Connection(); output = io.StringIO(); errors = io.StringIO()
                import contextlib
                with patch("socket.socket", return_value=connection), patch("sys.argv", [str(client), str(path), str(os.getpid()), f"{metadata.st_dev}:{metadata.st_ino}"]), patch("sys.stdin", io.StringIO(json.dumps(request))), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                    runpy.run_path(str(client), run_name="__main__")
        return frames, connection, output.getvalue(), script_bytes

    def test_actual_qga_client_completes_partial_sync_and_large_guest_request(self):
        import base64, json
        for short_sync in (False, True):
            with self.subTest(short_sync=short_sync):
                frames, connection, output, script = self.qga_partial_transport(short_sync)
                self.assertEqual(len(frames), 2)
                self.assertEqual(frames[0]["execute"], "guest-sync-delimited")
                self.assertEqual(base64.b64decode(frames[1]["arguments"]["input-data"]), script)
                self.assertGreater(len(json.dumps(frames[1])), 128 * 1024)
                self.assertEqual(json.loads(output)["id"], frames[1]["id"])
                self.assertEqual(connection.timeouts, [30])
                self.assertEqual(connection.pending, b"")

    def test_actual_qga_client_partial_fixture_still_rejects_wrong_peer(self):
        with self.assertRaises(SystemExit) as failure:
            self.qga_partial_transport(peer_mismatch=True)
        self.assertEqual(failure.exception.code, 1)

    def snapshot_reader(self):
        match = re.search(r"^snapshot_overlay_reader_program\(\) \{\n.*?<<'SNAPSHOT_READER_PY'\n(.*?)\nSNAPSHOT_READER_PY\n", VERIFY.read_text(), re.M | re.S)
        self.assertIsNotNone(match, "actual root-relative snapshot reader missing")
        namespace = {"__name__": "snapshot_reader_fixture"}
        exec(compile(match.group(1), "actual-snapshot-reader", "exec"), namespace)
        return namespace, match.group(1)

    def reader_marker(self, root, contents=None, mode=0o600):
        import os
        run = "grub-20261004T000000Z-aabbccdd"
        path = root / "marker"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
        try:
            os.write(fd, (run + "\n").encode() if contents is None else contents)
        finally:
            os.close(fd)
        return run, path

    def test_snapshot_reader_real_root_relative_read(self):
        namespace, _ = self.snapshot_reader()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); run, _ = self.reader_marker(root)
            self.assertEqual(namespace["read_marker"](run, root_path=str(root), relative="marker"), (run + "\n").encode())

    def test_snapshot_reader_symlink_file_and_parent_reject(self):
        namespace, _ = self.snapshot_reader()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); run, path = self.reader_marker(root)
            (root / "link").symlink_to(path)
            (root / "parent").symlink_to(root, target_is_directory=True)
            for relative in ("link", "parent/marker"):
                with self.subTest(relative=relative), self.assertRaises(OSError):
                    namespace["read_marker"](run, root_path=str(root), relative=relative)

    def test_snapshot_reader_actual_mount_crossing_reject(self):
        import errno
        namespace, _ = self.snapshot_reader()
        with self.assertRaises(OSError) as caught:
            namespace["read_marker"]("grub-20261004T000000Z-aabbccdd", relative="proc/version")
        self.assertEqual(caught.exception.errno, errno.EXDEV)

    def test_snapshot_reader_unsafe_metadata_reject(self):
        import os
        from contextlib import ExitStack
        from unittest.mock import patch
        namespace, _ = self.snapshot_reader()
        for case in ("writable", "hardlink", "directory"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                run, path = self.reader_marker(root)
                if case == "hardlink": os.link(path, root / "second")
                if case == "directory": path.unlink(); path.mkdir()
                real_fstat = os.fstat
                def writable_metadata(fd):
                    fields = list(real_fstat(fd)); fields[0] |= 0o022
                    return os.stat_result(fields)
                with ExitStack() as stack:
                    if case == "writable": stack.enter_context(patch.object(namespace["os"], "fstat", writable_metadata))
                    with self.assertRaises(ValueError): namespace["read_marker"](run, root_path=str(root), relative="marker")

    def test_snapshot_reader_exact_dynamic_bytes_and_eof(self):
        namespace, _ = self.snapshot_reader()
        run = "grub-20261004T000000Z-aabbccdd"
        for contents in ((run + "x\n").encode(), run.encode(), (run.replace("aabb", "ccdd") + "\n").encode()):
            with self.subTest(contents=contents), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); self.reader_marker(root, contents)
                with self.assertRaises(ValueError): namespace["read_marker"](run, root_path=str(root), relative="marker")

    def test_snapshot_reader_unsupported_syscall_has_no_fallback(self):
        import errno
        from unittest.mock import patch
        namespace, _ = self.snapshot_reader()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); run, _ = self.reader_marker(root)
            with patch.object(namespace["libc"], "syscall", return_value=-1), patch.object(namespace["ctypes"], "get_errno", return_value=errno.ENOSYS):
                with self.assertRaises(OSError) as caught:
                    namespace["read_marker"](run, root_path=str(root), relative="marker")
                self.assertEqual(caught.exception.errno, errno.ENOSYS)

    def test_snapshot_reader_mount_identity_change_reject(self):
        from unittest.mock import patch
        namespace, _ = self.snapshot_reader()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); run, _ = self.reader_marker(root)
            with patch.dict(namespace, {"mount_id": lambda fd: fd}):
                with self.assertRaises(ValueError): namespace["read_marker"](run, root_path=str(root), relative="marker")

    def test_snapshot_reader_changed_identity_after_read_reject(self):
        import os
        from unittest.mock import patch
        namespace, _ = self.snapshot_reader()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); run, path = self.reader_marker(root)
            original_read = os.read
            previous = path.stat()
            def changed_read(fd, count):
                data = original_read(fd, count)
                os.utime(path, ns=(previous.st_atime_ns, previous.st_mtime_ns + 1000000000))
                return data
            with patch.object(namespace["os"], "read", changed_read):
                with self.assertRaises(ValueError): namespace["read_marker"](run, root_path=str(root), relative="marker")

    def test_snapshot_reader_cli_error_is_controlled(self):
        _, source = self.snapshot_reader()
        result = subprocess.run(["python3", "-B", "-I", "-S", "-", "SECRET_INVALID_RUN"], input=source, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "SNAPSHOT_OVERLAY_READER_FAIL reason=read\n")

    def snapshot_program(self, name, marker):
        text = VERIFY.read_text()
        match = re.search(r"^" + name + r"\(\) \{\n.*?<<'" + marker + r"'\n(.*?)\n" + marker + r"\n", text, re.M | re.S)
        self.assertIsNotNone(match, "actual snapshot program missing: " + name)
        return match.group(1)

    def snapshot_proof(self):
        namespace = {"__name__": "snapshot_proof_fixture"}
        exec(compile(self.snapshot_program("snapshot_backing_checker_program", "SNAPSHOT_CHECKER_PY"), "actual-snapshot-consumer", "exec"), namespace)
        return namespace

    def proof_fixture(self, event=1):
        run = "grub-20261004T000000Z-aabbccdd"
        expected = {"markerInode": 1234, "rootId": 257, "fsUuid": "12345678-1234-1234-1234-123456789abc", "readOnly": True, "markerText": run + "\n", "major": 254, "minor": 2}
        common = "event=1 start=0 count=32 end=31 retval=31 valid=1 stable=1" if event == 1 else "event=2 start=31 count=1 end=31 retval=0 valid=1 stable=1"
        groups = {"CORE": "inode=1234 root_id=257 ro=1", "UUID_A": "fsid=1234567812341234", "UUID_B": "fsid=1234123456789abc", "MOUNT_DEVICE": "mount_ro=1 major=254 minor=2 dev_major=254 dev_minor=2", "FS_STATE": "num_devices=1 open_devices=1 total_devices=1 missing_devices=0 seeding=0 temp_fsid=0 seed_empty=1", "DEV_STATE": "device_link=1 device_clean=1"}
        rows = ["QA_OVERLAY_BPF_" + group + " " + common + " " + fields for group, fields in groups.items()]
        return expected, rows

    def proof_output(self, rows):
        return ("\n".join(["QA_OVERLAY_BPF_ATTACHED schema=1", "grub-20261004T000000Z-aabbccdd", *rows, "QA_OVERLAY_BPF_COMPLETE schema=1 pending=0"]) + "\n").encode()

    def test_snapshot_observed_proof_actual_consumer_positive_and_reordered(self):
        namespace = self.snapshot_proof(); expected, rows = self.proof_fixture()
        self.assertEqual(namespace["verify"]("positive", self.proof_output(rows), b"", expected, 0), (1, 0))
        _, eof = self.proof_fixture(2)
        self.assertEqual(namespace["verify"]("positive", self.proof_output(list(reversed(rows + eof))), b"", expected, 0), (1, 1))

    def test_snapshot_proof_refuses_copyup_wrong_physical_ro_and_mixed_groups(self):
        namespace = self.snapshot_proof(); expected, rows = self.proof_fixture(); _, eof = self.proof_fixture(2)
        cases = [[], rows[:-1], rows + [rows[1]], [rows[0], eof[1].replace("event=2", "event=1"), *rows[2:]]]
        for field, bad in (("mount_ro", "0"), ("major", "253"), ("minor", "3"), ("num_devices", "2"), ("missing_devices", "1"), ("seed_empty", "0"), ("device_link", "0"), ("device_clean", "0"), ("valid", "0"), ("stable", "0"), ("root_id", "256"), ("inode", "1235"), ("ro", "0")):
            cases.append([re.sub(r"(?<![a-z_])" + field + r"=[0-9]+", field + "=" + bad, row) for row in rows])
        for case in cases:
            with self.subTest(case=case), self.assertRaises(namespace["ProofError"]):
                namespace["verify"]("positive", self.proof_output(case), b"", expected, 0)

    def test_snapshot_proof_native_warning_drop_controls_and_bounds(self):
        namespace = self.snapshot_proof(); expected, rows = self.proof_fixture(); good = self.proof_output(rows)
        for status, stderr in ((1, b""), (124, b""), (0, b"WARNING SECRET"), (0, b"Lost events")):
            with self.subTest(status=status, stderr=stderr), self.assertRaises(namespace["ProofError"]):
                namespace["verify"]("positive", good, stderr, expected, status)
        for raw in (good.replace(b"pending=0", b"pending=1"), good + b"SECRET_UNKNOWN\n", good + b"QA_OVERLAY_BPF_ATTACHED schema=1\n", b"x" * 65537):
            with self.assertRaises(namespace["ProofError"]): namespace["verify"]("positive", raw, b"", expected, 0)

    def snapshot_state(self):
        namespace = {"__name__": "snapshot_state_fixture"}
        exec(compile(self.snapshot_program("snapshot_state_program", "SNAPSHOT_STATE_PY"), "actual-snapshot-state", "exec"), namespace)
        run = "grub-20261004T000000Z-aabbccdd"
        fields = {"run_id": run, "subvol": "@snapshots/qa-" + run, "root_uuid": "11111111-1111-1111-1111-111111111111", "normal_boot_id": "22222222-2222-2222-2222-222222222222", "root_device": "/dev/vda2", "root_partuuid": "33333333-3333-3333-3333-333333333333", "selector_sha256": "a" * 64, "production_cfg_sha256": "b" * 64, "snapshot_root_id": "257", "snapshot_marker_inode": "1234", "root_major": "254", "root_minor": "2"}
        raw = "".join(key + "=" + value + "\n" for key, value in fields.items()).encode()
        return namespace, fields, raw

    def test_snapshot_state_actual_twelve_field_closure(self):
        namespace, fields, raw = self.snapshot_state()
        self.assertEqual(namespace["parse_state"](raw, fields["run_id"], fields["subvol"]), fields)
        cases = [raw + b"root_major=254\n", raw.replace(b"root_major=", b"UNKNOWN="), raw.replace(b"snapshot_root_id=257\n", b""), raw[:-1], b"x" * 4097]
        for field, bad in (("snapshot_root_id", "0"), ("snapshot_marker_inode", "18446744073709551616"), ("root_major", "0"), ("root_major", "4096"), ("root_minor", "1048576"), ("root_minor", "02"), ("root_device", "SECRET PATH"), ("normal_boot_id", "SECRET")):
            cases.append(raw.replace((field + "=" + fields[field]).encode(), (field + "=" + bad).encode()))
        for case in cases:
            with self.subTest(case=case), self.assertRaises((ValueError, UnicodeError)):
                namespace["parse_state"](case, fields["run_id"], fields["subvol"])

    def test_snapshot_state_fd_owner_symlink_change_and_read_atime(self):
        import os
        from unittest.mock import patch
        namespace, fields, raw = self.snapshot_state()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "state"; path.write_bytes(raw); path.chmod(0o600)
            (Path(temporary) / "link").symlink_to(path)
            with self.assertRaises(OSError): namespace["load_state"](str(Path(temporary) / "link"), fields["run_id"], fields["subvol"])
            original = os.fstat
            def root_metadata(fd):
                value = list(original(fd)); value[4] = 0
                return os.stat_result(value)
            with patch.object(namespace["os"], "fstat", root_metadata):
                self.assertEqual(namespace["load_state"](str(path), fields["run_id"], fields["subvol"]), fields)
            def unsafe_metadata(fd):
                value = list(original(fd)); value[4] = 0; value[0] |= 0o022
                return os.stat_result(value)
            with patch.object(namespace["os"], "fstat", unsafe_metadata), self.assertRaises(ValueError):
                namespace["load_state"](str(path), fields["run_id"], fields["subvol"])

    def test_snapshot_runtime_rejects_failed_empty_unit_query(self):
        result = self.snapshot_runtime(changed="failed-query")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("query=failed count=unavailable unknown_count=unavailable", result.stderr)
        self.assertTrue(result.stderr.endswith("reason=failed-units\n"))

    def test_snapshot_unit_actual_helper_classifies_only_fixed_public_values(self):
        import contextlib, io
        namespace = {"__name__": "snapshot_unit_fixture"}
        exec(compile(self.snapshot_program("snapshot_unit_program", "SNAPSHOT_UNIT_PY"), "actual-snapshot-units", "exec"), namespace)
        run = "grub-20261004T000000Z-aabbccdd"
        properties = b"Result=exit-code\nExecMainCode=1\nExecMainStatus=32\n"
        def query(args):
            return (True, b"systemd-remount-fs.service loaded failed failed SECRET_DESCRIPTION\n") if "--failed" in args else (True, properties)
        output = io.StringIO()
        with contextlib.redirect_stderr(output): self.assertEqual(namespace["inspect_units"](run, "snapshot-prelogin", query), 1)
        self.assertEqual(output.getvalue().splitlines(), [
            "SNAPSHOT_UNIT_DIAGNOSTIC run_id=" + run + " phase=snapshot-prelogin query=success count=1 unknown_count=0",
            "SNAPSHOT_UNIT_DIAGNOSTIC run_id=" + run + " phase=snapshot-prelogin unit=systemd-remount-fs result=exit-code code=exited status=32"])
        self.assertNotIn("SECRET", output.getvalue())

    def test_snapshot_unit_actual_helper_query_unknown_malformed_and_empty(self):
        import contextlib, io
        namespace = {"__name__": "snapshot_unit_fixture"}
        exec(compile(self.snapshot_program("snapshot_unit_program", "SNAPSHOT_UNIT_PY"), "actual-snapshot-units", "exec"), namespace)
        run = "grub-20261004T000000Z-aabbccdd"
        for success, raw, category in ((True, b"", ""), (False, b"", "failed"), (False, b"SECRET", "failed"), (True, b"SECRET_RAW_LINE", "malformed"), (True, b" \n", "malformed"), (True, b"x" * 4096, "malformed"), (True, b"gdm.service.SECRET loaded failed failed SECRET_MESSAGE\n", "success"), (True, b"unknown.service loaded failed failed SECRET_MESSAGE\n", "success"), (True, b"gdm.service loaded failed failed x\ngdm.service loaded failed failed x\n", "malformed"), (True, b"gdm.service loaded active running x\n", "malformed")):
            output = io.StringIO()
            with self.subTest(raw=raw), contextlib.redirect_stderr(output):
                status = namespace["inspect_units"](run, "snapshot-login", lambda args: (success, raw))
            self.assertEqual(status, 1 if category else 0)
            self.assertNotIn("SECRET", output.getvalue()); self.assertNotIn("unknown.service", output.getvalue())
            if category: self.assertIn("query=" + category, output.getvalue())
            else: self.assertEqual(output.getvalue(), "")
        output = io.StringIO()
        with contextlib.redirect_stderr(output):
            self.assertEqual(namespace["inspect_units"]("SECRET_RUN", "snapshot-login", lambda args: (True, b"")), 1)
            self.assertEqual(namespace["inspect_units"](run, "SECRET_PHASE", lambda args: (True, b"")), 1)
        self.assertEqual(output.getvalue(), "")

    def test_snapshot_unit_actual_helper_properties_and_native_caps(self):
        import contextlib, io, sys
        namespace = {"__name__": "snapshot_unit_fixture"}
        exec(compile(self.snapshot_program("snapshot_unit_program", "SNAPSHOT_UNIT_PY"), "actual-snapshot-units", "exec"), namespace)
        run = "grub-20261004T000000Z-aabbccdd"
        for success, raw in ((False, b""), (True, b"Result=SECRET\nExecMainCode=SECRET\nExecMainStatus=SECRET\n"), (True, b"Result=exit-code\nResult=success\nExecMainCode=1\nExecMainStatus=32\n")):
            output = io.StringIO()
            def query(args): return (True, b"gdm.service loaded failed failed SECRET\n") if "--failed" in args else (success, raw)
            with contextlib.redirect_stderr(output): self.assertEqual(namespace["inspect_units"](run, "snapshot-prelogin", query), 1)
            self.assertIn("unit=gdm result=unavailable code=unavailable status=unavailable", output.getvalue())
            self.assertNotIn("SECRET", output.getvalue())
        self.assertEqual(namespace["bounded_query"]([sys.executable, "-c", "print('public')"]), (True, b"public\n"))
        self.assertFalse(namespace["bounded_query"]([sys.executable, "-c", "print('x'*8192)"])[0])
        from unittest.mock import patch
        with patch.object(namespace["subprocess"], "run", side_effect=subprocess.TimeoutExpired("systemctl", 5)) as run:
            self.assertEqual(namespace["bounded_query"](["systemctl", "--failed"]), (False, b""))
            self.assertEqual(run.call_args.kwargs["timeout"], 5)


    def test_snapshot_fat_state_actual_same_fd_ioctl_policy(self):
        import array, os
        from unittest.mock import patch
        namespace, fields, raw = self.snapshot_state()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "state"; path.write_bytes(raw); path.chmod(0o700)
            original = os.fstat; observed = []
            def root_metadata(fd):
                observed.append(fd)
                value = list(original(fd)); value[4] = 0
                return os.stat_result(value)
            def fat_ioctl(fd, request, buffer, mutate):
                self.assertEqual(fd, observed[-1]); self.assertEqual(request, 0x80047210)
                self.assertIsInstance(buffer, array.array); self.assertEqual(buffer.typecode, "I")
                self.assertEqual(buffer.itemsize, 4); self.assertTrue(mutate)
                return 0
            with patch.object(namespace["os"], "fstat", root_metadata), patch("fcntl.ioctl", side_effect=fat_ioctl) as ioctl:
                self.assertEqual(namespace["load_state"](str(path), fields["run_id"], fields["subvol"]), fields)
                self.assertEqual(ioctl.call_count, 1)
                namespace["load_metadata"](str(path))
                self.assertEqual(ioctl.call_count, 2)

    def test_snapshot_state_metadata_policy_security_and_stability(self):
        import os, stat
        from types import SimpleNamespace
        from unittest.mock import patch
        namespace, fields, raw = self.snapshot_state()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "state"; path.write_bytes(raw); path.chmod(0o600)
            original = os.fstat
            for case in ("normal", "posix700", "ioctl-error", "foreign-owner", "hardlink", "unsafe-mode", "nonregular", "changed"):
                for operation in ("load_state", "load_metadata"):
                    calls = []
                    def metadata(fd):
                        value = original(fd); calls.append(fd)
                        data = {key: getattr(value, key) for key in ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns")}
                        data["st_uid"] = 0
                        if case in ("posix700", "ioctl-error"): data["st_mode"] = stat.S_IFREG | 0o700
                        if case == "foreign-owner": data["st_uid"] = 1000
                        if case == "hardlink": data["st_nlink"] = 2
                        if case == "unsafe-mode": data["st_mode"] = stat.S_IFREG | 0o722
                        if case == "nonregular": data["st_mode"] = stat.S_IFIFO | 0o600
                        if case == "changed" and len(calls) > 1: data["st_ctime_ns"] += 1
                        return SimpleNamespace(**data)
                    args = (str(path), fields["run_id"], fields["subvol"]) if operation == "load_state" else (str(path),)
                    with self.subTest(case=case, operation=operation), patch.object(namespace["os"], "fstat", metadata):
                        if case == "normal":
                            with patch("fcntl.ioctl", side_effect=AssertionError("POSIX600 must not need ioctl")):
                                namespace[operation](*args)
                        elif case == "ioctl-error":
                            with patch("fcntl.ioctl", side_effect=OSError("SECRET fixture error")), self.assertRaises(ValueError): namespace[operation](*args)
                        else:
                            with self.assertRaises(ValueError): namespace[operation](*args)

    def test_snapshot_state_actual_metadata_cli_does_not_reorder_parse(self):
        import os
        from unittest.mock import patch
        namespace, fields, raw = self.snapshot_state()
        source = self.snapshot_program("snapshot_state_program", "SNAPSHOT_STATE_PY")
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "state"; path.write_bytes(b"malformed SECRET fields\n"); path.chmod(0o600)
            original = os.fstat
            def metadata(fd):
                value = list(original(fd)); value[4] = 0
                return os.stat_result(value)
            with patch("os.fstat", metadata), patch("sys.argv", ["state.py", "--metadata", str(path)]):
                exec(compile(source, "actual-metadata-cli", "exec"), {"__name__": "__main__"})
            with patch("os.fstat", metadata), self.assertRaises(ValueError):
                namespace["load_state"](str(path), fields["run_id"], fields["subvol"])

    def test_snapshot_prepare_final_failures_stop_before_reboot_and_pass(self):
        body = function("prepare_snapshot_boot")
        tail = body[body.index('    final_uuid='):].rsplit("\n}", 1)[0]
        diagnostic = function("snapshot_prepare_fail")
        for case, expected, reboot in (("identity", "device-identity", False), ("uuid-query", "device-identity", False), ("partuuid-query", "device-identity", False), ("state", "state-validation", False), ("reboot", "grub-reboot", True), ("normal", "", True)):
            script = 'set -euo pipefail\nrun_id=grub-20261004T000000Z-aabbccdd\nuuid=expected partuuid=expected device=fixture state=fixture subvol=fixture\ncase_name=' + case + "\n" + diagnostic + r"""
blkid(){ if [ "$case_name" = identity ]; then printf wrong; else printf expected; fi; if [ "$case_name" = uuid-query ] && [[ "$*" != *PARTUUID* ]]; then return 1; fi; if [ "$case_name" = partuuid-query ] && [[ "$*" = *PARTUUID* ]]; then return 1; fi; return 0; }
snapshot_validate_state(){ [ "$case_name" != state ]; }
grub-reboot(){ printf 'REBOOT\n'; [ "$case_name" != reboot ]; }
emit_runtime_action_pass(){ printf 'PASS\n'; }
finish(){
""" + tail + "\n}\nfinish\n"
            result = subprocess.run(["bash", "--noprofile", "--norc", "-c", script], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0 if case == "normal" else 1)
            self.assertEqual("REBOOT" in result.stdout, reboot)
            self.assertEqual("PASS" in result.stdout, case == "normal")
            if expected:
                self.assertEqual(result.stderr.strip(), "SNAPSHOT_PREPARE_DIAGNOSTIC run_id=grub-20261004T000000Z-aabbccdd phase=snapshot-prepare step=" + expected + " status=failed")
            else: self.assertEqual(result.stderr, "")
        for run, step in (("SECRET RUN", "state-validation"), ("grub-20261004T000000Z-aabbccdd", "SECRET_STEP")):
            result = subprocess.run(["bash", "-c", diagnostic + '\nrun_id="$1"; snapshot_prepare_fail "$2"\n', "fixture", run, step], capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0); self.assertEqual(result.stdout + result.stderr, "")

    def test_snapshot_update_tool_install_exact_grub_full_transaction(self):
        body = function("is_grub_stock") + "\n" + function("upgrade_stock_runtime_tools")
        for scenario, phase, status, extra in (("stock-gnome-btrfs-grub", "update", 0, True), ("stock-gnome-btrfs-luks2-plymouth-grub", "update", 0, False), ("stock-gnome-ext4-systemdboot", "update", 0, False), ("stock-gnome-btrfs-grub", "snapshot-prepare", 1, False)):
            script = "pacman(){ printf '%s' \"$*\"; }\n" + body + "\nupgrade_stock_runtime_tools\n"
            result = subprocess.run(["bash", "-c", "scenario=$1 phase=$2\n" + script, "snapshot-update", scenario, phase], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, status)
            if status == 0:
                self.assertEqual(result.stdout, "-Syu --noconfirm --disable-download-timeout" + (" --needed bpftrace" if extra else ""))
            else:
                self.assertEqual(result.stdout, "")

    def test_snapshot_readback_rejects_metadata_before_marker_read(self):
        import shlex
        body = "\n".join(function(name) for name in ("snapshot_runtime_fail", "snapshot_lowerdir_matches", "snapshot_expected_readback"))
        for case in ("valid", "oversize", "owner", "writable", "hardlink", "stat-failure"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); marker = root / "var/lib/arch-linux-vm/snapshot-marker"
                marker.parent.mkdir(parents=True); marker.write_text("grub-20261004T000000Z-aabbccdd\n")
                script = "fixture=" + shlex.quote(str(root)) + "\ncase_fixture=" + shlex.quote(case) + "\n" + r'''
run_id=grub-20261004T000000Z-aabbccdd phase=snapshot-prelogin
mount(){ :; }
findmnt(){ case "$*" in *FSTYPE*) printf btrfs;; *FSROOT*) printf '/@snapshots/qa-%s' "$run_id";; *OPTIONS*) printf ro;; *UUID*) printf 12345678-1234-1234-1234-123456789abc;; esac; }
mounted_source_device(){ printf /dev/vda2; }
btrfs(){ case "$*" in *rootid*) printf 257;; *) printf ro=true;; esac; }
stat(){
    if [[ "$*" = *'%i'* ]]; then printf 1234; return; fi
    case "$case_fixture" in
        valid) printf '0:600:1:31';; oversize) printf '0:600:1:32';;
        owner) printf '1000:600:1:31';; writable) printf '0:622:1:31';;
        hardlink) printf '0:600:2:31';; stat-failure) return 1;;
    esac
}
cat(){ printf called >"$fixture/cat-called"; command cat "$@"; }
''' + body + "\nsnapshot_expected_readback \"$fixture\" /dev/vda2 @snapshots/qa-$run_id 12345678-1234-1234-1234-123456789abc 257 1234\n"
                result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0 if case == "valid" else 1, result.stderr)
                self.assertEqual((root / "cat-called").exists(), case == "valid", "unsafe or oversized marker must be rejected before cat")
                if case != "valid": self.assertIn("reason=lower-marker", result.stderr)

    def test_snapshot_executor_actual_consumer_cleanup_and_missing_observation(self):
        import json
        program = self.snapshot_program("snapshot_backing_executor_program", "SNAPSHOT_EXECUTOR_SH")
        checker = self.snapshot_program("snapshot_backing_checker_program", "SNAPSHOT_CHECKER_PY")
        expected, rows = self.proof_fixture()
        for case in ("success", "readback-only", "native-fail", "cleanup-fail"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                work = Path(temporary); (work / "readback").mkdir(); (work / "checker.py").write_text(checker)
                (work / "expected.json").write_text(json.dumps(expected))
                (work / "fixture.stdout").write_bytes(self.proof_output(rows if case != "readback-only" else []))
                (work / "case").write_text(case)
                prefix = r'''
snapshot_expected_readback(){ printf 'readback\n' >>"$1/../calls"; }
mount(){ printf 'mount %s\n' "$*" >>"$work/calls"; }
mountpoint(){ return 1; }
umount(){ printf 'umount %s\n' "$*" >>"$work/calls"; if [ "$(cat "$work/case")" = cleanup-fail ] && [ "$*" = '-- /sys/kernel/tracing' ]; then return 1; fi; }
timeout(){
    printf 'observer %s\n' "$*" >>"$work/calls"
    cat "$work/fixture.stdout"
    [ "$(cat "$work/case")" != native-fail ]
}
'''
                result = subprocess.run(["bash", "-c", prefix + program, "snapshot-executor", str(work), "/dev/vda2", "@snapshots/qa-grub-20261004T000000Z-aabbccdd", expected["fsUuid"], "257", "1234", "grub-20261004T000000Z-aabbccdd", "snapshot-prelogin"], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0 if case == "success" else 1, result.stderr)
                calls = (work / "calls").read_text()
                self.assertLess(calls.index("readback"), calls.index("observer"))
                self.assertIn("reader.py grub-20261004T000000Z-aabbccdd", calls)
                self.assertIn("probe.bt 1234 31", calls)
                self.assertIn("umount -- /sys/kernel/tracing", calls)
                self.assertIn("umount -- /tmp", calls)

    def test_snapshot_backing_owned_cleanup_and_target_stdout(self):
        import shlex
        names = ("snapshot_runtime_fail", "snapshot_lowerdir_matches", "mounted_source_device", "snapshot_expected_readback", "verify_snapshot_backing")
        body = "\n".join(function(name) for name in names)
        for name, delimiter in (("snapshot_backing_probe_program", "SNAPSHOT_BACKING_BPF"), ("snapshot_overlay_reader_program", "SNAPSHOT_READER_PY"), ("snapshot_backing_checker_program", "SNAPSHOT_CHECKER_PY"), ("snapshot_backing_executor_program", "SNAPSHOT_EXECUTOR_SH")):
            body += "\n" + name + "(){ printf '%s\\n' " + shlex.quote(self.snapshot_program(name, delimiter)) + "; }\n"
        for case in ("success", "foreign-file", "cleanup-fail"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                work = Path(temporary) / "owned"; work.mkdir()
                if case == "foreign-file": (work / "foreign").write_text("preserve")
                prefix = "work_fixture=" + shlex.quote(str(work)) + "\ncase_fixture=" + shlex.quote(case) + "\n" + r'''
set -euo pipefail
run_id=grub-20261004T000000Z-aabbccdd phase=snapshot-prelogin
bpftrace(){ :; }
unshare(){ :; }
mktemp(){ printf '%s\n' "$work_fixture"; }
timeout(){ printf 'NOT_A_TARGET_PATH\n'; }
rm(){ if [ "$case_fixture" = cleanup-fail ]; then return 1; fi; command rm "$@"; }
'''
                result = subprocess.run(["bash", "-c", prefix + body + "\nverify_snapshot_backing /dev/vda2 @snapshots/qa-$run_id 12345678-1234-1234-1234-123456789abc 257 1234 254 2\n"], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0 if case == "success" else 1, result.stderr)
                self.assertEqual(result.stdout, "", "observer output must not replace the target pathname")
                if case == "success": self.assertFalse(work.exists())
                else: self.assertIn("reason=lower-source-query", result.stderr)
                if case == "foreign-file": self.assertEqual((work / "foreign").read_text(), "preserve")

    def shell_lifecycle(self, case="normal", checkpoint="extension-timeout", requested_uid=None, stat_change=None):
        text = VERIFY.read_text()
        match = re.search(r"^emit_gnome_shell_lifecycle_diagnostic\(\) \{\n.*?<<'PY'\n(.*?)\nPY\n", text, re.M | re.S)
        self.assertIsNotNone(match, "actual lifecycle diagnostic helper missing")
        import json
        import os
        from unittest.mock import patch
        import io
        import contextlib
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); sentinel = root / "sentinel"; unit = root / "unit"
            unit.write_text("[Service]\nExecStart=gsettings set org.gnome.shell disable-user-extensions true\n")
            if case in ("early", "killed", "timeout", "recovery"):
                sentinel.touch()
            if case == "unsafe-sentinel":
                sentinel.symlink_to(unit)
            source = match.group(1).replace('"/run/user/{uid}/gnome-shell-disable-extensions"', '"' + str(sentinel) + '"').replace('"/usr/lib/systemd/user/org.gnome.Shell-disable-extensions.service"', '"' + str(unit) + '"')
            namespace = {"__name__": "lifecycle_fixture"}
            exec(compile(source, "actual-lifecycle-helper", "exec"), namespace)
            calls = []
            def run(args, **kwargs):
                calls.append(args)
                if case == "unavailable":
                    raise subprocess.TimeoutExpired(args, 5)
                if any(arg.endswith("/gsettings") for arg in args):
                    raw = "SECRET_FLAG" if case == "malformed" else ("true" if case == "recovery" else "false")
                elif "journalctl" in " ".join(args):
                    records = []
                    if case == "recovery":
                        records.append({"USER_UNIT": "org.gnome.Shell-disable-extensions.service", "MESSAGE_ID": "39f53479d3a045ac8e11786248231fbf"})
                    if case in ("killed", "timeout"):
                        records.append({"USER_UNIT": "org.gnome.Shell@wayland.service", "MESSAGE_ID": "d9b373ed55a64feb8242e02dbe79a49c", "UNIT_RESULT": "timeout" if case == "timeout" else "signal"})
                        records.append({"USER_UNIT": "org.gnome.Shell@wayland.service", "MESSAGE_ID": "98e322203f7a4ed290d09fe03c09fe15", "EXIT_CODE": "killed", "EXIT_STATUS": "9"})
                    if case == "normal":
                        records.append({"USER_UNIT": "org.gnome.Shell@wayland.service", "MESSAGE_ID": "9d1aaa27d60140bd96365438aad20286"})
                    raw = "SECRET_MALFORMED" if case == "malformed" else "\n".join(json.dumps(record | {"_SYSTEMD_USER_UNIT": "init.scope", "MESSAGE": "SECRET_RAW_JOURNAL"}) for record in records)
                    if case == "duplicate-json": raw = '{"USER_UNIT":"org.gnome.Shell@wayland.service","USER_UNIT":"SECRET"}'
                    if case == "unknown-unit": raw = '{"USER_UNIT":"SECRET_UNIT","MESSAGE_ID":"SECRET_EVENT"}'
                    if case == "oversized": raw = "x" * 262145
                    if case == "capped": raw = "\n".join(json.dumps({"USER_UNIT": "org.gnome.Shell@wayland.service"}) for _ in range(129))
                else:
                    raw = "LoadState=loaded\nResult=success\nExecMainCode=1\nExecMainStatus=0\nExecMainStartTimestampMonotonic=12345\nInvocationID=" + "a" * 32 + "\n"
                    if case == "malformed": raw += "Result=SECRET_RESULT\n"
                kwargs["stdout"].write(raw.encode())
                return subprocess.CompletedProcess(args, 0)
            real_fstat = os.fstat
            unit_stats = []
            def fstat(fd):
                value = real_fstat(fd)
                fields = list(value)
                fields[4] = 0
                times = {name: getattr(value, name) for name in
                         ("st_atime", "st_mtime", "st_ctime",
                          "st_atime_ns", "st_mtime_ns", "st_ctime_ns")}
                if os.readlink(f"/proc/self/fd/{fd}") == str(unit):
                    if not unit_stats:
                        unit_stats.append((fields.copy(), times.copy()))
                    elif stat_change is not None:
                        # Freeze unrelated metadata so each read-race regression is deterministic.
                        fields, times = unit_stats[0][0].copy(), unit_stats[0][1].copy()
                        if stat_change == "st_atime":
                            fields[7] += 1
                            times["st_atime"] += 1
                            times["st_atime_ns"] += 1_000_000_000
                        elif stat_change in ("st_mtime_ns", "st_ctime_ns"):
                            times[stat_change] += 1
                        else:
                            index = {"st_mode": 0, "st_ino": 1, "st_dev": 2,
                                     "st_nlink": 3, "st_uid": 4, "st_gid": 5,
                                     "st_size": 6}[stat_change]
                            fields[index] += 1
                return os.stat_result(fields, times)
            output = io.StringIO()
            with patch("subprocess.run", run), patch("os.fstat", fstat), contextlib.redirect_stderr(output):
                namespace["diagnose"](str(os.getuid() if requested_uid is None else requested_uid), str(os.getgid()), "fixture", "return-user-login", checkpoint)
            return output.getvalue(), calls

    def test_shell_lifecycle_normal_and_early_sentinel(self):
        for case, sentinel in (("normal", "absent"), ("early", "present")):
            output, calls = self.shell_lifecycle(case)
            self.assertIn("early_sentinel=" + sentinel, output)
            self.assertIn("disabled_user_extensions=false", output)
            self.assertIn("result=success exit_code=exited exit_status=0 start_monotonic_us=12345 invocation=yes", output)
            self.assertRegex(output, r"recovery_unit_sha256=[a-f0-9]{64}")
            self.assertIn("stop_events=" + ("1" if case == "normal" else "0"), output)
            self.assertFalse(any("set" in call for call in calls))

    def test_shell_lifecycle_atime_only_read_preserves_recovery_digest(self):
        output, _ = self.shell_lifecycle(stat_change="st_atime")
        self.assertRegex(output, r"recovery_unit_sha256=[a-f0-9]{64}")

    def test_shell_lifecycle_recovery_digest_rejects_protected_metadata_changes(self):
        for field in ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink",
                      "st_size", "st_mtime_ns", "st_ctime_ns"):
            with self.subTest(field=field):
                output, _ = self.shell_lifecycle(stat_change=field)
                self.assertIn("recovery_unit_sha256=unknown", output)
                self.assertNotRegex(output, r"recovery_unit_sha256=[a-f0-9]{64}")

    def test_shell_lifecycle_actual_helper_under_ci_uid_model(self):
        import os
        from unittest.mock import patch
        original = Path.lstat
        def ci_lstat(path, *args, **kwargs):
            value = original(path, *args, **kwargs)
            fields = list(value); fields[4] = 1001
            return os.stat_result(fields)
        with patch.object(Path, "lstat", ci_lstat), patch("os.getuid", return_value=1001), patch("os.getgid", return_value=1001):
            for case, expected in (("normal", "absent"), ("early", "present")):
                output, _ = self.shell_lifecycle(case)
                self.assertIn("early_sentinel=" + expected, output)

    def test_shell_lifecycle_foreign_runtime_owner_is_unknown(self):
        import os
        for case in ("normal", "early"):
            with self.subTest(case=case):
                output, calls = self.shell_lifecycle(case, requested_uid=os.getuid() + 1)
                self.assertIn("early_sentinel=unknown", output)
                self.assertNotIn("early_sentinel=absent", output)
                self.assertNotIn("early_sentinel=present", output)
                self.assertTrue(any("--reuid=" + str(os.getuid() + 1) in call for call in calls))

    def test_shell_lifecycle_failure_events_and_recovery_are_distinct(self):
        for case, token in (("killed", "killed_events=1"), ("timeout", "timeout_events=1"), ("recovery", "recovery_started=yes")):
            output, _ = self.shell_lifecycle(case)
            self.assertIn(token, output)
            self.assertNotIn("SECRET", output)
            self.assertLess(len(output), 1800)

    def test_shell_lifecycle_unknown_queries_and_malformed_are_not_normal(self):
        for case in ("unavailable", "malformed", "oversized", "capped", "duplicate-json", "unknown-unit"):
            output, _ = self.shell_lifecycle(case)
            self.assertIn("journal_query=unknown", output)
            self.assertIn("recovery_started=unknown", output)
            self.assertNotIn("SECRET", output)
            self.assertNotIn("Traceback", output)
            if case in ("unavailable", "malformed"):
                self.assertIn("disabled_user_extensions=unknown", output)
                self.assertIn("result=unknown", output)

    def test_shell_lifecycle_unsafe_sentinel_is_unknown(self):
        output, _ = self.shell_lifecycle("unsafe-sentinel")
        self.assertIn("early_sentinel=unknown", output)

    def test_shell_lifecycle_actual_query_enforces_caps_and_timeout(self):
        import sys
        source = re.search(r"^emit_gnome_shell_lifecycle_diagnostic\(\) \{\n.*?<<'PY'\n(.*?)\nPY\n", VERIFY.read_text(), re.M | re.S).group(1)
        namespace = {"__name__": "lifecycle_fixture"}
        exec(compile(source, "actual-lifecycle-helper", "exec"), namespace)
        self.assertEqual(namespace["query"]([sys.executable, "-c", "print('safe')"], 64), "safe\n")
        self.assertIsNone(namespace["query"]([sys.executable, "-c", "print('x'*10000)"], 64))
        self.assertIsNone(namespace["query"]([sys.executable, "-c", "import time;time.sleep(6)"], 64))

    def test_shell_lifecycle_checkpoints_do_not_query_journal(self):
        for checkpoint in ("migrated-login", "before-original-user-logout"):
            output, calls = self.shell_lifecycle(checkpoint=checkpoint)
            self.assertIn("checkpoint=" + checkpoint, output)
            self.assertFalse(any("journalctl" in " ".join(args) for args in calls))

    def test_shell_lifecycle_actual_checkpoint_routes_before_logout(self):
        body = function("prepare_fresh_marble_user")
        start = body.index('    uid="$(id -u "${username}")"')
        end = body.index('    greeter_session=', start)
        script = '''set -euo pipefail
username=vmtest
id(){ printf 1000; }
emit_gnome_shell_lifecycle_diagnostic(){ printf 'CHECKPOINT:%s\\n' "$2"; }
run_in_user_session(){ printf 'SESSION_COMMAND:%s\\n' "$*"; }
wait_for_named_user_logout(){ printf 'LOGOUT_WAIT:%s\\n' "$1"; }
''' + body[start:end]
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["CHECKPOINT:before-original-user-logout", "SESSION_COMMAND:1000 /usr/bin/gnome-session-quit --logout --no-prompt", "LOGOUT_WAIT:vmtest"])

    def test_shell_lifecycle_actual_migrated_session_checkpoint_route(self):
        body = function("verify_marble_user_session").split('    shell_environment=', 1)[0] + "\n}\n"
        setup = '''set -euo pipefail
username=vmtest
verify_common(){ printf target; }
verify_marble_storage_profile(){ :; }
verify_public_repository_contract(){ :; }
wait_for_user_session(){ printf session; }
id(){ printf 1000; }
session_property(){ printf 1000; }
wait_for_gnome_shell(){ printf 123; }
emit_gnome_shell_lifecycle_diagnostic(){ printf 'CHECKPOINT:%s\\n' "$2"; }
'''
        for phase in ("migrated-login", "return-user-login"):
            result = subprocess.run(["bash", "-c", setup + body + "phase=" + phase + "\nverify_marble_user_session marble\n"], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "CHECKPOINT:migrated-login\n" if phase == "migrated-login" else "")

    def media_prepare(self, available=False, install_status=0, installed=True, trusted=True, mode="public", qualification="true", inherited=False, missing=""):
        body = function("require_public_readback_tools") + "\n" + function("prepare_media_readback")
        script = "set -euo pipefail\ninput_mode=" + mode + " media_qualification=" + qualification + " scenario=minimal-ext4-systemdboot phase=media-readback-prepare marker_prefix=MINIMAL run_id=fixture\n"
        script += "available=" + str(int(available)) + "\ncommand(){ if [ \"$*\" = '-v -- jq' ]; then [ \"$available\" = 1 ]; else [ \"$*\" != '-v -- " + missing + "' ]; fi; }\n"
        script += "pacman-conf(){ " + ("if [[ \"$*\" = --repo* ]]; then return 0; fi; " if inherited else "") + "printf '%s\\n' PackageRequired " + ("PackageTrustedOnly" if trusted else "PackageTrustAll") + "; }\n"
        script += "pacman(){ printf 'PACMAN:%s\\n' \"$*\"; available=" + str(int(installed)) + "; return " + str(install_status) + "; }\n"
        script += "jq(){ printf 'jq-fixture\\n'; }\n" + body + "\nprepare_media_readback\n"
        return subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)

    def test_media_readback_preparation_installs_official_jq(self):
        result = self.media_prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PACMAN:-S --noconfirm --needed -- extra/jq", result.stdout)
        self.assertIn("phase=media-readback-prepare", result.stdout)

    def test_media_readback_preparation_missing_other_tool(self):
        result = self.media_prepare(missing="gpgv")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing public readback dependency: gpgv", result.stderr)
        self.assertNotIn("PACMAN:", result.stdout)

    def test_media_readback_preparation_inherited_signature_policy(self):
        result = self.media_prepare(inherited=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_media_readback_preparation_existing_tool(self):
        result = self.media_prepare(available=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("PACMAN:", result.stdout)

    def test_media_readback_preparation_failures_stop(self):
        for kwargs in ({"install_status": 1}, {"installed": False}, {"trusted": False},
                       {"mode": "staged"}, {"qualification": "false"}):
            with self.subTest(kwargs=kwargs):
                result = self.media_prepare(**kwargs)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("_QEMU_GUEST_PASS", result.stdout)
        self.assertIn("missing public readback dependency: jq", self.media_prepare(installed=False).stderr)

    def test_readback_missing_dependency_is_named(self):
        body = function("require_public_readback_tools") + "\n" + re.search(r"^verify_public_release_pages_binding\(\) \(\n.*?^\)", VERIFY.read_text(), re.M | re.S).group(0)
        for missing in ("jq", "gpgv"):
            script = "set -euo pipefail\ninput_mode=public\ncommand(){ [ \"$*\" != '-v -- " + missing + "' ]; }\n" + body + "\nverify_public_release_pages_binding\n"
            result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing public readback dependency: " + missing, result.stderr)

    def test_media_prepare_phase_only_public_qualification(self):
        prefix = VERIFY.read_text().split("trim_value() {", 1)[0]
        for mode, qualification, expected in (("public", "true", 0), ("public", "false", 2), ("staged", "false", 1)):
            args = ["media-readback-prepare", "ALI100M123456789ABC", "SNAPLYZE", "ALI_MIN_12345678", "vmtest", "minimal-ext4-systemdboot", "minimal-20261003T145600Z-b3895c93", "A" * 40, "B" * 40, mode, "1.0.5", "absent", "https://snaplyze.github.io/arch-linux/repo/$arch" if mode == "public" else "-", "https://github.com/snaplyze/arch-linux/releases/download/1.0.5/arch-linux.gpg" if mode == "public" else "-", "a" * 64, "a" * 40, "b" * 40] + ["a" * 64] * 5 + ["-", "-", "-", qualification]
            result = subprocess.run(["bash", "-c", prefix, "phase-guard-fixture", *args], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, expected, result.stderr)

    def test_host_media_preparation_route_and_failure(self):
        host = (ROOT / "tests/vm/run.sh").read_text()
        body = re.search(r"^prepare_public_media_readback\(\) \{\n.*?^\}", host, re.M | re.S).group(0)
        self.assertIn("prepare_public_media_readback", host.split("wait_qga || die 'first boot QEMU guest agent did not become ready'", 1)[1].split("if is_marble_scenario", 1)[0])
        for mode, qualification, status in (("public", "true", 0), ("public", "true", 1), ("public", "false", 0), ("staged", "false", 0)):
            script = "set -euo pipefail\ninput_mode=" + mode + " media_qualification=" + qualification + "\nqga_verify(){ printf 'PREPARE:%s\\n' \"$*\"; return " + str(status) + "; }\n" + body + "\nprepare_public_media_readback\nprintf 'READBACK_READY\\n'\n"
            result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, status)
            self.assertEqual("PREPARE:media-readback-prepare" in result.stdout, mode == "public" and qualification == "true")
            self.assertEqual("READBACK_READY" in result.stdout, status == 0)

    def kernel(self, phase="firstboot", running="new", releases=("new",), image=True, modules=True, match=True):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            boot = root / "boot"; boot.mkdir()
            mod = root / "usr/lib/modules/new"; mod.mkdir(parents=True)
            (mod / "pkgbase").write_text("linux\n")
            (mod / "vmlinuz").write_bytes(b"kernel")
            (boot / "vmlinuz-linux").write_bytes(b"kernel" if match else b"wrong")
            if image: (boot / "initramfs-linux.img").write_bytes(b"image")
            if not modules: (mod / "pkgbase").unlink()
            body = function("verify_kernel_initramfs_pair").replace("/usr/lib/modules", str(root / "usr/lib/modules")).replace("/boot/vmlinuz-linux", str(boot / "vmlinuz-linux"))
            listing = "\n".join("usr/lib/modules/" + release + "/kernel/test.ko.zst" for release in releases)
            script = "set -euo pipefail\nrun_id=fixture\npacman(){ printf '%s\\n' 'package 1'; }\nphase=" + phase + "\nuname(){ printf '%s\\n' '" + running + "'; }\nlsinitcpio(){ printf '%s\\n' '" + listing + "'; }\n" + body + "\nverify_kernel_initramfs_pair '" + str(boot / "initramfs-linux.img") + "'\n"
            return subprocess.run(["bash", "-c", script], capture_output=True, timeout=5).returncode
    def helper_failure(self, prepare=1, status=1):
        body = function("exercise_gdm_helper_failure")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); directory = root / "override"; directory.mkdir(mode=0o755)
            payload = root / "payload"; payload.write_text("fixture")
            (directory / "50-arch-linux-marble-gdm.conf").symlink_to(payload)
            helper = root / "helper"
            helper.write_text("#!/bin/sh\ncase \"$1\" in --prepare) exit " + str(prepare) + ";; --status) exit " + str(status) + ";; esac\n")
            helper.chmod(0o700)
            script = "set -euo pipefail\n" + body + "\nexercise_gdm_helper_failure '" + str(directory) + "' '" + str(helper) + "' '" + str(payload) + "'\n"
            result = subprocess.run(["bash", "-c", script], capture_output=True, timeout=5)
            self.assertEqual(directory.stat().st_mode & 0o777, 0o755)
            self.assertTrue((directory / "50-arch-linux-marble-gdm.conf").is_symlink())
            return result.returncode
    def test_helper_failure_observed(self): self.assertEqual(self.helper_failure(), 0)
    def test_helper_false_success_rejected(self): self.assertNotEqual(self.helper_failure(prepare=0), 0)
    def test_status_false_stock_rejected(self): self.assertNotEqual(self.helper_failure(status=0), 0)
    def test_host_lifecycle_executes_real_transitions(self):
        host = (ROOT / "tests/vm/run.sh").read_text()
        body = re.search(r"^run_marble_acceptance\(\) \{\n.*?^\}", host, re.M | re.S).group(0)
        script = """set -euo pipefail
input_mode=staged scenario_id=marble-gnome-btrfs-luks2-plymouth-systemdboot
last_boot_id=before
qga_verify(){ printf 'verify:%s\n' "$1"; }
record_assertion(){ :; }
capture_screen(){ :; }
marble_gdm_login(){ printf 'login:%s\n' "$1"; }
run_fresh_marble_user_round_trip(){ :; }
run_extension_functional_acceptance(){ printf 'functional:%s\n' "$1"; }
hmp_request(){ :; }
hmp_type_password(){ :; }
sleep(){ :; }
schedule_transition(){ :; }
wait_qemu_exit(){ :; }
launch_qemu(){ last_boot_id=after; }
capture_and_unlock_luks_prompt(){ :; }
wait_qga(){ :; }
""" + body + "\nrun_marble_acceptance\n"
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual([line for line in lines if line.startswith("functional:")], ["functional:upgrade", "functional:postreboot"])
        expected = ["verify:helper-failure", "verify:helper-restored-prelogin", "login:helper-restored-login", "verify:deactivate-gdm", "verify:deactivated-prelogin", "login:deactivated-login"]
        self.assertEqual([line for line in lines if line in expected], expected)
    def snapshot_entry(self, rootflags="subvol=@snapshots/qa-fixture", root="UUID=fixture", image="/initramfs-linux.img", inner=False):
        body = function("select_snapshot_grub_entry")
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp) / "grub.cfg"; entries = Path(tmp) / "grub-btrfs.cfg"
            main.write_text("submenu 'Arch snapshots' {\nconfigfile ${prefix}/grub-btrfs.cfg\n}\n")
            entries.write_text("submenu 'snapshot fixture' {\nmenuentry 'linux' {\nlinux /vmlinuz-linux root=" + root + " rootflags=" + rootflags + " systemd.volatile=overlay\ninitrd " + image + "\n}\n}\n")
            command = body + "\nselect_snapshot_grub_entry '" + str(main) + "' '" + str(entries) + "' fixture @snapshots/qa-fixture /dev/vda2 partuuid" + (" --inner" if inner else "") + "\n"
            return subprocess.run(["bash", "-c", command], capture_output=True, text=True, timeout=5)
    def selector_fixture(self, case="success"):
        self.assertTrue("create_snapshot_selector() {" in VERIFY.read_text(), "run-owned one-shot selector absent")
        body = function("create_snapshot_selector") + "\n" + function("remove_snapshot_selector")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); grub = root / "grub.d"; grub.mkdir()
            run = "grub-20261003T193308Z-eb295d38"
            fragment = grub / ("42_qa_snapshot_" + run)
            state = root / "state"
            inner = "snapshot fixture>  vmlinuz-linux & initramfs-linux.img"
            if case == "existing": fragment.write_text("unrelated")
            if case == "symlink": fragment.symlink_to(root / "absent")
            if case == "invalid": inner = "snapshot'; halt; '"
            if case == "invalid-run": run = "../../foreign"
            body = body.replace("/etc/grub.d", str(grub))
            script = "set -Eeuo pipefail\nrun_id=\"$1\"\nstat(){ printf '0:755:1'; }\n" + body + "\nsha=$(create_snapshot_selector \"$2\")\nprintf 'selector_sha256=%s\\n' \"$sha\" >\"$3\"\n"
            if case == "changed": script += "printf altered >>\"$4\"\n"
            if case == "cleanup-failure": script += "rm(){ return 1; }\n"
            script += "cat -- \"$4\"\nremove_snapshot_selector \"$3\"\n"
            result = subprocess.run(["bash", "-c", script, "fixture", run, inner, str(state), str(fragment)], capture_output=True, text=True, timeout=5)
            remains = fragment.exists() or fragment.is_symlink()
            if case == "existing": self.assertEqual(fragment.read_text(), "unrelated")
            return result, remains

    def test_snapshot_selector_exported_configfile_context(self):
        result, remains = self.selector_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(remains)
        # Model GRUB's actual fresh configfile context: only exported variables survive.
        text = result.stdout
        default = re.search(r"set default='([^']+)'", text).group(1)
        outer_context = {"default": default, "timeout": "0"}
        exported = set(re.search(r"export ([^\n]+)", text).group(1).split())
        configfile_context = {key: value for key, value in outer_context.items() if key in exported}
        self.assertEqual(configfile_context, outer_context)
        self.assertEqual(configfile_context["default"].split(">"), ["snapshot fixture", "  vmlinuz-linux & initramfs-linux.img"])
        self.assertIn('configfile "${prefix}/grub-btrfs.cfg"', text)
        self.assertNotRegex(text, r"(?m)^\s*(?:linux|initrd) ")
        self.assertNotIn("timeout", {key: value for key, value in outer_context.items() if key in set()})

    def test_snapshot_selector_refuses_invalid_or_existing_files(self):
        for case in ("existing", "symlink", "invalid", "invalid-run", "changed", "cleanup-failure"):
            with self.subTest(case=case):
                result, remains = self.selector_fixture(case)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                if case in ("existing", "symlink", "changed", "cleanup-failure"): self.assertTrue(remains)

    def test_snapshot_selector_production_regeneration_binding(self):
        for case in ("success", "cfg-changed", "regeneration-failure", "syntax-failure"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); (root / "grub.d").mkdir(); (root / "boot/grub").mkdir(parents=True)
                cfg = root / "boot/grub/grub-btrfs.cfg"; cfg.write_text("unchanged production snapshot entries\n")
                state = root / "state"; state.write_text("run_id=grub-20261003T193308Z-eb295d38\n")
                body = "\n".join(function(name) for name in ("create_snapshot_selector", "install_snapshot_selector", "remove_snapshot_selector"))
                body = body.replace("/etc/grub.d", str(root / "grub.d")).replace("/boot/grub", str(root / "boot/grub"))
                script = """set -Eeuo pipefail
run_id=grub-20261003T193308Z-eb295d38
stat(){ printf '0:755:1'; }
grub-mkconfig(){
    [ "$1" = -o ] && [ "$2" = "$fixture_root/boot/grub/grub.cfg" ]
    [ "$fixture_case" != regeneration-failure ] || return 9
    if [ "$fixture_case" = cfg-changed ]; then printf changed >>"$fixture_root/boot/grub/grub-btrfs.cfg"; fi
    printf main >"$2"
}
grub-script-check(){ [ "$fixture_case" != syntax-failure ]; }
""" + body + "\ninstall_snapshot_selector \"$fixture_root/state\" 'snapshot fixture>linux'\nremove_snapshot_selector \"$fixture_root/state\"\n"
                import os
                result = subprocess.run(["bash", "-c", script], env=dict(os.environ, fixture_root=tmp, fixture_case=case), capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, case == "success", result.stderr)
                self.assertEqual(cfg.read_text(), "unchanged production snapshot entries\n" + ("changed" if case == "cfg-changed" else ""))
                self.assertIn("production_cfg_sha256=", state.read_text())
                self.assertEqual(any((root / "grub.d").iterdir()), case != "success")

    def test_snapshot_cleanup_preserves_failure_and_owned_boundary(self):
        for case in ("success", "changed-fragment", "regeneration-failure"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); (root / "grub.d").mkdir(); (root / "boot").mkdir(); (root / "snapshots").mkdir()
                run = "grub-20261003T193308Z-eb295d38"
                marker = root / "snapshots" / ("qa-" + run) / "var/lib/arch-linux-vm/snapshot-marker"
                marker.parent.mkdir(parents=True); marker.write_text(run)
                live_marker = root / "var/lib/arch-linux-vm/snapshot-marker"; live_marker.parent.mkdir(parents=True); live_marker.write_text(run)
                state = root / "boot" / ("qa-snapshot-" + run + ".state")
                body = "\n".join(function(name) for name in ("create_snapshot_selector", "remove_snapshot_selector", "cleanup_snapshot_boot"))
                body = body.replace("/etc/grub.d", str(root / "grub.d")).replace("/.snapshots", str(root / "snapshots")).replace("/boot/", str(root / "boot") + "/")
                # Replace only the live marker literal; snapshot marker remains below owned path.
                body = body.replace('"${state}" /var/lib/arch-linux-vm/snapshot-marker', '\"${state}\" ' + str(live_marker))
                script = """set -Eeuo pipefail
scenario=stock-gnome-btrfs-grub run_id=grub-20261003T193308Z-eb295d38
stat(){ printf '0:755:1'; }
findmnt(){ printf /@; }
btrfs(){ if [ "$1" = property ]; then printf ro=true; else printf deleted >"$fixture_root/deleted"; fi; }
grub-mkconfig(){ [ "$fixture_case" != regeneration-failure ]; }
verify_common(){ :; }
verify_btrfs_contract(){ :; }
emit_runtime_action_pass(){ printf RESTORED; }
""" + body + "\nsha=$(create_snapshot_selector 'snapshot fixture>linux')\nprintf 'run_id=%s\\nselector_sha256=%s\\n' \"$run_id\" \"$sha\" >\"$fixture_state\"\n"
                if case == "changed-fragment": script += "printf changed >>\"$fixture_root/grub.d/42_qa_snapshot_$run_id\"\n"
                script += "cleanup_snapshot_boot\n"
                import os
                result = subprocess.run(["bash", "-c", script], env=dict(os.environ, fixture_root=tmp, fixture_case=case, fixture_state=str(state)), capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, case == "success", result.stderr)
                self.assertEqual("RESTORED" in result.stdout, case == "success")
                if case == "changed-fragment": self.assertFalse((root / "deleted").exists())

    def test_snapshot_selector_inner_path_has_no_configfile_outer(self):
        result = self.snapshot_entry(inner=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "snapshot fixture>linux")

    def test_snapshot_production_device_root(self):
        result = self.snapshot_entry(root="/dev/vda2")
        self.assertEqual(result.returncode, 0, result.stderr)
    def test_snapshot_root_argument_identity(self):
        body = function("snapshot_root_argument_matches")
        for argument, expected in (("root=/dev/vda2", 0), ("root=UUID=fixture", 0),
                                   ("root=PARTUUID=partuuid", 0), ("root=/dev/vda3", 1),
                                   ("root=UUID=wrong", 1), ("root=/dev/vda2 root=UUID=fixture", 1)):
            result = subprocess.run(["bash", "-c", body + "\nsnapshot_root_argument_matches \"$1\" /dev/vda2 fixture partuuid", "snapshot-root-fixture", argument], capture_output=True, timeout=5)
            self.assertEqual(result.returncode, expected)

    def gdm_inventory(self, case="valid"):
        body = function("gdm_password_worker_inventory")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); proc = root / "proc"; proc.mkdir()
            daemon = root / "gdm"; daemon.write_text("daemon")
            worker = root / "gdm-session-worker"; worker.write_text("worker")
            for pid, parent, start, executable in ((10, 1, 100, daemon), (20, 10, 200, worker)):
                base = proc / str(pid); base.mkdir()
                tail = ["S", str(parent)] + ["0"] * 17 + [str(start)]
                (base / "stat").write_text(str(pid) + " (gdm-session-wor) " + " ".join(tail))
                (base / "status").write_text("Uid:\t0\t0\t0\t0\n")
                (base / "cgroup").write_text("0::/system.slice/gdm.service\n")
                (base / "cmdline").write_bytes(("gdm" if pid == 10 else "gdm-session-worker [pam/gdm-password]").encode() + b"\0")
                (base / "exe").symlink_to(executable)
            base = proc / "20"
            if case == "owner": (base / "status").write_text("Uid:\t1000\t1000\t1000\t1000\n")
            if case == "cgroup": (base / "cgroup").write_text("0::/foreign.service\n")
            if case == "ancestor": (base / "stat").write_text("20 (gdm-session-wor) " + " ".join(["S", "30"] + ["0"] * 17 + ["200"]))
            if case == "executable": (base / "exe").unlink(); (base / "exe").symlink_to(daemon)
            if case == "other-pam": (base / "cmdline").write_bytes(b"gdm-session-worker [pam/gdm-launch-environment]\0")
            command = body + "\ngdm_password_worker_inventory \"$1\" \"$2\" 10 /system.slice/gdm.service \"$3\"\n"
            return subprocess.run(["bash", "-c", command, "gdm-proc-fixture", str(proc), str(worker), str(daemon)], capture_output=True, text=True, timeout=5)

    def test_gdm_actual_worker_inventory_and_truncated_comm(self):
        result = self.gdm_inventory()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "10.100 20.200")
        self.assertEqual(self.gdm_inventory("other-pam").stdout.strip(), "10.100 none")

    def test_gdm_worker_owner_executable_ancestry_and_cgroup(self):
        for case in ("owner", "cgroup", "ancestor", "executable"):
            with self.subTest(case=case): self.assertNotEqual(self.gdm_inventory(case).returncode, 0)

    def gdm_probe(self, case="delayed", phase="gdm-activation-baseline"):
        text = VERIFY.read_text()
        names = ["wait_for_greeter", "gdm_activation_failure", "gdm_activation_probe"]
        body = "\n".join(function(name) for name in names if re.search(r"^" + name + r"\(\)", text, re.M))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); worker = root / "gdm-session-worker"; worker.write_text("fixture")
            counter = root / "counter"; counter.write_text("0")
            setup = "set -euo pipefail\nphase=" + phase + " username=vmtest run_id=fixture gdm_worker_baseline=none\n"
            setup += 'fixture_worker="$1" fixture_counter="$2" fixture_case="$3"\n'
            setup += r"""
systemctl(){ case "$*" in *MainPID*) printf '10
';; *ControlGroup*) printf '/system.slice/gdm.service
';; *) return 0;; esac; }
find_session(){ printf 'c1'; }
session_property(){ case "$2" in Type) printf wayland;; State) if [ "$fixture_case" = timeout ] || { [ "$fixture_case" = delayed ] && [ "$(cat "$fixture_counter")" -lt 2 ]; }; then printf opening; else printf active; fi;; Remote) printf no;; esac; }
session_name_exists(){ return 1; }
sleep(){ printf '%s
' "$(( $(cat "$fixture_counter") + 1 ))" > "$fixture_counter"; if [ "$fixture_case" = timeout ]; then SECONDS=$((SECONDS + 301)); fi; }
readlink(){ [ "$fixture_case" != daemon ] || return 1; printf '/usr/bin/gdm
'; }
pacman(){ if [ "$1" = -Qqo ]; then printf 'gdm
'; else printf '%s
' "$fixture_worker"; fi; }
stat(){ if [ "$2" = '%u:%g:%h' ]; then case "$fixture_case" in owner) printf '1000:0:1
';; nlink) printf '0:0:2
';; *) printf '0:0:1
';; esac; else printf '0:0
'; fi; }
find(){ if [ "$fixture_case" = permission ]; then printf '%s
' "$fixture_worker"; fi; }
gdm_password_worker_inventory(){ [ "$fixture_case" != inventory ] || return 1; if [ "$fixture_case" = ambiguous ]; then printf '10.100 20.200,21.201
'; else printf '10.100 none
'; fi; }
emit_runtime_action_pass(){ printf 'ACTION_PASS:%s
' "$1"; }
"""
            if case == "path": worker.unlink(); worker.symlink_to(counter)
            script = setup + body + "\ngdm_activation_probe && printf 'PASSWORD_ALLOWED\n'\n"
            return subprocess.run(["bash", "-c", script, "fixture", str(worker), str(counter), case], capture_output=True, text=True, timeout=5)

    def test_gdm_baseline_waits_for_delayed_active_greeter(self):
        result = self.gdm_probe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("activation=baseline", result.stdout)

    def test_gdm_guard_failures_report_bounded_steps_and_withhold_password(self):
        for case, phase, step in (("timeout", "gdm-activation-baseline", "greeter-ready"),
                                  ("delayed", "gdm-activation-check", "greeter-state"),
                                  ("owner", "gdm-activation-baseline", "worker-metadata"),
                                  ("nlink", "gdm-activation-baseline", "worker-metadata"),
                                  ("path", "gdm-activation-baseline", "worker-path"),
                                  ("permission", "gdm-activation-baseline", "daemon-permissions"),
                                  ("daemon", "gdm-activation-baseline", "daemon-executable"),
                                  ("inventory", "gdm-activation-baseline", "worker-inventory"),
                                  ("ambiguous", "gdm-activation-check", "worker-ambiguity"),
                                  ("valid", "invalid", "phase")):
            with self.subTest(case=case):
                result = self.gdm_probe(case, phase)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("PASSWORD_ALLOWED", result.stdout)
                self.assertIn("step=" + step, result.stderr)
                self.assertNotIn("Traceback", result.stderr)
                self.assertNotIn("/tmp/", result.stderr)
                self.assertLess(len(result.stderr), 1024)

    def test_gdm_inventory_failures_have_controlled_reasons(self):
        for case, reason in (("owner", "process-owner"), ("cgroup", "process-cgroup"),
                             ("ancestor", "worker-ancestry"), ("executable", "worker-executable")):
            result = self.gdm_inventory(case)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("reason=" + reason, result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertNotIn("/tmp/", result.stderr)

    def extension_wait(self, case="exact", disabled="false", info="ERROR"):
        text = VERIFY.read_text()
        names = ["emit_extension_timeout_diagnostic", "wait_for_enabled_extensions"]
        body = "\n".join(function(name) for name in names if re.search(r"^" + name + r"\(\)", text, re.M))
        expected = "blur-my-shell@aunetx\ncaffeine@patapon.info"
        with tempfile.TemporaryDirectory() as tmp:
            counter = Path(tmp) / "counter"; counter.write_text("0")
            script = 'set -euo pipefail\nrun_id=fixture phase=return-user-login fixture_expected="$1" fixture_case="$2" fixture_disabled="$3" fixture_counter="$4" fixture_info="$5"\n'
            script += "emit_gnome_shell_lifecycle_diagnostic(){ :; }\n"
            script += r"""
run_in_user_session(){
    if [[ "$*" = *gnome-extensions*info* ]]; then
        printf 'Name: SECRET_INFO_NAME\nPath: /private/SECRET_INFO_PATH\nError: SECRET_INFO_ERROR\n'
        [ "$fixture_info" != query-failed ] || return 7
        printf '  State: %s\n' "$fixture_info"; return 0
    fi
    if [[ "$*" = *disable-user-extensions* ]]; then
        printf '%s
' "$fixture_disabled"; return 0
    fi
    printf '%s
' "$(( $(cat "$fixture_counter") + 1 ))" > "$fixture_counter"
    case "$fixture_case" in
      query-failure) printf 'SECRET_QUERY_ERROR
' >&2; return 7;;
      missing) printf 'blur-my-shell@aunetx
';;
      unexpected) printf '%s
SECRET_UNKNOWN_EXTENSION
' "$fixture_expected";;
      duplicate) printf '%s
caffeine@patapon.info
' "$fixture_expected";;
      delayed) if [ "$(cat "$fixture_counter")" -lt 2 ]; then printf 'blur-my-shell@aunetx
'; else printf '%s
' "$fixture_expected"; fi;;
      *) printf '%s
' "$fixture_expected";;
    esac
}
sleep(){ if [ "$fixture_case" != delayed ]; then SECONDS=$((SECONDS+181)); fi; }
"""
            script += body + '\nwait_for_enabled_extensions 1000 "$fixture_expected"\n'
            return subprocess.run(["bash", "-c", script, "fixture", expected, case, disabled, str(counter), info], capture_output=True, text=True, timeout=5)

    def test_extension_timeout_reports_only_finite_known_states(self):
        for info, state in (("ERROR", "error"), ("DISABLED", "disabled"), ("ACTIVE", "enabled"),
                            ("OUT OF DATE", "out-of-date"), ("INITIALIZED", "initialized"),
                            ("query-failed", "unavailable"), ("ERROR SECRET_INFO_STATE", "unknown")):
            with self.subTest(info=info):
                result = self.extension_wait(case="missing", info=info)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stderr.count(" state=" + state + "\n"), 8, result.stderr)
                self.assertNotIn("SECRET_INFO", result.stderr)
                self.assertNotIn("/private", result.stderr)

    def test_extension_wait_exact_and_delayed_positives(self):
        for case in ("exact", "delayed"):
            result = self.extension_wait(case)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "blur-my-shell@aunetx\ncaffeine@patapon.info")
            self.assertNotIn("GNOME_EXTENSION_DIAGNOSTIC", result.stderr)

    def test_extension_timeout_distinguishes_failures_and_redacts_unknown_data(self):
        for case, reason, field in (("missing", "enabled-set-mismatch", "missing_known_count=1"),
                                    ("unexpected", "enabled-set-mismatch", "unexpected_count=1"),
                                    ("duplicate", "enabled-set-mismatch", "duplicate_count=1"),
                                    ("query-failure", "query-failed", "actual_count=0")):
            with self.subTest(case=case):
                result = self.extension_wait(case)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("reason=" + reason, result.stderr)
                self.assertIn(field, result.stderr)
                self.assertIn("expected_count=2", result.stderr)
                self.assertIn("disabled_user_extensions=false", result.stderr)
                self.assertIn("known_extension=caffeine@patapon.info expected=yes", result.stderr)
                self.assertNotIn("SECRET_", result.stderr)
                self.assertNotIn("/tmp/", result.stderr)
                self.assertLessEqual(len(result.stderr.splitlines()), 9)
                self.assertLess(len(result.stderr), 4096)

    def test_extension_timeout_disabled_flag_is_a_fixed_enum(self):
        for raw, expected in (("true", "true"), ("false", "false"), ("SECRET_ARBITRARY_STATE", "unavailable")):
            result = self.extension_wait("missing", raw)
            self.assertIn("disabled_user_extensions=" + expected, result.stderr)
            self.assertNotIn("SECRET_", result.stderr)

    def test_normal_gdm_routes_use_activation_guard(self):
        host = (ROOT / "tests/vm/run.sh").read_text()
        self.assertIn("activate_gdm_password_conversation firstboot", host)
        self.assertIn("activate_gdm_password_conversation postreboot", host)
        self.assertIn("activate_gdm_password_conversation snapshot", host)
        body = re.search(r"^marble_gdm_login\(\) \{\n.*?^\}", host, re.M | re.S).group(0)
        for status in (0, 1):
            with tempfile.TemporaryDirectory() as temporary:
                script = "set -euo pipefail\nevidence=\"$1\"\nactivate_gdm_password_conversation(){ return " + str(status) + "; }\nhmp_type_password(){ printf 'PASSWORD_SENT\n'; }\nqga_verify(){ :; }\n" + body + "\nmarble_gdm_login firstlogin fixture\n"
                result = subprocess.run(["bash", "-c", script, "login-guard-fixture", temporary], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, status)
                self.assertEqual("PASSWORD_SENT" in result.stdout, status == 0)

    def test_gdm_activation_evidence_is_exact_and_unambiguous(self):
        host = (ROOT / "tests/vm/run.sh").read_text()
        body = re.search(r"^parse_gdm_activation_evidence\(\) \{\n.*?^\}", host, re.M | re.S).group(0)
        line = "GDM_ACTIVATION_DIAGNOSTIC run_id=fixture phase=gdm-activation-check daemon=10.100 greeter=c1 worker_ids=20.200 new_worker=20.200 activation=started\n"
        for content, expected in ((line, 0), (line * 2, 1), (line.replace("run_id=fixture", "run_id=other"), 1), (line.replace("new_worker=20.200", "new_worker=none"), 1)):
            with tempfile.TemporaryDirectory() as temporary:
                file = Path(temporary) / "probe.stdout"; file.write_text(content)
                result = subprocess.run(["bash", "-c", "set -euo pipefail\nrun_id=fixture\n" + body + "\nparse_gdm_activation_evidence \"$1\" gdm-activation-check\n", "gdm-marker-fixture", str(file)], capture_output=True, timeout=5)
                self.assertEqual(result.returncode, expected)

    def snapshot_runtime(self, argument="root=/dev/vda2", changed=""):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); state = root / "snapshot.state"; lower = root / "lower"; lower.mkdir()
            marker = lower / "var/lib/arch-linux-vm/snapshot-marker"; marker.parent.mkdir(parents=True); marker.write_text("grub-20261004T000000Z-aabbccdd")
            uuid = "11111111-1111-1111-1111-111111111111"; partuuid = "22222222-2222-2222-2222-222222222222"
            state.write_text("run_id=grub-20261004T000000Z-aabbccdd\nsubvol=@snapshots/qa-grub-20261004T000000Z-aabbccdd\nroot_uuid=" + uuid + "\nnormal_boot_id=33333333-3333-3333-3333-333333333333\nroot_device=/dev/vda2\nroot_partuuid=" + partuuid + "\nselector_sha256=" + "a" * 64 + "\nproduction_cfg_sha256=" + "b" * 64 + "\nsnapshot_root_id=257\nsnapshot_marker_inode=1234\nroot_major=254\nroot_minor=2\n")
            state.chmod(0o600)
            import json
            expected, rows = self.proof_fixture()
            expected["fsUuid"] = uuid
            rows = [row.replace("fsid=1234567812341234", "fsid=" + uuid.replace("-", "")[:16]).replace("fsid=1234123456789abc", "fsid=" + uuid.replace("-", "")[16:]) for row in rows]
            (root / "checker.py").write_text(self.snapshot_program("snapshot_backing_checker_program", "SNAPSHOT_CHECKER_PY"))
            (root / "state.py").write_text(self.snapshot_program("snapshot_state_program", "SNAPSHOT_STATE_PY"))
            (root / "units.py").write_text(self.snapshot_program("snapshot_unit_program", "SNAPSHOT_UNIT_PY"))
            (root / "proof.stdout").write_bytes(self.proof_output(rows)); (root / "proof.stderr").write_bytes(b"")
            (root / "expected.json").write_text(json.dumps(expected))
            if changed == "state-lines": state.write_text(state.read_text() + "SECRET_EXTRA\n")
            if changed == "state-run": state.write_text(state.read_text().replace("run_id=grub-20261004T000000Z-aabbccdd", "run_id=SECRET_ID"))
            if changed == "state-subvol": state.write_text(state.read_text().replace("subvol=@snapshots/qa-grub-20261004T000000Z-aabbccdd", "subvol=SECRET_PATH"))
            if changed == "cfg-record": state.write_text(state.read_text().replace("production_cfg_sha256=", "unknown="))
            if changed == "cfg-hash": state.write_text(state.read_text().replace("b" * 64, "c" * 64))
            if changed == "root-uuid": state.write_text(state.read_text().replace(uuid, "SECRET_UUID"))
            if changed == "marker": marker.write_text("SECRET_MARKER")
            commandline = root / "cmdline"; commandline.write_text(argument.replace("uuid", uuid).replace("part-id", partuuid) + " rootflags=subvol=@snapshots/qa-grub-20261004T000000Z-aabbccdd systemd.volatile=overlay")
            body = "\n".join(function(name) for name in ("snapshot_root_argument_matches", "snapshot_lowerdir_matches", "snapshot_expected_readback", "require_kernel_argument_once", "require_prefixed_kernel_argument_once", "verify_snapshot_runtime"))
            if "snapshot_runtime_fail() {" in VERIFY.read_text(): body = function("snapshot_runtime_fail") + "\n" + body
            body = body.replace('/boot/qa-snapshot-${run_id}.state', str(state)).replace('/proc/cmdline', str(commandline))
            script = r'''set -euo pipefail
run_id=grub-20261004T000000Z-aabbccdd scenario=stock-gnome-btrfs-grub phase=snapshot-prelogin
fixture_lower=$1
fixture_uuid=$2
fixture_partuuid=$3
changed=$4
fixture_root=${fixture_lower%/lower}
[(){ if [[ "$*" = '-b /dev/vda2 ]' ]]; then return 0; fi; builtin [ "$@"; }
stat(){ if [[ "$*" = *'%i'* ]]; then printf 1234; elif [[ "$*" = *'%u:%a:%h:%s'* ]]; then printf '0:600:1:31'; elif [ "$changed" = state-mode ]; then printf '1000:644:1'; else printf '0:600:1'; fi; }
sha256sum(){ printf '%s fixture' bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; }
findmnt(){
    case "$*" in
        *FSTYPE*'target /') if [ "$changed" = root-type ]; then printf btrfs; else printf overlay; fi;;
        *FSTYPE*) if [ "$changed" = lower-type ]; then printf SECRET_VALUE; else printf btrfs; fi;;
        *FSROOT*) if [ "$changed" = lower-subvol ]; then printf /SECRET_PATH; else printf /@snapshots/qa-grub-20261004T000000Z-aabbccdd; fi;;
        *OPTIONS*'target /') if [ "$changed" = root-options-query ]; then return 1; elif [ "$changed" = lower-shape ]; then printf lowerdir=SECRET_RELATIVE; else printf 'lowerdir=%s' "$fixture_lower"; fi;;
        *OPTIONS*) if [ "$changed" = lower-options-query ]; then return 1; elif [ "$changed" = lower-rw ]; then printf rw; else printf ro; fi;;
        *UUID*) if [ "$changed" = lower-uuid ]; then printf wrong; else printf '%s' "$fixture_uuid"; fi;;
    esac
}
btrfs(){ if [[ "$*" = *rootid* ]]; then printf 257; elif [ "$changed" = property ]; then printf ro=false; else printf ro=true; fi; }
mounted_source_device(){ if [ "$changed" = device ]; then printf /dev/vda3; else printf /dev/vda2; fi; }
find_target(){ printf /dev/vda; }
partition_name(){ if [ "$changed" = device ]; then printf /dev/vda3; else printf /dev/vda2; fi; }
mount(){ return 0; }
snapshot_failed_units(){ python3 - "$fixture_root/units.py" "$run_id" "$phase" "$changed" <<'FIXTURE_UNITS_PY'
import runpy, sys
namespace = runpy.run_path(sys.argv[1])
def query(arguments):
    if sys.argv[4] == "failed-query": return False, b""
    if sys.argv[4] == "failed-units": return True, b"secret-fixture.service loaded failed failed SECRET_MESSAGE\n"
    return True, b""
raise SystemExit(namespace["inspect_units"](sys.argv[2], sys.argv[3], query))
FIXTURE_UNITS_PY
}
snapshot_validate_metadata(){ python3 - "$fixture_root/state.py" "$1" "$changed" <<'FIXTURE_METADATA_PY'
import os, runpy, sys
from unittest.mock import patch
namespace = runpy.run_path(sys.argv[1])
original = os.fstat
# The command fixture models guest UID0; state-mode deliberately models foreign ownership.
def guest_metadata(fd):
    value = list(original(fd)); value[4] = 1000 if sys.argv[3] == "state-mode" else 0
    return os.stat_result(value)
try:
    with patch.object(namespace["os"], "fstat", guest_metadata):
        namespace["load_metadata"](sys.argv[2])
except (OSError, ValueError):
    raise SystemExit(1)
FIXTURE_METADATA_PY
}
snapshot_validate_state(){ python3 - "$fixture_root/state.py" "$1" "$run_id" "$2" <<'FIXTURE_STATE_PY'
import runpy, sys
from pathlib import Path
runpy.run_path(sys.argv[1])["parse_state"](Path(sys.argv[2]).read_bytes(), sys.argv[3], sys.argv[4])
FIXTURE_STATE_PY
}
snapshot_device_numbers(){ printf 254:2; }
verify_snapshot_backing(){
    snapshot_expected_readback "$fixture_lower" "$1" "$2" "$3" "$4" "$5" || return 1
    python3 "$fixture_root/checker.py" positive "$fixture_root/proof.stdout" "$fixture_root/proof.stderr" "$fixture_root/expected.json" 0 >/dev/null || { snapshot_runtime_fail lower-source-query; return 1; }
}
blkid(){
    if [[ "$*" = *PARTUUID* ]]; then
        if [ "$changed" = partuuid ]; then printf wrong; else printf '%s' "$fixture_partuuid"; fi
    else
        if [ "$changed" = uuid ]; then printf wrong; else printf '%s' "$fixture_uuid"; fi
    fi
}
verify_kernel_initramfs_pair(){ [ "$changed" != modules ]; }
verify_grub_efi_target(){ [ "$changed" != efi ]; }
verify_grub_package_integrity(){ [ "$changed" != package ]; }
systemctl(){ if [[ "$*" = *is-active* ]]; then [ "$changed" != service ]; elif [ "$changed" = failed-units ]; then printf SECRET_UNIT; elif [ "$changed" = failed-query ]; then return 1; fi; }
nm-online(){ [ "$changed" != network ]; }
''' + body + "\ntarget=$(verify_snapshot_runtime) || exit 1\nprintf '%s' \"$target\"\n"
            return subprocess.run(["bash", "-c", script, "snapshot-runtime-fixture", str(lower), uuid, partuuid, changed], capture_output=True, text=True, timeout=5)

    def test_actual_snapshot_runtime_accepts_proven_root_forms(self):
        for argument in ("root=/dev/vda2", "root=UUID=uuid", "root=PARTUUID=part-id"):
            with self.subTest(argument=argument):
                result = self.snapshot_runtime(argument)
                self.assertEqual(result.returncode, 0, result.stderr)
    def test_actual_snapshot_runtime_rejects_root_identity_and_module_changes(self):
        for changed in ("device", "uuid", "partuuid", "lower-uuid", "modules"):
            with self.subTest(changed=changed): self.assertNotEqual(self.snapshot_runtime(changed=changed).returncode, 0)
        for argument in ("root=/dev/vda3", "root=/dev/vda2 root=UUID=uuid"):
            with self.subTest(argument=argument): self.assertNotEqual(self.snapshot_runtime(argument).returncode, 0)

    def test_snapshot_runtime_failure_reasons_survive_command_substitution(self):
        cases = {"state-mode": "state-mode", "state-lines": "state-lines", "state-run": "state-run", "state-subvol": "state-subvolume", "cfg-record": "cfg-record", "cfg-hash": "cfg-hash", "root-uuid": "root-uuid", "marker": "lower-marker", "root-type": "root-filesystem", "root-options-query": "root-options-query", "lower-shape": "lower-shape", "lower-type": "lower-filesystem", "lower-subvol": "lower-subvolume", "lower-rw": "lower-readonly", "lower-options-query": "lower-options-query", "lower-uuid": "lower-uuid", "property": "lower-property", "device": "target-partition", "uuid": "device-identity", "partuuid": "device-identity", "modules": "kernel-initramfs", "efi": "grub-efi", "package": "grub-package", "service": "services", "network": "network", "failed-units": "failed-units"}
        for changed, reason in cases.items():
            with self.subTest(changed=changed):
                result = self.snapshot_runtime(changed=changed)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                expected = "SNAPSHOT_RUNTIME_DIAGNOSTIC run_id=grub-20261004T000000Z-aabbccdd phase=snapshot-prelogin reason=" + reason + "\n"
                if changed == "failed-units":
                    expected = "SNAPSHOT_UNIT_DIAGNOSTIC run_id=grub-20261004T000000Z-aabbccdd phase=snapshot-prelogin query=success count=1 unknown_count=1\n" + expected
                self.assertEqual(result.stderr, expected)
                self.assertNotIn("SECRET", result.stderr)
        result = self.snapshot_runtime(argument="root=/dev/vda3")
        self.assertIn("reason=root-argument\n", result.stderr)

    def test_snapshot_runtime_diagnostic_rejects_unknown_and_raw_fields(self):
        self.assertTrue("snapshot_runtime_fail() {" in VERIFY.read_text(), "diagnostic helper absent")
        body = function("snapshot_runtime_fail")
        result = subprocess.run(["bash", "-c", body + "\nrun_id=$'SECRET\\nPATH' phase=SECRET snapshot_runtime_fail SECRET_REASON\n"], capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "SNAPSHOT_RUNTIME_DIAGNOSTIC run_id=unavailable phase=unavailable reason=unknown\n")
        result = subprocess.run(["bash", "-c", body + "\nrun_id=grub-20261004T123456Z-1234abcd phase=snapshot-login snapshot_runtime_fail lower-filesystem\n"], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "SNAPSHOT_RUNTIME_DIAGNOSTIC run_id=grub-20261004T123456Z-1234abcd phase=snapshot-login reason=lower-filesystem\n")

    def test_guarded_gdm_activation_withholds_password_until_new_stable_worker(self):
        host = (ROOT / "tests/vm/run.sh").read_text()
        body = re.search(r"^activate_gdm_password_conversation\(\) \{\n.*?^\}", host, re.M | re.S).group(0)
        for outcome, expected in (("delayed", 0), ("never", 1), ("ambiguous", 1), ("changed", 1)):
            script = r'''set -euo pipefail
outcome=$1
checks=0
last_boot_id=boot
qga_verify() {
    last_gdm_daemon_identity=1.10
    last_gdm_greeter_session=c1
    if [ "$1" = gdm-activation-baseline ]; then
        last_gdm_worker_ids=none
        last_gdm_activation_status=baseline
    else
        checks=$((checks+1))
        last_gdm_activation_status=pending
        last_gdm_worker_ids=none
        last_gdm_new_worker_identity=none
        if [ "$outcome" = ambiguous ]; then return 1; fi
        if [ "$outcome" != never ] && [ "$checks" -ge 3 ]; then
            last_gdm_activation_status=started
            last_gdm_worker_ids=2.20
            last_gdm_new_worker_identity=2.20
            if [ "$outcome" = changed ] && [ "$checks" -ge 4 ]; then last_gdm_worker_ids=3.30; last_gdm_new_worker_identity=3.30; fi
        fi
    fi
}
hmp_request(){ printf 'ACTIVATION_KEY\n'; }
sleep(){ :; }
die(){ return 1; }
''' + body + "\nactivate_gdm_password_conversation fixture\nprintf 'PASSWORD_ALLOWED\n'\n"
            result = subprocess.run(["bash", "-c", script, "gdm-activation-fixture", outcome], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, expected, result.stderr)
            self.assertEqual("PASSWORD_ALLOWED" in result.stdout, expected == 0)
            self.assertLessEqual(result.stdout.count("ACTIVATION_KEY"), 30)

    def test_snapshot_entry_exact(self):
        result = self.snapshot_entry(); self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Arch snapshots>snapshot fixture>linux")
    def test_snapshot_wrong_entry(self): self.assertNotEqual(self.snapshot_entry(rootflags="subvol=@").returncode, 0)
    def test_snapshot_wrong_device(self):
        for root in ("UUID=other", "/dev/vda3", "PARTUUID=other", "/dev/vda2 root=UUID=fixture"):
            with self.subTest(root=root): self.assertNotEqual(self.snapshot_entry(root=root).returncode, 0)
    def test_snapshot_wrong_image(self): self.assertNotEqual(self.snapshot_entry(image="/initramfs-other.img").returncode, 0)
    def test_snapshot_lowerdir_identity(self):
        body = function("snapshot_runtime_fail") + "\n" + function("snapshot_lowerdir_matches")
        for fsroot, expected in (("/@snapshots/qa-fixture", 0), ("/@", 1), ("/@snapshots/foreign", 1)):
            script = "findmnt(){ case \"$*\" in *FSTYPE*) printf btrfs;; *FSROOT*) printf '" + fsroot + "';; *OPTIONS*) printf ro;; esac; }\n" + body + "\nsnapshot_lowerdir_matches /lower @snapshots/qa-fixture\n"
            result = subprocess.run(["bash", "-c", script], capture_output=True, timeout=5)
            self.assertEqual(result.returncode, expected)
    def neighbor(self, changed=False, wrong_identity=False):
        body = function("verify_neighbor_readback")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); data = root / "neighbor"; data.mkdir()
            names = ("etc/hostname", "etc/fstab", "neighbor-preserved.txt", "boot/EFI/ali-neighbor/vmlinuz-linux", "boot/EFI/ali-neighbor/initramfs-linux.img", "boot/loader/entries/neighbor.conf")
            import hashlib
            manifest = root / "neighbor.sha256"
            lines = []
            for name in names:
                item = data / name; item.parent.mkdir(parents=True, exist_ok=True); item.write_text(name)
                lines.append(hashlib.sha256(item.read_bytes()).hexdigest() + "  " + name)
            manifest.write_text("\n".join(lines) + "\n")
            proof = root / "neighbor-identities.txt"
            proof.write_text("run_id=fixture\nesp_uuid=esp\nesp_partuuid=esp-part\nneighbor_uuid=neighbor\nneighbor_partuuid=neighbor-part\n")
            if changed: (data / names[-1]).write_text("altered")
            uuid = "wrong" if wrong_identity else "esp"
            script = "set -euo pipefail\nrun_id=fixture phase=neighbor-select\nstat(){ printf '0:600:1'; }\nblkid(){ case \"$*\" in *PARTUUID*esp*) printf esp-part;; *PARTUUID*neighbor*) printf neighbor-part;; *esp*) printf '" + uuid + "';; *neighbor*) printf neighbor;; esac; }\n" + body + "\nverify_neighbor_readback '" + str(proof) + "' '" + str(manifest) + "' '" + str(data) + "' esp neighbor\n"
            return subprocess.run(["bash", "-c", script], capture_output=True, timeout=5).returncode
    def test_neighbor_exact_baseline(self): self.assertEqual(self.neighbor(), 0)
    def test_neighbor_changed_after_update(self): self.assertNotEqual(self.neighbor(changed=True), 0)
    def test_neighbor_wrong_identity(self): self.assertNotEqual(self.neighbor(wrong_identity=True), 0)
    def test_snapshot_host_route_boots_and_returns(self):
        host = (ROOT / "tests/vm/run.sh").read_text()
        body = re.search(r"^run_snapshot_acceptance\(\) \{\n.*?^\}", host, re.M | re.S).group(0)
        script = """set -euo pipefail
post_boot_id=normal last_boot_id=normal
qga_verify(){ printf '%s\n' "$1"; }
schedule_transition(){ :; }
wait_qemu_exit(){ :; }
launch_qemu(){ last_boot_id="$1"; }
wait_qga(){ :; }
hmp_request(){ :; }
sleep(){ :; }
hmp_type_password(){ :; }
activate_gdm_password_conversation(){ :; }
record_assertion(){ :; }
die(){ return 1; }
""" + body + "\nrun_snapshot_acceptance\n"
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["snapshot-prepare", "snapshot-prelogin", "snapshot-login", "snapshot-cleanup", "postreboot-prelogin"])
    def test_real_gdm_helper_unsafe_ancestry(self):
        import os
        body = function("exercise_gdm_helper_failure")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            directory = root / "etc/systemd/user/org.gnome.Shell@gdm.service.d"
            directory.mkdir(parents=True)
            for path in (root / "etc", root / "etc/systemd", root / "etc/systemd/user", directory): path.chmod(0o755)
            payload = root / "usr/share/arch-linux-marble-gdm/systemd/50-arch-linux-marble-gdm.conf"
            payload.parent.mkdir(parents=True); payload.write_text("fixture")
            (directory / "50-arch-linux-marble-gdm.conf").symlink_to(payload)
            helper = ROOT / "packages/arch-linux-marble-gdm/update-compatibility"
            script = "set -euo pipefail\n" + body + "\nexercise_gdm_helper_failure '" + str(directory) + "' '" + str(helper) + "' '" + str(payload) + "'\n"
            result = subprocess.run(["bash", "-c", script], env={**os.environ, "ARCH_LINUX_MARBLE_GDM_TEST_ROOT": tmp}, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("prepare_status=1 status_status=1", result.stdout)
            self.assertEqual(directory.stat().st_mode & 0o777, 0o755)
    def collision(self, content):
        host = (ROOT / "tests/vm/run.sh").read_text()
        body = re.search(r"^verify_collision_refusal_marker\(\) \{\n.*?^\}", host, re.M | re.S).group(0)
        with tempfile.TemporaryDirectory() as tmp:
            logfile = Path(tmp) / "serial.log"; logfile.write_text(content)
            script = "set -euo pipefail\nrun_id=fixture\ndie(){ return 1; }\n" + body + "\nverify_collision_refusal_marker '" + str(logfile) + "'\nprintf '%s:%s' \"$collision_esp_sha256\" \"$collision_root_sha256\"\n"
            return subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
    def test_collision_marker_exact_bound(self):
        line = "MINIMAL_QEMU_ESP_COLLISION_REFUSAL_PASS run_id=fixture esp_sha256=" + "a" * 64 + " root_sha256=" + "b" * 64
        for terminator in ("\n", "\r\n"):
            result = self.collision(line + terminator)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "a" * 64 + ":" + "b" * 64)
    def test_collision_marker_malformed_rejected(self):
        line = "MINIMAL_QEMU_ESP_COLLISION_REFUSAL_PASS run_id=fixture esp_sha256=" + "a" * 64 + " root_sha256=" + "b" * 64
        for malformed in ("", line + "\n" + line, line.replace("fixture", "other"), "prefix " + line, line + " suffix", line.replace("a" * 64, "a" * 63), line.replace("b" * 64, "B" * 64), line.replace("esp_sha256=", "root_sha256=")):
            with self.subTest(malformed=malformed): self.assertNotEqual(self.collision(malformed).returncode, 0)
    def test_snapshot_production_quoted_subvol(self):
        # grub-btrfs v4.14 emits rootflags options followed by subvol="path".
        result = self.snapshot_entry(rootflags='noatime,compress=zstd,subvol="@snapshots/qa-fixture"')
        self.assertEqual(result.returncode, 0, result.stderr)
    def test_snapshot_path_aliases_rejected(self):
        for path in ("@snapshots/../qa-fixture", "//@snapshots/qa-fixture", "@snapshots/qa-fixture-extra"):
            self.assertNotEqual(self.snapshot_entry(rootflags="subvol=" + path).returncode, 0)
    def test_actual_dualboot_route_requires_collision_proof(self):
        host = (ROOT / "tests/vm/run.sh").read_text()
        helper = re.search(r"^verify_collision_refusal_marker\(\) \{\n.*?^\}", host, re.M | re.S).group(0)
        route = re.search(r'        if \[ "\$\{scenario_id\}" = minimal-dualboot-ext4-systemdboot \]; then\n.*?            shutdown_phase=neighbor\n        fi', host, re.S).group(0)
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "install-serial.log"
            line = "MINIMAL_QEMU_ESP_COLLISION_REFUSAL_PASS run_id=fixture esp_sha256=" + "a" * 64 + " root_sha256=" + "b" * 64 + "\n"
            script = "set -euo pipefail\nscenario_id=minimal-dualboot-ext4-systemdboot run_id=fixture evidence='" + tmp + "'\ndie(){ return 1; }\nqga_verify(){ printf '%s\\n' \"$1\"; }\nrecord_assertion(){ :; }\nschedule_transition(){ :; }\nwait_qemu_exit(){ :; }\nlaunch_qemu(){ :; }\nwait_qga(){ :; }\ncapture_screen(){ :; }\n" + helper + "\n" + route
            for marker, expected in ((line, 0), ("", 1)):
                log.write_text(marker + "MINIMAL_QEMU_NEIGHBOR_PRESERVED run_id=fixture\n")
                result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, expected, result.stderr)
                if expected == 0: self.assertEqual(result.stdout.splitlines(), ["neighbor-select", "neighbor"])
                else: self.assertEqual(result.stdout, "")
    def test_matching_boot(self): self.assertEqual(self.kernel(), 0)
    def test_marble_update_checks_new_disk_kernel_before_reboot(self):
        branch = function("run_marble_phase").split("    update)\n", 1)[1].split("        ;;", 1)[0]
        for mode in ("public", "staged"):
            for pair_status in (0, 1):
                with self.subTest(mode=mode, pair_status=pair_status):
                    script = "set -euo pipefail\ninput_mode=" + mode + "\nphase=update\n"
                    script += "pacman(){ :; }\nverify_public_repository_contract(){ :; }\n"
                    script += "verify_marble_packages(){ :; }\nverify_vendor_integrity(){ :; }\nmarble_gdm_enabled(){ return 1; }\n"
                    script += "verify_kernel_initramfs_pair(){ printf 'PAIR_CHECKED:%s\\n' \"$*\"; return " + str(pair_status) + "; }\n"
                    script += "emit_marble_action_pass(){ printf 'PASS:%s\\n' \"$*\"; }\n" + branch
                    result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
                    self.assertIn("PAIR_CHECKED:/boot/initramfs-linux.img", result.stdout)
                    self.assertEqual(result.returncode, pair_status, result.stderr)
                    self.assertEqual("PASS:" in result.stdout, pair_status == 0)

    def test_qga_request_preserves_script_larger_than_exec_argument_limit(self):
        import base64, json
        body = self.host_function("qga_verify")
        script_bytes = "# harmless fixture\n" * 8000 + "cat >/dev/null\nprintf 'fixture\n'\nprintf 'phase=%s argc=%s\\n' \"$1\" \"$#\"\n"
        self.assertGreater(len(script_bytes.encode()), 128 * 1024)
        globals_used = "target_serial target_model run_id scenario_id repository_primary_fingerprint repository_signing_fingerprint release_version pages_url snapshot_sha256 source_commit source_tree installer_sha256 repository_package_set_sha256 build_metadata_sha256 unsigned_manifest_sha256 repository_public_key_sha256 target_disk_metadata".split()
        marker = "MINIMAL_QEMU_GUEST_PASS run_id=fixture scenario=fixture phase=firstboot boot_id=00000000-0000-0000-0000-000000000001 target=fixture\n"
        for exit_code in (0, 1):
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); (root / "guest").mkdir(); (root / "guest/verify.sh").write_text(script_bytes)
                response = json.dumps({"return": {"exited": True, "exitcode": exit_code, "out-data": base64.b64encode(marker.encode()).decode(), "err-data": "", "out-truncated": False}})
                program = "set -euo pipefail\n" + body + "\n" + "\n".join(name + "=fixture" for name in globals_used)
                program += r"""
script_dir="$1" evidence="$1" response="$2" input_mode=staged marker_prefix=MINIMAL media_qualification=false gnome51_upgrade_manifest_sha256=-
die(){ exit 2; }
qga_call(){ if [[ "$1" = *guest-exec-status* ]]; then printf '%s
' "$response"; else printf '%s
' "$1" > "$evidence/transmitted-request.json"; printf '%s
' '{"return":{"pid":1}}'; fi; }
qga_verify firstboot fixture
printf 'VERIFY_CONTINUED
'
"""
                result = subprocess.run(["bash", "-c", program, "fixture", str(root), response], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0 if exit_code == 0 else 2, result.stderr)
                self.assertEqual("VERIFY_CONTINUED" in result.stdout, exit_code == 0)
                request = json.loads((root / "transmitted-request.json").read_bytes())
                self.assertLess(len(json.dumps(request).encode()), 1_048_576)
                arguments = request["arguments"]
                decoded = base64.b64decode(arguments["input-data"], validate=True)
                self.assertEqual(decoded, script_bytes.encode())
                self.assertEqual(arguments["arg"][3], "firstboot")
                self.assertTrue(all(len(arg.encode()) < 128 * 1024 for arg in arguments["arg"]))
                execution = subprocess.run([arguments["path"], *arguments["arg"]], input=decoded, capture_output=True, timeout=5)
                self.assertEqual(execution.returncode, 0, execution.stderr)
                self.assertEqual(execution.stdout, b"fixture\nphase=firstboot argc=27\n")
                self.assertEqual(request["arguments"]["arg"][-2:], ["false", "-"])

    def host_function(self, name):
        return re.search(r"^" + name + r"\(\) \{\n.*?^\}", (ROOT / "tests/vm/run.sh").read_text(), re.M | re.S).group(0)

    def test_archiso_probe_requires_exact_complete_unique_current_nonce(self):
        body = self.host_function("serial_archiso_ready")
        marker = "ARCHISO-READY-stock-20261009T070018Z-1ca6689d-2"
        cases = [(marker + "\r\n", 0), (marker, 1), ("echo " + marker + "\n", 1),
                 (marker[:-1] + "1\n", 1), (marker + "extra\n", 1),
                 (marker + "\n" + marker + "\n", 2), ("", 1)]
        for content, expected in cases:
            with self.subTest(content=content), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "serial"; path.write_bytes(content.encode())
                result = subprocess.run(["bash", "-c", body + '\nserial_archiso_ready "$1" "$2"',
                                         "fixture", str(path), marker], capture_output=True, timeout=5)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_install_outcome_distinguishes_failure_shutdown_bridge_and_deadline(self):
        body = self.host_function('wait_for_install_outcome')
        program = 'set -uo pipefail\n' + body + r'''
qemu_pid=123 qemu_start_time=fixture serial_bridge_pid=456 marker_prefix=STOCK
mode="$2"
process_is_exact_qemu(){ [ "$mode" != qemu ]; }
kill(){ [ "$mode" != bridge ]; }
sleep(){ SECONDS=$((SECONDS + 1)); }
wait_for_install_outcome "$1" 'STOCK_QEMU_INSTALL_COMPLETE run_id=fixture' 'Show Logs?' 2
'''
        success = 'STOCK_QEMU_INSTALL_COMPLETE run_id=fixture\n'
        failed = 'STOCK_QEMU_INSTALLER_EXIT status=1\n'
        cases = [(success, 'alive', 0), (failed, 'alive', 2), (failed, 'qemu', 2),
                 (failed + success, 'alive', 2), ('Show Logs?\n', 'alive', 2),
                 ('STOCK_QEMU_INSTALLER_EXIT status=0\n', 'qemu', 3),
                 ('', 'bridge', 4), ('', 'alive', 1),
                 ('STOCK_QEMU_INSTALLER_EXIT status=1wrong\n', 'alive', 1)]
        for content, mode, expected in cases:
            with self.subTest(content=content, mode=mode), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'serial'; path.write_text(content)
                result = subprocess.run(['bash', '-c', program, 'fixture', str(path), mode],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_archiso_wait_retries_only_public_probe_and_rejects_stale_reply(self):
        body = self.host_function("serial_archiso_ready") + "\n" + self.host_function("wait_for_archiso_shell")
        program = 'set -euo pipefail\n' + body + r'''
evidence="$1" mode="$2" run_id=stock-20261009T070018Z-1ca6689d
qemu_pid=$$ qemu_start_time=fixture serial_bridge_pid=$$
sleep(){ SECONDS=$((SECONDS + $1)); }
process_is_exact_qemu(){ [ "$mode" != dead ]; }
hmp_request(){
    printf 'TYPE:%s\n' "$2"
    [ "$mode" != transport ] || return 1
    token="${2#echo }"; token="${token%% *}"
    case "$mode" in
      fresh) printf '%s\n' "$token" >>"$evidence/install-serial.log" ;;
      delayed) if [[ "$token" = *-2 ]]; then printf '%s\n' "$token" >>"$evidence/install-serial.log"; fi ;;
      stale) printf '%s\n' "${token%-*}-0" >>"$evidence/install-serial.log" ;;
    esac
}
wait_for_archiso_shell 25
printf 'READY\n'
'''
        for mode, expected_probes, succeeds in [('fresh', 1, True), ('delayed', 2, True),
                                               ('stale', 3, False), ('dead', 1, False), ('transport', 1, False)]:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                result = subprocess.run(['bash', '-c', program, 'fixture', tmp, mode],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, succeeds, result.stderr)
                self.assertEqual(result.stdout.count('TYPE:'), expected_probes, result.stdout)
                self.assertEqual('READY\n' in result.stdout, succeeds)
                self.assertNotIn('LABEL=ALIPAY', result.stdout)

    def test_archiso_bootstrap_and_credentials_follow_readiness_once(self):
        source = (ROOT / 'tests/vm/run.sh').read_text()
        fragment = source.split("    current_phase='install-archiso'\n", 1)[1].split('    set +e\n', 1)[0]
        program = 'set -euo pipefail\n' + r'''
mode="$1" bootstrap_command=INSTALLER scenario_id=minimal-ext4-systemdboot
launch_qemu(){ printf 'LAUNCH\n'; }
sleep(){ :; }
wait_for_archiso_shell(){ printf 'PROBE\n'; [ "$mode" = ready ]; }
hmp_request(){ printf 'BOOTSTRAP:%s\n' "$2"; }
deliver_installer_credentials(){ printf 'CREDENTIAL_GATE\n'; }
die(){ exit 1; }
''' + fragment
        for mode in ('ready', 'timeout'):
            result = subprocess.run(['bash', '-c', program, 'fixture', mode], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode == 0, mode == 'ready', result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['LAUNCH', 'PROBE', 'BOOTSTRAP:INSTALLER', 'CREDENTIAL_GATE']
                             if mode == 'ready' else ['LAUNCH', 'PROBE'])

    def test_hmp_public_probe_redirection_uses_complete_released_keys(self):
        import os, socket, threading
        commands = []
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / 'hmp')
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                server.bind(path); server.listen(1); server.settimeout(5)
                def serve():
                    connection, _ = server.accept()
                    with connection:
                        connection.sendall(b'(qemu) ')
                        pending = b''
                        while chunk := connection.recv(1024):
                            pending += chunk
                            while b'\n' in pending:
                                line, pending = pending.split(b'\n', 1)
                                commands.append(line)
                                connection.sendall(b'(qemu) ')
                thread = threading.Thread(target=serve); thread.start()
                script = 'hmp_socket="$1" qemu_pid="$2"\n' + self.host_function('hmp_request') + '\nhmp_request type "A >/"\n'
                result = subprocess.run(['bash', '-c', script, 'fixture', path, str(os.getpid())],
                                        capture_output=True, text=True, timeout=5)
                thread.join(timeout=5)
                self.assertFalse(thread.is_alive())
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(commands, [b'sendkey shift-a 50', b'sendkey spc 50',
                                            b'sendkey shift-dot 50', b'sendkey slash 50', b'sendkey ret 50'])

    def test_stage_password_prompt_rejects_stale_and_duplicate_marker(self):
        body = self.host_function("serial_stage_password_ready")
        marker = "MINIMAL_QEMU_COLLISION_PROBE_READY run_id=fixture scenario=minimal-dualboot-ext4-systemdboot"
        for content, expected in (("Enter Password\n" + marker + "\n", 1),
                                  (marker + "\r\nEnter Password", 0),
                                  ("Enter Password\n" + marker + "\nEnter Password", 0),
                                  (marker + "\n" + marker + "\nEnter Password", 2),
                                  (marker + "wrong\nEnter Password", 1)):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as tmp:
                log = Path(tmp) / "serial.log"; log.write_text(content)
                result = subprocess.run(["bash", "-c", body + '\nserial_stage_password_ready "$1" "$2"', "fixture", str(log), marker], capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_stage_prompt_accepts_actual_complete_ready_contract(self):
        body = self.host_function("serial_stage_password_ready")
        producer = (ROOT / "tests/vm/guest/bootstrap.sh").read_text()
        fmt = re.search(r"printf '(%s_QEMU_READY[^']+)'", producer).group(1)
        values = ["MINIMAL", "fixture", "minimal-ext4-systemdboot", "public", "a" * 40, "b" * 40] + [letter * 64 for letter in "cdef"]
        line = subprocess.run(["bash", "-c", 'printf "$1" "${@:2}"', "producer", fmt, *values], capture_output=True, text=True, check=True).stdout
        marker = "MINIMAL_QEMU_READY run_id=fixture scenario=minimal-ext4-systemdboot"
        setup = "input_mode=public source_commit=" + "a" * 40 + " source_tree=" + "b" * 40
        setup += " installer_sha256=" + "c" * 64 + " harness_sha256=" + "d" * 64 + " iso_sha256=" + "e" * 64 + " snapshot_sha256=" + "f" * 64 + "\n"
        for content, expected in ((line + "Enter Password", 0),
                                  ("Enter Password\n" + line, 1),
                                  (line + line + "Enter Password", 2),
                                  (line.replace("run_id=fixture", "run_id=fixture-other") + "Enter Password", 1),
                                  (line.replace("scenario=minimal-ext4-systemdboot", "scenario=minimal-ext4-systemdboot-other") + "Enter Password", 1),
                                  ("WRONG_" + line + "Enter Password", 1),
                                  (line.replace("input_mode=public", "input_mode=staged") + "Enter Password", 1),
                                  (marker + "\nEnter Password", 1)):
            with self.subTest(content=content[:120]), tempfile.TemporaryDirectory() as tmp:
                log = Path(tmp) / "serial.log"; log.write_text(content)
                result = subprocess.run(["bash", "-c", setup + body + '\nserial_stage_password_ready "$1" "$2"', "fixture", str(log), marker], capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_installer_two_stage_credentials_only_for_dualboot(self):
        body = self.host_function("deliver_installer_credentials")
        for scenario, count in (("minimal-dualboot-ext4-systemdboot", 2), ("minimal-ext4-systemdboot", 1)):
            script = 'set -euo pipefail\nscenario_id=' + scenario + ' marker_prefix=MINIMAL run_id=fixture evidence=/fixture bootstrap_timeout=1800\n'
            script += 'die(){ exit 1; }; wait_for_marker(){ printf "MARKER:%s\\n" "$2"; }; wait_for_stage_password(){ printf "PROMPT:%s\\n" "$2"; }; send_password(){ printf "DELIVERY\\n"; };\n'
            result = subprocess.run(["bash", "-c", script + body + "\ndeliver_installer_credentials"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.count("DELIVERY"), count)
            self.assertEqual(result.stdout.count("PROMPT:"), count)
            if count == 2:
                self.assertLess(result.stdout.index("COLLISION_PROBE_READY"), result.stdout.index("MINIMAL_QEMU_READY"))

    def test_password_sender_keeps_only_dualboot_first_channel_open(self):
        body = self.host_function("send_password")
        for scenario, expected in (("minimal-dualboot-ext4-systemdboot", "OPEN\nCLOSED\n"), ("minimal-ext4-systemdboot", "CLOSED\n")):
            with tempfile.TemporaryDirectory() as tmp:
                output = Path(tmp) / "private-input"
                script = 'set -euo pipefail\nscenario_id=' + scenario + ' serial_credential_deliveries=0 runtime_password=' + 'a' * 48 + '\nserial_bridge_pid=$$\ndie(){ exit 1; }\nexec {serial_bridge_input_fd}>"$1"\n'
                script += body + '\nsend_password\nif [ -n "$serial_bridge_input_fd" ]; then printf "OPEN\\n"; send_password; fi\n[ -z "$serial_bridge_input_fd" ] && printf "CLOSED\\n"\n'
                result = subprocess.run(["bash", "-c", script, "fixture", str(output)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)
                self.assertEqual(len(output.read_text().splitlines()), 2 if "OPEN" in expected else 1)

    def test_stage_prompt_failure_withholds_password(self):
        body = self.host_function("deliver_installer_credentials")
        for scenario in ("minimal-dualboot-ext4-systemdboot", "minimal-ext4-systemdboot"):
            script = 'set -euo pipefail\nscenario_id=' + scenario + ' marker_prefix=MINIMAL run_id=fixture evidence=/fixture bootstrap_timeout=1\n'
            script += 'die(){ exit 1; }; wait_for_marker(){ return 0; }; wait_for_stage_password(){ return 1; }; send_password(){ printf "PASSWORD_SENT\\n"; };\n'
            result = subprocess.run(["bash", "-c", script + body + "\ndeliver_installer_credentials"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("PASSWORD_SENT", result.stdout)

    def test_protected_serial_bridge_delivery_limits(self):
        import os, socket
        host = self.host_function("start_serial_bridge")
        code = host.split("3<<'PY'\n", 1)[1].split("\nPY", 1)[0]
        for limit, records, expected, deliveries in ((2, [b"a" * 48, b"b" * 48], 0, 4),
                                                    (1, [b"a" * 48], 0, 2),
                                                    (2, [b"a" * 48, b"z" * 48], 1, 2),
                                                    (2, [b"a" * 48, b"b" * 48, b"c" * 48], 1, 4),
                                                    (1, [b"a" * 48 + b"\ntrailing"], 1, 0)):
            with self.subTest(limit=limit, records=len(records)), tempfile.TemporaryDirectory() as tmp:
                path = str(Path(tmp) / "socket"); log = str(Path(tmp) / "serial.log")
                server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); server.bind(path); server.listen(1)
                proc = subprocess.Popen(["python3", "-c", code, path, str(os.getpid()), log, str(limit)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                connection, _ = server.accept(); connection.settimeout(4)
                try:
                    self.assertEqual(proc.stdout.readline(), b"SERIAL_BRIDGE_READY\n")
                    received = b""
                    for index, record in enumerate(records):
                        try:
                            proc.stdin.write(record + b"\n"); proc.stdin.flush()
                        except BrokenPipeError:
                            break
                        needed = 98 if index < limit and len(record) == 48 and set(record) <= set(b"0123456789abcdef") else 0
                        while needed and len(received) < (index + 1) * 98:
                            part = connection.recv(1024)
                            if not part: break
                            received += part
                        if not needed: break
                    try: proc.stdin.close()
                    except BrokenPipeError: pass
                    proc.stdin = None
                    if expected == 0:
                        connection.shutdown(socket.SHUT_WR)
                    _, stderr = proc.communicate(timeout=5)
                    self.assertEqual(proc.returncode, expected, stderr)
                    self.assertEqual(received.count(b"\r"), deliveries)
                    self.assertNotIn(b"a" * 48, Path(log).read_bytes())
                finally:
                    connection.close(); server.close()
                    if proc.poll() is None:
                        proc.kill()
                    proc.communicate(timeout=5)

    def test_upgrade_before_reboot(self): self.assertEqual(self.kernel(phase="update", running="old"), 0)
    def test_stale_running_release(self): self.assertNotEqual(self.kernel(running="old"), 0)
    def test_missing_image(self): self.assertNotEqual(self.kernel(image=False), 0)
    def test_missing_modules(self): self.assertNotEqual(self.kernel(modules=False), 0)
    def test_wrong_boot_image(self): self.assertNotEqual(self.kernel(match=False), 0)
    def test_mixed_initramfs(self): self.assertNotEqual(self.kernel(releases=("new", "old")), 0)
    def test_empty_initramfs(self): self.assertNotEqual(self.kernel(releases=()), 0)
if __name__ == "__main__": unittest.main()
