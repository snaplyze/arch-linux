#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
export LC_ALL=C

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
host="${repo_root}/tests/vm/run.sh"
bootstrap="${repo_root}/tests/vm/guest/bootstrap.sh"
verify="${repo_root}/tests/vm/guest/verify.sh"
preflight="${repo_root}/tests/vm/preflight.sh"

fail() {
    printf 'VM harness check failed: %s\n' "$*" >&2
    exit 1
}

for source in "${host}" "${bootstrap}" "${verify}"; do
    if [ ! -f "${source}" ] || [ -L "${source}" ]; then
        fail "unsafe harness source: ${source}"
    fi
    ! grep -Fq -- '1.0.1' "${source}" || fail "release version is hard-coded: ${source}"
done

grep -Fq -- "[[ \"\${release_version}\" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\$ ]]" "${host}" ||
    fail 'host does not validate passed release version'
grep -Fq -- "[[ \"\${IDENTITY[RELEASE_VERSION]}\" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\$ ]]" \
    "${bootstrap}" || fail 'bootstrap does not validate passed release version'
grep -Fq -- "[[ \"\${release_version}\" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\$ ]]" "${verify}" ||
    fail 'guest verifier does not validate passed release version'

grep -Fq -- "refs/tags/\${release_version}" "${host}" ||
    fail 'public release tag is not bound to the passed version'
grep -Fq -- "source_commit=\"\$(git -C \"\${repository_root}\" rev-parse \"refs/tags/\${release_version}^{commit}\")\"" \
    "${host}" || fail 'public release commit is not recorded separately from harness commit'
grep -Fq -- "source_tree=\"\$(git -C \"\${repository_root}\" rev-parse \"refs/tags/\${release_version}^{tree}\")\"" \
    "${host}" || fail 'public release tree is not recorded separately from harness tree'
grep -Fq -- 'verify-release-assets.sh' "${host}" ||
    fail 'staged source-bound snapshot verifier is absent'
for legacy_option in --legacy-release-assets --legacy-release-version --legacy-snapshot-sha256; do
    grep -Fq -- "${legacy_option}" "${host}" ||
        fail "legacy migration input is absent: ${legacy_option}"
done
grep -Fq -- 'prepare_legacy_repository_input' "${host}" ||
    fail 'legacy signed repository validation is absent'
if ! grep -Fq -- 'legacy-install' "${host}" || ! grep -Fq -- 'migration-update' "${host}"; then
    fail 'legacy-to-candidate package transition is absent'
fi
if ! grep -Fq -- 'fresh-user-login' "${host}" || ! grep -Fq -- 'return-user-login' "${host}"; then
    fail 'second ordinary user GDM round trip is absent'
fi
grep -Fq -- 'gtk4-app-smoke' "${verify}" ||
    fail 'GTK4/libadwaita application smoke phase is absent'
grep -Fq -- 'systemd-run --user --quiet --collect' "${verify}" ||
    fail 'GTK4 application smoke does not inherit the real user-manager environment'
grep -Fq -- 'verify_user_manager_graphical_environment' "${verify}" ||
    fail 'GTK4 application smoke does not validate the real graphical session environment'
grep -Fq -- 'GTK4_APP_LAUNCH_FAIL' "${verify}" ||
    fail 'GTK4 application launch failures do not retain unit and journal diagnostics'
grep -Fq -- 'reason=missing-executable' "${verify}" ||
    fail 'GTK4 application smoke does not identify a missing executable'
grep -Fq -- 'GTK4_APP_(DIAGNOSTIC|LAUNCH_FAIL)' "${host}" ||
    fail 'bounded GTK4 application diagnostics are absent from the compact summary'
