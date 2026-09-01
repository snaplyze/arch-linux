#!/usr/bin/env python3
from __future__ import annotations
import pathlib, re

ROOT=pathlib.Path(__file__).resolve().parent.parent
EXCLUDE={pathlib.Path('tests/portability-checks.py')}
patterns={
    'concrete home directory': re.compile(r'/home/(?!\$|\{|<)[A-Za-z0-9._-]+'),
    'concrete removable-media mount': re.compile(r'/run/media/(?!\$|\{|<)[A-Za-z0-9._-]+'),
    'local runner directory': re.compile(r'/(?:opt|var/lib)/actions-runner(?:/|\b)',re.I),
    'workstation name': re.compile(r'\bNucBox\b',re.I),
    'assistant workspace path': re.compile(r'/(?:mnt/data|workspace)/(?:codex|chatgpt)(?:/|\b)',re.I),
    'local runner service': re.compile(r'actions\.runner\.[^\s/]+\.service',re.I),
}
for path in ROOT.rglob('*'):
    if not path.is_file() or '.git' in path.parts or path.relative_to(ROOT) in EXCLUDE:
        continue
    try: text=path.read_text(encoding='utf-8')
    except UnicodeDecodeError: continue
    for label,pattern in patterns.items():
        match=pattern.search(text)
        if match:
            line=text.count('\n',0,match.start())+1
            raise SystemExit(f"portability check failed: {label} in {path.relative_to(ROOT)}:{line}: {match.group(0)}")
print('portability checks passed')
