#!/usr/bin/env bash
# Opt-in integration test; never run on an installed workstation.
# SC2016: positional arguments and HOME are intentionally expanded by inner Bash.
# shellcheck disable=SC1090,SC2034,SC2016
set -euo pipefail
[[ "${ARCH_LINUX_DISPOSABLE_BUILD:-}" = 1 && "$EUID" = 0 && -f /.dockerenv ]] || {
    echo 'Requires an explicitly authorized disposable Arch container' >&2; exit 1;
}
grep -qx 'ID=arch' /etc/os-release
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd -- "$repo_root"
source <(sed '/^main "\$@"/d' arch-linux-installer.sh)
trap - ERR EXIT
log_fail() { printf '%s\n' "$*" >&2; }
log_warn() { printf '%s\n' "$*" >&2; }
# Adapter only: production dependency resolution/payload validation is unchanged.
arch-chroot() { [ "$1" = /mnt ] || return 1; shift; "$@"; }
SCRIPT_TMP_DIR="$(mktemp -d /run/arch-linux-multilib-test.XXXXXXXX)"
builder=archlinux-multilib-test
if getent passwd "$builder" >/dev/null; then
    echo 'Refusing to reuse an existing builder identity' >&2; exit 1
fi
useradd --system --create-home --home-dir /var/lib/archlinux-multilib-test --shell /usr/bin/nologin "$builder"
builder_home=/var/lib/archlinux-multilib-test
builder_uid="$(id -u "$builder")"
cleanup() {
    local status=$?
    trap - EXIT
    pkill -KILL -u "$builder_uid" 2>/dev/null || true
    userdel -r "$builder" 2>/dev/null || true
    rm -rf -- "$SCRIPT_TMP_DIR"
    exit "$status"
}
trap cleanup EXIT
run_builder() {
    runuser -u "$builder" -- env -i HOME="$builder_home" USER="$builder" LOGNAME="$builder" \
        PATH=/usr/bin:/bin LANG=C.UTF-8 LC_ALL=C.UTF-8 MAKEFLAGS=-j4 "$@"
}
# Extract the exact production hardening program, including public-key imports.
hardening_program="$(python3 - arch-linux-installer.sh <<'PY'
from pathlib import Path
import shlex, sys
text = Path(sys.argv[1]).read_text()
anchor = text.index('# Apply only reviewed deterministic hardening changes')
start = text.index('bash -c ', anchor) + len('bash -c ')
end = text.index(' bash "$repo_tmp_dir" "$repo" ||', start)
print(shlex.split(text[start:end])[0])
PY
)"
pacman -S --noconfirm --needed lib32-glibc lib32-gcc-libs
for package in lib32-libvpx lib32-libwebp lib32-sdl2-compat lib32-sdl12-compat; do
    read -r commit archive_sha info_sha recipe_sha < <(aur_review_metadata "$package")
    build_dir="$builder_home/$package"
    run_builder timeout 180 git clone --quiet --no-checkout "https://aur.archlinux.org/$package.git" "$build_dir"
    run_builder git -C "$build_dir" checkout --quiet --detach "$commit"
    actual_archive="$(run_builder git -C "$build_dir" archive --format=tar HEAD | sha256sum | cut -d' ' -f1)"
    [ "$actual_archive" = "$archive_sha" ]
    [ "$(sha256sum "$build_dir/.SRCINFO" | cut -d' ' -f1)" = "$info_sha" ]
    [ "$(aur_srcinfo_dependencies "$package" <"$build_dir/.SRCINFO")" = "$(aur_reviewed_dependencies "$package")" ]
    chroot_aur_install_dependencies "$package"
    actual_recipe="$(run_builder bash -c "$hardening_program" bash "$build_dir" "$package")"
    [ "$actual_recipe" = "$recipe_sha" ]
    [ "$(run_builder bash -c 'cd "$1"; makepkg --printsrcinfo' _ "$build_dir" | aur_srcinfo_dependencies "$package")" = "$(aur_reviewed_dependencies "$package")" ]
    if ! run_builder timeout 1800 bash -c 'cd "$1"; makepkg --nodeps --noconfirm --cleanbuild' _ "$build_dir" >"$SCRIPT_TMP_DIR/$package.build.log" 2>&1; then
        tail -n 100 "$SCRIPT_TMP_DIR/$package.build.log"
        exit 1
    fi
    tail -n 12 "$SCRIPT_TMP_DIR/$package.build.log"
    mapfile -t outputs < <(run_builder bash -c 'cd "$1"; makepkg --packagelist' _ "$build_dir")
    [ "${#outputs[@]}" = 1 ]
    # Stop all processes of this dedicated test UID before consuming its output.
    run_builder gpgconf --kill all
    if pgrep -u "$builder_uid" >/dev/null; then
        echo 'Refusing package handoff with a live builder process' >&2; exit 1
    fi
    package_file="${outputs[0]}"
    [ -f "$package_file" ] && [ ! -L "$package_file" ]
    [ "$(stat -c '%u:%h' "$package_file")" = "$builder_uid:1" ]
    accepted="$(aur_copy_regular_file_stably "$package_file" "$SCRIPT_TMP_DIR" "$package" "$builder_uid")"
    if ! aur_package_archive_is_safe "$package" "$accepted"; then
        echo "PAYLOAD_REJECTED $package" >&2
        bsdtar --numeric-owner -tvf "$accepted"
        exit 1
    fi
    extracted="$SCRIPT_TMP_DIR/$package.elf"
    mkdir "$extracted"
    bsdtar -xf "$accepted" -C "$extracted"
    count=0
    while IFS= read -r -d '' library; do
        header="$(readelf -h "$library")"
        grep -q 'Class:.*ELF32' <<<"$header"
        grep -q 'Machine:.*Intel 80386' <<<"$header"
        count=$((count + 1))
    done < <(find "$extracted/usr/lib32" -type f -name '*.so*' -print0)
    [ "$count" -gt 0 ]
    pacman -U --noconfirm --needed -- "$accepted"
    pacman -Qkk "$package"
    echo "REAL_MULTILIB_BUILD_PASS $package elf32_libraries=$count recipe_sha256=$recipe_sha"
done
run_builder bash -c 'cat >"$HOME/load.c"' <<'C'
#include <dlfcn.h>
#include <stdio.h>
int main(void) {
    const char *names[] = {"libvpx.so", "libwebp.so", "libSDL2-2.0.so.0", "libSDL-1.2.so.0"};
    for (unsigned i = 0; i < sizeof(names)/sizeof(names[0]); ++i) {
        void *handle = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
        if (!handle) { fprintf(stderr, "%s: %s\n", names[i], dlerror()); return 1; }
        printf("ELF32_DLOPEN_PASS %s\n", names[i]);
        dlclose(handle);
    }
    return 0;
}
C
run_builder gcc -m32 -o "$builder_home/load" "$builder_home/load.c" -ldl
run_builder "$builder_home/load"
python3 tests/desktop-package-checks.py --live
echo 'REAL_MULTILIB_INTEGRATION_PASS packages=4; FULL_INSTALLATION=NOT_RUN'
