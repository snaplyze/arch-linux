#!/usr/bin/env python3
from __future__ import annotations
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
agents = (ROOT / 'AGENTS.md').read_text(encoding='utf-8')
claude = (ROOT / 'CLAUDE.md').read_text(encoding='utf-8')
required = [
    'Project structure', 'Allowed commands', 'Repository root', 'Installer invariants',
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
        'useradd --create-home --shell /bin/bash source-checker',
        'stat --file-system --format=%t', 'test -f /.dockerenv', 'test ! -L /.dockerenv',
        'source_parent="${workspace_parent}/arch-linux-source-validation"',
        'source_temp="${workspace_parent}/arch-linux-source-temp"',
        'chown -R root:root -- "${GITHUB_WORKSPACE}"',
        'chmod -R go-w -- "${GITHUB_WORKSPACE}"',
        'install -d -m0700 -o source-checker -g source-checker',
        'writable_path="$(runuser -u source-checker --',
        'find "${GITHUB_WORKSPACE}" -writable -print -quit)',
        'git config --global --add safe.directory "${GITHUB_WORKSPACE}"',
        'git config --global --add safe.directory "${GITHUB_WORKSPACE}/.git"',
        'clone --no-local --no-hardlinks', '--no-checkout -- "${GITHUB_WORKSPACE}"',
        'rm -f -- "${checker_home}/.gitconfig"',
        'checkout --detach "${canonical_commit}"',
        'test ! -e "${source_parent}/repo/.git/objects/info/alternates"',
        'test ! -L "${source_parent}/repo/.git/objects/info/alternates"',
        'find "${source_parent}/repo" -type f -links +1',
    ):
        demand(literal in prepare_step, f'CI unprivileged setup differs: {literal}')
    demand(prepare_step.count('stat --file-system --format=%t') >= 3,
           'CI source parent and temp are not both bound to ext4')
    demand(re.search(r'chown[^\n]*source-checker[^\n]*GITHUB_WORKSPACE', prepare_step) is None,
           'CI grants canonical checkout ownership to source checker')
    source_step = block(text, steps[3], steps[4])
    for literal in (
        'runuser -u source-checker -- env -i', *HOSTED_MARKERS,
        'RUNNER_TEMP="$(dirname -- "${GITHUB_WORKSPACE}")/arch-linux-source-temp"',
        'arch-linux-source-validation/repo/tests/source-tests.sh',
    ):
        demand(literal in source_step, f'CI source invocation differs: {literal}')
    whitespace_step = block(text, steps[4], None)
    demand('runuser -u source-checker -- env -i' in whitespace_step and
           'git -C "${source_root}" diff --check' in whitespace_step and
           'safe.directory="${GITHUB_WORKSPACE}"' in whitespace_step,
           'CI whitespace readback is not unprivileged')


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
    source_step = block(build_job, steps[3], steps[4])
    for literal in (
        'useradd --create-home --shell /bin/bash package-builder',
        'stat --file-system --format=%t', 'test -f /.dockerenv', 'test ! -L /.dockerenv',
        'source_parent="${workspace_parent}/arch-linux-source-validation"',
        'source_temp="${workspace_parent}/arch-linux-source-temp"',
        'chown -R root:root -- "${GITHUB_WORKSPACE}"',
        'chmod -R go-w -- "${GITHUB_WORKSPACE}"',
        'install -d -m0700 -o package-builder -g package-builder',
        'writable_path="$(runuser -u package-builder --',
        'find "${GITHUB_WORKSPACE}" -writable -print -quit)',
        'git config --global --add safe.directory "${GITHUB_WORKSPACE}"',
        'git config --global --add safe.directory "${GITHUB_WORKSPACE}/.git"',
        'clone --no-local --no-hardlinks', '--no-checkout -- "${GITHUB_WORKSPACE}"',
        'rm -f -- "${builder_home}/.gitconfig"',
        'checkout --detach "${SOURCE_COMMIT}"',
        'test ! -e "${source_parent}/repo/.git/objects/info/alternates"',
        'test ! -L "${source_parent}/repo/.git/objects/info/alternates"',
        'find "${source_parent}/repo" -type f -links +1',
        'runuser -u package-builder -- env -i', *HOSTED_MARKERS,
        'RUNNER_TEMP="${source_temp}"', 'bash "${source_parent}/repo/tests/source-tests.sh"',
    ):
        demand(literal in source_step, f'package source invocation differs: {literal}')
    demand(source_step.count('stat --file-system --format=%t') >= 3,
           'package source parent and temp are not both bound to ext4')
    demand(re.search(r'chown[^\n]*package-builder[^\n]*GITHUB_WORKSPACE', source_step) is None,
           'package workflow grants canonical checkout ownership to builder')
    build_step = block(build_job, steps[4], steps[5])
    demand('useradd ' not in build_step, 'package builder is recreated after source validation')
    demand('runuser -u package-builder -- env -i' in build_step and
           'bash "${GITHUB_WORKSPACE}/repository/build-packages.sh"' in build_step,
           'canonical build is not tied to the validated unprivileged user')
    demand(build_step.count('writable_path="$(runuser -u package-builder --') == 2 and
           build_step.count('find "${GITHUB_WORKSPACE}" -writable -print -quit)') == 2,
           'canonical source write authority is not checked before and after build')
    demand(build_step.count('test ! -e "${builder_home}/.gitconfig"') == 2 and
           build_step.count('test ! -L "${builder_home}/.gitconfig"') == 2,
           'temporary clone trust is not absent before and after build')
    demand(build_step.count("rev-parse --verify 'HEAD^{commit}'") == 2 and
           build_step.count("rev-parse --verify 'HEAD^{tree}'") == 2 and
           build_step.count('status --porcelain=v1 --untracked-files=all') == 2,
           'canonical source identity is not checked before and after build')


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
    ('CI unprivileged execution', validate_ci, ci,
     'runuser -u source-checker -- env -i', 'env -i', None),
    ('CI hosted marker', validate_ci, ci, HOSTED_MARKERS[1],
     'ARCH_LINUX_ALLOW_HOSTED_NAMESPACE_DEFERRAL=', 1),
    ('CI canonical ownership', validate_ci, ci, 'chown -R root:root -- "${GITHUB_WORKSPACE}"',
     'chown -R source-checker:source-checker -- "${GITHUB_WORKSPACE}"', 1),
    ('CI non-local clone', validate_ci, ci,
     'clone --no-local --no-hardlinks', 'clone --no-hardlinks', 1),
    ('package unprivileged execution', validate_packages, packages,
     'runuser -u package-builder -- env -i', 'env -i', None),
    ('package hosted identity markers', validate_packages, packages, HOSTED_MARKERS[0],
     'CI=true GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted', 1),
    ('package hosted deferral marker', validate_packages, packages, HOSTED_MARKERS[1],
     'ARCH_LINUX_ALLOW_HOSTED_NAMESPACE_DEFERRAL=', 1),
    ('package canonical ownership', validate_packages, packages,
     'chown -R root:root -- "${GITHUB_WORKSPACE}"',
     'chown -R package-builder:package-builder -- "${GITHUB_WORKSPACE}"', 1),
    ('package non-local clone', validate_packages, packages,
     'clone --no-local --no-hardlinks', 'clone --no-hardlinks', 1),
    ('package canonical nonwritability', validate_packages, packages,
     'find "${GITHUB_WORKSPACE}" -writable -print -quit)',
     'find "${GITHUB_WORKSPACE}" -readable -print -quit)', None),
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
