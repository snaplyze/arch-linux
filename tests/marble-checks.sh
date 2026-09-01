#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/arch-linux-marble-tests.XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

command -v dconf >/dev/null 2>&1 || { printf 'marble check failed: dconf is required\n' >&2; exit 1; }

profile_root="$work/profile"
mkdir -p -- "$profile_root/usr/share/arch-linux-marble"
printf '50\n' >"$profile_root/usr/share/arch-linux-marble/supported-gnome-majors"
ARCH_LINUX_MARBLE_TEST_ROOT="$profile_root" \
ARCH_LINUX_MARBLE_TEST_GNOME_PKGVER='1:50.4-1' \
PROFILE_HELPER="$repo_root/packages/arch-linux-marble-profile/update-compatibility" \
bash -euo pipefail <<'BASH'
source "$PROFILE_HELPER"
validate_assets() { return 0; }
main
[ -L "$shell_alias" ]
[ "$(readlink -- "$shell_alias")" = "$shell_payload" ]
[ -f "$dconf_defaults" ]
main # package upgrade/reconcile is idempotent
[ -L "$shell_alias" ] && [ -f "$dconf_defaults" ]
main --remove
[ ! -e "$shell_alias" ] && [ ! -L "$shell_alias" ] && [ ! -e "$dconf_defaults" ]
main # reinstall restores package-owned defaults
[ -L "$shell_alias" ] && [ -f "$dconf_defaults" ]
ARCH_LINUX_MARBLE_TEST_GNOME_PKGVER='1:51.0-1'
main # unsupported GNOME fails safely to Stock
[ ! -e "$shell_alias" ] && [ ! -L "$shell_alias" ] && [ ! -e "$dconf_defaults" ]

# A package update/removal may remove only the exact project-owned alias. Foreign state survives and
# makes the helper fail closed instead of being overwritten or silently claimed.
ln -s -- /opt/foreign-marble-theme "$shell_alias"
if main --remove; then
    : # Foreign state is deliberately preserved; package removal itself may continue.
fi
[ "$(readlink -- "$shell_alias")" = /opt/foreign-marble-theme ]
rm -f -- "$shell_alias"
printf 'foreign regular path\n' >"$shell_alias"
ARCH_LINUX_MARBLE_TEST_GNOME_PKGVER='1:50.4-1'
if main; then
    printf 'profile fixture overwrote a foreign regular alias path\n' >&2
    exit 1
fi
grep -Fxq -- 'foreign regular path' "$shell_alias"
rm -f -- "$shell_alias"
BASH

gdm_root="$work/gdm"
mkdir -p -- "$gdm_root/usr/share/arch-linux-marble-gdm/systemd"
install -m0644 -- "$repo_root/packages/arch-linux-marble-gdm/50-arch-linux-marble-gdm.conf" \
    "$gdm_root/usr/share/arch-linux-marble-gdm/systemd/50-arch-linux-marble-gdm.conf"
ARCH_LINUX_MARBLE_GDM_TEST_ROOT="$gdm_root" \
GDM_HELPER="$repo_root/packages/arch-linux-marble-gdm/update-compatibility" \
bash -euo pipefail <<'BASH'
source "$GDM_HELPER"
validate_compatibility() { return 0; }
main # install
[ -L "$active_override" ] && [ "$(readlink -- "$active_override")" = "$dropin_payload" ]
[ "$(main --status)" = active ]
main --prepare # pre-upgrade safety
[ ! -e "$active_override" ] && [ ! -L "$active_override" ]
main # post-upgrade/reinstall
[ -L "$active_override" ]
validate_compatibility() { validation_error='fixture unsupported GNOME'; return 1; }
main # unsupported GNOME restores Stock GDM
[ "$(main --status)" = stock ]
validate_compatibility() { return 0; }
main # reinstall restores the opt-in override
[ "$(main --status)" = active ]
main --remove
[ "$(main --status)" = stock ]

# Foreign activation is never removed or accepted as the managed project link.
mkdir -p -- "$override_dir"
ln -s -- /opt/foreign-marble-gdm.conf "$active_override"
main --remove
[ "$(readlink -- "$active_override")" = /opt/foreign-marble-gdm.conf ]
if main --status >/dev/null 2>&1; then
    printf 'GDM fixture accepted a foreign override\n' >&2
    exit 1
fi
rm -f -- "$active_override"

# Unsafe writable ancestry blocks both reconciliation and cleanup without creating activation.
chmod 0777 -- "$override_dir"
if disable_managed_override >/dev/null 2>&1; then
    printf 'GDM fixture accepted a world-writable override directory\n' >&2
    exit 1
fi
[ ! -e "$active_override" ] && [ ! -L "$active_override" ]
chmod 0755 -- "$override_dir"
BASH

profile_install="$repo_root/packages/arch-linux-marble-profile/arch-linux-marble-profile.install"
gdm_dropin="$repo_root/packages/arch-linux-marble-gdm/50-arch-linux-marble-gdm.conf"
grep -Fq 'post_upgrade()' "$profile_install"
grep -Fq 'pre_remove()' "$profile_install"
grep -Fq 'G_RESOURCE_OVERLAYS=' "$gdm_dropin"
grep -Fq 'DCONF_PROFILE=' "$gdm_dropin"
if grep -Rqs -- '/etc/environment' "$repo_root/packages/arch-linux-marble-gdm"; then
    printf 'Marble lifecycle check failed: GDM package writes global environment\n' >&2
    exit 1
fi
if grep -RqsE -- '/etc/(profile|profile\.d|environment\.d)|/home/|\.config/environment\.d' \
    "$repo_root/packages/arch-linux-marble-gdm"; then
    printf 'Marble lifecycle check failed: GDM package writes a user/global Shell environment\n' >&2
    exit 1
fi

printf 'Marble lifecycle checks passed\n'