(
    eval "$(sed -n '/^verify_user_manager_graphical_environment() {/,/^}/p' "${verify}")"
    manager_environment=$'XDG_CURRENT_DESKTOP=GNOME\nXDG_SESSION_TYPE=wayland\nWAYLAND_DISPLAY=wayland-1'
    # shellcheck disable=SC2329 # Invoked indirectly by the extracted verifier helper above.
    run_in_user_session() { printf '%s\n' "${manager_environment}"; }
    verify_user_manager_graphical_environment 1000 ||
        fail 'valid real user-manager graphical environment was rejected'
    manager_environment=$'XDG_SESSION_TYPE=wayland\nWAYLAND_DISPLAY=wayland-1'
    if verify_user_manager_graphical_environment 1000; then
        fail 'missing GNOME desktop environment was accepted for graphical app launch'
    fi
    manager_environment=$'XDG_CURRENT_DESKTOP=GNOME\nXDG_SESSION_TYPE=wayland'
    if verify_user_manager_graphical_environment 1000; then
        fail 'missing Wayland display environment was accepted for graphical app launch'
    fi
)
(
    eval "$(sed -n '/^provision_gtk4_smoke_dependencies() {/,/^}/p' "${verify}")"
    # shellcheck disable=SC2034 # Consumed by the extracted verifier helper above.
    boxes_installed=false install_calls=0 metadata_signed=true phase=fixture
    # shellcheck disable=SC2329 # Invoked indirectly by the extracted verifier helper above.
    package_installed_exact() {
        [ "$1" = gnome-boxes ] && [ "${boxes_installed}" = true ]
    }
    # shellcheck disable=SC2329 # Invoked indirectly by the extracted verifier helper above.
    pacman() {
        case "$1" in
        -S)
            [ "$#" -eq 5 ] && [ "$2" = --needed ] && [ "$3" = --noconfirm ] &&
                [ "$4" = --disable-download-timeout ] && [ "$5" = extra/gnome-boxes ]
            install_calls=$((install_calls + 1))
            boxes_installed=true
            ;;
        -Qi)
            [ "$2" = -- ] && [ "$3" = gnome-boxes ]
            printf 'Name            : gnome-boxes\n'
            if [ "${metadata_signed}" = true ]; then
                printf 'Validated By    : Signature\n'
            else
                printf 'Validated By    : None\n'
            fi
            ;;
        *) return 1 ;;
        esac
    }
    provision_gtk4_smoke_dependencies 2>/dev/null ||
        fail 'missing Boxes dependency was not provisioned'
    [ "${install_calls}" -eq 1 ] || fail 'missing Boxes dependency did not trigger one install'
    install_calls=0
    provision_gtk4_smoke_dependencies 2>/dev/null ||
        fail 'installed signed Boxes dependency was rejected'
    [ "${install_calls}" -eq 0 ] || fail 'installed Boxes dependency was reinstalled'
    metadata_signed=false
    if provision_gtk4_smoke_dependencies 2>/dev/null; then
        fail 'unsigned Boxes dependency metadata was accepted'
    fi
)
grep -Fq -- 'installed_package_record_exact' "${verify}" ||
    fail 'package assertions do not reject provider-only pacman query matches'
if grep -Eq 'pacman -Q (arch-linux-colloid-gtk3|arch-linux-colloid-gtk)([[:space:]]|$)' "${verify}"; then
    fail 'migration package assertion still accepts pacman provider resolution'
fi
(
    eval "$(sed -n '/^installed_package_record_exact() {/,/^}/p; /^installed_package_version_exact() {/,/^}/p; /^package_installed_exact() {/,/^}/p' "${verify}")"
    # shellcheck disable=SC2329 # Invoked indirectly by the extracted verifier helpers above.
    pacman() {
        [ "$1" = -Q ] && [ "$2" = -- ]
        case "$3" in
        arch-linux-colloid-gtk3) printf '%s\n' 'arch-linux-colloid-gtk 20260808-5' ;;
        arch-linux-colloid-gtk) printf '%s\n' 'arch-linux-colloid-gtk 20260808-5' ;;
        *) return 1 ;;
        esac
    }
    if package_installed_exact arch-linux-colloid-gtk3; then
        fail 'exact-name helper accepted a provider returned by pacman -Q'
    fi
    package_installed_exact arch-linux-colloid-gtk ||
        fail 'exact-name helper rejected the installed package name'
    [ "$(installed_package_version_exact arch-linux-colloid-gtk)" = 20260808-5 ] ||
        fail 'exact-name helper did not return the exact package version'
)
grep -Fq -- '/run/arch-linux-qemu-gdm-profile' "${verify}" ||
    fail 'fresh-user login does not install an effective test-owned GDM profile'
grep -Fq -- 'legacy-repository-manifest.json | legacy-repository-manifest.json.sig' "${host}" ||
    fail 'legacy signed manifest evidence is not retained explicitly'
grep -Fq -- 'legacy-extracted' "${host}" ||
    fail 'legacy extraction scratch is not removed by finalization'
grep -Fq -- '"sourceCommit"' "${verify}" ||
    fail 'public repository manifest does not bind its source commit'
grep -Fq -- '"sourceTree"' "${verify}" ||
    fail 'public repository manifest does not bind its source tree'

grep -Fq -- 'TARGET_DISK_METADATA' "${host}" ||
    fail 'target disk metadata mode is absent from host harness'
grep -Fq -- 'TARGET_DISK_METADATA' "${bootstrap}" ||
    fail 'bootstrap does not enforce target disk metadata mode'
grep -Fq -- 'target_disk_metadata' "${verify}" ||
    fail 'guest verifier does not enforce target disk metadata mode'
grep -Fq -- 'virtio-blk-pci,id=targetdev,drive=target' "${host}" ||
    fail 'metadata-absent target does not use a virtio disk'

if [ ! -f "${preflight}" ] || [ -L "${preflight}" ]; then
    fail 'VM preflight is absent or unsafe'
fi
grep -Fq -- '--scenario' "${preflight}" || fail 'VM preflight is not scenario-aware'
grep -Fq -- '/dev/kvm' "${preflight}" || fail 'VM preflight does not check KVM access'
grep -Fq -- 'qemu-system-x86_64' "${preflight}" || fail 'VM preflight does not probe QEMU KVM acceleration'
grep -Fq -- 'VM_PREFLIGHT_RESULT schema=1' "${preflight}" || fail 'VM preflight result marker is absent'

printf 'VM_HARNESS_CHECKS_RESULT schema=1 version_provenance=passed metadata_absent=passed; QEMU=NOT_RUN\n'
