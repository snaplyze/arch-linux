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
for literal in 'payloadIsoSha256' 'recorderIdentities' 'challenge_measurements_are_valid' \
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
start = host.index('    if [ "${run_prefix}" = minimal ]; then\n', end)
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
print(f"VM identity checks passed: routes=7 finalizer=3 guest_negatives={guest_negatives} "
      f"finalizer_negatives={final_negatives} legacy_regressions={legacy_regressions}; QEMU=NOT_RUN")
VM_IDENTITY_PY

# FRAME_FILESYSTEM_SELFTEST_BEGIN
frame_selftest_roots=()
cleanup_frame_selftests() {
    local root
    for root in "${frame_selftest_roots[@]}"; do
        if [ -e "$root" ] || [ -L "$root" ]; then
            find "$root" -xdev -depth -delete
        fi
    done
}
frame_selftest() {
    local label="$1" parent="$2" magic="$3" root actual
    [ -d "$parent" ] && [ ! -L "$parent" ] || fail "$label self-test parent is unsafe"
    actual="$(stat --file-system --format=%t -- "$parent")"
    [ "$actual" = "$magic" ] || fail "$label self-test filesystem differs: $actual"
    root="$(mktemp -d -- "$parent/.arch-linux-frame-${label}.XXXXXXXX")"
    frame_selftest_roots+=("$root")
    chmod 0700 -- "$root"
    actual="$(stat --file-system --format=%t -- "$root")"
    [ "$actual" = "$magic" ] || fail "$label temporary filesystem differs: $actual"
    [ "$(stat --format=%a -- "$root")" = 700 ] || fail "$label temporary mode differs"
    TMPDIR="$root" PYTHONDONTWRITEBYTECODE=1 python3 -B \
        "$repo_root/tests/vm/frame-evidence.py" --self-test
    rmdir -- "$root" || fail "$label self-test left temporary residue"
}
trap cleanup_frame_selftests EXIT
frame_selftest ext4 "$(dirname -- "$repo_root")" ef53
frame_selftest tmpfs /dev/shm 1021994
trap - EXIT
# FRAME_FILESYSTEM_SELFTEST_END

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

python3 - "$repo_root" <<'FRAMEBUFFER_PY'
from pathlib import Path
import ast
import json
import os
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
run_path = root / "tests/vm/run.sh"
guest_path = root / "tests/vm/guest/verify.sh"
helper_path = root / "tests/vm/frame-evidence.py"
readme_path = root / "tests/vm/README.md"
static_path = root / "tests/static-checks.sh"
run = run_path.read_text(encoding="utf-8")
guest = guest_path.read_text(encoding="utf-8")
helper = helper_path.read_text(encoding="utf-8")
readme = readme_path.read_text(encoding="utf-8")
static = static_path.read_text(encoding="utf-8")

def function(text, name):
    match = re.search(rf"(?ms)^{re.escape(name)}\(\) \{{\n(.*?)^\}}$", text)
    if match is None:
        raise SystemExit(f"static check failed: missing function {name}")
    return match.group(1)

def ordered(text, values, label):
    position = -1
    for value in values:
        current = text.find(value, position + 1)
        if current < 0:
            raise ValueError(f"{label}: missing or misordered {value!r}")
        position = current

