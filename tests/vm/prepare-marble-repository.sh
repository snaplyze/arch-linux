#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
    printf '%s\n' \
        'Usage: prepare-marble-repository.sh --source-root ABS --release-assets ABS --release-version VERSION' \
        '       --source-commit SHA --source-tree SHA --build-metadata-sha256 SHA256' \
        '       --unsigned-manifest-sha256 SHA256 --snapshot-sha256 SHA256 --output ABS' >&2
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

canonical_existing() {
    local destination="$1" value="$2" label="$3" resolved
    [[ "$destination" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 'invalid destination variable' || return
    [[ "$value" = /* ]] && [ "$value" != / ] || die "$label must be an absolute non-root path" || return
    resolved="$(realpath -e -- "$value")" || die "cannot resolve $label" || return
    [ "$resolved" = "$value" ] || die "$label must already be canonical" || return
    [ -d "$resolved" ] && [ ! -L "$resolved" ] || die "$label is not a real directory" || return
    printf -v "$destination" '%s' "$resolved"
}

canonical_output() {
    local destination="$1" value="$2" parent resolved
    [[ "$destination" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 'invalid destination variable' || return
    [[ "$value" = /* ]] && [ "$value" != / ] || die '--output must be an absolute non-root path' || return
    [ ! -e "$value" ] && [ ! -L "$value" ] || die '--output already exists' || return
    parent="$(dirname -- "$value")"
    resolved="$(realpath -e -- "$parent")" || die 'cannot resolve --output parent' || return
    [ "$resolved" = "$parent" ] || die '--output parent must already be canonical' || return
    [ -d "$parent" ] && [ ! -L "$parent" ] && [ -w "$parent" ] || die '--output parent is unsafe or not writable' || return
    printf -v "$destination" '%s/%s' "$parent" "$(basename -- "$value")"
}

paths_disjoint() {
    local first="$1" second="$2"
    case "$first/" in "$second/"*) return 1 ;; esac
    case "$second/" in "$first/"*) return 1 ;; esac
}

source_root='' release_assets='' output=''
source_root_arg='' release_assets_arg='' release_version='' source_commit='' source_tree=''
build_metadata_sha256='' unsigned_manifest_sha256='' snapshot_sha256='' output_arg=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --source-root) [ "$#" -ge 2 ] || { usage; exit 2; }; source_root_arg="$2"; shift 2 ;;
        --release-assets) [ "$#" -ge 2 ] || { usage; exit 2; }; release_assets_arg="$2"; shift 2 ;;
        --release-version) [ "$#" -ge 2 ] || { usage; exit 2; }; release_version="$2"; shift 2 ;;
        --source-commit) [ "$#" -ge 2 ] || { usage; exit 2; }; source_commit="$2"; shift 2 ;;
        --source-tree) [ "$#" -ge 2 ] || { usage; exit 2; }; source_tree="$2"; shift 2 ;;
        --build-metadata-sha256) [ "$#" -ge 2 ] || { usage; exit 2; }; build_metadata_sha256="$2"; shift 2 ;;
        --unsigned-manifest-sha256) [ "$#" -ge 2 ] || { usage; exit 2; }; unsigned_manifest_sha256="$2"; shift 2 ;;
        --snapshot-sha256) [ "$#" -ge 2 ] || { usage; exit 2; }; snapshot_sha256="$2"; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage; exit 2; }; output_arg="$2"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done
[ -n "$source_root_arg" ] && [ -n "$release_assets_arg" ] && [ -n "$release_version" ] &&
    [ -n "$source_commit" ] && [ -n "$source_tree" ] && [ -n "$build_metadata_sha256" ] &&
    [ -n "$unsigned_manifest_sha256" ] && [ -n "$snapshot_sha256" ] && [ -n "$output_arg" ] || {
    usage
    exit 2
}
[ "$EUID" -ne 0 ] || die 'VM repository preparation must run as an unprivileged user'
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'release version must be SemVer'
[[ "$source_commit" =~ ^[a-f0-9]{40}$ ]] || die 'source commit is malformed'
[[ "$source_tree" =~ ^[a-f0-9]{40}$ ]] || die 'source tree is malformed'
for digest in "$build_metadata_sha256" "$unsigned_manifest_sha256" "$snapshot_sha256"; do
    [[ "$digest" =~ ^[a-f0-9]{64}$ ]] || die 'release input SHA-256 is malformed'
done
for command_name in awk chmod cp find install python3 realpath sha256sum sort stat; do
    command -v -- "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
done

canonical_existing source_root "$source_root_arg" '--source-root'
canonical_existing release_assets "$release_assets_arg" '--release-assets'
canonical_output output "$output_arg"
paths_disjoint "$output" "$source_root" || die '--output overlaps source root'
paths_disjoint "$output" "$release_assets" || die '--output overlaps release assets'

script_root="$(realpath -e -- "$(dirname -- "${BASH_SOURCE[0]}")/../..")"
[ "$source_root" = "$script_root" ] || die '--source-root differs from this sidecar checkout'
repository_dir="$source_root/repository"
for required in \
    "$repository_dir/lib/common.sh" \
    "$repository_dir/package-set" \
    "$repository_dir/safe-extract-snapshot.py" \
    "$repository_dir/snapshot-manifest.py" \
    "$repository_dir/verify-signed-repository.sh" \
    "$repository_dir/verify-release-assets.sh"; do
    [ -f "$required" ] && [ ! -L "$required" ] && [ -s "$required" ] || die "required source is absent: $required"
done
# shellcheck source=repository/lib/common.sh
source "$repository_dir/lib/common.sh"

archive="$release_assets/arch-linux-repository-${release_version}.tar.zst"
"$repository_dir/verify-release-assets.sh" \
    "$release_assets" \
    --release-version "$release_version" \
    --source-commit "$source_commit" \
    --source-tree "$source_tree" \
    --build-metadata-sha256 "$build_metadata_sha256" \
    --unsigned-manifest-sha256 "$unsigned_manifest_sha256" >/dev/null
repository_assert_regular_file "$archive" 'signed repository archive'
[ "$(sha256sum --binary -- "$archive" | awk '{print $1}')" = "$snapshot_sha256" ] ||
    die 'signed repository snapshot SHA-256 differs'

cleanup_output() {
    local status=$?
    trap - EXIT HUP INT TERM
    if [ "$status" -ne 0 ] && { [ -e "$output" ] || [ -L "$output" ]; }; then
        if [ -d "$output" ] && [ ! -L "$output" ]; then
            find "$output" -xdev -depth -delete
        fi
    fi
    exit "$status"
}
trap cleanup_output EXIT HUP INT TERM
python3 "$repository_dir/safe-extract-snapshot.py" "$archive" "$output"
repo_dir="$output/repo/x86_64"
"$repository_dir/verify-signed-repository.sh" "$repo_dir" \
    --release-version "$release_version" \
    --source-commit "$source_commit" \
    --source-tree "$source_tree" \
    --build-metadata-sha256 "$build_metadata_sha256" \
    --unsigned-manifest-sha256 "$unsigned_manifest_sha256" >/dev/null

mapfile -t packages < <(repository_read_package_set "$repository_dir/package-set")
[ "${#packages[@]}" -eq 6 ] || die 'VM package set must contain exactly six packages'
primary="$(repository_read_fingerprint "$repository_dir/trust/primary-fingerprint")"
signing="$(repository_read_fingerprint "$repository_dir/trust/signing-subkey-fingerprint")"
public_key_sha256="$(sha256sum --binary -- "$repository_dir/trust/arch-linux.gpg" | awk '{print $1}')"
package_set_sha256="$(sha256sum --binary -- "$repository_dir/package-set" | awk '{print $1}')"
install -m0644 -- "$repository_dir/trust/arch-linux.gpg" "$output/arch-linux.gpg"
{
    printf 'PUBLIC_KEY_SHA256=%s\n' "$public_key_sha256"
    printf 'PRIMARY_FINGERPRINT=%s\n' "$primary"
    printf 'SIGNING_SUBKEY_FINGERPRINT=%s\n' "$signing"
    printf 'PACKAGE_SET_SHA256=%s\n' "$package_set_sha256"
    printf 'SNAPSHOT_SHA256=%s\n' "$snapshot_sha256"
    printf 'BUILD_METADATA_SHA256=%s\n' "$build_metadata_sha256"
    printf 'UNSIGNED_MANIFEST_SHA256=%s\n' "$unsigned_manifest_sha256"
    printf 'REPOSITORY_MANIFEST_SHA256=%s\n' \
        "$(sha256sum --binary -- "$repo_dir/repository-manifest.json" | awk '{print $1}')"
    printf 'REPOSITORY_MANIFEST_SIGNATURE_SHA256=%s\n' \
        "$(sha256sum --binary -- "$repo_dir/repository-manifest.json.sig" | awk '{print $1}')"
    printf 'REPOSITORY_DATABASE_SHA256=%s\n' \
        "$(sha256sum --binary -- "$repo_dir/arch-linux.db.tar.gz" | awk '{print $1}')"
    printf 'REPOSITORY_DATABASE_SIGNATURE_SHA256=%s\n' \
        "$(sha256sum --binary -- "$repo_dir/arch-linux.db.tar.gz.sig" | awk '{print $1}')"
    printf 'REPOSITORY_FILES_SHA256=%s\n' \
        "$(sha256sum --binary -- "$repo_dir/arch-linux.files.tar.gz" | awk '{print $1}')"
    printf 'REPOSITORY_FILES_SIGNATURE_SHA256=%s\n' \
        "$(sha256sum --binary -- "$repo_dir/arch-linux.files.tar.gz.sig" | awk '{print $1}')"
    shopt -s nullglob
    for package in "${packages[@]}"; do
        matches=("$repo_dir/${package}-"*.pkg.tar.zst)
        [ "${#matches[@]}" -eq 1 ] || die "signed package closure differs: $package"
        suffix="${package^^}"
        suffix="${suffix//-/_}"
        printf 'PACKAGE_SHA256_%s=%s\n' "$suffix" \
            "$(sha256sum --binary -- "${matches[0]}" | awk '{print $1}')"
    done
    shopt -u nullglob
} >"$output/repository.env"
chmod 0644 -- "$output/repository.env"

find "$output" -type d -exec chmod 0755 -- {} +
find "$output" -type f -exec chmod 0644 -- {} +
unexpected="$(find "$output" -mindepth 1 \( -type l -o ! -type f ! -type d \) -print -quit)"
[ -z "$unexpected" ] || die "VM repository contains a link or special object: $unexpected"
unexpected="$(find "$output" -type f -links +1 -print -quit)"
[ -z "$unexpected" ] || die "VM repository contains a hard-linked file: $unexpected"
trap - EXIT HUP INT TERM
printf 'prepared verified production-signed Marble repository: %s\n' "$output"
