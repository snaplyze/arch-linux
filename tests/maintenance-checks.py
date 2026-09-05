#!/usr/bin/env python3
from __future__ import annotations
import datetime, hashlib, json, pathlib, runpy, subprocess, sys, tempfile
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

lifetime = runpy.run_path(str(ROOT/'maintenance/check-key-lifetime.py'))
primary, signing, expiry, certificate_digest = lifetime['inspect_public_trust']()
public_before = digest(ROOT/'repository/trust/arch-linux.gpg')
assert certificate_digest == public_before
day = 86400
for remaining, expected in (
    (211*day, 'healthy'), (210*day, 'prepare-renewal'), (180*day, 'renewal-due'),
    (90*day, 'urgent'), (30*day, 'critical'), (1, 'critical'), (0, 'expired'), (-day, 'expired'),
):
    report = lifetime['lifetime_report'](primary, signing, expiry, certificate_digest, expiry-remaining)
    assert report['status'] == expected and report['automaticChanges'] is False
    assert datetime.datetime.fromisoformat(report['renewalStartsAt']).timestamp() == expiry-180*day
assert digest(ROOT/'repository/trust/arch-linux.gpg') == public_before
with tempfile.TemporaryDirectory(prefix='maintenance-lifetime-check-') as temporary:
    report_path = pathlib.Path(temporary)/'report.json'
    subprocess.run([sys.executable, '-B', str(ROOT/'maintenance/check-key-lifetime.py'),
                    '--report', str(report_path)], check=True, stdout=subprocess.DEVNULL)
    assert json.loads(report_path.read_text())['certificateSha256'] == public_before

advisory = runpy.run_path(str(ROOT/'maintenance/update-advisory-issue.py'))
healthy = {'status': 'healthy', 'automaticChanges': False}
due = {'status': 'renewal-due', 'automaticChanges': False, 'expiresAt': '2027-08-24',
       'renewalStartsAt': '2027-02-25', 'signingFingerprint': signing}
combine = advisory['combined_body']
body, clean = combine('', healthy, 'Monthly check passed.\n', True)
assert clean
due_body, clean = combine(body, due, None)
assert not clean and 'Monthly check passed.' in due_body and 'renewal-due' in due_body
renewed_body, clean = combine(due_body, healthy, None)
assert clean and 'renewal-due' not in renewed_body
drift_body, clean = combine('', healthy, 'Unresolved package drift.\n', False)
assert not clean
assert combine(drift_body, due, None)[1] is False
body, clean = combine(drift_body, healthy, None)
assert not clean and 'Unresolved package drift.' in body
assert combine(body, {'status': 'error'}, None)[1] is False
assert combine('', healthy, None)[1] is False  # Unknown monthly state is not fabricated as PASS.

workflow = (ROOT/'.github/workflows/maintenance.yml').read_text()
assert "- cron: '17 4 1 * *'" in workflow and "- cron: '41 5 * * *'" in workflow
for job in ('source-monitor', 'reproducibility'):
    assert f"  {job}:\n    if: github.event.schedule != '41 5 * * *'" in workflow
assert 'group: maintenance-advisory' in workflow and '--key-report' in workflow
print('maintenance checks passed')
