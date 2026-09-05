#!/usr/bin/env bash
set -euo pipefail
umask 077
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
require_full_namespace=false
case "$#:${1:-}" in
    0:) ;;
    1:--require-full-namespace) require_full_namespace=true ;;
    *) printf 'Usage: %s [--require-full-namespace]\n' "$0" >&2; exit 2 ;;
esac
[ "$EUID" -ne 0 ] || { printf 'repository check failed: run as an unprivileged user\n' >&2; exit 1; }
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/arch-linux-repository-tests.XXXXXXXX")"
key_home=''
wrong_home=''
shape_home=''
cleanup() {
    local home
    for home in "${key_home:-}" "${wrong_home:-}" "${shape_home:-}"; do
        if [ -n "$home" ] && [ -d "$home" ]; then
            gpgconf --homedir "$home" --kill all >/dev/null 2>&1 || true
        fi
    done
    rm -rf -- "$work"
}
trap cleanup EXIT HUP INT TERM

for command_name in cc file git gpg gpgconf python3 readelf sha256sum tar unshare zstd; do
    command -v -- "$command_name" >/dev/null 2>&1 || {
        printf 'repository check failed: required command absent: %s\n' "$command_name" >&2
        exit 1
    }
done

entry_guard_root="$work/entry-guard-probes"
mkdir -m0700 -- "$entry_guard_root"
PYTHONDONTWRITEBYTECODE=1 python3 -I -B - "$repo_root" "$entry_guard_root" <<'PY'
import fcntl
import os
from pathlib import Path
import shlex
import subprocess
import sys

source_root = Path(sys.argv[1])
probe_root = Path(sys.argv[2])
inputs = probe_root / "inputs"
inputs.mkdir(mode=0o700)
for name in ("unsigned", "phase-a", "minimal", "stock", "marble"):
    (inputs / name).mkdir(mode=0o700)


def probe(source_name: str, output_name: str, anchor: str, marker_name: str) -> tuple[Path, Path]:
    source = source_root / source_name
    output = probe_root / output_name
    marker = probe_root / marker_name
    raw = source.read_text(encoding="utf-8")
    if raw.count(anchor) != 1:
        raise SystemExit(f"entry-guard probe anchor differs: {source_name}")
    reached = (
        f"/usr/bin/printf '%s\\n' reached >{shlex.quote(str(marker))}\n"
        "exit 0\n"
    )
    output.write_text(raw.replace(anchor, reached + anchor), encoding="utf-8")
    output.chmod(0o700)
    return output, marker


def expect_rejected(
    label: str,
    command: list[str],
    environment: dict[str, str],
    descriptors: tuple[int, ...],
    marker: Path,
    diagnostic: bytes,
) -> None:
    completed = subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        pass_fds=descriptors,
        check=False,
    )
    if (
        completed.returncode != 1
        or completed.stdout
        or completed.stderr != diagnostic
        or marker.exists()
    ):
        raise SystemExit(f"entry-guard negative did not fail at its isolated boundary: {label}")


run_probe, run_marker = probe(
    "repository/run-offline-signing.sh",
    "run-offline-signing.sh",
    "authenticate_launcher_parent_liveness() {\n",
    "run-offline-signing.reached",
)
snapshot_shell_probe, snapshot_shell_marker = probe(
    "repository/offline-sign-release.sh",
    "offline-sign-release-shell.sh",
    "exec 6<&- 9<&-\n",
    "offline-sign-release-shell.reached",
)
snapshot_namespace_probe, snapshot_namespace_marker = probe(
    "repository/offline-sign-release.sh",
    "offline-sign-release-namespace.sh",
    "exec 6<&- 9<&-\n",
    "offline-sign-release-namespace.reached",
)
final_shell_probe, final_shell_marker = probe(
    "repository/offline-finalize-release.sh",
    "offline-finalize-release-shell.sh",
    "exec 6<&- 9<&-\n",
    "offline-finalize-release-shell.reached",
)
final_namespace_probe, final_namespace_marker = probe(
    "repository/offline-finalize-release.sh",
    "offline-finalize-release-namespace.sh",
    "exec 6<&- 9<&-\n",
    "offline-finalize-release-namespace.reached",
)

digest = "0" * 64
snapshot_arguments = [
    "--unsigned", str(inputs / "unsigned"),
    "--installer", str(source_root / "arch-linux-installer.sh"),
    "--output", str(inputs / "snapshot-output"),
    "--release-version", "1.0.0",
    "--build-metadata-sha256", digest,
    "--unsigned-manifest-sha256", digest,
]
final_arguments = [
    "--phase-a", str(inputs / "phase-a"),
    "--output", str(inputs / "final-output"),
    "--release-version", "1.0.0",
    "--build-metadata-sha256", digest,
    "--unsigned-manifest-sha256", digest,
    "--snapshot-sha256", digest,
    "--minimal-run", str(inputs / "minimal"),
    "--stock-run", str(inputs / "stock"),
    "--marble-run", str(inputs / "marble"),
]

sealed_input_fd = os.memfd_create("arch-linux-entry-guard-passphrase", os.MFD_ALLOW_SEALING)
os.fchmod(sealed_input_fd, 0o600)
os.write(sealed_input_fd, b"fixture-passphrase\n")
seals = fcntl.F_SEAL_WRITE | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_SEAL
fcntl.fcntl(sealed_input_fd, fcntl.F_ADD_SEALS, seals)
if sealed_input_fd != 7:
    os.dup2(sealed_input_fd, 7, inheritable=True)
    os.close(sealed_input_fd)
sealed_input_fd = 7
passphrase_metadata = os.fstat(sealed_input_fd)

broker_read, broker_write = os.pipe()
os.write(broker_write, b"arch-linux-offline-inspection-v1\narch-linux-offline-broker-v1\n")
os.close(broker_write)
if broker_read != 8:
    os.dup2(broker_read, 8, inheritable=True)
    os.close(broker_read)
broker_read = 8

base_environment = {
    "HOME": "/nonexistent",
    "LANG": "C",
    "LC_ALL": "C",
    "PATH": "/usr/bin:/bin",
    "TMPDIR": "/tmp",
}
parent_fields = Path("/proc/self/stat").read_text(encoding="ascii").rsplit(")", 1)[1].split()
run_environment = base_environment | {
    "ARCH_LINUX_OFFLINE_BROKER_PARENT": str(os.getpid()),
    "ARCH_LINUX_OFFLINE_BROKER_PARENT_START": parent_fields[19],
    "ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT": "0" * 40,
    "ARCH_LINUX_OFFLINE_ACCEPTED_TREE": "1" * 40,
    "ARCH_LINUX_OFFLINE_ACCEPTED_TREE_SHA256": digest,
    "ARCH_LINUX_OFFLINE_CODE_ROOT": str(probe_root),
    "ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY": "1:1",
    "ARCH_LINUX_OFFLINE_LAUNCHER": str(probe_root / "offline-signing-launcher"),
    "ARCH_LINUX_OFFLINE_LAUNCHER_IDENTITY": "1:1:1:1:500:1:1",
    "ARCH_LINUX_SIGNING_HOME_IDENTITY": "1:1",
    "ARCH_LINUX_SIGNING_HOST_UID": str(os.getuid()),
    "ARCH_LINUX_SIGNING_HOST_GID": str(os.getgid()),
    "ARCH_LINUX_PASSPHRASE_IDENTITY": (
        f"{passphrase_metadata.st_dev}:{passphrase_metadata.st_ino}:{passphrase_metadata.st_size}"
    ),
}
expect_rejected(
    "run-offline-signing privileged-shell entry",
    ["/usr/bin/bash", str(run_probe), "--sealed-broker", "snapshot", *snapshot_arguments],
    run_environment,
    (sealed_input_fd, broker_read),
    run_marker,
    b"ERROR: offline signing requires the sealed compiled launcher\n",
)

namespace_environment = base_environment | {
    "ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT": "sealed-root-v1",
    "GNUPGHOME": "/run/user/0/arch-linux-offline/gnupg",
    "OFFLINE_SIGN_PASSPHRASE_FILE": "/proc/self/fd/7",
    "ARCH_LINUX_PASSPHRASE_IDENTITY": run_environment["ARCH_LINUX_PASSPHRASE_IDENTITY"],
}
expect_rejected(
    "snapshot inner privileged-shell entry",
    ["/usr/bin/bash", str(snapshot_shell_probe), *snapshot_arguments],
    namespace_environment,
    (sealed_input_fd,),
    snapshot_shell_marker,
    b"ERROR: snapshot signing requires the sealed compiled launcher\n",
)
expect_rejected(
    "finalize inner privileged-shell entry",
    ["/usr/bin/bash", str(final_shell_probe), *final_arguments],
    namespace_environment,
    (sealed_input_fd,),
    final_shell_marker,
    b"ERROR: release finalization requires the sealed compiled launcher\n",
)

invalid_namespace_environment = namespace_environment | {
    "ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT": "invalid",
}
expect_rejected(
    "snapshot inner namespace entry",
    ["/usr/bin/bash", "-p", str(snapshot_namespace_probe), *snapshot_arguments],
    invalid_namespace_environment,
    (sealed_input_fd,),
    snapshot_namespace_marker,
    b"ERROR: snapshot signing requires the sealed namespace boundary\n",
)
expect_rejected(
    "finalize inner namespace entry",
    ["/usr/bin/bash", "-p", str(final_namespace_probe), *final_arguments],
    invalid_namespace_environment,
    (sealed_input_fd,),
    final_namespace_marker,
    b"ERROR: release finalization requires the sealed namespace boundary\n",
)

os.close(broker_read)
os.close(sealed_input_fd)
PY
if python3 -I "$repo_root/repository/offline-signing-fd-guard.py" unknown >/dev/null 2>&1; then
    printf 'repository check failed: unknown descriptor-guard mode was accepted\n' >&2
    exit 1
fi

PYTHONDONTWRITEBYTECODE=1 python3 -I -B - \
    "$repo_root/repository/offline-signing-fd-guard.py" <<'PY'
import fcntl
import os
import subprocess
import sys

guard = sys.argv[1]
diagnostic = b"ERROR: offline signing descriptor hygiene failed\n"
fixed_home = "/run/user/0/arch-linux-offline/gnupg"
valid_arguments = [
    "/usr/bin/gpg", "--batch", "--no-options", "--no-autostart", "--with-colons",
    "--with-subkey-fingerprint", "--list-secret-keys", "--", "A" * 40 + "!",
]


