#!/usr/bin/env python3
"""Exercise real desktop target construction and package transaction preflight.

Default mode is offline and never installs packages. --live checks synchronized
Arch databases and resolves desktop transactions without downloading/installing.
Run --live only in a disposable, fully updated Arch validation environment.
"""
from pathlib import Path
import itertools
import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'arch-linux-installer.sh').read_text()
AUR_MOVED = {'lib32-libvpx', 'lib32-libwebp', 'lib32-sdl2-compat', 'lib32-sdl12-compat'}


def function(name):
    match = re.search(r'^' + re.escape(name) + r'\(\) \{\n.*?^\}', SOURCE, re.M | re.S)
    if match is None:
        raise AssertionError('Missing production function: ' + name)
    return match.group(0)


def run_bash(program, *args):
    return subprocess.run(['bash', '--noprofile', '--norc', '-c',
                           'set -euo pipefail\n' + program, 'package-check', *args],
                          text=True, capture_output=True, timeout=20,
                          env={'PATH': os.environ['PATH'], 'LANG': 'C', 'LC_ALL': 'C'})


def desktop_targets(extras='true', multilib='true', profile='stock',
                    filesystem='btrfs', kernel='linux-zen'):
    # Evaluate only the reviewed, side-effect-free array construction, not an
    # installation executor. The resulting argv is what production passes to pacman.
    body = function('exec_install_desktop')
    start = body.index('            local packages=()')
    end = body.index('            # Installing packages together')
    program = '''
ARCH_LINUX_DESKTOP_EXTRAS_ENABLED="$1"
ARCH_LINUX_MULTILIB_ENABLED="$2"
ARCH_LINUX_GNOME_THEME_PROFILE="$3"
ARCH_LINUX_FILESYSTEM="$4"
ARCH_LINUX_KERNEL="$5"
ARCH_LINUX_BTRFS_ASSISTANT_ENABLED=true
collect() {
''' + body[start:end] + '''
printf '%s\\n' "${packages[@]}"
}
collect
'''
    result = run_bash(program, extras, multilib, profile, filesystem, kernel)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout.splitlines()


def matrix():
    return itertools.product(('false', 'true'), ('false', 'true'),
                             ('stock', 'marble'), ('ext4', 'btrfs'),
                             ('linux', 'linux-lts', 'linux-zen'))


def helper_run(mode):
    with tempfile.TemporaryDirectory() as tmp:
        result = run_bash(function('chroot_pacman_install') + r'''
log_fail() { printf 'FAIL %s\n' "$*" >&2; }
log_warn() { :; }
sleep() { printf 'sleep\n' >>"$calls"; }
calls="$1/calls"
mode="$2"
attempt=0
arch-chroot() {
    [ "$1" = /mnt ] && [ "$2" = pacman ] || return 98
    shift 2
    printf '%s\n' "$*" >>"$calls"
    case "$1" in
        -Sp)
            if [ "$mode" = missing ]; then
                printf 'error: target not found: unavailable-package\n' >&2
                return 1
            fi
            return 0 ;;
        -S)
            attempt=$((attempt + 1))
            case "$mode" in
                missing|permanent) return 1 ;;
                transient) [ "$attempt" -gt 1 ] ;;
                success) return 0 ;;
                *) return 98 ;;
            esac ;;
        *) return 98 ;;
    esac
}
chroot_pacman_install gnome 'glibc>=2.39'
''', tmp, mode)
        return result, Path(tmp, 'calls').read_text().splitlines()


class DesktopPackageChecks(unittest.TestCase):
    def test_aur_targets_are_not_sent_to_official_pacman(self):
        for args in matrix():
            with self.subTest(configuration=args):
                self.assertFalse(AUR_MOVED.intersection(desktop_targets(*args)))

    def test_native_codecs_and_sdl_are_preserved(self):
        self.assertTrue({'libvpx', 'libwebp', 'sdl3_image', 'sdl2-compat',
                         'sdl12-compat', 'gamemode', 'ffmpeg', 'gst-plugins-good',
                         'gst-plugins-bad', 'gst-plugins-ugly'} <= set(desktop_targets()))

    def test_remaining_multilib_audio_and_gamemode_are_preserved(self):
        self.assertTrue({'lib32-pipewire', 'lib32-pipewire-jack',
                         'lib32-gamemode'} <= set(desktop_targets()))

    def test_multilib_off_requests_no_lib32_targets(self):
        self.assertFalse(any(p.startswith('lib32-') for p in desktop_targets(multilib='false')))

    def test_extras_off_keeps_desktop_and_required_services(self):
        packages = set(desktop_targets(extras='false'))
        self.assertTrue({'gnome', 'ptyxis', 'pipewire', 'pipewire-pulse',
                         'wireplumber', 'bluez', 'avahi', 'extension-manager'} <= packages)
        self.assertNotIn('gamemode', packages)
        self.assertNotIn('ffmpeg', packages)

    def test_gnome_calendar_server_dependency_is_explicit(self):
        self.assertIn('evolution-data-server', desktop_targets())

    def test_profile_filesystem_and_kernel_selection_remain_effective(self):
        self.assertNotIn('gnome-shell-extensions', desktop_targets())
        self.assertIn('gnome-shell-extensions', desktop_targets(profile='marble'))
        self.assertNotIn('btrfs-assistant', desktop_targets(filesystem='ext4'))
        self.assertIn('btrfs-assistant', desktop_targets(filesystem='btrfs'))
        for kernel in ('linux', 'linux-lts', 'linux-zen'):
            self.assertIn(kernel + '-headers', desktop_targets(kernel=kernel))

    def test_missing_target_fails_before_install_without_retries(self):
        result, calls = helper_run('missing')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertTrue(calls[0].startswith('-Sp '))
        self.assertIn('target not found: unavailable-package', result.stderr)
        self.assertIn('Package selection cannot be resolved', result.stderr)

    def test_preflight_is_read_only_and_preserves_requested_arguments(self):
        result, calls = helper_run('success')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0], '-Sp --noconfirm --print-format %n -- gnome glibc>=2.39')
        self.assertEqual(calls[1], '-S --noconfirm --needed --disable-download-timeout -- gnome glibc>=2.39')
        self.assertEqual(len(calls), 2)

    def test_transient_download_failure_still_retries(self):
        result, calls = helper_run('transient')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(x.startswith('-Sp ') for x in calls), 1)
        self.assertEqual(sum(x.startswith('-S ') for x in calls), 2)
        self.assertEqual(calls.count('sleep'), 1)

    def test_permanent_install_failure_is_not_reported_as_success(self):
        result, calls = helper_run('permanent')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sum(x.startswith('-Sp ') for x in calls), 1)
        self.assertEqual(sum(x.startswith('-S ') for x in calls), 5)


def live_check():
    # This is explicitly not a VM installation or runtime acceptance result.
    unique = {tuple(dict.fromkeys(desktop_targets(*args))) for args in matrix()}
    for targets in sorted(unique):
        result = subprocess.run(['pacman', '-Sp', '--noconfirm', '--print-format', '%n', '--', *targets],
                                text=True, capture_output=True, timeout=120)
        if result.returncode:
            raise SystemExit(result.stderr)
    print(f'LIVE_PACKAGE_RESOLUTION_PASS desktop_transactions={len(unique)}; INSTALLATION=NOT_RUN')


if __name__ == '__main__':
    if sys.argv[1:] == ['--live']:
        live_check()
    else:
        unittest.main(verbosity=2)
