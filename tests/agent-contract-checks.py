#!/usr/bin/env python3
from __future__ import annotations
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
agents = (ROOT / 'AGENTS.md').read_text(encoding='utf-8')
claude = (ROOT / 'CLAUDE.md').read_text(encoding='utf-8')
release_process = (ROOT / 'docs/release-process.md').read_text(encoding='utf-8')
vm_readme = (ROOT / 'tests/vm/README.md').read_text(encoding='utf-8')
vm_runner = (ROOT / 'tests/vm/run.sh').read_text(encoding='utf-8')
agents_flat = ' '.join(agents.split())
required = [
    'Project structure', 'Allowed commands', 'Repository root', 'Canonical checkout workflow',
    'Installer invariants',
    'Disk and destructive invariants', 'Package and signing boundaries',
    'Marble and GDM boundaries', 'Required source tests', 'Evidence separation', 'Secrets',
    'Tree-bound results', 'Bounded remediation', 'Product failure', 'Infrastructure retry',
    'Pins and keys', 'Release authorization',
]
for heading in required:
    if heading.lower() not in agents.lower():
        raise SystemExit(f'agent contract check failed: missing section {heading!r}')
if len(claude.splitlines()) > 8 or 'AGENTS.md' not in claude:
    raise SystemExit('agent contract check failed: CLAUDE.md is not a short pointer')
commands = set(re.findall(r'`((?:bash|python3|shellcheck)[^`\n]+)`', agents))
expected = {
    'bash tests/source-tests.sh', 'bash tests/bootstrap-checks.sh',
    'bash tests/static-checks.sh', 'bash tests/function-checks.sh',
    'bash tests/marble-checks.sh', 'bash tests/repository-checks.sh',
    'python3 repository/verify-package-metadata.py', 'python3 maintenance/check-sources.py',
}
if not expected <= commands:
    missing = sorted(expected - commands)
    raise SystemExit(f'agent contract check failed: allowed command list differs: {missing}')

canonical_checkout_markers = (
    'sole persistent local development checkout',
    'additional local Git worktrees',
    'sibling clones',
    'per-cycle source directories',
    'copied or replacement source repositories',
    'switch feature or pull-request branches in place',
    'return this same checkout to `main`',
    'Mandatory ephemeral security boundaries remain permitted',
    'protected GitHub Actions canonical and validation clones',
    'one-use signing input copies',
    'qcow2 disks, OVMF variable stores',
    'They are not development source, must not be edited or committed',
    'must be removed when their bounded stage ends',
)
for marker in canonical_checkout_markers:
    if marker not in agents_flat:
        raise SystemExit(f'agent contract check failed: canonical checkout rule differs: {marker!r}')

remediation_markers = (
    'When continuous remediation is explicitly authorized',
    'Preserve the rejected freeze and its artifacts and evidence unchanged',
    'new pull-request branch in the same canonical checkout',
    'fresh tests, freeze, build, signing and VM evidence for the new identity',
    'Never transfer a PASS to the corrected candidate or replace published bytes or tags',
)


def check_remediation_contract(document: str) -> None:
    normalized = ' '.join(document.split())
    for marker in remediation_markers:
        if marker not in normalized:
            raise ValueError(f'remediation boundary is missing: {marker}')


for document in (agents, release_process):
    check_remediation_contract(document)
    normalized = ' '.join(document.split())
    for marker in remediation_markers:
        try:
            check_remediation_contract(normalized.replace(marker, '', 1))
        except ValueError:
            continue
        raise SystemExit('agent contract check failed: missing remediation boundary was accepted')