def contract(run_text, helper_text=helper, static_text=static):
    for literal in (
        "-device 'virtio-vga,id=display0'",
        '-qmp "unix:${runtime_dir}/qmp-recorder.sock,server=on,wait=off"',
        '-qmp "unix:${runtime_dir}/qmp-capture.sock,server=on,wait=off"',
        "tests/vm/frame-evidence.py",
        '--run-root "${run_root}"',
        "frame_recorder_event shutdown-armed",
        "frame-evidence.py\" seal",
        "manual-review-template.json",
        "build_result PENDING_VISUAL_REVIEW 0 -",
        "frame evidence failed:",
    ):
        if literal not in run_text:
            raise ValueError(f"framebuffer contract literal missing: {literal}")
    if "build_result PASS 0 -" in run_text or "hmp_request key ctrl-alt-f1" in run_text:
        raise ValueError("automated visual PASS or forced VT switch remains")
    launch = function(run_text, "launch_qemu")
    ordered(
        launch,
        ('else\n        command+=(\n            -S', 'start_frame_recorder "${phase}" boot'),
        "pause/recorder",
    )
    identity_output = '>"${evidence}/${phase}-qemu.identity"'
    identity_guard = re.search(r'if \[ "\$\{install_phase\}" = false \]; then\n(.*?)\n    fi', launch, re.S)
    if identity_guard is None or launch.count(identity_output) != 1 or \
            identity_output not in identity_guard.group(1):
        raise ValueError("install QEMU may retain an identity file")
    start = function(run_text, "start_frame_recorder")
    ordered(
        start,
        ('frame_recorder_ready=', '[ -s "${frame_recorder_ready}" ]', 'hmp_request cont -',
         'frame_recorder_event cont-sent'),
        "READY/cont",
    )
    transition = function(run_text, "schedule_transition")
    ordered(
        transition,
        ('stop_boot_frame_recorder "${phase}"', 'start_frame_recorder "${phase}" shutdown',
         'frame_recorder_event shutdown-armed', 'request="$(jq'),
        "shutdown arm",
    )
    exit_function = function(run_text, "wait_qemu_exit")
    ordered(
        exit_function,
        ('wait "${qemu_pid}"', 'finish_frame_recorder "${frame_recorder_phase}" shutdown'),
        "PID exit/recorder join",
    )
    challenge = function(run_text, "capture_minimal_tty_challenge")
    ordered(
        challenge,
        ('capture_frame "${phase}-tty-before"', 'frame_recorder_event challenge-before',
         'hmp_request type-no-enter',
         'capture_frame "${phase}-tty" challenge-before "${before}"',
         'frame_recorder_event challenge-after', 'hmp_request key ctrl-u',
         'capture_frame "${phase}-tty-cleared" challenge-after "${after}" "${before}"',
         'frame_recorder_event challenge-cleared', 'qga_verify "${phase}"'),
        "challenge chronology",
    )
    minimal = re.search(
        r'elif \[ "\$\{scenario_id\}" = minimal-ext4-systemdboot \]; then\n(.*?)\n    else',
        run_text,
        re.S,
    )
    if minimal is None:
        raise ValueError("Minimal acceptance block is missing")
    body = minimal.group(1)
    ordered(body, ('qga_verify firstboot', 'capture_minimal_tty_challenge firstboot'), "firstboot order")
    ordered(body, ('qga_verify postreboot', 'capture_minimal_tty_challenge postreboot'), "postreboot order")
    ordered(
        body,
        ('capture_minimal_tty_challenge firstboot', 'stop_boot_frame_recorder firstboot',
         'qga_verify update firstboot-update'),
        "firstboot challenge validation/update order",
    )
    stock_identity_branch = (
        'elif [ "${run_prefix}" = grub ] || [ "${run_prefix}" = luksgrub ]; then'
    )
    if stock_identity_branch not in run_text or "ALI100G" not in run_text or "ALI_GRB_" not in run_text:
        raise ValueError("Stock LUKS+GRUB disk identity differs from the final acceptance contract")
    ordered(
        function(run_text, "main"),
        ('"${qemu_img}" check -- "${run_root}/target.qcow2" >"${evidence}/final-qemu-img-check.txt"',
         'final_qemu_matches="$(find_run_qemu_processes',
         '[ -z "${final_qemu_matches}" ]', 'verify_frozen_source_unchanged',
         'remove_heavy_run_inputs\n    "${python_bin}" -I "${script_dir}/frame-evidence.py" seal',
         'finalize_run_storage', 'build_result PENDING_VISUAL_REVIEW 0 -'),
        "qemu-img/process/source recheck/heavy removal/seal/compaction/result order",
    )
    recheck = function(run_text, "verify_frozen_source_unchanged")
    for literal in (
        'status --porcelain=v1 --untracked-files=all', "rev-parse HEAD", "rev-parse 'HEAD^{tree}'",
        'arch-linux-installer.sh', 'harness.sha256', 'sha256sum --strict --check',
    ):
        if literal not in recheck:
            raise ValueError(f"pre-seal source recheck is incomplete: {literal}")
    for literal in (
        'query-status', 'prelaunch', 'gzip.compress', 'recorder gap',
        'manual-review-template.json', 'manual-review-receipt.json',
        'frame-evidence-manifest.json', 'PENDING_VISUAL_REVIEW',
        'QMP_TIMEOUT_SECONDS = MAX_GAP_MS / 1000',
        'REPOSITORY_OBJECT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]*$")',
        'manifest/ledger sample count', 'verify_current_source', 'file_binding', 'os.pread',
        '"target.qcow2", "payload.iso", "OVMF_VARS.fd", "payload", "repository"',
        'access = os.O_RDWR if retain else os.O_WRONLY',
        'access | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW',
        'value == (linked.st_dev, linked.st_ino, linked.st_size)', 'replace(staged, b"verdict")',
        'os.close(fd)\n    reject(file_binding, staged, fd, binding)',
    ):
        if literal not in helper_text:
            raise ValueError(f"frame helper contract literal missing: {literal}")
    if any(value in helper_text for value in ('export-frame', 'validate-ledger', 'contact-sheet-map')):
        raise ValueError("retired generic frame helper interface remains")
    if any(value in readme for value in ("rawArtifacts", ".tiles", "contact-sheet tile")):
        raise ValueError("retired frame manifest model remains in the VM README")
    for literal in ("fileHashes", "pendingResultSha256", "result.json", ".notes = \"\"",
                    "length == 5 and all(.[]; . == true)"):
        if literal not in readme:
            raise ValueError(f"VM README manual-review binding is incomplete: {literal}")
    static_prefix = static_text.split("python3 - \"$repo_root\" <<'FRAMEBUFFER_PY'", 1)[0]
    begin_fs = "# FRAME_FILESYSTEM_SELFTEST_BEGIN\n"
    end_fs = "# FRAME_FILESYSTEM_SELFTEST_END\n"
    if static_prefix.count(begin_fs) != 1 or static_prefix.count(end_fs) != 1:
        raise ValueError("dual-filesystem self-test markers differ")
    filesystem_gate = static_prefix.split(begin_fs, 1)[1].split(end_fs, 1)[0]
    for literal in (
        'actual="$(stat --file-system --format=%t -- "$parent")"',
        'actual="$(stat --file-system --format=%t -- "$root")"',
        'TMPDIR="$root" PYTHONDONTWRITEBYTECODE=1 python3 -B',
        'frame_selftest ext4 "$(dirname -- "$repo_root")" ef53',
        'frame_selftest tmpfs /dev/shm 1021994',
        'trap cleanup_frame_selftests EXIT', 'trap - EXIT',
    ):
        if filesystem_gate.count(literal) != 1:
            raise ValueError(f"dual-filesystem self-test gate differs: {literal}")
    parsed = ast.parse(helper_text, filename=str(helper_path))
    commands = {
        node.args[0].value
        for node in ast.walk(parsed)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "add_parser"
        and node.args
        and isinstance(node.args[0], ast.Constant)
        and isinstance(node.args[0].value, str)
    }
    if commands != {"record", "capture", "seal", "finalize-review"}:
        raise ValueError(f"frame helper command surface differs: {sorted(commands)}")
    ordered(
        helper_text,
        ('fd = write_once(pending, encoded, retain=True)', 'binding = file_binding(pending, fd)',
         'remove_tree(raw)', 'file_binding(pending, fd, binding)', 'os.rename(pending, output)',
         'file_binding(output, fd, binding)', 'finally:\n        os.close(fd)'),
        "retained verdict descriptor lifecycle",
    )
    begin_marker = "# FRAME_EVIDENCE_SELFTEST_BEGIN\n"
    end_marker = "# FRAME_EVIDENCE_SELFTEST_END\n"
    if helper_text.count(begin_marker) != 1 or helper_text.count(end_marker) != 1:
        raise ValueError("frame helper self-test markers differ")
    begin = helper_text.index(begin_marker)
    end_start = helper_text.index(end_marker)
    end = end_start + len(end_marker)
    if not begin < end_start:
        raise ValueError("frame helper self-test marker order differs")
    begin_line = helper_text[:begin].count("\n") + 1
    end_line = helper_text[:end_start].count("\n") + 1
    marked = [
        node for node in parsed.body
        if getattr(node, "lineno", 0) > begin_line and getattr(node, "end_lineno", 0) < end_line
    ]
    marked_names = [node.name for node in marked if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))]
    if marked_names != ["_selftest_fail", "_selftest_run"] or len(marked) != 2:
        raise ValueError("frame helper self-test boundary contains runtime code")
    outside_refs = [
        node.id for node in ast.walk(parsed)
        if isinstance(node, ast.Name) and node.id in set(marked_names)
        and not begin_line < node.lineno < end_line
    ]
    calls = [
        node for node in ast.walk(parsed)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "_selftest_run"
    ]
    dispatches = [
        node for node in ast.walk(parsed)
        if isinstance(node, ast.If) and ast.get_source_segment(helper_text, node.test) == "args.self_test"
        and any(isinstance(item, ast.Expr) and isinstance(item.value, ast.Call)
                and isinstance(item.value.func, ast.Name) and item.value.func.id == "_selftest_run"
                for item in node.body)
    ]
    if outside_refs != ["_selftest_run"] or len(calls) != 1 or len(dispatches) != 1 or \
            'demand(args.command is None, "--self-test cannot be combined with a command")' not in helper_text:
        raise ValueError("frame helper self-test dispatch differs")
    helper_lines = helper_text.splitlines()
    total_bytes = len(helper_text.encode("utf-8"))
    selftest_bytes = len(helper_text[begin:end].encode("utf-8"))
    runtime_bytes = total_bytes - selftest_bytes
    if runtime_bytes > 65536 or selftest_bytes > 16384 or total_bytes > 81920 or \
            len(helper_lines) > 1500 or max(map(len, helper_lines), default=0) > 120:
        raise ValueError("frame helper exceeds its narrow readable size boundary")

