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
    def test_dual_boot_probe_refusal_precedes_every_root_mutation(self):
        for failure in ('collision', 'inspection-error', 'custom-kernel',
                        'post-probe-idle', 'post-probe-identity', 'post-probe-handle'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as tmp:
                bash(function('exec_prepare_disk') + r'''
DEBUG=false
ARCH_LINUX_DISK="$1/disk"
ARCH_LINUX_BOOT_PARTITION="$1/boot"
ARCH_LINUX_ROOT_PARTITION="$1/root"
touch "$ARCH_LINUX_DISK" "$ARCH_LINUX_BOOT_PARTITION" "$ARCH_LINUX_ROOT_PARTITION"
ARCH_LINUX_DISK_IDENTITY=accepted
ARCH_LINUX_BOOT_PARTITION_IDENTITY=boot
ARCH_LINUX_ROOT_PARTITION_IDENTITY=root
ARCH_LINUX_DUAL_BOOT_ENABLED=true
ARCH_LINUX_FILESYSTEM=ext4
ARCH_LINUX_ENCRYPTION_ENABLED=true
ARCH_LINUX_PASSWORD=fixture
ARCH_LINUX_KERNEL=linux
[ "$2" != custom-kernel ] || ARCH_LINUX_KERNEL=custom
ARCH_LINUX_MICROCODE=none
ARCH_LINUX_BOOTLOADER=systemd
TARGET_MOUNT_MARKER="$1/marker"
CRYPTROOT_MARKER="$1/crypt"
PROCESS_LOG_TMP_FILE="$1/log"
process_init() { :; }
process_enter_cgroup() { :; }
process_capture() { wait "$1"; }
log_fail() { :; }
log_info() { :; }
failure="$2"
identity_checks=0
assert_accepted_destructive_target() {
    identity_checks=$((identity_checks + 1))
    [ "$failure" != post-probe-identity ] || [ "$identity_checks" -le 2 ]
}
idle_checks=0
target_storage_is_idle() {
    idle_checks=$((idle_checks + 1))
    [ "$failure" != post-probe-idle ] || [ "$idle_checks" -le 1 ]
}
block_canonical() { printf '%s' "$1"; }
block_disk_handle_is_bound() { :; }
handle_checks=0
block_partition_handle_is_bound() {
    handle_checks=$((handle_checks + 1))
    [ "$failure" != post-probe-handle ] || [ "$handle_checks" -le 2 ]
}
# Only the read-only namespace adapter is replaced. The actual executor must
# consume refusal before invoking any cryptsetup/mkfs or storage-intent writer.
dual_boot_inspect_esp_handle() { [[ "$failure" = post-probe-* ]]; }
mark_storage_intent() { echo intent >"$1"; }
cryptsetup() { echo mutation >"$calls"; exit 77; }
calls="$1/calls"
status=0
exec_prepare_disk || status=$?
[ "$status" -ne 0 ] && [ ! -e "$calls" ] && [ ! -e "$CRYPTROOT_MARKER" ]
''', tmp, failure)

    def test_exit_trap_requires_quiescence_and_retains_only_operational_state(self):
        for scenario, expected_status, retained in (
                ('reap-failure', 1, True), ('reap-before-target', 1, True),
                ('recovery-allocation-failure', 1, False),
                ('busy-unmount', 1, True),
                ('scope-remove-failure', 1, True),
                ('mapper-failure', 1, True), ('cleanup-success', 1, False),
                ('success', 0, False), ('cancel', 130, False)):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as tmp:
                # Evaluate the real EXIT handler. Adapters represent process and
                # storage outcomes; runtime files, deletion and permissions are real.
                names = ['trap_exit', 'runtime_directory_metadata_is_safe', 'installer_cleanup_created_storage']
                for optional in ('installer_preserve_recovery_state',):
                    if re.search(r'^' + optional + r'\(\)', SOURCE, re.M):
                        names.append(optional)
                result = subprocess.run(['bash', '--noprofile', '--norc', '-c',
                    'set -euo pipefail\n' + '\n'.join(function(n) for n in names) + r'''
SCRIPT_TMP_DIR="$1/runtime"
mkdir -m700 "$SCRIPT_TMP_DIR"
SCRIPT_MAIN_PID="$BASHPID"
PROCESS_ACTIVE_PID=123
PROCESS_ACTIVE_PGID=123
PROCESS_CGROUP_DIR=''
PROCESS_CGROUP_RELATIVE=''
PROCESS_SEQUENCE=1
ERROR_MSG_TMP_FILE="$SCRIPT_TMP_DIR/installer.err"
TARGET_MOUNT_MARKER="$SCRIPT_TMP_DIR/target-mounted"
CRYPTROOT_MARKER="$SCRIPT_TMP_DIR/cryptroot-opened"
ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT="$(printf 'a%.0s' {1..64})"
ARCH_LINUX_PASSWORD='private-fixture-value'
SCRIPT_LOG="$1/log"
GUM=/missing-gum
DEBUG=false
scenario="$2"
printf 'active %s\n' "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT" >"$TARGET_MOUNT_MARKER"
printf 'active %s\n' "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT" >"$CRYPTROOT_MARKER"
chmod 600 "$TARGET_MOUNT_MARKER" "$CRYPTROOT_MARKER"
if [ "$scenario" = reap-before-target ]; then
    rm -- "$TARGET_MOUNT_MARKER" "$CRYPTROOT_MARKER"
    ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT=''
fi
printf '%s\n' "$ARCH_LINUX_PASSWORD" >"$SCRIPT_TMP_DIR/process.log"
printf '%s\n' "$ARCH_LINUX_PASSWORD" >"$SCRIPT_TMP_DIR/installer.conf.new"
storage_marker_state() { echo active; }
process_cgroup_is_empty() { [ -z "$PROCESS_ACTIVE_PID" ]; }
process_reap_active() {
    echo reap >>"$SCRIPT_LOG"
    case "$scenario" in reap-failure | reap-before-target | recovery-allocation-failure) return 1 ;; esac
    PROCESS_ACTIVE_PID=''
    if [ "$scenario" = scope-remove-failure ]; then
        PROCESS_CGROUP_DIR=/fixture/unremoved
        return 1
    fi
}
if [ "$scenario" = recovery-allocation-failure ]; then
    mktemp(){ return 1; }
fi
mounted=true
findmnt() { [ "$mounted" = true ] || return 1; echo '/dev/root /mnt'; }
target_mount_tree_is_owned() { :; }
assert_target_root_mounted() { :; }
umount() {
    echo unmount >>"$SCRIPT_LOG"
    [ "$scenario" != busy-unmount ] || return 1
    mounted=false
}
cryptroot_belongs_to_target() { :; }
cryptsetup() { echo close >>"$SCRIPT_LOG"; [ "$scenario" != mapper-failure ]; }
log_fail() { printf '%s\n' "$*" >&2; }
# Verify the production handler clears its password even on a failed cleanup.
unset() { builtin unset "$@"; [ "${ARCH_LINUX_PASSWORD+x}" != x ] || exit 98; }
trap 'trap_exit' EXIT
[ "$scenario" != success ] || exit 0
[ "$scenario" != cancel ] || exit 130
exit 1
''', 'exit-check', tmp, scenario], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, expected_status, result.stderr)
                calls = Path(tmp, 'log').read_text().splitlines()
                self.assertEqual(calls, ['reap'] if scenario in ('success', 'reap-failure', 'reap-before-target', 'recovery-allocation-failure')
                                 else ['reap', 'unmount'] if scenario == 'busy-unmount'
                                 else ['reap', 'unmount', 'close'])
                runtime = Path(tmp, 'runtime')
                self.assertFalse(runtime.exists())
                recoveries = list(Path(tmp).glob('arch-linux-installer-recovery.*'))
                self.assertEqual(len(recoveries), 1 if retained else 0)
                if retained:
                    runtime = recoveries[0]
                    self.assertEqual(runtime.stat().st_mode & 0o777, 0o700)
                    self.assertEqual({p.name for p in runtime.iterdir()},
                                     {'recovery-state'} if scenario in ('scope-remove-failure', 'reap-before-target')
                                     else {'cryptroot-opened', 'recovery-state'} if scenario == 'mapper-failure'
                                     else {'target-mounted', 'cryptroot-opened', 'recovery-state'})
                    for item in runtime.iterdir():
                        self.assertEqual(item.stat().st_mode & 0o777, 0o600)
                        self.assertNotIn(b'private-fixture-value', item.read_bytes())

    def test_recovery_receipt_isolated_from_late_worker_absolute_paths(self):
        definitions = '\n'.join(function(n) for n in (
            'trap_exit', 'installer_preserve_recovery_state', 'runtime_directory_metadata_is_safe'))
        with tempfile.TemporaryDirectory() as tmp:
            program = 'set -euo pipefail\n' + definitions + r'''
SCRIPT_TMP_DIR="$1/runtime"
mkdir -m700 "$SCRIPT_TMP_DIR"
SCRIPT_MAIN_PID="$BASHPID" PROCESS_SEQUENCE=1 PROCESS_ACTIVE_PID=123 PROCESS_CGROUP_DIR=''
TARGET_MOUNT_MARKER="$SCRIPT_TMP_DIR/target-mounted"
CRYPTROOT_MARKER="$SCRIPT_TMP_DIR/cryptroot-opened"
ERROR_MSG_TMP_FILE="$SCRIPT_TMP_DIR/installer.err"
ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT="$(printf 'a%.0s' {1..64})"
ARCH_LINUX_PASSWORD=private-fixture
GUM=/missing DEBUG=false SCRIPT_LOG="$1/log"
printf 'active %s\n' "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT" >"$TARGET_MOUNT_MARKER"
chmod 600 "$TARGET_MOUNT_MARKER"
storage_marker_state(){ echo active; }
process_reap_active(){ return 1; }
process_cgroup_is_empty(){ return 1; }
# Synchronize an actual background writer with the real retention receipt/log event.
# It retains the original absolute path, as the launched executor does.
old_runtime="$SCRIPT_TMP_DIR"
(
    while [ ! -e "$1/retention-ready" ]; do sleep .01; done
    mkdir -p -- "$old_runtime"
    printf 'late-worker-secret\n' >"$old_runtime/installer.err"
    chmod 600 "$old_runtime/installer.err"
    touch "$1/late-write-done"
) &
writer="$!"
# This logging adapter's argv is the message; retain test synchronization path separately.
sync_root="$1"
log_fail(){
    if [[ "$*" = 'Cleanup incomplete;'* ]]; then
        touch "$sync_root/retention-ready"
        while [ ! -e "$sync_root/late-write-done" ]; do sleep .01; done
        wait "$writer"
        printf '%s\n' "${SCRIPT_RECOVERY_DIR:-$SCRIPT_TMP_DIR}" >"$sync_root/recovery-path"
    fi
}
trap trap_exit EXIT
exit 1
'''
            result = subprocess.run(['bash', '-c', program, 'late-worker', tmp], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1, result.stderr)
            recovery = Path(Path(tmp, 'recovery-path').read_text().strip())
            self.assertNotEqual(recovery, Path(tmp, 'runtime'))
            self.assertEqual({item.name for item in recovery.iterdir()}, {'target-mounted', 'recovery-state'})
            self.assertEqual(recovery.stat().st_mode & 0o777, 0o700)
            for item in recovery.iterdir():
                self.assertEqual(item.stat().st_mode & 0o777, 0o600)
                self.assertNotIn(b'secret', item.read_bytes())
            self.assertEqual(Path(tmp, 'runtime/installer.err').read_text(), 'late-worker-secret\n')

    def test_appearance_selector_describes_all_gtk_payloads_and_preserves_value(self):
        output = bash(function('select_gnome_theme_profile') + r'''
ARCH_LINUX_DESKTOP_ENABLED=true
ARCH_LINUX_GNOME_THEME_PROFILE=''
gum_choose() {
    [[ "$*" = *GTK3/GTK4/libadwaita* ]] || return 99
    printf '%s\n' 'marble - selected'
}
trap_gum_exit_confirm() { exit 99; }
properties_generate() { :; }
gum_property() { :; }
select_gnome_theme_profile
printf '%s' "$ARCH_LINUX_GNOME_THEME_PROFILE"
''')
        self.assertEqual(output, 'marble')

    def test_exact_dual_boot_footprint_and_case_insensitive_ancestors(self):
        program = (function('dual_boot_esp_path_is_available') + '\n' +
                   function('dual_boot_esp_footprint_is_clear'))
        for kernel in ('linux', 'linux-lts', 'linux-zen', 'linux-hardened'):
            for microcode in ('none', 'intel-ucode', 'amd-ucode'):
                with self.subTest(kernel=kernel, microcode=microcode), tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    (root / 'EFI/ali-neighbor').mkdir(parents=True)
                    (root / 'loader/entries').mkdir(parents=True)
                    (root / 'EFI/ali-neighbor/vmlinuz-linux').write_text('foreign')
                    (root / 'loader/entries/neighbor.conf').write_text('foreign')
                    (root / 'loader/entries.srel').write_text('type1\n')
                    paths = [f'vmlinuz-{kernel}', f'initramfs-{kernel}.img',
                             f'initramfs-{kernel}-fallback.img', 'EFI/systemd', 'EFI/BOOT',
                             'loader/loader.conf', 'loader/random-seed',
                             'loader/entries/main.conf', 'loader/entries/main-fallback.conf']
                    if microcode != 'none':
                        paths.append(microcode + '.img')
                    check = program + '\ndual_boot_esp_footprint_is_clear "$1" "$2" "$3" systemd\n'
                    bash(check, tmp, kernel, microcode)
                    for path in paths:
                        target = root / path
                        target.write_text('existing neighbor bytes')
                        bash(check, tmp, kernel, microcode, expected_status=1)
                        self.assertEqual(target.read_text(), 'existing neighbor bytes')
                        target.unlink()
                    # Existing regular-file and symlink ancestors cannot mean an absent writer.
                    (root / 'EFI/ali-neighbor/vmlinuz-linux').unlink()
                    (root / 'EFI/ali-neighbor').rmdir()
                    (root / 'EFI').rmdir()
                    for ancestor in ('file', 'symlink', 'case-duplicate'):
                        if ancestor == 'file':
                            (root / 'EFI').write_text('foreign')
                        elif ancestor == 'symlink':
                            (root / 'EFI').symlink_to(root / 'loader', target_is_directory=True)
                        else:
                            (root / 'EFI').mkdir()
                            (root / 'efi').mkdir()
                        bash(check, tmp, kernel, microcode, expected_status=1)
                        if ancestor == 'case-duplicate':
                            (root / 'EFI').rmdir()
                            (root / 'efi').rmdir()
                        else:
                            (root / 'EFI').unlink()
                    (root / 'eFi/BoOt').mkdir(parents=True)
                    bash(check, tmp, kernel, microcode, expected_status=1)

    def test_grub_subtree_custom_kernel_and_entries_srel_refusal(self):
        program = (function('dual_boot_esp_path_is_available') + '\n' +
                   function('dual_boot_esp_footprint_is_clear') +
                   '\ndual_boot_esp_footprint_is_clear "$1" "$2" none "$3"\n')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bash(program, tmp, 'linux', 'grub')
            for path in ('grub/grub.cfg', 'gRuB/grub-btrfs.cfg', 'EFI/aRcHlInUx/grubx64.efi'):
                target = root / path
                target.parent.mkdir(parents=True)
                target.write_text('foreign')
                bash(program, tmp, 'linux', 'grub', expected_status=1)
                target.unlink()
                target.parent.rmdir()
            bash(program, tmp, 'custom', 'systemd', expected_status=1)
            (root / 'loader').mkdir()
            target = root / 'loader/entries.srel'
            for content in ('type2\n', 'type1', 'type1\nforeign', ''):
                target.write_text(content)
                bash(program, tmp, 'linux', 'systemd', expected_status=1)
                target.unlink()
            target.symlink_to(root / 'missing')
            bash(program, tmp, 'linux', 'systemd', expected_status=1)


    def test_readonly_namespace_probe_consumes_failures_and_removes_scratch(self):
        for outcome in ('clear', 'mount-failure', 'findmnt-failure', 'writable-view', 'umount-failure'):
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as tmp:
                output = bash('\n'.join(function(n) for n in (
                    'dual_boot_inspect_esp_handle', 'dual_boot_esp_path_is_available',
                    'dual_boot_esp_footprint_is_clear')) + r'''
SCRIPT_TMP_DIR="$1"
ARCH_LINUX_KERNEL=linux
ARCH_LINUX_MICROCODE=none
ARCH_LINUX_BOOTLOADER=systemd
outcome="$2"
log_fail() { :; }
timeout() { [ "$1" = --signal=TERM ] && [ "$2" = --kill-after=5 ] && [ "$3" = 30 ]; shift 3; "$@"; }
unshare() {
    [ "$1" = --mount ] && [ "$2" = --propagation ] && [ "$3" = private ]
    [ "$4" = /usr/bin/bash ] && [ "$7" = -c ]
    local program="$8" adapters
    shift 9
    adapters='mount() {
        [ "$1" = -t ] && [ "$2" = vfat ] && [ "$3" = -o ] &&
        [ "$4" = ro,nosuid,nodev,noexec ] && [ "$5" = -- ] &&
        [ "$6" = /proc/accepted/fd/10 ] || return 99
        [ "$outcome" != mount-failure ];
    }
    umount() { [ "$outcome" != umount-failure ]; }
    findmnt() {
        [ "$outcome" != findmnt-failure ] || return 2
        if [ "$outcome" = writable-view ]; then echo rw; else echo ro,nosuid,nodev,noexec; fi
    }'
    outcome="$outcome" /usr/bin/bash --noprofile --norc -c "$adapters
$program" probe-child "$@"
}
status=0
dual_boot_inspect_esp_handle /proc/accepted/fd/10 || status=$?
[ -z "$(find "$SCRIPT_TMP_DIR" -mindepth 1 -print -quit)" ]
printf '%s' "$status"
''', tmp, outcome)
                self.assertEqual(output, '0' if outcome == 'clear' else '1')

    def test_actual_storage_cleanup_failure_preserves_mapper_and_markers(self):
        for outcome in ('busy', 'probe-error', 'foreign-root', 'close-failure', 'success'):
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as tmp:
                output = bash(function('installer_cleanup_created_storage') + r'''
TARGET_MOUNT_MARKER="$1/target-mounted"
CRYPTROOT_MARKER="$1/cryptroot-opened"
touch "$TARGET_MOUNT_MARKER" "$CRYPTROOT_MARKER"
outcome="$2"
mounted=true
storage_marker_state() { echo active; }
findmnt() {
    [ "$outcome" != probe-error ] || return 2
    [ "$mounted" = true ] || return 1
    echo '/dev/root /mnt'
}
target_mount_tree_is_owned() { :; }
assert_target_root_mounted() { [ "$outcome" != foreign-root ]; }
umount() {
    echo unmount >>"$calls"
    [ "$outcome" != busy ] || return 1
    mounted=false
}
cryptroot_belongs_to_target() { :; }
cryptsetup() { echo close >>"$calls"; [ "$outcome" != close-failure ]; }
log_fail() { :; }
calls="$1/calls"
status=0
installer_cleanup_created_storage || status=$?
printf '%s:%s:%s\n' "$status" "$([ -e "$TARGET_MOUNT_MARKER" ] && echo retained || echo removed)" \
    "$([ -e "$CRYPTROOT_MARKER" ] && echo retained || echo removed)"
[ ! -e "$calls" ] || cat "$calls"
''', tmp, outcome)
                self.assertEqual(output, {
                    'busy': '1:retained:retained\nunmount',
                    'probe-error': '1:retained:retained',
                    'foreign-root': '1:retained:retained',
                    'close-failure': '1:removed:retained\nunmount\nclose',
                    'success': '0:removed:removed\nunmount\nclose',
                }[outcome])

    def test_recovery_retention_rejects_secret_malformed_linked_and_stale_markers(self):
        definitions = '\n'.join(function(n) for n in (
            'installer_preserve_recovery_state', 'runtime_directory_metadata_is_safe',
            'storage_marker_state'))
        for invalid in ('secret', 'symlink', 'hardlink', 'wrong-mode', 'stale'):
            with self.subTest(invalid=invalid), tempfile.TemporaryDirectory() as tmp:
                bash(definitions + r'''
SCRIPT_TMP_DIR="$1/runtime"
mkdir -m700 "$SCRIPT_TMP_DIR"
TARGET_MOUNT_MARKER="$SCRIPT_TMP_DIR/target-mounted"
CRYPTROOT_MARKER="$SCRIPT_TMP_DIR/cryptroot-opened"
SCRIPT_MAIN_PID="$BASHPID"
PROCESS_SEQUENCE=1
PROCESS_CGROUP_DIR=''
ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT="$(printf 'a%.0s' {1..64})"
printf 'active %s\n' "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT" >"$CRYPTROOT_MARKER"
cp "$CRYPTROOT_MARKER" "$TARGET_MOUNT_MARKER"
chmod 600 "$CRYPTROOT_MARKER" "$TARGET_MOUNT_MARKER"
invalid="$2"
case "$invalid" in
secret) printf 'private-secret\n' >"$TARGET_MOUNT_MARKER" ;;
symlink) rm "$TARGET_MOUNT_MARKER"; ln -s "$1/foreign" "$TARGET_MOUNT_MARKER"; echo private-secret >"$1/foreign" ;;
hardlink) ln "$TARGET_MOUNT_MARKER" "$1/foreign" ;;
wrong-mode) chmod 644 "$TARGET_MOUNT_MARKER" ;;
stale) printf 'active %s\n' "$(printf 'b%.0s' {1..64})" >"$TARGET_MOUNT_MARKER" ;;
esac
printf 'private-secret\n' >"$SCRIPT_TMP_DIR/process.log"
is_choice() { local value="$1"; shift; local allowed; for allowed; do [ "$value" != "$allowed" ] || return 0; done; return 1; }
destructive_target_snapshot() { printf '%s\n' "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT"; }
log_fail() { :; }
installer_preserve_recovery_state false
[ ! -e "$TARGET_MOUNT_MARKER" ] && [ ! -L "$TARGET_MOUNT_MARKER" ]
[ ! -e "$SCRIPT_TMP_DIR" ]
[ -f "$SCRIPT_RECOVERY_DIR/cryptroot-opened" ] && [ -f "$SCRIPT_RECOVERY_DIR/recovery-state" ]
[ "$(find "$SCRIPT_RECOVERY_DIR" -mindepth 1 -maxdepth 1 | wc -l)" = 2 ]
! grep -rFq private-secret "$SCRIPT_RECOVERY_DIR"
''', tmp, invalid)

    def test_recovery_parent_validation_is_fail_closed(self):
        definitions = '\n'.join(function(n) for n in (
            'installer_preserve_recovery_state', 'runtime_directory_metadata_is_safe'))
        with tempfile.TemporaryDirectory() as tmp:
            bash(definitions + r'''
SCRIPT_TMP_DIR="$1/runtime"
mkdir -m700 "$SCRIPT_TMP_DIR"
TARGET_MOUNT_MARKER="$SCRIPT_TMP_DIR/target-mounted"
CRYPTROOT_MARKER="$SCRIPT_TMP_DIR/cryptroot-opened"
ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT="$(printf 'a%.0s' {1..64})"
PROCESS_CGROUP_DIR=''
chmod 777 "$1"
status=0
installer_preserve_recovery_state false || status=$?
chmod 700 "$1"
[ "$status" -eq 1 ]
[ -z "${SCRIPT_RECOVERY_DIR:-}" ]
[ -z "$(find "$1" -maxdepth 1 -name 'arch-linux-installer-recovery.*' -print -quit)" ]
''', tmp)

    def test_reap_does_not_block_wait_when_containment_is_still_populated(self):
        output = bash(function('process_reap_active') + r'''
PROCESS_ACTIVE_PID=99999999
PROCESS_ACTIVE_PGID=''
PROCESS_CGROUP_DIR=/fixture/unquiet
process_wait_cgroup_empty() { return 1; }
process_kill_contained() { return 1; }
wait() { echo unsafe-wait; return 0; }
process_remove_cgroup() { echo unsafe-removal; }
status=0
process_reap_active true || status=$?
printf '%s:%s:%s' "$status" "$PROCESS_ACTIVE_PID" "$PROCESS_CGROUP_DIR"
''')
        self.assertEqual(output, '1:99999999:/fixture/unquiet')

    def test_prepare_disk_stops_after_accepted_handle_rejection(self):
        for filesystem in ('ext4', 'btrfs'):
            for encrypted in ('false', 'true'):
                with self.subTest(filesystem=filesystem, encrypted=encrypted), tempfile.TemporaryDirectory() as tmp:
                    bash(function('exec_prepare_disk') + r'''
DEBUG=false
ARCH_LINUX_DISK="$1/disk"
ARCH_LINUX_BOOT_PARTITION="$1/boot"
ARCH_LINUX_ROOT_PARTITION="$1/root"
touch "$ARCH_LINUX_DISK" "$ARCH_LINUX_BOOT_PARTITION" "$ARCH_LINUX_ROOT_PARTITION"
ARCH_LINUX_DISK_IDENTITY=accepted
ARCH_LINUX_BOOT_PARTITION_IDENTITY=boot
ARCH_LINUX_ROOT_PARTITION_IDENTITY=root
ARCH_LINUX_DUAL_BOOT_ENABLED=true
ARCH_LINUX_FILESYSTEM="$2"
ARCH_LINUX_ENCRYPTION_ENABLED="$3"
ARCH_LINUX_PASSWORD=fixture
TARGET_MOUNT_MARKER="$1/marker"
CRYPTROOT_MARKER="$1/crypt"
PROCESS_LOG_TMP_FILE="$1/log"
process_init() { :; }
process_enter_cgroup() { :; }
process_return() { exit "$1"; }
process_capture() { wait "$1"; }
log_fail() { :; }
log_info() { :; }
assert_accepted_destructive_target() { :; }
target_storage_is_idle() { :; }
block_canonical() { printf '%s' "$1"; }
block_disk_handle_is_bound() { :; }
checks=0
block_partition_handle_is_bound() { checks=$((checks + 1)); [ "$checks" -le 2 ]; }
dual_boot_inspect_esp_handle() { :; }
mark_storage_intent() { echo intent >"$1"; }
activate_storage_marker() { echo active >"$1"; }
installer_cleanup_created_storage() { :; }
mkfs.ext4() { echo mutation >>"$calls"; }
mkfs.btrfs() { echo mutation >>"$calls"; }
mount() { echo mutation >>"$calls"; }
btrfs() { echo mutation >>"$calls"; }
umount() { echo mutation >>"$calls"; }
mkdir() { echo mutation >>"$calls"; }
cryptsetup() { echo mutation >>"$calls"; }
calls="$1/calls"
status=0
exec_prepare_disk || status=$?
[ "$status" -ne 0 ] && [ ! -e "$calls" ] && [ ! -e "$TARGET_MOUNT_MARKER" ]
''', tmp, filesystem, encrypted)

    def test_pacstrap_rejects_missing_root_before_target_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            bash(function('exec_pacstrap_core') + r'''
DEBUG=false
PROCESS_LOG_TMP_FILE="$1/log"
process_init() { :; }
process_enter_cgroup() { :; }
process_capture() { wait "$1"; }
assert_target_root_mounted() { return 1; }
log_fail() { :; }
mkdir() { echo mutation >"$1/calls"; }
pacstrap() { echo mutation >"$1/calls"; }
status=0
exec_pacstrap_core || status=$?
[ "$status" -ne 0 ] && [ ! -e "$1/calls" ]
''', tmp)

    def test_mount_marker_requires_the_accepted_root(self):
        for source in ('', '/dev/foreign', '/dev/root', '/dev/root[/@]\n/dev/foreign'):
            with self.subTest(source=source), tempfile.TemporaryDirectory() as tmp:
                output = bash(function('activate_storage_marker') + '\n' + function('assert_target_root_mounted') + r'''
TARGET_MOUNT_MARKER="$1/marker"
CRYPTROOT_MARKER="$1/crypt"
ARCH_LINUX_ROOT_PARTITION=/dev/root
ARCH_LINUX_ENCRYPTION_ENABLED=false
storage_marker_state() { echo intent; }
write_storage_marker() { echo active >"$1"; }
assert_accepted_destructive_target() { :; }
block_canonical() { printf '%s' "$1"; }
# Use a separate variable because findmnt arguments are production argv.
fixture_source="$2"
findmnt() { [ -n "$fixture_source" ] || return 1; printf '%s\n' "$fixture_source"; }
status=0
activate_storage_marker "$TARGET_MOUNT_MARKER" || status=$?
printf '%s' "$status"
''', tmp, source)
                self.assertEqual(output, '0' if source == '/dev/root' else '1')

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