def rejected(*, sealed, home, arguments):
    descriptor = os.memfd_create("arch-linux-test-passphrase", os.MFD_ALLOW_SEALING)
    try:
        os.fchmod(descriptor, 0o600)
        os.write(descriptor, b"fixture-passphrase\n")
        if sealed:
            seals = fcntl.F_SEAL_WRITE | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_SEAL
            fcntl.fcntl(descriptor, fcntl.F_ADD_SEALS, seals)
        if descriptor != 7:
            os.dup2(descriptor, 7, inheritable=True)
            os.close(descriptor)
            descriptor = 7
        metadata = os.fstat(descriptor)
        environment = {
            "ARCH_LINUX_PASSPHRASE_IDENTITY":
                f"{metadata.st_dev}:{metadata.st_ino}:{metadata.st_size}",
            "GNUPGHOME": home,
        }
        completed = subprocess.run(
            ["/usr/bin/python3", "-I", guard, "exec-private-gpg", *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            pass_fds=(descriptor,),
            check=False,
        )
        if completed.returncode != 1 or completed.stdout or completed.stderr != diagnostic:
            raise SystemExit("private GPG descriptor/environment negative did not fail in the guard")
    finally:
        os.close(descriptor)


rejected(sealed=True, home="/tmp/not-the-private-runtime", arguments=valid_arguments)
rejected(sealed=True, home=fixed_home, arguments=[*valid_arguments[:-1], "a" * 40 + "!"])
rejected(sealed=False, home=fixed_home, arguments=valid_arguments)
PY

atomic_root="$work/atomic-publish"
mkdir -m0700 -- "$atomic_root" "$atomic_root/output-parent"
mkdir -m0700 -- "$atomic_root/stage"
printf '%s\n' accepted >"$atomic_root/stage/payload"
env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin TMPDIR=/tmp \
    python3 -I "$repo_root/repository/offline-signing-fd-guard.py" atomic-publish \
    "$atomic_root/stage" "$atomic_root/output-parent/published" </dev/null
[ ! -e "$atomic_root/stage" ] && [ ! -L "$atomic_root/stage" ] &&
    [ "$(cat -- "$atomic_root/output-parent/published/payload")" = accepted ] || {
    printf 'repository check failed: atomic no-replace publication readback differs\n' >&2
    exit 1
}
mkdir -m0700 -- "$atomic_root/stage-collision" "$atomic_root/output-parent/collision"
printf '%s\n' staged >"$atomic_root/stage-collision/payload"
printf '%s\n' retained >"$atomic_root/output-parent/collision/payload"
if env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin TMPDIR=/tmp \
    python3 -I "$repo_root/repository/offline-signing-fd-guard.py" atomic-publish \
    "$atomic_root/stage-collision" "$atomic_root/output-parent/collision" </dev/null >/dev/null 2>&1; then
    printf 'repository check failed: atomic publication replaced an existing output\n' >&2
    exit 1
fi
[ "$(cat -- "$atomic_root/stage-collision/payload")" = staged ] &&
    [ "$(cat -- "$atomic_root/output-parent/collision/payload")" = retained ] || {
    printf 'repository check failed: rejected atomic publication changed an object\n' >&2
    exit 1
}
mkdir -m0755 -- "$atomic_root/unsafe-parent"
mkdir -m0700 -- "$atomic_root/stage-unsafe"
if env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin TMPDIR=/tmp \
    python3 -I "$repo_root/repository/offline-signing-fd-guard.py" atomic-publish \
    "$atomic_root/stage-unsafe" "$atomic_root/unsafe-parent/published" </dev/null >/dev/null 2>&1; then
    printf 'repository check failed: atomic publication accepted an unsafe output parent\n' >&2
    exit 1
fi

launcher_fixture="$work/offline-signing-launcher"
cc -std=c17 -O2 -static-pie -fstack-protector-strong -D_FORTIFY_SOURCE=3 -Wall -Wextra -Werror \
    '-DALI_ACCEPTED_COMMIT_SHA="0000000000000000000000000000000000000000"' \
    '-DALI_ACCEPTED_TREE_SHA="1111111111111111111111111111111111111111"' \
    '-DALI_ACCEPTED_TREE_SHA256="2222222222222222222222222222222222222222222222222222222222222222"' \
    -DALI_SIGNING_UID=65534 -DALI_SIGNING_GID=65534 \
    -o "$launcher_fixture" "$repo_root/repository/offline-signing-launcher.c"
file "$launcher_fixture" | grep -Fq 'static-pie linked' || {
    printf 'repository check failed: launcher is not static PIE\n' >&2
    exit 1
}
if readelf -l "$launcher_fixture" | grep -Fq INTERP; then
    printf 'repository check failed: launcher has PT_INTERP\n' >&2
    exit 1
fi

namespace_marker=full
parent_user="$(stat -Lc '%i' -- /proc/self/ns/user)"
parent_net="$(stat -Lc '%i' -- /proc/self/ns/net)"
parent_pid="$(stat -Lc '%i' -- /proc/self/ns/pid)"
parent_mnt="$(stat -Lc '%i' -- /proc/self/ns/mnt)"
# shellcheck disable=SC2016
if ! env PARENT_USER="$parent_user" PARENT_NET="$parent_net" PARENT_PID="$parent_pid" PARENT_MNT="$parent_mnt" \
    unshare --user --map-root-user --net --pid --mount --mount-proc --fork --kill-child=SIGKILL \
    bash -c '
        set -euo pipefail
        [ "$BASHPID" = 1 ]
        [ "$(stat -Lc %i -- /proc/self/ns/user)" != "$PARENT_USER" ]
        [ "$(stat -Lc %i -- /proc/self/ns/net)" != "$PARENT_NET" ]
        [ "$(stat -Lc %i -- /proc/self/ns/pid)" != "$PARENT_PID" ]
        [ "$(stat -Lc %i -- /proc/self/ns/mnt)" != "$PARENT_MNT" ]
        [ "$(awk '\''{$1=$1; print}'\'' /proc/self/uid_map)" = "0 '"$(id -u)"' 1" ]
        [ "$(awk '\''{$1=$1; print}'\'' /proc/self/gid_map)" = "0 '"$(id -g)"' 1" ]
        [ "$(awk -F: '\''NR>2 {gsub(/[[:space:]]/,"",$1); if($1!="") print $1}'\'' /proc/self/net/dev)" = lo ]
    ' >/dev/null 2>&1; then
    hosted=false
    [ "${ARCH_LINUX_ALLOW_HOSTED_NAMESPACE_DEFERRAL:-}" = github-hosted-container-v1 ] &&
        [ "${CI:-}" = true ] && [ "${GITHUB_ACTIONS:-}" = true ] &&
        [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] && [ -f /.dockerenv ] && [ ! -L /.dockerenv ] && hosted=true
    if [ "$require_full_namespace" = true ] || [ "$hosted" != true ]; then
        printf 'repository check failed: full namespace fixture unavailable\n' >&2
        exit 1
    fi
    namespace_marker=deferred
fi

make_key() {
    local home="$1" identity="$2" primary signing metadata
    mkdir -m0700 -- "$home"
    GNUPGHOME="$home" gpg --batch --no-options --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "$identity" ed25519 cert 1d >/dev/null 2>&1
    metadata="$(GNUPGHOME="$home" gpg --batch --no-options --with-colons --list-keys)"
    primary="$(awk -F: '$1=="fpr"{print toupper($10); exit}' <<<"$metadata")"
    GNUPGHOME="$home" gpg --batch --no-options --pinentry-mode loopback --passphrase '' \
        --quick-add-key "$primary" ed25519 sign 1d >/dev/null 2>&1
    metadata="$(GNUPGHOME="$home" gpg --batch --no-options --with-colons --with-subkey-fingerprint --list-keys)"
    primary="$(awk -F: '$1=="fpr"{print toupper($10); exit}' <<<"$metadata")"
    signing="$(awk -F: '$1=="sub"{want=1; next} want && $1=="fpr"{print toupper($10); exit}' <<<"$metadata")"
    printf '%s\n%s\n' "$primary" "$signing"
}

sign_file() {
    local home="$1" key="$2" payload="$3" signature="$4"
    GNUPGHOME="$home" gpg --batch --no-options --pinentry-mode loopback --passphrase '' \
        --local-user "${key}!" --detach-sign --output "$signature" -- "$payload"
    chmod 0644 -- "$signature"
}

fixture_project="$work/project"
fixture_packages="$work/valid-package-fixtures"
mkdir -p -- "$fixture_project/repository/lib" "$fixture_project/repository/trust" \
    "$fixture_project/packages" "$fixture_project/tests/vm/guest" \
    "$fixture_project/maintenance" "$fixture_packages"
PACKAGE_FIXTURE_OUTPUT_DIR="$fixture_packages" bash "$repo_root/tests/package-checks.sh" >/dev/null
cp -- "$repo_root/repository/lib/common.sh" "$fixture_project/repository/lib/common.sh"
printf '%s\n' arch-linux-keyring arch-linux-marble-profile >"$fixture_project/repository/package-set"
cp -- "$repo_root/repository/source-date-epoch" "$fixture_project/repository/source-date-epoch"
cp -- "$repo_root/repository/safe-extract-snapshot.py" "$fixture_project/repository/safe-extract-snapshot.py"
cp -- "$repo_root/repository/acceptance-manifest.py" "$fixture_project/repository/acceptance-manifest.py"
cp -- "$repo_root/repository/snapshot-manifest.py" "$fixture_project/repository/snapshot-manifest.py"
cp -- "$repo_root/repository/verify-release-assets.sh" "$fixture_project/repository/verify-release-assets.sh"
cp -- "$repo_root/repository/verify-signed-repository.sh" "$fixture_project/repository/verify-signed-repository.sh"
cp -- "$repo_root/repository/verify-unsigned-build.sh" "$fixture_project/repository/verify-unsigned-build.sh"
cp -- "$repo_root/maintenance/accepted-arch-iso.json" \
    "$fixture_project/maintenance/accepted-arch-iso.json"
for harness_file in \
    tests/vm/run.sh tests/vm/frame-evidence.py tests/vm/qga-client.py tests/vm/https-server.py \
    tests/vm/prepare-marble-repository.sh tests/vm/guest/bootstrap.sh tests/vm/guest/verify.sh; do
    cp -- "$repo_root/$harness_file" "$fixture_project/$harness_file"
done
for package in arch-linux-keyring arch-linux-marble-profile; do
    cp -a -- "$repo_root/packages/$package" "$fixture_project/packages/$package"
done
python3 - "$fixture_project/repository/verify-package-metadata.py" \
    "$repo_root/repository/verify-package-metadata.py" <<'PY'
import pathlib, sys
destination=pathlib.Path(sys.argv[1])
verifier=sys.argv[2]
destination.write_text(
    '#!/usr/bin/env python3\nimport os,sys\n'
    f'os.execv(sys.executable,[sys.executable,{verifier!r},*sys.argv[1:]])\n',
    encoding='utf-8',
)
PY
chmod 0755 -- "$fixture_project/repository/lib/common.sh" \
    "$fixture_project/repository/safe-extract-snapshot.py" \
    "$fixture_project/repository/acceptance-manifest.py" \
    "$fixture_project/repository/snapshot-manifest.py" \
    "$fixture_project/repository/verify-release-assets.sh" \
    "$fixture_project/repository/verify-signed-repository.sh" \
    "$fixture_project/repository/verify-unsigned-build.sh" \
    "$fixture_project/repository/verify-package-metadata.py"
chmod 0644 -- "$fixture_project/repository/package-set" "$fixture_project/repository/source-date-epoch"
PYTHONDONTWRITEBYTECODE=1 python3 -I -B - \
    "$fixture_project/repository/acceptance-manifest.py" <<'PY'
import importlib.util
import io
import json
import sys

spec = importlib.util.spec_from_file_location("acceptance_negative_fixture", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def require_rejected(callback, label):
    try:
        callback()
    except module.ManifestError:
        return
    raise SystemExit(f"acceptance negative did not fail closed: {label}")


marker = module.SECRET_MARKERS[0]
split_payload = b"x" * (1024 * 1024 - len(marker) // 2) + marker + b"x"
require_rejected(
    lambda: module.inspect_binary_secret_markers("selected-frame.ppm", io.BytesIO(split_payload)),
    "private-key marker split across PPM chunks",
)

if module.challenge_measurements_are_valid([257, 64, 0], 256, {(16, 16)}, (16, 16)):
    raise SystemExit("acceptance negative accepted an impossible framebuffer pixel delta")
if module.challenge_measurements_are_valid(
        [64, 64, 0], 8192 * 8192, {(8192, 8192)}, (8192, 8192)):
    raise SystemExit("acceptance negative ignored the geometry-dependent framebuffer delta")

qemu_identity = {
    "pid": "101", "start_time": "1001", "qmp_identity": "30:40",
}
aliasing_header = {
    "e": "header", "schema": 1, "phase": "firstboot", "segment": "boot",
    "pid": 101, "start": "1001", "qmp": "30:40", "peerPid": 101, "peerUid": 1000,
    "recorderPid": 101, "recorderStart": "1001", "device": "display0", "head": 0,
    "intervalMs": 250, "maxGapMs": 500, "maxRawBytes": 45 * 1024 * 1024,
    "maxSamples": 2000, "t": 1, "initial": "prelaunch",
}
require_rejected(
    lambda: module.validate_retained_ledger(
        (json.dumps(aliasing_header, sort_keys=True, separators=(",", ":")) + "\n").encode(),
        "firstboot", "boot", qemu_identity, False,
    ),
    "recorder identity aliases QEMU identity",
)

bad_socket_identity = (
    b"phase=firstboot\npid=101\nstart_time=1001\nqga_identity=10:20\n"
    b"qmp_identity=30:40\nqmp_capture_identity=50:60\n"
)
require_rejected(
    lambda: module.parse_identity(bad_socket_identity, "firstboot"),
    "QEMU sockets do not have one distinct three-endpoint topology",
)

chronology_identities = {
    "firstboot": {"start_time": "100", "qga_identity": "30:40"},
    "postreboot": {"start_time": "200", "qga_identity": "30:50"},
}
chronology_recorders = {
    "firstboot-boot": {"start_time": "110"},
    "firstboot-shutdown": {"start_time": "120"},
    "postreboot-boot": {"start_time": "210"},
    "postreboot-shutdown": {"start_time": "220"},
}
chronology = {
    "firstboot-boot": {"peerUid": 1000, "firstMonotonicNs": 100, "lastMonotonicNs": 200},
    "firstboot-shutdown": {"peerUid": 1000, "firstMonotonicNs": 300, "lastMonotonicNs": 400},
    "postreboot-boot": {"peerUid": 1000, "firstMonotonicNs": 350, "lastMonotonicNs": 500},
    "postreboot-shutdown": {"peerUid": 1000, "firstMonotonicNs": 600, "lastMonotonicNs": 700},
}
require_rejected(
    lambda: module.validate_run_process_chronology(
        chronology_identities, chronology_recorders, chronology),
    "overlapping firstboot/postreboot ledger chronology",
)
chronology["postreboot-boot"] = {
    "peerUid": 1001, "firstMonotonicNs": 500, "lastMonotonicNs": 550,
}
require_rejected(
    lambda: module.validate_run_process_chronology(
        chronology_identities, chronology_recorders, chronology),
    "inconsistent QMP peer UID across one run",
)
chronology["postreboot-boot"]["peerUid"] = 1000
chronology_recorders["firstboot-shutdown"]["start_time"] = "200"
require_rejected(
    lambda: module.validate_run_process_chronology(
        chronology_identities, chronology_recorders, chronology),
    "firstboot recorder does not precede the postreboot QEMU process",
)
chronology_recorders["firstboot-shutdown"]["start_time"] = "120"
chronology_identities["postreboot"]["qga_identity"] = "31:50"
require_rejected(
    lambda: module.validate_run_process_chronology(
        chronology_identities, chronology_recorders, chronology),
    "firstboot/postreboot QEMU sockets do not share one runtime device",
)

records = []
for scenario_index in range(3):
    qemu = {
        phase: {"pid": str(200 + scenario_index * 10 + phase_index),
                "start_time": str(2000 + scenario_index * 10 + phase_index)}
        for phase_index, phase in enumerate(module.PHASES)
    }
    recorders = {
        f"{phase}-{segment}": {
            "pid": str(400 + scenario_index * 10 + segment_index),
            "start_time": str(4000 + scenario_index * 10 + segment_index),
        }
        for segment_index, (phase, segment) in enumerate(module.SEGMENTS)
    }
    records.append({
        "runId": f"run-{scenario_index}", "targetSerial": f"serial-{scenario_index}",
        "payloadIsoSha256": "a" * 64 if scenario_index < 2 else "b" * 64,
        "isoSha256": "c" * 64, "harnessSha256": "d" * 64,
        "qemuIdentities": qemu, "recorderIdentities": recorders,
    })
require_rejected(
    lambda: module.validate_cross_scenario_records(records),
    "duplicate helper/config payload ISO across scenarios",
)
PY
cat >"$fixture_project/arch-linux-installer.sh" <<'INSTALLER'
#!/usr/bin/env bash
if [ "$#" -eq 1 ] && [ "$1" = --version ]; then
    printf '%s\n' 1.0.0
    exit 0
fi
exit 2
INSTALLER
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fixture_project/install.sh"
chmod 0644 -- "$fixture_project/arch-linux-installer.sh" "$fixture_project/install.sh"

key_home="$work/key-home"
mapfile -t fingerprints < <(make_key "$key_home" 'Arch Linux Repository Test <repository-test@invalid>')
primary="${fingerprints[0]}"
signing="${fingerprints[1]}"
GNUPGHOME="$key_home" gpg --batch --no-options --export "$primary" >"$fixture_project/repository/trust/arch-linux.gpg"
printf '%s\n' "$primary" >"$fixture_project/repository/trust/primary-fingerprint"
printf '%s\n' "$signing" >"$fixture_project/repository/trust/signing-subkey-fingerprint"
chmod 0644 -- "$fixture_project/repository/trust/"*

git -C "$fixture_project" init --quiet --initial-branch=main
git -C "$fixture_project" add -- .
git -C "$fixture_project" -c user.name='Repository Test' -c user.email='repository-test@invalid' \
    commit --quiet -m 'test: fixture source'
source_commit="$(git -C "$fixture_project" rev-parse 'HEAD^{commit}')"
source_tree="$(git -C "$fixture_project" rev-parse 'HEAD^{tree}')"
installer_hash="$(sha256sum --binary -- "$fixture_project/arch-linux-installer.sh" | awk '{print $1}')"
package_set_hash="$(sha256sum --binary -- "$fixture_project/repository/package-set" | awk '{print $1}')"
source_epoch="$(cat -- "$fixture_project/repository/source-date-epoch")"

# The accepted public-certificate shape is part of the repository trust boundary.
# Verify the positive fixture, secret-packet rejection, and wrong-subkey rejection.
# shellcheck source=repository/lib/common.sh
source "$fixture_project/repository/lib/common.sh"
repository_assert_public_certificate \
    "$fixture_project/repository/trust/arch-linux.gpg" \
    "$fixture_project/repository/trust/primary-fingerprint" \
    "$fixture_project/repository/trust/signing-subkey-fingerprint"
base_certificate_metadata="$(GNUPGHOME="$key_home" gpg --batch --no-options --with-colons \
    --with-subkey-fingerprint --list-keys -- "$primary" 2>/dev/null)"
assert_synthetic_certificate_metadata_rejected() (
    local certificate_metadata="$1" label="$2"
    gpg() {
        case " $* " in
            *' --show-keys '*) printf '%s\n' "$certificate_metadata" ;;
            *' --list-packets '*) printf '%s\n' ':public key packet:' ;;
            *) return 97 ;;
        esac
    }
    if repository_assert_public_certificate \
        "$fixture_project/repository/trust/arch-linux.gpg" \
        "$fixture_project/repository/trust/primary-fingerprint" \
        "$fixture_project/repository/trust/signing-subkey-fingerprint" >/dev/null 2>&1; then
        printf 'repository check failed: malformed certificate metadata accepted: %s\n' "$label" >&2
        exit 1
    fi
)
certificate_with_uat="${base_certificate_metadata}"$'\n''uat:-::::fixture-photo:::::::::0:'
certificate_with_revoked_uid="$(awk -F: 'BEGIN{OFS=":"} \
    $1=="uid" && !changed {$2="r"; changed=1} {print} END {if(changed!=1) exit 1}' \
    <<<"$base_certificate_metadata")"
