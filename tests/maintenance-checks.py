#!/usr/bin/env python3
from __future__ import annotations
import datetime, hashlib, json, os, pathlib, runpy, subprocess, sys, tempfile
from unittest import mock
ROOT=pathlib.Path(__file__).resolve().parent.parent
checker=ROOT/'maintenance/check-arch-iso.py'
fixtures=ROOT/'tests/fixtures/arch-releases'
state=ROOT/'maintenance/accepted-arch-iso.json'
sources=ROOT/'maintenance/sources.json'

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
before={path:digest(path) for path in (state,sources)}
subprocess.run([sys.executable,str(ROOT/'maintenance/check-sources.py')],check=True,stdout=subprocess.DEVNULL)
iso = runpy.run_path(str(checker))
iso['parse_accepted_state'](state.read_bytes())  # Validate the actual, advancing accepted baseline.
# Detector fixtures keep their own historical baseline, independent of later accepted ISOs.
baseline = iso['parse_official_metadata']((fixtures/'unchanged.json').read_bytes(), iso['OFFICIAL_METADATA_SOURCE'])
with tempfile.TemporaryDirectory(prefix='maintenance-iso-fixture-') as temporary:
    fixture_state = pathlib.Path(temporary)/'accepted.json'
    fixture_state.write_text(json.dumps({
        'schema': 1, 'source': baseline.source, 'version': baseline.version,
        'releaseDate': baseline.release_date, 'isoName': baseline.iso_name,
        'isoUrl': baseline.iso_url, 'sha256': baseline.sha256,
    }))
    def check_iso(name, *extra):
        return subprocess.run([sys.executable, str(checker), '--state', str(fixture_state),
                               '--metadata', str(fixtures/name), *extra],
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    unchanged = check_iso('unchanged.json')
    assert unchanged.returncode == 0 and 'Arch ISO detector: unchanged' in unchanged.stdout
    new = check_iso('new.json')
    assert new.returncode == 0 and 'CHANGE DETECTED' in new.stdout and 'automatic_trust_update=forbidden' in new.stdout
    for name in ('duplicate.json', 'malformed.json'):
        assert check_iso(name).returncode != 0, f'negative fixture accepted: {name}'
    assert check_iso('source-mismatch.json', '--source-url',
                     'https://example.invalid/api/v1/releng/releases/').returncode != 0
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

# Exercise actual issue updates at the HTTP boundary, including lost-response recovery.
with tempfile.TemporaryDirectory(prefix='maintenance-key-notice-') as temporary:
    report_path = pathlib.Path(temporary)/'key.json'
    remote = {'body': drift_body, 'comments': [], 'lose_post_response': False}
    calls = []
    def fake_request(method, url, token, payload=None):
        assert token == 'fixture-only'
        calls.append((method, url))
        if method == 'GET' and '/comments?' in url:
            page = int(url.rsplit('page=', 1)[1])
            return remote['comments'][(page-1)*100:page*100]
        if method == 'GET':
            return [{'number': 24, 'title': advisory['TITLE'], 'body': remote['body']}]
        if method == 'POST' and url.endswith('/comments'):
            remote['comments'].append({'user': {'login': 'github-actions[bot]'}, **payload})
            if remote['lose_post_response']:
                remote['lose_post_response'] = False
                raise OSError('fixture: POST succeeded but response was lost')
            return {}
        if method == 'PATCH':
            assert 'state' not in payload  # Unresolved monthly findings must stay open.
            remote['body'] = payload['body']
            return {}
        raise AssertionError((method, url))
    def update_key(report):
        report_path.write_text(json.dumps(report))
        with mock.patch.dict(advisory['main'].__globals__, {'request': fake_request}), \
             mock.patch.dict(os.environ, {'GITHUB_TOKEN': 'fixture-only', 'GITHUB_REPOSITORY': 'example/test'}), \
             mock.patch.object(sys, 'argv', ['updater', '--key-only', '--key-report', str(report_path)]):
            advisory['main']()
    update_key(healthy)
    assert not remote['comments']
    update_key(due)
    assert len(remote['comments']) == 1 and '2027-08-24' in remote['comments'][-1]['body']
    calls.clear()
    update_key(due | {'remainingDays': 179})
    assert len(remote['comments']) == 1 and all(method == 'GET' for method, _ in calls)
    update_key(healthy)
    assert len(remote['comments']) == 2 and 'Unresolved package drift.' in remote['body']
    update_key({'status': 'error', 'automaticChanges': False})
    assert len(remote['comments']) == 3
    urgent = due | {'status': 'urgent'}
    remote['lose_post_response'] = True
    try:
        update_key(urgent)
    except OSError:
        pass
    else:
        raise AssertionError('lost POST response was hidden')
    assert len(remote['comments']) == 4 and '- Status: `error`' in remote['body']
    remote['comments'][:0] = [{'user': {'login': 'someone'}, 'body': 'ordinary comment'}]*100
    calls.clear()
    update_key(urgent)
    assert len(remote['comments']) == 104 and '- Status: `urgent`' in remote['body']
    assert any('page=2' in url for _, url in calls)
    assert not any(method == 'POST' for method, _ in calls)
    # A notice-shaped user comment cannot suppress the workflow's notification.
    remote['comments'][-1]['user']['login'] = 'someone'
    remote['body'] = drift_body
    update_key(urgent)
    assert len(remote['comments']) == 105

# Actual monitor functions: preserve version granularity and resolve exact tags.
monitor = runpy.run_path(str(ROOT/'maintenance/check-sources.py'))
version = monitor['arch_version']
arch = {'epoch': 1, 'pkgver': '50.4', 'pkgrel': '1'}
assert version(arch, '1:50.4-1') == '1:50.4-1'
assert version(arch | {'pkgrel': '2'}, '1:50.4-1') != '1:50.4-1'
assert version(arch | {'epoch': 2}, '1:50.4-1') != '1:50.4-1'
assert version(arch, '50.4-1') == '1:50.4-1'  # Epoch changes are not hidden.
assert version(arch, '50.4') == '50.4'  # Existing pkgver-only contract.
assert version({'epoch': 0, 'pkgver': '50.3', 'pkgrel': '1'}, '50.2') == '50.3'
tag_item = {'id': 'tagged', 'git': 'https://example.invalid/source.git',
            'acceptedTag': '50.4', 'acceptedCommit': 'a'*40, 'impact': 'manual review'}
resolve = monitor['upstream_commit']
tag_ref = 'refs/tags/50.4'
for response, expected in (
    (f"{'a'*40}\t{tag_ref}\n", 'a'*40),
    (f"{'b'*40}\t{tag_ref}\n{'a'*40}\t{tag_ref}^{{}}\n", 'a'*40),
    (f"{'c'*40}\t{tag_ref}\n", 'c'*40),  # A moved lightweight tag stays visible.
):
    with mock.patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, response)) as query:
        assert resolve(tag_item) == expected
        assert query.call_args.args[0][-2:] == [tag_ref, tag_ref+'^{}']
