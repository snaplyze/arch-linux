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