assert_synthetic_certificate_metadata_rejected "$certificate_with_uat" 'additional UAT'
assert_synthetic_certificate_metadata_rejected "$certificate_with_revoked_uid" 'revoked UID'
secret_certificate="$work/secret-certificate.gpg"
GNUPGHOME="$key_home" gpg --batch --no-options --pinentry-mode loopback --passphrase '' \
    --export-secret-keys "$primary" >"$secret_certificate"
chmod 0600 -- "$secret_certificate"
if repository_assert_public_certificate \
    "$secret_certificate" \
    "$fixture_project/repository/trust/primary-fingerprint" \
    "$fixture_project/repository/trust/signing-subkey-fingerprint" >/dev/null 2>&1; then
    printf 'repository check failed: secret certificate accepted as public trust\n' >&2
    exit 1
fi

shape_home="$work/shape-key"
mkdir -m0700 -- "$shape_home"
GNUPGHOME="$shape_home" gpg --batch --no-options --pinentry-mode loopback --passphrase '' \
    --quick-generate-key 'Wrong Shape Test <wrong-shape@invalid>' ed25519 cert 1d >/dev/null 2>&1
shape_metadata="$(GNUPGHOME="$shape_home" gpg --batch --no-options --with-colons --list-keys)"
shape_primary="$(awk -F: '$1=="fpr"{print toupper($10); exit}' <<<"$shape_metadata")"
GNUPGHOME="$shape_home" gpg --batch --no-options --pinentry-mode loopback --passphrase '' \
    --quick-add-key "$shape_primary" cv25519 encr 1d >/dev/null 2>&1