for response in ('', f"{'a'*40}\tHEAD\n", f"{'a'*40}\t{tag_ref}\n{'b'*40}\t{tag_ref}\n"):
    with mock.patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, response)):
        try:
            resolve(tag_item)
        except ValueError:
            pass
        else:
            raise AssertionError('invalid/missing upstream ref was accepted')
head_item = dict(tag_item)
del head_item['acceptedTag']
with mock.patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess(
        [], 0, f"{'a'*40}\tHEAD\n{'b'*40}\trefs/remotes/origin/HEAD\n")) as query:
    assert resolve(head_item) == 'a'*40 and query.call_args.args[0][-1] == 'HEAD'
network = monitor['network_findings']
document = {'archPackages': [], 'tools': [], 'gnomeExtensions': [], 'aurPins': [],
            'upstreams': [tag_item | {'source': 'https://example.invalid/releases/latest'}]}
with mock.patch.dict(network.__globals__, {'upstream_commit': lambda item: 'a'*40,
                                         'fetch_json': lambda url: {'tag_name': 'v50.5'}}):
    findings = network(document)
    assert len(findings) == 1 and findings[0]['id'] == 'tagged:release' and findings[0]['detected'] == '50.5'
assert advisory['body_for']({'findings': []}, 'mismatch', 'unchanged').count('both unsigned builds verified') == 1
assert 'could not be determined' in advisory['body_for']({'findings': []}, 'error', 'unchanged')

