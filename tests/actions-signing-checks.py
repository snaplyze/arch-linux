#!/usr/bin/env python3
"""Disposable-key checks for the Actions secret broker and import boundary."""

from __future__ import annotations

import ast
import gzip
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import re
import runpy
import shlex
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
ADAPTER = ROOT / "repository/actions-sign-release.py"
NAMESPACES = ROOT / "repository/prepare-actions-namespaces.sh"


class AdapterChecks(unittest.TestCase):
    def test_publication_fixture_consumes_actual_sealer_required_closure(self) -> None:
        source = (ROOT / "tests/publication-root-check.sh").read_text()
        fragment = 'fixture_source="$work/fixture-source"\n' + source.split(
            'fixture_source="$work/fixture-source"\n', 1)[1].split(
            'PYTHONDONTWRITEBYTECODE=1 PACKAGE_FIXTURE_OUTPUT_DIR=', 1)[0]
        # Exercise the fixture's actual installers and verifier wrapper, without host-root
        # ownership changes. Everything written is inside this disposable test fixture.
        fragment = fragment.replace("/usr/bin/install", "fixture_install")
        setup = r'''set -euo pipefail
work=$1
repo_root=$2
fixture_public="$repo_root/repository/trust/arch-linux.gpg"
primary="$(cat "$repo_root/repository/trust/primary-fingerprint")"
signing="$(cat "$repo_root/repository/trust/signing-subkey-fingerprint")"
fixture_install() {
    local args=()
    while [ "$#" -gt 0 ]; do
        case "$1" in -o|-g) shift 2 ;; *) args+=("$1"); shift ;; esac
    done
    /usr/bin/install "${args[@]}"
}
'''
        with tempfile.TemporaryDirectory(prefix="publication-source-closure-") as temporary:
            completed = subprocess.run(["bash", "-c", setup + fragment,
                                        "publication-closure-fixture", temporary, str(ROOT)],
                                       capture_output=True, timeout=10, check=False)
            self.assertEqual(completed.returncode, 0, completed.stderr.decode())
            fixture = Path(temporary) / "fixture-source"
            files = {str(path.relative_to(fixture)) for path in fixture.rglob("*") if path.is_file()}
            sealer = ROOT / "repository/seal-offline-signing-code.py"
            tree = ast.parse(sealer.read_text(), filename=str(sealer))
            # Run the production gate itself against the assembled fixture inventory.
            # Do not mirror its required paths in this regression.
            assignment = next(node for node in ast.walk(tree) if isinstance(node, ast.Assign)
                              and any(isinstance(target, ast.Name) and target.id == "required"
                                      for target in node.targets))
            gate = next(node for node in ast.walk(tree) if isinstance(node, ast.If)
                        and node.lineno > assignment.end_lineno
                        and "required.issubset(files)" in ast.unparse(node.test))
            code = compile(ast.Module(body=[assignment, gate], type_ignores=[]), str(sealer), "exec")
            exec(code, {"files": files, "fail": self.fail})
            verifier = fixture / "repository/verify-database-metadata.py"
            self.assertEqual(verifier.read_bytes(), (ROOT / "repository/verify-database-metadata.py").read_bytes())
            self.assertEqual(verifier.stat().st_mode & 0o777, 0o755)
            canonical = ROOT / "repository/verify-package-metadata.py"
            actual_lstat = Path.lstat
            def mapped_owner(path, *args, **kwargs):
                info = actual_lstat(path, *args, **kwargs)
                if path == canonical:
                    attributes = list(info)
                    attributes[4] = attributes[5] = 0
                    return os.stat_result(attributes)
                return info
            with mock.patch.object(Path, "lstat", mapped_owner), \
                    mock.patch("os.execv", side_effect=AssertionError("import attempted CLI execv")):
                database = runpy.run_path(str(verifier))
            metadata = database["metadata"]
            self.assertEqual(metadata.ROOT, ROOT)
            self.assertTrue(callable(metadata.run_zstd_bounded))
            stream = io.BytesIO()
            with tarfile.open(fileobj=stream, mode="w") as archive:
                directory = tarfile.TarInfo("fixture-1-1")
                directory.type = tarfile.DIRTYPE
                archive.addfile(directory)
                content = b"%NAME%\nfixture\n\n"
                member = tarfile.TarInfo("fixture-1-1/desc")
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
            archive_path = Path(temporary) / "fixture.db.tar.gz"
            archive_path.write_bytes(gzip.compress(stream.getvalue()))
            self.assertEqual(database["database_records"](archive_path, 1, False),
                             {"fixture-1-1": {"desc": content}})
            wrapper = fixture / "repository/verify-package-metadata.py"
            rejected_hash = mock.Mock()
            rejected_hash.hexdigest.return_value = "0" * 64
            with mock.patch.object(Path, "lstat", mapped_owner), \
                    mock.patch.object(hashlib, "sha256", return_value=rejected_hash), \
                    self.assertRaisesRegex(SystemExit, "fixture verifier hash differs"):
                runpy.run_path(str(wrapper))
            def foreign_owner(path, *args, **kwargs):
                info = mapped_owner(path, *args, **kwargs)
                if path == canonical:
                    attributes = list(info)
                    attributes[4] = attributes[5] = 1
                    return os.stat_result(attributes)
                return info
            with mock.patch.object(Path, "lstat", foreign_owner), \
                    self.assertRaisesRegex(SystemExit, "fixture verifier owner"):
                runpy.run_path(str(wrapper))
            arguments = ["--verify-package", "fixture.pkg.tar.zst", "arch-linux-marble-profile"]
            with mock.patch.object(Path, "lstat", mapped_owner), \
                    mock.patch.object(sys, "argv", [str(wrapper), *arguments]), \
                    mock.patch("os.execv", side_effect=RuntimeError("CLI forwarded")) as execute, \
                    self.assertRaisesRegex(RuntimeError, "CLI forwarded"):
                runpy.run_path(str(wrapper), run_name="__main__")
            execute.assert_called_once_with("/usr/bin/python3",
                                            ["/usr/bin/python3", "-I", str(canonical), *arguments])


    def test_publication_agent_watcher_skips_processes_that_disappear_during_read(self) -> None:
        source = (ROOT / "tests/publication-root-check.sh").read_text()
        start = source.index("(\n    for attempt in {1..2000}; do")
        end = source.index(') >"$watch_result" &', start)
        watcher = source[start + 2:end]
        for vanished, next_agent in (("status", True), ("stat", True), ("status", False), ("stat", False)):
            with self.subTest(vanished=vanished, next_agent=next_agent), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                for pid in (101, 102):
                    process = root / str(pid)
                    process.mkdir()
                    (process / "comm").write_text("gpg-agent\n")
                    (process / "status").write_text("Uid:\t944\t944\t944\t944\n")
                    (process / "stat").write_text(" ".join([str(pid)] * 22) + "\n")
                if not next_agent:
                    (root / "102/comm").write_text("unrelated\n")
                body = watcher.replace("/proc/[1-9]*/status", '"$fixture_root"/[1-9]*/status')
                body = body.replace("/usr/bin/awk", "fixture_awk")
                body = body.replace("/usr/bin/kill", "fixture_kill")
                body = body.replace("/usr/bin/sleep 0.005", ":")
                setup = r'''
set -euo pipefail
fixture_root=$1
vanished=$2
signing_uid=944
supervisor_pid=999
supervisor_start=999
process_identity_is_live() { [[ "$1 $2" = '999 999' || "$1 $2" = '102 102' ]]; }
fixture_awk() {
    local path="${@: -1}"
    if [[ "$path" = "$fixture_root/101/$vanished" ]]; then
        rm -- "$path"
    fi
    /usr/bin/awk "$@"
}
fixture_kill() {
    [[ "$*" = '-KILL -- 999' ]]
    printf 'observed\n' >"$fixture_root/killed"
}
'''
                completed = subprocess.run(
                    ["bash", "-c", setup + body, "watcher-fixture", str(root), vanished],
                    capture_output=True, timeout=10, check=False)
                self.assertEqual(completed.returncode, 0 if next_agent else 1, completed.stderr.decode())
                self.assertEqual(completed.stderr, b"")
                self.assertEqual(completed.stdout, b"102 102\n" if next_agent else b"")
                self.assertEqual((root / "killed").exists(), next_agent)

    @classmethod
    def setUpClass(cls) -> None:
        if not ADAPTER.is_file():
            raise AssertionError("the Actions signing adapter is missing")
        spec = importlib.util.spec_from_file_location("actions_signing", ADAPTER)
        assert spec is not None and spec.loader is not None
        cls.adapter = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.adapter
        spec.loader.exec_module(cls.adapter)

    def test_namespace_preparation_rejects_missing_or_foreign_release_context(self) -> None:
        expected = {"CI": "true", "GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "self-hosted",
                    "GITHUB_REPOSITORY": "snaplyze/arch-linux", "GITHUB_WORKFLOW": "Release",
                    "GITHUB_JOB": "snapshot", "GITHUB_REF": "refs/heads/main"}
        cases = [{}] + [dict(expected, **{name: "foreign"}) for name in expected]
        for context in cases:
            with self.subTest(context=context):
                completed = subprocess.run(["/usr/bin/bash", str(NAMESPACES)], env=context,
                                           capture_output=True, timeout=10, check=False)
                self.assertEqual(completed.returncode, 1)
                self.assertIn(b"namespace preparation requires the self-hosted Release signing job", completed.stderr)
                self.assertNotIn(b"ACTIONS_NAMESPACES_RESULT", completed.stdout)

    def test_namespace_preparation_rejects_secret_presence_without_echoing_bytes(self) -> None:
        sentinel = os.urandom(24).hex()
        for name in ("ARCH_LINUX_SIGNING_KEY", "ARCH_LINUX_SIGNING_PASSPHRASE"):
            for value in ("", sentinel):
                with self.subTest(name=name, present=bool(value)):
                    completed = subprocess.run(["/usr/bin/bash", str(NAMESPACES)], env={name: value},
                                               capture_output=True, timeout=10, check=False)
                    self.assertEqual(completed.returncode, 1)
                    self.assertIn(b"namespace preparation refuses signing secret environment", completed.stderr)
                    self.assertNotIn(sentinel.encode(), completed.stdout + completed.stderr)

    def test_each_signing_job_prepares_namespaces_before_sealing_and_secret_access(self) -> None:
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        invocation = "run: bash repository/prepare-actions-namespaces.sh"
        self.assertEqual(workflow.count(invocation), 2)
        for job in ("snapshot", "finalize"):
            with self.subTest(job=job):
                blocks = re.findall(rf"(?ms)^  {job}:\n(.*?)(?=^  [a-z_]+:\n|\Z)", workflow)
                self.assertEqual(len(blocks), 1)
                block = blocks[0]
                self.assertEqual(block.count(invocation), 1)
                order = [block.index(marker) for marker in (
                    "python3 repository/release-source.py restore", invocation,
                    "/usr/bin/python3 -I /opt/arch-linux-canonical/repository/actions-sign-release.py prepare",
                    "ARCH_LINUX_SIGNING_KEY: ${{ secrets.ARCH_LINUX_SIGNING_KEY }}")]
                self.assertEqual(order, sorted(order))

    def test_namespace_probe_fails_closed_without_host_policy_mutation(self) -> None:
        source = NAMESPACES.read_text()
        marker = "# The shared runner administrator"
        self.assertEqual(source.count(marker), 1)
        block = source[source.index(marker):]
        self.assertNotIn("/proc/sys", source)
        self.assertNotRegex(source, r"(?m)^\s*(?:/[^ ]*/)?sysctl\s")
        cases = [("return 0", 0), ("return 1", 1), ("exit 37", 37)]
        cases.extend((f'kill -{name} "$$"', -number)
                     for name, number in (("HUP", 1), ("INT", 2), ("TERM", 15)))
        for probe, status in cases:
            with self.subTest(probe=probe):
                script = ('set -euo pipefail\n'
                          'fail() { printf "ERROR: %s\\n" "$1" >&2; exit 1; }\n'
                          f'probe() {{ {probe}; }}\n' + block)
                completed = subprocess.run(["/usr/bin/bash", "-c", script],
                                           env={"PATH": "/usr/bin:/bin"},
                                           capture_output=True, timeout=10, check=False)
                self.assertEqual(completed.returncode, status)
                if status == 0:
                    self.assertIn(b"ACTIONS_NAMESPACES_RESULT state=unchanged", completed.stdout)
                else:
                    self.assertNotIn(b"ACTIONS_NAMESPACES_RESULT", completed.stdout)
                if probe == "return 1":
                    self.assertIn(b"configure the arch-linux-ci Docker AppArmor profile", completed.stderr)
                    self.assertIn(b"host-global sysctl changes are forbidden", completed.stderr)

    def test_secret_protocol_is_bounded_and_exact(self) -> None:
        adapter = self.adapter
        key = b"fixture-transfer"
        fixture_phrase = os.urandom(24).hex().encode()
        request = adapter.encode_request(key, fixture_phrase)
        self.assertEqual(adapter.read_request(io.BytesIO(request)), (key, fixture_phrase))
        for malformed in (b"", request[:-1], request + b"x", b"wrong" + request,
                          request[:8] + b"\xff" * 8):
            with self.subTest(size=len(malformed)), self.assertRaises(adapter.SigningError):
                adapter.read_request(io.BytesIO(malformed))
        for bad_passphrase in (b"", b"line\nbreak", b"carriage\rreturn", b"nul\x00byte",
                               b"x" * 4097):
            with self.subTest(size=len(bad_passphrase)), self.assertRaises(adapter.SigningError):
                adapter.encode_request(key, bad_passphrase)

    def test_broker_pipe_lifetime_and_clean_interpreter_exit(self) -> None:
        program = (
            "import importlib.util,sys,threading,time;sys.dont_write_bytecode=True;"
            "s=importlib.util.spec_from_file_location('adapter',sys.argv[1]);"
            "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
            "threading.Thread(target=m.watch_broker,daemon=True).start();"
            "print('READY',flush=True);"
            "time.sleep(30) if sys.argv[2]=='wait' else None"
        )
        for mode in ("normal", "eof", "trailing"):
            process = subprocess.Popen([sys.executable, "-I", "-c", program, str(ADAPTER),
                                        "normal" if mode == "normal" else "wait"],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                self.assertEqual(process.stdout.readline(), b"READY\n")
                if mode == "eof":
                    process.stdin.close()
                elif mode == "trailing":
                    process.stdin.write(b"x")
                    process.stdin.flush()
                self.assertEqual(process.wait(timeout=5), 0 if mode == "normal" else 1)
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait()
                process.stdin.close()
                process.stdout.close()
                process.stderr.close()

    def test_unsealed_direct_entry_rejects_before_secret_read(self) -> None:
        args = [sys.executable, "-I", str(ADAPTER), "snapshot", "--source-commit", "0" * 40,
                "--source-tree", "1" * 40, "--source-tree-sha256", "2" * 64,
                "--unsigned", "/nonexistent/unsigned", "--installer", str(ROOT / "arch-linux-installer.sh"),
                "--output", "/nonexistent/output/result", "--release-version", "1.0.0",
                "--build-metadata-sha256", "3" * 64, "--unsigned-manifest-sha256", "4" * 64]
        sentinel = os.urandom(24).hex()
        environment = dict(os.environ, CI="true", GITHUB_ACTIONS="true",
                           ARCH_LINUX_SIGNING_KEY=sentinel, ARCH_LINUX_SIGNING_PASSPHRASE=sentinel)
        completed = subprocess.run(args, env=environment, capture_output=True, timeout=10, check=False)
        self.assertEqual(completed.returncode, 1)
        self.assertIn(b"ERROR: Actions signing", completed.stderr)
        self.assertNotIn(sentinel.encode(), completed.stdout + completed.stderr)
        if os.getuid() != 0:
            self.assertIn(b"host root signing job is required", completed.stderr)

    def test_sealer_mutation_after_canonical_capture_is_not_retrusted(self) -> None:
        if os.getuid() != 0:
            self.skipTest("root sealer capture fixture requires root execution")
        with tempfile.TemporaryDirectory(prefix="actions-sealer-fixture-", dir="/root") as temporary:
            root = Path(temporary)
            (root / "repository").mkdir(mode=0o755)
            sealer = root / "repository/seal-offline-signing-code.py"
            sealer.write_text("raise SystemExit(0)\n")
            sealer.chmod(0o644)
            git = ["git", "-C", str(root)]
            for arguments in (("init", "-q"), ("add", "."),
                              ("-c", "user.name=Actions Fixture", "-c", "user.email=fixture@invalid",
                               "commit", "-qm", "fixture")):
                subprocess.run([*git, *arguments], check=True, capture_output=True)
            commit = subprocess.check_output([*git, "rev-parse", "HEAD"]).decode().strip()
            tree = subprocess.check_output([*git, "rev-parse", "HEAD^{tree}"]).decode().strip()
            import hashlib
            import argparse
            digest = hashlib.sha256(sealer.read_bytes()).hexdigest()
            canonical = hashlib.sha256(f"0644 {digest} *repository/seal-offline-signing-code.py\n".encode()).hexdigest()
            args = argparse.Namespace(source_commit=commit, source_tree=tree, source_tree_sha256=canonical,
                                      sealed_root=str(root / "sealed"))
            marker = root / "untrusted-sealer-executed"

            def mutate_after_capture(*, provision: bool) -> tuple[int, int]:
                self.assertTrue(provision)
                sealer.write_text(f"from pathlib import Path\nPath({str(marker)!r}).touch()\n")
                return 65534, 65534

            with mock.patch.object(self.adapter, "source_root", return_value=root), \
                    mock.patch.object(self.adapter, "signing_account", side_effect=mutate_after_capture), \
                    mock.patch.dict(os.environ, self.adapter.ROOT_ENV, clear=True):
                with self.assertRaises(self.adapter.SigningError):
                    self.adapter.prepare(args)
            self.assertFalse(marker.exists(), "a post-acceptance sealer was executed as root")

    def test_root_owned_input_inventory_rejects_links_and_writable_files(self) -> None:
        if os.getuid() != 0:
            self.skipTest("root input ownership fixture requires --root execution")
        with tempfile.TemporaryDirectory(prefix="actions-public-input-", dir="/var/tmp") as temporary:
            root = Path(temporary)
            os.chmod(root, 0o755)
            payload = root / "payload"
            payload.write_bytes(b"accepted public bytes")
            os.chmod(payload, 0o644)
            before = self.adapter.public_inventory(root)
            payload.write_bytes(b"changed public bytes")
            self.assertNotEqual(self.adapter.public_inventory(root), before)
            os.chmod(payload, 0o664)
            with self.assertRaises(self.adapter.SigningError):
                self.adapter.public_inventory(root)
            payload.unlink()
            payload.symlink_to("/etc/passwd")
            with self.assertRaises(self.adapter.SigningError):
                self.adapter.public_inventory(root)

    def test_forged_public_sealed_context_cannot_replace_code_verification(self) -> None:
        environment = {"HOME": "/nonexistent", "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin",
                       "ARCH_LINUX_PUBLIC_CODE_ROOT": str(ROOT),
                       "ARCH_LINUX_PUBLIC_ACCEPTED_COMMIT": "0" * 40,
                       "ARCH_LINUX_PUBLIC_ACCEPTED_TREE": "1" * 40,
                       "ARCH_LINUX_PUBLIC_ACCEPTED_TREE_SHA256": "2" * 64}
        completed = subprocess.run(["/usr/bin/bash", str(ROOT / "repository/verify-unsigned-build.sh"),
                                    "--sealed-public-root", "/nonexistent"], env=environment,
                                   capture_output=True, timeout=10, check=False)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn(b"sealed public verification", completed.stderr)

    def test_only_pinned_protected_signing_subkey_can_enter_import(self) -> None:
        with tempfile.TemporaryDirectory(prefix="actions-key-fixture-") as temporary:
            home = Path(temporary)
            home.chmod(0o700)
            phrase_file = home / "fixture-phrase"
            phrase_file.write_bytes(os.urandom(24).hex().encode() + b"\n")
            phrase_file.chmod(0o600)

            def gpg(*arguments: str) -> bytes:
                with phrase_file.open("rb") as phrase:
                    completed = subprocess.run(
                        ["gpg", "--homedir", str(home), "--batch", "--no-options", "--pinentry-mode", "loopback",
                         "--passphrase-fd", str(phrase.fileno()), *arguments],
                        pass_fds=(phrase.fileno(),), capture_output=True, check=False, timeout=30)
                self.assertEqual(completed.returncode, 0, "disposable GPG fixture command failed")
                return completed.stdout

            try:
                gpg("--quick-generate-key", "Actions adapter fixture", "ed25519", "cert", "1d")
                primary = next(line.split(":")[9] for line in gpg("--with-colons", "--list-keys").decode().splitlines()
                               if line.startswith("fpr:"))
                gpg("--quick-add-key", primary, "ed25519", "sign", "1d")
                fingerprints = [line.split(":")[9] for line in gpg("--with-colons", "--list-keys").decode().splitlines()
                                if line.startswith("fpr:")]
                signing = fingerprints[1]
                transfer = gpg("--armor", "--export-secret-subkeys", primary)
                self.adapter.assert_signing_transfer(transfer, primary, signing)
                for exported, expected_primary, expected_signing in (
                    (gpg("--armor", "--export-secret-keys", primary), primary, signing),
                    (transfer, "0" * 40, signing), (transfer, primary, "0" * 40),
                    (transfer + transfer, primary, signing), (transfer[:-25], primary, signing),
                ):
                    with self.assertRaises(self.adapter.SigningError):
                        self.adapter.assert_signing_transfer(exported, expected_primary, expected_signing)
            finally:
                subprocess.run(["gpgconf", "--homedir", str(home), "--kill", "all"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


if __name__ == "__main__":
    unittest.main()
