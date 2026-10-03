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
            command = body + "\nselect_snapshot_grub_entry '" + str(main) + "' '" + str(entries) + "' fixture @snapshots/qa-fixture /dev/vda2 partuuid\n"
            return subprocess.run(["bash", "-c", command], capture_output=True, text=True, timeout=5)
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
            marker = lower / "var/lib/arch-linux-vm/snapshot-marker"; marker.parent.mkdir(parents=True); marker.write_text("fixture")
            uuid = "11111111-1111-1111-1111-111111111111"; partuuid = "22222222-2222-2222-2222-222222222222"
            state.write_text("run_id=fixture\nsubvol=@snapshots/qa-fixture\nroot_uuid=" + uuid + "\nnormal_boot_id=33333333-3333-3333-3333-333333333333\nroot_device=/dev/vda2\nroot_partuuid=" + partuuid + "\n")
            commandline = root / "cmdline"; commandline.write_text(argument.replace("uuid", uuid).replace("part-id", partuuid) + " rootflags=subvol=@snapshots/qa-fixture systemd.volatile=overlay")
            body = "\n".join(function(name) for name in ("snapshot_root_argument_matches", "snapshot_lowerdir_matches", "require_kernel_argument_once", "require_prefixed_kernel_argument_once", "verify_snapshot_runtime"))
            body = body.replace('/boot/qa-snapshot-${run_id}.state', str(state)).replace('/proc/cmdline', str(commandline))
            script = r'''set -euo pipefail
run_id=fixture scenario=stock-gnome-btrfs-grub
fixture_lower=$1
fixture_uuid=$2
fixture_partuuid=$3
changed=$4
[(){ if [[ "$*" = '-b /dev/vda2 ]' ]]; then return 0; fi; builtin [ "$@"; }
stat(){ printf '0:600:1'; }
findmnt(){
    case "$*" in
        *FSTYPE*'target /') printf overlay;;
        *FSTYPE*) printf btrfs;;
        *FSROOT*) printf /@snapshots/qa-fixture;;
        *OPTIONS*'target /') printf 'lowerdir=%s' "$fixture_lower";;
        *OPTIONS*) printf ro;;
        *UUID*) if [ "$changed" = lower-uuid ]; then printf wrong; else printf '%s' "$fixture_uuid"; fi;;
    esac
}
btrfs(){ printf ro=true; }
mounted_source_device(){ if [ "$changed" = device ]; then printf /dev/vda3; else printf /dev/vda2; fi; }
find_target(){ printf /dev/vda; }
partition_name(){ printf /dev/vda2; }
blkid(){
    if [[ "$*" = *PARTUUID* ]]; then
        if [ "$changed" = partuuid ]; then printf wrong; else printf '%s' "$fixture_partuuid"; fi
    else
        if [ "$changed" = uuid ]; then printf wrong; else printf '%s' "$fixture_uuid"; fi
    fi
}
verify_kernel_initramfs_pair(){ [ "$changed" != modules ]; }
verify_grub_efi_target(){ :; }
verify_grub_package_integrity(){ :; }
systemctl(){ :; }
nm-online(){ :; }
''' + body + "\nverify_snapshot_runtime\n"
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
script_dir="$1" evidence="$1" response="$2" input_mode=staged marker_prefix=MINIMAL media_qualification=false
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
