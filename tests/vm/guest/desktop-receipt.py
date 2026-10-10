#!/usr/bin/env python3
"""Root custody for bounded, native desktop acceptance observations."""
import argparse
import base64
import hashlib
import json
import os
import pwd
from pathlib import Path
import re
import signal
import stat
import subprocess

RUN = re.compile(r"(?:marble|luksgrub)-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}\Z")
ROUNDS = {"firstlogin", "upgrade", "postreboot"}
SOURCES = {
    "shell": ("desktop-shell-probe.js", "desktop-extension-observer.js", "observerSha256"),
    "service": ("desktop-service-probe.js", "desktop-service-runner.js", "serviceSha256"),
}
THEME = "/usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark/gnome-shell/gnome-shell.css"
SETTING_PATHS = (
    '/org/gnome/shell/extensions/caffeine/toggle-shortcut',
    '/org/gnome/shell/extensions/caffeine/user-enabled',
    '/org/gnome/shell/extensions/caffeine/screen-blank',
    '/org/gnome/shell/extensions/blur-my-shell/overview/blur',
    '/org/gnome/shell/extensions/blur-my-shell/overview/pipeline',
    '/org/gnome/shell/extensions/blur-my-shell/pipelines',
    '/org/gnome/shell/extensions/just-perfection/panel',
    '/org/gnome/shell/extensions/just-perfection/panel-in-overview',
    '/org/gnome/shell/extensions/just-perfection/top-panel-position',
    '/org/gnome/shell/extensions/user-theme/name',
)
PROCESS_FIELDS = ('pid', 'starttime', 'executable', 'argv', 'bootId')


def require(condition):
    if not condition:
        raise ValueError("invalid-custody")


def exact_facts(value, expected):
    require(set(value) == set(expected) and all(type(value[key]) is type(item)
            and value[key] == item for key, item in expected.items()))


def read_file(directory, name, uid, mode, limit=16384):
    require(re.fullmatch(r"[a-zA-Z0-9.-]+", name) is not None)
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and before.st_uid == uid and
                stat.S_IMODE(before.st_mode) == mode and before.st_nlink == 1 and before.st_size <= limit)
        data = os.read(fd, limit + 1)
        after = os.fstat(fd)
        linked = os.stat(name, dir_fd=directory, follow_symlinks=False)
        require(len(data) == before.st_size and len(data) <= limit and
                (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) ==
                (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) and
                (before.st_dev, before.st_ino) == (linked.st_dev, linked.st_ino))
        return data
    finally:
        os.close(fd)


def parse(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result)
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=unique, parse_constant=lambda _: require(False))


def directory(path, uid, mode=0o700):
    require(path.is_absolute() and path.resolve() == path)
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    info = os.fstat(fd)
    if info.st_uid != uid or stat.S_IMODE(info.st_mode) != mode:
        os.close(fd)
        require(False)
    return fd


def settings_snapshot(trusted, owner):
    fd = directory(Path(trusted), owner)
    try:
        value = parse(read_file(fd, 'settings.json', owner, 0o600, 65536))
    finally:
        os.close(fd)
    require(isinstance(value, list) and len(value) == len(SETTING_PATHS))
    require(all(isinstance(row, dict) and set(row) == {'path', 'value'} and
                isinstance(row['path'], str) and isinstance(row['value'], str) and
                len(row['value'].encode()) <= 16384 and '\0' not in row['value'] for row in value))
    require([row['path'] for row in value] == list(SETTING_PATHS))
    return value


def print_settings_rows(trusted, selection):
    require(selection in ('all', 'panel'))
    values = settings_snapshot(trusted, os.geteuid())
    for row in values:
        if selection == 'panel' and row['path'] not in SETTING_PATHS[6:8]:
            continue
        print(row['path'] + '\t' + base64.b64encode(row['value'].encode()).decode())


