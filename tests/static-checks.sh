#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fail() { printf 'static check failed: %s\n' "$*" >&2; exit 1; }

required=(
    arch-linux-installer.sh install.sh AGENTS.md README.md NOTICE.md
    repository/build-packages.sh repository/verify-unsigned-build.sh
    repository/offline-sign-release.sh repository/verify-signed-repository.sh
    repository/verify-release-assets.sh repository/safe-extract-snapshot.py
    repository/snapshot-manifest.py repository/verify-package-metadata.py
    repository/offline-signing-launcher.c repository/offline-signing-fd-guard.py
    repository/offline-signing-namespace.sh repository/run-offline-signing.sh
    repository/seal-offline-signing-code.py repository/verify-sealed-offline-code.py
    repository/offline-finalize-release.sh repository/acceptance-manifest.py
    tests/publication-root-check.sh tests/keyring-rotation-checks.sh
    maintenance/check-arch-iso.py maintenance/check-sources.py maintenance/sources.json
    tests/vm/frame-evidence.py
    .github/workflows/ci.yml .github/workflows/packages.yml
    .github/workflows/pages.yml .github/workflows/maintenance.yml
)
for path in "${required[@]}"; do
    [ -f "$repo_root/$path" ] && [ ! -L "$repo_root/$path" ] || fail "required file absent or linked: $path"
done

for path in \
    UPSTREAM.md .github/dependabot.yml .github/runner .github/workflows/publish-repository.yml \
    .github/workflows/release-verify.yml repository/verify-snapshot.sh \
    repository/publication-broker.py repository/publication-launcher.c \
    repository/create-validation-evidence.sh repository/validation-evidence-archive.py \
    maintenance/accepted-dependencies.json maintenance/check-dependency-upstreams.py; do
    [ ! -e "$repo_root/$path" ] && [ ! -L "$repo_root/$path" ] || fail "retired component remains: $path"
done

