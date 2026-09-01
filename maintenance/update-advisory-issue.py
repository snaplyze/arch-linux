#!/usr/bin/env python3
"""Create, update, or close the single maintenance advisory issue."""

from __future__ import annotations

import argparse
import json
import os
import urllib.parse
import urllib.request
from typing import Any

TITLE = "[advisory] arch-linux maintenance drift"
API = "https://api.github.com"


def request(method: str, url: str, token: str, payload: Any | None = None) -> Any:
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "arch-linux-maintenance/1",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        body = response.read()
    return json.loads(body) if body else None


def body_for(report: dict[str, Any], reproducibility: str, iso_status: str) -> str:
    lines = [
        "This issue is maintained by the monthly advisory workflow.",
        "It never changes code, pins, hashes, keys, signatures, releases, or pull requests.",
        "",
        f"- A+B reproducibility: `{reproducibility}`",
        f"- Arch ISO monitor: `{iso_status}`",
        f"- External source monitor: `{report.get('status', 'unknown')}`",
        "",
        "## Findings",
    ]
    findings = report.get("findings", [])
    if not findings and reproducibility == "match" and iso_status == "unchanged":
        lines.append("No advisory drift remains.")
    else:
        for finding in findings:
            lines.append(
                f"- **{finding.get('id', 'unknown')}**: accepted `{finding.get('accepted', '')}`, "
                f"detected `{finding.get('detected', '')}` — {finding.get('impact', '')}"
            )
        if reproducibility != "match":
            lines.append("- **A+B**: independent canonical package builds differ or could not be compared.")
        if iso_status != "unchanged":
            lines.append("- **Arch ISO**: a new ISO or detector error requires manual review and fresh VM evidence.")
    lines += ["", "Manual review is required. Automatic remediation is forbidden."]
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True)
    parser.add_argument("--reproducibility", choices=("match", "mismatch", "error"), required=True)
    parser.add_argument("--iso-status", required=True)
    args = parser.parse_args()
    token = os.environ.get("GITHUB_TOKEN", "")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    if not token or "/" not in repository:
        raise SystemExit("GITHUB_TOKEN and GITHUB_REPOSITORY are required")
    with open(args.report, encoding="utf-8") as stream:
        report = json.load(stream)
    body = body_for(report, args.reproducibility, args.iso_status)
    clean = report.get("status") == "unchanged" and args.reproducibility == "match" and args.iso_status == "unchanged"

    query = urllib.parse.urlencode({"state": "open", "per_page": "100"})
    issues = request("GET", f"{API}/repos/{repository}/issues?{query}", token)
    matches = [item for item in issues if "pull_request" not in item and item.get("title") == TITLE]
    if len(matches) > 1:
        raise SystemExit("more than one open maintenance advisory issue exists")
    if clean:
        if matches:
            request("PATCH", matches[0]["url"], token, {"body": body, "state": "closed"})
        print("maintenance advisory issue is closed/absent")
        return
    payload = {"title": TITLE, "body": body}
    if matches:
        request("PATCH", matches[0]["url"], token, payload)
        print(f"updated issue #{matches[0]['number']}")
    else:
        created = request("POST", f"{API}/repos/{repository}/issues", token, payload)
        print(f"created issue #{created['number']}")


if __name__ == "__main__":
    main()