shape_metadata="$(GNUPGHOME="$shape_home" gpg --batch --no-options --with-colons \
    --with-subkey-fingerprint --list-keys)"
shape_signing="$(awk -F: '$1=="sub"{want=1; next} want && $1=="fpr"{print toupper($10); exit}' \
    <<<"$shape_metadata")"
shape_certificate="$work/wrong-shape.gpg"
shape_primary_file="$work/wrong-shape-primary"
shape_signing_file="$work/wrong-shape-signing"
GNUPGHOME="$shape_home" gpg --batch --no-options --export "$shape_primary" >"$shape_certificate"
printf '%s\n' "$shape_primary" >"$shape_primary_file"
printf '%s\n' "$shape_signing" >"$shape_signing_file"
chmod 0644 -- "$shape_certificate" "$shape_primary_file" "$shape_signing_file"
if repository_assert_public_certificate \
    "$shape_certificate" "$shape_primary_file" "$shape_signing_file" >/dev/null 2>&1; then
    printf 'repository check failed: encryption subkey accepted as repository signing trust\n' >&2
    exit 1
fi

snapshot="$work/snapshot"
mkdir -m0755 -- "$snapshot"
mapfile -t packages <"$fixture_project/repository/package-set"
package_names=()
for package in "${packages[@]}"; do
    file=("$fixture_packages/${package}-"*.pkg.tar.zst)
    [ "${#file[@]}" -eq 1 ] || {
        printf 'repository check failed: valid fixture package closure differs: %s\n' "$package" >&2
        exit 1
    }
    name="${file[0]##*/}"
    install -m0644 -- "${file[0]}" "$snapshot/$name"
    sign_file "$key_home" "$signing" "$snapshot/$name" "$snapshot/$name.sig"
    package_names+=("$name")
done
python3 - "$snapshot" "${package_names[@]}" <<'PY'
from __future__ import annotations
import gzip, io, pathlib, sys, tarfile
root=pathlib.Path(sys.argv[1])
filenames=sys.argv[2:]

def write(path: pathlib.Path, include_files: bool) -> None:
    with path.open('wb') as raw:
        with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0) as zipped:
            with tarfile.open(fileobj=zipped,mode='w',format=tarfile.USTAR_FORMAT) as stream:
                for filename in filenames:
                    package=filename.split('-1.0.0-1-any.pkg.tar.zst',1)[0]
                    directory=f'{package}-1.0.0-1'
                    info=tarfile.TarInfo(directory+'/')
                    info.type=tarfile.DIRTYPE; info.mode=0o755; info.uid=info.gid=0; info.mtime=0
                    stream.addfile(info)
                    desc=f'%FILENAME%\n{filename}\n\n%NAME%\n{package}\n'.encode()
                    info=tarfile.TarInfo(directory+'/desc')
                    info.mode=0o644; info.uid=info.gid=0; info.mtime=0; info.size=len(desc)
                    stream.addfile(info,io.BytesIO(desc))
                    if include_files:
                        payload=f'%FILES%\nusr/share/{package}/fixture\n'.encode()
                        info=tarfile.TarInfo(directory+'/files')
                        info.mode=0o644; info.uid=info.gid=0; info.mtime=0; info.size=len(payload)
                        stream.addfile(info,io.BytesIO(payload))
write(root/'arch-linux.db.tar.gz',False)
write(root/'arch-linux.files.tar.gz',True)
PY
for file in arch-linux.db.tar.gz arch-linux.files.tar.gz; do
    chmod 0644 -- "$snapshot/$file"
    sign_file "$key_home" "$signing" "$snapshot/$file" "$snapshot/$file.sig"
done
cp -- "$snapshot/arch-linux.db.tar.gz" "$snapshot/arch-linux.db"
cp -- "$snapshot/arch-linux.db.tar.gz.sig" "$snapshot/arch-linux.db.sig"
cp -- "$snapshot/arch-linux.files.tar.gz" "$snapshot/arch-linux.files"
cp -- "$snapshot/arch-linux.files.tar.gz.sig" "$snapshot/arch-linux.files.sig"
cp -- "$fixture_project/repository/trust/"* "$snapshot/"
chmod 0644 -- "$snapshot/"*
unsigned_build="$work/unsigned-build"
mkdir -m0755 -- "$unsigned_build" "$unsigned_build/metadata"
for package in "${packages[@]}"; do
    file=("$fixture_packages/${package}-"*.pkg.tar.zst)
    install -m0644 -- "${file[0]}" "$unsigned_build/${file[0]##*/}"
    install -m0644 -- "$fixture_project/packages/$package/.SRCINFO" \
        "$unsigned_build/metadata/$package.SRCINFO"
done
(
    cd -- "$unsigned_build"
    while IFS= read -r file; do sha256sum --binary -- "$file"; done \
        < <(find . -type f ! -name BUILD-METADATA.json ! -name UNSIGNED-SHA256SUMS \
            -printf '%P\n' | LC_ALL=C sort)
) >"$unsigned_build/UNSIGNED-SHA256SUMS"
unsigned_manifest="$unsigned_build/UNSIGNED-SHA256SUMS"
chmod 0644 -- "$unsigned_manifest"
unsigned_manifest_hash="$(sha256sum --binary -- "$unsigned_manifest" | awk '{print $1}')"
build_metadata="$unsigned_build/BUILD-METADATA.json"
python3 - "$build_metadata" "$source_commit" "$source_tree" "$installer_hash" \
    "$package_set_hash" "$source_epoch" "$unsigned_manifest_hash" "${package_names[@]}" <<'PY'
import json, pathlib, sys
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
pathlib.Path(sys.argv[1]).write_text(json.dumps(data,sort_keys=True,separators=(',',':'))+'\n')
PY
chmod 0644 -- "$build_metadata"
build_metadata_hash="$(sha256sum --binary -- "$build_metadata" | awk '{print $1}')"
"$fixture_project/repository/verify-unsigned-build.sh" "$unsigned_build" >/dev/null
python3 "$fixture_project/repository/snapshot-manifest.py" create "$snapshot" 1.0.0 \
    --build-metadata "$build_metadata"
sign_file "$key_home" "$signing" "$snapshot/repository-manifest.json" "$snapshot/repository-manifest.json.sig"

verify_snapshot() {
    "$fixture_project/repository/verify-signed-repository.sh" "$1" \
        --release-version 1.0.0 \
        --source-commit "$source_commit" \
        --source-tree "$source_tree" \
        --build-metadata-sha256 "$build_metadata_hash" \
        --unsigned-manifest-sha256 "$unsigned_manifest_hash"
}

verify_snapshot "$snapshot" >/dev/null

for mutation in schema1 missing-field extra-field noncanonical; do
    metadata_negative="$work/build-metadata-$mutation.json"
    metadata_snapshot="$work/build-metadata-snapshot-$mutation"
    cp -- "$build_metadata" "$metadata_negative"
    cp -a -- "$snapshot" "$metadata_snapshot"
    rm -- "$metadata_snapshot/repository-manifest.json" \
        "$metadata_snapshot/repository-manifest.json.sig"
    python3 - "$metadata_negative" "$mutation" <<'PY'
import json, pathlib, sys
path=pathlib.Path(sys.argv[1]); data=json.loads(path.read_text())
if sys.argv[2]=='schema1': data['schema']=1
elif sys.argv[2]=='missing-field': del data['sourceTree']
elif sys.argv[2]=='extra-field': data['unexpected']='value'
if sys.argv[2]=='noncanonical': path.write_text(json.dumps(data,indent=2)+'\n')
else: path.write_text(json.dumps(data,sort_keys=True,separators=(',',':'))+'\n')
PY
    chmod 0644 -- "$metadata_negative"
    if python3 "$fixture_project/repository/snapshot-manifest.py" create \
        "$metadata_snapshot" 1.0.0 --build-metadata "$metadata_negative" >/dev/null 2>&1; then
        printf 'repository check failed: invalid build metadata accepted: %s\n' "$mutation" >&2
        exit 1
    fi
done

resign_manifest() {
    local target="$1"
    rm -f -- "$target/repository-manifest.json" "$target/repository-manifest.json.sig"
    python3 "$fixture_project/repository/snapshot-manifest.py" create "$target" 1.0.0 \
        --build-metadata "$build_metadata"
    sign_file "$key_home" "$signing" "$target/repository-manifest.json" "$target/repository-manifest.json.sig"
}
sign_existing_manifest() {
    local target="$1"
    rm -f -- "$target/repository-manifest.json.sig"
    sign_file "$key_home" "$signing" "$target/repository-manifest.json" "$target/repository-manifest.json.sig"
}
expect_rejected() {
    local label="$1" target="$2"
    if verify_snapshot "$target" >/dev/null 2>&1; then
        printf 'repository check failed: negative fixture accepted: %s\n' "$label" >&2
        exit 1
    fi
}

negative="$work/tampered-package"
cp -a -- "$snapshot" "$negative"
printf 'tamper\n' >>"$negative/${package_names[0]}"
rm -- "$negative/${package_names[0]}.sig"
sign_file "$key_home" "$signing" "$negative/${package_names[0]}" \
    "$negative/${package_names[0]}.sig"
