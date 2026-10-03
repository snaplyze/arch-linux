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

# Execute host routing, including rejection of staged and nonqualification public combinations.
# shellcheck disable=SC2034 # Inputs are consumed by the extracted production validator.
(
    mode_validator="$(sed -n '/^validate_vm_mode_scenario() {/,/^}/p' "${host}")"
    [ -n "$mode_validator" ] || fail 'media qualification routing helper is missing'
    eval "$mode_validator"
    # shellcheck disable=SC2329
    die() { return 1; }
    for scenario_id in minimal-ext4-systemdboot stock-gnome-ext4-systemdboot; do
        input_mode=public media_qualification=true
        validate_vm_mode_scenario || fail 'public media qualification scenario was rejected'
        media_qualification=false
        if validate_vm_mode_scenario; then fail 'ordinary public mode accepted a media-only scenario'; fi
        input_mode=staged media_qualification=true
        if validate_vm_mode_scenario; then fail 'staged mode accepted media qualification'; fi
    done
    input_mode=public media_qualification=false
    scenario_id=marble-gnome-btrfs-luks2-plymouth-systemdboot
    validate_vm_mode_scenario || fail 'ordinary public Marble was rejected'
    media_qualification=true
    if validate_vm_mode_scenario; then fail 'qualification accepted Marble'; fi
)

# Exercise known firmware pairs with real temporary files; no host path is altered.
python3 - "$host" "$preflight" <<'FIRMWARE_PY'
from pathlib import Path
import re
import subprocess
import sys
import tempfile
for script in sys.argv[1:]:
    body = re.search(r'^select_ovmf_pair\(\) \{\n.*?^\}', Path(script).read_text(), re.M | re.S).group(0)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        ubuntu = root / 'OVMF'
        arch = root / 'edk2/x64'
        ubuntu.mkdir()
        arch.mkdir(parents=True)
        def run():
            program = ('set -euo pipefail\ndie(){ return 1; }\n' + body.replace('/usr/share', tmp) +
                       '\nselect_ovmf_pair\nprintf "%s:%s" "$ovmf_code" "$ovmf_vars_template"\n')
            return subprocess.run(['bash', '-c', program], capture_output=True, text=True, timeout=5)
        assert run().returncode != 0
        code = ubuntu / 'OVMF_CODE_4M.fd'
        code.write_bytes(b'code')
        (arch / 'OVMF_VARS.4m.fd').write_bytes(b'vars')
        assert run().returncode != 0  # never mix distributions
        (arch / 'OVMF_CODE.4m.fd').write_bytes(b'code')
        assert run().stdout == str(arch / 'OVMF_CODE.4m.fd') + ':' + str(arch / 'OVMF_VARS.4m.fd')
        (ubuntu / 'OVMF_VARS_4M.fd').symlink_to(arch / 'OVMF_VARS.4m.fd')
        assert run().stdout.startswith(str(arch))  # refuse linked firmware
        (ubuntu / 'OVMF_VARS_4M.fd').unlink()
        (ubuntu / 'OVMF_VARS_4M.fd').write_bytes(b'vars')
        assert run().stdout == str(code) + ':' + str(ubuntu / 'OVMF_VARS_4M.fd')
FIRMWARE_PY

