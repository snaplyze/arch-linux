#!/usr/bin/env bash
set -E
set -euo pipefail
trap 'printf "ERROR: unsigned-build verification failed at source line %s\n" "$LINENO" >&2' ERR

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

usage() {
    printf 'Usage: %s [--sealed-offline-root] UNSIGNED_BUILD_DIRECTORY\n' "$0" >&2
}

main() {
    local sealed=false
    if [ "${1:-}" = --sealed-offline-root ]; then
        sealed=true
        shift
    fi
    [ "$#" -eq 1 ] || { usage; return 2; }
    local build="$1" package file info buildinfo expected actual unexpected source_epoch
    local expected_manifest source_commit source_tree installer_hash package_set_hash unsigned_hash
    local cleanup_command
    local packages=() package_files=() metadata_files=() checksum_files=()

    for command_name in awk bsdtar cmp find git grep mktemp python3 realpath sha256sum sort stat; do
        repository_require_command "$command_name"
    done
    if [ "$sealed" = true ]; then
        [ "${ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT:-}" = sealed-root-v1 ] &&
            [ "${ARCH_LINUX_OFFLINE_CODE_ROOT:-}" = "$(cd -- "$script_dir/.." && pwd -P)" ] ||
            repository_die 'sealed unsigned verification requires the offline namespace' || return
        /usr/bin/python3 -I "${script_dir}/offline-signing-fd-guard.py" assert-public ||
            repository_die 'sealed unsigned verification descriptor authority differs' || return
        source_commit="${ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT:-}"
        source_tree="${ARCH_LINUX_OFFLINE_ACCEPTED_TREE:-}"
        [[ "$source_commit" =~ ^[a-f0-9]{40}$ ]] && [[ "$source_tree" =~ ^[a-f0-9]{40}$ ]] ||
            repository_die 'sealed source identity is missing or malformed' || return
    else
        repository_read_source_identity source_commit source_tree "$script_dir/.."
    fi
    installer_hash="$(repository_sha256 "$script_dir/../arch-linux-installer.sh")"
    package_set_hash="$(repository_sha256 "${script_dir}/package-set")"
    repository_canonical_existing build "$build" 'unsigned build'
    repository_assert_clean_public_tree "$build"
    python3 "${script_dir}/verify-package-metadata.py"
    mapfile -t packages < <(repository_read_package_set "${script_dir}/package-set")
    source_epoch="$(cat -- "${script_dir}/source-date-epoch")"
    [[ "$source_epoch" =~ ^[0-9]+$ ]] || repository_die 'repository/source-date-epoch is invalid'

    unexpected="$(find "$build" -mindepth 1 -maxdepth 1 ! -type f ! -type d -print -quit)"
    [ -z "$unexpected" ] || repository_die "unsigned build contains a special object: $unexpected"
    unexpected="$(find "$build" -mindepth 1 -maxdepth 1 -type d ! -name metadata -print -quit)"
    [ -z "$unexpected" ] || repository_die "unsigned build contains an unexpected directory: $unexpected"
    repository_assert_directory "$build/metadata" 'unsigned metadata directory'

    shopt -s nullglob
    for package in "${packages[@]}"; do
        file=("$build/${package}-"*.pkg.tar.zst)
        [ "${#file[@]}" -eq 1 ] || repository_die "unsigned package closure differs for $package"
        repository_assert_regular_file "${file[0]}" "unsigned package $package"
        [ "$(stat -Lc '%a' -- "${file[0]}")" = 644 ] || repository_die "unsigned package mode differs: ${file[0]}"
        python3 "${script_dir}/verify-package-metadata.py" --verify-package "${file[0]}" "$package"
        package_files+=("${file[0]##*/}")
        [ ! -e "${file[0]}.sig" ] && [ ! -L "${file[0]}.sig" ] ||
            repository_die "unsigned build contains a package signature: ${file[0]}.sig"

        info="$(bsdtar -xOf "${file[0]}" .PKGINFO)" || repository_die "cannot read .PKGINFO: ${file[0]}"
        grep -Fqx "pkgname = $package" <<<"$info" || repository_die "package name differs in .PKGINFO: $package"
        grep -Eq '^pkgver = [^[:space:]]+$' <<<"$info" || repository_die "package version is absent: $package"
        grep -Eq '^arch = (any|x86_64)$' <<<"$info" || repository_die "package architecture differs: $package"
        bsdtar -tf "${file[0]}" | grep -Fxq '.BUILDINFO' || repository_die ".BUILDINFO is absent: $package"
        bsdtar -tf "${file[0]}" | grep -Fxq '.MTREE' || repository_die ".MTREE is absent: $package"
        buildinfo="$(bsdtar -xOf "${file[0]}" .BUILDINFO)" || repository_die "cannot read .BUILDINFO: $package"
        grep -Fqx "pkgname = $package" <<<"$buildinfo" || repository_die "package name differs in .BUILDINFO: $package"

        repository_assert_regular_file "$build/metadata/$package.SRCINFO" "source metadata $package"
        cmp --silent -- "$build/metadata/$package.SRCINFO" "$script_dir/../packages/$package/.SRCINFO" ||
            repository_die "source metadata differs from committed .SRCINFO: $package"
        metadata_files+=("$package.SRCINFO")
    done
    shopt -u nullglob

    unexpected="$(find "$build" -maxdepth 1 -type f -name '*.pkg.tar.*' \
        ! -name '*.pkg.tar.zst' -print -quit)"
    [ -z "$unexpected" ] || repository_die "unexpected package format: $unexpected"
    unexpected="$(find "$build" -maxdepth 1 -type f -name '*.sig' -print -quit)"
    [ -z "$unexpected" ] || repository_die "unsigned build contains a signature: $unexpected"

    mapfile -t actual < <(find "$build" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
    mapfile -t expected < <(
        {
            printf '%s\n' "${package_files[@]}"
            printf '%s\n' BUILD-METADATA.json UNSIGNED-SHA256SUMS
        } | LC_ALL=C sort
    )
    [ "$(printf '%s\n' "${actual[@]}")" = "$(printf '%s\n' "${expected[@]}")" ] ||
        repository_die 'unsigned build root file closure differs'
    mapfile -t actual < <(find "$build/metadata" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
    mapfile -t expected < <(printf '%s\n' "${metadata_files[@]}" | LC_ALL=C sort)
    [ "$(printf '%s\n' "${actual[@]}")" = "$(printf '%s\n' "${expected[@]}")" ] ||
        repository_die 'unsigned source metadata closure differs'

    repository_assert_regular_file "$build/UNSIGNED-SHA256SUMS" 'unsigned checksum manifest'
    expected_manifest="$(mktemp "${RUNNER_TEMP:-/tmp}/arch-linux-unsigned-checksums.XXXXXXXX")"
    printf -v cleanup_command 'rm -f -- %q' "$expected_manifest"
    # Eager capture is required because main locals do not survive EXIT.
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT
    checksum_files=("${package_files[@]}")
    for package in "${packages[@]}"; do checksum_files+=("metadata/$package.SRCINFO"); done
    (
        cd -- "$build"
        while IFS= read -r file; do sha256sum --binary -- "$file"; done \
            < <(printf '%s\n' "${checksum_files[@]}" | LC_ALL=C sort)
    ) >"$expected_manifest"
    cmp --silent -- "$expected_manifest" "$build/UNSIGNED-SHA256SUMS" ||
        repository_die 'unsigned checksum manifest differs' || return
    trap - EXIT
    rm -f -- "$expected_manifest"

    repository_assert_regular_file "$build/BUILD-METADATA.json" 'build metadata'
    unsigned_hash="$(repository_sha256 "$build/UNSIGNED-SHA256SUMS")"
    python3 - "$build/BUILD-METADATA.json" "$source_commit" "$source_tree" \
        "$installer_hash" "$package_set_hash" "$source_epoch" "$unsigned_hash" "${package_files[@]}" <<'PY'
import json, pathlib, sys
path=pathlib.Path(sys.argv[1])
raw=path.read_bytes()
try:
    data=json.loads(raw.decode('utf-8'))
except Exception as exc:
    raise SystemExit(f'invalid BUILD-METADATA.json: {exc}')
canonical=(json.dumps(data,sort_keys=True,separators=(',',':'))+'\n').encode()
if raw != canonical:
    raise SystemExit('BUILD-METADATA.json is not canonical')
expected={
    'schema':2,
    'sourceCommit':sys.argv[2],
    'sourceTree':sys.argv[3],
    'installerSha256':sys.argv[4],
    'packageSetSha256':sys.argv[5],
    'sourceDateEpoch':int(sys.argv[6]),
    'unsignedManifestSha256':sys.argv[7],
    'packages':sorted(sys.argv[8:]),
}
if data != expected:
    raise SystemExit('BUILD-METADATA.json content differs')
PY
    printf 'unsigned build checks passed: packages=%s\n' "${#packages[@]}"
}

main "$@"
