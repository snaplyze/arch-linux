#!/usr/bin/env python3
"""The renamed theme must upgrade existing Marble dependency closures."""
import importlib.util
import contextlib
import io
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("metadata", ROOT / "repository/verify-package-metadata.py")
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class MigrationChecks(unittest.TestCase):
    def test_renamed_package_replaces_installed_gtk3(self):
        source = ROOT / "packages/arch-linux-colloid-gtk/.SRCINFO"
        self.assertTrue(source.is_file(), "Unified GTK package is missing")
        info = metadata.parse_srcinfo(source)
        self.assertEqual(info["replaces"], ["arch-linux-colloid-gtk3"])
        self.assertEqual(info["conflicts"], ["arch-linux-colloid-gtk3"])
        version = info["pkgver"][0] + "-" + info["pkgrel"][0]
        self.assertEqual(info["provides"], ["arch-linux-colloid-gtk3=" + version])
        self.assertGreater(int(subprocess.check_output(["vercmp", version, "20260808-4"], text=True)), 0)
        profile = metadata.parse_srcinfo(ROOT / "packages/arch-linux-marble-profile/.SRCINFO")
        self.assertIn("arch-linux-colloid-gtk>=20260808-5", profile["depends"])
        self.assertFalse(any(dep.startswith("arch-linux-colloid-gtk3") for dep in profile["depends"]))

    def test_closed_package_set_retains_six_packages(self):
        names = (ROOT / "repository/package-set").read_text().splitlines()
        self.assertEqual(len(names), 6)
        self.assertIn("arch-linux-colloid-gtk", names)
        self.assertNotIn("arch-linux-colloid-gtk3", names)

    def test_payload_verifier_rejects_missing_migration_relations(self):
        name = "arch-linux-colloid-gtk"
        info = metadata.parse_srcinfo(ROOT / "packages" / name / ".SRCINFO")
        lines = [f"pkgname = {name}", f"pkgver = {metadata.expected_pkgver(name)}", "arch = any"]
        lines += [f"license = {v}" for v in info["license"]]
        lines += [f"depend = {v}" for v in info["depends"]]
        relations = [f"{'conflict' if field == 'conflicts' else field} = {value}" for field in ("provides", "conflicts", "replaces")
                     for value in info[field]]
        metadata.verify_pkginfo(name, ("\n".join(lines + relations) + "\n").encode())
        for missing in relations:
            with self.subTest(missing=missing), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    metadata.verify_pkginfo(name, ("\n".join(lines + [r for r in relations if r != missing]) + "\n").encode())


if __name__ == "__main__":
    unittest.main()