# Exercise the disposable collision stage: require actual refusal plus unchanged complete
# partition hashes, then remove only its generated writers and preserve isolated neighbor files.
python3 - "$bootstrap" <<'COLLISION_PY'
from pathlib import Path
import re
import subprocess
import sys
import tempfile
source = Path(sys.argv[1]).read_text()
body = re.search(r'^prove_dual_boot_collision_refusal\(\) \{\n.*?^\}', source, re.M | re.S).group(0)
for outcome in ('refused', 'accepted', 'root-changed', 'esp-changed', 'missing-password', 'wrong-password', 'wrong-refusal-cause', 'timeout', 'neighbor-check-failed', 'esp-read-failed'):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        esp = root / 'esp-files'
        esp.mkdir()
        for name in ('EFI/systemd/systemd-bootx64.efi', 'EFI/BOOT/BOOTX64.EFI',
                     'vmlinuz-linux', 'initramfs-linux.img', 'loader/random-seed',
                     'loader/loader.conf', 'loader/entries/main.conf',
                     'EFI/ali-neighbor/vmlinuz-linux', 'loader/entries/neighbor.conf',
                     'loader/entries.srel'):
            path = esp / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'fixture')
        (root / 'esp').write_bytes(b'ESP partition bytes')
        (root / 'target-root').write_bytes(b'root partition bytes')
        if outcome == 'esp-read-failed':
            (root / 'esp').unlink()
        # Execute the producer's real timeout/env/Bash command through a bounded installer fixture.
        # Its input prerequisite catches /dev/null and suppressed serial prompts in the producer.
        (root / 'arch-linux-installer.sh').write_text(r'''#!/usr/bin/env bash
set -euo pipefail
[ "${FORCE}" = true ] && [ "${DEBUG}" = false ]
printf '+ Enter Password\n'
IFS= read -r first || exit 113
printf '+ Enter Password again\n'
IFS= read -r second || exit 113
[ -n "$first" ] && [ "$first" = "$second" ] || exit 114
printf 'FIXTURE_PASSWORD_PREREQUISITE_PASSED\n'
case "${COLLISION_FIXTURE_OUTCOME}" in
accepted) exit 0 ;;
timeout) exit 124 ;;
root-changed) printf mutation > target-root ;;
esp-changed) printf mutation > esp ;;
wrong-refusal-cause) printf 'unrelated failure\n' > installer.log; exit 1 ;;
esac
printf 'Dual-boot ESP collision or unsafe ancestor\n' > installer.log
exit 1
''')
        program = 'set -euo pipefail\n' + body + r'''
work_root="$1"
outcome="$2"
declare -A IDENTITY=([INPUT_MODE]=staged [SCENARIO]=minimal-dualboot-ext4-systemdboot [RUN_ID]=fixture)
partition_name() { if [ "$2" = 1 ]; then echo "$work_root/esp"; else echo "$work_root/target-root"; fi; }
fail() { echo "$*" >&2; exit 1; }
check_dual_boot_neighbor() { [ "$outcome" != neighbor-check-failed ]; }
export COLLISION_FIXTURE_OUTCOME="$outcome"

mount() { cp -a "$work_root/esp-files/." "$3/"; }
umount() {
    rm -rf -- "$work_root/esp-files"
    mkdir "$work_root/esp-files"
    cp -a "$2/." "$work_root/esp-files/"
    find "$2" -mindepth 1 -depth -delete
}
prove_dual_boot_collision_refusal /fixture/target
'''
        result = subprocess.run(['bash', '-c', program, 'collision-fixture', tmp, outcome],
                                capture_output=True, text=True, timeout=10,
                                input="" if outcome == 'missing-password' else
                                      "public mock input\ndifferent public mock input\n" if outcome == 'wrong-password' else
                                      "public mock input\npublic mock input\n")
        assert (result.returncode == 0) == (outcome == 'refused'), result.stderr
        lines = result.stdout.splitlines()
        ready = 'MINIMAL_QEMU_COLLISION_PROBE_READY run_id=fixture scenario=minimal-dualboot-ext4-systemdboot'
        if outcome == 'esp-read-failed':
            assert ready not in lines and '+ Enter Password' not in lines, result.stdout
        else:
            assert lines.count(ready) == 1, result.stdout
            assert lines.index(ready) < lines.index('+ Enter Password'), result.stdout
            exit_marker = next(line for line in lines if line.startswith('MINIMAL_QEMU_COLLISION_PROBE_EXIT '))
            assert lines.index('+ Enter Password') < lines.index(exit_marker)
            assert exit_marker.endswith('status=113' if outcome == 'missing-password' else
                                        'status=114' if outcome == 'wrong-password' else
                                        'status=124' if outcome == 'timeout' else
                                        'status=0' if outcome == 'accepted' else 'status=1')
        if outcome == 'refused':
            proof = next(line for line in lines if line.startswith('MINIMAL_QEMU_ESP_COLLISION_REFUSAL_PASS '))
            assert lines.index('+ Enter Password again') < lines.index('FIXTURE_PASSWORD_PREREQUISITE_PASSED') < lines.index(proof)
            assert 'public mock input' not in result.stdout + result.stderr
            assert 'MINIMAL_QEMU_ESP_COLLISION_REFUSAL_PASS' in result.stdout
            assert not (esp / 'EFI/systemd').exists()
            assert not (esp / 'EFI/BOOT').exists()
            assert not (esp / 'vmlinuz-linux').exists()
            assert not (esp / 'loader/entries/main.conf').exists()
        else:
            assert 'MINIMAL_QEMU_ESP_COLLISION_REFUSAL_PASS' not in result.stdout
            assert (esp / 'loader/entries/main.conf').exists()
        for name in ('EFI/ali-neighbor/vmlinuz-linux', 'loader/entries/neighbor.conf', 'loader/entries.srel'):
            assert (esp / name).read_bytes() == b'fixture'