for document, markers, label in (
    (release_process, (
        'same canonical checkout',
        'local per-cycle worktrees, sibling clones or copied source repositories',
        'Ephemeral CI, package-build, signing, test and VM isolation remains mandatory',
    ), 'release process'),
    (vm_readme, (
        'same clean frozen canonical checkout',
        'not a copied or per-cycle source checkout',
    ), 'VM documentation'),
    (vm_runner, ('completely clean exact committed canonical checkout',), 'VM runner'),
):
    document_flat = ' '.join(document.split())
    for marker in markers:
        if marker not in document_flat:
            raise SystemExit(f'agent contract check failed: {label} differs: {marker!r}')

UBUNTU_CONTAINER = (
    'container:\n'
    '      image: ubuntu@sha256:'
    '33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517'
)
ARCH_CONTAINER = (
    'container:\n'
    '      image: archlinux:base-devel@sha256:'
    '714acd1eef9ae997d95691b1c5220ada0076185b77857c1813f02de0fa83cf7b'
)
HOSTED_MARKERS = (
    'CI=true GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=github-hosted',
    'ARCH_LINUX_ALLOW_HOSTED_NAMESPACE_DEFERRAL=github-hosted-container-v1',
)
CANONICAL_SOURCE = '/opt/arch-linux-canonical'
PROTECTED_WORKDIR = f'working-directory: {CANONICAL_SOURCE}'


