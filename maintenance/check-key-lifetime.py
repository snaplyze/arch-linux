#!/usr/bin/env python3
"""Read public trust expiry for advisory maintenance; never renew or sign a key."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DAY = 86400


def inspect_public_trust() -> tuple[str, str, int, str]:
    trust = ROOT / "repository/trust"
    certificate = trust / "arch-linux.gpg"
    primary = (trust / "primary-fingerprint").read_text().strip()
    signing = (trust / "signing-subkey-fingerprint").read_text().strip()
    if not all(re.fullmatch(r"[A-F0-9]{40}", value) for value in (primary, signing)):
        raise ValueError("invalid tracked public fingerprint")
    if not certificate.is_file() or certificate.is_symlink():
        raise ValueError("public certificate is not a regular file")
    with tempfile.TemporaryDirectory(prefix="arch-linux-public-lifetime-") as home:
        command = ["gpg", "--batch", "--no-options", "--no-autostart", "--homedir", home]
        packets = subprocess.run(command + ["--list-packets", str(certificate)], check=True,
                                 capture_output=True, text=True, timeout=30).stdout
        if re.search(r"^:secret (?:sub )?key packet:", packets, re.M):
            raise ValueError("private packets in public trust")
        metadata = subprocess.run(command + ["--with-colons", "--with-subkey-fingerprint",
                                  "--show-keys", str(certificate)], check=True,
                                  capture_output=True, text=True, timeout=30).stdout
    rows = [line.split(":") for line in metadata.splitlines()]
    keys = [row for row in rows if row[0] in ("pub", "sub")]
    fingerprints = [row[9] for row in rows if row[0] == "fpr"]
    if ([row[0] for row in keys] != ["pub", "sub"] or fingerprints != [primary, signing]
            or len([row for row in rows if row[0] == "uid"]) != 1):
        raise ValueError("public certificate identity or shape differs")
    for row, capability in zip(keys, ("c", "s"), strict=True):
        # Expiration is reported below; revoked/disabled keys are never healthy.
        if (len(row) < 12 or row[1] in ("r", "d", "i", "n") or row[3] != "22"
                or "".join(c for c in row[11] if c.islower()) != capability):
            raise ValueError("public certificate capability or validity differs")
    expiry = int(keys[1][6])
    if expiry <= 0:
        raise ValueError("signing subkey has no finite expiry")
    return primary, signing, expiry, hashlib.sha256(certificate.read_bytes()).hexdigest()


def lifetime_report(primary: str, signing: str, expiry: int, digest: str, now: int) -> dict:
    remaining = expiry - now
    if remaining <= 0:
        status = "expired"
    elif remaining <= 30 * DAY:
        status = "critical"
    elif remaining <= 90 * DAY:
        status = "urgent"
    elif remaining <= 180 * DAY:
        status = "renewal-due"
    elif remaining <= 210 * DAY:
        status = "prepare-renewal"
    else:
        status = "healthy"
    utc = lambda timestamp: dt.datetime.fromtimestamp(timestamp, dt.timezone.utc).isoformat()
    return {
        "schema": 1, "status": status, "automaticChanges": False,
        "primaryFingerprint": primary, "signingFingerprint": signing,
        "certificateSha256": digest, "expiresAt": utc(expiry),
        "renewalStartsAt": utc(expiry - 180 * DAY),
        "remainingDays": remaining // DAY,
        "signingMinimumDays": 180,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="write an advisory JSON report outside source")
    args = parser.parse_args()
    try:
        report = lifetime_report(*inspect_public_trust(), int(dt.datetime.now(dt.timezone.utc).timestamp()))
    except (OSError, ValueError, subprocess.SubprocessError):
        # Do not echo raw GPG output or unexpected input bytes into Actions logs.
        report = {"schema": 1, "status": "error", "automaticChanges": False,
                  "error": "Cannot validate the tracked public certificate; manual review required."}
    rendered = json.dumps(report, sort_keys=True, indent=2) + "\n"
    if args.report:
        args.report.write_text(rendered, encoding="utf-8")
    print(rendered, end="")


if __name__ == "__main__":
    main()