resign_manifest "$negative"
expect_rejected 'tampered package with valid package and manifest signatures' "$negative"

wrong_home="$work/wrong-key"
mapfile -t wrong_fingerprints < <(make_key "$wrong_home" 'Wrong Repository Test <wrong@invalid>')
wrong_signing="${wrong_fingerprints[1]}"
negative="$work/wrong-signature"
cp -a -- "$snapshot" "$negative"
rm -- "$negative/${package_names[0]}.sig"
sign_file "$wrong_home" "$wrong_signing" "$negative/${package_names[0]}" "$negative/${package_names[0]}.sig"
resign_manifest "$negative"
expect_rejected 'signature from another key' "$negative"

negative="$work/missing-signature"
cp -a -- "$snapshot" "$negative"
rm -- "$negative/${package_names[0]}.sig"
resign_manifest "$negative"
expect_rejected 'missing package signature' "$negative"

negative="$work/extra-file"
cp -a -- "$snapshot" "$negative"
printf 'unexpected\n' >"$negative/unexpected.txt"
chmod 0644 -- "$negative/unexpected.txt"
resign_manifest "$negative"
expect_rejected 'extra public file' "$negative"

for mutation in \
    sourceCommit:0000000000000000000000000000000000000000 \
    sourceTree:1111111111111111111111111111111111111111 \
    installerSha256:0000000000000000000000000000000000000000000000000000000000000000 \
    packageSetSha256:1111111111111111111111111111111111111111111111111111111111111111 \
    buildMetadataSha256:2222222222222222222222222222222222222222222222222222222222222222 \
    unsignedManifestSha256:3333333333333333333333333333333333333333333333333333333333333333 \
    sourceDateEpoch:1; do
    field="${mutation%%:*}"
    value="${mutation#*:}"
    negative="$work/wrong-$field"
    cp -a -- "$snapshot" "$negative"
    python3 - "$negative/repository-manifest.json" "$field" "$value" <<'PY'
import json, pathlib, sys
path=pathlib.Path(sys.argv[1]); data=json.loads(path.read_text())
data[sys.argv[2]]=int(sys.argv[3]) if sys.argv[2]=='sourceDateEpoch' else sys.argv[3]
path.write_text(json.dumps(data,sort_keys=True,separators=(',',':'))+'\n')
PY
    sign_existing_manifest "$negative"
    expect_rejected "validly signed wrong $field" "$negative"
done

for mutation in schema1 extra-field; do
    negative="$work/$mutation"
    cp -a -- "$snapshot" "$negative"
    python3 - "$negative/repository-manifest.json" "$mutation" <<'PY'
import json, pathlib, sys
path=pathlib.Path(sys.argv[1]); data=json.loads(path.read_text())
if sys.argv[2]=='schema1': data['schema']=1
else: data['unexpected']='value'
path.write_text(json.dumps(data,sort_keys=True,separators=(',',':'))+'\n')
PY
    sign_existing_manifest "$negative"
    expect_rejected "$mutation repository manifest" "$negative"
done

archive_stage="$work/archive-stage"
mkdir -p -- "$archive_stage/repo/x86_64"
cp -a -- "$snapshot/." "$archive_stage/repo/x86_64/"
find "$archive_stage" -type d -exec chmod 0755 -- {} +
find "$archive_stage" -type f -exec chmod 0644 -- {} +
(
    cd -- "$archive_stage"
    tar --sort=name --format=ustar --owner=0 --group=0 --numeric-owner \
        --mtime="@${source_epoch}" -cf - repo |
        zstd --compress --quiet --threads=1 -19 --stdout >"$work/repository.tar.zst"
)
chmod 0644 -- "$work/repository.tar.zst"
python3 "$repo_root/repository/safe-extract-snapshot.py" "$work/repository.tar.zst" "$work/extracted"
verify_snapshot "$work/extracted/repo/x86_64" >/dev/null

python3 - "$work" <<'PY'
import io, pathlib, sys, tarfile
root=pathlib.Path(sys.argv[1]); data=b'escape'
def directories(stream):
    for name in ('repo/','repo/x86_64/'):
        info=tarfile.TarInfo(name); info.type=tarfile.DIRTYPE; info.mode=0o755; stream.addfile(info)
def regular(stream,name='repo/x86_64/file'):
    info=tarfile.TarInfo(name); info.mode=0o644; info.size=len(data); stream.addfile(info,io.BytesIO(data))
for case in ('traversal','absolute','symlink','hardlink','device','duplicate','oversize'):
    if case=='oversize':
        with (root/f'{case}.tar').open('wb') as raw:
            for name in ('repo/','repo/x86_64/'):
                info=tarfile.TarInfo(name); info.type=tarfile.DIRTYPE; info.mode=0o755
                raw.write(info.tobuf(format=tarfile.USTAR_FORMAT))
            info=tarfile.TarInfo('repo/x86_64/oversize'); info.mode=0o644; info.size=1024*1024*1024+1
            raw.write(info.tobuf(format=tarfile.USTAR_FORMAT)); raw.write(b'\0'*1024)
        continue
    with tarfile.open(root/f'{case}.tar','w',format=tarfile.USTAR_FORMAT) as stream:
        if case=='traversal': regular(stream,'../escape')
        elif case=='absolute': regular(stream,'/escape')
        else:
            directories(stream)
            if case=='symlink':
                info=tarfile.TarInfo('repo/x86_64/link'); info.type=tarfile.SYMTYPE; info.mode=0o777; info.linkname='/etc/passwd'; stream.addfile(info)
            elif case=='hardlink':
                info=tarfile.TarInfo('repo/x86_64/link'); info.type=tarfile.LNKTYPE; info.mode=0o644; info.linkname='repo/x86_64/file'; stream.addfile(info)
            elif case=='device':
                info=tarfile.TarInfo('repo/x86_64/device'); info.type=tarfile.CHRTYPE; info.mode=0o600; stream.addfile(info)
            else:
                regular(stream); regular(stream)
PY
for malicious in traversal absolute symlink hardlink device duplicate oversize; do
    zstd --compress --quiet --threads=1 -19 --stdout \
        <"$work/$malicious.tar" >"$work/$malicious.tar.zst"
    if python3 "$repo_root/repository/safe-extract-snapshot.py" \
        "$work/$malicious.tar.zst" "$work/extracted-$malicious" >/dev/null 2>&1; then
        printf 'repository check failed: unsafe archive accepted: %s\n' "$malicious" >&2
        exit 1
    fi
done

assets="$work/release-assets"
archive="arch-linux-repository-1.0.0.tar.zst"
release_verify_temp="$work/release-verify-temp"
mkdir -m0755 -- "$assets" "$release_verify_temp"
install -m0644 -- "$work/repository.tar.zst" "$assets/$archive"
sign_file "$key_home" "$signing" "$assets/$archive" "$assets/$archive.sig"
printf '%s *%s\n' "$(sha256sum --binary -- "$assets/$archive" | awk '{print $1}')" "$archive" \
    >"$assets/$archive.sha256"
chmod 0644 -- "$assets/$archive.sha256"
install -m0644 -- "$fixture_project/install.sh" "$assets/install.sh"
install -m0644 -- "$fixture_project/arch-linux-installer.sh" "$assets/arch-linux-installer.sh"
sign_file "$key_home" "$signing" "$assets/arch-linux-installer.sh" "$assets/arch-linux-installer.sh.sig"
printf '%s *arch-linux-installer.sh\n' \
    "$(sha256sum --binary -- "$assets/arch-linux-installer.sh" | awk '{print $1}')" \
    >"$assets/arch-linux-installer.sh.sha256"
chmod 0644 -- "$assets/arch-linux-installer.sh.sha256"
for file in arch-linux.gpg primary-fingerprint signing-subkey-fingerprint; do
    install -m0644 -- "$fixture_project/repository/trust/$file" "$assets/$file"
done
install -m0644 -- "$build_metadata" "$assets/BUILD-METADATA.json"
install -m0644 -- "$unsigned_manifest" "$assets/UNSIGNED-SHA256SUMS"
refresh_release_manifest() {
    local target="$1"
    rm -f -- "$target/RELEASE-SHA256SUMS" "$target/RELEASE-SHA256SUMS.sig"
    (
        cd -- "$target"
        while IFS= read -r -d '' file; do sha256sum --binary -- "${file#./}"; done \
            < <(find . -mindepth 1 -maxdepth 1 -type f \
                ! -name RELEASE-SHA256SUMS ! -name RELEASE-SHA256SUMS.sig -print0 | LC_ALL=C sort -z)
    ) >"$target/RELEASE-SHA256SUMS"
    chmod 0644 -- "$target/RELEASE-SHA256SUMS"
    sign_file "$key_home" "$signing" "$target/RELEASE-SHA256SUMS" "$target/RELEASE-SHA256SUMS.sig"
}
verify_release() {
    local target="$1" closure="${2:---phase-a}"
    local extra=()
    [ "$closure" = --phase-a ] || extra=(--source-tree-sha256 "$source_tree_sha256")
    RUNNER_TEMP="$release_verify_temp" "$fixture_project/repository/verify-release-assets.sh" "$target" \
        "$closure" \
        --release-version 1.0.0 \
        --source-commit "$source_commit" \
        --source-tree "$source_tree" \
        "${extra[@]}" \
        --build-metadata-sha256 "$build_metadata_hash" \
        --unsigned-manifest-sha256 "$unsigned_manifest_hash"
}
expect_release_rejected() {
    local label="$1" target="$2"
    if verify_release "$target" >/dev/null 2>&1; then
        printf 'repository check failed: negative release fixture accepted: %s\n' "$label" >&2
        exit 1
    fi
}
refresh_release_manifest "$assets"
verify_release "$assets" >/dev/null

source_tree_sha256="$(
    git -C "$fixture_project" ls-files -z |
        while IFS= read -r -d '' file; do
            mode=0644
            [ -x "$fixture_project/$file" ] && mode=0755
            printf '%s %s *%s\n' "$mode" "$(sha256sum --binary -- "$fixture_project/$file" | awk '{print $1}')" "$file"
        done | LC_ALL=C sort | sha256sum | awk '{print $1}'
)"
final_assets="$work/final-assets"
cp -a -- "$assets" "$final_assets"
evidence_name=arch-linux-acceptance-evidence-1.0.0.tar.zst
acceptance_name=arch-linux-acceptance-1.0.0.json
evidence_root="$work/final-evidence-stage/evidence"
mkdir -p -- "$evidence_root"
python3 -B - "$evidence_root" "$source_commit" "$source_tree" "$build_metadata_hash" \
    "$unsigned_manifest_hash" "$(sha256sum --binary -- "$assets/$archive" | awk '{print $1}')" \
    "$(sha256sum --binary -- "$assets/RELEASE-SHA256SUMS" | awk '{print $1}')" \
    "$snapshot/repository-manifest.json" "$snapshot/repository-manifest.json.sig" \
    "$assets" "$fixture_project" <<'PY'
