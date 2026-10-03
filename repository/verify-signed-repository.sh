#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

usage() {
    cat >&2 <<USAGE
Usage: $0 SNAPSHOT_DIRECTORY --release-version X.Y.Z \\
  --source-commit SHA --source-tree SHA \\
  --build-metadata-sha256 SHA --unsigned-manifest-sha256 SHA \
  [--sealed-offline-root|--sealed-public-root]
USAGE
}

inspect_database_archives() {
    local database="$1" files_archive="$2"
    shift 2
    python3 "${script_dir}/verify-database-metadata.py" "$database" "$files_archive" "$@"
}

main() {
    [ "$#" -ge 1 ] || { usage; return 2; }
    local snapshot_arg="$1" sealed=false version='' source_commit='' source_tree=''
    local build_metadata_hash='' unsigned_manifest_hash=''
    local snapshot primary signing keyring package file unexpected installer_hash package_set_hash source_epoch
    local packages=() package_paths=() package_names=() expected=() actual=()
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --release-version) [ "$#" -ge 2 ] || { usage; return 2; }; version="$2"; shift 2 ;;
            --source-commit) [ "$#" -ge 2 ] || { usage; return 2; }; source_commit="$2"; shift 2 ;;
            --source-tree) [ "$#" -ge 2 ] || { usage; return 2; }; source_tree="$2"; shift 2 ;;
            --build-metadata-sha256) [ "$#" -ge 2 ] || { usage; return 2; }; build_metadata_hash="$2"; shift 2 ;;
            --unsigned-manifest-sha256) [ "$#" -ge 2 ] || { usage; return 2; }; unsigned_manifest_hash="$2"; shift 2 ;;
            --sealed-offline-root) [ "$sealed" = false ] || { usage; return 2; }; sealed=true; shift ;;
            --sealed-public-root) [ "$sealed" = false ] || { usage; return 2; }; sealed=public; shift ;;
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

    for command_name in awk cat cmp find git gpg gpgv python3 realpath sha256sum sort stat zstd; do
        repository_require_command "$command_name"
    done
    if [ "$sealed" = true ]; then
        [ "${ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT:-}" = sealed-root-v1 ] &&
            [ "${ARCH_LINUX_OFFLINE_CODE_ROOT:-}" = "$repo_root" ] &&
            [ "${ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT:-}" = "$source_commit" ] &&
            [ "${ARCH_LINUX_OFFLINE_ACCEPTED_TREE:-}" = "$source_tree" ] ||
            repository_die 'sealed repository verification requires the accepted offline namespace' || return
        [ "$(stat -Lc '%d:%i' -- "$repo_root")" = "${ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY:-}" ] ||
            repository_die 'sealed repository verifier source identity differs' || return
        /usr/bin/python3 -I "${script_dir}/offline-signing-fd-guard.py" assert-public ||
            repository_die 'sealed repository verification descriptor authority differs' || return
    elif [ "$sealed" = public ]; then
        repository_assert_sealed_public_root "$repo_root" "$source_commit" "$source_tree" \
            "${ARCH_LINUX_PUBLIC_ACCEPTED_TREE_SHA256:-}"
    else
        repository_assert_source_identity "$repo_root" "$source_commit" "$source_tree"
    fi
    installer_hash="$(repository_sha256 "$repo_root/arch-linux-installer.sh")"
    package_set_hash="$(repository_sha256 "$repo_root/repository/package-set")"
    source_epoch="$(cat -- "$repo_root/repository/source-date-epoch")"
    [[ "$source_epoch" =~ ^[0-9]+$ ]] && [ "$source_epoch" -gt 0 ] ||
        repository_die 'repository/source-date-epoch is invalid'
    repository_canonical_existing snapshot "$snapshot_arg" 'signed repository snapshot'
    repository_assert_clean_public_tree "$snapshot"
    unexpected="$(find "$snapshot" -mindepth 1 -type d -print -quit)"
    [ -z "$unexpected" ] || repository_die "signed repository must be flat: $unexpected"
    unexpected="$(find "$snapshot" -maxdepth 1 -type f ! -perm 0644 -print -quit)"
    [ -z "$unexpected" ] || repository_die "signed repository file mode differs from 0644: $unexpected"

    repository_assert_public_certificate \
        "${repo_root}/repository/trust/arch-linux.gpg" \
        "${repo_root}/repository/trust/primary-fingerprint" \
        "${repo_root}/repository/trust/signing-subkey-fingerprint"
    for file in arch-linux.gpg primary-fingerprint signing-subkey-fingerprint; do
        repository_assert_regular_file "$snapshot/$file" "snapshot trust file $file"
        cmp --silent -- "$snapshot/$file" "${repo_root}/repository/trust/$file" ||
            repository_die "snapshot trust file differs from tracked trust: $file"
    done
    primary="$(repository_read_fingerprint "${repo_root}/repository/trust/primary-fingerprint")"
    signing="$(repository_read_fingerprint "${repo_root}/repository/trust/signing-subkey-fingerprint")"

    keyring="${repo_root}/repository/trust/arch-linux.gpg"

    repository_assert_regular_file "$snapshot/repository-manifest.json" 'repository manifest'
    repository_verify_signature "$keyring" "$snapshot/repository-manifest.json.sig" \
        "$snapshot/repository-manifest.json" "$signing" "$primary" ||
        repository_die 'repository manifest signature is invalid or from another key'
    python3 "${script_dir}/snapshot-manifest.py" verify "$snapshot" \
        --version "$version" \
        --source-commit "$source_commit" \
        --source-tree "$source_tree" \
        --installer-sha256 "$installer_hash" \
        --package-set-sha256 "$package_set_hash" \
        --source-date-epoch "$source_epoch" \
        --build-metadata-sha256 "$build_metadata_hash" \
        --unsigned-manifest-sha256 "$unsigned_manifest_hash"

    mapfile -t packages < <(repository_read_package_set "${script_dir}/package-set")
    shopt -s nullglob
    for package in "${packages[@]}"; do
        file=("$snapshot/${package}-"*.pkg.tar.zst)
        [ "${#file[@]}" -eq 1 ] || repository_die "signed package closure differs for $package"
        repository_assert_regular_file "${file[0]}" "signed package $package"
        repository_verify_signature "$keyring" "${file[0]}.sig" "${file[0]}" "$signing" "$primary" ||
            repository_die "package signature is invalid or from another key: ${file[0]##*/}"
        python3 "${script_dir}/verify-package-metadata.py" --verify-package "${file[0]}" "$package"
        package_paths+=("${file[0]}")
        package_names+=("${file[0]##*/}")
        expected+=("${file[0]##*/}" "${file[0]##*/}.sig")
    done
    shopt -u nullglob

    for file in arch-linux.db.tar.gz arch-linux.files.tar.gz; do
        repository_assert_regular_file "$snapshot/$file" "$file"
        repository_verify_signature "$keyring" "$snapshot/$file.sig" "$snapshot/$file" "$signing" "$primary" ||
            repository_die "database signature is invalid or from another key: $file"
    done
    for file in arch-linux.db arch-linux.files; do
        repository_assert_regular_file "$snapshot/$file" "$file alias"
        repository_assert_regular_file "$snapshot/$file.sig" "$file alias signature"
        cmp --silent -- "$snapshot/$file" "$snapshot/$file.tar.gz" ||
            repository_die "repository alias bytes differ: $file"
        cmp --silent -- "$snapshot/$file.sig" "$snapshot/$file.tar.gz.sig" ||
            repository_die "repository alias signature differs: $file.sig"
    done
    inspect_database_archives "$snapshot/arch-linux.db.tar.gz" "$snapshot/arch-linux.files.tar.gz" \
        "${package_names[@]}"

    expected+=(
        arch-linux.db arch-linux.db.sig arch-linux.db.tar.gz arch-linux.db.tar.gz.sig
        arch-linux.files arch-linux.files.sig arch-linux.files.tar.gz arch-linux.files.tar.gz.sig
        arch-linux.gpg primary-fingerprint signing-subkey-fingerprint
        repository-manifest.json repository-manifest.json.sig
    )
    mapfile -t expected < <(printf '%s\n' "${expected[@]}" | LC_ALL=C sort)
    mapfile -t actual < <(find "$snapshot" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
    [ "$(printf '%s\n' "${actual[@]}")" = "$(printf '%s\n' "${expected[@]}")" ] ||
        repository_die 'signed repository file closure differs'

    printf 'signed repository checks passed: packages=%s\n' "${#packages[@]}"
}

main "$@"
