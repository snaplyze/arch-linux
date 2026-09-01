#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

usage() {
    printf 'Usage: %s [--regenerate] PACKAGE_DIRECTORY [SRCINFO_OUTPUT]\n' "$0" >&2
}

main() {
    local regenerate=false package_dir='' output='' generated work='' cleanup_command=''
    if [ "${1:-}" = --regenerate ]; then
        regenerate=true
        shift
    fi
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage; return 2; }
    package_dir="$1"
    output="${2:-}"
    repository_assert_directory "$package_dir" 'package directory'
    repository_assert_regular_file "$package_dir/PKGBUILD" 'PKGBUILD'
    repository_assert_regular_file "$package_dir/.SRCINFO" 'committed .SRCINFO'
    python3 "${script_dir}/verify-package-metadata.py"

    if [ "$regenerate" = true ]; then
        [ "$EUID" -ne 0 ] || repository_die 'PKGBUILD metadata regeneration must run unprivileged'
        repository_require_command makepkg
        work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/arch-linux-srcinfo.XXXXXXXX")"
        printf -v cleanup_command 'rm -rf -- %q' "$work"
        # Eager capture is required because main locals do not survive EXIT.
        # shellcheck disable=SC2064
        trap "$cleanup_command" EXIT
        generated="$work/.SRCINFO"
        (
            cd -- "$package_dir"
            env -i HOME="$work" USER="$(id -un)" LOGNAME="$(id -un)" \
                PATH=/usr/local/bin:/usr/bin LANG=C.UTF-8 LC_ALL=C \
                makepkg --printsrcinfo
        ) >"$generated"
        cmp --silent -- "$generated" "$package_dir/.SRCINFO" ||
            repository_die "committed .SRCINFO differs from makepkg output: $(basename -- "$package_dir")"
    else
        generated="$package_dir/.SRCINFO"
    fi

    if [ -n "$output" ]; then
        [ ! -e "$output" ] && [ ! -L "$output" ] || repository_die "SRCINFO output already exists: $output"
        install -Dm0644 -- "$generated" "$output"
    fi
    if [ -n "$work" ]; then
        trap - EXIT
        rm -rf -- "$work"
    fi
    printf 'package source metadata passed: %s\n' "$(basename -- "$package_dir")"
}

main "$@"