try:
    contract(run)
except ValueError as error:
    raise SystemExit(f"static check failed: {error}") from error

mutations = (
    run.replace("            -S\n", "", 1),
    run.replace("-device 'virtio-vga,id=display0'", "-device virtio-vga", 1),
    run.replace("frame_recorder_event shutdown-armed", ": # removed shutdown arm", 1),
    run.replace('start_frame_recorder "${phase}" shutdown', ': # removed shutdown recorder', 1),
    run.replace('start_frame_recorder "${phase}" boot', 'start_frame_recorder "${phase}"', 1),
    run.replace("build_result PENDING_VISUAL_REVIEW 0 -", "build_result PASS 0 -", 1),
    run.replace('if [ "${install_phase}" = false ]; then', 'if [ "${install_phase}" = true ]; then', 1),
    run.replace(
        '    "${qemu_img}" check -- "${run_root}/target.qcow2" >"${evidence}/final-qemu-img-check.txt"',
        ': # final qemu-img removed',
        1,
    ),
    run.replace('[ -z "${final_qemu_matches}" ] || die', 'true || die', 1),
    run.replace("verify_frozen_source_unchanged\n    remove_heavy_run_inputs", "remove_heavy_run_inputs", 1),
    run.replace(
        'remove_heavy_run_inputs\n    "${python_bin}" -I "${script_dir}/frame-evidence.py" seal',
        '"${python_bin}" -I "${script_dir}/frame-evidence.py" seal',
        1,
    ),
    run.replace(
        "qga_verify firstboot firstboot-verify\n        first_boot_id=\"${last_boot_id}\"\n        capture_minimal_tty_challenge firstboot",
        "capture_minimal_tty_challenge firstboot\n        qga_verify firstboot firstboot-verify\n        first_boot_id=\"${last_boot_id}\"",
        1,
    ),
)
for index, mutation in enumerate(mutations, 1):
    try:
        contract(mutation)
    except ValueError:
        continue
    raise SystemExit(f"static check failed: framebuffer mutation {index} was accepted")

