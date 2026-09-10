#!/usr/bin/env python3
"""Regression checks for the confirmed installation remediation contracts.

These tests evaluate isolated production functions and run the generated first-login
runner only in temporary directories. They never invoke the installer or touch host
mounts, boot files, user settings, or package databases.
"""

from pathlib import Path
import os
import re
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "arch-linux-installer.sh").read_text(encoding="utf-8")


def function(name):
    if name == "chroot_user_finalize_init":
        pattern = r"^" + re.escape(name) + r"\(\) \{\n.*?^\}\n\n# /{5,}\n# TRAP FUNCTIONS"
    else:
        pattern = r"^" + re.escape(name) + r"\(\) \{\n.*?^\}\n"
    match = re.search(pattern, SOURCE, re.M | re.S)
    if match is None:
        raise AssertionError("Missing production function: " + name)
    return match.group(0)


def run_bash(program, *args, timeout=20):
    return subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", "set -euo pipefail\n" + program,
         "installation-remediation-check", *map(str, args)],
        text=True,
        capture_output=True,
        timeout=timeout,
        env={"PATH": os.environ["PATH"], "LANG": "C", "LC_ALL": "C"},
    )


def write_fake_gsettings(path):
    path.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${GSETTINGS_CALLS:?}"
case "${1:-}" in
set)
    if [ "${FAIL_GSETTINGS:-0}" = 1 ]; then
        printf 'injected gsettings failure\n' >&2
        exit 42
    fi
    touch -- "${GSETTINGS_STATE:?}"
    ;;
get)
    if [ -f "${GSETTINGS_STATE:?}" ]; then
        if [ "${MISMATCH_GSETTINGS:-0}" = 1 ]; then
            printf "'en_US.UTF-8'\n"
        else
            printf "'ru_RU.UTF-8'\n"
        fi
    else
        printf "'C.UTF-8'\n"
    fi
    ;;
*)
    printf 'unexpected gsettings operation\n' >&2
    exit 99
    ;;
esac
""",
        encoding="utf-8",
    )
    path.chmod(0o700)


def generate_locale_initializer(fixture):
    locale_function = function("desktop_configure_gnome_locale")
    finalizer = function("chroot_user_finalize_init")
    program = f"""
