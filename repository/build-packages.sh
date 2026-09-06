#!/usr/bin/env bash
set -euo pipefail
umask 022

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

usage() {
    printf 'Usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
}

create_build_workspace() {
    local output="$1" workspace parent
    if [ -z "${WORK_DIR:-}" ]; then
        mktemp -d "${RUNNER_TEMP:-/tmp}/arch-linux-build.XXXXXXXX"
        return
    fi
    # A stable path inside each independent disposable build environment keeps
    # makepkg's real builddir/startdir provenance reproducible. Never reuse it.
    [ ! -e "$WORK_DIR" ] && [ ! -L "$WORK_DIR" ] ||
        repository_die 'package build WORK_DIR already exists' || return
    parent="$(realpath -e -- "$(dirname -- "$WORK_DIR")")" || return
    workspace="$parent/$(basename -- "$WORK_DIR")"
    repository_assert_paths_disjoint "$workspace" 'build workspace' "$repo_root" 'source tree' || return
    repository_assert_paths_disjoint "$workspace" 'build workspace' "$output" 'unsigned output' || return
    mkdir -m0700 -- "$workspace" || return
    printf '%s\n' "$workspace"
}

prefetch_marble_asset() {
    local destination="$1" work="$2"
    local metadata="$work/marble-release.json" download="$work/Marble-shell-filled-50.zip"
    local release_url='https://api.github.com/repos/imarkoff/Marble-shell-theme/releases/359996153'
    local asset_url='https://api.github.com/repos/imarkoff/Marble-shell-theme/releases/assets/490305209'
    local expected='2b5c99f676b93ad6288921c108459b3679360e33935a4f98b8c283f82eecec11'

    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
        --output "$metadata" -- "$release_url"
    jq -e --arg url "$asset_url" --arg digest "sha256:$expected" '
      .id == 359996153 and .tag_name == "50.0.0" and
      ([.assets[] | select(.id == 490305209)] | length == 1) and
      ([.assets[] | select(.id == 490305209)][0] |
        .url == $url and .name == "Marble-shell-filled-50.zip" and
        .size == 170376 and .digest == $digest and .state == "uploaded")
    ' "$metadata" >/dev/null || repository_die 'Marble release asset identity differs'
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        -H 'Accept: application/octet-stream' -H 'X-GitHub-Api-Version: 2022-11-28' \
        --output "$download" -- "$asset_url"
    [ "$(stat -Lc '%s' -- "$download")" -eq 170376 ] &&
        [ "$(repository_sha256 "$download")" = "$expected" ] ||
        repository_die 'Marble release asset bytes differ'
    install -m0644 -- "$download" "$destination"
}