helper_mutation = helper.replace("parser = argparse.ArgumentParser()", "parser = _selftest_fail", 1)
try:
    contract(run, helper_mutation)
except ValueError:
    pass
else:
    raise SystemExit("static check failed: runtime reference to a marked self-test symbol was accepted")

helper_mutations = (
    helper.replace('access = os.O_RDWR if retain else os.O_WRONLY', 'access = os.O_WRONLY', 1),
    helper.replace('access | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW',
                   'access | os.O_CREAT | os.O_EXCL', 1),
    helper.replace('data = os.pread(', 'data = os.read(', 1),
    helper.replace('fd = write_once(pending, encoded, retain=True)', 'fd = write_once(pending, encoded)', 1),
    helper.replace('value == (linked.st_dev, linked.st_ino, linked.st_size)', 'True', 1),
    helper.replace('        print(json.dumps(value, sort_keys=True))\n    finally:\n        os.close(fd)',
                   '        print(json.dumps(value, sort_keys=True))\n    except BaseException:\n        os.close(fd)', 1),
    helper.replace('file_binding(output, fd, binding)', 'file_binding(pending, fd, binding)', 1),
    helper.replace('replace(staged, b"verdict")', 'replace(staged, b"changed")', 1),
    helper.replace('os.close(fd)\n    reject(file_binding, staged, fd, binding)',
                   'os.close(fd)\n    pass', 1),
)
for index, mutation in enumerate(helper_mutations, 1):
    try:
        contract(run, mutation)
    except ValueError:
        continue
    raise SystemExit(f"static check failed: retained-FD helper mutation {index} was accepted")