from __future__ import annotations
import gzip, hashlib, importlib.util, json, os, pathlib, sys

root=pathlib.Path(sys.argv[1])
commit,tree,build_hash,unsigned_hash,snapshot_hash,release_hash=sys.argv[2:8]
repository_manifest=pathlib.Path(sys.argv[8]).read_bytes()
repository_signature=pathlib.Path(sys.argv[9]).read_bytes()
assets=pathlib.Path(sys.argv[10])
source=pathlib.Path(sys.argv[11])
spec=importlib.util.spec_from_file_location('acceptance_manifest_fixture',source/'repository/acceptance-manifest.py')
am=importlib.util.module_from_spec(spec); spec.loader.exec_module(am)
scenarios=(
    ('minimal-ext4-systemdboot','minimal','M'),
    ('stock-gnome-btrfs-luks2-plymouth-grub','luksgrub','G'),
    ('marble-gnome-btrfs-luks2-plymouth-systemdboot','marble','A'),
)
phases=('firstboot','postreboot')
segments=tuple((phase,segment) for phase in phases for segment in ('boot','shutdown'))
ledgers=sorted(f'{phase}-{segment}-frame-ledger.jsonl' for phase,segment in segments)
confirmations=tuple(sorted(am.CONFIRMATIONS))
manifest_value=json.loads(repository_manifest)
objects=manifest_value['files']
object_map={item['name']:item for item in objects}
primary=(assets/'primary-fingerprint').read_text().strip()
signing=(assets/'signing-subkey-fingerprint').read_text().strip()
public_key_hash=hashlib.sha256((assets/'arch-linux.gpg').read_bytes()).hexdigest()
installer_hash=hashlib.sha256((assets/'arch-linux-installer.sh').read_bytes()).hexdigest()
bootstrap_hash=hashlib.sha256((assets/'install.sh').read_bytes()).hexdigest()
iso_hash=json.loads((source/'maintenance/accepted-arch-iso.json').read_text())['sha256']

def encoded(value):
    return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def digest(value):
    return hashlib.sha256(value).hexdigest()
def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(value)
    path.chmod(0o644)
def ppm(width,height,seed):
    pixel=bytes(((seed*17)%256,(seed*31)%256,(seed*47)%256))
    return f'P6\n{width} {height}\n255\n'.encode()+pixel*(width*height)
def identity(phase,index):
    socket_device=10+index//10
    start_time=9000+index if phase=='firstboot' else 9001+index
    values={'phase':phase,'pid':str(100+index),'start_time':str(start_time),
        'qga_identity':f'{socket_device}:{20+index}','qmp_identity':f'{socket_device}:{40+index}',
        'qmp_capture_identity':f'{socket_device}:{60+index}'}
    raw=''.join(f'{key}={values[key]}\n' for key in
        ('phase','pid','start_time','qga_identity','qmp_identity','qmp_capture_identity')).encode()
    return values,raw
def raw_sample(ppm_sha,n,t,previous,width=16,height=16):
    raw_name=f'frame-{ppm_sha}.ppm.gz'
    return {'e':'sample','n':n,'t':t,'gapMs':0 if previous is None else (t-previous)//1_000_000,
        'ppm':ppm_sha,'raw':raw_name,'rawSha':digest(('raw:'+ppm_sha).encode()),'w':width,'h':height}
def control(name,n,t,index):
    return {'e':'control','name':name,'nonce':f'{index:016x}','n':n,'t':t,'state':'running'}
def ledger(phase,segment,ident,digests,index,challenge=False):
    base=1_000_000_000+index*10_000_000_000
    header={'e':'header','schema':1,'phase':phase,'segment':segment,'pid':int(ident['pid']),
        'start':ident['start_time'],'qmp':ident['qmp_identity'],'peerPid':int(ident['pid']),
        'peerUid':1000,'recorderPid':5000+index,'recorderStart':str(9000+index),
        'device':'display0','head':0,'intervalMs':250,'maxGapMs':500,
        'maxRawBytes':45*1024*1024,'maxSamples':2000,'t':base,
        'initial':'prelaunch' if segment=='boot' else 'running'}
    records=[header]
    previous=None
    def add_sample(value,offset):
        nonlocal previous
        item=raw_sample(value,len([row for row in records if row.get('e')=='sample']),base+offset,previous)
        records.append(item); previous=item['t']
    add_sample(digests[0],100_000_000)
    records.append({'e':'ready','n':0,'t':base+110_000_000,'ppm':digests[0],
                    'state':header['initial']})
    if segment=='shutdown':
        records.append(control('shutdown-armed',0,base+120_000_000,index*10+1))
        add_sample(digests[-1],200_000_000)
        records.append({'e':'terminal','reason':'qemu-exit','n':2,'t':base+250_000_000,'qemuExit':True})
    elif challenge:
        records.append(control('cont-sent',0,base+120_000_000,index*10+1))
        add_sample(digests[1],200_000_000)
        records.append(control('challenge-before',1,base+210_000_000,index*10+2))
        add_sample(digests[2],300_000_000)
        records.append(control('challenge-after',2,base+310_000_000,index*10+3))
        add_sample(digests[3],400_000_000)
        records.append(control('challenge-cleared',3,base+410_000_000,index*10+4))
        add_sample(digests[3],450_000_000)
        records.append(control('stop-boot',4,base+460_000_000,index*10+5))
        records.append({'e':'terminal','reason':'requested-stop','n':4,'t':base+470_000_000,
                        'qemuExit':False})
    else:
        records.append(control('cont-sent',0,base+120_000_000,index*10+1))
        for offset,value in enumerate(digests[1:],2):
            add_sample(value,offset*100_000_000)
        last=len([row for row in records if row.get('e')=='sample'])-1
        records.append(control('stop-boot',last,base+(len(digests)+2)*100_000_000,index*10+2))
        records.append({'e':'terminal','reason':'requested-stop','n':last,
                        't':base+(len(digests)+2)*100_000_000+10_000_000,'qemuExit':False})
    raw_map={}
    for item in records:
        if item.get('e')=='sample':
            raw_map[f"frame-raw/{phase}-{segment}/{item['raw']}"]=item['rawSha']
    return records,raw_map