COLLISION_PY

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
(
    eval "$(sed -n '/^run_fresh_marble_user_round_trip() {/,/^}/p' "${host}")"
    calls=()
    # shellcheck disable=SC2329 # Invoked by the extracted orchestration helper.
    qga_verify() { calls+=("verify:$1"); }
    # shellcheck disable=SC2329 # Invoked by the extracted orchestration helper.
    marble_named_gdm_login() { calls+=("login:$1:$3"); }
    # shellcheck disable=SC2329 # Invoked by the extracted orchestration helper.
    hmp_request() { calls+=("key:$1:$2"); }
    # shellcheck disable=SC2329 # Avoid a real UI pause in this behavioral fixture.
    sleep() { :; }
    run_fresh_marble_user_round_trip
    expected=(verify:fresh-user-prepare login:fresh-user-login:marblefresh
        key:key:esc verify:fresh-user-logout login:return-user-login:vmtest)
    [ "${calls[*]}" = "${expected[*]}" ] ||
        fail 'fresh-user login, Welcome dismissal, logout and return are out of order'
)
grep -Fq -- 'fresh-user-login | fresh-user-logout | return-user-login' "${verify}" ||
    fail 'fresh-user logout is not registered as a separate guest phase'
grep -Fq -- 'GTK4_SESSION_DIAGNOSTIC' "${host}" ||
    fail 'bounded fresh-user logout diagnostics are absent from the compact summary'
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

# Exercise the production mount orchestration without host mounts.
python3 - "${verify}" <<'PY_NEIGHBOR'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
source = Path(sys.argv[1]).read_text()
body = re.search(r"^verify_dual_boot_preservation\(\) \{\n.*?^\}", source, re.M | re.S).group()
model = r'''
set -Eeuo pipefail
phase=neighbor-select
partition_name(){ printf '%s%s' "$1" "$2"; }
mktemp(){ mkdir "$FIXTURE/work"; printf '%s' "$FIXTURE/work"; }
mounted_source_device(){
    if [ "$CASE" = wrong-source ] || { [ "$CASE" = wrong-bind-source ] && [ "$1" != /boot ]; }; then printf /dev/foreign; else printf /dev/vda1; fi
}
findmnt(){
    field="$2"; target="${@: -1}"
    case "$field" in
    FSTYPE) if [ "$CASE" = wrong-fstype ] || { [ "$CASE" = wrong-bind-fstype ] && [ "$target" != /boot ]; }; then printf ext4; else printf vfat; fi;;
    FSROOT) if [ "$CASE" = subroot ] || { [ "$CASE" = bind-subroot ] && [ "$target" != /boot ]; }; then printf /subdir; else printf /; fi;;
    OPTIONS|VFS-OPTIONS) if [ "$target" = /boot ]; then printf rw; elif [ "$CASE" = readonly-check ]; then printf rw; else cat "$FIXTURE/bind-options"; fi;;
    *) return 1;;
    esac
}
mount(){
    printf 'mount %s\n' "$*" >>"$FIXTURE/calls"
    target="${@: -1}"
    [ "$target" != /boot ] || return 99
    case "$*" in
    *remount*bind*ro*) [ "$CASE" != remount-failure ] || return 32; printf ro >"$FIXTURE/bind-options";;
    *--bind*) [ "$CASE" != bind-failure ] || return 32; printf rw >"$FIXTURE/bind-options"; touch "$FIXTURE/bind";;
    *ro,noload*) mkdir "$target/boot"; touch "$FIXTURE/root";;
    *) printf 'existing ESP superblock RW; conflicting RO mount -> EBUSY\n' >&2; return 32;;
    esac
}
mountpoint(){
    case "${@: -1}" in */neighbor/boot) [ -f "$FIXTURE/bind" ];; */neighbor) [ -f "$FIXTURE/root" ];; *) return 1;; esac
}
umount(){
    target="${@: -1}"; printf 'umount %s\n' "$target" >>"$FIXTURE/calls"
    [ "$target" != /boot ] || return 99
    case "$target" in
    */neighbor/boot) [ "$CASE" != cleanup-failure ] || return 1; rm "$FIXTURE/bind";;
    */neighbor) [ ! -f "$FIXTURE/bind" ] || return 1; rmdir "$target/boot"; rm "$FIXTURE/root";;
    *) return 1;; esac
}
verify_neighbor_readback(){
    [ "$CASE" != readback-failure ] || return 1
    [ -f "$FIXTURE/bind" ] && [ "$(cat "$FIXTURE/bind-options")" = ro ]
    printf readback >"$FIXTURE/readback"
}
'''
for case in ("success", "wrong-source", "subroot", "wrong-fstype", "wrong-bind-source", "wrong-bind-fstype", "bind-subroot", "bind-failure", "remount-failure", "readonly-check", "readback-failure", "cleanup-failure"):
    with tempfile.TemporaryDirectory(prefix="qa-neighbor-") as tmp:
        root = Path(tmp)
        result = subprocess.run(["bash", "-c", model + body + "\nverify_dual_boot_preservation /dev/vda\n"], env=dict(os.environ, FIXTURE=tmp, CASE=case), capture_output=True, text=True, timeout=5)
        calls = (root / "calls").read_text() if (root / "calls").exists() else ""
        assert "umount /boot\n" not in calls, (case, calls)
        if case == "success":
            assert result.returncode == 0, (case, result.returncode, result.stderr)
            assert (root / "readback").exists(), case
            assert not (root / "work").exists(), (case, "owned mount directories leaked")
        else:
            assert result.returncode != 0, (case, "incorrectly passed")
            if case != "cleanup-failure":
                assert not (root / "work").exists(), (case, "failed operation leaked owned mounts")
