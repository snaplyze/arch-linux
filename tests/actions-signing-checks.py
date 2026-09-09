#!/usr/bin/env python3
"""Disposable-key checks for the Actions secret broker and import boundary."""

from __future__ import annotations

import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
ADAPTER = ROOT / "repository/actions-sign-release.py"


class AdapterChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not ADAPTER.is_file():
            raise AssertionError("the Actions signing adapter is missing")
        spec = importlib.util.spec_from_file_location("actions_signing", ADAPTER)
        assert spec is not None and spec.loader is not None
        cls.adapter = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.adapter
        spec.loader.exec_module(cls.adapter)

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
