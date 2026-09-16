#!/usr/bin/env python3
"""Prepare and verify the exact release-only child of a reviewed main commit."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
ORIGIN = "repository/release-origin.json"
TRANSFORMER = "repository/release-source.py"
HEX40 = re.compile(r"[a-f0-9]{40}\Z")
VERSION = re.compile(r"(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\Z")


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


def transformed_tree(root: Path, main: str, version: str) -> str:
    if HEX40.fullmatch(main) is None or oid(root, f"{main}^{{commit}}") != main:
        raise ValueError("reviewed main commit is malformed")
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
    for path in ("README.md", "docs/installation.md"):
        if path in entries:
            raw = blob(root, main, path)
            # Only the canonical immutable install commands are release-generated prose.
            before = f"https://raw.githubusercontent.com/snaplyze/arch-linux/{old}/install.sh".encode()
            after = f"https://raw.githubusercontent.com/snaplyze/arch-linux/{version}/install.sh".encode()
            changes[path] = entries[path][0], raw.replace(before, after)
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
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        if args.command == "prepare":
            identity = prepare(root, args.main_commit, args.release_version, args.output_dir)
        elif args.command == "restore":
            identity = restore(root, args.main_commit, args.source_commit, args.release_version, args.input_dir, args.bundle_sha256)
        else:
            identity = verify(root, args.source_commit, args.main_commit, args.release_version)
        print(json.dumps(identity, sort_keys=True, separators=(",", ":")))
    except (OSError, ValueError, UnicodeError) as error:
        print(f"release source failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