# Exercise the real exclusive workspace allocator without running any PKGBUILD.
with tempfile.TemporaryDirectory(prefix='maintenance-build-path-') as temporary:
    base = pathlib.Path(temporary)
    output = base/'unsigned'
    def allocate(path):
        env = dict(os.environ, WORK_DIR=str(path) if path else '', RUNNER_TEMP=str(base))
        return subprocess.run(['bash', '-c', 'source "$1"; create_build_workspace "$2"',
                               'workspace-test', str(ROOT/'repository/build-packages.sh'), str(output)],
                              env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    fixed = base/'canonical-work'
    result = allocate(fixed)
    assert result.returncode == 0 and result.stdout.strip() == str(fixed)
    assert fixed.stat().st_mode & 0o777 == 0o700
    marker = fixed/'keep'
    marker.write_text('owned by fixture\n')
    assert allocate(fixed).returncode != 0 and marker.read_text() == 'owned by fixture\n'
    linked = base/'linked'
    linked.symlink_to(fixed)
    for path in (linked, marker, ROOT/'forbidden-work', output, output/'nested'):
        assert allocate(path).returncode != 0
    assert not (ROOT/'forbidden-work').exists() and not output.exists()
    random_a, random_b = allocate(None), allocate(None)
    assert random_a.returncode == random_b.returncode == 0
    assert random_a.stdout != random_b.stdout

# Compare's verifier failure must not be reported as a verified mismatch.
# The stub isolates status routing; real unsigned artifacts are checked separately.
with tempfile.TemporaryDirectory(prefix='maintenance-compare-') as temporary:
    base = pathlib.Path(temporary)
    comparator = base/'compare-package-builds.sh'
    comparator.write_bytes((ROOT/'repository/compare-package-builds.sh').read_bytes())
    verifier = base/'verify-unsigned-build.sh'
    verifier.write_text('#!/usr/bin/env bash\n[ ! -e "$1/reject" ]\n')
    verifier.chmod(0o700)
    a, b = base/'a', base/'b'
    for directory in (a, b):
        directory.mkdir()
        (directory/'UNSIGNED-SHA256SUMS').write_text('same bytes\n')
        (directory/'BUILD-METADATA.json').write_text('{}\n')
    def compare():
        return subprocess.run(['bash', str(comparator), str(a), str(b)],
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert compare().returncode == 0
    (b/'UNSIGNED-SHA256SUMS').write_text('different bytes\n')
    assert compare().returncode == 1
    (b/'UNSIGNED-SHA256SUMS').write_text('same bytes\n')
    (b/'BUILD-METADATA.json').write_text('{"different":"provenance"}\n')
    assert compare().returncode == 1
    (b/'reject').touch()
    result = compare()
    assert result.returncode == 2 and 'ADVISORY_ERROR' in result.stderr

workflow = (ROOT/'.github/workflows/maintenance.yml').read_text()
assert "- cron: '17 4 1 * *'" in workflow and "- cron: '41 5 * * *'" in workflow
for job in ('source-monitor', 'reproducibility'):
    assert f"  {job}:\n    if: github.event.schedule != '41 5 * * *'" in workflow
assert 'group: maintenance-advisory' in workflow and '--key-report' in workflow
assert "steps.compare.outputs.status || 'error'" in workflow and '1) status=mismatch' in workflow
for name in ('maintenance.yml', 'packages.yml'):
    assert 'WORK_DIR=/tmp/arch-linux-canonical-work' in (ROOT/'.github/workflows'/name).read_text()
print('maintenance checks passed')
