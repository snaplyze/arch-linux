#!/usr/bin/env python3
"""Exercise generated release commits without publishing or executing product code."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "repository/release-source.py"


class ReleaseSourceChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(HELPER.is_file(), "release source preparation helper is missing")
        spec = importlib.util.spec_from_file_location("release_source", HELPER)
        assert spec is not None and spec.loader is not None
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temporary = tempfile.TemporaryDirectory(prefix="release-source-check-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "source"
        self.root.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        files = {
            "arch-linux-installer.sh": "#!/bin/bash\nreadonly VERSION='1.0.2'\nprintf 'product behavior\\n'\n",
            "install.sh": "#!/bin/bash\nreadonly BOOTSTRAP_VERSION='1.0.2'\nreadonly BOOTSTRAP_RELEASE_URL='https://github.com/snaplyze/arch-linux/releases/download/1.0.2'\nbootstrap_fail 'release 1.0.2 supports Linux x86_64 only'\nbootstrap_fail 'installer version does not match immutable release 1.0.2'\n",
            "repository/package-set": "arch-linux-keyring\n",
            "packages/arch-linux-keyring/PKGBUILD": "pkgname=arch-linux-keyring\npkgver=1.0.0\npkgrel=2\nsha256sums=('unchanged')\n",
            "packages/arch-linux-keyring/.SRCINFO": "pkgbase = arch-linux-keyring\n\tpkgver = 1.0.0\n\tpkgrel = 2\n\tsha256sums = unchanged\n",
            "repository/trust/primary-fingerprint": "A" * 40 + "\n",
            "repository/release-source.py": HELPER.read_text(),
        }
        for name, contents in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
            path.chmod(0o755 if name.endswith(".sh") else 0o644)
        self.git("add", ".")
        self.git("commit", "-m", "reviewed main")
        self.main = self.git("rev-parse", "HEAD")

    def git(self, *args: str, input_data: bytes | None = None) -> str:
        return subprocess.check_output(["git", "-C", str(self.root), *args], input=input_data,
                                       stderr=subprocess.DEVNULL).decode().strip()

    def prepare(self, version: str = "1.0.2") -> dict[str, str]:
        return self.module.prepare(self.root, self.main, version, Path(self.temporary.name) / version)

    def test_child_is_deterministic_and_main_is_unchanged(self) -> None:
        first = self.prepare()
        second = self.module.prepare(self.root, self.main, "1.0.2", Path(self.temporary.name) / "retry")
        self.assertEqual(first, second)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.main)
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertEqual(self.git("show", "-s", "--format=%P", first["source_commit"]), self.main)
        self.assertEqual(self.git("show", f"{first['source_commit']}:arch-linux-installer.sh"),
                         "#!/bin/bash\nreadonly VERSION='1.0.2'\nprintf 'product behavior\\n'")
        self.assertIn("pkgrel=3", self.git("show", f"{first['source_commit']}:packages/arch-linux-keyring/PKGBUILD"))
        self.module.verify(self.root, first["source_commit"], self.main, "1.0.2")
        self.git("bundle", "verify", str(Path(self.temporary.name) / "1.0.2/source.bundle"))

    def test_historical_versions_and_non_semver_are_rejected(self) -> None:
        for version in ("1.0.0", "1.0.1", "01.0.2", "1.0.2;false", "main", "../1.0.2"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                self.prepare(version)

    def test_next_patch_updates_bootstrap_and_advances_package_revision(self) -> None:
        identity = self.prepare("1.0.3")
        bootstrap = self.module.blob(self.root, identity["source_commit"], "install.sh")
        self.assertIn(b"releases/download/1.0.3'", bootstrap)
        self.assertNotIn(b"1.0.2", bootstrap)
        self.assertIn("pkgrel=4", self.git("show", f"{identity['source_commit']}:packages/arch-linux-keyring/PKGBUILD"))

    def test_modified_bytes_modes_or_origin_are_rejected(self) -> None:
        identity = self.prepare()
        release = identity["source_commit"]
        for name, mode, payload in (
            ("arch-linux-installer.sh", "100755", b"#!/bin/bash\nreadonly VERSION='1.0.2'\nfalse\n"),
            ("repository/trust/primary-fingerprint", "100644", b"B" * 40 + b"\n"),
            ("install.sh", "100644", self.module.blob(self.root, release, "install.sh")),
            ("repository/release-origin.json", "100644", b'{"mainCommit":"forged"}\n'),
        ):
            with self.subTest(name=name):
                tree = self.module.replace_tree(self.root, release, {name: (mode, payload)})
                forged = self.git("commit-tree", tree, "-p", self.main, input_data=b"forged\n")
                with self.assertRaises(ValueError):
                    self.module.verify(self.root, forged, self.main, "1.0.2")

    def test_origin_binds_reviewed_parent_and_transform(self) -> None:
        identity = self.prepare()
        origin = json.loads(self.module.blob(self.root, identity["source_commit"], "repository/release-origin.json"))
        self.assertEqual(origin["mainCommit"], self.main)
        self.assertEqual(origin["mainTree"], self.git("rev-parse", f"{self.main}^{{tree}}"))
        self.assertEqual(origin["releaseVersion"], "1.0.2")
        self.assertEqual(origin["packageRevisions"], {"arch-linux-keyring": 3})
        self.assertEqual(origin["schema"], 1)
        with self.assertRaises(ValueError):
            self.module.verify(self.root, identity["source_commit"], "0" * 40, "1.0.2")

    def test_arbitrary_commit_metadata_cannot_relabel_the_same_tree(self) -> None:
        identity = self.prepare()
        forged = self.git("commit-tree", identity["source_tree"], "-p", self.main, input_data=b"different commit metadata\n")
        with self.assertRaises(ValueError):
            self.module.verify(self.root, forged, self.main, "1.0.2")

    def test_bundle_restoration_verifies_transport_before_checkout(self) -> None:
        identity = self.prepare()
        with self.assertRaises(ValueError):
            self.module.restore(self.root, self.main, identity["source_commit"], "1.0.2",
                                Path(self.temporary.name) / "1.0.2", "0" * 64)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.main)
        restored = self.module.restore(self.root, self.main, identity["source_commit"], "1.0.2",
                                       Path(self.temporary.name) / "1.0.2", identity["bundle_sha256"])
        self.assertEqual(restored, identity)
        self.assertEqual(self.git("rev-parse", "HEAD"), identity["source_commit"])

    def test_reviewed_version_floor_reset_cannot_lower_existing_package_revisions(self) -> None:
        previous = self.prepare("1.0.3")
        self.git("tag", "1.0.3", previous["source_commit"])
        for path in ("arch-linux-installer.sh", "install.sh"):
            file = self.root / path
            file.write_text(file.read_text().replace("1.0.2", "1.0.4"))
        self.git("add", ".")
        self.git("commit", "-m", "reviewed version floor change without package bump")
        self.main = self.git("rev-parse", "HEAD")
        with self.assertRaisesRegex(ValueError, "package revision would not advance"):
            self.prepare("1.0.4")


if __name__ == "__main__":
    unittest.main()
