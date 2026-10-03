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
        expected = ["verify:helper-failure", "verify:helper-restored-prelogin", "login:helper-restored-login", "verify:deactivate-gdm", "verify:deactivated-prelogin", "login:deactivated-login"]
        self.assertEqual([line for line in lines if line in expected], expected)
    def snapshot_entry(self, rootflags="subvol=@snapshots/qa-fixture", root="UUID=fixture", image="/initramfs-linux.img"):
        body = function("select_snapshot_grub_entry")
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp) / "grub.cfg"; entries = Path(tmp) / "grub-btrfs.cfg"
            main.write_text("submenu 'Arch snapshots' {\nconfigfile ${prefix}/grub-btrfs.cfg\n}\n")
            entries.write_text("submenu 'snapshot fixture' {\nmenuentry 'linux' {\nlinux /vmlinuz-linux root=" + root + " rootflags=" + rootflags + " systemd.volatile=overlay\ninitrd " + image + "\n}\n}\n")
            command = body + "\nselect_snapshot_grub_entry '" + str(main) + "' '" + str(entries) + "' fixture @snapshots/qa-fixture\n"
            return subprocess.run(["bash", "-c", command], capture_output=True, text=True, timeout=5)
    def test_snapshot_entry_exact(self):
        result = self.snapshot_entry(); self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Arch snapshots>snapshot fixture>linux")
    def test_snapshot_wrong_entry(self): self.assertNotEqual(self.snapshot_entry(rootflags="subvol=@").returncode, 0)
    def test_snapshot_wrong_device(self): self.assertNotEqual(self.snapshot_entry(root="UUID=other").returncode, 0)
    def test_snapshot_wrong_image(self): self.assertNotEqual(self.snapshot_entry(image="/initramfs-other.img").returncode, 0)
    def test_snapshot_lowerdir_identity(self):
        body = function("snapshot_lowerdir_matches")
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

    def test_upgrade_before_reboot(self): self.assertEqual(self.kernel(phase="update", running="old"), 0)
    def test_stale_running_release(self): self.assertNotEqual(self.kernel(running="old"), 0)
    def test_missing_image(self): self.assertNotEqual(self.kernel(image=False), 0)
    def test_missing_modules(self): self.assertNotEqual(self.kernel(modules=False), 0)
    def test_wrong_boot_image(self): self.assertNotEqual(self.kernel(match=False), 0)
    def test_mixed_initramfs(self): self.assertNotEqual(self.kernel(releases=("new", "old")), 0)
    def test_empty_initramfs(self): self.assertNotEqual(self.kernel(releases=()), 0)
if __name__ == "__main__": unittest.main()
