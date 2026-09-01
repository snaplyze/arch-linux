#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

usage() {
    cat >&2 <<USAGE
Usage: $0 RELEASE_ASSET_DIRECTORY --release-version X.Y.Z \\
  --source-commit SHA --source-tree SHA \\
  --build-metadata-sha256 SHA --unsigned-manifest-sha256 SHA
USAGE
}

main() {
    [ "$#" -ge 1 ] || { usage; return 2; }
    local assets_arg="$1" version='' source_commit='' source_tree=''
    local build_metadata_hash='' unsigned_manifest_hash=''
    local assets archive primary signing keyring work expected_checksum file cleanup_command
    local expected=() actual=() checksum_names=()
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --release-version) [ "$#" -ge 2 ] || { usage; return 2; }; version="$2"; shift 2 ;;
            --source-commit) [ "$#" -ge 2 ] || { usage; return 2; }; source_commit="$2"; shift 2 ;;
            --source-tree) [ "$#" -ge 2 ] || { usage; return 2; }; source_tree="$2"; shift 2 ;;
            --build-metadata-sha256) [ "$#" -ge 2 ] || { usage; return 2; }; build_metadata_hash="$2"; shift 2 ;;
            --unsigned-manifest-sha256) [ "$#" -ge 2 ] || { usage; return 2; }; unsigned_manifest_hash="$2"; shift 2 ;;
            *) usage; return 2 ;;
        esac
    done
    [ -n "$version" ] && [ -n "$source_commit" ] && [ -n "$source_tree" ] &&
        [ -n "$build_metadata_hash" ] && [ -n "$unsigned_manifest_hash" ] || {
        usage
        return 2
    }
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || repository_die 'release version must be a SemVer triplet'
    repository_assert_sha256 "$build_metadata_hash" 'build metadata SHA-256'
    repository_assert_sha256 "$unsigned_manifest_hash" 'unsigned manifest SHA-256'
    for command_name in awk bash cat cmp find git gpg gpgv mktemp python3 realpath sha256sum sort stat zstd; do
        repository_require_command "$command_name"
    done
    repository_assert_source_identity "$repo_root" "$source_commit" "$source_tree"
    repository_canonical_existing assets "$assets_arg" 'release assets'
    repository_assert_clean_public_tree "$assets"
    [ -z "$(find "$assets" -mindepth 1 -type d -print -quit)" ] || repository_die 'release assets must be flat'
    [ -z "$(find "$assets" -maxdepth 1 -type f ! -perm 0644 -print -quit)" ] ||
        repository_die 'release asset mode differs from 0644'

    archive="arch-linux-repository-${version}.tar.zst"
    expected=(
        RELEASE-SHA256SUMS RELEASE-SHA256SUMS.sig
        install.sh
        arch-linux-installer.sh arch-linux-installer.sh.sha256 arch-linux-installer.sh.sig
        arch-linux.gpg primary-fingerprint signing-subkey-fingerprint
        "$archive" "$archive.sha256" "$archive.sig"
    )
    mapfile -t expected < <(printf '%s\n' "${expected[@]}" | LC_ALL=C sort)
    mapfile -t actual < <(find "$assets" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
    [ "$(printf '%s\n' "${actual[@]}")" = "$(printf '%s\n' "${expected[@]}")" ] ||
        repository_die 'release asset closure differs'

    for file in "${expected[@]}"; do repository_assert_regular_file "$assets/$file" "release asset $file"; done
    for file in arch-linux.gpg primary-fingerprint signing-subkey-fingerprint; do
        cmp --silent -- "$assets/$file" "$repo_root/repository/trust/$file" ||
            repository_die "release trust file differs: $file"
    done
    repository_assert_public_certificate \
        "$repo_root/repository/trust/arch-linux.gpg" \
        "$repo_root/repository/trust/primary-fingerprint" \
        "$repo_root/repository/trust/signing-subkey-fingerprint"
    primary="$(repository_read_fingerprint "$repo_root/repository/trust/primary-fingerprint")"
    signing="$(repository_read_fingerprint "$repo_root/repository/trust/signing-subkey-fingerprint")"

    work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/arch-linux-release-verify.XXXXXXXX")"
    printf -v cleanup_command 'rm -rf -- %q' "$work"
    # Eager capture is required because main locals do not survive EXIT.
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT
    keyring="$assets/arch-linux.gpg"
    for file in RELEASE-SHA256SUMS arch-linux-installer.sh "$archive"; do
        repository_verify_signature "$keyring" "$assets/$file.sig" "$assets/$file" "$signing" "$primary" ||
            repository_die "release signature is invalid or from another key: $file"
    done

    [ "$(bash "$assets/arch-linux-installer.sh" --version)" = "$version" ] ||
        repository_die 'release installer version differs'
    cmp --silent -- "$assets/arch-linux-installer.sh" "$repo_root/arch-linux-installer.sh" ||
        repository_die 'release installer differs from source tree'
    cmp --silent -- "$assets/install.sh" "$repo_root/install.sh" ||
        repository_die 'release bootstrap differs from source tree'

    expected_checksum="$(repository_sha256 "$assets/arch-linux-installer.sh") *arch-linux-installer.sh"
    [ "$(cat -- "$assets/arch-linux-installer.sh.sha256")" = "$expected_checksum" ] ||
        repository_die 'installer checksum file differs'
    expected_checksum="$(repository_sha256 "$assets/$archive") *$archive"
    [ "$(cat -- "$assets/$archive.sha256")" = "$expected_checksum" ] ||
        repository_die 'repository archive checksum file differs'

    mapfile -t checksum_names < <(awk '{name=$2; sub(/^\*/,"",name); print name}' "$assets/RELEASE-SHA256SUMS")
    mapfile -t actual < <(printf '%s\n' "${checksum_names[@]}" | LC_ALL=C sort)
    mapfile -t expected < <(find "$assets" -mindepth 1 -maxdepth 1 -type f \
        ! -name RELEASE-SHA256SUMS ! -name RELEASE-SHA256SUMS.sig -printf '%f\n' | LC_ALL=C sort)
    [ "$(printf '%s\n' "${actual[@]}")" = "$(printf '%s\n' "${expected[@]}")" ] ||
        repository_die 'RELEASE-SHA256SUMS file closure differs'
    (
        cd -- "$assets"
        sha256sum --check --strict --warn RELEASE-SHA256SUMS
    ) >/dev/null

    python3 "${script_dir}/safe-extract-snapshot.py" "$assets/$archive" "$work/extracted"
    "${script_dir}/verify-signed-repository.sh" "$work/extracted/repo/x86_64" \
        --release-version "$version" \
        --source-commit "$source_commit" \
        --source-tree "$source_tree" \
        --build-metadata-sha256 "$build_metadata_hash" \
        --unsigned-manifest-sha256 "$unsigned_manifest_hash"
    trap - EXIT
    rm -rf -- "$work"
    printf 'release asset checks passed: version=%s\n' "$version"
}

main "$@"