def cleanup_files(state, uid, code, source_root=Path('/run'), root_uid=0):
    """Delete only validated closure entries through retained directory descriptors."""
    state, code = Path(state), Path(code)
    descriptors = []
    try:
        def retain(path, owner, mode):
            fd = directory(path, owner, mode)
            descriptors.append(fd)
            return fd
        user_fd = retain(state, uid, 0o700)
        for parent in (code.parent, code.parent.parent):
            retain(parent, root_uid, 0o755)
        code_fd = retain(code, root_uid, 0o755)
        source_fd = os.open(source_root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        descriptors.append(source_fd)
        allowed = re.compile(r'desktop-(?:shell|service)-(?:metadata|command|ready|[0-9]+-[a-z-]+)\.json\Z')
        entries = os.listdir(user_fd)
        require(len(entries) <= 128)
        for name in entries:
            info = os.stat(name, dir_fd=user_fd, follow_symlinks=False)
            require(allowed.fullmatch(name) and stat.S_ISREG(info.st_mode) and
                    info.st_nlink == 1 and info.st_uid == uid and stat.S_IMODE(info.st_mode) == 0o600)
        sources = os.listdir(code_fd)
        require(set(sources) == {name for names in SOURCES.values() for name in names[:2]})
        for name in sources:
            original = read_file(source_fd, 'arch-linux-qemu-' + name, root_uid, 0o500, 262144)
            copy = read_file(code_fd, name, root_uid, 0o555, 262144)
            require(hashlib.sha256(original).digest() == hashlib.sha256(copy).digest())
        # A replaced pathname must never redirect unlink into another directory.
        for fd, names in ((user_fd, entries), (code_fd, sources)):
            for name in names:
                os.unlink(name, dir_fd=fd)
        for path, fd in ((state, user_fd), (code, code_fd)):
            parent_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            descriptors.append(parent_fd)
            linked = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
            retained = os.fstat(fd)
            require(stat.S_ISDIR(linked.st_mode) and
                    (linked.st_dev, linked.st_ino) == (retained.st_dev, retained.st_ino))
            os.rmdir(path.name, dir_fd=parent_fd)
    finally:
        for fd in reversed(descriptors):
            os.close(fd)


class Custody:
    def __init__(self, state, trusted, uid, run_id, round_name, source_root=Path('/run'),
                 proc_root=Path('/proc'), root_uid=0, session_check=None, setting_read=None, code_root=None):
        require(type(uid) is int and uid > 0 and RUN.fullmatch(run_id) and round_name in ROUNDS)
        self.uid, self.run, self.round = uid, run_id, round_name
        self.state, self.trusted = Path(state), Path(trusted)
        self.code = Path(code_root) if code_root is not None else Path(f'/run/arch-linux-qemu-desktop-code/{run_id}/{round_name}')
        self.source_root, self.proc_root, self.root_uid = Path(source_root), Path(proc_root), root_uid
        self.session_check = session_check or self.check_session
        self.setting_read = setting_read or self.read_setting
        self.user_fd = self.root_fd = self.code_fd = None
        try:
            self.user_fd = directory(self.state, uid)
            self.root_fd = directory(self.trusted, root_uid)
            for parent in (self.code.parent, self.code.parent.parent):
                fd = directory(parent, root_uid, 0o755); os.close(fd)
            self.code_fd = directory(self.code, root_uid, 0o755)
        except Exception:
            self.close()
            raise

    def close(self):
        for name in ('user_fd', 'root_fd', 'code_fd'):
            fd = getattr(self, name)
            if fd is not None:
                os.close(fd)
                setattr(self, name, None)

    def write_root(self, name, value, exclusive=False):
        flags = os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW
        fd = os.open(name, flags | (os.O_EXCL if exclusive else 0), 0o600, dir_fd=self.root_fd)
        try:
            info = os.fstat(fd)
            require(stat.S_ISREG(info.st_mode) and info.st_uid == self.root_uid and
                    stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1)
            os.ftruncate(fd, 0)
            os.write(fd, (json.dumps(value, separators=(',', ':')) + '\n').encode())
        finally:
            os.close(fd)

    def hashes(self, kind):
        names = SOURCES[kind]
        result = {}
        source_fd = os.open(self.source_root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            for name, field in zip(names[:2], ('probeSha256', names[2])):
                source = read_file(source_fd, 'arch-linux-qemu-' + name, self.root_uid, 0o500, 262144)
                copy = read_file(self.code_fd, name, self.root_uid, 0o555, 262144)
                require(source == copy)
                result[field] = hashlib.sha256(source).hexdigest()
        finally:
            os.close(source_fd)
        return result

    def context(self):
        value = parse(read_file(self.root_fd, 'context.json', self.root_uid, 0o600))
        require(set(value) == {'schema', 'runId', 'round', 'uid', 'shellPid', 'session', 'bootId'} and
                type(value['schema']) is int and value['schema'] == 1 and value['runId'] == self.run and value['round'] == self.round and
                type(value['uid']) is int and value['uid'] == self.uid and type(value['shellPid']) is int and value['shellPid'] > 1 and
                isinstance(value['session'], str) and re.fullmatch(r'[a-zA-Z0-9]+', value['session']) and
                isinstance(value['bootId'], str) and re.fullmatch(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', value['bootId']))
        self.session_check(value)
        return value

    def check_session(self, context):
        result = subprocess.run(['/usr/bin/loginctl', 'show-session', context['session'],
                                 '--no-pager', '-p', 'User', '-p', 'Service', '-p', 'Type',
                                 '-p', 'Class', '-p', 'State', '-p', 'Remote', '-p', 'Seat'],
                                check=True, capture_output=True, timeout=5)
        require(len(result.stdout) <= 2048)
        values = dict(line.split('=', 1) for line in result.stdout.decode().splitlines())
        require(values == {'User': str(self.uid), 'Service': 'gdm-password', 'Type': 'wayland',
                           'Class': 'user', 'State': 'active', 'Remote': 'no', 'Seat': 'seat0'})

    def process(self, kind, pid, context):
        require(type(pid) is int and 1 < pid < 2147483648)
        process = self.proc_root / str(pid)
        require(process.stat().st_uid == self.uid)
        def bounded(name, limit):
            with (process / name).open('rb') as source:
                data = source.read(limit + 1)
            require(len(data) <= limit)
            return data
        fields = bounded('stat', 4096).decode().rsplit(')', 1)[1].split()
        require(fields[0] != 'Z')
        executable = os.readlink(process / 'exe')
        argv = bounded('cmdline', 8192)
        require(len(argv) <= 8192 and argv.endswith(b'\0'))
        args = argv[:-1].decode().split('\0')
        if kind == 'shell':
            require(pid == context['shellPid'] and executable == str(Path('/usr/bin/gnome-shell').resolve()) and
                    args and Path(args[0]).name == 'gnome-shell')
            env = bounded('environ', 131072)
            require(len(env) <= 131072)
            session_ids = [item for item in env.split(b'\0') if item.startswith(b'XDG_SESSION_ID=')]
            require(not session_ids or session_ids == [('XDG_SESSION_ID=' + context['session']).encode()])
        else:
            require(executable == str(Path('/usr/bin/gjs').resolve()) and
                    args == ['/usr/bin/gjs', '-m', str(self.code / 'desktop-service-runner.js'),
                             str(self.state), self.run, self.round])
        boot_id = (self.proc_root / 'sys/kernel/random/boot_id').read_text().strip()
        require(boot_id == context['bootId'])
        return {'pid': pid, 'starttime': int(fields[19]), 'executable': executable, 'argv': args, 'bootId': boot_id}

    def read_setting(self, path):
        require(path in SETTING_PATHS)
        account = pwd.getpwuid(self.uid)
        result = subprocess.run(['/usr/bin/runuser', '-u', account.pw_name, '--',
            '/usr/bin/env', '-i', 'HOME=' + account.pw_dir,
            f'XDG_RUNTIME_DIR=/run/user/{self.uid}',
            f'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{self.uid}/bus',
            'LANG=C', 'LC_ALL=C', '/usr/bin/dconf', 'read', path],
            check=True, capture_output=True, timeout=5)
        require(len(result.stdout) <= 16384 and not result.stderr)
        return result.stdout.decode().rstrip('\n')

    def restored_state(self):
        values = settings_snapshot(self.trusted, self.root_uid)
        require(all(self.setting_read(row['path']) == row['value'] for row in values))
        original = parse(read_file(self.root_fd, 'original-state.json', self.root_uid, 0o600))
        require(isinstance(original, dict) and set(original) == {'blur', 'panel', 'panelInOverview', 'theme'} and
                all(type(original[key]) is bool for key in ('blur', 'panel', 'panelInOverview')) and
                original['theme'] in (None, THEME))
        return original

    def metadata(self, kind, hashes, context):
        name = 'desktop-' + kind + '-metadata.json'
        raw = read_file(self.user_fd, name, self.uid, 0o600)
        value = parse(raw)
        fields = {'schema', 'runId', 'round', 'uid', *hashes}
        fields |= {'shellPid', 'monitorCount', 'themePath'} if kind == 'shell' else {'expectedFlags'}
        require(set(value) == fields and type(value['schema']) is int and value['schema'] == 1 and value['runId'] == self.run and
                value['round'] == self.round and type(value['uid']) is int and value['uid'] == self.uid and
                all(value[key] == digest for key, digest in hashes.items()))
        if kind == 'shell':
            require(value['shellPid'] == context['shellPid'] and type(value['monitorCount']) is int and
                    1 <= value['monitorCount'] <= 16 and value['themePath'] in (None, THEME))
        else:
            require(type(value['expectedFlags']) is int and value['expectedFlags'] in (4, 8))
        pinned = read_file(self.root_fd, name, self.root_uid, 0o600)
        require(raw == pinned)
        return value

    def verify(self, kind, sequence, stage, expected='any'):
        require(kind in SOURCES and type(sequence) is int and 0 <= sequence <= 64 and
                re.fullmatch(r'[a-z-]+', stage) is not None)
        hashes = self.hashes(kind)
        context = self.context()
        metadata = self.metadata(kind, hashes, context)
        filename = f'desktop-{kind}-ready.json' if sequence == 0 else f'desktop-{kind}-{sequence}-{stage}.json'
        raw = read_file(self.user_fd, filename, self.uid, 0o600)
        value = parse(raw)
        require(set(value) == {'schema', 'runId', 'round', 'sequence', 'stage', 'pid', 'uid',
                               'status', 'code', 'facts', *hashes} and
                type(value['schema']) is int and value['schema'] == 1 and value['runId'] == self.run and
                value['round'] == self.round and type(value['sequence']) is int and value['sequence'] == sequence and
                value['stage'] == stage and type(value['uid']) is int and value['uid'] == self.uid and
                value['status'] == 'ready' and all(value[key] == digest for key, digest in hashes.items()))
        self.facts(kind, stage, value['code'], value['facts'], metadata, expected)
        actual = self.process(kind, value['pid'], context)
        actual.update(hashes)
        identity_name = kind + '-identity.json'
        if sequence == 0:
            require(stage == 'ready')
            self.write_root(identity_name, actual, exclusive=True)
            self.write_root(kind + '-sequence.json', {'sequence': 0, 'digest': hashlib.sha256(raw).hexdigest()}, exclusive=True)
        else:
            require(parse(read_file(self.root_fd, identity_name, self.root_uid, 0o600)) == actual)
            previous = parse(read_file(self.root_fd, kind + '-sequence.json', self.root_uid, 0o600))
            digest = hashlib.sha256(raw).hexdigest()
            require(sequence == previous['sequence'] + 1 or
                    (sequence == previous['sequence'] and digest == previous['digest']))
            command = parse(read_file(self.root_fd, kind + '-command.json', self.root_uid, 0o600))
            require(command == {'schema': 1, 'runId': self.run, 'round': self.round,
                                'sequence': sequence, 'stage': stage})
            require(read_file(self.user_fd, 'desktop-' + kind + '-command.json', self.uid, 0o600) ==
                    read_file(self.root_fd, kind + '-command.json', self.root_uid, 0o600))
            self.write_root(kind + '-sequence.json', {'sequence': sequence, 'digest': digest})
        require(self.process(kind, value['pid'], context) == {k: actual[k] for k in PROCESS_FIELDS})
        self.write_root(filename, value)
        return value

    @staticmethod
    def facts(kind, stage, code, facts, metadata, expected):
        require(isinstance(facts, dict))
        if stage == 'ready':
            require(code == 'observer-started')
            exact_facts(facts, {'unsafeMode': False} if kind == 'shell' else {})
        elif stage == 'stop':
            require(code == 'observer-stopped')
            exact_facts(facts, {} if kind == 'shell' else {'closed': True})
        elif kind == 'service':
            if stage == 'indicator-register':
                require(code == 'indicator-registered')
                exact_facts(facts, {'registered': True, 'signal': True})
            elif stage == 'indicator-remove':
                require(code == 'indicator-removed')
                exact_facts(facts, {'absent': True, 'signal': True})
            else:
                require(stage == 'caffeine-observe' and code == 'inhibitor-observed' and
                        set(facts) == {'count', 'matchingCount', 'found'} and
                        type(facts['count']) is int and type(facts['matchingCount']) is int and
                        0 <= facts['matchingCount'] <= facts['count'] <= 128 and type(facts['found']) is bool and
                        facts['found'] == (facts['matchingCount'] > 0) and expected in ('on', 'off') and
                        facts['found'] == (expected == 'on'))
        elif stage == 'blur-on':
            n = metadata['monitorCount']
            require(code == 'blur-applied')
            exact_facts(facts, {'monitorCountMatches': True, 'enabled': True,
                    'attached': True, 'overviewVisible': True, 'widgetCount': n, 'managerCount': n, 'activeWidgets': n})
        elif stage == 'blur-off':
            require(code == 'blur-removed')
            exact_facts(facts, {'monitorCountMatches': True, 'disabled': True,
                    'detached': True, 'widgetCount': 0, 'managerCount': 0})
        elif stage in ('panel-shown', 'panel-hidden', 'panel-overview-only'):
            shown, hidden = stage == 'panel-shown', stage == 'panel-hidden'
            require(code == 'panel-applied')
            require(all(type(facts.get(key)) is bool for key in ('visible', 'mapped', 'overviewVisible')))
            exact_facts(facts, {'chromeParent': shown, 'overviewParent': not shown,
                    'zeroOffset': not hidden, 'hiddenTopOffset': hidden,
                    'visible': facts['visible'], 'mapped': facts['mapped'], 'overviewVisible': facts['overviewVisible']})
            if not hidden:
                require(facts['visible'] and facts['mapped'])
            if stage == 'panel-overview-only':
                require(facts['overviewVisible'])
        else:
            require(stage in ('theme-marble', 'theme-stock') and code == 'theme-applied')
            require(stage != 'theme-marble' or metadata['themePath'] == THEME)
            exact_facts(facts, {'selectedMatches': True, 'loadedMatches': True})

    def terminate_service(self):
        context = self.context()
        identity = parse(read_file(self.root_fd, 'service-identity.json', self.root_uid, 0o600))
        hashes = self.hashes('service')
        require(all(identity[key] == value for key, value in hashes.items()))
        expected = {k: identity[k] for k in PROCESS_FIELDS}
        require(self.process('service', identity['pid'], context) == expected)
        # pidfd pins the exact owned process through the signal boundary.
        fd = os.pidfd_open(identity['pid'])
        try:
            require(self.process('service', identity['pid'], context) == expected)
            signal.pidfd_send_signal(fd, signal.SIGTERM)
        finally:
            os.close(fd)

    def completion(self):
        """Check root-custodied transitions; emit no claim from an isolated positive."""
        context = self.context()
        original = self.restored_state()
        all_values = {}
        hashes = {}
        for kind in SOURCES:
            hashes[kind] = self.hashes(kind)
            metadata = self.metadata(kind, hashes[kind], context)
            identity = parse(read_file(self.root_fd, kind + '-identity.json', self.root_uid, 0o600))
            require(all(identity[key] == value for key, value in hashes[kind].items()))
            if kind == 'shell':
                require(self.process(kind, identity['pid'], context) ==
                        {k: identity[k] for k in PROCESS_FIELDS})
            values = []
            for name in os.listdir(self.root_fd):
                match = re.fullmatch(r'desktop-' + kind + r'-([1-9][0-9]*)-([a-z-]+)\.json', name)
                if match:
                    require(len(values) < 64)
                    value = parse(read_file(self.root_fd, name, self.root_uid, 0o600))
                    require(type(value['sequence']) is int and value['sequence'] == int(match[1]) and
                            value['stage'] == match[2] and value['runId'] == self.run and value['round'] == self.round and
                            value['uid'] == self.uid and value['pid'] == identity['pid'] and value['status'] == 'ready' and
                            all(value[key] == digest for key, digest in hashes[kind].items()))
                    expected = 'on' if value['facts'].get('found') is True else 'off'
                    self.facts(kind, value['stage'], value['code'], value['facts'], metadata, expected)
                    values.append(value)
            values.sort(key=lambda value: value['sequence'])
            require([v['sequence'] for v in values] == list(range(1, len(values) + 1)) and values[-1]['stage'] == 'stop')
            all_values[kind] = values
        service = all_values['service']
        require([v['stage'] for v in service[:5]] == ['indicator-register', 'indicator-remove',
                'caffeine-observe', 'caffeine-observe', 'caffeine-observe'] and
                [v['facts']['found'] for v in service[2:5]] == [False, True, False])
        shell_stages = [v['stage'] for v in all_values['shell']]
        required = ['blur-on', 'blur-off', 'panel-shown', 'panel-hidden', 'panel-overview-only']
        require(shell_stages[:5] == required and shell_stages[5] in
                ('panel-shown', 'panel-hidden', 'panel-overview-only'))
        panel_stage = ('panel-shown' if original['panel'] else
                       'panel-overview-only' if original['panelInOverview'] else 'panel-hidden')
        require(shell_stages[5] == panel_stage)
        require(shell_stages[-4:] == ['blur-on' if original['blur'] else 'blur-off', panel_stage,
                                     'theme-stock' if original['theme'] is None else 'theme-marble', 'stop'])
        features = [('appindicator', hashes['service']['serviceSha256'], 'registered=1 removed=1'),
                    ('caffeine', hashes['service']['serviceSha256'], 'baseline=0 keyboard_on=1 keyboard_off=0'),
                    ('blur', hashes['shell']['probeSha256'], 'native_blur=1 removed=1'),
                    ('just-perfection', hashes['shell']['probeSha256'], 'shown=1 hidden=1 overview_only=1 restored=1')]
        if self.metadata('shell', hashes['shell'], context)['themePath'] is not None:
            require('theme-stock' in shell_stages and 'theme-marble' in shell_stages and
                    shell_stages.index('theme-stock') < shell_stages.index('theme-marble'))
            features.append(('user-theme', hashes['shell']['probeSha256'], 'stock_control=1 marble_applied=1'))
        for feature, digest, facts in features:
            print(f'EXTENSION_FUNCTIONAL_PASS phase={self.round} feature={feature} run_id={self.run} '
                  f'session={context["session"]} probe_sha256={digest} {facts}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('verify', 'terminate-service', 'complete', 'cleanup'))
    parser.add_argument('uid', type=int)
    parser.add_argument('run_id')
    parser.add_argument('round')
    parser.add_argument('kind', choices=('shell', 'service'))
    parser.add_argument('sequence', type=int)
    parser.add_argument('stage')
    parser.add_argument('expected', nargs='?', default='any')
    args = parser.parse_args()
    custody = None
    try:
        require(os.geteuid() == 0 and RUN.fullmatch(args.run_id) and args.round in ROUNDS)
        state = Path(f'/run/user/{args.uid}/arch-linux-qemu-extension-{args.run_id}-{args.round}')
        trusted = Path(f'/run/arch-linux-qemu-desktop-functional/{args.run_id}/{args.round}')
        if args.action == 'cleanup':
            code = Path(f'/run/arch-linux-qemu-desktop-code/{args.run_id}/{args.round}')
            cleanup_files(state, args.uid, code)
            return 0
        custody = Custody(state, trusted, args.uid, args.run_id, args.round)
        if args.action == 'verify':
            custody.verify(args.kind, args.sequence, args.stage, args.expected)
        elif args.action == 'terminate-service':
            custody.terminate_service()
        else:
            custody.completion()
    except (ValueError, OSError, KeyError, TypeError, IndexError, subprocess.SubprocessError):
        print('DESKTOP_NATIVE_RECEIPT_FAIL reason=invalid-custody')
        return 1
    finally:
        if custody is not None:
            custody.close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
