#!/usr/bin/env python3
from __future__ import annotations
import pathlib, re
from typing import NoReturn

ROOT=pathlib.Path(__file__).resolve().parent.parent
LINK=re.compile(r"\[[^\]]+\]\(([^)]+)\)")

def fail(message: str) -> NoReturn:
    raise SystemExit(f"documentation check failed: {message}")

markdown=sorted(ROOT.glob('*.md'))+sorted((ROOT/'docs').rglob('*.md'))+[
    ROOT/'repository/README.md', ROOT/'packages/README.md'
]
seen=set()
for path in markdown:
    if path in seen or not path.is_file(): continue
    seen.add(path)
    text=path.read_text(encoding='utf-8')
    for target in LINK.findall(text):
        target=target.strip()
        if not target or target.startswith(('#','http://','https://','mailto:')):
            continue
        target=target.split('#',1)[0]
        resolved=(path.parent/target).resolve()
        try: resolved.relative_to(ROOT.resolve())
        except ValueError: fail(f"link escapes repository: {path.relative_to(ROOT)} -> {target}")
        if not resolved.exists(): fail(f"broken local link: {path.relative_to(ROOT)} -> {target}")

readme=(ROOT/'README.md').read_text(encoding='utf-8')
for literal in (
    'Minimal TTY','Stock GNOME','Marble','ext4','Btrfs','GRUB','systemd-boot','LUKS2',
    'pacman -Syu','SHA-256','arch-linux.gpg','release-pinned',
):
    if literal not in readme: fail(f"README lacks {literal!r}")
for command_path in re.findall(r'`((?:repository|tests|maintenance)/[A-Za-z0-9_./-]+(?:\.sh|\.py))', readme):
    if not (ROOT/command_path).is_file(): fail(f"README names missing command: {command_path}")

package_repository=(ROOT/'docs/package-repository.md').read_text(encoding='utf-8')
offline_signing=package_repository.split('## Offline signing',1)[1].split('## Verification',1)[0]
verification=package_repository.split('## Verification',1)[1].split('## Pacman policy',1)[0]
for literal in (
    '$ACCEPTED_UNSIGNED', '$SNAPSHOT_OUTPUT', 'root-owned, single-link',
    'signing-account-owned mode-`0700` parent',
):
    if literal not in offline_signing:
        fail(f"package repository offline-signing contract lacks {literal!r}")
for stale in (
    '--unsigned "$ARTIFACT_DIR/unsigned"', '--output "$ARTIFACT_DIR/snapshot"',
):
    if stale in offline_signing:
        fail(f"package repository retains rejected signing path: {stale}")
for literal in ('$SNAPSHOT_OUTPUT/repository', '$SNAPSHOT_OUTPUT/assets'):
    if literal not in verification:
        fail(f"package repository verification path lacks {literal!r}")

release_process=(ROOT/'docs/release-process.md').read_text(encoding='utf-8')
release_verification=release_process.split('## 4. Independent verification',1)[1].split(
    '## 5. Three QEMU scenarios',1
)[0]
for literal in ('$SNAPSHOT_OUTPUT/repository', '$SNAPSHOT_OUTPUT/assets'):
    if literal not in release_verification:
        fail(f"release verification path lacks {literal!r}")
print(f"documentation checks passed: files={len(seen)}")
