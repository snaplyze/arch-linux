#!/usr/bin/env python3
from __future__ import annotations
import pathlib, re

ROOT=pathlib.Path(__file__).resolve().parent.parent
SELF=pathlib.Path(__file__).resolve()
patterns={
    'OpenPGP private block': re.compile('-----BEGIN PGP PRIVATE KEY BLOCK-----'),
    'PEM private key': re.compile('-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'GitHub token': re.compile(r'\bgh[pousr]_[A-Za-z0-9]{30,}\b'),
    'GitHub fine-grained token': re.compile(r'\bgithub_pat_[A-Za-z0-9_]{40,}\b'),
    'AWS access key': re.compile(r'\bAKIA[0-9A-Z]{16}\b'),
    'generic assigned secret': re.compile(r'(?im)^\s*(?:passphrase|recovery[_-]?(?:phrase|share)|private[_-]?key|github[_-]?token)\s*=\s*["\']?[^$<{\s][^\s]{7,}'),
}
for path in ROOT.rglob('*'):
    if not path.is_file() or '.git' in path.parts or path.resolve()==SELF:
        continue
    if path.suffix.lower() in {'.png','.jpg','.jpeg','.webp','.gpg'}:
        continue
    try: text=path.read_text(encoding='utf-8')
    except UnicodeDecodeError: continue
    for label,pattern in patterns.items():
        match=pattern.search(text)
        if match:
            line=text.count('\n',0,match.start())+1
            raise SystemExit(f"secret scan failed: {label} in {path.relative_to(ROOT)}:{line}")
print('secret scan passed')