fixture={shlex.quote(str(fixture))}
export FIXTURE="$fixture"
mkdir -m 700 -- "$fixture/home"
mkdir -m 700 -- "$fixture/bin"
ARCH_LINUX_USERNAME=reviewuser
home_prefix="/home/"
INIT_FILENAME=initialize
VERSION=1.0.2
ARCH_LINUX_LOCALE_LANG=ru_RU
locale_with_utf8() {{ printf '%s.UTF-8\\n' "$1"; }}
chroot_user_append_file() {{
    local target="$1" relative
    relative="${{target#"${{home_prefix}}reviewuser"}}"
    cat >>"$FIXTURE/home${{relative}}"
}}
arch-chroot() {{
    [ "$1" = /mnt ] || return 98
    shift
    while [ "$#" -gt 0 ] && [ "$1" != /usr/bin/env ]; do shift; done
    [ "$#" -gt 0 ] || return 98
    shift
    local arg
    local -a args=()
    for arg in "$@"; do
        case "$arg" in
        "HOME=${{home_prefix}}reviewuser") args+=("HOME=$FIXTURE/home") ;;
        *) args+=("$arg") ;;
        esac
    done
    /usr/bin/env "${{args[@]}}"
}}
{locale_function}
{finalizer}
desktop_configure_gnome_locale
chroot_user_finalize_init
"""
    result = run_bash(program, timeout=20)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    home = fixture / "home"
    desktop = home / ".config/autostart/initialize.desktop"
    script = home / ".arch-linux/system/initialize.sh"
    log = home / ".arch-linux/system/initialize.log"
    marker = home / ".arch-linux/system/initialize.success"
    state = home / ".arch-linux/system/initialize.state"
    return home, desktop, script, log, marker, state


def run_autostart(desktop, home, fake_bin, state, calls, fail=False, mismatch=False):
    line = next(raw.removeprefix("Exec=") for raw in desktop.read_text().splitlines()
                if raw.startswith("Exec="))
    environment = os.environ.copy()
    environment.update(
        HOME=str(home),
        PATH=f"{fake_bin}:/usr/bin:/bin",
        LANG="C.UTF-8",
        LC_ALL="C.UTF-8",
        GSETTINGS_STATE=str(state.with_name("gsettings.state")),
        GSETTINGS_CALLS=str(calls),
        FAIL_GSETTINGS="1" if fail else "0",
        MISMATCH_GSETTINGS="1" if mismatch else "0",
    )
    return subprocess.run(["bash", "--noprofile", "--norc", "-c", line],
                          text=True, capture_output=True, env=environment, timeout=20)


class InstallationRemediationChecks(unittest.TestCase):
    def test_grub_uses_systemd_native_snapshot_overlay(self):
        body = function("exec_pacstrap_core")
        self.assertIn("btrfs_hook=' sd-volatile'", body)
        self.assertNotIn("grub-btrfs-overlayfs", body)
        self.assertIn("chroot_configure_grub_btrfs_snapshot_boot /mnt", body)
        guest = (ROOT / "tests/vm/guest/verify.sh").read_text(encoding="utf-8")
        self.assertIn("verify_kernel_initramfs_pair", guest)
        self.assertIn('kernel_release="$(uname -r)"', guest)

    def test_gnome_mandatory_settings_use_checked_runner(self):
        desktop = function("exec_install_desktop")
        self.assertIn("initialize_gsettings keyboard-sources", desktop)
        self.assertIn("initialize_gsettings switch-input-source", desktop)
        self.assertIn("initialize_gsettings switch-input-source-backward", desktop)
        finalizer = function("chroot_user_finalize_init")
        self.assertIn('exec >>"$log_file" 2>&1', finalizer)
        self.assertIn('success_marker="$system_dir/${init_name}.success"', finalizer)

    def test_grub_btrfs_configuration_is_idempotent_and_preserves_mode(self):
        body = function("chroot_configure_grub_btrfs_snapshot_boot")
        with tempfile.TemporaryDirectory(prefix="arch-linux-grub-btrfs-check-") as temporary:
            root = Path(temporary)
            config = root / "etc/default/grub-btrfs/config"
            config.parent.mkdir(parents=True)
            config.write_text(
                "# preserved\n"
                "GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=\"old\"\n"
                "GRUB_BTRFS_ROOTFLAGS=\"old\"\n",
                encoding="utf-8",
            )
            config.chmod(0o640)
            result = run_bash(body + r'''
chroot_configure_grub_btrfs_snapshot_boot "$1"
first="$(sha256sum -- "$1/etc/default/grub-btrfs/config" | awk '{print $1}')"
chroot_configure_grub_btrfs_snapshot_boot "$1"
second="$(sha256sum -- "$1/etc/default/grub-btrfs/config" | awk '{print $1}')"
printf '%s %s %s\n' "$first" "$second" "$(stat -c '%a' "$1/etc/default/grub-btrfs/config")"
''', root)
            self.assertEqual(result.returncode, 0, result.stderr)
            first, second, mode = result.stdout.strip().split()
            self.assertEqual(first, second)
            self.assertEqual(mode, "640")
            content = config.read_text(encoding="utf-8")
            self.assertEqual(content.count("GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="), 1)
            self.assertEqual(content.count("GRUB_BTRFS_ROOTFLAGS="), 1)
            self.assertIn('GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="systemd.volatile=overlay"', content)
            self.assertIn('GRUB_BTRFS_ROOTFLAGS="ro"', content)
            self.assertIn("# preserved", content)

    def test_scrub_configuration_enables_one_root_timer(self):
        body = function("chroot_enable_btrfs_scrub")
        result = run_bash(body + r'''
arch-chroot() { printf '%s\n' "$*"; }
chroot_enable_btrfs_scrub /mnt
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "/mnt systemctl enable btrfs-scrub@-.timer")
        core = function("exec_pacstrap_core")
        self.assertIn("chroot_enable_btrfs_scrub /mnt", core)
        self.assertNotIn("btrfs-scrub@home.timer", core)
        self.assertNotIn("btrfs-scrub@.snapshots.timer", core)

    def test_first_login_success_failure_and_retry_contract(self):
        with tempfile.TemporaryDirectory(prefix="arch-linux-first-login-check-") as temporary:
            fixture = Path(temporary)
            home, desktop, script, log, marker, state = generate_locale_initializer(fixture)
            fake_bin = fixture / "bin"
            fake_gsettings = fake_bin / "gsettings"
            calls = fixture / "gsettings.calls"
            write_fake_gsettings(fake_gsettings)

            failed = run_autostart(desktop, home, fake_bin, state, calls, fail=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertTrue(desktop.is_file())
            self.assertFalse(marker.exists())
            failure_log = log.read_text(encoding="utf-8")
            self.assertIn("injected gsettings failure", failure_log)
            self.assertNotIn("Initialized", failure_log)

            mismatch = run_autostart(desktop, home, fake_bin, state, calls, mismatch=True)
            self.assertNotEqual(mismatch.returncode, 0)
            self.assertTrue(desktop.is_file())
            self.assertFalse(marker.exists())
            mismatch_log = log.read_text(encoding="utf-8")
            self.assertIn("readback-mismatch", mismatch_log)
            self.assertNotIn("Initialized", mismatch_log)

            retried = run_autostart(desktop, home, fake_bin, state, calls, fail=False)
            self.assertEqual(retried.returncode, 0, retried.stderr)
            self.assertFalse(desktop.exists())
            self.assertTrue(marker.is_file())
            self.assertIn("Initialized", log.read_text(encoding="utf-8"))
            self.assertIn("completed=gnome-formats", state.read_text(encoding="utf-8"))
            self.assertGreaterEqual(log.read_text(encoding="utf-8").count("attempt="), 2)

            call_count = len(calls.read_text(encoding="utf-8").splitlines())
            second = subprocess.run(["bash", "--noprofile", "--norc", str(script)],
                                    text=True, capture_output=True,
                                    env=dict(os.environ, HOME=str(home), PATH=f"{fake_bin}:/usr/bin:/bin",
                                             LANG="C.UTF-8", LC_ALL="C.UTF-8",
                                             GSETTINGS_STATE=str(fixture / "gsettings.state"),
                                             GSETTINGS_CALLS=str(calls), FAIL_GSETTINGS="0"),
                                    timeout=20)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(call_count, len(calls.read_text(encoding="utf-8").splitlines()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
