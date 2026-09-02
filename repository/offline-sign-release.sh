#!/usr/bin/env bash
set +x
set -E
set -euo pipefail
umask 077
trap 'printf "ERROR: snapshot signing command failed at source line %s\n" "$LINENO" >&2' ERR

[[ "${BASH_SOURCE[0]}" = /* ]] || { printf 'ERROR: sealed signer path is not absolute\n' >&2; exit 1; }
script_dir="${BASH_SOURCE[0]%/*}"
repo_root="${script_dir%/*}"

case "$-" in
    *p*) ;;
    *) printf 'ERROR: snapshot signing requires the sealed compiled launcher\n' >&2; exit 1 ;;
esac
if [ "${ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT:-}" != sealed-root-v1 ] ||
    [ "${GNUPGHOME:-}" != /run/user/0/arch-linux-offline/gnupg ] ||
    [ "${OFFLINE_SIGN_PASSPHRASE_FILE:-}" != /proc/self/fd/7 ] ||
    [ -n "${CI+x}" ] || [ -n "${GITHUB_ACTIONS+x}" ]; then
    printf 'ERROR: snapshot signing requires the sealed namespace boundary\n' >&2
    exit 1
fi
exec 6<&- 9<&-
fd_guard="${script_dir}/offline-signing-fd-guard.py"
readonly fd_guard
/usr/bin/python3 -I "$fd_guard" assert-signer || {
    printf 'ERROR: snapshot signing private authority is invalid\n' >&2
    exit 1
}
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

public_exec() {
    /usr/bin/python3 -I "$fd_guard" exec-public "$@" 7<&-
}

usage() {
    cat 7<&- >&2 <<USAGE
Usage: $0 --unsigned DIR --installer FILE --output DIR --release-version X.Y.Z \
  --build-metadata-sha256 SHA --unsigned-manifest-sha256 SHA

Run only as mode snapshot through the generated sealed static launcher. The
launcher passes private authority only through retained descriptors 6 and 7.
USAGE
}

sign_file() {
    local key="$1" payload="$2" signature="$3"
    [ ! -e "$signature" ] && [ ! -L "$signature" ] ||
        repository_die "signature already exists: $signature" || return
    repository_assert_regular_file "$payload" 'payload selected for signing' 7<&- || return
    /usr/bin/python3 -I "$fd_guard" exec-signing-gpg /usr/bin/gpg \
        --batch --no-options --no-autostart --no-tty --pinentry-mode loopback \
        --passphrase-file /proc/self/fd/7 --local-user "${key}!" \
        --detach-sign --output "$signature" -- "$payload" || return
    public_exec /usr/bin/chmod 0644 -- "$signature"
}

main() {
    local unsigned_arg='' installer_arg='' output_arg='' version=''
    local expected_build_metadata_hash='' expected_unsigned_manifest_hash=''
    local unsigned accepted_unsigned installer output primary signing source_epoch source_commit source_tree
    local build_metadata_hash unsigned_manifest_hash cleanup_command
    local work stage snapshot assets archive_stage archive release_manifest package file
    local packages=() package_paths=() package_names=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --unsigned) [ "$#" -ge 2 ] || { usage; return 2; }; unsigned_arg="$2"; shift 2 ;;
            --installer) [ "$#" -ge 2 ] || { usage; return 2; }; installer_arg="$2"; shift 2 ;;
            --output) [ "$#" -ge 2 ] || { usage; return 2; }; output_arg="$2"; shift 2 ;;
            --release-version) [ "$#" -ge 2 ] || { usage; return 2; }; version="$2"; shift 2 ;;
            --build-metadata-sha256)
                [ "$#" -ge 2 ] && [ -z "$expected_build_metadata_hash" ] || { usage; return 2; }
                expected_build_metadata_hash="$2"
                shift 2
                ;;
            --unsigned-manifest-sha256)
                [ "$#" -ge 2 ] && [ -z "$expected_unsigned_manifest_hash" ] || { usage; return 2; }
                expected_unsigned_manifest_hash="$2"
                shift 2
                ;;
            -h|--help) usage; return 0 ;;
            *) usage; return 2 ;;
        esac
    done
    [ -n "$unsigned_arg" ] && [ -n "$installer_arg" ] && [ -n "$output_arg" ] && [ -n "$version" ] &&
        [ -n "$expected_build_metadata_hash" ] && [ -n "$expected_unsigned_manifest_hash" ] || {
        usage
        return 2
    }
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || repository_die 'release version must be a SemVer triplet'
    repository_assert_sha256 "$expected_build_metadata_hash" 'accepted BUILD-METADATA.json SHA-256' 7<&-
    repository_assert_sha256 "$expected_unsigned_manifest_hash" 'accepted UNSIGNED-SHA256SUMS SHA-256' 7<&-
    repository_assert_loopback_only_network 7<&-

    for command_name in awk bash cmp cp find git gpg mktemp python3 realpath repo-add sha256sum sort stat tar zstd; do
        repository_require_command "$command_name" 7<&-
    done
    repository_canonical_existing unsigned "$unsigned_arg" 'unsigned build' 7<&-
    repository_canonical_existing installer "$installer_arg" 'installer' 7<&-
    repository_canonical_output output "$output_arg" 'offline release output' 7<&-
    [ "$installer" = "$repo_root/arch-linux-installer.sh" ] ||
        repository_die 'installer must be the exact sealed source-tree installer'
    repository_assert_paths_disjoint "$output" 'offline release output' "$unsigned" 'unsigned build' 7<&-
    repository_assert_paths_disjoint "$output" 'offline release output' "$repo_root" 'source tree' 7<&-
    source_commit="${ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT:-}"
    source_tree="${ARCH_LINUX_OFFLINE_ACCEPTED_TREE:-}"
    [[ "$source_commit" =~ ^[a-f0-9]{40}$ ]] && [[ "$source_tree" =~ ^[a-f0-9]{40}$ ]] ||
        repository_die 'sealed source identity is missing or malformed'
    [ "$(public_exec /usr/bin/bash "$repo_root/arch-linux-installer.sh" --version)" = "$version" ] ||
        repository_die 'sealed source-tree installer version differs from release version'
    repository_assert_regular_file "$unsigned/BUILD-METADATA.json" 'accepted build metadata' 7<&-
    repository_assert_regular_file "$unsigned/UNSIGNED-SHA256SUMS" 'accepted unsigned manifest' 7<&-
    build_metadata_hash="$(repository_sha256 "$unsigned/BUILD-METADATA.json" 7<&-)"
    unsigned_manifest_hash="$(repository_sha256 "$unsigned/UNSIGNED-SHA256SUMS" 7<&-)"
    [ "$build_metadata_hash" = "$expected_build_metadata_hash" ] ||
        repository_die 'BUILD-METADATA.json differs from the independently accepted SHA-256'
    [ "$unsigned_manifest_hash" = "$expected_unsigned_manifest_hash" ] ||
        repository_die 'UNSIGNED-SHA256SUMS differs from the independently accepted SHA-256'
    "${script_dir}/verify-unsigned-build.sh" --sealed-offline-root "$unsigned" 7<&-
    repository_assert_public_certificate \
        "${script_dir}/trust/arch-linux.gpg" \
        "${script_dir}/trust/primary-fingerprint" \
        "${script_dir}/trust/signing-subkey-fingerprint" 15552000 7<&-
    primary="$(repository_read_fingerprint "${script_dir}/trust/primary-fingerprint" 7<&-)"
    signing="$(repository_read_fingerprint "${script_dir}/trust/signing-subkey-fingerprint" 7<&-)"
    repository_assert_private_signing_subkey "$primary" "$signing" "$fd_guard"
    /usr/bin/python3 -I "$fd_guard" exec-private-gpg /usr/bin/gpg \
        --batch --no-options --no-autostart --list-keys -- "$primary" >/dev/null 2>&1 ||
        repository_die 'GNUPGHOME does not contain the required primary certificate'

    IFS= read -r source_epoch <"${script_dir}/source-date-epoch"
    [[ "$source_epoch" =~ ^[0-9]+$ ]] || repository_die 'repository/source-date-epoch is invalid'
    work="$(public_exec /usr/bin/mktemp -d \
        "${RUNNER_TEMP:-${output%/*}}/arch-linux-offline-sign.XXXXXXXX")"
    printf -v cleanup_command '/usr/bin/rm -rf -- %q 7<&-' "$work"
    # Eager capture is required because main locals do not survive EXIT.
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT
    stage="$work/stage"
    snapshot="$stage/repository"
    assets="$stage/assets"
    archive_stage="$work/archive"
    accepted_unsigned="$work/accepted-unsigned"
    public_exec /usr/bin/cp -a --no-preserve=ownership -- "$unsigned" "$accepted_unsigned"
    "${script_dir}/verify-unsigned-build.sh" --sealed-offline-root "$accepted_unsigned" 7<&-
    [ "$(repository_sha256 "$accepted_unsigned/BUILD-METADATA.json" 7<&-)" = "$expected_build_metadata_hash" ] &&
        [ "$(repository_sha256 "$accepted_unsigned/UNSIGNED-SHA256SUMS" 7<&-)" = "$expected_unsigned_manifest_hash" ] ||
        repository_die 'unsigned build changed while entering the signing boundary'
    unsigned="$accepted_unsigned"
    public_exec /usr/bin/mkdir -p -- "$snapshot" "$assets" "$archive_stage/repo/x86_64"

    mapfile -t packages < <(repository_read_package_set "${script_dir}/package-set" 7<&-)
    shopt -s nullglob
    for package in "${packages[@]}"; do
        file=("$unsigned/${package}-"*.pkg.tar.zst)
        [ "${#file[@]}" -eq 1 ] || repository_die "unsigned package closure differs for $package"
        public_exec /usr/bin/install -m0644 -- "${file[0]}" "$snapshot/${file[0]##*/}"
        public_exec /usr/bin/cmp --silent -- "${file[0]}" "$snapshot/${file[0]##*/}" ||
            repository_die "staged package readback differs: ${file[0]##*/}"
        public_exec /usr/bin/python3 "${script_dir}/verify-package-metadata.py" --verify-package \
            "$snapshot/${file[0]##*/}" "$package"
        package_paths+=("$snapshot/${file[0]##*/}")
        package_names+=("${file[0]##*/}")
    done
    shopt -u nullglob
    for file in "${package_paths[@]}"; do sign_file "$signing" "$file" "$file.sig"; done

    (
        cd -- "$snapshot"
        public_exec /usr/bin/repo-add --include-sigs arch-linux.db.tar.gz "${package_names[@]}"
    ) 7<&-
    sign_file "$signing" "$snapshot/arch-linux.db.tar.gz" "$snapshot/arch-linux.db.tar.gz.sig"
    sign_file "$signing" "$snapshot/arch-linux.files.tar.gz" "$snapshot/arch-linux.files.tar.gz.sig"
    for file in arch-linux.db.tar.gz arch-linux.db.tar.gz.sig arch-linux.files.tar.gz arch-linux.files.tar.gz.sig; do
        repository_assert_regular_file "$snapshot/$file" "repo-add output $file" 7<&-
        public_exec /usr/bin/chmod 0644 -- "$snapshot/$file"
    done
    public_exec /usr/bin/rm -f -- "$snapshot/arch-linux.db" "$snapshot/arch-linux.db.sig" \
        "$snapshot/arch-linux.files" "$snapshot/arch-linux.files.sig"
    public_exec /usr/bin/install -m0644 -- "$snapshot/arch-linux.db.tar.gz" "$snapshot/arch-linux.db"
    public_exec /usr/bin/install -m0644 -- "$snapshot/arch-linux.db.tar.gz.sig" "$snapshot/arch-linux.db.sig"
    public_exec /usr/bin/install -m0644 -- "$snapshot/arch-linux.files.tar.gz" "$snapshot/arch-linux.files"
    public_exec /usr/bin/install -m0644 -- "$snapshot/arch-linux.files.tar.gz.sig" "$snapshot/arch-linux.files.sig"
    for file in arch-linux.gpg primary-fingerprint signing-subkey-fingerprint; do
        public_exec /usr/bin/install -m0644 -- "${script_dir}/trust/$file" "$snapshot/$file"
    done
    public_exec /usr/bin/python3 "${script_dir}/snapshot-manifest.py" create "$snapshot" "$version" \
        --build-metadata "$unsigned/BUILD-METADATA.json"
    sign_file "$signing" "$snapshot/repository-manifest.json" "$snapshot/repository-manifest.json.sig"
    "${script_dir}/verify-signed-repository.sh" "$snapshot" --sealed-offline-root \
        --release-version "$version" \
        --source-commit "$source_commit" \
        --source-tree "$source_tree" \
        --build-metadata-sha256 "$expected_build_metadata_hash" \
        --unsigned-manifest-sha256 "$expected_unsigned_manifest_hash" 7<&-

    public_exec /usr/bin/cp -a -- "$snapshot/." "$archive_stage/repo/x86_64/"
    public_exec /usr/bin/find "$archive_stage" -type d -exec chmod 0755 -- {} +
    public_exec /usr/bin/find "$archive_stage" -type f -exec chmod 0644 -- {} +
    archive="$assets/arch-linux-repository-${version}.tar.zst"
    (
        cd -- "$archive_stage"
        /usr/bin/tar --sort=name --format=ustar --owner=0 --group=0 --numeric-owner \
            --mtime="@${source_epoch}" -cf - repo | /usr/bin/zstd --compress --quiet --threads=1 -19 --stdout >"$archive"
    ) 7<&-
    public_exec /usr/bin/chmod 0644 -- "$archive"
    sign_file "$signing" "$archive" "$archive.sig"
    printf '%s *%s\n' "$(repository_sha256 "$archive" 7<&-)" "${archive##*/}" >"$archive.sha256"
    public_exec /usr/bin/chmod 0644 -- "$archive.sha256"

    public_exec /usr/bin/install -m0644 -- "$repo_root/arch-linux-installer.sh" "$assets/arch-linux-installer.sh"
    sign_file "$signing" "$assets/arch-linux-installer.sh" "$assets/arch-linux-installer.sh.sig"
    printf '%s *arch-linux-installer.sh\n' \
        "$(repository_sha256 "$assets/arch-linux-installer.sh" 7<&-)" >"$assets/arch-linux-installer.sh.sha256"
    public_exec /usr/bin/chmod 0644 -- "$assets/arch-linux-installer.sh.sha256"
    public_exec /usr/bin/install -m0644 -- "$repo_root/install.sh" "$assets/install.sh"
    for file in arch-linux.gpg primary-fingerprint signing-subkey-fingerprint; do
        public_exec /usr/bin/install -m0644 -- "${script_dir}/trust/$file" "$assets/$file"
    done
    public_exec /usr/bin/install -m0644 -- "$unsigned/BUILD-METADATA.json" "$assets/BUILD-METADATA.json"
    public_exec /usr/bin/install -m0644 -- "$unsigned/UNSIGNED-SHA256SUMS" "$assets/UNSIGNED-SHA256SUMS"
    if ! public_exec /usr/bin/cmp --silent -- "$unsigned/BUILD-METADATA.json" "$assets/BUILD-METADATA.json" ||
        ! public_exec /usr/bin/cmp --silent -- "$unsigned/UNSIGNED-SHA256SUMS" "$assets/UNSIGNED-SHA256SUMS"; then
        repository_die 'accepted build manifests changed while creating Phase A'
    fi

    release_manifest="$assets/RELEASE-SHA256SUMS"
    (
        cd -- "$assets"
        while IFS= read -r -d '' file; do sha256sum --binary -- "${file#./}"; done \
            < <(find . -mindepth 1 -maxdepth 1 -type f \
                ! -name RELEASE-SHA256SUMS ! -name RELEASE-SHA256SUMS.sig -print0 | LC_ALL=C sort -z)
    ) 7<&- >"$release_manifest"
    public_exec /usr/bin/chmod 0644 -- "$release_manifest"
    sign_file "$signing" "$release_manifest" "$release_manifest.sig"
    "${script_dir}/verify-release-assets.sh" "$assets" --phase-a --sealed-offline-root \
        --release-version "$version" \
        --source-commit "$source_commit" \
        --source-tree "$source_tree" \
        --build-metadata-sha256 "$expected_build_metadata_hash" \
        --unsigned-manifest-sha256 "$expected_unsigned_manifest_hash" 7<&-

    public_exec /usr/bin/python3 -I "$fd_guard" atomic-publish "$stage" "$output"
    trap - EXIT
    public_exec /usr/bin/rm -rf -- "$work"
    printf 'offline release signing completed: %s\n' "$output"
}

main "$@"