static_mutations = (
    static.replace('frame_selftest ext4 "$(dirname -- "$repo_root")" ef53',
                   ': # removed ext4 self-test', 1),
    static.replace('frame_selftest tmpfs /dev/shm 1021994', ': # removed tmpfs self-test', 1),
    static.replace('frame_selftest ext4 "$(dirname -- "$repo_root")" ef53',
                   'frame_selftest ext4 "$(dirname -- "$repo_root")" ef52', 1),
    static.replace('frame_selftest tmpfs /dev/shm 1021994',
                   'frame_selftest tmpfs /dev/shm 1021995', 1),
    static.replace('actual="$(stat --file-system --format=%t -- "$parent")"',
                   'actual="$magic"', 1),
    static.replace('actual="$(stat --file-system --format=%t -- "$root")"',
                   'actual="$magic"', 1),
    static.replace('TMPDIR="$root" PYTHONDONTWRITEBYTECODE=1 python3 -B',
                   'TMPDIR=/tmp PYTHONDONTWRITEBYTECODE=1 python3 -B', 1),
)
for index, mutation in enumerate(static_mutations, 1):
    try:
        contract(run, helper, mutation)
    except ValueError:
        continue
    raise SystemExit(f"static check failed: filesystem self-test mutation {index} was accepted")

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

# Deterministically publish an ACK at the liveness probe, after the actual waiter's empty
# ledger poll. This is a scheduling fixture, not a QEMU or visual-acceptance substitute.
waiter = function(run, 'wait_for_frame_ledger_event')
death_branch = re.search(r'(?ms)^        if ! process_is_exact_frame_recorder .*?^        fi\n', waiter)
if death_branch is None:
    raise SystemExit('static check failed: recorder stop-ACK race handling is absent')
legacy_waiter = waiter.replace(death_branch.group(),
    '        process_is_exact_frame_recorder "${frame_recorder_pid}" "${frame_recorder_start_time}" || return 1\n', 1)
nonce = 'a' * 16
for label, event, emitted, emitted_nonce, qemu, expected in (
    ('ack-then-exit', 'stop-boot', 'stop-boot', nonce, 'alive', 0),
    ('wrong-nonce', 'stop-boot', 'stop-boot', 'b' * 16, 'alive', 1),
    ('missing-ack', 'stop-boot', None, nonce, 'alive', 1),
    ('wrong-event', 'stop-boot', 'challenge-cleared', nonce, 'alive', 1),
    ('dead-qemu', 'stop-boot', 'stop-boot', nonce, 'dead', 1),
    ('late-dead-qemu', 'stop-boot', 'stop-boot', nonce, 'late-dead', 1),
    ('nonstop-death', 'challenge-cleared', 'challenge-cleared', nonce, 'alive', 1),
):
    record = '' if emitted is None else json.dumps(
        {'e':'control', 'name':emitted, 'nonce':emitted_nonce}, separators=(',', ':'))
    for version, body in (('current', waiter), ('legacy', legacy_waiter)):
        with tempfile.TemporaryDirectory(prefix='arch-linux-stop-ack-', dir=os.environ.get('RUNNER_TEMP')) as work:
            ledger = Path(work) / 'ledger'; ledger.write_bytes(b'')
            program = '''set -Eeuo pipefail
frame_recorder_ledger=$1; event=$2; nonce=$3; record=$4; qemu=$5
qemu_pid=1; qemu_start_time=1; frame_recorder_pid=2; frame_recorder_start_time=1; probes=0
process_is_exact_qemu() {
    probes=$((probes + 1))
    [ "$qemu" != dead ] && { [ "$qemu" != late-dead ] || [ "$probes" -eq 1 ]; }
}
process_is_exact_frame_recorder() {
    printf '%s\\n' "$record" >>"$frame_recorder_ledger"
    return 1
}
wait_for_frame_ledger_event() {
''' + body + '}\nwait_for_frame_ledger_event "$event" "$nonce"\n'
            result = subprocess.run(['/usr/bin/bash', '-c', program, 'stop-ack-fixture',
                str(ledger), event, nonce, record, qemu], capture_output=True, timeout=3,
                env={'PATH':'/usr/bin:/bin', 'LC_ALL':'C'})
            wanted = expected if version == 'current' else 1
            if result.returncode != wanted or result.stdout or result.stderr:
                raise SystemExit(f'static check failed: stop-ACK fixture {label}/{version}')

