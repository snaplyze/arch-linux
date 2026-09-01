#!/usr/bin/env bash
set +x
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

usage() {
    cat >&2 <<USAGE
Usage: $0 --unsigned DIR --installer FILE --output DIR --release-version X.Y.Z \
  --build-metadata-sha256 SHA --unsigned-manifest-sha256 SHA

Run only through repository/run-offline-signing.sh with GNUPGHOME pointing to
a caller-prepared, explicitly marked disposable mode-0700 signing home. The
wrapper deletes that home on exit; this inner signer never deletes a signing
home itself. No private key, passphrase, token, or recovery material is
accepted as an argument or written to output.
USAGE
}

sign_file() {
    local key="$1" payload="$2" signature="$3"
    [ ! -e "$signature" ] && [ ! -L "$signature" ] || repository_die "signature already exists: $signature"
    gpg --batch --no-options --local-user "${key}!" --detach-sign --output "$signature" -- "$payload"
    chmod 0644 -- "$signature"
}

main() {
    local unsigned_arg='' installer_arg='' output_arg='' version=''
    local expected_build_metadata_hash='' expected_unsigned_manifest_hash=''
    local unsigned accepted_unsigned installer output gnupg_home primary signing source_epoch source_commit source_tree
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
    repository_assert_sha256 "$expected_build_metadata_hash" 'accepted BUILD-METADATA.json SHA-256'
    repository_assert_sha256 "$expected_unsigned_manifest_hash" 'accepted UNSIGNED-SHA256SUMS SHA-256'
    [ "${CI:-false}" != true ] && [ "${GITHUB_ACTIONS:-false}" != true ] ||
        repository_die 'private-key signing is forbidden in CI and GitHub Actions'
    [ -n "${GNUPGHOME:-}" ] || repository_die 'GNUPGHOME must identify the existing local private signing home'
    repository_assert_loopback_only_network

    for command_name in awk bash cmp cp find git gpg mktemp python3 realpath repo-add sha256sum sort stat tar zstd; do
        repository_require_command "$command_name"
    done
    repository_canonical_existing unsigned "$unsigned_arg" 'unsigned build'
    repository_canonical_existing installer "$installer_arg" 'installer'
    repository_canonical_existing gnupg_home "$GNUPGHOME" 'GNUPGHOME'
    [ "$(stat -Lc '%u' -- "$gnupg_home")" = "$EUID" ] &&
        [ "$(stat -Lc '%a' -- "$gnupg_home")" = 700 ] ||
        repository_die 'GNUPGHOME must be owned by the signing user and have mode 0700'
    repository_canonical_output output "$output_arg" 'offline release output'
    repository_assert_paths_disjoint "$output" 'offline release output' "$unsigned" 'unsigned build'
    repository_assert_paths_disjoint "$output" 'offline release output' "$repo_root" 'source tree'
    repository_assert_paths_disjoint "$gnupg_home" 'private signing home' "$repo_root" 'source tree'
    repository_assert_paths_disjoint "$gnupg_home" 'private signing home' "$unsigned" 'unsigned build'
    repository_assert_paths_disjoint "$gnupg_home" 'private signing home' "$output" 'offline release output'
    repository_read_source_identity source_commit source_tree "$repo_root"
    [ "$(bash "$installer" --version)" = "$version" ] || repository_die 'installer version differs from release version'
    cmp --silent -- "$installer" "$repo_root/arch-linux-installer.sh" ||
        repository_die 'installer input differs from the source-tree installer'
    repository_assert_regular_file "$unsigned/BUILD-METADATA.json" 'accepted build metadata'
    repository_assert_regular_file "$unsigned/UNSIGNED-SHA256SUMS" 'accepted unsigned manifest'
    build_metadata_hash="$(repository_sha256 "$unsigned/BUILD-METADATA.json")"
    unsigned_manifest_hash="$(repository_sha256 "$unsigned/UNSIGNED-SHA256SUMS")"
    [ "$build_metadata_hash" = "$expected_build_metadata_hash" ] ||
        repository_die 'BUILD-METADATA.json differs from the independently accepted SHA-256'
    [ "$unsigned_manifest_hash" = "$expected_unsigned_manifest_hash" ] ||
        repository_die 'UNSIGNED-SHA256SUMS differs from the independently accepted SHA-256'
    "${script_dir}/verify-unsigned-build.sh" "$unsigned"
    repository_assert_public_certificate \
        "${script_dir}/trust/arch-linux.gpg" \
        "${script_dir}/trust/primary-fingerprint" \
        "${script_dir}/trust/signing-subkey-fingerprint"
    primary="$(repository_read_fingerprint "${script_dir}/trust/primary-fingerprint")"
    signing="$(repository_read_fingerprint "${script_dir}/trust/signing-subkey-fingerprint")"
    GNUPGHOME="$gnupg_home" gpg --batch --no-options --list-secret-keys "${signing}!" >/dev/null 2>&1 ||
        repository_die 'GNUPGHOME does not contain the required signing subkey'
    GNUPGHOME="$gnupg_home" gpg --batch --no-options --list-keys "$primary" >/dev/null 2>&1 ||
        repository_die 'GNUPGHOME does not contain the required primary certificate'
    export GNUPGHOME="$gnupg_home"

    source_epoch="$(cat -- "${script_dir}/source-date-epoch")"
    [[ "$source_epoch" =~ ^[0-9]+$ ]] || repository_die 'repository/source-date-epoch is invalid'
    work="$(mktemp -d "${RUNNER_TEMP:-$(dirname -- "$output")}/arch-linux-offline-sign.XXXXXXXX")"
    printf -v cleanup_command 'rm -rf -- %q' "$work"
    # Eager capture is required because main locals do not survive EXIT.
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT
    stage="$work/stage"
    snapshot="$stage/repository"
    assets="$stage/assets"
    archive_stage="$work/archive"
    accepted_unsigned="$work/accepted-unsigned"
    cp -a --no-preserve=ownership -- "$unsigned" "$accepted_unsigned"
    "${script_dir}/verify-unsigned-build.sh" "$accepted_unsigned"
    [ "$(repository_sha256 "$accepted_unsigned/BUILD-METADATA.json")" = "$expected_build_metadata_hash" ] &&
        [ "$(repository_sha256 "$accepted_unsigned/UNSIGNED-SHA256SUMS")" = "$expected_unsigned_manifest_hash" ] ||
        repository_die 'unsigned build changed while entering the signing boundary'
    unsigned="$accepted_unsigned"
    mkdir -p -- "$snapshot" "$assets" "$archive_stage/repo/x86_64"

    mapfile -t packages < <(repository_read_package_set "${script_dir}/package-set")
    shopt -s nullglob
    for package in "${packages[@]}"; do
        file=("$unsigned/${package}-"*.pkg.tar.zst)
        [ "${#file[@]}" -eq 1 ] || repository_die "unsigned package closure differs for $package"
        install -m0644 -- "${file[0]}" "$snapshot/${file[0]##*/}"
        cmp --silent -- "${file[0]}" "$snapshot/${file[0]##*/}" ||
            repository_die "staged package readback differs: ${file[0]##*/}"
        python3 "${script_dir}/verify-package-metadata.py" --verify-package \
            "$snapshot/${file[0]##*/}" "$package"
        package_paths+=("$snapshot/${file[0]##*/}")
        package_names+=("${file[0]##*/}")
    done
    shopt -u nullglob
    for file in "${package_paths[@]}"; do sign_file "$signing" "$file" "$file.sig"; done

    (
        cd -- "$snapshot"
        repo-add --sign --key "${signing}!" --include-sigs arch-linux.db.tar.gz "${package_names[@]}"
    )
    for file in arch-linux.db.tar.gz arch-linux.db.tar.gz.sig arch-linux.files.tar.gz arch-linux.files.tar.gz.sig; do
        repository_assert_regular_file "$snapshot/$file" "repo-add output $file"
        chmod 0644 -- "$snapshot/$file"
    done
    rm -f -- "$snapshot/arch-linux.db" "$snapshot/arch-linux.db.sig" \
        "$snapshot/arch-linux.files" "$snapshot/arch-linux.files.sig"
    install -m0644 -- "$snapshot/arch-linux.db.tar.gz" "$snapshot/arch-linux.db"
    install -m0644 -- "$snapshot/arch-linux.db.tar.gz.sig" "$snapshot/arch-linux.db.sig"
    install -m0644 -- "$snapshot/arch-linux.files.tar.gz" "$snapshot/arch-linux.files"
    install -m0644 -- "$snapshot/arch-linux.files.tar.gz.sig" "$snapshot/arch-linux.files.sig"
    for file in arch-linux.gpg primary-fingerprint signing-subkey-fingerprint; do
        install -m0644 -- "${script_dir}/trust/$file" "$snapshot/$file"
    done
    python3 "${script_dir}/snapshot-manifest.py" create "$snapshot" "$version" \
        --build-metadata "$unsigned/BUILD-METADATA.json"
    sign_file "$signing" "$snapshot/repository-manifest.json" "$snapshot/repository-manifest.json.sig"
    "${script_dir}/verify-signed-repository.sh" "$snapshot" \
        --release-version "$version" \
        --source-commit "$source_commit" \
        --source-tree "$source_tree" \
        --build-metadata-sha256 "$expected_build_metadata_hash" \
        --unsigned-manifest-sha256 "$expected_unsigned_manifest_hash"

    cp -a -- "$snapshot/." "$archive_stage/repo/x86_64/"
    find "$archive_stage" -type d -exec chmod 0755 -- {} +
    find "$archive_stage" -type f -exec chmod 0644 -- {} +
    archive="$assets/arch-linux-repository-${version}.tar.zst"
    (
        cd -- "$archive_stage"
        tar --sort=name --format=ustar --owner=0 --group=0 --numeric-owner \
            --mtime="@${source_epoch}" -cf - repo | zstd --compress --quiet --threads=1 -19 --stdout >"$archive"
    )
    chmod 0644 -- "$archive"
    sign_file "$signing" "$archive" "$archive.sig"
    printf '%s *%s\n' "$(repository_sha256 "$archive")" "${archive##*/}" >"$archive.sha256"
    chmod 0644 -- "$archive.sha256"

    install -m0644 -- "$installer" "$assets/arch-linux-installer.sh"
    sign_file "$signing" "$assets/arch-linux-installer.sh" "$assets/arch-linux-installer.sh.sig"
    printf '%s *arch-linux-installer.sh\n' \
        "$(repository_sha256 "$assets/arch-linux-installer.sh")" >"$assets/arch-linux-installer.sh.sha256"
    install -m0644 -- "$repo_root/install.sh" "$assets/install.sh"
    for file in arch-linux.gpg primary-fingerprint signing-subkey-fingerprint; do
        install -m0644 -- "${script_dir}/trust/$file" "$assets/$file"
    done

    release_manifest="$assets/RELEASE-SHA256SUMS"
    (
        cd -- "$assets"
        while IFS= read -r -d '' file; do sha256sum --binary -- "${file#./}"; done \
            < <(find . -mindepth 1 -maxdepth 1 -type f \
                ! -name RELEASE-SHA256SUMS ! -name RELEASE-SHA256SUMS.sig -print0 | LC_ALL=C sort -z)
    ) >"$release_manifest"
    chmod 0644 -- "$release_manifest"
    sign_file "$signing" "$release_manifest" "$release_manifest.sig"
    "${script_dir}/verify-release-assets.sh" "$assets" \
        --release-version "$version" \
        --source-commit "$source_commit" \
        --source-tree "$source_tree" \
        --build-metadata-sha256 "$expected_build_metadata_hash" \
        --unsigned-manifest-sha256 "$expected_unsigned_manifest_hash"

    mv -- "$stage" "$output"
    trap - EXIT
    rm -rf -- "$work"
    printf 'offline release signing completed: %s\n' "$output"
}

main "$@"
