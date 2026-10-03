#!/usr/bin/env python3
"""Exercise generated release commits without publishing or executing product code."""

from __future__ import annotations

import importlib.util
import hashlib
import io
import json
from pathlib import Path
from unittest.mock import patch
import subprocess
import sys
import tempfile
import tarfile
import textwrap
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

    def test_revision_updates_versioned_legacy_package_provides(self) -> None:
        pkg = self.root / "packages/arch-linux-keyring/PKGBUILD"
        pkg.write_text(pkg.read_text() + 'provides=("legacy-keyring=${pkgver}-${pkgrel}")\n')
        info = self.root / "packages/arch-linux-keyring/.SRCINFO"
        info.write_text(info.read_text() + '\tprovides = legacy-keyring=1.0.0-2\n')
        self.git("add", ".")
        self.git("commit", "-m", "review versioned migration")
        self.main = self.git("rev-parse", "HEAD")
        identity = self.prepare("1.0.3")
        generated = self.git("show", f"{identity['source_commit']}:packages/arch-linux-keyring/.SRCINFO")
        self.assertIn("provides = legacy-keyring=1.0.0-4", generated)
        self.assertNotIn("provides = legacy-keyring=1.0.0-2", generated)

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


class PackageSourceChecks(ReleaseSourceChecks):
    def baseline(self, with_snapshot=True):
        # Frozen primary inputs; six-package closure, as in the actual repository.
        names = ["arch-linux-keyring"] + [f"arch-linux-fixture-{i}" for i in range(5)]
        for name in names[1:]:
            folder = self.root / "packages" / name
            folder.mkdir()
            (folder / "PKGBUILD").write_text(f"pkgname={name}\npkgver=1.0.0\npkgrel=2\narch=('any')\n")
            (folder / ".SRCINFO").write_text(f"pkgbase = {name}\n\tpkgver = 1.0.0\n\tpkgrel = 2\n\tarch = any\npkgname = {name}\n")
        keyring_build = self.root / "packages/arch-linux-keyring/PKGBUILD"
        keyring_build.write_text(keyring_build.read_text() + "arch=('any')\n")
        info = self.root / "packages/arch-linux-keyring/.SRCINFO"
        info.write_text(info.read_text() + "\tarch = any\npkgname = arch-linux-keyring\n")
        (self.root / "repository/package-set").write_text("\n".join(names) + "\n")
        self.git("add", "."); self.git("commit", "-m", "six packages")
        self.main = self.git("rev-parse", "HEAD")
        released = self.prepare("1.0.5")
        release = released["source_commit"]
        self.git("tag", "-a", "1.0.5", release, "-m", "published release")
        self.directory = Path(self.temporary.name) / "published"
        self.directory.mkdir()
        assets = []
        import hashlib
        for index, name in enumerate(("arch-linux-installer.sh", "install.sh"), 1):
            raw = self.module.blob(self.root, release, name)
            (self.directory / name).write_bytes(raw)
            assets.append({"id": index, "name": name, "size": len(raw), "digest": "sha256:" + hashlib.sha256(raw).hexdigest(), "state": "uploaded"})
        api = {"id": 123, "tag_name": "1.0.5", "draft": False, "prerelease": False, "immutable": True, "assets": assets}
        (self.directory / "release-api.json").write_text(json.dumps(api))
        manifest = {"schema": 2, "releaseVersion": "1.0.5", "sourceCommit": release, "sourceTree": released["source_tree"],
                    "installerSha256": hashlib.sha256((self.directory / "arch-linux-installer.sh").read_bytes()).hexdigest(),
                    "packageSetSha256": hashlib.sha256((self.root / "repository/package-set").read_bytes()).hexdigest(),
                    "files": [{"name": f"{name}-1.0.0-6-any.pkg.tar.zst", "sha256": "a" * 64, "size": 1} for name in names]}
        manifest.update(repository='arch-linux', architecture='x86_64', sourceDateEpoch=1,
                        buildMetadataSha256='b' * 64, unsignedManifestSha256='c' * 64)
        raw = json.dumps(manifest).encode()
        (self.directory / "repository-manifest.json").write_bytes(raw)
        self.intent = {"schema": 1, "kind": "packages", "packageTag": "packages-20261003.1", "published": {
            "releaseVersion": "1.0.5", "releaseId": 123, "sourceCommit": release, "sourceTree": released["source_tree"],
            "installerAssetId": 1, "bootstrapAssetId": 2, "repositoryManifestSha256": hashlib.sha256(raw).hexdigest()}}
        (self.root / "repository/delivery-intent.json").write_text(json.dumps(self.intent))
        for name in names:
            pkg = self.root / "packages" / name / "PKGBUILD"
            pkg.write_text(pkg.read_text().replace("pkgrel=2", "pkgrel=7"))
            info = self.root / "packages" / name / ".SRCINFO"
            info.write_text(info.read_text().replace("pkgrel = 2", "pkgrel = 7"))
        self.commit_candidate()
        if with_snapshot:
            self.freeze_snapshot()
        return self.directory

    def freeze_snapshot(self, tag='1.0.5', archive_manifest=None):
        name = 'arch-linux-repository-1.0.5.tar.zst'
        raw = (self.directory / 'repository-manifest.json').read_bytes()
        contents = raw if archive_manifest is None else archive_manifest
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode='w', format=tarfile.USTAR_FORMAT) as archive:
            for directory in ('repo', 'repo/x86_64'):
                member = tarfile.TarInfo(directory)
                member.type, member.mode = tarfile.DIRTYPE, 0o755
                archive.addfile(member)
            for filename, content in [('repository-manifest.json', contents),
                                      ('repository-manifest.json.sig', b'public fixture signature')]:
                member = tarfile.TarInfo('repo/x86_64/' + filename)
                member.mode, member.size = 0o644, len(content)
                archive.addfile(member, io.BytesIO(content))
        compressed = subprocess.check_output(['zstd', '--quiet', '--stdout'], input=stream.getvalue())
        (self.directory / name).write_bytes(compressed)
        digest = hashlib.sha256(compressed).hexdigest()
        api = {'id': 321, 'tag_name': tag, 'draft': False, 'prerelease': False,
               'immutable': True, 'assets': [{'id': 3, 'name': name, 'state': 'uploaded',
                                             'size': len(compressed), 'digest': 'sha256:' + digest}]}
        (self.directory / 'baseline-release-api.json').write_text(json.dumps(api))
        self.intent['published']['repositorySnapshotSha256'] = digest
        (self.root / 'repository/delivery-intent.json').write_text(json.dumps(self.intent))
        self.commit_candidate()
        return name

    def test_active_snapshot_is_independently_bound_in_package_origin(self):
        self.baseline()
        result = self.package_prepare()
        origin = json.loads(self.module.blob(self.root, result['source_commit'], 'repository/package-origin.json'))
        self.assertEqual(origin['baselineRepositorySnapshotSha256'],
                         self.intent['published']['repositorySnapshotSha256'])
        self.assertEqual(origin['baselineTag'], '1.0.5')

    def test_missing_active_snapshot_binding_is_refused(self):
        self.baseline(with_snapshot=False)
        with self.assertRaises(ValueError):
            self.package_prepare()

    def test_active_snapshot_identity_hash_metadata_and_manifest_negatives(self):
        for case in ('wrong-hash', 'wrong-tag', 'draft', 'prerelease', 'mutable', 'wrong-size',
                     'wrong-digest', 'not-uploaded', 'duplicate-asset', 'wrong-source', 'manifest-mismatch', 'oversize'):
            with self.subTest(case=case):
                self.setUp(); self.baseline()
                name = 'arch-linux-repository-1.0.5.tar.zst'
                path = self.directory / 'baseline-release-api.json'
                api = json.loads(path.read_bytes())
                if case == 'wrong-hash':
                    self.intent['published']['repositorySnapshotSha256'] = '0' * 64
                elif case == 'wrong-tag': api['tag_name'] = 'packages-20261001.1'
                elif case == 'draft': api['draft'] = True
                elif case == 'prerelease': api['prerelease'] = True
                elif case == 'mutable': api['immutable'] = False
                elif case == 'wrong-size': api['assets'][0]['size'] += 1
                elif case == 'wrong-digest': api['assets'][0]['digest'] = 'sha256:' + '0' * 64
                elif case == 'not-uploaded': api['assets'][0]['state'] = 'new'
                elif case == 'duplicate-asset': api['assets'].append(dict(api['assets'][0]))
                elif case == 'manifest-mismatch':
                    self.freeze_snapshot(archive_manifest=b'{}\n')
                    api = json.loads(path.read_bytes())
                elif case == 'wrong-source':
                    manifest = json.loads((self.directory / 'repository-manifest.json').read_bytes())
                    manifest['sourceCommit'] = self.main
                    manifest['sourceTree'] = self.git('rev-parse', 'HEAD^{tree}')
                    raw = json.dumps(manifest).encode()
                    (self.directory / 'repository-manifest.json').write_bytes(raw)
                    self.intent['published']['repositoryManifestSha256'] = hashlib.sha256(raw).hexdigest()
                    self.freeze_snapshot()
                    api = json.loads(path.read_bytes())
                elif case == 'oversize': api['assets'][0]['size'] = 128 * 1024 * 1024 + 1
                path.write_text(json.dumps(api))
                (self.root / 'repository/delivery-intent.json').write_text(json.dumps(self.intent))
                if self.git('status', '--porcelain'):
                    self.commit_candidate()
                with self.assertRaises(ValueError): self.package_prepare()

    def test_active_package_snapshot_uses_its_package_tag_not_installer_tag(self):
        self.baseline()
        previous = self.package_prepare()
        previous_tag = self.intent['packageTag']
        self.git('tag', '-a', previous_tag, previous['source_commit'], '-m', 'published package snapshot')
        manifest_file = self.directory / 'repository-manifest.json'
        manifest = json.loads(manifest_file.read_bytes())
        manifest['sourceCommit'], manifest['sourceTree'] = previous['source_commit'], previous['source_tree']
        for row in manifest['files']:
            row['name'] = row['name'].replace('-6-any.pkg.tar.zst', '-7-any.pkg.tar.zst')
        raw = json.dumps(manifest).encode()
        manifest_file.write_bytes(raw)
        self.intent['published']['repositoryManifestSha256'] = hashlib.sha256(raw).hexdigest()
        self.intent['packageTag'] = 'packages-20261004.1'
        for package in (self.root / 'packages').iterdir():
            for name, before, after in (('PKGBUILD', 'pkgrel=7', 'pkgrel=8'),
                                        ('.SRCINFO', 'pkgrel = 7', 'pkgrel = 8')):
                file = package / name
                file.write_text(file.read_text().replace(before, after))
        self.freeze_snapshot(tag=previous_tag)
        result = self.module.prepare_packages(self.root, self.main, self.intent['packageTag'], self.directory,
                                             Path(self.temporary.name) / 'next-package-output')
        origin = json.loads(self.module.blob(self.root, result['source_commit'], 'repository/package-origin.json'))
        self.assertEqual(origin['baselineTag'], previous_tag)
        self.assertEqual(origin['baselineCommit'], previous['source_commit'])
        # Execute the actual Pages baseline-fetch fragment. Network adapters check the requested
        # immutable package tag; Git/tag resolution, jq checks and frozen outputs are real.
        workflow = (ROOT / '.github/workflows/pages.yml').read_text()
        fragment = workflow.split('            # The active repository may come from', 1)[1]
        fragment = '# The active repository may come from' + fragment.split(
            '            python3 repository/release-source.py verify-packages', 1)[0]
        fragment = textwrap.dedent('            ' + fragment)
        archive = self.directory / 'arch-linux-repository-1.0.5.tar.zst'
        original_archive = Path(self.temporary.name) / 'frozen-input.tar.zst'
        original_archive.write_bytes(archive.read_bytes())
        program = r'''
set -euo pipefail
published="$1"
original_archive="$2"
baseline_api="$(cat "$published/baseline-release-api.json")"
intent="$(cat "$3")"
baseline_tag_expected="$4"
RELEASE_VERSION=1.0.5
GITHUB_REPOSITORY=snaplyze/arch-linux
timeout() { shift 3; "$@"; }
gh() {
    if [ "$*" = "api /repos/snaplyze/arch-linux/releases/tags/$baseline_tag_expected" ]; then
        printf '%s\n' "$baseline_api"
    elif [ "$*" = "api -H Accept: application/octet-stream /repos/snaplyze/arch-linux/releases/assets/$(jq -r '.assets[0].id' <<<"$baseline_api")" ]; then
        cat "$original_archive"
    else
        return 99
    fi
}
''' + fragment
        fetch = subprocess.run(['bash', '-c', program, 'pages-baseline-fixture', str(self.directory),
                                str(original_archive), str(self.root / 'repository/delivery-intent.json'),
                                previous_tag], cwd=self.root, capture_output=True, text=True, timeout=10)
        self.assertEqual(fetch.returncode, 0, fetch.stderr)
        self.assertEqual(archive.read_bytes(), original_archive.read_bytes())
        path = self.directory / 'baseline-release-api.json'
        api = json.loads(path.read_bytes()); api['tag_name'] = '1.0.5'
        path.write_text(json.dumps(api))
        with self.assertRaisesRegex(ValueError, 'baseline release identity'):
            self.module.verify_packages(self.root, result['source_commit'], self.main,
                                        self.intent['packageTag'], self.directory)

    def test_snapshot_stream_bounds_and_invalid_compression_are_rejected(self):
        for kind in ('stale-stat', 'truncated', 'uncompressed'):
            with self.subTest(kind=kind):
                self.setUp(); self.baseline()
                file = self.directory / 'arch-linux-repository-1.0.5.tar.zst'
                raw = file.read_bytes()
                if kind == 'stale-stat': raw += b'x' * 2048
                elif kind == 'truncated': raw = raw[:-4]
                else: raw = b'uncompressed archive bytes'
                file.write_bytes(raw)
                digest = hashlib.sha256(raw).hexdigest()
                api_file = self.directory / 'baseline-release-api.json'
                api = json.loads(api_file.read_bytes())
                api['assets'][0].update(size=1024 if kind == 'stale-stat' else len(raw), digest='sha256:' + digest)
                api_file.write_text(json.dumps(api))
                original_fstat = self.module.os.fstat
                def stale(descriptor):
                    import os
                    attributes = list(original_fstat(descriptor)); attributes[6] = 1
                    return os.stat_result(attributes)
                with patch.object(self.module, 'MAX_BASELINE_SNAPSHOT_BYTES', 1024), \
                        patch.object(self.module.os, 'fstat', stale if kind == 'stale-stat' else original_fstat), \
                        self.assertRaisesRegex(ValueError, 'byte limit|integrity'):
                    self.module.verify_baseline_snapshot(self.directory, '1.0.5', '1.0.5', digest,
                                                        (self.directory / 'repository-manifest.json').read_bytes())

    def commit_candidate(self):
        self.git("add", "."); self.git("commit", "-m", "reviewed package intent")
        self.main = self.git("rev-parse", "HEAD")

    def package_prepare(self):
        return self.module.prepare_packages(self.root, self.main, self.intent["packageTag"], self.directory,
                                            Path(self.temporary.name) / "package-output")

    def test_package_child_preserves_published_bytes_and_reviewed_revisions(self):
        self.baseline()
        result = self.package_prepare()
        self.assertEqual(self.git("rev-parse", "HEAD"), self.main)
        for name in ("arch-linux-installer.sh", "install.sh"):
            self.assertEqual(self.module.blob(self.root, result["source_commit"], name), (self.directory / name).read_bytes())
        self.assertIn("pkgrel=7", self.git("show", f"{result['source_commit']}:packages/arch-linux-keyring/PKGBUILD"))
        self.module.verify_packages(self.root, result["source_commit"], self.main, self.intent["packageTag"], self.directory)
        before = self.module.tree_entries(self.root, self.main)
        after = self.module.tree_entries(self.root, result["source_commit"])
        changed = {name for name in before.keys() | after.keys() if before.get(name) != after.get(name)}
        self.assertEqual(changed, {"arch-linux-installer.sh", "install.sh", "repository/package-origin.json"})

    def test_package_rejects_installer_behavior_change(self):
        self.baseline()
        file = self.root / "arch-linux-installer.sh"
        file.write_text(file.read_text() + "false\n")
        self.commit_candidate()
        with self.assertRaisesRegex(ValueError, "published installer"):
            self.package_prepare()

    def test_package_rejects_stale_baseline(self):
        self.baseline()
        file = self.directory / "repository-manifest.json"
        file.write_bytes(file.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "baseline"):
            self.package_prepare()

    def test_package_rejects_revision_or_version_or_arch_change(self):
        for before, after in (("pkgrel = 7", "pkgrel = 6"), ("pkgver = 1.0.0", "pkgver = 2.0.0"), ("arch = any", "arch = x86_64")):
            with self.subTest(after=after):
                self.setUp(); self.baseline()
                file = self.root / "packages/arch-linux-keyring/.SRCINFO"
                file.write_text(file.read_text().replace(before, after))
                pkgbuild = self.root / "packages/arch-linux-keyring/PKGBUILD"
                if not before.startswith("arch"):
                    pkgbuild.write_text(pkgbuild.read_text().replace(before.replace(" = ", "="), after.replace(" = ", "=")))
                self.commit_candidate()
                with self.assertRaises(ValueError): self.package_prepare()

    def test_package_bundle_restoration_checks_transport_and_origin(self):
        self.baseline()
        result = self.package_prepare()
        output = Path(self.temporary.name) / "package-output"
        with self.assertRaises(ValueError):
            self.module.restore_packages(self.root, self.main, result["source_commit"], self.intent["packageTag"],
                                         self.directory, output, "0" * 64)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.main)
        restored = self.module.restore_packages(self.root, self.main, result["source_commit"], self.intent["packageTag"],
                                               self.directory, output, result["bundle_sha256"])
        self.assertEqual(restored, result)
        self.assertEqual(self.git("rev-parse", "HEAD"), result["source_commit"])

    def test_package_child_forgery_cannot_change_path_mode_or_metadata(self):
        self.baseline()
        result = self.package_prepare()
        for name, mode, raw in (("repository/package-origin.json", "100644", b"{}\n"),
                                ("install.sh", "100644", (self.directory / "install.sh").read_bytes()),
                                ("packages/arch-linux-keyring/PKGBUILD", "100644", b"pkgrel=99\n")):
            with self.subTest(name=name):
                tree = self.module.replace_tree(self.root, result["source_commit"], {name: (mode, raw)})
                forged = self.git("commit-tree", tree, "-p", self.main, input_data=b"forged\n")
                with self.assertRaises(ValueError):
                    self.module.verify_packages(self.root, forged, self.main, self.intent["packageTag"], self.directory)
        with self.assertRaises(ValueError):
            self.module.verify(self.root, result["source_commit"], self.main, "1.0.5")

    def test_package_rejects_bootstrap_modes_trust_assets_and_inventory(self):
        cases = ("bootstrap", "mode", "trust", "asset", "closure", "inventory", "intent")
        for case in cases:
            with self.subTest(case=case):
                self.setUp(); self.baseline()
                if case == "bootstrap":
                    file = self.root / "install.sh"; file.write_text(file.read_text() + "false\n")
                elif case == "mode": (self.root / "install.sh").chmod(0o644)
                elif case == "trust": (self.root / "repository/trust/primary-fingerprint").write_text("B" * 40 + "\n")
                elif case == "closure": (self.root / "repository/package-set").write_text("arch-linux-keyring\n")
                elif case == "intent":
                    self.intent["packageTag"] = "invalid"
                    (self.root / "repository/delivery-intent.json").write_text(json.dumps(self.intent))
                elif case == "asset":
                    file = self.directory / "release-api.json"
                    api = json.loads(file.read_bytes()); api["assets"][0]["id"] = 999
                    file.write_text(json.dumps(api))
                elif case == "inventory":
                    import hashlib
                    file = self.directory / "repository-manifest.json"
                    manifest = json.loads(file.read_bytes()); manifest["files"].pop()
                    raw = json.dumps(manifest).encode(); file.write_bytes(raw)
                    self.intent["published"]["repositoryManifestSha256"] = hashlib.sha256(raw).hexdigest()
                    (self.root / "repository/delivery-intent.json").write_text(json.dumps(self.intent))
                    self.freeze_snapshot()
                if self.git("status", "--porcelain"):
                    self.commit_candidate()
                with self.assertRaises(ValueError): self.package_prepare()

    def test_package_release_tag_binds_exact_published_source(self):
        for case in ("missing", "lightweight", "same-installer-wrong-source"):
            with self.subTest(case=case):
                self.setUp(); self.baseline()
                release = self.intent["published"]["sourceCommit"]
                if case == "same-installer-wrong-source":
                    forged = self.git("commit-tree", self.intent["published"]["sourceTree"], input_data=b"different provenance\n")
                    self.intent["published"]["sourceCommit"] = forged
                    (self.root / "repository/delivery-intent.json").write_text(json.dumps(self.intent))
                    self.commit_candidate()
                else:
                    self.git("tag", "-d", "1.0.5")
                    if case == "lightweight": self.git("tag", "1.0.5", release)
                with self.assertRaises(ValueError): self.package_prepare()

    def test_package_baseline_installer_hash_is_semantically_bound(self):
        self.baseline()
        import hashlib
        file = self.directory / "repository-manifest.json"
        manifest = json.loads(file.read_bytes()); manifest["installerSha256"] = "0" * 64
        raw = json.dumps(manifest).encode(); file.write_bytes(raw)
        self.intent["published"]["repositoryManifestSha256"] = hashlib.sha256(raw).hexdigest()
        (self.root / "repository/delivery-intent.json").write_text(json.dumps(self.intent))
        self.freeze_snapshot()
        with self.assertRaises(ValueError): self.package_prepare()

    def test_published_input_read_is_bounded_even_if_stat_is_stale(self):
        directory = Path(self.temporary.name) / "large-input"
        directory.mkdir()
        file = directory / "release-api.json"
        file.write_bytes(b"x" * (8 * 1024 * 1024 + 1))
        original_stat = Path.stat
        original_fstat = self.module.os.fstat
        def stale_stat(path, *args, **kwargs):
            value = original_stat(path, *args, **kwargs)
            if path == file:
                import os
                fields = list(value); fields[6] = 0
                return os.stat_result(fields)
            return value
        def stale_fstat(descriptor):
            value = original_fstat(descriptor)
            import os
            fields = list(value); fields[6] = 0
            return os.stat_result(fields)
        with patch.object(Path, "stat", stale_stat), patch.object(self.module.os, "fstat", stale_fstat), self.assertRaises(ValueError):
            self.module.read_input(directory, file.name)

    def test_package_recipe_name_and_architecture_cannot_disagree_with_metadata(self):
        for before, after in (("pkgname=arch-linux-keyring", "pkgname=unrelated"), ("arch=('any')", "arch=('x86_64')")):
            with self.subTest(after=after):
                self.setUp(); self.baseline()
                file = self.root / "packages/arch-linux-keyring/PKGBUILD"
                file.write_text(file.read_text().replace(before, after)); self.commit_candidate()
                with self.assertRaises(ValueError): self.package_prepare()

    def test_delivery_intent_schema_rejects_bool_float_and_string(self):
        self.baseline()
        for kind in ("installer", "packages"):
            for schema in (True, 1.0, "1"):
                with self.subTest(kind=kind, schema=schema):
                    intent = dict(self.intent) if kind == "packages" else {"kind": "installer"}
                    intent["schema"] = schema
                    (self.root / "repository/delivery-intent.json").write_text(json.dumps(intent))
                    self.commit_candidate()
                    with self.assertRaises(ValueError): self.module.delivery_intent(self.root, self.main)

    def test_delivery_intent_rejects_duplicate_keys_at_every_depth(self):
        self.baseline()
        duplicate_inputs = (
            '{"schema":1,"kind":"packages","kind":"installer"}',
            '{"schema":2,"schema":1,"kind":"installer"}',
            json.dumps(self.intent).replace('"releaseId":', '"releaseId": 0, "releaseId":', 1),
        )
        for raw in duplicate_inputs:
            with self.subTest(raw=raw):
                (self.root / "repository/delivery-intent.json").write_text(raw)
                self.commit_candidate()
                with self.assertRaisesRegex(ValueError, "duplicate"):
                    self.module.delivery_intent(self.root, self.main)

    def test_package_intent_suppresses_installer_preparation(self):
        self.baseline()
        with self.assertRaisesRegex(ValueError, "intent"):
            self.prepare("1.0.6")


if __name__ == "__main__":
    unittest.main()