for index,(scenario,prefix,serial_code) in enumerate(scenarios,1):
    run=root/scenario
    evidence=run/'evidence'
    evidence.mkdir(parents=True)
    run_id=f'{prefix}-20260902T00000{index}Z-{index:08x}'
    selected=list(am.EXPECTED_SCREENSHOTS[scenario])
    contacts=sorted(f'{phase}-{segment}-contact-sheet-001.ppm' for phase,segment in segments)
    identities={}
    for phase_index,phase in enumerate(phases,1):
        values,raw=identity(phase,index*10+phase_index)
        identities[phase]=values
        write(evidence/f'{phase}-qemu.identity',raw)
    selected_bytes={name:ppm(16,16,index*20+item) for item,name in enumerate(selected,1)}
    for name,value in selected_bytes.items():
        write(evidence/name,value)
    selected_hashes={name:digest(value) for name,value in selected_bytes.items()}
    raw_hashes={}
    challenge_values={}
    segment_values=[]
    for segment_index,(phase,segment) in enumerate(segments,1):
        challenge=prefix=='minimal' and segment=='boot'
        if challenge:
            before=digest(ppm(16,16,index*30+segment_index))
            after=selected_hashes[f'{phase}-tty.ppm']
            cleared=before
            initial=digest(ppm(16,16,index*30+segment_index+20))
            values=[initial,before,after,cleared]
            challenge_values[phase]=(before,after,cleared)
        elif segment=='boot' and phase=='firstboot':
            values=[digest(ppm(16,16,index*40+segment_index)),
                    *(selected_hashes[name] for name in selected)]
        else:
            values=[digest(ppm(16,16,index*40+segment_index)),
                    digest(ppm(16,16,index*40+segment_index+10))]
        records,raw_map=ledger(phase,segment,identities[phase],values,index*10+segment_index,challenge)
        if index==1 and phase=='firstboot' and segment=='boot':
            mutations=((0,'schema',2),(0,'schema',True),(0,'head',1),(1,'gapMs',False),
                       (2,'n',False),(3,'n',True))
            for record_index,field,bad_value in mutations:
                changed=json.loads(json.dumps(records))
                changed[record_index][field]=bad_value
                try:
                    am.validate_retained_ledger(
                        b''.join(encoded(item) for item in changed),phase,segment,
                        identities[phase],challenge)
                except am.ManifestError:
                    pass
                else:
                    raise SystemExit(
                        f'acceptance negative accepted {field}={bad_value!r}')
        write(evidence/f'{phase}-{segment}-frame-ledger.jsonl',b''.join(encoded(item) for item in records))
        raw_hashes.update(raw_map)
        segment_values.append({'phase':phase,'segment':segment,
                               'samples':sum(item.get('e')=='sample' for item in records),'sheets':1})
    for contact_index,name in enumerate(contacts,1):
        write(evidence/name,ppm(1280,800,index*10+contact_index))
    retained=[*(f'evidence/{name}' for name in ledgers),
        *(f'evidence/{phase}-qemu.identity' for phase in phases),
        *(f'evidence/{name}' for name in selected),*(f'evidence/{name}' for name in contacts)]
    file_hashes={name:digest((run/name).read_bytes()) for name in retained}
    file_hashes.update(raw_hashes)
    challenges={}
    if prefix=='minimal':
        suffix=run_id.rsplit('-',1)[-1]
        for phase in phases:
            before,after,cleared=challenge_values[phase]
            challenges[phase]={'challenge':f'ali-{phase}-{suffix}','before':{'sha256':before},
                'after':{'sha256':after},'cleared':{'sha256':cleared},'changedPixels':256,
                'clearChangedPixels':256,'restoredPixels':0,'input':'hmp-no-enter','clearInput':'ctrl-u'}
    frame_manifest={'schema':1,'status':'SEALED','sourceCommit':commit,'sourceTree':tree,
        'runId':run_id,'scenario':scenario,
        'policy':{'device':'display0','head':0,'intervalMs':250,'maxGapMs':500,
                  'maxEvidenceBytes':500*1024*1024},
        'qemuIdentities':identities,'segments':segment_values,
        'selectedFrames':sorted(selected),'challenges':challenges,'fileHashes':file_hashes}
    frame_manifest_raw=encoded(frame_manifest)
    write(evidence/'frame-evidence-manifest.json',frame_manifest_raw)
    template={'schema':1,'verdict':'PENDING','reviewer':'','reviewedAt':'',
        'sourceCommit':commit,'sourceTree':tree,'runId':run_id,'scenario':scenario,
        'manifestSha256':digest(frame_manifest_raw),'pendingResultSha256':'',
        'confirmations':{name:False for name in confirmations},'notes':''}
    template_raw=encoded(template)
    write(evidence/'manual-review-template.json',template_raw)
    object_rows=''.join(f"{item['name']}\t{item['sha256']}\t{item['size']}\n" for item in objects).encode()
    write(evidence/'repository-objects.tsv',object_rows)
    write(evidence/'repository-manifest.json',repository_manifest)
    write(evidence/'repository-manifest.json.sig',repository_signature)
    marker={'minimal':'MINIMAL','luksgrub':'LUKSGRUB','marble':'MARBLE'}[prefix]
    log=f'{marker}_QEMU_INSTALLER_EXIT status=0\n{marker}_QEMU_INSTALL_COMPLETE run_id={run_id}\n'.encode()
    write(evidence/'scenario.log.gz',gzip.compress(log,mtime=0))
    write(evidence/'final-qemu-img-check.txt',b'No errors were found on the image.\n')
    write(evidence/'no-qemu-process.txt',f'no matching QEMU process remains for {run_id}\n'.encode())
    harness=b''.join(f'{digest((source/name).read_bytes())}  {name}\n'.encode() for name in am.HARNESS_FILES)
    write(run/'harness.sha256',harness)
    write(evidence/'preseal-harness-check.txt',b''.join(f'{name}: OK\n'.encode() for name in am.HARNESS_FILES))
    run_path=f'/fixture/{run_id}'
    initial_ovmf=digest(b'OVMF template fixture')
    final_ovmf=digest(f'OVMF final {scenario}'.encode())
    write(run/'OVMF_VARS.initial.sha256',f'{initial_ovmf}  {run_path}/OVMF_VARS.fd\n'.encode())
    write(run/'OVMF_VARS.final.sha256',f'{final_ovmf}  {run_path}/OVMF_VARS.fd\n'.encode())
    write(run/'payload.iso.sha256',f"{digest(f'payload {scenario}'.encode())}  {run_path}/payload.iso\n".encode())
    runtime_names=('/usr/bin/qemu-system-x86_64','/usr/bin/qemu-img',
                   '/usr/share/OVMF/OVMF_CODE_4M.fd','/usr/share/OVMF/OVMF_VARS_4M.fd')
    write(run/'runtime-inputs.sha256',b''.join(
        f"{digest(f'{scenario}:{name}'.encode())}  {name}\n".encode() for name in runtime_names))
    assertion_rows=[]
    assertion_values=[]
    for assertion_id in am.EXPECTED_ASSERTIONS[scenario]:
        detail=f'fixture exercises exact required assertion {assertion_id}'
        assertion_rows.append(f'{assertion_id}\tPASS\t{detail}\n')
        assertion_values.append({'id':assertion_id,'status':'PASS','detail':detail})
    write(run/'assertions.tsv',''.join(assertion_rows).encode())
    write(run/'qemu-version.txt',b'QEMU emulator version 9.2.0\n')
    if prefix=='marble':
        runtime_suffixes=('/repository/repository.env','/repository.contract','/repository-ca.crt',
                          '/repository-server.crt')
        write(run/'repository-runtime.sha256',b''.join(
            f"{digest(f'{scenario}:{name}'.encode())}  {run_path}{name}\n".encode()
            for name in runtime_suffixes))
    retained_counter=400_000_000+index
    write(run/'evidence-size.txt',f'{retained_counter}\n'.encode())
    serial=f'ALI100{serial_code}{index:012X}'
    result={'assertions':assertion_values,
        'buildMetadataSha256':build_hash,'contactSheets':contacts,'exitStatus':0,'failedPhase':None,
        'frameLedgers':ledgers,'harnessSha256':digest(harness),'inputMode':'staged',
        'installerSha256':installer_hash,'isoSha256':iso_hash,
        'manualReviewStatus':'PENDING','manualReviewTemplateSha256':digest(template_raw),
        'releaseSha256sumsSha256':release_hash,'releaseVersion':'1.0.0',
        'repositoryDatabaseSha256':object_map['arch-linux.db.tar.gz']['sha256'],
        'repositoryDatabaseSignatureSha256':object_map['arch-linux.db.tar.gz.sig']['sha256'],
        'repositoryFilesSha256':object_map['arch-linux.files.tar.gz']['sha256'],
        'repositoryFilesSignatureSha256':object_map['arch-linux.files.tar.gz.sig']['sha256'],
        'repositoryManifestSha256':digest(repository_manifest),
        'repositoryManifestSignatureSha256':digest(repository_signature),
        'repositoryObjects':objects,'repositoryPackageSetSha256':manifest_value['packageSetSha256'],
        'repositoryPrimaryFingerprint':primary,'repositoryPublicKeySha256':public_key_hash,
        'repositorySigningFingerprint':signing,'repositorySnapshotSha256':snapshot_hash,
        'retainedEvidenceBytes':retained_counter,'runId':run_id,'scenario':scenario,
        'screenshots':sorted(selected),'snapshotVerification':'INDEPENDENT_PASS',
        'sourceCommit':commit,'sourceTree':tree,'status':'PENDING_VISUAL_REVIEW',
        'targetSerial':serial,'unsignedManifestSha256':unsigned_hash}
    assert set(result)==am.RESULT_KEYS
    model={'minimal':'MIN','luksgrub':'GRB','marble':'MAR'}[prefix]
    identity_rows=[
        ('scenario',scenario),('input_mode','staged'),('release_version','1.0.0'),('run_id',run_id),
        ('source_commit',commit),('source_tree',tree),('installer_sha256',installer_hash),
        ('bootstrap_sha256',bootstrap_hash),('harness_sha256',digest(harness)),('iso_sha256',iso_hash),
        ('snapshot_sha256',snapshot_hash),('build_metadata_sha256',build_hash),
        ('unsigned_manifest_sha256',unsigned_hash),('target_serial',serial),('target_vendor','SNAPLYZE'),
        ('target_model',f'ALI_{model}_{index:08X}'),('repository_public_key_sha256',public_key_hash),
        ('repository_primary_fingerprint',primary),('repository_signing_fingerprint',signing),
        ('repository_package_set_sha256',manifest_value['packageSetSha256']),
        ('repository_manifest_sha256',digest(repository_manifest)),
        ('repository_manifest_signature_sha256',digest(repository_signature)),
        ('repository_database_sha256',object_map['arch-linux.db.tar.gz']['sha256']),
        ('repository_database_signature_sha256',object_map['arch-linux.db.tar.gz.sig']['sha256']),
        ('repository_files_sha256',object_map['arch-linux.files.tar.gz']['sha256']),
        ('repository_files_signature_sha256',object_map['arch-linux.files.tar.gz.sig']['sha256']),
        ('release_sha256sums_sha256',release_hash),
    ]
    identity_text=''.join(f'{key}={value}\n' for key,value in identity_rows)
    identity_text+=''.join(
        f"repository_object_sha256={item['sha256']} name={item['name']} size={item['size']}\n"
        for item in objects)
    if prefix=='marble': identity_text+='repository_server_port=43210\n'
    write(run/'identity.txt',identity_text.encode())
    result_raw=encoded(result)
    write(run/'result.json',result_raw)
    receipt=template|{'verdict':'PASS','reviewer':'fixture-reviewer',
        'reviewedAt':'2026-09-02T00:10:00Z','pendingResultSha256':digest(result_raw),
        'confirmations':{name:True for name in confirmations}}
    receipt_raw=encoded(receipt)
    write(evidence/'manual-review-receipt.json',receipt_raw)
    verdict={'schema':1,'status':'PASS','sourceCommit':commit,'sourceTree':tree,
        'runId':run_id,'scenario':scenario,'manifestSha256':digest(frame_manifest_raw),
        'templateSha256':digest(template_raw),'receiptSha256':digest(receipt_raw),
        'pendingResultSha256':digest(result_raw),'rawFramesRemoved':True,
        'budgetBytes':500*1024*1024,'transientEvidenceBytes':480_000_000,
        'cumulativePermanentEvidenceBytes':470_000_000}
    write(run/'visual-review-verdict.json',encoded(verdict))

for base,dirs,files in os.walk(root):
    pathlib.Path(base).chmod(0o755)
    for name in dirs:
        (pathlib.Path(base)/name).chmod(0o755)
    for name in files:
        (pathlib.Path(base)/name).chmod(0o644)
PY
evidence_tar="$work/final-evidence.tar"
python3 - "$evidence_root" "$evidence_tar" "$source_epoch" <<'PY'
import io, pathlib, sys, tarfile
root=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); epoch=int(sys.argv[3])
paths=[root,*root.rglob('*')]
paths.sort(key=lambda path: pathlib.PurePosixPath('evidence',*path.relative_to(root).parts).as_posix())
with tarfile.open(output,'w',format=tarfile.USTAR_FORMAT) as archive:
    for path in paths:
        name=pathlib.PurePosixPath('evidence',*path.relative_to(root).parts).as_posix()
        info=tarfile.TarInfo(name); info.uid=info.gid=0; info.uname=info.gname=''; info.mtime=epoch
        if path.is_dir():
            info.type=tarfile.DIRTYPE; info.mode=0o755; info.size=0; archive.addfile(info)
        else:
            payload=path.read_bytes(); info.type=tarfile.REGTYPE; info.mode=0o644; info.size=len(payload)
            archive.addfile(info,io.BytesIO(payload))
