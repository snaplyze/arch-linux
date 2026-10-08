#!/usr/bin/env python3
"""Prepare and verify the exact release-only child of a reviewed main commit."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
ORIGIN = "repository/release-origin.json"
TRANSFORMER = "repository/release-source.py"
HEX40 = re.compile(r"[a-f0-9]{40}\Z")
VERSION = re.compile(r"(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\Z")


# Only these instruction blocks are generated; acceptance and dated evidence stay outside.
BOOTSTRAP_DOCUMENTS = {
    "README.md": """The commands below pin immutable release **@RELEASE_VERSION@**. Use them from the Arch ISO only after
confirming publication and acceptance in the [release evidence](docs/validation.md):

```bash
curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/@RELEASE_VERSION@/install.sh | bash
```

For a newer version, use the release-pinned command in the
[latest published immutable GitHub Release](https://github.com/snaplyze/arch-linux/releases).
These examples pin @RELEASE_VERSION@; they do not track `main` or a moving latest-download URL.

The bootstrap is release-pinned. It downloads the installer, its SHA-256 file, detached signature
and `arch-linux.gpg`; validates the exact public-certificate digest and fingerprints; rejects secret
key packets; then launches only the verified installer bytes from a private root-owned directory.
For a verification-only run:

```bash
curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/@RELEASE_VERSION@/install.sh | bash -s -- --verify-only
```
""",
    "docs/installation.md": """Use the single release-pinned bootstrap command in the [README](../README.md). It downloads
`install.sh` from the documented immutable release tag `@RELEASE_VERSION@`. Confirm publication and
acceptance in [validation](validation.md) before using that tag. The bootstrap never downloads
from `main`; it downloads and
verifies the release installer, checksum, detached signature, public certificate and both
fingerprint files. The verified installer starts as root from an exact root-owned mode-`0700`
single-link file inside its private root-owned mode-`0700` working directory. Every ancestor is
root-owned and not writable by group or others; the user-owned download directory is removed before
the installer starts.

For a non-destructive public-release or QEMU readback, run the same immutable bootstrap in
verification-only mode:

```bash
curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/@RELEASE_VERSION@/install.sh | bash -s -- --verify-only
```
""",
}


SOURCE_RELEASE_OVERVIEW = """As of 2026-10-09, the GNOME 51 recovery changes currently in this checkout are an unpublished
candidate. They add a shared signed extension package, reviewed desktop/GDM
compatibility and safe migration of the old local extension. They are not yet
available through `pacman -Syu`; see the [current gates](docs/PLAN.md#gnome-51-update-recovery--2026-10-09).
"""
RELEASE_OVERVIEW = """This tree describes release **@RELEASE_VERSION@**. Its reviewed changes are recorded in the
[changelog](CHANGELOG.md).

Before installation or update, verify immutable publication, exact package delivery and the signed
`arch-linux-acceptance-@RELEASE_VERSION@.json` assets for
[release @RELEASE_VERSION@](https://github.com/snaplyze/arch-linux/releases/tag/@RELEASE_VERSION@).
Follow the [release verification procedure](docs/release-process.md) and
[validation records](docs/validation.md), whose results remain bound to their own release inputs.
A tagged source tree alone does not establish installed-system, GNOME/GDM or public acceptance.
"""


def git(root: Path, *args: str, data: bytes | None = None,
        extra_env: dict[str, str] | None = None) -> bytes:
    environment = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
    if extra_env:
        environment.update(extra_env)
    try:
        return subprocess.check_output(["git", "-c", f"safe.directory={root}", "-C", str(root), *args],
                                       input=data, env=environment, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as error:
        raise ValueError("release Git object operation failed") from error


def oid(root: Path, name: str) -> str:
    return git(root, "rev-parse", "--verify", name).decode().strip()


def version_parts(version: str) -> tuple[int, int, int]:
    match = VERSION.fullmatch(version)
    if match is None:
        raise ValueError("release version must be canonical SemVer with components at most 9999")
    parts = tuple(int(part) for part in match.groups())
    if parts < (1, 0, 2):
        raise ValueError("historical release names 1.0.0 and 1.0.1 are permanently retired")
    return parts


def blob(root: Path, commit: str, path: str) -> bytes:
    return git(root, "show", f"{commit}:{path}")


def tree_entries(root: Path, commit: str) -> dict[str, tuple[str, str]]:
    entries = {}
    for record in git(root, "ls-tree", "-rz", "--full-tree", commit).split(b"\0"):
        if not record:
            continue
        metadata, encoded_name = record.split(b"\t", 1)
        mode, kind, object_id = metadata.decode("ascii").split()
        name = encoded_name.decode("utf-8")
        if mode not in {"100644", "100755"} or kind != "blob" or any(ord(c) < 32 for c in name):
            raise ValueError("release source contains a non-regular object or unsafe path")
        entries[name] = mode, object_id
    return entries


def replace_tree(root: Path, base: str, changes: dict[str, tuple[str, bytes]]) -> str:
    with tempfile.TemporaryDirectory(prefix="arch-linux-release-index-") as temporary:
        environment = {"GIT_INDEX_FILE": str(Path(temporary) / "index")}
        git(root, "read-tree", base, extra_env=environment)
        for path, (mode, content) in sorted(changes.items()):
            object_id = git(root, "hash-object", "-w", "--stdin", data=content).decode().strip()
            git(root, "update-index", "--add", "--cacheinfo", mode, object_id, path, extra_env=environment)
        return git(root, "write-tree", extra_env=environment).decode().strip()


def replace_once(raw: bytes, before: bytes, after: bytes, label: str) -> bytes:
    if raw.count(before) != 1:
        raise ValueError(f"release transformation requires one exact {label}")
    return raw.replace(before, after, 1)


INTENT = "repository/delivery-intent.json"
PACKAGE_ORIGIN = "repository/package-origin.json"
PACKAGE_TAG = re.compile(r"packages-[0-9]{8}\.[1-9][0-9]{0,8}\Z")
HEX64 = re.compile(r"[a-f0-9]{64}\Z")
MAX_BASELINE_SNAPSHOT_BYTES = 128 * 1024 * 1024
MAX_BASELINE_SNAPSHOT_SECONDS = 60


def unique_json_object(pairs: list[tuple[str, object]]) -> dict:
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("delivery intent contains a duplicate JSON key")
        value[key] = item
    return value


def delivery_intent(root: Path, commit: str) -> dict:
    entries = tree_entries(root, commit)
    if INTENT not in entries:
        return {"schema": 1, "kind": "installer"}
    value = json.loads(blob(root, commit, INTENT), object_pairs_hook=unique_json_object)
    if not isinstance(value, dict) or type(value.get("schema")) is not int or value["schema"] != 1:
        raise ValueError("delivery intent schema must be integer 1")
    if value == {"schema": 1, "kind": "installer"}:
        return value
    if not isinstance(value, dict) or set(value) != {"schema", "kind", "packageTag", "published"} or value["schema"] != 1 or value["kind"] != "packages":
        raise ValueError("delivery intent is malformed")
    published = value["published"]
    expected = {"releaseVersion", "releaseId", "sourceCommit", "sourceTree", "installerAssetId", "bootstrapAssetId", "repositoryManifestSha256", "repositorySnapshotSha256"}
    if not isinstance(published, dict) or set(published) != expected or not isinstance(value["packageTag"], str) or not PACKAGE_TAG.fullmatch(value["packageTag"]):
        raise ValueError("package delivery intent is malformed")
    version_parts(published["releaseVersion"])
    for key in ("releaseId", "installerAssetId", "bootstrapAssetId"):
        if type(published[key]) is not int or published[key] <= 0:
            raise ValueError("published asset identity is malformed")
    for key in ("sourceCommit", "sourceTree", "repositoryManifestSha256", "repositorySnapshotSha256"):
        pattern = HEX64 if key.endswith("Sha256") else HEX40
        if not isinstance(published[key], str) or not pattern.fullmatch(published[key]):
            raise ValueError("published source identity is malformed")
    return value


def read_input(directory: Path, name: str) -> bytes:
    path = directory / name
    limit = 8 * 1024 * 1024
    if directory.is_symlink():
        raise ValueError("published input directory is a symlink")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        attributes = os.fstat(stream.fileno())
        if not stat.S_ISREG(attributes.st_mode) or attributes.st_size > limit:
            raise ValueError("published input is not a bounded regular file")
        raw = stream.read(limit + 1)
    if len(raw) > limit:
        raise ValueError("published input exceeds byte limit")
    return raw


def baseline_tag(root: Path, commit: str, version: str) -> str:
    tag = version
    if PACKAGE_ORIGIN in tree_entries(root, commit):
        origin = json.loads(blob(root, commit, PACKAGE_ORIGIN), object_pairs_hook=unique_json_object)
        tag = origin.get("packageTag")
        if origin.get("kind") != "packages" or not isinstance(tag, str) or not PACKAGE_TAG.fullmatch(tag):
            raise ValueError("repository baseline package origin is malformed")
    if git(root, "cat-file", "-t", f"refs/tags/{tag}").decode().strip() != "tag" or oid(root, f"refs/tags/{tag}^{{commit}}") != commit:
        raise ValueError("repository baseline requires its exact annotated source tag")
    return tag


def verify_baseline_snapshot(directory: Path, tag: str, version: str,
                             digest: str, manifest_raw: bytes) -> None:
    api = json.loads(read_input(directory, "baseline-release-api.json"), object_pairs_hook=unique_json_object)
    if (not isinstance(api, dict) or type(api.get("id")) is not int or api["id"] <= 0 or
            api.get("tag_name") != tag or api.get("draft") is not False or
            api.get("prerelease") is not False or api.get("immutable") is not True):
        raise ValueError("repository baseline release identity differs")
    name = f"arch-linux-repository-{version}.tar.zst"
    assets = api.get("assets")
    if not isinstance(assets, list) or any(not isinstance(row, dict) for row in assets):
        raise ValueError("repository baseline release assets are malformed")
    rows = [row for row in assets if row.get("name") == name]
    if len(rows) != 1:
        raise ValueError("repository baseline snapshot asset is ambiguous")
    asset = rows[0]
    if (type(asset.get("id")) is not int or asset["id"] <= 0 or
            sum(row.get("id") == asset["id"] for row in assets) != 1 or
            asset.get("state") != "uploaded" or type(asset.get("size")) is not int or
            not 0 < asset["size"] <= MAX_BASELINE_SNAPSHOT_BYTES or
            asset.get("digest") != "sha256:" + digest):
        raise ValueError("repository baseline snapshot asset identity differs")
    if directory.is_symlink():
        raise ValueError("published input directory is a symlink")
    descriptor = os.open(directory / name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    deadline = time.monotonic() + MAX_BASELINE_SNAPSHOT_SECONDS
    prior_handler = signal.getsignal(signal.SIGALRM)
    prior_timer = signal.getitimer(signal.ITIMER_REAL)
    def expired(_signum, _frame):
        raise ValueError("repository baseline snapshot time limit exceeded")
    signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, MAX_BASELINE_SNAPSHOT_SECONDS)
    try:
        with os.fdopen(descriptor, "rb") as source, tempfile.TemporaryFile() as compressed:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or not 0 < info.st_size <= MAX_BASELINE_SNAPSHOT_BYTES:
                raise ValueError("repository baseline snapshot is not a bounded regular file")
            actual = hashlib.sha256()
            size = 0
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                size += len(chunk)
                if size > MAX_BASELINE_SNAPSHOT_BYTES:
                    raise ValueError("repository baseline snapshot exceeds byte limit")
                actual.update(chunk)
                compressed.write(chunk)
            if size != asset["size"] or actual.hexdigest() != digest:
                raise ValueError("repository baseline snapshot bytes differ")
            # Reuse public TRUST-01 resource/pre-extension bounds. The private unnamed copy
            # contains exactly the accepted hash bytes, independent of source-path/inode changes.
            metadata = runpy.run_path(str(ROOT / "repository/verify-package-metadata.py"))
            compressed.flush()
            frozen = f"/proc/{os.getpid()}/fd/{compressed.fileno()}"
            # --force follows this owned FD link. Integrity testing first prohibits zstd's
            # force/stdout passthrough of an uncompressed input.
            if metadata["run_zstd_bounded"](["zstd", "--test", "--quiet", "--force", "--", frozen], deadline) != 0:
                raise ValueError("repository baseline snapshot integrity differs")
            with tempfile.TemporaryFile() as expanded:
                if metadata["run_zstd_bounded"](
                        ["zstd", "--decompress", "--quiet", "--stdout", "--force", "--", frozen], deadline, expanded) != 0:
                    raise ValueError("repository baseline snapshot decompression failed")
                expanded.seek(0)
                seen = set()
                matched = False
                with tarfile.open(fileobj=expanded, mode="r:", tarinfo=metadata["BoundedTarInfo"]) as archive:
                    for member in archive:
                        member_name = metadata["safe_member_name"](member)
                        if member_name in seen or len(seen) >= 64:
                            raise ValueError("repository baseline snapshot archive closure differs")
                        seen.add(member_name)
                        if member.isdir() and member_name in {"repo", "repo/x86_64"}:
                            continue
                        if (not member.isreg() or member.type != tarfile.REGTYPE or
                                not re.fullmatch(r"repo/x86_64/[A-Za-z0-9][A-Za-z0-9+._-]*", member_name)):
                            raise ValueError("repository baseline snapshot contains an unsafe member")
                        if member_name == "repo/x86_64/repository-manifest.json":
                            if member.size != len(manifest_raw) or metadata["read_member"](archive, member) != manifest_raw:
                                raise ValueError("repository baseline snapshot manifest bytes differ")
                            matched = True
                if not matched:
                    raise ValueError("repository baseline snapshot manifest is absent")
    except (OSError, tarfile.TarError) as error:
        raise ValueError("repository baseline snapshot inspection failed") from error
    except SystemExit as error:
        raise ValueError("repository baseline snapshot resource or archive limit exceeded") from error
    finally:
        signal.setitimer(signal.ITIMER_REAL, *prior_timer)
        signal.signal(signal.SIGALRM, prior_handler)


def package_metadata(root: Path, commit: str, package: str) -> tuple[str, str, int, str]:
    raw = blob(root, commit, f"packages/{package}/.SRCINFO").decode("ascii")
    values = []
    for key in ("epoch", "pkgver", "pkgrel", "arch"):
        matches = re.findall(rf"^\t{key} = (\S+)$", raw, re.M)
        if key == "epoch" and not matches:
            matches = ["0"]
        if len(matches) != 1:
            raise ValueError("package metadata is ambiguous")
        values.append(matches[0])
    epoch, version, revision, arch = values
    if not re.fullmatch(r"0|[1-9][0-9]{0,8}", epoch) or not re.fullmatch(r"[1-9][0-9]{0,8}", revision) or not re.fullmatch(r"[A-Za-z0-9+._]+", version) or arch not in {"any", "x86_64"}:
        raise ValueError("package metadata is malformed")
    pkgbuild = blob(root, commit, f"packages/{package}/PKGBUILD")
    if re.findall(rb"^pkgname=(\S+)$", pkgbuild, re.M) != [package.encode()] or re.findall(rb"^arch=\('([^']+)'\)$", pkgbuild, re.M) != [arch.encode()]:
        raise ValueError("PKGBUILD name or architecture differs from package metadata")
    for key in ("pkgbase", "pkgname"):
        if re.findall(rf"^{key} = (\S+)$", raw, re.M) != [package]:
            raise ValueError("SRCINFO package name differs from package closure")
    for key, value in (("pkgver", version), ("pkgrel", revision)):
        if re.findall(rb"^" + key.encode() + rb"=(\S+)$", pkgbuild, re.M) != [value.encode()]:
            raise ValueError("PKGBUILD and SRCINFO versions differ")
    epoch_values = re.findall(rb"^epoch=(\S+)$", pkgbuild, re.M)
    if epoch_values != ([] if epoch == "0" and not epoch_values else [epoch.encode()]):
        raise ValueError("PKGBUILD and SRCINFO epochs differ")
    for alias in re.findall(rb'"([a-z0-9+._-]+)=\$\{pkgver\}-\$\{pkgrel\}"', pkgbuild):
        if raw.count(f"\tprovides = {alias.decode()}={version}-{revision}\n") != 1:
            raise ValueError("version-bound provides differ")
    return epoch, version, int(revision), arch


def package_tree(root: Path, main: str, tag: str, directory: Path) -> tuple[str, str]:
    if not HEX40.fullmatch(main) or oid(root, f"{main}^{{commit}}") != main:
        raise ValueError("reviewed package commit is malformed")
    entries = tree_entries(root, main)
    if ORIGIN in entries or PACKAGE_ORIGIN in entries:
        raise ValueError("a delivery child cannot be reviewed main")
    transformer = blob(root, main, TRANSFORMER)
    if transformer != Path(__file__).read_bytes():
        raise ValueError("package transformer differs from reviewed main")
    intent = delivery_intent(root, main)
    if intent["kind"] != "packages" or intent["packageTag"] != tag:
        raise ValueError("package intent or tag differs")
    published = intent["published"]
    version = published["releaseVersion"]
    release = published["sourceCommit"]
    if git(root, "cat-file", "-t", f"refs/tags/{version}").decode().strip() != "tag" or oid(root, f"refs/tags/{version}^{{commit}}") != release:
        raise ValueError("published release requires its exact annotated SemVer tag")
    if oid(root, f"{release}^{{tree}}") != published["sourceTree"]:
        raise ValueError("published release source tree differs")
    api = json.loads(read_input(directory, "release-api.json"))
    if api.get("id") != published["releaseId"] or api.get("tag_name") != version or api.get("draft") is not False or api.get("prerelease") is not False or api.get("immutable") is not True:
        raise ValueError("published release identity differs")
    raw_manifest = read_input(directory, "repository-manifest.json")
    if hashlib.sha256(raw_manifest).hexdigest() != published["repositoryManifestSha256"]:
        raise ValueError("active repository baseline differs")
    baseline = json.loads(raw_manifest)
    baseline_commit = baseline["sourceCommit"]
    if baseline.get("schema") != 2 or baseline.get("releaseVersion") != version or not isinstance(baseline_commit, str) or not HEX40.fullmatch(baseline_commit) or oid(root, f"{baseline_commit}^{{tree}}") != baseline["sourceTree"]:
        raise ValueError("repository baseline source differs")
    active_tag = baseline_tag(root, baseline_commit, version)
    verify_baseline_snapshot(directory, active_tag, version, published["repositorySnapshotSha256"], raw_manifest)
    for field in ("buildMetadataSha256", "unsignedManifestSha256"):
        if not isinstance(baseline.get(field), str) or not HEX64.fullmatch(baseline[field]):
            raise ValueError("repository baseline build identity differs")
    published_installer = read_input(directory, "arch-linux-installer.sh")
    if baseline.get("installerSha256") != hashlib.sha256(published_installer).hexdigest() or blob(root, baseline_commit, "arch-linux-installer.sh") != published_installer:
        raise ValueError("repository baseline installer hash or bytes differ")
    package_set = blob(root, main, "repository/package-set")
    names = package_set.decode("ascii").splitlines()
    if len(names) not in (6, 7) or len(set(names)) != len(names) or any(not re.fullmatch(r"arch-linux-[a-z0-9-]+", name) for name in names) or package_set != blob(root, baseline_commit, "repository/package-set") or hashlib.sha256(package_set).hexdigest() != baseline["packageSetSha256"]:
        raise ValueError("package closure differs from active baseline")
    revisions = {}
    expected_names = set()
    for name in names:
        before = package_metadata(root, baseline_commit, name)
        after = package_metadata(root, main, name)
        if before[:2] != after[:2] or before[3] != after[3] or after[2] <= before[2]:
            raise ValueError("all package revisions must advance with unchanged epoch/version/architecture")
        expected_names.add(f"{name}-{before[1]}-{before[2]}-{before[3]}.pkg.tar.zst")
        revisions[name] = after[2]
    files = baseline["files"]
    actual_names = [row["name"] for row in files if row["name"].endswith(".pkg.tar.zst")]
    if len(actual_names) != len(names) or set(actual_names) != expected_names:
        raise ValueError("repository baseline package inventory differs")
    release_entries = tree_entries(root, release)
    # Trust and keyring payload remain byte/mode identical to the installer release.
    protected = {name for name in entries.keys() | release_entries.keys() if name.startswith("repository/trust/") or (name.startswith("packages/arch-linux-keyring/") and not name.endswith(("/PKGBUILD", "/.SRCINFO")))}
    for name in protected:
        if entries.get(name) != release_entries.get(name):
            raise ValueError("package delivery cannot change release trust inputs")
    installer = blob(root, main, "arch-linux-installer.sh")
    matches = re.findall(rb"^readonly VERSION='([^']+)'$", installer, re.M)
    if len(matches) != 1:
        raise ValueError("installer version is ambiguous")
    old = matches[0].decode("ascii")
    base = version_parts(old)
    target = version_parts(version)
    if target[:2] != base[:2] or target < base:
        raise ValueError("package normalization requires the same forward patch series")
    installer = replace_once(installer, b"readonly VERSION='" + matches[0] + b"'", f"readonly VERSION='{version}'".encode(), "installer version")
    bootstrap = blob(root, main, "install.sh")
    for before, after in ((f"readonly BOOTSTRAP_VERSION='{old}'", f"readonly BOOTSTRAP_VERSION='{version}'"),
                          (f"readonly BOOTSTRAP_RELEASE_URL='https://github.com/snaplyze/arch-linux/releases/download/{old}'", f"readonly BOOTSTRAP_RELEASE_URL='https://github.com/snaplyze/arch-linux/releases/download/{version}'")):
        bootstrap = replace_once(bootstrap, before.encode(), after.encode(), "bootstrap version/URL")
    for template in ("release {} supports Linux x86_64 only", "installer version does not match immutable release {}"):
        if template.format(old).encode() in bootstrap:
            bootstrap = replace_once(bootstrap, template.format(old).encode(), template.format(version).encode(), "bootstrap diagnostic")
    changes = {}
    for name, content, id_key in (("arch-linux-installer.sh", installer, "installerAssetId"), ("install.sh", bootstrap, "bootstrapAssetId")):
        rows = [row for row in api["assets"] if row.get("name") == name or row.get("id") == published[id_key]]
        digest = hashlib.sha256(content).hexdigest()
        if len(rows) != 1 or rows[0].get("id") != published[id_key] or rows[0].get("name") != name or rows[0].get("size") != len(content) or rows[0].get("digest") != "sha256:" + digest or rows[0].get("state") != "uploaded" or content != read_input(directory, name) or content != blob(root, release, name) or entries[name][0] != release_entries[name][0]:
            raise ValueError("published installer/bootstrap bytes or identity differ")
        changes[name] = entries[name][0], content
    origin = {"schema": 1, "transformSchema": 1, "kind": "packages", "mainCommit": main,
              "mainTree": oid(root, f"{main}^{{tree}}"), "packageTag": tag, "published": published,
              "baselineCommit": baseline_commit, "baselineTree": baseline["sourceTree"],
              "baselineTag": active_tag, "baselineRepositorySnapshotSha256": published["repositorySnapshotSha256"],
              "baselineBuildMetadataSha256": baseline["buildMetadataSha256"],
              "baselineUnsignedManifestSha256": baseline["unsignedManifestSha256"],
              "baselineSourceSha256": source_hash(root, baseline_commit), "publishedSourceSha256": source_hash(root, release),
              "transformerSha256": hashlib.sha256(transformer).hexdigest(), "packageRevisions": revisions}
    changes[PACKAGE_ORIGIN] = "100644", (json.dumps(origin, sort_keys=True, separators=(",", ":")) + "\n").encode()
    return replace_tree(root, main, changes), version


def verify_packages(root: Path, source: str, main: str, tag: str, directory: Path) -> dict[str, str]:
    tree, version = package_tree(root, main, tag, directory)
    if not HEX40.fullmatch(source) or git(root, "show", "-s", "--format=%P", source).decode().strip() != main or oid(root, f"{source}^{{tree}}") != tree or release_commit(root, main, tag, tree) != source:
        raise ValueError("package child differs from deterministic reviewed transformation")
    return {"main_commit": main, "main_tree": oid(root, f"{main}^{{tree}}"), "source_commit": source,
            "source_tree": tree, "source_tree_sha256": source_hash(root, source), "release_version": version, "package_tag": tag, "delivery_kind": "packages"}


def prepare_packages(root: Path, main: str, tag: str, directory: Path, output: Path) -> dict[str, str]:
    if oid(root, "HEAD") != main or git(root, "status", "--porcelain=v1", "--untracked-files=all").strip():
        raise ValueError("package preparation requires clean reviewed main")
    if not output.is_absolute() or output == root or root in output.parents:
        raise ValueError("package output must be absolute and outside source")
    tree, _ = package_tree(root, main, tag, directory)
    source = release_commit(root, main, tag, tree)
    identity = verify_packages(root, source, main, tag, directory)
    output.mkdir(mode=0o700)
    candidate_ref = "refs/arch-linux-release/prepared"
    git(root, "update-ref", candidate_ref, source)
    git(root, "bundle", "create", str(output / "source.bundle"), candidate_ref, f"^{main}")
    identity["bundle_sha256"] = hashlib.sha256((output / "source.bundle").read_bytes()).hexdigest()
    (output / "identity.json").write_text(json.dumps(identity, sort_keys=True, separators=(",", ":")) + "\n")
    return identity


def release_bootstrap_document(raw: bytes, path: str, version: str) -> bytes:
    begin = b"<!-- BEGIN release-bootstrap -->\n"
    end = b"<!-- END release-bootstrap -->"
    if raw.count(b"<!-- BEGIN release-bootstrap") != 1 or raw.count(b"<!-- END release-bootstrap") != 1:
        raise ValueError(f"release bootstrap requires one instruction block in {path}")
    if raw.count(begin) != 1 or raw.count(end) != 1:
        raise ValueError(f"release bootstrap block markers are malformed in {path}")
    prefix, remaining = raw.split(begin, 1)
    content, suffix = remaining.split(end, 1) if end in remaining else (b"", b"")
    template = BOOTSTRAP_DOCUMENTS[path].encode("ascii")
    fragments = template.split(b"@RELEASE_VERSION@")
    canonical_version = rb"(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})"
    pattern = re.escape(fragments[0]) + b"(?P<version>" + canonical_version + b")"
    pattern += b"".join(re.escape(fragment) + (b"(?P=version)" if index < len(fragments) - 1 else b"")
                        for index, fragment in enumerate(fragments[1:], 1))
    if re.fullmatch(pattern, content) is None:
        raise ValueError(f"release bootstrap instructions are malformed in {path}")
    return prefix + begin + template.replace(b"@RELEASE_VERSION@", version.encode("ascii")) + end + suffix


def release_overview(raw: bytes, version: str) -> bytes:
    begin, end = b"<!-- BEGIN release-overview -->\n", b"<!-- END release-overview -->"
    if raw.count(b"<!-- BEGIN release-overview") != 1 or raw.count(b"<!-- END release-overview") != 1:
        raise ValueError("release overview requires one exact block")
    if raw.count(begin) != 1 or raw.count(end) != 1:
        raise ValueError("release overview markers are malformed")
    prefix, remaining = raw.split(begin, 1)
    content, suffix = remaining.split(end, 1) if end in remaining else (b"", b"")
    source = SOURCE_RELEASE_OVERVIEW.encode("ascii")
    template = RELEASE_OVERVIEW.encode("ascii")
    if content != source:
        match = re.match(rb"This tree describes release \*\*([0-9]+\.[0-9]+\.[0-9]+)\*\*", content)
        if (match is None or VERSION.fullmatch(match[1].decode("ascii")) is None or
                content != template.replace(b"@RELEASE_VERSION@", match[1])):
            raise ValueError("release overview content is malformed")
    return prefix + begin + template.replace(b"@RELEASE_VERSION@", version.encode("ascii")) + end + suffix


def release_changelog(raw: bytes, version: str) -> bytes:
    if len(re.findall(rb"^## Unreleased\b[^\n]*$", raw, re.M)) != 1 or raw.count(b"## Unreleased\n") != 1:
        raise ValueError("release changelog requires one exact Unreleased section")
    if re.search(rb"^## " + re.escape(version.encode("ascii")) + rb"(?:\s|$)", raw, re.M):
        raise ValueError("release changelog already names the selected version")
    start = raw.index(b"## Unreleased\n") + len(b"## Unreleased\n")
    next_heading = re.search(rb"^## ", raw[start:], re.M)
    end = start + next_heading.start() if next_heading else len(raw)
    if not raw[start:end].strip():
        raise ValueError("release changelog Unreleased section is empty")
    return raw[:start - len(b"## Unreleased\n")] + b"## " + version.encode("ascii") + b"\n" + raw[start:]


def transformed_tree(root: Path, main: str, version: str) -> str:
    if HEX40.fullmatch(main) is None or oid(root, f"{main}^{{commit}}") != main:
        raise ValueError("reviewed main commit is malformed")
    if delivery_intent(root, main)["kind"] != "installer":
        raise ValueError("package intent suppresses installer release preparation")
    parts = version_parts(version)
    entries = tree_entries(root, main)
    if ORIGIN in entries:
        raise ValueError("a release child cannot be used as reviewed main")
    transformer = blob(root, main, TRANSFORMER)
    if transformer != Path(__file__).read_bytes():
        raise ValueError("release transformation code differs from reviewed main")
    installer = blob(root, main, "arch-linux-installer.sh")
    match = re.search(rb"^readonly VERSION='([^']+)'$", installer, re.M)
    if match is None:
        raise ValueError("reviewed installer version is absent")
    old = match.group(1).decode("ascii")
    old_match = VERSION.fullmatch(old)
    if old_match is None:
        raise ValueError("reviewed installer version is malformed")
    base = tuple(int(part) for part in old_match.groups())
    if parts[:2] != base[:2] or parts[2] < base[2]:
        raise ValueError("automatic releases are forward patches of the reviewed major/minor")
    offset = parts[2] - base[2] + 1
    new = version.encode("ascii")
    changes = {
        "arch-linux-installer.sh": (entries["arch-linux-installer.sh"][0], replace_once(
            installer, b"readonly VERSION='" + match.group(1) + b"'",
            b"readonly VERSION='" + new + b"'", "installer version")),
    }
    bootstrap = blob(root, main, "install.sh")
    for before, after, label in (
        (f"readonly BOOTSTRAP_VERSION='{old}'", f"readonly BOOTSTRAP_VERSION='{version}'", "bootstrap version"),
        (f"readonly BOOTSTRAP_RELEASE_URL='https://github.com/snaplyze/arch-linux/releases/download/{old}'",
         f"readonly BOOTSTRAP_RELEASE_URL='https://github.com/snaplyze/arch-linux/releases/download/{version}'", "bootstrap URL"),
    ):
        bootstrap = replace_once(bootstrap, before.encode(), after.encode(), label)
    for message in ("release {} supports Linux x86_64 only", "installer version does not match immutable release {}"):
        before, after = message.format(old).encode(), message.format(version).encode()
        if before in bootstrap:
            bootstrap = replace_once(bootstrap, before, after, "bootstrap diagnostic version")
    changes["install.sh"] = entries["install.sh"][0], bootstrap
    for path in BOOTSTRAP_DOCUMENTS:
        if path not in entries:
            raise ValueError(f"release bootstrap document is missing: {path}")
        changes[path] = entries[path][0], release_bootstrap_document(blob(root, main, path), path, version)
    changes["README.md"] = entries["README.md"][0], release_overview(changes["README.md"][1], version)
    if "CHANGELOG.md" not in entries:
        raise ValueError("release changelog document is missing")
    changes["CHANGELOG.md"] = entries["CHANGELOG.md"][0], release_changelog(blob(root, main, "CHANGELOG.md"), version)
    revisions = {}
    packages = blob(root, main, "repository/package-set").decode("ascii").splitlines()
    if len(packages) != len(set(packages)) or not packages:
        raise ValueError("reviewed package closure is malformed")
    for package in packages:
        if re.fullmatch(r"arch-linux-[a-z0-9-]+", package) is None:
            raise ValueError("reviewed package name is malformed")
        pkgbuild_name, srcinfo_name = f"packages/{package}/PKGBUILD", f"packages/{package}/.SRCINFO"
        pkgbuild, srcinfo = blob(root, main, pkgbuild_name), blob(root, main, srcinfo_name)
        matches = re.findall(rb"^pkgrel=([1-9][0-9]{0,8})$", pkgbuild, re.M)
        if len(matches) != 1:
            raise ValueError("automatic package revisions require one bounded integer pkgrel")
        current = int(matches[0])
        revision = current + offset
        revisions[package] = revision
        changes[pkgbuild_name] = entries[pkgbuild_name][0], replace_once(
            pkgbuild, b"pkgrel=" + matches[0] + b"\n", f"pkgrel={revision}\n".encode(), "PKGBUILD revision")
        updated_srcinfo = replace_once(
            srcinfo, f"\tpkgrel = {current}\n".encode(), f"\tpkgrel = {revision}\n".encode(), "SRCINFO revision")
        # A renamed package may provide its former name at its own full version.
        # Keep only explicitly version-bound aliases in sync with makepkg output.
        for alias in re.findall(rb'"([a-z0-9+._-]+)=\$\{pkgver\}-\$\{pkgrel\}"', pkgbuild):
            versions = re.findall(rb"^\tpkgver = (\S+)$", srcinfo, re.M)
            if len(versions) != 1:
                raise ValueError("version-bound provides require one pkgver")
            prefix = b"\tprovides = " + alias + b"=" + versions[0] + b"-"
            updated_srcinfo = replace_once(updated_srcinfo,
                prefix + str(current).encode() + b"\n",
                prefix + str(revision).encode() + b"\n", "version-bound provides")
        changes[srcinfo_name] = entries[srcinfo_name][0], updated_srcinfo
    origin = {"schema": 1, "transformSchema": 1, "mainCommit": main,
              "mainTree": oid(root, f"{main}^{{tree}}"), "releaseVersion": version,
              "transformerSha256": hashlib.sha256(transformer).hexdigest(), "packageRevisions": revisions}
    changes[ORIGIN] = "100644", (json.dumps(origin, sort_keys=True, separators=(",", ":")) + "\n").encode()
    return replace_tree(root, main, changes)


def source_hash(root: Path, commit: str) -> str:
    rows = [f"{'0755' if mode == '100755' else '0644'} {hashlib.sha256(blob(root, commit, name)).hexdigest()} *{name}\n"
            for name, (mode, _) in tree_entries(root, commit).items()]
    return hashlib.sha256("".join(sorted(rows)).encode()).hexdigest()


def release_commit(root: Path, main: str, version: str, tree: str) -> str:
    timestamp = git(root, "show", "-s", "--format=%ct", main).decode().strip()
    environment = {"GIT_AUTHOR_NAME": "arch-linux release automation", "GIT_COMMITTER_NAME": "arch-linux release automation",
                   "GIT_AUTHOR_EMAIL": "release@users.noreply.github.com", "GIT_COMMITTER_EMAIL": "release@users.noreply.github.com",
                   "GIT_AUTHOR_DATE": f"{timestamp} +0000", "GIT_COMMITTER_DATE": f"{timestamp} +0000"}
    return git(root, "commit-tree", tree, "-p", main,
               data=f"Prepare immutable release {version}\n\nReviewed-main: {main}\n".encode(),
               extra_env=environment).decode().strip()


def require_package_progress(root: Path, source: str, version: str) -> None:
    candidate = version_parts(version)
    tags = git(root, "tag", "--list").decode().splitlines()
    previous = [(tuple(map(int, match.groups())), tag) for tag in tags
                if (match := VERSION.fullmatch(tag)) and tuple(map(int, match.groups())) < candidate]
    if not previous:
        return
    tag = max(previous)[1]
    previous_entries = tree_entries(root, f"refs/tags/{tag}")
    packages = blob(root, source, "repository/package-set").decode().splitlines()
    for package in packages:
        path = f"packages/{package}/.SRCINFO"
        if path not in previous_entries:
            continue
        before, after = [], []
        for commit, destination in ((f"refs/tags/{tag}", before), (source, after)):
            raw = blob(root, commit, path).decode()
            for field in ("epoch", "pkgver", "pkgrel"):
                values = re.findall(rf"^\s*{field} = (\S+)$", raw, re.M)
                if len(values) != (0 if field == "epoch" and not values else 1):
                    raise ValueError("package progress metadata is ambiguous")
                destination.append(values[0] if values else "0")
        if before[:2] == after[:2]:
            if re.fullmatch(r"[1-9][0-9]*", before[2]) is None or int(after[2]) <= int(before[2]):
                raise ValueError(f"reviewed package revision would not advance the existing release: {package}")


def verify(root: Path, source: str, main: str, version: str) -> dict[str, str]:
    if HEX40.fullmatch(source) is None:
        raise ValueError("release source commit is malformed")
    parents = git(root, "show", "-s", "--format=%P", source).decode().strip()
    if parents != main:
        raise ValueError("release source must have exactly the reviewed main commit as parent")
    expected_tree = transformed_tree(root, main, version)
    if oid(root, f"{source}^{{tree}}") != expected_tree:
        raise ValueError("release source bytes or modes differ from the reviewed transformation")
    if release_commit(root, main, version, expected_tree) != source:
        raise ValueError("release commit metadata differs from deterministic preparation")
    return {"main_commit": main, "main_tree": oid(root, f"{main}^{{tree}}"),
            "source_commit": source, "source_tree": expected_tree,
            "source_tree_sha256": source_hash(root, source), "release_version": version}


def prepare(root: Path, main: str, version: str, output: Path) -> dict[str, str]:
    if git(root, "status", "--porcelain=v1", "--untracked-files=all").strip():
        raise ValueError("release preparation requires a clean committed checkout")
    if not output.is_absolute() or output == root or root in output.parents:
        raise ValueError("release preparation output must be absolute and outside source")
    tree = transformed_tree(root, main, version)
    source = release_commit(root, main, version, tree)
    require_package_progress(root, source, version)
    identity = verify(root, source, main, version)
    output.mkdir(mode=0o700)
    candidate_ref = "refs/arch-linux-release/prepared"
    git(root, "update-ref", candidate_ref, source)
    git(root, "bundle", "create", str(output / "source.bundle"), candidate_ref, f"^{main}")
    identity["bundle_sha256"] = hashlib.sha256((output / "source.bundle").read_bytes()).hexdigest()
    (output / "identity.json").write_text(json.dumps(identity, sort_keys=True, separators=(",", ":")) + "\n")
    return identity


def restore(root: Path, main: str, source: str, version: str, directory: Path, bundle_hash: str) -> dict[str, str]:
    if oid(root, "HEAD") != main or git(root, "status", "--porcelain=v1", "--untracked-files=all").strip():
        raise ValueError("release restoration requires the clean reviewed main checkout")
    bundle = directory / "source.bundle"
    if bundle.is_symlink() or not bundle.is_file() or hashlib.sha256(bundle.read_bytes()).hexdigest() != bundle_hash:
        raise ValueError("release source bundle digest differs")
    git(root, "bundle", "verify", str(bundle))
    git(root, "fetch", "--no-tags", str(bundle), "refs/arch-linux-release/prepared")
    if oid(root, "FETCH_HEAD") != source:
        raise ValueError("release source bundle commit differs")
    identity = verify(root, source, main, version)
    expected = dict(identity, bundle_sha256=bundle_hash)
    if json.loads((directory / "identity.json").read_bytes()) != expected:
        raise ValueError("release source transport metadata differs")
    previous_umask = os.umask(0o022)
    try:
        git(root, "checkout", "--detach", source)
    finally:
        os.umask(previous_umask)
    return expected


def restore_packages(root: Path, main: str, source: str, tag: str, published: Path,
                     directory: Path, bundle_hash: str) -> dict[str, str]:
    if oid(root, "HEAD") != main or git(root, "status", "--porcelain=v1", "--untracked-files=all").strip():
        raise ValueError("package restoration requires clean reviewed main")
    bundle = directory / "source.bundle"
    if not HEX64.fullmatch(bundle_hash) or bundle.is_symlink() or not bundle.is_file() or hashlib.sha256(bundle.read_bytes()).hexdigest() != bundle_hash:
        raise ValueError("package source bundle digest differs")
    git(root, "bundle", "verify", str(bundle))
    git(root, "fetch", "--no-tags", str(bundle), "refs/arch-linux-release/prepared")
    if oid(root, "FETCH_HEAD") != source:
        raise ValueError("package bundle commit differs")
    identity = verify_packages(root, source, main, tag, published)
    expected = dict(identity, bundle_sha256=bundle_hash)
    if json.loads(read_input(directory, "identity.json")) != expected:
        raise ValueError("package transport metadata differs")
    previous_umask = os.umask(0o022)
    try:
        git(root, "checkout", "--detach", source)
    finally:
        os.umask(previous_umask)
    return expected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("prepare", "verify", "restore"):
        child = commands.add_parser(command)
        child.add_argument("--main-commit", required=True)
        child.add_argument("--release-version", required=True)
        if command == "prepare":
            child.add_argument("--output-dir", type=Path, required=True)
        else:
            child.add_argument("--source-commit", required=True)
        if command == "restore":
            child.add_argument("--input-dir", type=Path, required=True)
            child.add_argument("--bundle-sha256", required=True)
    intent_parser = commands.add_parser("intent")
    intent_parser.add_argument("--main-commit", required=True)
    for command in ("prepare-packages", "verify-packages", "restore-packages"):
        child = commands.add_parser(command)
        child.add_argument("--main-commit", required=True)
        child.add_argument("--package-tag", required=True)
        child.add_argument("--published-input-dir", type=Path, required=True)
        if command == "prepare-packages":
            child.add_argument("--output-dir", type=Path, required=True)
        else:
            child.add_argument("--source-commit", required=True)
        if command == "restore-packages":
            child.add_argument("--input-dir", type=Path, required=True)
            child.add_argument("--bundle-sha256", required=True)
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        if args.command == "intent":
            identity = delivery_intent(root, args.main_commit)
        elif args.command == "prepare-packages":
            identity = prepare_packages(root, args.main_commit, args.package_tag, args.published_input_dir, args.output_dir)
        elif args.command == "restore-packages":
            identity = restore_packages(root, args.main_commit, args.source_commit, args.package_tag,
                                        args.published_input_dir, args.input_dir, args.bundle_sha256)
        elif args.command == "verify-packages":
            identity = verify_packages(root, args.source_commit, args.main_commit, args.package_tag, args.published_input_dir)
        elif args.command == "prepare":
            identity = prepare(root, args.main_commit, args.release_version, args.output_dir)
        elif args.command == "restore":
            identity = restore(root, args.main_commit, args.source_commit, args.release_version, args.input_dir, args.bundle_sha256)
        else:
            identity = verify(root, args.source_commit, args.main_commit, args.release_version)
        print(json.dumps(identity, sort_keys=True, separators=(",", ":")))
    except (OSError, ValueError, UnicodeError, KeyError, TypeError) as error:
        print(f"release source failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
