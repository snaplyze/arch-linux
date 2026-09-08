#!/usr/bin/env python3
"""Offline regressions: retain moved 32-bit libraries, not just remove pacman targets."""
from pathlib import Path
import os
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'arch-linux-installer.sh').read_text()
PACKAGES = ['lib32-libvpx', 'lib32-libwebp', 'lib32-sdl2-compat', 'lib32-sdl12-compat']


def function(name):
    result = re.search(r'^' + re.escape(name) + r'\(\) \{\n.*?^\}', SOURCE, re.M | re.S)
    if result is None:
        raise AssertionError('Missing production function: ' + name)
    return result.group(0)


def bash(program, *args):
    return subprocess.run(['bash', '--noprofile', '--norc', '-c',
                           'set -euo pipefail\n' + program, 'multilib-check', *args],
                          text=True, capture_output=True, timeout=20,
                          env={'PATH': os.environ['PATH'], 'LANG': 'C', 'LC_ALL': 'C'})


class RetainedMultilibChecks(unittest.TestCase):
    def test_all_four_libraries_are_installed_in_dependency_order(self):
        result = bash(function('chroot_install_desktop_multilib') + '''
ARCH_LINUX_DESKTOP_EXTRAS_ENABLED=true
ARCH_LINUX_MULTILIB_ENABLED=true
chroot_pacman_install() { :; }
chroot_aur_install() { printf '%s\\n' "$1"; }
chroot_install_desktop_multilib
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), PACKAGES)
        desktop = function('exec_install_desktop')
        self.assertLess(desktop.index('chroot_pacman_install "${packages[@]}"'),
                        desktop.index('chroot_install_desktop_multilib'))

    def test_disabled_features_do_not_install_aur_libraries(self):
        for extras, multilib in [('false', 'true'), ('true', 'false'), ('false', 'false')]:
            result = bash(function('chroot_install_desktop_multilib') + '''
ARCH_LINUX_DESKTOP_EXTRAS_ENABLED="$1"
ARCH_LINUX_MULTILIB_ENABLED="$2"
chroot_pacman_install() { exit 99; }
chroot_aur_install() { exit 99; }
chroot_install_desktop_multilib
''', extras, multilib)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, '')

    def test_failed_aur_build_is_not_skipped(self):
        result = bash(function('chroot_install_desktop_multilib') + '''
ARCH_LINUX_DESKTOP_EXTRAS_ENABLED=true
ARCH_LINUX_MULTILIB_ENABLED=true
chroot_pacman_install() { :; }
chroot_aur_install() { printf '%s\\n' "$1"; [ "$1" != lib32-libwebp ]; }
chroot_install_desktop_multilib
printf 'FALSE_SUCCESS\\n'
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines(), PACKAGES[:2])

    def test_sdl12_virtual_dependency_is_checked_not_sent_to_official_repository(self):
        code = function('aur_reviewed_dependencies') + '\n' + function('chroot_aur_install_dependencies')
        for provider in ('present', 'missing'):
            result = bash(code + '''
log_fail() { printf '%s\\n' "$*" >&2; }
arch-chroot() { printf 'query:%s\\n' "$*" >&2; [ "$1" = /mnt ] && [ "$3" = -T ] && [ "$4" = -- ] && [ "$5" = lib32-sdl2 ] && [ "$mode" = present ]; }
chroot_pacman_install() { printf '%s\\n' "$@"; }
mode="$1"
chroot_aur_install_dependencies lib32-sdl12-compat
''', provider)
            self.assertIn('pacman -T -- lib32-sdl2', result.stderr)
            if provider == 'present':
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), ['cmake', 'lib32-glu', 'sdl12-compat'])
            else:
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')

    def test_pins_and_dependency_metadata_are_bound_to_fixtures(self):
        import hashlib
        for package in PACKAGES:
            result = bash(function('aur_review_metadata') + '\naur_review_metadata "$1"\n', package)
            self.assertEqual(result.returncode, 0, result.stderr)
            fields = result.stdout.split()
            self.assertEqual(len(fields), 4)
            self.assertRegex(fields[0], r'^[a-f0-9]{40}$')
            for field in fields[1:]:
                self.assertRegex(field, r'^[a-f0-9]{64}$')
            fixture = ROOT / 'tests/fixtures/aur' / (package + '.SRCINFO')
            self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(), fields[2])
            code = '\n'.join(function(name) for name in ('aur_dependency_is_safe', 'aur_srcinfo_dependencies', 'aur_reviewed_dependencies'))
            result = bash(code + '\naur_srcinfo_dependencies "$1" <"$2"\nprintf -- "---\\n"\naur_reviewed_dependencies "$1"\n', package, str(fixture))
            self.assertEqual(result.returncode, 0, result.stderr)
            parsed, reviewed = result.stdout.split('---\n')
            self.assertEqual(parsed, reviewed)

    def test_payload_paths_remain_package_specific(self):
        code = function('aur_extension_uuid') + '\n' + function('aur_multilib_path_is_allowed') + '\n' + function('aur_package_path_is_allowed')
        examples = {
            'lib32-libvpx': ['usr/lib32/libvpx.so.12.0.0', 'usr/lib32/pkgconfig/vpx.pc'],
            'lib32-libwebp': ['usr/lib32/libwebp.so.7.2.0', 'usr/lib32/libsharpyuv.so.0.1.1'],
            'lib32-sdl2-compat': ['usr/lib32/libSDL2-2.0.so.0.3200.72', 'usr/lib32/pkgconfig/sdl2-compat.pc', 'usr/lib32/libSDL2_test.a', 'usr/lib32/libSDL2main.a', 'usr/lib32/cmake/SDL2/SDL2Config.cmake', 'usr/lib32/cmake/SDL2/SDL2ConfigVersion.cmake', 'usr/lib32/cmake/SDL2/SDL2Targets-none.cmake', 'usr/lib32/cmake/SDL2/SDL2Targets.cmake', 'usr/lib32/cmake/SDL2/SDL2_testTargets-none.cmake', 'usr/lib32/cmake/SDL2/SDL2_testTargets.cmake', 'usr/lib32/cmake/SDL2/SDL2mainTargets-none.cmake', 'usr/lib32/cmake/SDL2/SDL2mainTargets.cmake', 'usr/lib32/cmake/SDL2/sdl2-config-version.cmake', 'usr/lib32/cmake/SDL2/sdl2-config.cmake'],
            'lib32-sdl12-compat': ['usr/lib32/libSDL-1.2.so.0.68.0', 'usr/lib32/libSDLmain.a', 'usr/lib32/pkgconfig/sdl12_compat.pc'],
        }
        for package, allowed in examples.items():
            for path in allowed:
                result = bash(code + '\naur_package_path_is_allowed "$1" "$2" -\n', package, path)
                self.assertEqual(result.returncode, 0, (package, path, result.stderr))
            for path in ['etc/ld.so.preload', 'usr/lib/libvpx.so', 'usr/lib32/libevil.so',
                         'usr/share/libalpm/hooks/install.hook', 'usr/bin/owned', '.INSTALL',
                         'usr/lib32/libSDL2evil.a', 'usr/lib32/cmake/SDL2/foreign.cmake',
                         'usr/lib32/../lib/owned.so']:
                result = bash(code + '\naur_package_path_is_allowed "$1" "$2" -\n', package, path)
                self.assertNotEqual(result.returncode, 0, (package, path))

    def test_library_symlinks_cannot_escape_or_cross_package_names(self):
        code = function('aur_multilib_path_is_allowed') + '\n' + function('aur_package_symlink_is_safe')
        valid = [('lib32-libvpx', 'usr/lib32/libvpx.so', 'libvpx.so.12'),
                 ('lib32-libwebp', 'usr/lib32/libwebp.so', 'libwebp.so.7'),
                 ('lib32-sdl2-compat', 'usr/lib32/libSDL2.so', 'libSDL2-2.0.so.0'),
                 ('lib32-sdl12-compat', 'usr/lib32/libSDL.so', 'libSDL-1.2.so.0')]
        for package, path, target in valid:
            result = bash(code + '\naur_package_symlink_is_safe "$1" "$2" "$3"\n', package, path, target)
            self.assertEqual(result.returncode, 0, result.stderr)
            for bad in ['/etc/shadow', '../../etc/shadow', '../lib/libc.so.6', 'libevil.so', 'subdir/libvpx.so']:
                result = bash(code + '\naur_package_symlink_is_safe "$1" "$2" "$3"\n', package, path, bad)
                self.assertNotEqual(result.returncode, 0, (package, path, bad))


if __name__ == '__main__':
    unittest.main(verbosity=2)
