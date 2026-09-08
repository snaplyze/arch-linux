#!/usr/bin/env python3
"""Regression checks for executor permissions and primary keyboard selection.

Only the named production function bodies are evaluated. The cgroup probes and TUI
are isolated adapters; file creation, umask inheritance and permission checks use
real OS operations. No installation, network access or disk mutation is performed.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "arch-linux-installer.sh").read_text()


def function(name):
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}", SOURCE, re.M | re.S)
    if match is None:
        raise AssertionError("Missing production function: " + name)
    return match.group(0)


def bash(program, *args, expected_status=0):
    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", "set -euo pipefail\n" + program,
         "boundary-check", *map(str, args)],
        text=True, capture_output=True, timeout=20,
    )
    if result.returncode != expected_status:
        raise AssertionError(f"bash exited {result.returncode}:\n{result.stdout}{result.stderr}")
    return result.stdout.strip()


# Replace process-membership probes only. The actual entry function still checks
# their results, writes its real acknowledgement and sets its execution context.
CGROUP = r'''
PROCESS_CGROUP_DIR="$1/cgroup"
PROCESS_CGROUP_RELATIVE=/fixture
PROCESS_CGROUP_ACK_TMP_FILE="$1/ack"
mkdir -p "$PROCESS_CGROUP_DIR"
ps() { local last; for last; do :; done; printf '%s\n' "$last"; }
awk() { printf '%s\n' /fixture; }
'''
KEYBOARD = r'''
ARCH_LINUX_DESKTOP_ENABLED=true
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT=''
ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT=''
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND=ru
ARCH_LINUX_VCONSOLE_KEYMAP=us
declare -A variant_map=([de]='nodeadkeys')
desktop_keymap_layouts() { echo 'us ru gb de'; }
properties_generate() { printf '%s\n' saved; }
gum_property() { :; }
gum_filter() { echo 'UNEXPECTED PRIMARY PROMPT' >&2; return 99; }
trap_gum_exit_confirm() { exit 99; }
'''


class InstallerBoundaryChecks(unittest.TestCase):
    def test_bootstrap_verified_handoff_resets_only_execution_mask(self):
        bootstrap = (ROOT / 'install.sh').read_text()
        launch = re.search(r'^bootstrap_launch_installer\(\) \{\n.*?^\}',
                           bootstrap, re.M | re.S).group(0)
        handoff = re.search(r'            cd -- "\$\{dir\}"\n.*?'
                            r'            exec /usr/bin/bash --noprofile --norc '
                            r'./arch-linux-installer.sh', launch, re.S).group(0)
        with tempfile.TemporaryDirectory() as tmp:
            result = bash('umask 077\ndir="$1"\nexec() { umask; }\n' + handoff, tmp)
            self.assertEqual(result, '0022')

    def test_executor_normalizes_restrictive_and_permissive_masks(self):
        for mask in ('077', '027', '000', '022'):
            with self.subTest(mask=mask), tempfile.TemporaryDirectory() as tmp:
                output = bash(function('process_enter_cgroup') + CGROUP + r'''
umask "$2"
process_enter_cgroup
umask
''', tmp, mask)
                self.assertEqual(output, '0022')

    def test_public_system_paths_do_not_inherit_bootstrap_private_mask(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = bash(function('process_enter_cgroup') + CGROUP + r'''
umask 077
process_enter_cgroup
mkdir -p "$1/target/etc" "$1/target/var/lib/portables"
printf 'nameserver 127.0.0.53\n' >"$1/target/etc/resolv.conf"
stat -c '%a' "$1/target" "$1/target/etc" "$1/target/var" \
    "$1/target/var/lib" "$1/target/etc/resolv.conf"
''', tmp)
            self.assertEqual(output.splitlines(), ['755', '755', '755', '755', '644'])

    def test_parent_runtime_state_and_explicit_private_modes_stay_private(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = bash(function('process_enter_cgroup') + CGROUP + r'''
umask 077
(
    process_enter_cgroup
    private="$(mktemp -d -- "$1/private.XXXXXXXXXX")"
    printf 'fixture\n' >"$private/state"
    chmod 0600 "$private/state"
    stat -c '%a' "$private" "$private/state"
)
printf 'fixture\n' >"$1/parent-state"
umask
stat -c '%a' "$1/parent-state"
''', tmp)
            self.assertEqual(output.splitlines(), ['700', '600', '0077', '600'])

    def test_failed_containment_still_rejects_before_acknowledgement(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = bash(function('process_enter_cgroup') + CGROUP + r'''
ps() { printf '%s\n' 0; }
status=0
( process_enter_cgroup ) || status=$?
[ ! -e "$PROCESS_CGROUP_ACK_TMP_FILE" ]
printf '%s\n' "$status"
''', tmp)
            self.assertEqual(output, '125')

    def test_known_console_layouts_need_no_second_primary_prompt(self):
        for console, desktop in [('us', 'us'), ('ru', 'ru'), ('uk', 'gb')]:
            with self.subTest(console=console):
                output = bash(function('select_enable_desktop_keyboard') + KEYBOARD + r'''
ARCH_LINUX_VCONSOLE_KEYMAP="$1"
select_enable_desktop_keyboard
printf '%s|%s|%s\n' "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" \
    "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND"
''', console)
                self.assertEqual(output, f'saved\n{desktop}||ru')

    def test_explicit_desktop_layout_and_variant_are_preserved(self):
        output = bash(function('select_enable_desktop_keyboard') + KEYBOARD + r'''
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT=de
ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT=nodeadkeys
select_enable_desktop_keyboard
printf '%s|%s|%s\n' "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" \
    "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND"
''')
        self.assertEqual(output, 'de|nodeadkeys|ru')

    def test_ambiguous_console_keymap_keeps_explicit_desktop_choice(self):
        output = bash(function('select_enable_desktop_keyboard') + KEYBOARD + r'''
ARCH_LINUX_VCONSOLE_KEYMAP=dvorak
gum_filter() {
    case "$*" in
        *'Choose Desktop Keyboard Layout'*) printf '%s\n' de ;;
        *'Choose Desktop Keyboard Variant'*) printf '%s\n' nodeadkeys ;;
        *) return 99 ;;
    esac
}
select_enable_desktop_keyboard
printf '%s|%s|%s\n' "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" \
    "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND"
''')
        self.assertEqual(output, 'saved\nde|nodeadkeys|ru')

    def test_tty_install_does_not_ask_for_desktop_keyboard(self):
        output = bash(function('select_enable_desktop_keyboard') + KEYBOARD + r'''
ARCH_LINUX_DESKTOP_ENABLED=false
select_enable_desktop_keyboard
printf '%s|%s\n' "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND"
''')
        self.assertEqual(output, '|ru')

    def test_multilib_refresh_includes_full_upgrade_and_propagates_failure(self):
        for result_code in (0, 42):
            with self.subTest(result_code=result_code), tempfile.TemporaryDirectory() as tmp:
                output = bash(function('exec_enable_multilib') + r'''
ARCH_LINUX_MULTILIB_ENABLED=true
DEBUG=false
PROCESS_LOG_TMP_FILE="$1/process.log"
process_init() { :; }
process_enter_cgroup() { :; }
process_return() { exit "$1"; }
process_capture() { wait "$1"; }
sed() { :; }
# The actual package process is not run on the host. Record the production argv
# and return the requested process status from the executor's child.
arch-chroot() { printf '%s\n' "$*" >"$calls"; return "$expected_status"; }
calls="$1/calls"
expected_status="$2"
exec_enable_multilib
''', tmp, result_code, expected_status=result_code)
                self.assertEqual(output, '')
                self.assertEqual(Path(tmp, 'calls').read_text().strip(),
                                 '/mnt pacman -Syu --noconfirm')


if __name__ == '__main__':
    unittest.main(verbosity=2)