print("neighbor preservation orchestration: 12 cases passed; host mounts NOT_RUN")
PY_NEIGHBOR

# Run the real scrubber/diagnostic producer/compactor on bounded serial fixtures.
python3 - "${host}" <<'PY_BOOT_DIAGNOSTICS'
import gzip
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
source = Path(sys.argv[1]).read_text()
functions = []
for name in ("remove_secret_bearing_evidence", "capture_snapshot_boot_failure", "compact_run_evidence"):
    match = re.search(r"^" + name + r"\(\) \{\n.*?^\}", source, re.M | re.S)
    assert match, "missing production function: " + name
    functions.append(match.group())
for case in ("boot-errors", "credential", "oversize", "symlink", "empty-serial", "no-serial"):
    with tempfile.TemporaryDirectory(prefix="qa-boot-diagnostic-") as tmp:
        root = Path(tmp); evidence = root / "evidence"; evidence.mkdir()
        serial = evidence / "snapshot-serial.log"
        secret = "fixture-runtime-credential"
        if case == "boot-errors":
            serial.write_text(("arbitrary private path /hidden/key token=unrelated\nKernel panic - not syncing: secret-looking arbitrary payload\nVFS: Unable to mount root fs on unknown-block(0,0)\n[FAILED] Failed to start systemd-volatile-root.service\n" * 100))
        elif case == "empty-serial": serial.write_text("")
        elif case == "credential": serial.write_text("Kernel panic - not syncing: " + secret + "\n")
        elif case == "oversize": serial.write_bytes(b"x" * (16777216 + 1))
        elif case == "symlink":
            outside = root / "outside"; outside.write_text("Kernel panic - not syncing: outside\n")
            serial.symlink_to(outside)
        (evidence / "snapshot-qemu.identity").write_text("pid=123\nstart=456\n")
        (evidence / "snapshot-qemu.stderr").write_text("raw stderr untrusted private payload\n")
        script = "set -Eeuo pipefail\nrun_root=$FIXTURE evidence=$FIXTURE/evidence runtime_password=fixture-runtime-credential\ndie(){ printf '%s\\n' \"$*\" >&2; return 1; }\n" + "\n".join(functions) + "\ncapture_snapshot_boot_failure\ncompact_run_evidence\n"
        result = subprocess.run(["bash", "-c", script], env=dict(os.environ, FIXTURE=tmp), capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, (case, result.stderr)
        diagnostic = (evidence / "snapshot-boot-diagnostic.txt").read_text()
        assert "reason=qga-not-ready" in diagnostic, case
        assert len(diagnostic.encode()) <= 4096 and len(diagnostic.splitlines()) <= 33, case
        assert secret not in diagnostic and "private" not in diagnostic and "/hidden" not in diagnostic, case
        assert ("code=kernel-panic" in diagnostic) == (case == "boot-errors"), case
        assert (evidence / "snapshot-qemu.identity").exists(), case
        assert (not serial.exists() or case == "symlink") and not (evidence / "snapshot-qemu.stderr").exists(), case
        summary = gzip.decompress((evidence / "scenario.log.gz").read_bytes()).decode()
        assert "reason=qga-not-ready" in summary and secret not in summary, case
        if case == "symlink": assert (root / "outside").read_text().endswith("outside\n")
route = re.search(r"^run_snapshot_acceptance\(\) \{\n.*?^\}", source, re.M | re.S).group()
script = """set -Eeuo pipefail
qga_verify(){ :; }
schedule_transition(){ :; }
wait_qemu_exit(){ :; }
launch_qemu(){ :; }
wait_qga(){ return 1; }
capture_screen(){ printf 'OPTIONAL_SCREEN %s\n' "$1"; return 77; }
capture_snapshot_boot_failure(){ printf 'BOUNDED_DIAGNOSTIC\n'; }
die(){ printf 'FAIL %s\n' "$*"; exit 1; }
""" + route + "\nrun_snapshot_acceptance\n"
result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=5)
assert result.returncode == 1, result
assert result.stdout.splitlines() == ["OPTIONAL_SCREEN snapshot-qga-timeout", "BOUNDED_DIAGNOSTIC", "FAIL snapshot boot guest agent did not become ready"], result.stdout
print("snapshot boot diagnostics: 6 production compaction cases passed")
PY_BOOT_DIAGNOSTICS