# The final ledger reread is not sufficient for PASS: execute the unmodified join/exit guard
# directly under Bash errexit, with real owned children returning zero and nonzero statuses.
for child_status in (0, 3):
    with tempfile.TemporaryDirectory(prefix='arch-linux-recorder-exit-', dir=os.environ.get('RUNNER_TEMP')) as work:
        program = 'set -Eeuo pipefail\nevidence=$1\nframe_recorder_phase=firstboot\nframe_recorder_segment=boot\nframe_recorder_start_time=1\n'
        for name in ('die', 'record_frame_recorder_exit', 'finish_frame_recorder'):
            program += name + '() {\n' + function(run, name) + '}\n'
        program += '(exit "$2") &\nframe_recorder_pid=$!\nfinish_frame_recorder firstboot boot\n'
        result = subprocess.run(['/usr/bin/bash', '-c', program, 'recorder-exit-fixture', work, str(child_status)],
            capture_output=True, timeout=3, env={'PATH':'/usr/bin:/bin', 'LC_ALL':'C'})
        recorded = (Path(work) / 'firstboot-boot-frame-recorder.exit').read_text()
        if not re.fullmatch(r'phase=firstboot segment=boot recorder_pid=[1-9][0-9]* recorder_start=1 '
                            rf'exit_status={child_status}\n', recorded) or result.stdout or \
                result.returncode != (0 if child_status == 0 else 1) or \
                result.stderr != (b'' if child_status == 0 else b'QEMU_HOST_FAIL: framebuffer recorder failed: firstboot/boot: 3\n'):
            raise SystemExit('static check failed: recorder exit status was not preserved')

# A dead recorder is joined by the actual cleanup path, which must retain its status without
# changing the original host failure. Run only an owned exit-7 child; no QEMU or installer.
for existing in (False, True, 'malformed'):
    with tempfile.TemporaryDirectory(prefix='arch-linux-recorder-cleanup-', dir=os.environ.get('RUNNER_TEMP')) as work:
        root = Path(work); evidence_dir = root / 'evidence'; evidence_dir.mkdir(mode=0o700)
        receipt = evidence_dir / 'firstboot-boot-frame-recorder.exit'
        program = '''set -Eeuo pipefail
run_root=$1; evidence=$1/evidence; run_id=recorder-cleanup-fixture; current_phase=firstboot
run_storage_finalized=true; runtime_password=''; runtime_dir=''
serial_bridge_input_fd=''; serial_bridge_pid=''; qemu_pid=''; qemu_start_time=''
frame_recorder_phase=firstboot; frame_recorder_segment=boot; frame_recorder_start_time=1
stop_repository_server() { :; }
process_is_exact_frame_recorder() { return 1; }
find_run_qemu_processes() { :; }
enforce_evidence_budget() { :; }
build_result() { printf '%s:%s\\n' "$1" "$2" >"$run_root/fixture-result"; }
'''
        for name in ('record_frame_recorder_exit', 'cleanup'):
            program += name + '() {\n' + function(run, name) + '}\n'
        program += '(exit 7) &\nframe_recorder_pid=$!\n'
        if existing:
            program += ('record_frame_recorder_exit firstboot boot "$frame_recorder_pid" 1 7\n'
                        'cp -- "$evidence/firstboot-boot-frame-recorder.exit" "$run_root/first-receipt"\n')
            if existing == 'malformed':
                program += 'printf "malformed exit_status=0\\n" >"$evidence/firstboot-boot-frame-recorder.exit"\n'
        program += 'set +e\n(exit 9)\ncleanup\n'
        result = subprocess.run(['/usr/bin/bash', '-c', program, 'recorder-cleanup-fixture', work],
            capture_output=True, timeout=3, env={'PATH':'/usr/bin:/bin', 'LC_ALL':'C'})
        recorded = receipt.read_text()
        wanted_stderr = b'FAIL run_id=recorder-cleanup-fixture phase=firstboot exit_status=9\n'
        if existing == 'malformed':
            wanted_stderr = b'QEMU_HOST_FAIL: cannot preserve recorder exit diagnostics\n' + wanted_stderr
        if result.returncode != 9 or result.stdout or \
                result.stderr != wanted_stderr or \
                (root / 'fixture-result').read_text() != 'FAIL:9\n' or \
                (existing is True and recorded != (root / 'first-receipt').read_text()) or \
                (existing == 'malformed' and recorded != 'malformed exit_status=0\n') or \
                (not existing and not re.fullmatch(
                    r'phase=firstboot segment=boot recorder_pid=[1-9][0-9]* recorder_start=1 exit_status=7\n', recorded)):
            raise SystemExit('static check failed: cleanup lost recorder status or original failure')
        program = ('set -Eeuo pipefail\nrun_root=$1; evidence=$1/evidence\n'
                   'remove_secret_bearing_evidence() { :; }\n'
                   'compact_run_evidence() {\n' + function(run, 'compact_run_evidence') + '}\n'
                   'compact_run_evidence\n')
        result = subprocess.run(['/usr/bin/bash', '-c', program, 'recorder-compact-fixture', work],
            capture_output=True, timeout=3, env={'PATH':'/usr/bin:/bin', 'LC_ALL':'C'})
        import gzip
        compact = gzip.decompress((evidence_dir / 'scenario.log.gz').read_bytes()).decode()
        if result.returncode or result.stdout or result.stderr or compact.splitlines().count(recorded.strip()) != 1:
            raise SystemExit('static check failed: compaction lost bound recorder diagnostics')

