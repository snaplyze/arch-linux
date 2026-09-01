#!/usr/bin/env python3
from __future__ import annotations
import argparse, pathlib, re, stat, zipfile

def fail(message: str): raise SystemExit(f'archive integrity check failed: {message}')
parser=argparse.ArgumentParser()
parser.add_argument('archive',type=pathlib.Path)
args=parser.parse_args()
archive=args.archive.resolve()
if not archive.is_file() or archive.is_symlink(): fail('archive is missing or linked')
seen=set(); files=0
forbidden_ext={'.iso','.qcow2','.img','.vdi','.vmdk','.ova','.ovf'}
forbidden_parts={'.git','__pycache__','.pytest_cache','node_modules','artifacts','evidence','logs'}
with zipfile.ZipFile(archive) as zf:
    bad=zf.testzip()
    if bad: fail(f'CRC failure: {bad}')
    for info in zf.infolist():
        name=info.filename
        pure=pathlib.PurePosixPath(name.rstrip('/'))
        if not name or name.startswith('/') or '\\' in name or '..' in pure.parts: fail(f'unsafe path: {name!r}')
        if name in seen: fail(f'duplicate path: {name!r}')
        seen.add(name)
        mode=(info.external_attr>>16)&0o177777
        kind=stat.S_IFMT(mode)
        if info.is_dir():
            if kind not in (0,stat.S_IFDIR): fail(f'non-directory mode: {name!r}')
            continue
        if kind not in (0,stat.S_IFREG): fail(f'link or special entry: {name!r}')
        files+=1
        lowered=name.lower()
        if any(part.lower() in forbidden_parts for part in pure.parts): fail(f'forbidden source directory: {name}')
        if pathlib.PurePosixPath(lowered).suffix in forbidden_ext: fail(f'forbidden binary artifact: {name}')
        if any(part.lower() in {'build','dist'} for part in pure.parts) and 'packages' not in pure.parts:
            fail(f'generated build directory: {name}')
if files < 50: fail(f'suspiciously small source archive: files={files}')
print(f'archive integrity checks passed: files={files}')