PY
zstd --compress --quiet --threads=1 -19 --stdout -- "$evidence_tar" >"$final_assets/$evidence_name"
chmod 0644 -- "$final_assets/$evidence_name"
python3 "$fixture_project/repository/acceptance-manifest.py" create \
    --phase-a "$assets" --evidence-root "$evidence_root" \
    --evidence-archive "$final_assets/$evidence_name" --release-version 1.0.0 \
    --source-commit "$source_commit" --source-tree "$source_tree" \
    --source-tree-sha256 "$source_tree_sha256" --build-metadata-sha256 "$build_metadata_hash" \
    --unsigned-manifest-sha256 "$unsigned_manifest_hash" \
    --snapshot-sha256 "$(sha256sum --binary -- "$assets/$archive" | awk '{print $1}')" \
    --output "$final_assets/$acceptance_name"
sign_file "$key_home" "$signing" "$final_assets/$evidence_name" "$final_assets/$evidence_name.sig"
sign_file "$key_home" "$signing" "$final_assets/$acceptance_name" "$final_assets/$acceptance_name.sig"
verify_release "$final_assets" --finalized >/dev/null
for file in "$assets"/*; do
    cmp --silent -- "$file" "$final_assets/${file##*/}" || {
        printf 'repository check failed: finalized closure changed Phase A\n' >&2
        exit 1
    }
done

negative="$work/release-installer-checksum-private-mode"
cp -a -- "$assets" "$negative"
chmod 0600 -- "$negative/arch-linux-installer.sh.sha256"
expect_release_rejected 'installer checksum private mode' "$negative"

negative="$work/release-missing-bootstrap"
cp -a -- "$assets" "$negative"
rm -- "$negative/install.sh"
expect_release_rejected 'missing install.sh' "$negative"

negative="$work/release-extra-asset"
cp -a -- "$assets" "$negative"
printf 'unexpected\n' >"$negative/unexpected.txt"
chmod 0644 -- "$negative/unexpected.txt"
expect_release_rejected 'extra asset' "$negative"

negative="$work/release-modified-bootstrap"
cp -a -- "$assets" "$negative"
printf 'tamper\n' >>"$negative/install.sh"
expect_release_rejected 'modified install.sh' "$negative"

negative="$work/final-release-nonempty-deferred"
cp -a -- "$final_assets" "$negative"
python3 - "$negative/$acceptance_name" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['deferred']=['bad']; p.write_text(json.dumps(d,sort_keys=True,separators=(',',':'))+'\n')
PY
rm -- "$negative/$acceptance_name.sig"
sign_file "$key_home" "$signing" "$negative/$acceptance_name" "$negative/$acceptance_name.sig"
if verify_release "$negative" --finalized >/dev/null 2>&1; then
    printf 'repository check failed: finalized nonempty deferred accepted\n' >&2
    exit 1
fi

negative="$work/final-release-wrong-qemu-result-binding"
cp -a -- "$final_assets" "$negative"
python3 - "$negative/$acceptance_name" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text())
scenario='minimal-ext4-systemdboot'
actual=d['qemu'][scenario]['resultSha256']
d['qemu'][scenario]['resultSha256']=('f'*64 if actual != 'f'*64 else 'e'*64)
p.write_text(json.dumps(d,sort_keys=True,separators=(',',':'))+'\n')
PY
rm -- "$negative/$acceptance_name.sig"
sign_file "$key_home" "$signing" "$negative/$acceptance_name" "$negative/$acceptance_name.sig"
if verify_release "$negative" --finalized >/dev/null 2>&1; then
    printf 'repository check failed: finalized wrong QEMU result binding accepted\n' >&2
    exit 1
fi

negative="$work/final-release-noncanonical-acceptance"
cp -a -- "$final_assets" "$negative"
python3 - "$negative/$acceptance_name" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); p.write_text(json.dumps(json.loads(p.read_text()),indent=2)+'\n')
PY
rm -- "$negative/$acceptance_name.sig"
sign_file "$key_home" "$signing" "$negative/$acceptance_name" "$negative/$acceptance_name.sig"
if verify_release "$negative" --finalized >/dev/null 2>&1; then
    printf 'repository check failed: finalized noncanonical acceptance manifest accepted\n' >&2
    exit 1
fi

negative="$work/final-release-linked-evidence-member"
cp -a -- "$final_assets" "$negative"
complete_evidence_tar="$work/complete-final-evidence.tar"
unsafe_evidence_tar="$work/unsafe-final-evidence.tar"
zstd --decompress --quiet --stdout -- "$final_assets/$evidence_name" >"$complete_evidence_tar"
python3 - "$complete_evidence_tar" "$unsafe_evidence_tar" <<'PY'
import copy
import hashlib
import pathlib
import sys
import tarfile

source_path=pathlib.Path(sys.argv[1])
output_path=pathlib.Path(sys.argv[2])
link_name='evidence/minimal-ext4-systemdboot/evidence/preseal-harness-check.txt'
target_name='evidence/marble-gnome-btrfs-luks2-plymouth-systemdboot/evidence/preseal-harness-check.txt'

with tarfile.open(source_path,'r:') as source:
    members=source.getmembers()
    by_name={member.name:member for member in members}
    if len(by_name) != len(members) or link_name not in by_name or target_name not in by_name:
        raise SystemExit('complete evidence archive fixture closure differs')
    link_source=by_name[link_name]
    link_target=by_name[target_name]
    if not link_source.isreg() or not link_target.isreg():
        raise SystemExit('hardlink mutation inputs are not regular files')
    source_payload=source.extractfile(link_source)
    target_payload=source.extractfile(link_target)
    if source_payload is None or target_payload is None or source_payload.read() != target_payload.read():
        raise SystemExit('hardlink mutation target is not byte-identical')
    with tarfile.open(output_path,'w',format=tarfile.USTAR_FORMAT) as output:
        changed=0
        for member in members:
            if member.name == link_name:
                replacement=copy.copy(member)
                replacement.type=tarfile.LNKTYPE
                replacement.linkname=target_name
                replacement.size=0
                replacement.pax_headers={}
                output.addfile(replacement)
                changed+=1
            elif member.isreg():
                payload=source.extractfile(member)
                if payload is None:
                    raise SystemExit('complete evidence archive member cannot be read')
                output.addfile(member,payload)
            else:
                output.addfile(member)
        if changed != 1:
            raise SystemExit('hardlink mutation count differs')

def records(path):
    result=[]
    with tarfile.open(path,'r:') as archive:
        for member in archive.getmembers():
            digest=None
            if member.isreg():
                payload=archive.extractfile(member)
                if payload is None:
                    raise SystemExit('evidence archive verification member cannot be read')
                digest=hashlib.sha256(payload.read()).hexdigest()
            result.append((member.name,member.type,member.mode,member.uid,member.gid,member.mtime,
                           member.size,member.uname,member.gname,member.linkname,digest))
    return result

before=records(source_path)
after=records(output_path)
if len(before) != len(after) or [item[0] for item in before] != [item[0] for item in after]:
    raise SystemExit('hardlink mutation changed the evidence member closure')
differences=[]
for old,new in zip(before,after,strict=True):
    if old != new:
        differences.append((old,new))
if len(differences) != 1 or differences[0][0][0] != link_name:
    raise SystemExit('hardlink mutation changed more than one evidence member')
old,new=differences[0]
if (old[1] != tarfile.REGTYPE or new[1] != tarfile.LNKTYPE or new[9] != target_name or
        old[2:6] != new[2:6] or new[6] != 0 or old[7:9] != new[7:9]):
    raise SystemExit('hardlink mutation metadata differs')
PY
zstd --compress --quiet --threads=1 -19 --stdout -- "$unsafe_evidence_tar" >"$negative/$evidence_name"
chmod 0644 -- "$negative/$evidence_name"
python3 - "$negative/$acceptance_name" "$negative/$evidence_name" <<'PY'
import hashlib,json,pathlib,sys
manifest=pathlib.Path(sys.argv[1]); evidence=pathlib.Path(sys.argv[2]); data=json.loads(manifest.read_text())
data['evidenceArchiveSha256']=hashlib.sha256(evidence.read_bytes()).hexdigest()
data['evidenceArchiveSizeBytes']=evidence.stat().st_size
manifest.write_text(json.dumps(data,sort_keys=True,separators=(',',':'))+'\n')
PY
rm -- "$negative/$evidence_name.sig" "$negative/$acceptance_name.sig"
sign_file "$key_home" "$signing" "$negative/$evidence_name" "$negative/$evidence_name.sig"
sign_file "$key_home" "$signing" "$negative/$acceptance_name" "$negative/$acceptance_name.sig"
linked_evidence_error="$work/final-release-linked-evidence-member.stderr"
set +e
verify_release "$negative" --finalized > /dev/null 2>"$linked_evidence_error"
linked_evidence_status=$?
set -e
[ "$linked_evidence_status" -eq 1 ] || {
    printf 'repository check failed: finalized linked evidence archive member accepted\n' >&2
    exit 1
}
expected_linked_evidence_error='ERROR: release acceptance manifest failed: acceptance archive contains a link, sparse member, or special object'
[ "$(cat -- "$linked_evidence_error")" = "$expected_linked_evidence_error" ] || {
    printf 'repository check failed: linked evidence rejection was not isolated to the special-member guard\n' >&2
    exit 1
}

negative="$work/release-wrong-archive-signature"
cp -a -- "$assets" "$negative"
rm -- "$negative/$archive.sig"
sign_file "$wrong_home" "$wrong_signing" "$negative/$archive" "$negative/$archive.sig"
refresh_release_manifest "$negative"
expect_release_rejected 'archive signature from another key' "$negative"
[ -z "$(find "$release_verify_temp" -mindepth 1 -print -quit)" ] || {
    printf 'repository check failed: release verifier left temporary data after failure\n' >&2
    exit 1
}

negative="$work/release-bad-archive-checksum"
cp -a -- "$assets" "$negative"
printf '%064d *%s\n' 0 "$archive" >"$negative/$archive.sha256"
refresh_release_manifest "$negative"
expect_release_rejected 'wrong archive checksum record' "$negative"

negative="$work/release-wrong-manifest-key"
cp -a -- "$assets" "$negative"
rm -- "$negative/RELEASE-SHA256SUMS.sig"
sign_file "$wrong_home" "$wrong_signing" "$negative/RELEASE-SHA256SUMS" \
    "$negative/RELEASE-SHA256SUMS.sig"
expect_release_rejected 'release manifest signature from another key' "$negative"

printf 'REPOSITORY_CHECKS_RESULT schema=1 namespace_fixtures=%s scenarios=10 signer=passed release_closures=14+18 deferred=%s\n' \
    "$namespace_marker" "$([ "$namespace_marker" = full ] && printf none || printf github-hosted-container-v1)"