# Diagnostics never create a path from an unsafe phase, segment, PID/start, status or link.
with tempfile.TemporaryDirectory(prefix='arch-linux-recorder-receipt-', dir=os.environ.get('RUNNER_TEMP')) as work:
    root = Path(work); evidence_dir = root / 'evidence'; evidence_dir.mkdir(mode=0o700)
    program = ('set -Eeuo pipefail\nevidence=$1; shift\nrecord_frame_recorder_exit() {\n' +
               function(run, 'record_frame_recorder_exit') + '}\nrecord_frame_recorder_exit "$@"\n')
    for field, invalid in ((0, '../escape'), (0, ''), (1, '../escape'), (2, '1/../../escape'),
                           (2, '0'), (2, '1'*11), (3, '-1'), (3, '1/escape'), (3, '1'*21),
                           (4, '256'), (4, '-1'), (4, '01')):
        values = ['firstboot', 'boot', '1', '1', '7']; values[field] = invalid
        result = subprocess.run(['/usr/bin/bash', '-c', program, 'recorder-receipt-fixture', str(evidence_dir), *values],
            capture_output=True, timeout=3, env={'PATH':'/usr/bin:/bin', 'LC_ALL':'C'})
        if result.returncode != 1 or result.stdout or result.stderr or list(evidence_dir.iterdir()):
            raise SystemExit('static check failed: unsafe recorder diagnostics identity accepted')
    sentinel = root / 'sentinel'; sentinel.write_bytes(b'unchanged'); sentinel.chmod(0o600)
    receipt = evidence_dir / 'firstboot-boot-frame-recorder.exit'; receipt.symlink_to(sentinel)
    result = subprocess.run(['/usr/bin/bash', '-c', program, 'recorder-receipt-fixture',
        str(evidence_dir), 'firstboot', 'boot', '1', '1', '7'], capture_output=True, timeout=3,
        env={'PATH':'/usr/bin:/bin', 'LC_ALL':'C'})
    if result.returncode != 1 or sentinel.read_bytes() != b'unchanged':
        raise SystemExit('static check failed: linked recorder receipt accepted')
    receipt.unlink()
    valid_receipt = 'phase=firstboot segment=boot recorder_pid=2 recorder_start=3 exit_status=7\n'
    for contents, cleanup, wanted in (
        (valid_receipt, 'false', 1), (valid_receipt, 'true', 0),
        (valid_receipt.replace('pid=2', 'pid=1'), 'true', 1),
        (valid_receipt.replace('start=3', 'start=4'), 'true', 1),
        (valid_receipt.replace('exit_status=7', 'exit_status=0'), 'true', 1),
        (valid_receipt.replace('firstboot', 'postreboot'), 'true', 1),
        (valid_receipt + '\n', 'true', 1), ('malformed\n', 'true', 1),
    ):
        receipt.write_text(contents); receipt.chmod(0o600)
        before = receipt.stat()
        result = subprocess.run(['/usr/bin/bash', '-c', program, 'recorder-receipt-fixture',
            str(evidence_dir), 'firstboot', 'boot', '2', '3', '7', cleanup], capture_output=True, timeout=3,
            env={'PATH':'/usr/bin:/bin', 'LC_ALL':'C'})
        after = receipt.stat()
        if result.returncode != wanted or result.stdout or result.stderr or receipt.read_text() != contents or \
                (before.st_ino, before.st_mtime_ns, before.st_ctime_ns) != \
                (after.st_ino, after.st_mtime_ns, after.st_ctime_ns):
            raise SystemExit('static check failed: existing recorder receipt accepted incorrectly or overwritten')

