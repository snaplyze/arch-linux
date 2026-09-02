#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

usage() {
    cat >&2 <<USAGE
Usage: $0 RELEASE_ASSET_DIRECTORY [--phase-a|--finalized] --release-version X.Y.Z \
  --source-commit SHA --source-tree SHA [--source-tree-sha256 SHA] \
  --build-metadata-sha256 SHA --unsigned-manifest-sha256 SHA [--sealed-offline-root]

The default is finalized exact-18 verification. --phase-a verifies the exact-14
pre-QEMU closure; --finalized is an explicit alias for the default.
USAGE
}

main() {
    [ "$#" -ge 1 ] || { usage; return 2; }
    local assets_arg="$1" mode=finalized mode_seen=false sealed=false version='' source_commit='' source_tree='' source_tree_sha=''
    local build_metadata_hash='' unsigned_manifest_hash=''
    local assets archive acceptance evidence primary signing keyring work expected_checksum file cleanup_command
    local expected=() phase_a=() checksum_expected=() actual=() checksum_names=() package_set=()
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --phase-a) [ "$mode_seen" = false ] || { usage; return 2; }; mode=phase-a; mode_seen=true; shift ;;
            --finalized) [ "$mode_seen" = false ] || { usage; return 2; }; mode=finalized; mode_seen=true; shift ;;
            --release-version) [ "$#" -ge 2 ] && [ -z "$version" ] || { usage; return 2; }; version="$2"; shift 2 ;;
            --source-commit) [ "$#" -ge 2 ] && [ -z "$source_commit" ] || { usage; return 2; }; source_commit="$2"; shift 2 ;;
            --source-tree) [ "$#" -ge 2 ] && [ -z "$source_tree" ] || { usage; return 2; }; source_tree="$2"; shift 2 ;;
            --source-tree-sha256) [ "$#" -ge 2 ] && [ -z "$source_tree_sha" ] || { usage; return 2; }; source_tree_sha="$2"; shift 2 ;;
            --build-metadata-sha256) [ "$#" -ge 2 ] && [ -z "$build_metadata_hash" ] || { usage; return 2; }; build_metadata_hash="$2"; shift 2 ;;
            --unsigned-manifest-sha256) [ "$#" -ge 2 ] && [ -z "$unsigned_manifest_hash" ] || { usage; return 2; }; unsigned_manifest_hash="$2"; shift 2 ;;
            --sealed-offline-root) [ "$sealed" = false ] || { usage; return 2; }; sealed=true; shift ;;
            *) usage; return 2 ;;
        esac
    done
    [ -n "$version" ] && [ -n "$source_commit" ] && [ -n "$source_tree" ] &&
        [ -n "$build_metadata_hash" ] && [ -n "$unsigned_manifest_hash" ] || { usage; return 2; }
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || repository_die 'release version must be a SemVer triplet'
    [[ "$source_commit" =~ ^[a-f0-9]{40}$ ]] && [[ "$source_tree" =~ ^[a-f0-9]{40}$ ]] ||
        repository_die 'release source identity is malformed'
    repository_assert_sha256 "$build_metadata_hash" 'build metadata SHA-256'
    repository_assert_sha256 "$unsigned_manifest_hash" 'unsigned manifest SHA-256'
    if [ "$mode" = finalized ]; then
        repository_assert_sha256 "$source_tree_sha" 'canonical source-tree SHA-256'
    elif [ -n "$source_tree_sha" ]; then
        repository_assert_sha256 "$source_tree_sha" 'canonical source-tree SHA-256'
    fi
    for file in awk bash cat cmp find git gpg gpgv mktemp python3 realpath sha256sum sort stat zstd; do
        repository_require_command "$file"
    done
    if [ "$sealed" = true ]; then
        [ "${ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT:-}" = sealed-root-v1 ] &&
            [ "${ARCH_LINUX_OFFLINE_CODE_ROOT:-}" = "$repo_root" ] &&
            [ "${ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT:-}" = "$source_commit" ] &&
            [ "${ARCH_LINUX_OFFLINE_ACCEPTED_TREE:-}" = "$source_tree" ] ||
            repository_die 'sealed release verification requires the accepted offline namespace' || return
        [ "$(stat -Lc '%d:%i' -- "$repo_root")" = "${ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY:-}" ] ||
            repository_die 'sealed release verifier source identity differs' || return
        /usr/bin/python3 -I "${script_dir}/offline-signing-fd-guard.py" assert-public ||
            repository_die 'sealed release verification descriptor authority differs' || return
    else
        repository_assert_source_identity "$repo_root" "$source_commit" "$source_tree"
    fi
    repository_canonical_existing assets "$assets_arg" 'release assets'
    repository_assert_clean_public_tree "$assets"
    [ -z "$(find "$assets" -mindepth 1 -type d -print -quit)" ] || repository_die 'release assets must be flat'
    [ -z "$(find "$assets" -maxdepth 1 -type f ! -perm 0644 -print -quit)" ] ||
        repository_die 'release asset mode differs from 0644'

    archive="arch-linux-repository-${version}.tar.zst"
    acceptance="arch-linux-acceptance-${version}.json"
    evidence="arch-linux-acceptance-evidence-${version}.tar.zst"
    phase_a=(
        BUILD-METADATA.json RELEASE-SHA256SUMS RELEASE-SHA256SUMS.sig UNSIGNED-SHA256SUMS
        install.sh arch-linux-installer.sh arch-linux-installer.sh.sha256 arch-linux-installer.sh.sig
        arch-linux.gpg primary-fingerprint signing-subkey-fingerprint
        "$archive" "$archive.sha256" "$archive.sig"
    )
    expected=("${phase_a[@]}")
    if [ "$mode" = finalized ]; then
        expected+=("$acceptance" "$acceptance.sig" "$evidence" "$evidence.sig")
    fi
    mapfile -t expected < <(printf '%s\n' "${expected[@]}" | LC_ALL=C sort)
    mapfile -t actual < <(find "$assets" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
    [ "$(printf '%s\n' "${actual[@]}")" = "$(printf '%s\n' "${expected[@]}")" ] ||
        repository_die "release asset closure is not exact ${#expected[@]}"
    for file in "${expected[@]}"; do repository_assert_regular_file "$assets/$file" "release asset $file"; done
    for file in arch-linux.gpg primary-fingerprint signing-subkey-fingerprint; do
        cmp --silent -- "$assets/$file" "$repo_root/repository/trust/$file" ||
            repository_die "release trust file differs: $file"
    done
    repository_assert_public_certificate "$assets/arch-linux.gpg" \
        "$assets/primary-fingerprint" "$assets/signing-subkey-fingerprint"
    primary="$(repository_read_fingerprint "$assets/primary-fingerprint")"
    signing="$(repository_read_fingerprint "$assets/signing-subkey-fingerprint")"
    keyring="$assets/arch-linux.gpg"
    for file in RELEASE-SHA256SUMS arch-linux-installer.sh "$archive"; do
        repository_verify_signature "$keyring" "$assets/$file.sig" "$assets/$file" "$signing" "$primary" ||
            repository_die "release signature is invalid or from another key: $file"
    done
    if [ "$mode" = finalized ]; then
        for file in "$acceptance" "$evidence"; do
            repository_verify_signature "$keyring" "$assets/$file.sig" "$assets/$file" "$signing" "$primary" ||
                repository_die "final acceptance signature is invalid or from another key: $file"
        done
    fi

    cmp --silent -- "$assets/arch-linux-installer.sh" "$repo_root/arch-linux-installer.sh" || repository_die 'release installer differs from source tree'
    [ "$(bash "$repo_root/arch-linux-installer.sh" --version)" = "$version" ] ||
        repository_die 'sealed source-tree installer version differs'
    cmp --silent -- "$assets/install.sh" "$repo_root/install.sh" || repository_die 'release bootstrap differs from source tree'
    [ "$(repository_sha256 "$assets/BUILD-METADATA.json")" = "$build_metadata_hash" ] || repository_die 'Phase-A BUILD-METADATA.json differs'
    [ "$(repository_sha256 "$assets/UNSIGNED-SHA256SUMS")" = "$unsigned_manifest_hash" ] || repository_die 'Phase-A UNSIGNED-SHA256SUMS differs'

    expected_checksum="$(repository_sha256 "$assets/arch-linux-installer.sh") *arch-linux-installer.sh"
    [ "$(cat -- "$assets/arch-linux-installer.sh.sha256")" = "$expected_checksum" ] || repository_die 'installer checksum file differs'
    expected_checksum="$(repository_sha256 "$assets/$archive") *$archive"
    [ "$(cat -- "$assets/$archive.sha256")" = "$expected_checksum" ] || repository_die 'repository archive checksum file differs'

    checksum_expected=(BUILD-METADATA.json UNSIGNED-SHA256SUMS install.sh arch-linux-installer.sh
        arch-linux-installer.sh.sha256 arch-linux-installer.sh.sig arch-linux.gpg primary-fingerprint
        signing-subkey-fingerprint "$archive" "$archive.sha256" "$archive.sig")
    mapfile -t checksum_expected < <(printf '%s\n' "${checksum_expected[@]}" | LC_ALL=C sort)
    awk 'NF==2 && $1 ~ /^[a-f0-9]{64}$/ && $2 ~ /^\*[A-Za-z0-9][A-Za-z0-9+._-]*$/ {next} {exit 1}' \
        "$assets/RELEASE-SHA256SUMS" || repository_die 'RELEASE-SHA256SUMS syntax differs'
    mapfile -t checksum_names < <(awk '{sub(/^\*/,"",$2); print $2}' "$assets/RELEASE-SHA256SUMS" | LC_ALL=C sort)
    [ "$(printf '%s\n' "${checksum_names[@]}")" = "$(printf '%s\n' "${checksum_expected[@]}")" ] ||
        repository_die 'RELEASE-SHA256SUMS does not cover exact 12 non-self Phase-A assets'
    (cd -- "$assets" && sha256sum --check --strict --warn RELEASE-SHA256SUMS) >/dev/null

    mapfile -t package_set < <(repository_read_package_set "$script_dir/package-set")
    python3 - "$assets/BUILD-METADATA.json" "$source_commit" "$source_tree" \
        "$(repository_sha256 "$repo_root/arch-linux-installer.sh")" \
        "$(repository_sha256 "$script_dir/package-set")" "$(cat -- "$script_dir/source-date-epoch")" \
        "$unsigned_manifest_hash" "${package_set[@]}" <<'PY'
import json, pathlib, sys
path=pathlib.Path(sys.argv[1]); raw=path.read_bytes(); data=json.loads(raw)
if raw != (json.dumps(data,sort_keys=True,separators=(',',':'))+'\n').encode(): raise SystemExit('BUILD-METADATA.json is not canonical')
if set(data) != {'schema','sourceCommit','sourceTree','installerSha256','packageSetSha256','sourceDateEpoch','unsignedManifestSha256','packages'}: raise SystemExit('BUILD-METADATA.json schema differs')
if data['schema'] != 2 or data['sourceCommit'] != sys.argv[2] or data['sourceTree'] != sys.argv[3]: raise SystemExit('BUILD-METADATA.json source differs')
if data['installerSha256'] != sys.argv[4] or data['packageSetSha256'] != sys.argv[5]: raise SystemExit('BUILD-METADATA.json source hashes differ')
if data['sourceDateEpoch'] != int(sys.argv[6]) or data['unsignedManifestSha256'] != sys.argv[7]: raise SystemExit('BUILD-METADATA.json build binding differs')
expected=sys.argv[8:]
packages=data['packages']
if not isinstance(packages,list) or packages != sorted(set(packages)) or len(packages) != len(expected): raise SystemExit('BUILD-METADATA.json package closure differs')
for name in expected:
    if sum(item.startswith(name+'-') and item.endswith('.pkg.tar.zst') for item in packages) != 1: raise SystemExit('BUILD-METADATA.json package set differs')
PY

    work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/arch-linux-release-verify.XXXXXXXX")"
    printf -v cleanup_command 'rm -rf -- %q' "$work"
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT
    python3 "${script_dir}/safe-extract-snapshot.py" "$assets/$archive" "$work/extracted"
    local sealed_option=()
    [ "$sealed" = false ] || sealed_option=(--sealed-offline-root)
    "${script_dir}/verify-signed-repository.sh" "$work/extracted/repo/x86_64" \
        --release-version "$version" --source-commit "$source_commit" --source-tree "$source_tree" \
        --build-metadata-sha256 "$build_metadata_hash" --unsigned-manifest-sha256 "$unsigned_manifest_hash" \
        "${sealed_option[@]}"
    if [ "$mode" = finalized ]; then
        python3 -I "${script_dir}/acceptance-manifest.py" verify --assets "$assets" \
            --manifest "$assets/$acceptance" --source-commit "$source_commit" --source-tree "$source_tree" \
            --source-tree-sha256 "$source_tree_sha"
    fi
    trap - EXIT
    rm -rf -- "$work"
    printf 'release asset checks passed: mode=%s assets=%s version=%s\n' "$mode" "${#expected[@]}" "$version"
}

main "$@"