def demand(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def block(text: str, start: str, end: str | None) -> str:
    demand(text.count(start) == 1, f'workflow step count differs: {start}')
    tail = text.split(start, 1)[1]
    if end is None:
        return tail
    demand(tail.count(end) >= 1, f'workflow next step is absent: {end}')
    return tail.split(end, 1)[0]


def ordered(text: str, markers: tuple[str, ...], label: str) -> None:
    positions = [text.find(marker) for marker in markers]
    demand(all(position >= 0 for position in positions), f'{label} step is absent')
    demand(positions == sorted(positions) and len(set(positions)) == len(positions),
           f'{label} step order differs')


def require_unprivileged_git(text: str, repo: str, user: str, label: str) -> None:
    marker = f'git -C "{repo}"'
    commands: list[str] = []
    current: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        current.append(line)
        if not line.endswith('\\'):
            commands.append(' '.join(current))
            current = []
    if current:
        commands.append(' '.join(current))
    matched = [command for command in commands if marker in command]
    demand(matched, f'{label} mutable Git read is absent')
    demand(all(f'runuser -u {user} -- env -i' in command for command in matched),
           f'{label} mutable Git is read by root')


def reject_global_wildcard(text: str, label: str) -> None:
    for literal in ('safe.directory=*', 'safe.directory "*"', "safe.directory '*'",
                    'safe.directory=\\*'):
        demand(literal not in text, f'{label} uses wildcard safe.directory')


def validate_ci(text: str) -> None:
    demand(text.count(UBUNTU_CONTAINER) == 1, 'CI pinned Ubuntu container differs')
    steps = (
        '      - name: Install check dependencies\n',
        '      - name: Check out source\n',
        '      - name: Prepare unprivileged source checker\n',
        '      - name: Run required source checks\n',
        '      - name: Check whitespace\n',
    )
    ordered(text, steps, 'CI')
    install_step = block(text, steps[0], steps[1])
    demand('sudo' not in install_step, 'CI container dependency step uses sudo')
    for literal in ('file git gnupg libarchive-tools', 'python3 util-linux',
                    'install -m0755 -o root -g root'):
        demand(literal in install_step, f'CI dependency contract differs: {literal}')
    prepare_step = block(text, steps[2], steps[3])
    for literal in (
        f'canonical_source={CANONICAL_SOURCE}',
        'test -d /opt', 'test ! -L /opt',
        'test ! -e "${canonical_source}"', 'test ! -L "${canonical_source}"',
        'git clone --no-local --no-hardlinks --no-checkout --',
        '"${GITHUB_WORKSPACE}" "${canonical_source}"',
        'git -C "${canonical_source}" checkout --detach "${canonical_commit}"',
        'git -C "${canonical_source}" remote remove origin',
        'test ! -e "${canonical_source}/.git/objects/info/alternates"',
        'test ! -L "${canonical_source}/.git/objects/info/alternates"',
        'find "${canonical_source}" -type f -links +1',
        'chown -R root:root -- "${canonical_source}"',
        'chmod -R go-w -- "${canonical_source}"',
        '\\( ! -user root -o ! -group root \\)',
        'find "${canonical_source}" -perm /022',
        'useradd --create-home --shell /bin/bash source-checker',
        'stat --file-system --format=%t', 'test -f /.dockerenv', 'test ! -L /.dockerenv',
        'source_parent="${workspace_parent}/arch-linux-source-validation"',
        'source_temp="${workspace_parent}/arch-linux-source-temp"',
        'install -d -m0700 -o source-checker -g source-checker',
        'current="${canonical_source}"', 'while :; do',
        'test "${current}" = / && break',
        'writable_path="$(runuser -u source-checker --',
        'find "${canonical_source}" -writable -print -quit)',
        'git config --global --add safe.directory "${canonical_source}"',
        'git config --global --add safe.directory "${canonical_source}/.git"',
        'git clone --no-local --no-hardlinks',
        '--no-checkout -- "${canonical_source}" "${source_parent}/repo"',
        'rm -f -- "${checker_home}/.gitconfig"',
        'checkout --detach "${canonical_commit}"',
        'runuser -u source-checker -- test ! -e',
        'runuser -u source-checker -- test ! -L',
        'runuser -u source-checker --',
        'find "${source_parent}/repo" -type f -links +1',
    ):
        demand(literal in prepare_step, f'CI unprivileged setup differs: {literal}')
    demand(prepare_step.count('stat --file-system --format=%t') >= 3,
           'CI source parent and temp are not both bound to ext4')
    demand(prepare_step.count(')" = ef53') >= 3,
           'CI source parent and temp do not require ext4')
    demand(prepare_step.count('git clone --no-local --no-hardlinks') == 2,
           'CI does not use two independent no-hardlink clones')
    demand(prepare_step.find('"${GITHUB_WORKSPACE}" "${canonical_source}"') <
           prepare_step.find('chown -R root:root -- "${canonical_source}"') <
           prepare_step.find('useradd --create-home --shell /bin/bash source-checker') <
           prepare_step.find('"${canonical_source}" "${source_parent}/repo"'),
           'CI canonical source is not sealed before unprivileged execution')
    after_useradd = prepare_step.split(
        'useradd --create-home --shell /bin/bash source-checker', 1)[1]
    demand('--no-checkout -- "${GITHUB_WORKSPACE}"' not in after_useradd,
           'CI validation clone returns to untrusted checkout')
    demand(re.search(r'chown[^\n]*source-checker[^\n]*canonical_source', prepare_step) is None,
           'CI grants protected source ownership to source checker')
    demand('safe.directory="${source_parent}/repo"' not in prepare_step,
           'CI root trusts the checker-owned source')
    require_unprivileged_git(
        prepare_step, '${source_parent}/repo', 'source-checker', 'CI')
    reject_global_wildcard(prepare_step, 'CI')
    demand(prepare_step.count('rm -f -- "${checker_home}/.gitconfig"') == 1 and
           prepare_step.count('test ! -e "${checker_home}/.gitconfig"') >= 2 and
           prepare_step.count('test ! -L "${checker_home}/.gitconfig"') >= 2,
           'CI temporary source trust is not removed')
    source_step = block(text, steps[3], steps[4])
    for literal in (
        PROTECTED_WORKDIR,
        'runuser -u source-checker -- env -i', *HOSTED_MARKERS,
        'RUNNER_TEMP="$(dirname -- "${GITHUB_WORKSPACE}")/arch-linux-source-temp"',
        'arch-linux-source-validation/repo/tests/source-tests.sh',
    ):
        demand(literal in source_step, f'CI source invocation differs: {literal}')
    demand('bash "${GITHUB_WORKSPACE}' not in source_step,
           'CI executes source from the untrusted checkout')
    whitespace_step = block(text, steps[4], None)
    for literal in (
        PROTECTED_WORKDIR, f'canonical_source={CANONICAL_SOURCE}',
        'runuser -u source-checker -- env -i',
        'git -C "${source_root}" diff --check',
        'git -C "${canonical_source}"',
        'current="${canonical_source}"', 'while :; do',
        'test "${current}" = / && break',
        'find "${canonical_source}" -writable -print -quit',
        'find "${canonical_source}" -perm /022',
    ):
        demand(literal in whitespace_step, f'CI whitespace contract differs: {literal}')
    demand('safe.directory="${source_root}"' not in whitespace_step and
           'safe.directory="${GITHUB_WORKSPACE}"' not in whitespace_step,
           'CI root trusts mutable or untrusted source during readback')
    require_unprivileged_git(
        whitespace_step, '${source_root}', 'source-checker', 'CI readback')


def validate_packages(text: str) -> None:
    build_job = text.split('\n  readback:\n', 1)[0]
    demand(build_job.count(ARCH_CONTAINER) == 1, 'package build container differs')
    steps = (
        '      - name: Install build dependencies\n',
        '      - name: Check out source\n',
        '      - name: Require exact frozen source\n',
        '      - name: Validate source before package execution\n',
        '      - name: Build as a temporary unprivileged user\n',
        '      - name: Record canonical provenance\n',
    )
    ordered(build_job, steps, 'package build')
    exact_step = block(build_job, steps[2], steps[3])
    for literal in (
        f'canonical_source={CANONICAL_SOURCE}',
        'test -d /opt', 'test ! -L /opt',
        'git clone --no-local --no-hardlinks --no-checkout --',
        '"${GITHUB_WORKSPACE}" "${canonical_source}"',
        'checkout --detach "${SOURCE_COMMIT}"',
        'git -C "${canonical_source}" remote remove origin',
        'test ! -e "${canonical_source}/.git/objects/info/alternates"',
        'test ! -L "${canonical_source}/.git/objects/info/alternates"',
        'find "${canonical_source}" -type f -links +1',
        'chown -R root:root -- "${canonical_source}"',
        'chmod -R go-w -- "${canonical_source}"',
        'find "${canonical_source}" -perm /022',
    ):
        demand(literal in exact_step, f'package canonicalization differs: {literal}')
    demand('useradd ' not in exact_step,
           'package user exists before protected source canonicalization')
    source_step = block(build_job, steps[3], steps[4])
    for literal in (
        PROTECTED_WORKDIR, f'canonical_source={CANONICAL_SOURCE}',
        'useradd --create-home --shell /bin/bash package-builder',
        'stat --file-system --format=%t', 'test -f /.dockerenv', 'test ! -L /.dockerenv',
        'source_parent="${workspace_parent}/arch-linux-source-validation"',
        'source_temp="${workspace_parent}/arch-linux-source-temp"',
        'install -d -m0700 -o package-builder -g package-builder',
        'current="${canonical_source}"', 'while :; do',
        'test "${current}" = / && break',
        'writable_path="$(runuser -u package-builder --',
        'find "${canonical_source}" -writable -print -quit)',
        'git config --global --add safe.directory "${canonical_source}"',
        'git config --global --add safe.directory "${canonical_source}/.git"',
        'git clone --no-local --no-hardlinks',
        '--no-checkout -- "${canonical_source}" "${source_parent}/repo"',
        'rm -f -- "${builder_home}/.gitconfig"',
        'checkout --detach "${SOURCE_COMMIT}"',
        'runuser -u package-builder -- test ! -e',
        'runuser -u package-builder -- test ! -L',
        'runuser -u package-builder --',
        'find "${source_parent}/repo" -type f -links +1',
        'runuser -u package-builder -- env -i', *HOSTED_MARKERS,
        'RUNNER_TEMP="${source_temp}"', 'bash "${source_parent}/repo/tests/source-tests.sh"',
    ):
        demand(literal in source_step, f'package source invocation differs: {literal}')
    demand(source_step.count('stat --file-system --format=%t') >= 3,
           'package source parent and temp are not both bound to ext4')
    demand(source_step.count(')" = ef53') >= 3,
           'package source parent and temp do not require ext4')
    demand('--no-checkout -- "${GITHUB_WORKSPACE}"' not in source_step,
           'package validation clone returns to untrusted checkout')
    demand(re.search(r'chown[^\n]*package-builder[^\n]*canonical_source', source_step) is None,
           'package workflow grants protected source ownership to builder')
    demand('safe.directory="${source_parent}/repo"' not in source_step,
           'package root trusts the builder-owned source')
    require_unprivileged_git(
        source_step, '${source_parent}/repo', 'package-builder', 'package validation')
    reject_global_wildcard(source_step, 'package validation')
    demand(source_step.count('rm -f -- "${builder_home}/.gitconfig"') == 1 and
           source_step.count('test ! -e "${builder_home}/.gitconfig"') >= 2 and
           source_step.count('test ! -L "${builder_home}/.gitconfig"') >= 2,
           'package temporary source trust is not removed')
    build_step = block(build_job, steps[4], steps[5])
    demand('useradd ' not in build_step, 'package builder is recreated after source validation')
    for literal in (
        PROTECTED_WORKDIR, f'canonical_source={CANONICAL_SOURCE}',
        'check_canonical_source() {', 'runuser -u package-builder -- env -i',
        'bash "${canonical_source}/repository/build-packages.sh"',
        'bash "${canonical_source}/tests/package-checks.sh"',
        'find "${canonical_source}" -writable -print -quit',
        'find "${canonical_source}" -type f -links +1',
        'find "${canonical_source}" -perm /022',
        'current="${canonical_source}"', 'while :; do',
        'test "${current}" = / && break',
    ):
        demand(literal in build_step, f'package build boundary differs: {literal}')
    demand('GITHUB_WORKSPACE' not in build_step,
           'package build returns to the untrusted checkout')
    demand(build_step.count('check_canonical_source') == 4,
           'canonical source is not checked before/after build and package verification')
    demand(build_step.count('test ! -e "${builder_home}/.gitconfig"') == 2 and
           build_step.count('test ! -L "${builder_home}/.gitconfig"') == 2,
           'temporary clone trust is not absent before and after build')
    provenance_step = block(build_job, steps[5], None)
    demand(PROTECTED_WORKDIR in provenance_step,
           'package provenance does not start from protected canonical source')


ci = (ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8')
packages = (ROOT / '.github/workflows/packages.yml').read_text(encoding='utf-8')
try:
    validate_ci(ci)
    validate_packages(packages)
except ValueError as error:
    raise SystemExit(f'agent contract check failed: {error}') from error

mutations = (
    ('CI container pin', validate_ci, ci, UBUNTU_CONTAINER,
     'container:\n      image: ubuntu:24.04', 1),
    ('CI protected source under writable runner mount', validate_ci, ci,
     f'canonical_source={CANONICAL_SOURCE}', 'canonical_source=/__w/arch-linux-canonical', None),
    ('CI unprivileged execution', validate_ci, ci,
     'runuser -u source-checker -- env -i', 'env -i', None),
    ('CI hosted marker', validate_ci, ci, HOSTED_MARKERS[1],
     'ARCH_LINUX_ALLOW_HOSTED_NAMESPACE_DEFERRAL=', 1),
    ('CI canonical ownership', validate_ci, ci, 'chown -R root:root -- "${canonical_source}"',
     'chown -R source-checker:source-checker -- "${canonical_source}"', 1),
    ('CI first non-local clone', validate_ci, ci,
     'clone --no-local --no-hardlinks', 'clone --no-hardlinks', 1),
    ('CI first no-hardlink clone', validate_ci, ci,
     'clone --no-local --no-hardlinks --no-checkout',
     'clone --no-local --no-checkout', 1),
    ('CI validation source', validate_ci, ci,
     '--no-checkout -- "${canonical_source}" "${source_parent}/repo"',
     '--no-checkout -- "${GITHUB_WORKSPACE}" "${source_parent}/repo"', 1),
    ('CI ancestor root', validate_ci, ci,
     'current="${canonical_source}"', 'current="${GITHUB_WORKSPACE}"', 1),
    ('CI inclusive ancestor walk', validate_ci, ci,
     'test "${current}" = / && break', 'test "${current}" = / && :', 1),
    ('CI ext4 validation', validate_ci, ci,
     ')" = ef53', ')" = 794c7630', 1),
    ('CI protected working directory', validate_ci, ci,
     PROTECTED_WORKDIR, 'working-directory: ${{ github.workspace }}', 1),
    ('CI wildcard trust', validate_ci, ci,
     'safe.directory "${canonical_source}"', 'safe.directory "*"', 1),
    ('package unprivileged execution', validate_packages, packages,
     'runuser -u package-builder -- env -i', 'env -i', None),
    ('package hosted identity markers', validate_packages, packages, HOSTED_MARKERS[0],
     'CI=true GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted', 1),
    ('package hosted deferral marker', validate_packages, packages, HOSTED_MARKERS[1],
     'ARCH_LINUX_ALLOW_HOSTED_NAMESPACE_DEFERRAL=', 1),
    ('package protected source under writable runner mount', validate_packages, packages,
     f'canonical_source={CANONICAL_SOURCE}', 'canonical_source=/__w/arch-linux-canonical', None),
    ('package canonical ownership', validate_packages, packages,
     'chown -R root:root -- "${canonical_source}"',
     'chown -R package-builder:package-builder -- "${canonical_source}"', 1),
    ('package first non-local clone', validate_packages, packages,
     'clone --no-local --no-hardlinks', 'clone --no-hardlinks', 1),
    ('package first no-hardlink clone', validate_packages, packages,
     'clone --no-local --no-hardlinks --no-checkout',
     'clone --no-local --no-checkout', 1),
    ('package validation source', validate_packages, packages,
     '--no-checkout -- "${canonical_source}" "${source_parent}/repo"',
     '--no-checkout -- "${GITHUB_WORKSPACE}" "${source_parent}/repo"', 1),
    ('package canonical build path', validate_packages, packages,
     'bash "${canonical_source}/repository/build-packages.sh"',
     'bash "${GITHUB_WORKSPACE}/repository/build-packages.sh"', 1),
    ('package verifier path', validate_packages, packages,
     'bash "${canonical_source}/tests/package-checks.sh"',
     'bash "${GITHUB_WORKSPACE}/tests/package-checks.sh"', 1),
    ('package protected working directory', validate_packages, packages,
     PROTECTED_WORKDIR, 'working-directory: ${{ github.workspace }}', 1),
    ('package inclusive ancestor walk', validate_packages, packages,
     'test "${current}" = / && break', 'test "${current}" = / && :', 1),
    ('package ext4 validation', validate_packages, packages,
     ')" = ef53', ')" = 794c7630', 1),
    ('package canonical nonwritability', validate_packages, packages,
     'find "${canonical_source}" -writable -print -quit)',
     'find "${canonical_source}" -readable -print -quit)', None),
)
for label, validator, original, before, after, count in mutations:
    mutated = original.replace(before, after) if count is None else original.replace(before, after, count)
    demand(mutated != original, 'workflow contract mutation was not applied')
    try:
        validator(mutated)
    except ValueError:
        continue
    raise SystemExit(f'agent contract check failed: workflow mutation was accepted: {label}')

print('agent contract checks passed')
