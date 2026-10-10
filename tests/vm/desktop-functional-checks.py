#!/usr/bin/env python3
"""Execute the actual functional-round producer under bounded input/guest fixtures."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHARED = [
    "clipboard-history-copy-paste",
    "dash-extension-app-activation",
    "no-screenshot-box-capture-on-release",
    "appindicator-synthetic-item-lifecycle",
    "caffeine-keyboard-inhibition-cycle",
    "blur-overview-native-effects",
    "just-perfection-panel-control",
]


class FunctionalRound(unittest.TestCase):
    def run_round(self, scenario, round_name, mode="staged", fail_phase=""):
        source = (ROOT / "tests/vm/run.sh").read_text()
        body = source.split("run_extension_functional_acceptance() {", 1)[1]
        body = "run_extension_functional_acceptance() {" + body.split("\nhmp_type_password() {", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            script = r'''
set -Eeuo pipefail
input_mode=$1; scenario_id=$2; evidence=$3; fail_phase=$4
qga_verify() {
    printf 'GUEST %s\n' "$1"
    [ "$1" != "$fail_phase" ] || return 1
    case "$1" in
    extension-*-native-prepare)
        probe_round=${1#extension-}; probe_round=${probe_round%-native-prepare}
        printf 'DESKTOP_PROBE_IDENTITY uid=1000 round=%s\n' "$probe_round" >"$evidence/$2.stdout" ;;
    extension-*-dash)
        printf 'EXTENSION_PROBE_DISPLAY width=1280 height=800 scale=1\n' >"$evidence/$2.stdout" ;;
    esac
}
qmp_extension_input() { printf 'INPUT %s\n' "$1"; }
sleep() { :; }
die() { printf 'FAIL %s\n' "$*" >&2; return 1; }
record_assertion() { printf 'ASSERT %s\n' "$1"; }
'''
            script += body + '\nrun_extension_functional_acceptance "$5"\n'
            return subprocess.run(
                ["bash", "--noprofile", "--norc", "-c", script, "fixture", mode,
                 scenario, directory, fail_phase, round_name],
                text=True, capture_output=True, timeout=5)

    def assert_round(self, scenario, round_name, mode="staged"):
        result = self.run_round(scenario, round_name, mode)
        self.assertEqual(result.returncode, 0, result.stderr)
        suffix = "-postreboot" if round_name == "postreboot" else ""
        expected = SHARED + (["user-theme-native-stylesheet-switch"]
                             if scenario.startswith("marble-") else [])
        assertions = [line.removeprefix("ASSERT ") for line in result.stdout.splitlines()
                      if line.startswith("ASSERT ")]
        self.assertEqual(assertions, [name + suffix for name in expected])
        self.assertIn("INPUT looking-glass", result.stdout)
        self.assertIn("INPUT overview", result.stdout)
        self.assertIn("INPUT caffeine", result.stdout)

    def test_marble_upgrade_covers_all_eight(self):
        self.assert_round("marble-gnome-btrfs-luks2-plymouth-systemdboot", "upgrade")

    def test_marble_postreboot_covers_all_eight(self):
        self.assert_round("marble-gnome-btrfs-luks2-plymouth-systemdboot", "postreboot")

    def test_stock_firstlogin_covers_all_seven(self):
        self.assert_round("stock-gnome-btrfs-luks2-plymouth-grub", "firstlogin")

    def test_stock_postreboot_covers_all_seven(self):
        self.assert_round("stock-gnome-btrfs-luks2-plymouth-grub", "postreboot")

    def test_public_marble_firstlogin_covers_all_eight(self):
        self.assert_round("marble-gnome-btrfs-luks2-plymouth-systemdboot", "firstlogin", "public")

    def test_public_marble_postreboot_covers_all_eight(self):
        self.assert_round("marble-gnome-btrfs-luks2-plymouth-systemdboot", "postreboot", "public")

    def test_invalid_profile_or_round_cannot_emit_assertions(self):
        for scenario, round_name, mode in [
            ("minimal-ext4-systemdboot", "firstlogin", "staged"),
            ("stock-gnome-btrfs-luks2-plymouth-grub", "upgrade", "staged"),
            ("stock-gnome-btrfs-luks2-plymouth-grub", "firstlogin", "public"),
            ("marble-gnome-btrfs-luks2-plymouth-systemdboot", "firstlogin", "staged"),
            ("marble-gnome-btrfs-luks2-plymouth-systemdboot", "upgrade", "public"),
        ]:
            with self.subTest(scenario=scenario, round_name=round_name, mode=mode):
                result = self.run_round(scenario, round_name, mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("ASSERT ", result.stdout)

    def test_failed_native_observation_cannot_emit_completed_round(self):
        result = self.run_round("marble-gnome-btrfs-luks2-plymouth-systemdboot", "upgrade",
                                fail_phase="extension-upgrade-native-blur-on")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("ASSERT ", result.stdout)


if __name__ == "__main__":
    unittest.main()