# Execute the real recorder loop with deterministic clocks and no VM/QMP. The unchanged exact
# 500ms boundary is accepted; +1ns must fail before another frame, sample or control ACK.
import types
for gap in (500_000_000, 500_000_001):
    scope = {'__name__':'recorder_timing_fixture', '__file__':str(helper_path)}
    exec(compile(helper, scope['__file__'], 'exec'), scope)
    with tempfile.TemporaryDirectory(prefix='arch-linux-recorder-timing-', dir=os.environ.get('RUNNER_TEMP')) as work:
        root = Path(work) / 'run'; root.mkdir(mode=0o700); (root / 'evidence').mkdir(mode=0o700)
        state = {'now':1_000_000_000, 'frames':0, 'status':0, 'controls':0, 'closed':False}
        records = []
        def advance(amount):
            state['now'] += amount
        def sleep(_):
            state['now'] = 1_000_000_000 + gap
        def exact_qemu(*_):
            if state['frames'] == 1:
                advance(5_000_000)
            return True
        class FakeQMP:
            def __init__(self, *_):
                self.identity='1:2'; self.pid=1; self.peer_uid=os.getuid()
            def status(self):
                state['status'] += 1
                return 'prelaunch' if state['status'] <= 2 else 'running'
            def frame(self, _):
                state['frames'] += 1; advance(10_000_000)
                return (1, 1, b'\0\0\0', 'a'*64, b'P6\n1 1\n255\n\0\0\0')
            def close(self):
                state['closed'] = True
        def store_raw(*_):
            advance(20_000_000)
            return 'frame.ppm.gz', 'b'*64, 0
        def append_json(_, value, first=False):
            records.append(value)
            if value['e'] == 'sample':
                advance(30_000_000)
        def read_controls(*_):
            state['controls'] += 1; advance(40_000_000)
            return 0, ([] if state['controls'] == 1 else [('stop-boot', 'c'*16)])
        scope.update(time=types.SimpleNamespace(monotonic_ns=lambda:state['now'], sleep=sleep),
            exact_qemu=exact_qemu, process_start=lambda _: '1', QMP=FakeQMP,
            store_raw=store_raw, append_json=append_json, read_controls=read_controls)
        args = types.SimpleNamespace(run_root=str(root), qmp_socket='/unused', qemu_pid=1,
            qemu_start='1', phase='firstboot', segment='boot')
        error = None
        try:
            scope['record_command'](args)
        except scope['EvidenceError'] as caught:
            error = str(caught)
        if not state['closed']:
            raise SystemExit('static check failed: recorder timing fixture did not close QMP')
        if gap == 500_000_000:
            if error or state['frames'] != 2 or records[-1]['e'] != 'terminal' or \
                    records[-1]['reason'] != 'requested-stop':
                raise SystemExit('static check failed: exact 500ms recorder boundary rejected')
        else:
            expected = 'gapNs=500000001'
            if error != expected or state['frames'] != 1 or \
                    sum(r['e'] == 'sample' for r in records) != 1 or \
                    any(r['e'] in ('control', 'terminal') for r in records):
                raise SystemExit('static check failed: over-limit recorder gap diagnostics/boundary differ')
FRAMEBUFFER_PY

printf 'static checks passed\n'
