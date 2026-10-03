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
    def shell_lifecycle(self, case="normal", checkpoint="extension-timeout"):
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
            def fstat(fd):
                value = real_fstat(fd)
                return os.stat_result(tuple(value)[:4] + (0,) + tuple(value)[5:])
            output = io.StringIO()
            with patch("subprocess.run", run), patch("os.fstat", fstat), contextlib.redirect_stderr(output):
                namespace["diagnose"]("1000", "1000", "fixture", "return-user-login", checkpoint)
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
            marker = lower / "var/lib/arch-linux-vm/snapshot-marker"; marker.parent.mkdir(parents=True); marker.write_text("fixture")
            uuid = "11111111-1111-1111-1111-111111111111"; partuuid = "22222222-2222-2222-2222-222222222222"
            state.write_text("run_id=fixture\nsubvol=@snapshots/qa-fixture\nroot_uuid=" + uuid + "\nnormal_boot_id=33333333-3333-3333-3333-333333333333\nroot_device=/dev/vda2\nroot_partuuid=" + partuuid + "\nselector_sha256=" + "a" * 64 + "\nproduction_cfg_sha256=" + "b" * 64 + "\n")
            if changed == "state-lines": state.write_text(state.read_text() + "SECRET_EXTRA\n")
            if changed == "state-run": state.write_text(state.read_text().replace("run_id=fixture", "run_id=SECRET_ID"))
            if changed == "state-subvol": state.write_text(state.read_text().replace("subvol=@snapshots/qa-fixture", "subvol=SECRET_PATH"))
            if changed == "cfg-record": state.write_text(state.read_text().replace("production_cfg_sha256=", "unknown="))
            if changed == "cfg-hash": state.write_text(state.read_text().replace("b" * 64, "c" * 64))
            if changed == "root-uuid": state.write_text(state.read_text().replace(uuid, "SECRET_UUID"))
            if changed == "marker": marker.write_text("SECRET_MARKER")
            commandline = root / "cmdline"; commandline.write_text(argument.replace("uuid", uuid).replace("part-id", partuuid) + " rootflags=subvol=@snapshots/qa-fixture systemd.volatile=overlay")
            body = "\n".join(function(name) for name in ("snapshot_root_argument_matches", "snapshot_lowerdir_matches", "require_kernel_argument_once", "require_prefixed_kernel_argument_once", "verify_snapshot_runtime"))
            if "snapshot_runtime_fail() {" in VERIFY.read_text(): body = function("snapshot_runtime_fail") + "\n" + body
            body = body.replace('/boot/qa-snapshot-${run_id}.state', str(state)).replace('/proc/cmdline', str(commandline))
            script = r'''set -euo pipefail
run_id=fixture scenario=stock-gnome-btrfs-grub phase=snapshot-prelogin
fixture_lower=$1
fixture_uuid=$2
fixture_partuuid=$3
changed=$4
[(){ if [[ "$*" = '-b /dev/vda2 ]' ]]; then return 0; fi; builtin [ "$@"; }
stat(){ if [ "$changed" = state-mode ]; then printf '1000:644:1'; else printf '0:600:1'; fi; }
sha256sum(){ printf '%s fixture' bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; }
findmnt(){
    case "$*" in
        *FSTYPE*'target /') if [ "$changed" = root-type ]; then printf btrfs; else printf overlay; fi;;
        *FSTYPE*) if [ "$changed" = lower-type ]; then printf SECRET_VALUE; else printf btrfs; fi;;
        *FSROOT*) if [ "$changed" = lower-subvol ]; then printf /SECRET_PATH; else printf /@snapshots/qa-fixture; fi;;
        *OPTIONS*'target /') if [ "$changed" = root-options-query ]; then return 1; elif [ "$changed" = lower-shape ]; then printf lowerdir=SECRET_RELATIVE; else printf 'lowerdir=%s' "$fixture_lower"; fi;;
        *OPTIONS*) if [ "$changed" = lower-options-query ]; then return 1; elif [ "$changed" = lower-rw ]; then printf rw; else printf ro; fi;;
        *UUID*) if [ "$changed" = lower-uuid ]; then printf wrong; else printf '%s' "$fixture_uuid"; fi;;
    esac
}
btrfs(){ if [ "$changed" = property ]; then printf ro=false; else printf ro=true; fi; }
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
verify_grub_efi_target(){ [ "$changed" != efi ]; }
verify_grub_package_integrity(){ [ "$changed" != package ]; }
systemctl(){ if [[ "$*" = *is-active* ]]; then [ "$changed" != service ]; elif [ "$changed" = failed-units ]; then printf SECRET_UNIT; fi; }
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
                self.assertEqual(result.stderr, "SNAPSHOT_RUNTIME_DIAGNOSTIC run_id=unavailable phase=snapshot-prelogin reason=" + reason + "\n")
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
