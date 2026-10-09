#!/usr/bin/env python3
"""Synthetic consumer fixtures only; these receipts do not establish VM acceptance.

Callers sign the generated baseline with their disposable fixture key before binding
its hashes into the temporary harness pins. No actual release/AUR package is built.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def encoded(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n"


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def functional_log(source: Path, run_id: str) -> bytes:
    """Synthetic finalizer input; never a record of actual extension behavior."""
    probe = digest((source / 'tests/vm/guest/extension-probe.js').read_bytes())
    return ''.join(
        f'EXTENSION_FUNCTIONAL_PASS phase={phase} feature={feature} run_id={run_id} '
        f'session=c2 probe_sha256={probe} synthetic_unit_fixture=1\n'
        for phase in ('upgrade', 'postreboot')
        for feature in ('clipboard', 'dash', 'screenshot')).encode()


def write(path: Path, raw: bytes) -> None:
    path.write_bytes(raw)
    path.chmod(0o644)


def baseline(source: Path, manifest: Path) -> None:
    pins = json.loads((source / "tests/vm/gnome51-upgrade-baseline.json").read_bytes())
    old = pins["baseline"]
    fixed = {"arch-linux.db", "arch-linux.db.sig", "arch-linux.db.tar.gz", "arch-linux.db.tar.gz.sig",
             "arch-linux.files", "arch-linux.files.sig", "arch-linux.files.tar.gz", "arch-linux.files.tar.gz.sig"}
    packages = {name + "-" + version + "-any.pkg.tar.zst" for name, version in old["packages"].items()}
    records = []
    for name in sorted(fixed | packages | {name + ".sig" for name in packages}):
        raw = ("synthetic GNOME 51 baseline object: " + name).encode()
        records.append({"name": name, "sha256": digest(raw), "size": len(raw)})
    for name in ("arch-linux.gpg", "primary-fingerprint", "signing-subkey-fingerprint"):
        raw = (source / "repository/trust" / name).read_bytes()
        records.append({"name": name, "sha256": digest(raw), "size": len(raw)})
    value = {"schema": 2, "repository": "arch-linux", "architecture": "x86_64",
             "releaseVersion": old["version"], "sourceDateEpoch": 1,
             "installerSha256": digest(b"synthetic baseline installer"),
             "packageSetSha256": digest(b"synthetic six-package baseline"),
             "files": sorted(records, key=lambda row: row["name"])}
    for field in ("sourceCommit", "sourceTree", "buildMetadataSha256", "unsignedManifestSha256"):
        value[field] = old[field]
    write(manifest, encoded(value))


def bind(source: Path, manifest: Path) -> None:
    path = source / "tests/vm/gnome51-upgrade-baseline.json"
    pins = json.loads(path.read_bytes())
    pins["baseline"]["repositoryManifestSha256"] = digest(manifest.read_bytes())
    pins["baseline"]["repositoryManifestSignatureSha256"] = digest(Path(str(manifest) + ".sig").read_bytes())
    for name in ("arch-linux.gpg", "primary-fingerprint", "signing-subkey-fingerprint"):
        raw = (source / "repository/trust" / name).read_bytes()
        pins["release"][name] = {"sha256": digest(raw), "size": len(raw)}
    write(path, encoded(pins))


def attach(source: Path, evidence: Path, commit: str, tree: str, manifest: Path) -> str:
    pins = json.loads((source / "tests/vm/gnome51-upgrade-baseline.json").read_bytes())
    aur = [dict(row, filename="aur/" + row["name"] + "-" + row["version"].split(":", 1)[-1] +
                "-any.pkg.tar.zst") for row in pins["aur"]]
    files = {"release/" + name: row for name, row in pins["release"].items()}
    for row in aur:
        raw = ("synthetic AUR input: " + row["filename"]).encode()
        files[row["filename"]] = {"sha256": digest(raw), "size": len(raw)}
    local = {key: pins["local"][key] for key in ("filename", "sha256")}
    files[local["filename"]] = {"sha256": local["sha256"], "size": 100}
    raw = encoded({"schema": 1, "baseline": pins["baseline"], "sourceCommit": commit,
                   "sourceTree": tree, "files": files, "aur": aur, "local": local})
    write(evidence / "gnome51-upgrade-manifest.json", raw)
    write(evidence / "gnome51-upgrade-baseline-repository-manifest.json", manifest.read_bytes())
    write(evidence / "gnome51-upgrade-baseline-repository-manifest.json.sig",
          Path(str(manifest) + ".sig").read_bytes())
    return f"gnome51_upgrade_manifest_sha256={digest(raw)}\n" + "".join(
        f"gnome51_upgrade_input_sha256={row['sha256']} name={name} size={row['size']}\n"
        for name, row in sorted(files.items()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("baseline", "bind"))
    parser.add_argument("source", type=Path)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    {"baseline": baseline, "bind": bind}[args.mode](args.source, args.manifest)
