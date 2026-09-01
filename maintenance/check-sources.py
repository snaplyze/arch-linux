#!/usr/bin/env python3
"""Validate accepted external inputs and optionally report upstream drift.

The command is advisory-only: it never edits source, hashes, pins, keys, issues,
or releases. Network drift is returned in a JSON report and does not alter files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import urllib.error
import urllib.request
from collections import defaultdict
from typing import Any, NoReturn

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "maintenance" / "sources.json"
INSTALLER = ROOT / "arch-linux-installer.sh"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")


def fail(message: str) -> NoReturn:
    raise SystemExit(f"maintenance source check failed: {message}")


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"cannot read {path.relative_to(ROOT)}: {exc}")


def parse_srcinfo(path: pathlib.Path) -> dict[str, list[str]]:
    result: dict[str, list[str]] = defaultdict(list)
    for line in path.read_text(encoding="utf-8").splitlines():
        value = line.strip()
        if not value:
            continue
        if " = " not in value:
            fail(f"malformed .SRCINFO: {path.relative_to(ROOT)}")
        key, item = value.split(" = ", 1)
        result[key].append(item)
    return dict(result)


def validate_offline(document: Any) -> None:
    expected = {
        "schema", "policy", "archPackages", "tools", "gnomeExtensions",
        "aurPins", "upstreams", "packageSources",
    }
    if not isinstance(document, dict) or set(document) != expected:
        fail("sources.json top-level closure differs")
    if document["schema"] != 1 or document["policy"] != "advisory-only":
        fail("sources.json schema/policy differs")
    raw = MANIFEST.read_text(encoding="utf-8").lower()
    if "arch-os" in raw or "murkl" in raw or "1.9.7" in raw:
        fail("retired upstream appears in maintenance manifest")

    installer = INSTALLER.read_text(encoding="utf-8")
    package_sources: list[dict[str, str]] = []
    for srcinfo_path in sorted((ROOT / "packages").glob("*/.SRCINFO")):
        info = parse_srcinfo(srcinfo_path)
        package = srcinfo_path.parent.name
        sources = info.get("source", [])
        sums = info.get("sha256sums", [])
        if len(sources) != len(sums):
            fail(f"source/checksum closure differs: {package}")
        for source, checksum in zip(sources, sums, strict=True):
            locator = source.split("::", 1)[-1]
            if locator.startswith("https://"):
                package_sources.append({"package": package, "source": source, "sha256": checksum})
    if document["packageSources"] != package_sources:
        fail("maintenance packageSources differ from committed .SRCINFO files")

    identifiers: set[str] = set()
    for section in ("archPackages", "tools", "gnomeExtensions", "upstreams"):
        values = document[section]
        if not isinstance(values, list) or not values:
            fail(f"{section} must be a non-empty list")
        for item in values:
            if not isinstance(item, dict) or not isinstance(item.get("id"), str):
                fail(f"{section} contains an invalid item")
            if item["id"] in identifiers:
                fail(f"duplicate advisory id: {item['id']}")
            identifiers.add(item["id"])
    aur = document["aurPins"]
    if not isinstance(aur, list) or not aur:
        fail("aurPins must be a non-empty list")
    for item in aur:
        if set(item) != {"name", "commit", "treeSha256", "srcinfoSha256", "pkgbuildSha256"}:
            fail("AUR pin closure differs")
        if not COMMIT.fullmatch(item["commit"]):
            fail(f"invalid AUR commit: {item['name']}")
        for field in ("treeSha256", "srcinfoSha256", "pkgbuildSha256"):
            if not SHA256.fullmatch(item[field]):
                fail(f"invalid AUR checksum: {item['name']}:{field}")
        literal = " ".join(item[field] for field in ("commit", "treeSha256", "srcinfoSha256", "pkgbuildSha256"))
        if literal not in installer:
            fail(f"AUR pin differs from installer: {item['name']}")

    gum = next((item for item in document["tools"] if item["id"] == "gum:linux-x86_64"), None)
    starship = next((item for item in document["tools"] if item["id"] == "tool:starship"), None)
    if gum is None or starship is None:
        fail("Gum or Starship advisory input is absent")
    for literal in (gum["acceptedVersion"], gum["acceptedSha256"]):
        if literal not in installer:
            fail("Gum accepted state differs from installer")
    preset = ROOT / starship["presetPath"]
    if not preset.is_file() or preset.is_symlink() or sha(preset) != starship["presetSha256"]:
        fail("Starship preset binding differs")
    if starship["presetSha256"] not in installer:
        fail("Starship preset checksum differs from installer")

    extension = document["gnomeExtensions"][0]
    for literal in (
        extension["uuid"], str(extension["acceptedVersionTag"]),
        str(extension["acceptedExtensionVersion"]), extension["acceptedSha256"],
    ):
        if literal not in installer:
            fail("GNOME extension accepted state differs from installer")


def fetch_json(url: str) -> Any:
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": "arch-linux-maintenance/1"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status}")
        data = response.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024:
        raise RuntimeError("response exceeds size limit")
    return json.loads(data.decode("utf-8"))


def network_findings(document: dict[str, Any]) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []

    def record(identifier: str, accepted: str, detected: str, impact: str) -> None:
        if detected != accepted:
            findings.append({
                "id": identifier,
                "accepted": accepted,
                "detected": detected,
                "impact": impact,
            })

    for item in document["archPackages"]:
        try:
            data = fetch_json(item["source"])
            record(item["id"], item["acceptedVersion"], str(data["pkgver"]), item["impact"])
        except Exception as exc:  # advisory monitor reports infrastructure errors instead of mutating state
            findings.append({"id": item["id"], "accepted": item["acceptedVersion"], "detected": f"ERROR: {exc}", "impact": item["impact"]})

    for item in document["tools"]:
        try:
            data = fetch_json(item["source"])
            tag = str(data["tag_name"]).removeprefix("v")
            record(item["id"], item["acceptedVersion"], tag, item["impact"])
        except Exception as exc:
            findings.append({"id": item["id"], "accepted": item["acceptedVersion"], "detected": f"ERROR: {exc}", "impact": item["impact"]})

    for item in document["gnomeExtensions"]:
        try:
            data = fetch_json(item["source"])
            versions = data.get("shell_version_map", {})
            candidates = []
            for values in versions.values():
                if isinstance(values, dict) and "pk" in values:
                    candidates.append(int(values["pk"]))
                elif isinstance(values, list):
                    candidates.extend(int(value["pk"]) for value in values if isinstance(value, dict) and "pk" in value)
            detected = str(max(candidates)) if candidates else "unknown"
            record(item["id"], str(item["acceptedVersionTag"]), detected, item["impact"])
        except Exception as exc:
            findings.append({"id": item["id"], "accepted": str(item["acceptedVersionTag"]), "detected": f"ERROR: {exc}", "impact": item["impact"]})

    for item in document["aurPins"]:
        identifier = f"aur:{item['name']}"
        try:
            result = subprocess.run(
                ["git", "ls-remote", f"https://aur.archlinux.org/{item['name']}.git", "HEAD"],
                check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45,
            )
            detected = result.stdout.split()[0]
            record(identifier, item["commit"], detected, "Review the new AUR snapshot; never update the pin automatically.")
        except Exception as exc:
            findings.append({"id": identifier, "accepted": item["commit"], "detected": f"ERROR: {exc}", "impact": "Manual AUR review required."})

    for item in document["upstreams"]:
        git_url = item.get("git")
        accepted = item.get("acceptedCommit")
        if not git_url or not accepted:
            continue
        try:
            result = subprocess.run(
                ["git", "ls-remote", git_url, "HEAD"],
                check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45,
            )
            detected = result.stdout.split()[0]
            record(item["id"], accepted, detected, item["impact"])
        except Exception as exc:
            findings.append({"id": item["id"], "accepted": accepted, "detected": f"ERROR: {exc}", "impact": item["impact"]})
    return sorted(findings, key=lambda item: item["id"])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--network", action="store_true", help="perform advisory upstream queries")
    parser.add_argument("--report", type=pathlib.Path, help="write canonical JSON report")
    args = parser.parse_args()
    document = load_json(MANIFEST)
    validate_offline(document)
    findings = network_findings(document) if args.network else []
    report = {
        "schema": 1,
        "mode": "network" if args.network else "offline",
        "status": "advisory" if findings else "unchanged",
        "findings": findings,
        "automaticChanges": False,
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
