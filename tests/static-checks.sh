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
    maintenance/check-arch-iso.py maintenance/check-sources.py maintenance/sources.json
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
for literal in release_id release_version source_commit source_tree snapshot_sha256 \
    build_metadata_sha256 unsigned_manifest_sha256 'GH_TOKEN: ${{ github.token }}' \
    'releases/${RELEASE_ID}' 'draft == true' '(.assets | length == 12)' \
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
for path in repository/run-offline-signing.sh repository/offline-sign-release.sh; do
    for literal in --build-metadata-sha256 --unsigned-manifest-sha256; do
        grep -Fq -- "$literal" "$repo_root/$path" ||
            fail "independently accepted signing digest absent from $path: $literal"
    done
done
for literal in '/usr/bin/env -i' '.arch-linux-disposable-signing-home' \
    'arch-linux-signing-home\.' '--net' '--pid' '--kill-child=SIGKILL' '--mount-proc'; do
    grep -Fq -- "$literal" "$repo_root/repository/run-offline-signing.sh" ||
        fail "offline signing boundary assertion absent: $literal"
done
! grep -Eq -- 'export-secret|cp[^\n]*GNUPGHOME' "$repo_root/repository/run-offline-signing.sh" ||
    fail 'offline signing wrapper copies or exports private key material'

python3 - "$repo_root" <<'CLEANUP_PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
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

printf 'static checks passed\n'
