#!/usr/bin/env python3
"""Create, update, or close the single maintenance advisory issue."""

from __future__ import annotations

import argparse
import json
import os
import re
import urllib.parse
import urllib.request
from typing import Any

TITLE = "[advisory] arch-linux maintenance drift"
API = "https://api.github.com"
KEY_HEADING = "\n## Signing key lifetime\n"
MONTHLY_CLEAN = "<!-- arch-linux-monthly:clean -->"
MONTHLY_ADVISORY = "<!-- arch-linux-monthly:advisory -->"


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


def combined_body(previous: str, key: dict[str, Any], monthly: str | None,
                  monthly_clean: bool = False) -> tuple[str, bool]:
    """Daily key checks preserve monthly findings in the same advisory issue."""
    if monthly is None:
        monthly = previous.split(KEY_HEADING, 1)[0] or "Monthly source/build checks have not reported yet.\n"
        monthly_clean = MONTHLY_CLEAN in monthly
    else:
        monthly += "\n" + (MONTHLY_CLEAN if monthly_clean else MONTHLY_ADVISORY) + "\n"
    status = key.get("status", "error")
    healthy = status == "healthy" and key.get("automaticChanges") is False
    lines = [KEY_HEADING.rstrip(), f"- Status: `{status}`"]
    if "expiresAt" in key:
        lines += [f"- Public signing subkey: `{key.get('signingFingerprint', 'unknown')}`",
                  f"- Expires: `{key['expiresAt']}`",
                  f"- Manual renewal starts: `{key.get('renewalStartsAt', 'unknown')}`"]
    if not healthy:
        lines += ["- Check the public certificate and arrange manual offline renewal before expiry.",
                  "- Deliver the reviewed renewed public certificate through an updated keyring package."]
    lines += ["- This workflow never extends expiry, changes trust, signs, merges or releases."]
    return monthly.rstrip() + "\n" + "\n".join(lines) + "\n", monthly_clean and healthy


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report")
    parser.add_argument("--reproducibility", choices=("match", "mismatch", "error"))
    parser.add_argument("--iso-status")
    parser.add_argument("--key-report", required=True)
    parser.add_argument("--key-only", action="store_true")
    args = parser.parse_args()
    token = os.environ.get("GITHUB_TOKEN", "")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    if not token or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise SystemExit("GITHUB_TOKEN and GITHUB_REPOSITORY are required")
    with open(args.key_report, encoding="utf-8") as stream:
        key = json.load(stream)
    monthly, monthly_clean = None, False
    if not args.key_only:
        if not all((args.report, args.reproducibility, args.iso_status)):
            parser.error("monthly update requires report, reproducibility and iso-status")
        with open(args.report, encoding="utf-8") as stream:
            report = json.load(stream)
        monthly = body_for(report, args.reproducibility, args.iso_status)
        monthly_clean = (report.get("status") == "unchanged" and args.reproducibility == "match"
                         and args.iso_status == "unchanged")

    issues = []
    page = 1
    while True:
        query = urllib.parse.urlencode({"state": "open", "per_page": "100", "page": page})
        current = request("GET", f"{API}/repos/{repository}/issues?{query}", token)
        issues.extend(current)
        if len(current) < 100:
            break
        page += 1
    matches = [item for item in issues if "pull_request" not in item and item.get("title") == TITLE]
    if len(matches) > 1:
        raise SystemExit("more than one open maintenance advisory issue exists")
    previous = (matches[0].get("body") or "") if matches else ""
    body, clean = combined_body(previous, key, monthly, monthly_clean)
    if (args.key_only and not matches and key.get("status") == "healthy"
            and key.get("automaticChanges") is False):
        clean = True  # Do not invent a monthly failure during a daily public-key check.
    if clean:
        if matches:
            request("PATCH", f"{API}/repos/{repository}/issues/{int(matches[0]['number'])}",
                    token, {"body": body, "state": "closed"})
        print("maintenance advisory issue is closed/absent")
        return
    payload = {"title": TITLE, "body": body}
    if matches:
        if body != previous:
            request("PATCH", f"{API}/repos/{repository}/issues/{int(matches[0]['number'])}", token, payload)
            print(f"updated issue #{matches[0]['number']}")
        else:
            print("maintenance advisory unchanged")
    else:
        created = request("POST", f"{API}/repos/{repository}/issues", token, payload)
        print(f"created issue #{created['number']}")


if __name__ == "__main__":
    main()
