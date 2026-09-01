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
print(f"documentation checks passed: files={len(seen)}")
