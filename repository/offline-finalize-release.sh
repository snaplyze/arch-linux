#!/usr/bin/bash -p

set +x
set -E
set -euo pipefail
umask 077
trap 'printf "ERROR: release finalization command failed at source line %s\n" "$LINENO" >&2' ERR

[[ "${BASH_SOURCE[0]}" = /* ]] || { printf 'ERROR: sealed finalizer path is not absolute\n' >&2; exit 1; }
script_dir="${BASH_SOURCE[0]%/*}"
case "$-" in
    *p*) ;;
    *) printf 'ERROR: release finalization requires the sealed compiled launcher\n' >&2; exit 1 ;;
esac
if [ "${ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT:-}" != sealed-root-v1 ] ||
    [ "${GNUPGHOME:-}" != /run/user/0/arch-linux-offline/gnupg ] ||
    [ "${OFFLINE_SIGN_PASSPHRASE_FILE:-}" != /proc/self/fd/7 ] ||
    [ -n "${CI+x}" ] || [ -n "${GITHUB_ACTIONS+x}" ]; then
    printf 'ERROR: release finalization requires the sealed namespace boundary\n' >&2
    exit 1
fi
exec 6<&- 9<&-
fd_guard="${script_dir}/offline-signing-fd-guard.py"
readonly fd_guard
/usr/bin/python3 -I "$fd_guard" assert-signer || {
    printf 'ERROR: release finalization private authority is invalid\n' >&2
    exit 1
}
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

public_exec() {
    /usr/bin/python3 -I "$fd_guard" exec-public "$@" 7<&-
}

usage() {
    cat 7<&- >&2 <<USAGE
Usage: $0 --phase-a DIR --output DIR --release-version X.Y.Z \
  --build-metadata-sha256 SHA --unsigned-manifest-sha256 SHA \
  --snapshot-sha256 SHA --minimal-run DIR --stock-run DIR --marble-run DIR
USAGE
}

sign_file() {
    local key="$1" payload="$2" signature="$3"
    [ ! -e "$signature" ] && [ ! -L "$signature" ] ||
        repository_die 'final signature output already exists' || return
    repository_assert_regular_file "$payload" 'payload selected for final signing' 7<&- || return
    /usr/bin/python3 -I "$fd_guard" exec-signing-gpg /usr/bin/gpg \
        --batch --no-options --no-autostart --no-tty --pinentry-mode loopback \
        --passphrase-file /proc/self/fd/7 --local-user "${key}!" \
        --detach-sign --output "$signature" -- "$payload" || return
    public_exec /usr/bin/chmod 0644 -- "$signature"
}

assert_run_tree() {
    local root="$1" unexpected
    repository_assert_directory "$root" 'accepted QEMU run' 7<&- || return
    unexpected="$(public_exec /usr/bin/find "$root" -xdev -mindepth 1 \
        \( -type l -o ! -type f ! -type d \) -print -quit)"
    [ -z "$unexpected" ] || repository_die 'accepted QEMU evidence contains a link or special object' || return
    unexpected="$(public_exec /usr/bin/find "$root" -xdev -type f -links +1 -print -quit)"
    [ -z "$unexpected" ] || repository_die 'accepted QEMU evidence contains a hard-linked file'
}

main() {
    local phase_a_arg='' output_arg='' version='' build_hash='' unsigned_hash='' snapshot_hash=''
    local minimal_arg='' stock_arg='' marble_arg=''
    local phase_a output minimal stock marble source_commit source_tree source_tree_sha primary signing
    local accepted_minimal accepted_stock accepted_marble
    local minimal_before stock_before marble_before
    local work stage evidence_stage evidence_tar evidence_archive acceptance archive source_epoch cleanup_command file
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --phase-a) [ "$#" -ge 2 ] || { usage; return 2; }; phase_a_arg="$2"; shift 2 ;;
            --output) [ "$#" -ge 2 ] || { usage; return 2; }; output_arg="$2"; shift 2 ;;
            --release-version) [ "$#" -ge 2 ] || { usage; return 2; }; version="$2"; shift 2 ;;
            --build-metadata-sha256) [ "$#" -ge 2 ] || { usage; return 2; }; build_hash="$2"; shift 2 ;;
            --unsigned-manifest-sha256) [ "$#" -ge 2 ] || { usage; return 2; }; unsigned_hash="$2"; shift 2 ;;
            --snapshot-sha256) [ "$#" -ge 2 ] || { usage; return 2; }; snapshot_hash="$2"; shift 2 ;;
            --minimal-run) [ "$#" -ge 2 ] || { usage; return 2; }; minimal_arg="$2"; shift 2 ;;
            --stock-run) [ "$#" -ge 2 ] || { usage; return 2; }; stock_arg="$2"; shift 2 ;;
            --marble-run) [ "$#" -ge 2 ] || { usage; return 2; }; marble_arg="$2"; shift 2 ;;
            *) usage; return 2 ;;
        esac
    done
    [ -n "$phase_a_arg" ] && [ -n "$output_arg" ] && [ -n "$version" ] &&
        [ -n "$build_hash" ] && [ -n "$unsigned_hash" ] && [ -n "$snapshot_hash" ] &&
        [ -n "$minimal_arg" ] && [ -n "$stock_arg" ] && [ -n "$marble_arg" ] || {
        usage
        return 2
    }
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || repository_die 'release version must be SemVer'
    for file in "$build_hash" "$unsigned_hash" "$snapshot_hash"; do
        repository_assert_sha256 "$file" 'finalization input SHA-256' 7<&-
    done
    repository_assert_loopback_only_network 7<&-
    for file in bash cmp cp find gpg install mktemp python3 realpath sha256sum sort stat tar zstd; do
        repository_require_command "$file" 7<&-
    done
    repository_canonical_existing phase_a "$phase_a_arg" 'Phase-A assets' 7<&-
    repository_canonical_existing minimal "$minimal_arg" 'Minimal QEMU run' 7<&-
    repository_canonical_existing stock "$stock_arg" 'Stock QEMU run' 7<&-
    repository_canonical_existing marble "$marble_arg" 'Marble QEMU run' 7<&-
    repository_canonical_output output "$output_arg" 'final release output' 7<&-
    for file in "$phase_a" "$minimal" "$stock" "$marble"; do
        repository_assert_paths_disjoint "$output" 'final release output' "$file" 'accepted input' 7<&-
    done
    assert_run_tree "$minimal"
    assert_run_tree "$stock"
    assert_run_tree "$marble"
    minimal_before="$(public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" \
        tree-identity --root "$minimal")"
    stock_before="$(public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" \
        tree-identity --root "$stock")"
    marble_before="$(public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" \
        tree-identity --root "$marble")"
    source_commit="${ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT:-}"
    source_tree="${ARCH_LINUX_OFFLINE_ACCEPTED_TREE:-}"
    source_tree_sha="${ARCH_LINUX_OFFLINE_ACCEPTED_TREE_SHA256:-}"
    [[ "$source_commit" =~ ^[a-f0-9]{40}$ ]] && [[ "$source_tree" =~ ^[a-f0-9]{40}$ ]] ||
        repository_die 'sealed finalization Git identity differs'
    repository_assert_sha256 "$source_tree_sha" 'sealed canonical source SHA-256' 7<&-
    "${script_dir}/verify-release-assets.sh" "$phase_a" --phase-a --sealed-offline-root \
        --release-version "$version" --source-commit "$source_commit" --source-tree "$source_tree" \
        --build-metadata-sha256 "$build_hash" --unsigned-manifest-sha256 "$unsigned_hash" 7<&-
    archive="arch-linux-repository-${version}.tar.zst"
    [ "$(repository_sha256 "$phase_a/$archive" 7<&-)" = "$snapshot_hash" ] ||
        repository_die 'accepted Phase-A snapshot SHA-256 differs'
    repository_assert_public_certificate "${script_dir}/trust/arch-linux.gpg" \
        "${script_dir}/trust/primary-fingerprint" "${script_dir}/trust/signing-subkey-fingerprint" 15552000 7<&-
    primary="$(repository_read_fingerprint "${script_dir}/trust/primary-fingerprint" 7<&-)"
    signing="$(repository_read_fingerprint "${script_dir}/trust/signing-subkey-fingerprint" 7<&-)"
    repository_assert_private_signing_subkey "$primary" "$signing" "$fd_guard"

    work="$(public_exec /usr/bin/mktemp -d \
        "${RUNNER_TEMP:-${output%/*}}/arch-linux-finalize.XXXXXXXX")"
    printf -v cleanup_command '/usr/bin/rm -rf -- %q 7<&-' "$work"
    # shellcheck disable=SC2064
    trap "$cleanup_command" EXIT
    stage="$work/assets"
    evidence_stage="$work/evidence"
    public_exec /usr/bin/mkdir -p -- "$stage" "$evidence_stage"
    public_exec /usr/bin/cp -a --no-preserve=ownership -- "$phase_a/." "$stage/"
    for file in "$phase_a"/*; do
        public_exec /usr/bin/cmp --silent -- "$file" "$stage/${file##*/}" ||
            repository_die 'Phase-A byte changed during finalization'
    done
    public_exec /usr/bin/cp -a --no-preserve=ownership -- "$minimal" \
        "$evidence_stage/minimal-ext4-systemdboot"
    public_exec /usr/bin/cp -a --no-preserve=ownership -- "$stock" \
        "$evidence_stage/stock-gnome-btrfs-luks2-plymouth-grub"
    public_exec /usr/bin/cp -a --no-preserve=ownership -- "$marble" \
        "$evidence_stage/marble-gnome-btrfs-luks2-plymouth-systemdboot"
    accepted_minimal="$evidence_stage/minimal-ext4-systemdboot"
    accepted_stock="$evidence_stage/stock-gnome-btrfs-luks2-plymouth-grub"
    accepted_marble="$evidence_stage/marble-gnome-btrfs-luks2-plymouth-systemdboot"
    assert_run_tree "$accepted_minimal"
    assert_run_tree "$accepted_stock"
    assert_run_tree "$accepted_marble"
    [ "$(public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" \
        tree-identity --root "$accepted_minimal")" = "$minimal_before" ] &&
        [ "$(public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" \
        tree-identity --root "$minimal")" = "$minimal_before" ] ||
        repository_die 'Minimal QEMU evidence changed during capture'
    [ "$(public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" \
        tree-identity --root "$accepted_stock")" = "$stock_before" ] &&
        [ "$(public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" \
        tree-identity --root "$stock")" = "$stock_before" ] ||
        repository_die 'Stock QEMU evidence changed during capture'
    [ "$(public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" \
        tree-identity --root "$accepted_marble")" = "$marble_before" ] &&
        [ "$(public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" \
        tree-identity --root "$marble")" = "$marble_before" ] ||
        repository_die 'Marble QEMU evidence changed during capture'
    public_exec /usr/bin/find "$evidence_stage" -type d -exec chmod 0755 -- {} +
    public_exec /usr/bin/find "$evidence_stage" -type f -exec chmod 0644 -- {} +
    IFS= read -r source_epoch <"${script_dir}/source-date-epoch"
    [[ "$source_epoch" =~ ^[0-9]+$ ]] || repository_die 'source-date-epoch is invalid'
    evidence_tar="$work/acceptance-evidence.tar"
    evidence_archive="$stage/arch-linux-acceptance-evidence-${version}.tar.zst"
    public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" create-archive \
        --evidence-root "$evidence_stage" --output-tar "$evidence_tar"
    public_exec /usr/bin/zstd --compress --quiet --threads=1 -19 --stdout -- "$evidence_tar" \
        >"$evidence_archive"
    public_exec /usr/bin/rm -- "$evidence_tar"
    public_exec /usr/bin/chmod 0644 -- "$evidence_archive"
    [ "$(public_exec /usr/bin/stat -Lc '%s' -- "$evidence_archive")" -le 524288000 ] ||
        repository_die 'compressed acceptance evidence exceeds 500 MiB'
    acceptance="$stage/arch-linux-acceptance-${version}.json"
    public_exec /usr/bin/python3 -I "${script_dir}/acceptance-manifest.py" create \
        --phase-a "$stage" --evidence-root "$evidence_stage" \
        --evidence-archive "$evidence_archive" --release-version "$version" \
        --source-commit "$source_commit" --source-tree "$source_tree" --source-tree-sha256 "$source_tree_sha" \
        --build-metadata-sha256 "$build_hash" --unsigned-manifest-sha256 "$unsigned_hash" \
        --snapshot-sha256 "$snapshot_hash" --output "$acceptance"
    sign_file "$signing" "$evidence_archive" "$evidence_archive.sig"
    sign_file "$signing" "$acceptance" "$acceptance.sig"
    "${script_dir}/verify-release-assets.sh" "$stage" --sealed-offline-root \
        --release-version "$version" --source-commit "$source_commit" --source-tree "$source_tree" \
        --source-tree-sha256 "$source_tree_sha" --build-metadata-sha256 "$build_hash" \
        --unsigned-manifest-sha256 "$unsigned_hash" 7<&-
    public_exec /usr/bin/python3 -I "$fd_guard" atomic-publish "$stage" "$output"
    trap - EXIT
    public_exec /usr/bin/rm -rf -- "$work"
    printf 'offline release finalization completed: %s\n' "$output"
}

main "$@"