mapfile -t workflows < <(find "$repo_root/.github/workflows" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
expected_workflows=$'ci.yml\nmaintenance.yml\npackages.yml\npages.yml'
[ "$(printf '%s\n' "${workflows[@]}")" = "$expected_workflows" ] || fail 'workflow closure differs'

python3 - "$repo_root/.github/workflows" <<'WORKFLOW_PY'
from pathlib import Path
import re, sys
root=Path(sys.argv[1])
uses=re.compile(r'^\s*uses:\s*([^\s#]+)',re.M)
for path in sorted(root.glob('*.yml')):
    text=path.read_text(encoding='utf-8')
    lowered=text.lower()
    if 'secrets.' in lowered or 'write-all' in lowered:
        raise SystemExit(f'static check failed: workflow requests secret/write-all authority: {path.name}')
    for match in uses.finditer(text):
        value=match.group(1)
        if value.startswith('./'):
            continue
        if '@' not in value or not re.fullmatch(r'[^@]+@[0-9a-f]{40}',value):
            raise SystemExit(f'static check failed: action is not pinned by full commit SHA: {path.name}: {value}')
WORKFLOW_PY

packages_workflow="$repo_root/.github/workflows/packages.yml"
maintenance_workflow="$repo_root/.github/workflows/maintenance.yml"
pages_workflow="$repo_root/.github/workflows/pages.yml"

python3 - "$packages_workflow" "$maintenance_workflow" <<'BUILD_DEPS_PY'
from pathlib import Path
import sys

expected = {
    "packages.yml": (
        "bash", "coreutils", "curl", "dconf", "git", "glib2", "glib2-devel", "gnupg",
        "gsettings-desktop-schemas", "jq", "libarchive", "python", "sassc", "shellcheck",
        "unzip", "zstd",
    ),
    "maintenance.yml": (
        "bash", "coreutils", "curl", "dconf", "git", "glib2", "glib2-devel", "gnupg",
        "gsettings-desktop-schemas", "jq", "libarchive", "python", "sassc", "unzip", "zstd",
    ),
}
step_marker = "      - name: Install build dependencies"
command = "          pacman -Syu --noconfirm --needed \\"

for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    lines = path.read_text(encoding="utf-8").splitlines()
    step_indexes = [index for index, line in enumerate(lines) if line == step_marker]
    if len(step_indexes) != 1:
        raise SystemExit(
            f"static check failed: expected one build-dependency step in {path.name}"
        )
    step_start = step_indexes[0]
    step_end = next(
        (
            index
            for index in range(step_start + 1, len(lines))
            if lines[index].startswith("      - name: ")
        ),
        len(lines),
    )
    command_indexes = [
        index for index in range(step_start, step_end) if lines[index] == command
    ]
    if len(command_indexes) != 1:
        raise SystemExit(
            f"static check failed: expected one direct pacman dependency command in {path.name}"
        )

    packages = []
    index = command_indexes[0] + 1
    terminated = False
    while index < step_end:
        value = lines[index].strip()
        if not value:
            break
        continued = value.endswith("\\")
        if continued:
            value = value[:-1].rstrip()
        packages.extend(value.split())
        index += 1
        if not continued:
            terminated = True
            break
    if not terminated:
        raise SystemExit(f"static check failed: unterminated dependency list in {path.name}")

    actual = tuple(packages)
    if len(actual) != len(set(actual)):
        raise SystemExit(f"static check failed: duplicate direct build dependency in {path.name}")
    if actual != expected[path.name]:
        raise SystemExit(
            f"static check failed: direct build dependency closure differs in {path.name}"
        )
BUILD_DEPS_PY

for literal in source_commit source_tree 'Read back canonical artifact' \
    'actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c' \
    'BUILD_METADATA_SHA256' 'UNSIGNED_MANIFEST_SHA256'; do
    grep -Fq -- "$literal" "$packages_workflow" || fail "canonical package binding absent: $literal"
done
! grep -Fq 'push:' "$packages_workflow" || fail 'canonical package workflow has an automatic tag build'

# shellcheck disable=SC2016
for literal in release_id release_version source_commit source_tree source_tree_sha256 snapshot_sha256 \
    build_metadata_sha256 unsigned_manifest_sha256 'GH_TOKEN: ${{ github.token }}' \
    'releases/${RELEASE_ID}' 'draft == true' '(.assets | length == 18)' \
    "refs/tags/\${RELEASE_VERSION}^{}" 'verify-release-assets.sh' '.tar.zst'; do
    grep -Fq -- "$literal" "$pages_workflow" || fail "Pages draft binding absent: $literal"
done
! grep -Fq 'snapshot_url' "$pages_workflow" || fail 'Pages accepts an arbitrary snapshot URL'
! grep -Fq '/releases/download/' "$pages_workflow" || fail 'Pages uses unauthenticated draft download URLs'

python3 - "$pages_workflow" <<'PAGES_MODES_PY'
import copy, json, os, pathlib, re, subprocess, sys, tempfile
workflow = pathlib.Path(sys.argv[1]).read_text()
expression = re.search(r"jq -e --argjson id.*?--arg kind.*?'\n(.*?)\n          ' \"\$\{release_json\}\"", workflow, re.S)
if expression is None:
    raise SystemExit('static check failed: Pages metadata verification is missing')
def accepts(kind, count, change=None):
    tag = '1.0.0' if kind == 'release' else 'packages-20260905.1'
    value = {'id': 1, 'tag_name': tag, 'name': tag, 'draft': True, 'prerelease': False,
             'assets': [{'id': n+1, 'name': f'asset-{n}', 'size': 1, 'state': 'uploaded',
                         'digest': 'sha256:'+'a'*64} for n in range(count)]}
    if change:
        change(value)
    result = subprocess.run(['jq', '-e', '--argjson', 'id', '1', '--arg', 'tag', tag,
                             '--arg', 'kind', kind, expression.group(1)],
                            input=json.dumps(value), text=True, capture_output=True, check=False)
    return result.returncode == 0
assert accepts('release', 18) and not accepts('release', 14)
assert accepts('packages', 14) and not accepts('packages', 18)
for kind, count in (('release', 18), ('packages', 14)):
    assert not accepts(kind, count, lambda x: x.update(tag_name='foreign'))
    assert not accepts(kind, count, lambda x: x.update(draft=False))
    assert not accepts(kind, count, lambda x: x['assets'][0].update(digest=None))
    assert not accepts(kind, count, lambda x: x['assets'].append(copy.deepcopy(x['assets'][0])))
assert 'verification_mode=--phase-a' in workflow and 'verification_mode=--finalized' in workflow
assert 'git diff --quiet "refs/tags/${RELEASE_VERSION}^{}" HEAD -- install.sh arch-linux-installer.sh' in workflow
assert '"refs/tags/${PACKAGE_TAG}^{}"' in workflow and '"${verification_mode}"' in workflow
verify_job = workflow.split('  verify:\n', 1)[1].split('\n  deploy:\n', 1)[0]
deploy_job = workflow.split('\n  deploy:\n', 1)[1]
assert '    permissions:\n      contents: write\n' in verify_job
assert 'contents: write' not in deploy_job
assert 'persist-credentials: false' in verify_job and 'ref: ${{ inputs.source_commit }}' in verify_job
assert not re.search(r'gh (?:release|api[^\n]*(?:--method|-X)\s+(?:POST|PATCH|PUT|DELETE))', verify_job)
# Exercise the actual workflow source/tag guard, including a later deployment commit.
guard = re.search(r'      - name: Require exact source and annotated tag\n.*?        run: \|\n(.*?)\n      - name:', workflow, re.S)
assert guard is not None
script = '\n'.join(line[10:] for line in guard.group(1).splitlines())
with tempfile.TemporaryDirectory(prefix='pages-source-') as raw:
    fixture = pathlib.Path(raw)
    def git(*args):
        return subprocess.check_output(['git', '-C', raw, *args], text=True, stderr=subprocess.DEVNULL).strip()
    git('init', '-b', 'main')
    git('config', 'user.name', 'Fixture')
    git('config', 'user.email', 'fixture@example.invalid')
    git('commit', '--allow-empty', '-m', 'release')
    source = git('rev-parse', 'HEAD')
    tree = git('rev-parse', 'HEAD^{tree}')
    git('tag', '-a', '1.0.0', '-m', 'frozen')
    git('commit', '--allow-empty', '-m', 'deployment-only')
    deployment = git('rev-parse', 'HEAD')
    git('checkout', '--orphan', 'foreign')
    git('commit', '--allow-empty', '-m', 'unrelated')
    foreign = git('rev-parse', 'HEAD')
    git('checkout', '--detach', source)
    env = dict(os.environ, DEPLOYMENT_KIND='release', PACKAGE_TAG='', RELEASE_VERSION='1.0.0',
               SOURCE_COMMIT=source, SOURCE_TREE=tree, SOURCE_TREE_SHA256='a'*64,
               GITHUB_REF='refs/heads/main', GITHUB_SHA=deployment)
    def source_accepts(**changes):
        return subprocess.run(['bash', '-euo', 'pipefail', '-c', script], cwd=fixture,
                              env=dict(env, **changes), capture_output=True, check=False).returncode == 0
    assert source_accepts() and source_accepts(GITHUB_SHA=source)
    assert not source_accepts(GITHUB_SHA=foreign)
    assert not source_accepts(GITHUB_REF='refs/heads/foreign')
    assert not source_accepts(SOURCE_COMMIT=deployment)
    assert not source_accepts(SOURCE_TREE='0'*40)
    assert not source_accepts(RELEASE_VERSION='1.0.1')
print('Pages release/package-only metadata checks passed; DEPLOY=NOT_RUN')
PAGES_MODES_PY

for literal in "'schema':2" sourceCommit sourceTree installerSha256 packageSetSha256 \
    unsignedManifestSha256; do
    grep -Fq -- "$literal" "$repo_root/repository/build-packages.sh" ||
        fail "schema-2 build binding absent: $literal"
done
for literal in '"schema": 2' sourceCommit sourceTree installerSha256 packageSetSha256 \
    sourceDateEpoch buildMetadataSha256 unsignedManifestSha256; do
    grep -Fq -- "$literal" "$repo_root/repository/snapshot-manifest.py" ||
        fail "schema-2 snapshot binding absent: $literal"
done
# shellcheck disable=SC2016
for path in repository/offline-sign-release.sh repository/verify-release-assets.sh; do
    grep -Fq -- 'arch-linux-repository-${version}.tar.zst' "$repo_root/$path" ||
        fail "tar.zst release archive absent: $path"
    grep -Fq -- 'install.sh' "$repo_root/$path" || fail "install.sh release asset absent: $path"
    ! grep -Fq -- 'arch-linux-repository-${version}.tar.gz' "$repo_root/$path" ||
        fail "retired outer tar.gz release archive remains: $path"
done

for path in repository/verify-unsigned-build.sh repository/verify-signed-repository.sh; do
    grep -Fq -- 'verify-package-metadata.py" --verify-package' "$repo_root/$path" ||
        fail "exact package payload verification absent: $path"
done
for path in repository/offline-sign-release.sh repository/offline-finalize-release.sh; do
    for literal in --build-metadata-sha256 --unsigned-manifest-sha256; do
        grep -Fq -- "$literal" "$repo_root/$path" ||
            fail "independently accepted signing digest absent from $path: $literal"
    done
    # shellcheck disable=SC2016
    grep -Fq -- 'repository_assert_private_signing_subkey "$primary" "$signing" "$fd_guard"' \
        "$repo_root/$path" || fail "guarded private-key inspection absent from $path"
    # shellcheck disable=SC2016
    [ "$(grep -Fc -- 'atomic-publish "$stage" "$output"' "$repo_root/$path")" -eq 1 ] ||
        fail "atomic no-replace publication differs in $path"
    # shellcheck disable=SC2016
    ! grep -Fq -- '/usr/bin/mv -- "$stage" "$output"' "$repo_root/$path" ||
        fail "replace-capable publication remains in $path"
done
grep -Fq -- 'exec-private-gpg /usr/bin/gpg' "$repo_root/repository/lib/common.sh" ||
    fail 'private signing-subkey inspection bypasses its exact descriptor guard'
for literal in '--sealed-broker' ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT \
    offline-signing-fd-guard.py '--net' '--pid' '--kill-child' '--mount-proc'; do
    grep -Fq -- "$literal" "$repo_root/repository/run-offline-signing.sh" ||
        fail "offline signing boundary assertion absent: $literal"
done
! grep -Eq -- 'export-secret|cp[^\n]*GNUPGHOME' "$repo_root/repository/run-offline-signing.sh" ||
    fail 'offline signing wrapper copies or exports private key material'
launcher="$repo_root/repository/offline-signing-launcher.c"
for literal in ALI_ACCEPTED_COMMIT_SHA ALI_ACCEPTED_TREE_SHA ALI_ACCEPTED_TREE_SHA256 \
    CLOSE_RANGE_UNSHARE S_ISFIFO MFD_ALLOW_SEALING F_SEAL_WRITE HOME_FD PASSPHRASE_FD BROKER_FD \
    'strcmp(argv[1], "snapshot")' 'strcmp(argv[1], "finalize")' PR_SET_DUMPABLE PR_SET_PDEATHSIG \
    validate_account_and_drop_privileges /etc/shadow setresuid setresgid; do
    grep -Fq -- "$literal" "$launcher" || fail "static launcher boundary absent: $literal"
done
for literal in -static-pie ALI_ACCEPTED_COMMIT_SHA sourceCommitSha signingAccount \
    offline-signing-launcher; do
    grep -Fq -- "$literal" "$repo_root/repository/seal-offline-signing-code.py" ||
        fail "root sealer boundary absent: $literal"
done
for literal in offline-sign-release.sh offline-finalize-release.sh sealed-root-v1 \
    '/proc/self/fd/6' '/proc/self/fd/7' '/run/user' 'BASHPID' repository_assert_loopback_only_network; do
    grep -Fq -- "$literal" "$repo_root/repository/offline-signing-namespace.sh" ||
        fail "full namespace boundary absent: $literal"
done
for literal in '--pinentry-mode loopback' '--passphrase-file /proc/self/fd/7' \
    'exec-public' 'exec-private-gpg' 'atomic-publish' '/usr/bin/repo-add --include-sigs'; do
    grep -Fq -- "$literal" "$repo_root/repository/offline-sign-release.sh" ||
        fail "snapshot signing boundary absent: $literal"
done
! grep -Eq -- 'repo-add[^\n]*(--sign|--key)' "$repo_root/repository/offline-sign-release.sh" ||
    fail 'repo-add receives private signing authority'
for literal in BUILD-METADATA.json UNSIGNED-SHA256SUMS '--phase-a' 'release asset closure is not exact' \
    arch-linux-acceptance-evidence- 'phaseAAssets' phaseAAggregateSha256 deferred; do
    grep -RqsF -- "$literal" "$repo_root/repository/verify-release-assets.sh" \
        "$repo_root/repository/acceptance-manifest.py" || fail "exact14/18 contract absent: $literal"
done
grep -Fq -- \
    'REPOSITORY_CHECKS_RESULT schema=1 namespace_fixtures=%s scenarios=10 signer=passed release_closures=14+18 deferred=%s' \
    "$repo_root/tests/repository-checks.sh" ||
    fail 'repository release-host result marker is not the normative schema-1/full/10/signer/no-deferral contract'
for literal in 'payloadIsoSha256' \
    'maintenance/accepted-arch-iso.json' 'inspect_binary_secret_markers'; do
    grep -RqsF -- "$literal" "$repo_root/repository/acceptance-manifest.py" \
        "$repo_root/repository/seal-offline-signing-code.py" ||
        fail "sealed acceptance evidence binding absent: $literal"
done
offline_signer="$repo_root/repository/offline-sign-release.sh"
# shellcheck disable=SC2016
safe_private_copy='    public_exec /usr/bin/cp -a --no-preserve=ownership -- "$unsigned" "$accepted_unsigned"'
# shellcheck disable=SC2016
unsafe_private_copy='    public_exec /usr/bin/cp -a -- "$unsigned" "$accepted_unsigned"'
if [ "$(grep -Fxc -- "$safe_private_copy" "$offline_signer")" -ne 1 ] ||
    grep -Fqx -- "$unsafe_private_copy" "$offline_signer"; then
    fail 'offline signing private copy must not preserve its unmapped host owner'
fi

python3 - "$repo_root" <<'CLEANUP_PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
offline_lines=(root/'repository/offline-sign-release.sh').read_text(encoding='utf-8').splitlines()
checksum_mode_sequence=[
    "    printf '%s *arch-linux-installer.sh\\n' \\",
    '        "$(repository_sha256 "$assets/arch-linux-installer.sh" 7<&-)" >"$assets/arch-linux-installer.sh.sha256"',
    '    public_exec /usr/bin/chmod 0644 -- "$assets/arch-linux-installer.sh.sha256"',
]
matches=sum(
    offline_lines[index:index + len(checksum_mode_sequence)] == checksum_mode_sequence
    for index in range(len(offline_lines) - len(checksum_mode_sequence) + 1)
)
if matches != 1:
    raise SystemExit('static check failed: installer checksum must receive mode 0644 immediately after production creation')
paths=[
    'repository/build-packages.sh',
    'repository/offline-sign-release.sh',
    'repository/verify-release-assets.sh',
    'repository/verify-unsigned-build.sh',
    'repository/validate-package-sources.sh',
]
for relative in paths:
    text=(root/relative).read_text(encoding='utf-8')
    if 'printf -v cleanup_command' not in text or 'trap "$cleanup_command" EXIT' not in text:
        raise SystemExit(f'static check failed: failure cleanup is not eagerly EXIT-bound: {relative}')
    if "trap 'rm -rf -- \"$work\"'" in text or "trap 'rm -f -- \"$expected_manifest\"'" in text:
        raise SystemExit(f'static check failed: late-bound local remains in EXIT cleanup: {relative}')
CLEANUP_PY

grep -Fq "VERSION='1.0.0'" "$repo_root/arch-linux-installer.sh" || fail 'installer version differs'
for literal in \
    "SigLevel = PackageRequired DatabaseRequired TrustedOnly" \
    "ARCH_LINUX_GNOME_THEME_PROFILE" "stock" "marble" \
    "ARCH_LINUX_GDM_THEME_PROFILE" "marble-experimental" \
    "ext4" "btrfs" "grub" "systemd-boot" "luks2"; do
    grep -Fq -- "$literal" "$repo_root/arch-linux-installer.sh" || fail "installer contract literal absent: $literal"
done
! grep -Eq 'SigLevel[[:space:]]*=[^#\n]*(TrustAll|Optional)' "$repo_root/arch-linux-installer.sh" ||
    fail 'installer weakens repository trust policy'
! grep -Eq 'makepkg.*(^|[[:space:]])root|sudo[[:space:]]+makepkg' "$repo_root/arch-linux-installer.sh" ||
    fail 'installer permits root PKGBUILD execution'

grep -Fq 'org.gnome.Shell@gdm.service.d' "$repo_root/packages/arch-linux-marble-gdm/update-compatibility" ||
    fail 'Marble GDM override is not scoped to the GDM Shell unit'
! grep -Rqs -- '/etc/environment' "$repo_root/packages/arch-linux-marble-gdm" ||
    fail 'Marble GDM writes a global environment'
grep -Fq 'Environment=G_RESOURCE_OVERLAYS=' "$repo_root/packages/arch-linux-marble-gdm/50-arch-linux-marble-gdm.conf" ||
    fail 'GDM resource overlay is absent'
grep -Fq 'Environment=DCONF_PROFILE=' "$repo_root/packages/arch-linux-marble-gdm/50-arch-linux-marble-gdm.conf" ||
    fail 'GDM dconf overlay is absent'

grep -Fq 'post_upgrade()' "$repo_root/packages/arch-linux-marble-profile/arch-linux-marble-profile.install" ||
    fail 'Marble profile lacks pacman upgrade hook'
grep -Fq 'pre_remove()' "$repo_root/packages/arch-linux-marble-profile/arch-linux-marble-profile.install" ||
    fail 'Marble profile lacks removal hook'
grep -Fq 'deactivate_profile' "$repo_root/packages/arch-linux-marble-profile/update-compatibility" ||
    fail 'Marble profile lacks Stock fallback'

python3 "$repo_root/repository/verify-package-metadata.py"

python3 - "$repo_root" <<'VM_IDENTITY_PY'
from pathlib import Path
import ast
import re
import subprocess
import sys

root = Path(sys.argv[1])
host = (root / "tests/vm/run.sh").read_text()
guests = [(root / path).read_text() for path in ("tests/vm/guest/bootstrap.sh", "tests/vm/guest/verify.sh")]
routes = (
    ("minimal-ext4-systemdboot", "minimal", "M", "MIN"),
    ("stock-gnome-ext4-systemdboot", "stock", "S", "STK"),
    ("stock-gnome-btrfs-systemdboot", "btrfs", "B", "BTR"),
    ("stock-gnome-btrfs-grub", "grub", "G", "GRB"),
    ("stock-gnome-btrfs-luks2-plymouth-systemdboot", "luks", "L", "LUK"),
    ("stock-gnome-btrfs-luks2-plymouth-grub", "luksgrub", "G", "GRB"),
    ("marble-gnome-btrfs-luks2-plymouth-systemdboot", "marble", "A", "MAR"),
    ("marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm", "marblestock", "A", "MAR"),
    ("minimal-dualboot-ext4-systemdboot", "dualboot", "M", "MIN"),
)
stock = routes[5][0]

def require(condition, message):
    if not condition:
        raise SystemExit(f"static check failed: VM identity: {message}")

def bash(program, *args):
    return subprocess.run(["bash", "--noprofile", "--norc", "-c", "set -euo pipefail\n" + program,
                           "identity-fixture", *args], capture_output=True, text=True, timeout=5,
                          env={"PATH": "/usr/bin:/usr/sbin", "LANG": "C", "LC_ALL": "C"})

# Execute only the actual scenario/identity assignments, never main, QEMU or guest setup.
start = host.index('    case "${scenario_id}" in\n', host.index("main() {"))
end = host.index("\n    esac\n    shift", start) + len("\n    esac")
case = host[start:end]
mode_start = host.index('    case "${input_mode}:${scenario_id}" in\n', end)
mode_end = host.index('\n    esac', mode_start) + len('\n    esac')
mode_case = host[mode_start:mode_end]
start = host.index('    if [ "${run_prefix}" = minimal ]', end)
end = host.index('    [[ "${run_id}" =~', start)
identity = host[start:end]
run_id_assignment = [line for line in host.splitlines() if line.startswith('    run_id="${run_prefix}-')]
require(len(run_id_assignment) == 1, "host run-id assignment closure")
generator = ('scenario_id=$1\nusage(){ return 2; }\n'
             'date(){ printf %s 20260905T000000Z; }\n'
             'openssl(){ case "$*" in "rand -hex 6") printf %s 0123456789ab ;; '
             '"rand -hex 4") printf %s 01234567 ;; *) return 2 ;; esac; }\n'
             + case + '\n' + run_id_assignment[0] + '\n' + identity
             + '\nprintf "%s\\n" "$target_serial" "$target_model" "$run_id"\n')

def guest_guards(text, scenario, bootstrap):
    matches = re.findall(r'^\s*' + re.escape(scenario) + r'\)\n(.*?)^\s*;;', text, re.M | re.S)
    require(len(matches) == 1, f"guest scenario closure: {scenario}")
    needles = ("IDENTITY[TARGET_SERIAL]", "IDENTITY[TARGET_MODEL]", "IDENTITY[RUN_ID]") if bootstrap else (
        "expected_serial", "expected_model", "run_id")
    guards = [line.strip() for line in matches[0].splitlines()
              if line.strip().startswith("[[") and any(needle in line for needle in needles)]
    require(len(guards) == 3, f"guest identity guard closure: {scenario}")
    return "\n".join(guards)

def guest_accepts(guards, serial, model, run_id):
    result = bash('fail(){ return 1; }\n'
                  'declare -A IDENTITY=([TARGET_SERIAL]="$1" [TARGET_MODEL]="$2" [RUN_ID]="$3")\n'
                  'expected_serial=$1; expected_model=$2; run_id=$3\n' + guards, serial, model, run_id)
    require(result.returncode in (0, 1) and not result.stdout and not result.stderr, "guest guard execution")
    return result.returncode == 0

# Exercise the actual finalizer identity function, with synthetic non-secret identity rows only.
acceptance = (root / "repository/acceptance-manifest.py").read_text()
parsed = ast.parse(acceptance)
scenarios_node = next(node for node in parsed.body if isinstance(node, ast.Assign)
                      and any(isinstance(t, ast.Name) and t.id == "SCENARIOS" for t in node.targets))
final_scenarios = ast.literal_eval(scenarios_node.value)
validator = next(node for node in parsed.body if isinstance(node, ast.FunctionDef)
                 and node.name == "validate_identity_record")
def rejected(message):
    raise ValueError(message)
namespace = {"SCENARIOS": final_scenarios, "re": re, "fail": rejected}
exec("from __future__ import annotations\n" + ast.get_source_segment(acceptance, validator), namespace)

def final_accepts(scenario, serial, model, run_id, recorded_run_id=None):
    digest = "a" * 64
    result = dict(sourceCommit="b" * 40, sourceTree="c" * 40, harnessSha256=digest,
                  isoSha256=digest, targetSerial=serial)
    expected = dict.fromkeys(("repositorySnapshotSha256", "buildMetadataSha256",
                             "unsignedManifestSha256", "releaseSha256sumsSha256"), digest)
    repository_rows = (
        ("repository_public_key_sha256", "publicKeySha256"),
        ("repository_primary_fingerprint", "primaryFingerprint"),
        ("repository_signing_fingerprint", "signingFingerprint"),
        ("repository_package_set_sha256", "packageSetSha256"),
        ("repository_manifest_sha256", "manifestSha256"),
        ("repository_manifest_signature_sha256", "manifestSignatureSha256"),
        ("repository_database_sha256", "databaseSha256"),
        ("repository_database_signature_sha256", "databaseSignatureSha256"),
        ("repository_files_sha256", "filesSha256"),
        ("repository_files_signature_sha256", "filesSignatureSha256"),
    )
    contract = dict.fromkeys((key for _, key in repository_rows), digest)
    contract.update(installerSha256=digest, objects=[])
    rows = [("scenario", scenario), ("input_mode", "staged"), ("release_version", "1.0.0"),
            ("run_id", recorded_run_id or run_id), ("source_commit", result["sourceCommit"]),
            ("source_tree", result["sourceTree"]), ("installer_sha256", digest),
            ("bootstrap_sha256", digest), ("harness_sha256", digest), ("iso_sha256", digest),
            ("snapshot_sha256", digest), ("build_metadata_sha256", digest),
            ("unsigned_manifest_sha256", digest), ("target_serial", serial),
            ("target_vendor", "SNAPLYZE"), ("target_model", model)]
    rows += [(name, contract[key]) for name, key in repository_rows]
    rows.append(("release_sha256sums_sha256", digest))
    if scenario == final_scenarios[2]:
        rows.append(("repository_server_port", "12345"))
    raw = "".join(f"{name}={value}\n" for name, value in rows).encode()
    try:
        namespace["validate_identity_record"](raw, result, scenario, run_id, "1.0.0", expected, contract, digest)
    except ValueError:
        return False
    return True

guest_negatives = final_negatives = legacy_regressions = 0
for scenario, prefix, letter, model_prefix in routes:
    for input_mode in ('staged', 'public', 'invalid'):
        mode_result = bash('input_mode=$1; scenario_id=$2; die(){ return 1; }\n' + mode_case,
                           input_mode, scenario)
        accepted = input_mode == 'staged' or (input_mode == 'public' and scenario == routes[6][0])
        require((mode_result.returncode == 0) == accepted, f'mode routing: {input_mode}/{scenario}')
    result = bash(generator, scenario)
    require(result.returncode == 0 and not result.stderr, f"host generator: {scenario}")
    actual = tuple(result.stdout.splitlines())
    expected = (f"ALI100{letter}0123456789AB", f"ALI_{model_prefix}_01234567", f"{prefix}-20260905T000000Z-01234567")
    require(actual == expected, f"host identity: {scenario}")
    serial, model, run_id = actual
    mutations = [(f"ALI100{x}0123456789AB", model, run_id) for x in "MSBGLAR" if x != letter]
    mutations += [(serial, f"ALI_{x}_01234567", run_id)
                  for x in ("MIN", "STK", "BTR", "GRB", "LUK", "MAR", "LGR") if x != model_prefix]
    mutations += [(serial, model, f"{foreign}-20260905T000000Z-01234567")
                  for _, foreign, _, _ in routes if foreign != prefix]
    mutations += [(bad, model, run_id) for bad in (serial[:-1], serial + "A", serial[:-1] + "g", serial + "\n")]
    mutations += [(serial, bad, run_id) for bad in (model[:-1], model + "A", model[:-1] + "g", model + "\n")]
    mutations += [(serial, model, run_id[:-1]), (serial, model, run_id[:-1] + "G")]
    for index, text in enumerate(guests):
        guards = guest_guards(text, scenario, index == 0)
        require(guest_accepts(guards, *actual), f"host/guest {index} mismatch: {scenario}")
        if scenario == stock:
            old_guards = guards.replace("ALI100G", "ALI100R").replace("ALI_GRB_", "ALI_LGR_")
            require(old_guards != guards and not guest_accepts(old_guards, *actual), "legacy Stock regression")
            legacy_regressions += 1
        for mutation in mutations:
            require(not guest_accepts(guards, *mutation), f"guest {index} accepted foreign/malformed identity: {scenario}")
            guest_negatives += 1
    if scenario in final_scenarios:
        require(final_accepts(scenario, *actual), f"host/finalizer mismatch: {scenario}")
        for changed_serial, changed_model, changed_run in mutations:
            require(not final_accepts(scenario, changed_serial, changed_model, run_id, changed_run),
                    f"finalizer accepted foreign/malformed identity: {scenario}")
            final_negatives += 1
require(tuple(final_scenarios) == tuple(routes[i][0] for i in (0, 5, 6)), "final scenario closure")
require(legacy_regressions == 2, "legacy Stock negative coverage")
print(f"VM identity checks passed: routes={len(routes)} finalizer=3 guest_negatives={guest_negatives} "
      f"finalizer_negatives={final_negatives} legacy_regressions={legacy_regressions}; QEMU=NOT_RUN")
VM_IDENTITY_PY

python3 - "$repo_root/tests/vm/guest/bootstrap.sh" <<'VM_CONFIG_PY'
import pathlib, re, subprocess, sys, tempfile
source = pathlib.Path(sys.argv[1]).read_text()
function = re.search(r'^write_config\(\) \{\n.*?^\}', source, re.M | re.S).group()
with tempfile.TemporaryDirectory(prefix='arch-linux-vm-config-') as temporary:
    config = pathlib.Path(temporary)/'installer.conf'
    base = 'marble-gnome-btrfs-luks2-plymouth-systemdboot'
    for scenario, expected in ((base, 'marble-experimental'), (base+'-stock-gdm', 'stock'),
                               ('minimal-dualboot-ext4-systemdboot', 'stock')):
        program = ('set -euo pipefail\ndeclare -A IDENTITY=([SCENARIO]="$1" [HOSTNAME]=test '
                   '[USERNAME]=vmtest [MICROCODE]=none)\n'
                   'partition_name(){ printf "%s%s" "$1" "$2"; }\nfail(){ return 1; }\n'
                   'partition_identity(){ printf "%064d" 1; }\n'
                   + function + '\nwrite_config "$2" /dev/sdz ' + 'a'*64)
        subprocess.run(['bash', '-c', program, 'fixture', scenario, str(config)], check=True)
        values = dict(line.split('=', 1) for line in config.read_text().splitlines())
        assert len(values) == 43
        assert values['ARCH_LINUX_GNOME_THEME_PROFILE'] == ('stock' if scenario.startswith('minimal') else 'marble')
        assert values['ARCH_LINUX_GDM_THEME_PROFILE'] == expected
        if scenario.startswith('minimal'):
            assert values['ARCH_LINUX_DUAL_BOOT_ENABLED'] == 'true'
            assert values['ARCH_LINUX_ROOT_PARTITION'] == '/dev/sdz3'
            assert values['ARCH_LINUX_BOOT_PARTITION'] == '/dev/sdz1'
            assert values['ARCH_LINUX_ROOT_PARTITION_IDENTITY'] == '0'*63+'1'
            assert values['ARCH_LINUX_BOOT_PARTITION_IDENTITY'] == '0'*63+'1'
        else:
            assert values['ARCH_LINUX_ENCRYPTION_ENABLED'] == 'true'
            assert values['ARCH_LINUX_DUAL_BOOT_ENABLED'] == 'false'
            assert values['ARCH_LINUX_ROOT_PARTITION'] == '/dev/sdz2'
print('Marble separate GDM configuration checks passed; QEMU=NOT_RUN')
VM_CONFIG_PY

PYTHONDONTWRITEBYTECODE=1 python3 -B "$repo_root/tests/vm/frame-evidence.py" --self-test

bash "$repo_root/repository/assert-public-key.sh" \
    "$repo_root/repository/trust/arch-linux.gpg" \
    "$repo_root/repository/trust/primary-fingerprint" \
    "$repo_root/repository/trust/signing-subkey-fingerprint"

python3 - "$repo_root" <<'PY'
from pathlib import Path
import re, sys
root=Path(sys.argv[1])
legal=root/'NOTICE.md'
self_path=root/'tests/static-checks.sh'
for path in root.rglob('*'):
    if not path.is_file() or '.git' in path.parts or path in {legal,self_path}:
        continue
    try: text=path.read_text(encoding='utf-8')
    except UnicodeDecodeError: continue
    forbidden=[
        'UPSTREAM.md', 'accepted-dependencies.json', 'publication-broker',
        'publication-launcher', 'validation-evidence', 'verify-snapshot.sh',
        'github.com/'+'murkl/'+'arch-os', 'baseline '+'1.9.7',
        'M'+'10', 'M'+'10R1',
    ]
    for value in forbidden:
        if value.lower() in text.lower():
            raise SystemExit(f'static check failed: retired operational reference {value!r} in {path.relative_to(root)}')
notice=legal.read_text(encoding='utf-8')
if 'attribution only' not in notice.lower() or 'GPL-3.0' not in notice:
    raise SystemExit('static check failed: legal attribution is not isolated in NOTICE.md')
PY

python3 - "$repo_root" <<'VM_GUEST_PY'
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
guest = (root / "tests/vm/guest/verify.sh").read_text(encoding="utf-8")

for literal in (
    "[ -r /proc/fb ]",
    "/sys/class/graphics/fb0/name",
    "/sys/class/vtconsole/vtcon*",
    "kernel_console=tty0",
    "framebuffer=%q fbcon=bound",
):
    if literal not in guest:
        raise SystemExit(f"static check failed: guest framebuffer prerequisite absent: {literal}")

# procfs reports st_size=0 even when /proc/fb has rows. Execute the actual read/parse/count
# block against a readable zero-size procfs pipe, rather than a regular-file fixture.
proc_start = guest.index("    [ -r /proc/fb ]\n")
proc_end = guest.index("    [ -e /sys/class/graphics/fb0 ]\n", proc_start)
proc_block = guest[proc_start:proc_end]

def framebuffer_stream_status(block, payload):
    program = (
        'set -Eeuo pipefail\nframebuffer_rows=0\n'
        '[ -p /proc/self/fd/0 ]\n'
        '[ "$(stat -Lc %s /proc/self/fd/0)" = 0 ]\n'
        + block.replace('/proc/fb', '/proc/self/fd/0')
    )
    result = subprocess.run(
        ['/usr/bin/bash', '-c', program], input=payload,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5,
        env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
    )
    if result.returncode not in (0, 1) or result.stdout or result.stderr:
        raise SystemExit('static check failed: framebuffer stream fixture did not execute cleanly')
    return result.returncode

for payload in (b'0 virtio_gpudrmfb\n', b'0 simpledrm\n1 driver_1.2-+\n'):
    if framebuffer_stream_status(proc_block, payload) != 0:
        raise SystemExit('static check failed: readable zero-size framebuffer stream rejected')
for payload in (b'', b'\n', b'x driver\n', b'-1 driver\n', b'0\n',
                b'0 driver/name\n', b'0 driver extra\n', b'0 driver\n\n', b'0 driver'):
    if framebuffer_stream_status(proc_block, payload) != 1:
        raise SystemExit('static check failed: empty or malformed framebuffer stream accepted')
legacy_block = proc_block.replace('[ -r /proc/fb ]', '[ -s /proc/fb ]', 1)
if framebuffer_stream_status(legacy_block, b'0 virtio_gpudrmfb\n') != 1:
    raise SystemExit('static check failed: legacy procfs size defect was not reproduced')

# Execute only the actual optional capture wrapper, not QEMU or the installation path.
run = (root / "tests/vm/run.sh").read_text(encoding="utf-8")

# Execute the actual disposable CA command with the longest supported run prefix.
# Keep the unique run ID, without overflowing X.509's common-name length limit.
ca_start = run.index('    openssl req -x509', run.index('start_marble_repository_runtime() {'))
ca_end = run.index('    openssl req -new -newkey', ca_start)
longest_prefix = max(re.findall(r"run_prefix='([^']+)'", run), key=len)
ca_run_id = longest_prefix + '-20260905T000000Z-00000000'
with tempfile.TemporaryDirectory(prefix='arch-linux-vm-ca-check-') as temporary:
    program = ('set -euo pipefail\numask 077\nrun_id=$1\nevidence=$2\n'
               'repository_ca_private_key=$2/key\nrepository_ca_file=$2/ca.crt\n'
               + run[ca_start:ca_end])
    result = subprocess.run(['bash', '--noprofile', '--norc', '-c', program,
                             'ca-fixture', ca_run_id, temporary], capture_output=True, timeout=30)
    if result.returncode:
        raise SystemExit('static check failed: disposable CA rejects a supported run ID')
    subject = subprocess.check_output(['openssl', 'x509', '-in', temporary + '/ca.crt',
                                       '-noout', '-subject'], text=True)
    if ca_run_id not in subject:
        raise SystemExit('static check failed: disposable CA lost its unique run ID')
capture = re.search(r'(?ms)^capture_screen\(\) \{\n.*?^\}\n', run)
if capture is None:
    raise SystemExit('static check failed: diagnostic capture wrapper is absent')
program = 'set -Eeuo pipefail\n' + capture.group() + '''
python_bin="$1" script_dir="$2" run_root="$3" evidence="$3"
qmp_socket="$3/qmp.sock" qemu_pid="$$" qemu_start_time=0
capture_screen optional-fixture
printf 'CAPTURE_CONTINUED\\n'
"$4"
'''
with tempfile.TemporaryDirectory(prefix='arch-linux-capture-check-') as temporary:
    for helper, following, expected_status, warning in (
        ('/usr/bin/true', '/usr/bin/true', 0, False),
        ('/usr/bin/false', '/usr/bin/true', 0, True),
        ('/usr/bin/false', '/usr/bin/false', 1, True),
    ):
        result = subprocess.run(
            ['/usr/bin/bash', '-c', program, 'capture-fixture', helper,
             str(root / 'tests/vm'), temporary, following],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5,
            env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
        )
        expected_error = (b'SCREENSHOT_WARNING: optional capture unavailable: optional-fixture\n'
                          if warning else b'')
        if (result.returncode != expected_status or result.stdout != b'CAPTURE_CONTINUED\n'
                or result.stderr != expected_error):
            raise SystemExit('static check failed: optional capture masks a functional failure or blocks progress')

# A successful guest command may emit harmless GPG/pacman diagnostics. Check the actual
# wrapper: stderr alone is advisory, but an error or missing functional marker still fails.
verify = re.search(r'(?ms)^qga_verify\(\) \{\n.*?^\}\n', run)
if verify is None:
    raise SystemExit('static check failed: guest verification wrapper is absent')
import base64
import json
globals_used = '''target_serial target_model run_id scenario_id repository_primary_fingerprint
repository_signing_fingerprint release_version pages_url snapshot_sha256 source_commit source_tree
installer_sha256 repository_package_set_sha256 build_metadata_sha256 unsigned_manifest_sha256
repository_public_key_sha256'''.split()
program = 'set -Eeuo pipefail\n' + verify.group() + '\n' + '\n'.join(
    name + '=fixture' for name in globals_used) + '''
script_dir="$1" evidence="$2" response="$3" input_mode=staged marker_prefix=MINIMAL
die() { exit 2; }
qga_call() {
    if [[ "$1" = *guest-exec-status* ]]; then printf '%s\\n' "$response";
    else printf '%s\\n' '{"return":{"pid":1}}'; fi
}
qga_verify firstboot fixture
printf 'VERIFY_CONTINUED\\n'
'''
marker = ('MINIMAL_QEMU_GUEST_PASS run_id=fixture scenario=fixture phase=firstboot '
          'boot_id=00000000-0000-0000-0000-000000000001 target=fixture\n')
with tempfile.TemporaryDirectory(prefix='arch-linux-guest-status-check-') as temporary:
    for exit_code, output, diagnostics, truncated, accepted in (
        (0, marker, '', False, True),
        (0, marker, 'gpg: checking the trustdb\n', False, True),
        (1, marker, 'failure\n', False, False),
        (0, '', '', False, False),
        (0, marker, '', True, False),
    ):
        response = json.dumps({'return': {'exited': True, 'exitcode': exit_code,
            'out-data': base64.b64encode(output.encode()).decode(),
            'err-data': base64.b64encode(diagnostics.encode()).decode(),
            'out-truncated': truncated}})
        result = subprocess.run(['/usr/bin/bash', '-c', program, 'guest-status-fixture',
            str(root / 'tests/vm'), temporary, response], capture_output=True, timeout=10,
            env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
        if result.returncode != (0 if accepted else 2) or result.stdout != (
                b'VERIFY_CONTINUED\n' if accepted else b''):
            raise SystemExit('static check failed: guest status handling changed functional outcome')

grub = re.search(r'(?ms)^run_grub_mkconfig_for_regression\(\) \{\n.*?^\}\n', guest)
if grub is None:
    raise SystemExit('static check failed: GRUB regeneration command is absent')
for code in (0, 1, 7):
    program = 'set -euo pipefail\n' + grub.group() + '''
grub-mkconfig() {
    [ "$*" = '-o /boot/grub/grub.cfg' ] || return 99
    printf 'new harmless diagnostic\\n' >&2
    return "$1_CODE"
}
run_grub_mkconfig_for_regression
'''.replace('"$1_CODE"', str(code))
    result = subprocess.run(['/usr/bin/bash', '-c', program], capture_output=True, timeout=5)
    if result.returncode != code or result.stderr != b'new harmless diagnostic\n':
        raise SystemExit('static check failed: GRUB diagnostics changed the command exit status')

# The real compact collector must not treat error-handling source text inside a QGA
# request as a runtime failure. Real failure output must still survive compaction.
compact = re.search(r'(?ms)^compact_run_evidence\(\) \{\n.*?^\}\n', run)
if compact is None:
    raise SystemExit('static check failed: compact log collector is absent')
program = 'set -Eeuo pipefail\n' + compact.group() + '''
run_root="$1" evidence="$1/evidence"
remove_secret_bearing_evidence() { :; }
compact_run_evidence
'''
for failure in (False, True):
    with tempfile.TemporaryDirectory(prefix='arch-linux-compact-check-') as temporary:
        evidence = Path(temporary) / 'evidence'
        evidence.mkdir()
        actual = ('MINIMAL_QEMU_INSTALLER_EXIT status=0\n'
                  'MINIMAL_QEMU_INSTALL_COMPLETE run_id=fixture\n')
        if failure:
            actual += 'MINIMAL_QEMU_GUEST_FAIL phase=firstboot status=1\n'
        (evidence / 'runtime.stdout').write_text(actual)
        (evidence / 'firstboot.request.json').write_text(json.dumps({
            'arguments': {'script': 'printf "MINIMAL_QEMU_GUEST_FAIL status=1"'}}) + '\n')
        (evidence / 'diagnostic.txt').write_text('source mentions _QEMU_GUEST_FAIL; not a result\n')
        result = subprocess.run(['/usr/bin/bash', '-c', program, 'compact-fixture', temporary],
                                capture_output=True, timeout=5)
        import gzip
        if (result.returncode != 0 or result.stderr or
                gzip.decompress((evidence / 'scenario.log.gz').read_bytes()).decode() != actual):
            raise SystemExit('static check failed: compact log confused commands and runtime results')

keyboard = re.search(r'(?ms)^verify_graphical_locale_keyboard_contract\(\) \{\n.*?^\}\n', guest)
if (keyboard is None or keyboard.group().index('wait_for_desktop_initialization') >=
        keyboard.group().index('gsettings get')):
    raise SystemExit('static check failed: graphical settings read before initialization completes')

# Execute the same lock/unlock helper with only its host path and guest APIs replaced.
# No live-ISO bootstrap directory is present in these installed-system fixtures.
lock = re.search(r'(?ms)^run_lock_phase\(\) \{\n.*?^\}\n', guest)
if lock is None or '/run/arch-linux-qemu/lock-session-' in lock.group():
    raise SystemExit('static check failed: installed lock state depends on live ISO bootstrap')
for fault in ('none', 'existing', 'symlink', 'mode', 'session', 'shell', 'malformed'):
    with tempfile.TemporaryDirectory(prefix='arch-linux-lock-check-') as temporary:
        helper = lock.group().replace('/run/arch-linux-qemu-lock-',
                                      '${lock_fixture}/arch-linux-qemu-lock-')
        program = 'set -Eeuo pipefail\n' + helper + '''
lock_fixture="$1" fault="$2" run_id=fixture username=vmtest marker_prefix=STOCK
scenario=stock-gnome-ext4-systemdboot phase=lock test_session=c2 test_shell=4242
state_path="${lock_fixture}/arch-linux-qemu-lock-fixture.state"
wait_for_user_session() { printf '%s' "${test_session}"; }
wait_for_gnome_shell() { [ "$1" = 1000 ]; printf '%s' "${test_shell}"; }
id() { [ "$*" = '-u vmtest' ]; printf '1000'; }
stat() { command stat "$@" | sed 's/^[0-9]*:/0:/'; }
session_property() {
    [ "$1" = c2 ]
    case "$2" in
    Service) printf 'gdm-password' ;;
    Type) printf 'wayland' ;;
    LockedHint) cat "${lock_fixture}/locked" ;;
    *) return 1 ;;
    esac
}
loginctl() {
    [ "$*" = 'lock-session c2' ]
    printf 'yes' >"${lock_fixture}/locked"
}
verify_stock_session() { : >"${lock_fixture}/profile-checked"; }
case "$fault" in
existing) printf 'preserve' >"${state_path}" ;;
symlink) ln -s missing "${state_path}" ;;
esac
run_lock_phase
[ "$(command stat -c '%a:%h' "${state_path}")" = '600:1' ]
[ "$(wc -l <"${state_path}")" -eq 4 ]
case "$fault" in
mode) chmod 0666 "${state_path}" ;;
session) test_session=c3 ;;
shell) test_shell=5252 ;;
malformed) printf 'bad-state' >"${state_path}" ;;
esac
phase=unlock
printf 'no' >"${lock_fixture}/locked"
run_lock_phase
[ ! -e "${state_path}" ] && [ -f "${lock_fixture}/profile-checked" ]
'''
        result = subprocess.run(['/usr/bin/bash', '-c', program, 'lock-fixture',
                                 temporary, fault], capture_output=True, timeout=5)
        if (result.returncode == 0) != (fault == 'none'):
            raise SystemExit(f'static check failed: lock/unlock state regression: {fault}')
        state = Path(temporary) / 'arch-linux-qemu-lock-fixture.state'
        if fault == 'existing' and state.read_text() != 'preserve':
            raise SystemExit('static check failed: foreign lock state overwritten')
        if fault == 'symlink' and (not state.is_symlink() or (Path(temporary) / 'missing').exists()):
            raise SystemExit('static check failed: linked lock state followed')

print('guest framebuffer, startup, lock and diagnostic handling checks passed; QEMU=NOT_RUN')
VM_GUEST_PY

printf 'static checks passed\n'
