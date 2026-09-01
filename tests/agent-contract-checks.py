#!/usr/bin/env python3
from __future__ import annotations
import pathlib, re
ROOT=pathlib.Path(__file__).resolve().parent.parent
agents=(ROOT/'AGENTS.md').read_text(encoding='utf-8')
claude=(ROOT/'CLAUDE.md').read_text(encoding='utf-8')
required=[
 'Project structure','Allowed commands','Repository root','Installer invariants',
 'Disk and destructive invariants','Package and signing boundaries','Marble and GDM boundaries',
 'Required source tests','Evidence separation','Secrets','Tree-bound results',
 'Bounded remediation','Product failure','Infrastructure retry','Pins and keys','Release authorization',
]
for heading in required:
    if heading.lower() not in agents.lower():
        raise SystemExit(f'agent contract check failed: missing section {heading!r}')
if len(claude.splitlines())>8 or 'AGENTS.md' not in claude:
    raise SystemExit('agent contract check failed: CLAUDE.md is not a short pointer')
commands=set(re.findall(r'`((?:bash|python3|shellcheck)[^`\n]+)`',agents))
expected={
 'bash tests/source-tests.sh','bash tests/bootstrap-checks.sh','bash tests/static-checks.sh',
 'bash tests/function-checks.sh','bash tests/marble-checks.sh','bash tests/repository-checks.sh',
 'python3 repository/verify-package-metadata.py','python3 maintenance/check-sources.py',
}
if not expected <= commands:
    raise SystemExit(f'agent contract check failed: allowed command list differs: {sorted(expected-commands)}')
for path in (ROOT/'.github/workflows').glob('*.yml'):
    text=path.read_text(encoding='utf-8')
    if path.name=='ci.yml' and 'bash tests/source-tests.sh' not in text:
        raise SystemExit('agent contract check failed: CI does not execute the normative source command')
print('agent contract checks passed')
