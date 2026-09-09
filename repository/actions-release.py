#!/usr/bin/env python3
"""Publish immutable, already verified release assets and check independent readback."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "snaplyze/arch-linux"
VERSION = re.compile(r"(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\Z")


def parts(version: str) -> tuple[int, ...]:
    match = VERSION.fullmatch(version)
    if match is None:
        raise ValueError("invalid canonical release version")
    return tuple(int(part) for part in match.groups())


def next_version(base: str, names: list[str]) -> str:
    minimum = parts(base)
    if minimum < (1, 0, 2):
        raise ValueError("reviewed release floor predates the trust migration")
    existing = [parts(name) for name in names if VERSION.fullmatch(name)]
    if any(value[:2] > minimum[:2] for value in existing):
        raise ValueError("reviewed major/minor is behind an existing release")
    patch = max([minimum[2] - 1] + [value[2] for value in existing if value[:2] == minimum[:2]]) + 1
    if patch > 9999:
        raise ValueError("review a new release minor version before the patch range is exhausted")
    return f"{minimum[0]}.{minimum[1]}.{patch}"


def asset_names(version: str) -> set[str]:
    parts(version)
    archive = f"arch-linux-repository-{version}.tar.zst"
    acceptance = f"arch-linux-acceptance-{version}.json"
    evidence = f"arch-linux-acceptance-evidence-{version}.tar.zst"
    return {"BUILD-METADATA.json", "RELEASE-SHA256SUMS", "RELEASE-SHA256SUMS.sig", "UNSIGNED-SHA256SUMS",
            "install.sh", "arch-linux-installer.sh", "arch-linux-installer.sh.sha256", "arch-linux-installer.sh.sig",
            "arch-linux.gpg", "primary-fingerprint", "signing-subkey-fingerprint", archive, archive + ".sha256",
            archive + ".sig", acceptance, acceptance + ".sig", evidence, evidence + ".sig"}


def validate_metadata(value: dict, release_id: int, version: str, draft: bool) -> list[dict]:
    if (value.get("id") != release_id or value.get("tag_name") != version or value.get("name") != version
            or value.get("draft") is not draft or value.get("prerelease") is not False):
        raise ValueError("release metadata identity differs")
    if not draft and value.get("immutable") is not True:
        raise ValueError("published release is not immutable on GitHub")
    assets = value.get("assets")
    if not isinstance(assets, list) or len(assets) != 18:
        raise ValueError("release must contain exactly eighteen assets")
    if any(not isinstance(asset, dict) for asset in assets):
        raise ValueError("release asset metadata is malformed")
    if {asset.get("name") for asset in assets} != asset_names(version):
        raise ValueError("release asset names differ")
    ids = [asset.get("id") for asset in assets]
    if any(type(value) is not int or value <= 0 for value in ids) or len(set(ids)) != 18:
        raise ValueError("release asset IDs are malformed or repeated")
    for asset in assets:
        if (type(asset.get("size")) is not int or not 0 < asset["size"] <= 4294967296
                or asset.get("state") != "uploaded" or not isinstance(asset.get("digest"), str)
                or re.fullmatch(r"sha256:[a-f0-9]{64}", asset["digest"]) is None):
            raise ValueError("release asset size, digest or upload state differs")
    return assets


def command(args: list[str], *, data: bytes | None = None, output=None, public: bool = False) -> bytes:
    environment = dict(os.environ)
    if public:
        for name in ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"):
            environment.pop(name, None)
    try:
        result = subprocess.run(args, input=data, stdout=output or subprocess.PIPE, stderr=subprocess.PIPE,
                                env=environment, check=True)
    except subprocess.CalledProcessError as error:
        raise ValueError(f"release operation failed: {Path(args[0]).name}") from error
    return result.stdout if output is None else b""


def api(path: str, method: str = "GET", payload: dict | None = None, public: bool = False):
    if not path.startswith(f"/repos/{REPOSITORY}/"):
        raise ValueError("API request is outside the canonical repository")
    if public:
        if method != "GET" or payload is not None:
            raise ValueError("public release readback is read-only")
        request = urllib.request.Request("https://api.github.com" + path,
                                         headers={"Accept": "application/vnd.github+json", "User-Agent": "arch-linux-readback"})
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read(16 * 1024 * 1024 + 1)
        if len(raw) > 16 * 1024 * 1024:
            raise ValueError("release API metadata exceeds its bound")
    else:
        args = ["gh", "api", "--hostname", "github.com", "--method", method, path]
        if payload is not None:
            args.extend(["--input", "-"])
        raw = command(args, data=json.dumps(payload).encode() if payload is not None else None)
    return json.loads(raw)


def releases() -> list[dict]:
    result = []
    for page in range(1, 101):
        batch = api(f"/repos/{REPOSITORY}/releases?per_page=100&page={page}")
        if not isinstance(batch, list):
            raise ValueError("release list is malformed")
        result.extend(batch)
        if len(batch) < 100:
            return result
    raise ValueError("release inventory exceeds its bound")


def require_immutability_policy() -> None:
    # The repository setting endpoint requires admin read, which GITHUB_TOKEN lacks.
    # An admin enables the setting once; the public API result is checked after publication.
    if os.environ.get("RELEASE_IMMUTABILITY_REQUIRED") != "true":
        raise ValueError("repository administrator must enable immutable releases and attest the required policy")


def require_latest_main(identity: dict[str, str]) -> None:
    remote = command(["git", "ls-remote", "--refs", f"https://github.com/{REPOSITORY}.git", "refs/heads/main"]).decode()
    if remote != f"{identity['main_commit']}\trefs/heads/main\n":
        raise ValueError("reviewed main has advanced; the superseded candidate cannot be published")


def require_release_trigger(selection: dict[str, str]) -> None:
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    if event == "workflow_run":
        return
    if event != "workflow_dispatch" or selection.get("resume") != "true":
        raise ValueError("manual release runs may only resume an existing release; rerun main CI for a fresh candidate")


def select_release() -> dict[str, str]:
    main_commit = command(["git", "-C", str(ROOT), "rev-parse", "HEAD"]).decode().strip()
    names = command(["git", "-C", str(ROOT), "tag", "--list"]).decode().splitlines()
    matches = []
    for name in names:
        if VERSION.fullmatch(name) is None:
            continue
        try:
            origin = json.loads(command(["git", "-C", str(ROOT), "show", f"refs/tags/{name}:repository/release-origin.json"]))
        except ValueError:
            continue
        if not isinstance(origin, dict):
            raise ValueError("existing release origin is malformed")
        if origin.get("mainCommit") == main_commit:
            matches.append(name)
    base = re.search(r"^readonly VERSION='([^']+)'$", (ROOT / "arch-linux-installer.sh").read_text(), re.M)
    if base is None:
        raise ValueError("reviewed installer version is absent")
    if not matches:
        return {"release_version": next_version(base.group(1), names), "resume": "false",
                "already_published": "false", "resume_release_id": "", "resume_run_id": ""}
    if len(matches) != 1:
        raise ValueError("multiple release tags refer to the same reviewed main origin")
    version = matches[0]
    candidates = [release for release in releases() if release.get("tag_name") == version]
    if len(candidates) > 1:
        raise ValueError("existing release metadata is ambiguous")
    tag_note = command(["git", "-C", str(ROOT), "for-each-ref", "--format=%(contents)", f"refs/tags/{version}"]).decode()
    note = candidates[0].get("body", "") if candidates else tag_note
    run_match = re.search(r"^Actions-run-id: ([1-9][0-9]*)$", note, re.M)
    if run_match is None:
        raise ValueError("existing release lacks its accepted artifact run identity")
    published = bool(candidates and candidates[0].get("draft") is False)
    if published:
        validate_metadata(candidates[0], candidates[0]["id"], version, False)
    return {"release_version": version, "resume": "true", "already_published": str(published).lower(),
            "resume_release_id": str(candidates[0]["id"]) if candidates else "",
            "resume_run_id": run_match.group(1)}


def unpack_evidence(archive: Path, destination: Path) -> None:
    if archive.is_symlink() or not archive.is_file() or archive.stat().st_size > 524288000:
        raise ValueError("evidence artifact is unsafe or too large")
    if not destination.is_absolute() or destination.exists() or destination.is_symlink():
        raise ValueError("evidence extraction requires a fresh absolute destination")
    with tarfile.open(archive, "r:gz") as stream:
        members = stream.getmembers()
        seen = set()
        total = 0
        for member in members:
            path = PurePosixPath(member.name)
            if (path.is_absolute() or ".." in path.parts or not path.parts or str(path) in seen
                    or not (member.isfile() or member.isdir()) or member.size < 0
                    or member.size > 67108864 or len(members) > 20000):
                raise ValueError("evidence archive contains an unsafe or excessive entry")
            seen.add(str(path))
            total += member.size
        if total > 524288000 or len({PurePosixPath(member.name).parts[0] for member in members}) != 1:
            raise ValueError("evidence archive exceeds one bounded run")
        destination.mkdir(parents=True, mode=0o755)
        stream.extractall(destination, members=members, filter="data")


def pages_readback(assets: Path, identity: dict[str, str]) -> None:
    verify_assets(assets, identity)
    with tempfile.TemporaryDirectory(prefix="arch-linux-pages-readback-") as temporary:
        expected = Path(temporary) / "site"
        command(["python3", str(ROOT / "repository/safe-extract-snapshot.py"),
                 str(assets / f"arch-linux-repository-{identity['release_version']}.tar.zst"), str(expected)], public=True)
        for path in sorted(expected.rglob("*")):
            if path.is_dir():
                continue
            relative = path.relative_to(expected).as_posix()
            request = urllib.request.Request("https://snaplyze.github.io/arch-linux/" + relative,
                                             headers={"Cache-Control": "no-cache"})
            digest = hashlib.sha256()
            with urllib.request.urlopen(request, timeout=180) as response:
                remaining = path.stat().st_size
                while remaining:
                    chunk = response.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise ValueError("Pages object is truncated")
                    digest.update(chunk)
                    remaining -= len(chunk)
                if response.read(1):
                    raise ValueError("Pages object exceeds its accepted size")
            with path.open("rb") as source:
                if digest.hexdigest() != hashlib.file_digest(source, "sha256").hexdigest():
                    raise ValueError("Pages object differs from the accepted signed snapshot")


def read_identity(path: Path) -> dict[str, str]:
    identity = json.loads(path.read_bytes())
    required = {"main_commit", "main_tree", "source_commit", "source_tree", "source_tree_sha256", "release_version", "bundle_sha256"}
    if not isinstance(identity, dict) or set(identity) != required:
        raise ValueError("release transport identity schema differs")
    for key in required - {"release_version"}:
        length = 40 if key in {"main_commit", "main_tree", "source_commit", "source_tree"} else 64
        if not isinstance(identity[key], str) or re.fullmatch(rf"[a-f0-9]{{{length}}}", identity[key]) is None:
            raise ValueError("release identity digest is malformed")
    parts(identity["release_version"])
    actual = json.loads(command(["python3", str(ROOT / "repository/release-source.py"), "verify",
                                 "--source-commit", identity["source_commit"], "--main-commit", identity["main_commit"],
                                 "--release-version", identity["release_version"]]))
    if any(actual.get(key) != value for key, value in identity.items() if key != "bundle_sha256"):
        raise ValueError("release transport identity differs from its committed source")
    return identity


def verify_assets(assets: Path, identity: dict[str, str]) -> None:
    build_hash = hashlib.sha256((assets / "BUILD-METADATA.json").read_bytes()).hexdigest()
    unsigned_hash = hashlib.sha256((assets / "UNSIGNED-SHA256SUMS").read_bytes()).hexdigest()
    command(["bash", str(ROOT / "repository/verify-release-assets.sh"), str(assets), "--finalized",
             "--release-version", identity["release_version"], "--source-commit", identity["source_commit"],
             "--source-tree", identity["source_tree"], "--source-tree-sha256", identity["source_tree_sha256"],
             "--build-metadata-sha256", build_hash, "--unsigned-manifest-sha256", unsigned_hash], public=True)


def readback(release_id: int, identity: dict[str, str], destination: Path, *, public: bool = False) -> dict:
    version = identity["release_version"]
    metadata = api(f"/repos/{REPOSITORY}/releases/{release_id}", public=public)
    assets = validate_metadata(metadata, release_id, version, not public)
    if not destination.is_absolute() or ROOT == destination or ROOT in destination.parents:
        raise ValueError("asset readback directory must be outside source")
    destination.mkdir(mode=0o700)
    for asset in assets:
        path = destination / asset["name"]
        with path.open("xb") as stream:
            if public:
                url = f"https://github.com/{REPOSITORY}/releases/download/{version}/{asset['name']}"
                with urllib.request.urlopen(url, timeout=180) as response:
                    remaining = asset["size"]
                    while remaining:
                        chunk = response.read(min(1024 * 1024, remaining))
                        if not chunk:
                            raise ValueError("public release asset is truncated")
                        stream.write(chunk)
                        remaining -= len(chunk)
                    if response.read(1):
                        raise ValueError("public release asset exceeds its declared size")
            else:
                command(["gh", "api", "--hostname", "github.com", "-H", "Accept: application/octet-stream",
                         f"/repos/{REPOSITORY}/releases/assets/{asset['id']}"], output=stream)
        path.chmod(0o644)
        with path.open("rb") as stream:
            actual_hash = hashlib.file_digest(stream, "sha256").hexdigest()
        if path.stat().st_size != asset["size"] or "sha256:" + actual_hash != asset["digest"]:
            raise ValueError("release API asset bytes differ")
    verify_assets(destination, identity)
    return metadata


def release_body(identity: dict[str, str], run_id: str) -> str:
    version = identity["release_version"]
    parts(version)
    return (f"Installer {version}. Source `{identity['source_commit']}`, reviewed main `{identity['main_commit']}`.\n\n"
            "The eighteen signed assets include staged QEMU acceptance and exact source/build identities.\n\n"
            f"Install this immutable release from the Arch live environment:\n\n```bash\n"
            f"curl -fsSL https://raw.githubusercontent.com/{REPOSITORY}/{version}/install.sh | bash\n```\n\n"
            f"[Installation instructions for {version}](https://github.com/{REPOSITORY}/blob/{version}/README.md).\n\n"
            f"Actions-run-id: {run_id}")


def draft(assets: Path, identity: dict[str, str]) -> int:
    require_immutability_policy()
    require_latest_main(identity)
    verify_assets(assets, identity)
    require_latest_main(identity)
    version, source = identity["release_version"], identity["source_commit"]
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if re.fullmatch(r"[1-9][0-9]*", run_id) is None:
        raise ValueError("release publication requires its accepted Actions run identity")
    tags = command(["git", "-C", str(ROOT), "ls-remote", "--tags", "origin", f"refs/tags/{version}", f"refs/tags/{version}^{{}}"]).decode()
    if tags:
        if f"{source}\trefs/tags/{version}^{{}}\n" not in tags:
            raise ValueError("an existing release tag cannot be moved or reused")
    else:
        command(["git", "-C", str(ROOT), "-c", "user.name=arch-linux release automation",
                 "-c", "user.email=release@users.noreply.github.com", "tag", "-a", version, source,
                 "-m", f"Immutable release {version}; reviewed main {identity['main_commit']}\n\nActions-run-id: {run_id}"])
        command(["git", "-C", str(ROOT), "-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential",
                 "push", f"https://github.com/{REPOSITORY}.git", f"refs/tags/{version}:refs/tags/{version}"])
    matches = [release for release in releases() if release.get("tag_name") == version]
    if len(matches) > 1:
        raise ValueError("release tag has ambiguous release metadata")
    if matches:
        release = matches[0]
        if release.get("draft") is not True:
            raise ValueError("published release assets cannot be changed")
    else:
        release = api(f"/repos/{REPOSITORY}/releases", "POST", {
            "tag_name": version, "target_commitish": source, "name": version, "draft": True,
            "prerelease": False, "generate_release_notes": False,
            "body": release_body(identity, run_id)
        })
    existing = {asset["name"]: asset for asset in release.get("assets", [])}
    if not set(existing) <= asset_names(version):
        raise ValueError("draft contains unexpected assets")
    for name in sorted(asset_names(version)):
        path = assets / name
        if name in existing:
            with path.open("rb") as stream:
                digest = "sha256:" + hashlib.file_digest(stream, "sha256").hexdigest()
            if existing[name].get("digest") != digest or existing[name].get("size") != path.stat().st_size:
                raise ValueError("draft upload retry would replace different bytes")
        else:
            command(["gh", "release", "upload", version, str(path), "--repo", REPOSITORY])
    with tempfile.TemporaryDirectory(prefix="arch-linux-draft-readback-") as temporary:
        readback(release["id"], identity, Path(temporary) / "assets")
    return release["id"]


def publish(release_id: int, identity: dict[str, str], destination: Path) -> None:
    require_immutability_policy()
    require_latest_main(identity)
    current = api(f"/repos/{REPOSITORY}/releases/{release_id}")
    published = current.get("draft") is False
    readback(release_id, identity, destination, public=published)
    pages_readback(destination, identity)
    require_latest_main(identity)
    result = (current if published else api(f"/repos/{REPOSITORY}/releases/{release_id}", "PATCH",
                                            {"draft": False, "make_latest": "true"}))
    validate_metadata(result, release_id, identity["release_version"], False)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("next-version")
    commands.add_parser("select")
    unpack = commands.add_parser("unpack-evidence")
    unpack.add_argument("--archive", type=Path, required=True)
    unpack.add_argument("--output-dir", type=Path, required=True)
    for name in ("draft", "readback", "publish"):
        child = commands.add_parser(name)
        child.add_argument("--identity", type=Path, required=True)
        if name == "draft":
            child.add_argument("--assets", type=Path, required=True)
        else:
            child.add_argument("--release-id", type=int, required=True)
            child.add_argument("--output-dir", type=Path, required=True)
        if name == "readback":
            child.add_argument("--public", action="store_true")
    args = parser.parse_args()
    try:
        if os.environ.get("GITHUB_REPOSITORY", REPOSITORY) != REPOSITORY:
            raise ValueError("release operations require the canonical repository")
        if args.command == "unpack-evidence":
            unpack_evidence(args.archive, args.output_dir)
        elif args.command == "select":
            selection = select_release()
            require_release_trigger(selection)
            print(json.dumps(selection, sort_keys=True, separators=(",", ":")))
        elif args.command == "next-version":
            base = re.search(r"^readonly VERSION='([^']+)'$", (ROOT / "arch-linux-installer.sh").read_text(), re.M)
            if base is None:
                raise ValueError("reviewed installer version is absent")
            names = command(["git", "-C", str(ROOT), "tag", "--list"]).decode().splitlines()
            print(next_version(base.group(1), names))
        else:
            identity = read_identity(args.identity)
            if args.command == "draft":
                print(draft(args.assets, identity))
            elif args.command == "readback":
                readback(args.release_id, identity, args.output_dir, public=args.public)
                print("public release readback passed" if args.public else "draft release readback passed")
            else:
                publish(args.release_id, identity, args.output_dir)
                print("immutable release published")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"release operation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
