#!/usr/bin/env python3
from __future__ import annotations
import hashlib, pathlib, subprocess, sys, tempfile
ROOT=pathlib.Path(__file__).resolve().parent.parent
checker=ROOT/'maintenance/check-arch-iso.py'
fixtures=ROOT/'tests/fixtures/arch-releases'
state=ROOT/'maintenance/accepted-arch-iso.json'
sources=ROOT/'maintenance/sources.json'

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
before={path:digest(path) for path in (state,sources)}
subprocess.run([sys.executable,str(ROOT/'maintenance/check-sources.py')],check=True,stdout=subprocess.DEVNULL)
unchanged=subprocess.run([sys.executable,str(checker),'--metadata',str(fixtures/'unchanged.json')],check=True,text=True,stdout=subprocess.PIPE).stdout
if 'Arch ISO detector: unchanged' not in unchanged: raise SystemExit('maintenance check failed: unchanged fixture differs')
new=subprocess.run([sys.executable,str(checker),'--metadata',str(fixtures/'new.json')],check=True,text=True,stdout=subprocess.PIPE).stdout
if 'CHANGE DETECTED' not in new or 'automatic_trust_update=forbidden' not in new: raise SystemExit('maintenance check failed: new fixture differs')
for name in ('duplicate.json','malformed.json'):
    result=subprocess.run([sys.executable,str(checker),'--metadata',str(fixtures/name)],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if result.returncode==0: raise SystemExit(f'maintenance check failed: negative fixture accepted: {name}')
result=subprocess.run([sys.executable,str(checker),'--metadata',str(fixtures/'source-mismatch.json'),'--source-url','https://example.invalid/api/v1/releng/releases/'],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if result.returncode==0: raise SystemExit('maintenance check failed: non-authoritative source accepted')
after={path:digest(path) for path in (state,sources)}
if before!=after: raise SystemExit('maintenance check failed: advisory checks changed accepted state')
print('maintenance checks passed')