main() {
    [ "$#" -eq 1 ] || { usage; return 2; }
    [ "$EUID" -ne 0 ] || repository_die 'makepkg must run as an unprivileged temporary builder'
    local requested_output="$1" output work stage staged config source_epoch package package_dir file
    local cleanup_command
    local source_commit source_tree final_commit final_tree installer_hash package_set_hash unsigned_hash
    local packages=() produced=() checksum_files=()

    for command_name in awk bash bsdtar curl find git gpg install jq makepkg python3 realpath sha256sum sort stat zstd; do
        repository_require_command "$command_name"
    done
    repository_read_source_identity source_commit source_tree "$repo_root"
    installer_hash="$(repository_sha256 "$repo_root/arch-linux-installer.sh")"
    package_set_hash="$(repository_sha256 "${script_dir}/package-set")"
    source_epoch="$(cat -- "${script_dir}/source-date-epoch")"
    [[ "$source_epoch" =~ ^[0-9]+$ ]] || repository_die 'repository/source-date-epoch is invalid'
    repository_canonical_output output "$requested_output" 'unsigned package output'
    repository_assert_paths_disjoint "$output" 'unsigned package output' "$repo_root/packages" 'package source'
    repository_assert_paths_disjoint "$output" 'unsigned package output' "$repo_root" 'source tree'
    python3 "${script_dir}/verify-package-metadata.py"
    repository_assert_public_certificate \
        "${script_dir}/trust/arch-linux.gpg" \
        "${script_dir}/trust/primary-fingerprint" \
        "${script_dir}/trust/signing-subkey-fingerprint"
    mapfile -t packages < <(repository_read_package_set "${script_dir}/package-set")

    work="$(create_build_workspace "$output")"
    printf -v cleanup_command 'rm -rf -- %q' "$work"
    # Eager capture is required because main locals do not survive EXIT.
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT
    stage="$work/output"
    staged="$work/packages"
    mkdir -p -- "$stage/metadata" "$work/sources" "$work/logs" "$work/build" "$work/home" "$work/srcpackages"
    cp -a -- "$repo_root/packages" "$staged"
    find "$staged" -type d -exec chmod 0755 -- {} +
    find "$staged" -type f -exec chmod 0644 -- {} +
    find "$staged" -type f \( -name update-compatibility -o -name '*.sh' \) -exec chmod 0755 -- {} +

    config="$work/makepkg.conf"
    cp -- /etc/makepkg.conf "$config"
    cat >>"$config" <<'CONFIG'
PACKAGER='arch-linux canonical builder <noreply@invalid>'
PKGEXT='.pkg.tar.zst'
COMPRESSZST=(zstd -c -T1 -z -q -19)
OPTIONS=(!strip !docs !libtool !staticlibs emptydirs zipman purge !debug lto)
CONFIG
    for file in arch-linux.gpg primary-fingerprint signing-subkey-fingerprint; do
        install -m0644 -- "${script_dir}/trust/$file" "$work/sources/$file"
    done
    prefetch_marble_asset "$work/sources/Marble-shell-filled-50.zip" "$work"

    for package in "${packages[@]}"; do
        package_dir="$staged/$package"
        "${script_dir}/validate-package-sources.sh" --regenerate \
            "$package_dir" "$stage/metadata/$package.SRCINFO"
        (
            cd -- "$package_dir"
            env -i HOME="$work/home" USER="$(id -un)" LOGNAME="$(id -un)" \
                PATH=/usr/local/bin:/usr/bin LANG=C.UTF-8 LC_ALL=C \
                SOURCE_DATE_EPOCH="$source_epoch" BUILDDIR="$work/build" PKGDEST="$stage" \
                SRCDEST="$work/sources" SRCPKGDEST="$work/srcpackages" LOGDEST="$work/logs" \
                makepkg --config "$config" --nodeps --noconfirm --verifysource
            env -i HOME="$work/home" USER="$(id -un)" LOGNAME="$(id -un)" \
                PATH=/usr/local/bin:/usr/bin LANG=C.UTF-8 LC_ALL=C \
                SOURCE_DATE_EPOCH="$source_epoch" BUILDDIR="$work/build" PKGDEST="$stage" \
                SRCDEST="$work/sources" SRCPKGDEST="$work/srcpackages" LOGDEST="$work/logs" \
                makepkg --config "$config" --nodeps --noconfirm --cleanbuild --clean --force
        )
    done

    shopt -s nullglob
    for package in "${packages[@]}"; do
        file=("$stage/${package}-"*.pkg.tar.zst)
        [ "${#file[@]}" -eq 1 ] || repository_die "canonical build produced an unexpected package closure: $package"
        chmod 0644 -- "${file[0]}"
        produced+=("${file[0]##*/}")
    done
    shopt -u nullglob
    checksum_files=("${produced[@]}")
    for package in "${packages[@]}"; do checksum_files+=("metadata/$package.SRCINFO"); done
    (
        cd -- "$stage"
        while IFS= read -r file; do sha256sum --binary -- "$file"; done \
            < <(printf '%s\n' "${checksum_files[@]}" | LC_ALL=C sort)
    ) >"$stage/UNSIGNED-SHA256SUMS"
    unsigned_hash="$(repository_sha256 "$stage/UNSIGNED-SHA256SUMS")"
    repository_read_source_identity final_commit final_tree "$repo_root"
    [ "$final_commit" = "$source_commit" ] && [ "$final_tree" = "$source_tree" ] ||
        repository_die 'source identity changed during package build'
    python3 - "$stage/BUILD-METADATA.json" "$source_commit" "$source_tree" \
        "$installer_hash" "$package_set_hash" "$source_epoch" "$unsigned_hash" "${produced[@]}" <<'PY'
import json, pathlib, sys
path=pathlib.Path(sys.argv[1])
data={
    'schema':2,
    'sourceCommit':sys.argv[2],
    'sourceTree':sys.argv[3],
    'installerSha256':sys.argv[4],
    'packageSetSha256':sys.argv[5],
    'sourceDateEpoch':int(sys.argv[6]),
    'unsignedManifestSha256':sys.argv[7],
    'packages':sorted(sys.argv[8:]),
}
path.write_text(json.dumps(data,sort_keys=True,separators=(',',':'))+'\n',encoding='utf-8')
PY
    chmod 0644 -- "$stage/UNSIGNED-SHA256SUMS" "$stage/BUILD-METADATA.json" "$stage"/metadata/*.SRCINFO
    "${script_dir}/verify-unsigned-build.sh" "$stage"
    mv -- "$stage" "$output"
    trap - EXIT
    rm -rf -- "$work"
    printf 'canonical unsigned package build completed: %s\n' "$output"
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    main "$@"
fi