# Preserve controlled extension diagnostics, never their raw or credential-bearing input.
python3 - "${host}" <<'PY_EXTENSION_COMPACTION'
import gzip
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
source = Path(sys.argv[1]).read_text()
functions = [re.search(r"^" + name + r"\(\) \{\n.*?^\}", source, re.M | re.S).group()
             for name in ("remove_secret_bearing_evidence", "compact_run_evidence")]
marker = "GNOME_EXTENSION_DIAGNOSTIC run_id=marble-fixture phase=return-user-login reason=enabled-set-mismatch expected_count=8 actual_count=7 missing_known_count=1 unexpected_count=0 duplicate_count=0 disabled_user_extensions=false"
known = "GNOME_EXTENSION_DIAGNOSTIC run_id=marble-fixture phase=return-user-login known_extension=dash-to-dock@micxgx.gmail.com expected=yes enabled=no state=error"
with tempfile.TemporaryDirectory(prefix="qa-extension-compaction-") as tmp:
    root = Path(tmp); evidence = root / "evidence"; evidence.mkdir()
    (evidence / "return-user-login.stdout").write_text(marker + "\n" + known + "\narbitrary untrusted raw output\n")
    (evidence / "credential.stderr").write_text(marker + " secret=fixture-runtime-credential\n")
    (evidence / "return-user-login.stderr").write_text("raw user private path /hidden/key\n")
    script = "set -Eeuo pipefail\nrun_root=$FIXTURE evidence=$FIXTURE/evidence runtime_password=fixture-runtime-credential\n" + "\n".join(functions) + "\ncompact_run_evidence\n"
    result = subprocess.run(["bash", "-c", script], env=dict(os.environ, FIXTURE=tmp), capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    summary = gzip.decompress((evidence / "scenario.log.gz").read_bytes()).decode()
    assert summary.splitlines() == [marker, known], summary
    assert sorted(item.name for item in evidence.iterdir()) == ["scenario.log.gz"]
print("extension diagnostic compaction: controlled marker preserved, credential/raw logs removed")
PY_EXTENSION_COMPACTION

printf 'VM_HARNESS_CHECKS_RESULT schema=1 version_provenance=passed metadata_absent=passed; QEMU=NOT_RUN\n'
