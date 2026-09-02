#!/usr/bin/env bash

# Fail-closed helpers shared by the small repository toolchain.

repository_die() {
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

repository_require_command() {
    command -v -- "$1" >/dev/null 2>&1 || repository_die "required command not found: $1"
}

repository_assert_regular_file() {
    local path="$1" label="${2:-file}"
    [ -f "$path" ] && [ ! -L "$path" ] && [ -s "$path" ] ||
        repository_die "$label is missing, empty, linked, or not regular: $path" || return
    [ "$(stat -Lc '%h' -- "$path")" = 1 ] ||
        repository_die "$label has more than one hard link: $path"
}

repository_assert_directory() {
    local path="$1" label="${2:-directory}"
    [ -d "$path" ] && [ ! -L "$path" ] ||
        repository_die "$label is missing, linked, or not a directory: $path"
}

repository_canonical_existing() {
    local destination="$1" path="$2" label="${3:-path}" value
    [[ "$destination" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
        repository_die 'invalid destination variable for canonical path' || return
    repository_require_command realpath || return
    value="$(realpath -e -- "$path")" || repository_die "cannot resolve $label: $path" || return
    [ "$value" != / ] || repository_die "$label may not be filesystem root" || return
    printf -v "$destination" '%s' "$value"
}

repository_canonical_output() {
    local destination="$1" path="$2" label="${3:-output}" parent value
    [[ "$destination" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
        repository_die 'invalid destination variable for canonical output' || return
    [ ! -e "$path" ] && [ ! -L "$path" ] ||
        repository_die "$label already exists: $path" || return
    parent="$(dirname -- "$path")"
    mkdir -p -- "$parent"
    parent="$(realpath -e -- "$parent")" || repository_die "cannot resolve $label parent" || return
    value="${parent}/$(basename -- "$path")"
    [ "$value" != / ] || repository_die "$label may not be filesystem root" || return
    printf -v "$destination" '%s' "$value"
}

repository_assert_paths_disjoint() {
    local first="$1" first_label="$2" second="$3" second_label="$4"
    case "${first}/" in "${second}/"*) repository_die "$first_label overlaps $second_label"; return ;; esac
    case "${second}/" in "${first}/"*) repository_die "$second_label overlaps $first_label"; return ;; esac
}

repository_read_package_set() {
    local path="$1" line seen=' '
    repository_assert_regular_file "$path" 'package set' || return
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[a-z0-9][a-z0-9+._-]*$ ]] ||
            repository_die "invalid package-set entry: $line" || return
        case "$seen" in *" $line "*) repository_die "duplicate package-set entry: $line"; return ;; esac
        seen+="$line "
        printf '%s\n' "$line"
    done <"$path"
}

repository_sha256() {
    sha256sum --binary -- "$1" | awk '{print $1}'
}

repository_assert_sha256() {
    local value="$1" label="${2:-SHA-256}"
    [[ "$value" =~ ^[a-f0-9]{64}$ ]] || repository_die "$label is not a lowercase SHA-256"
}

repository_read_source_identity() {
    local commit_destination="$1" tree_destination="$2" requested_root="$3"
    local root git_root commit tree status
    [[ "$commit_destination" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] &&
        [[ "$tree_destination" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
        repository_die 'invalid destination variable for source identity' || return
    repository_require_command git || return
    repository_canonical_existing root "$requested_root" 'source root' || return
    git_root="$(git -c safe.directory="$root" -C "$root" rev-parse --show-toplevel 2>/dev/null)" ||
        repository_die 'source root has no resolved Git work tree' || return
    git_root="$(realpath -e -- "$git_root")" || repository_die 'cannot resolve Git work tree' || return
    [ "$git_root" = "$root" ] || repository_die 'source root differs from Git work tree' || return
    commit="$(git -c safe.directory="$root" -C "$root" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" ||
        repository_die 'source root has no frozen commit' || return
    tree="$(git -c safe.directory="$root" -C "$root" rev-parse --verify 'HEAD^{tree}' 2>/dev/null)" ||
        repository_die 'source root has no frozen tree' || return
    [[ "$commit" =~ ^[a-f0-9]{40}$ ]] && [[ "$tree" =~ ^[a-f0-9]{40}$ ]] ||
        repository_die 'source Git identity is malformed' || return
    status="$(git -c safe.directory="$root" -C "$root" status --porcelain=v1 --untracked-files=all)" ||
        repository_die 'cannot inspect source status' || return
    [ -z "$status" ] || repository_die 'source work tree is not clean' || return
    printf -v "$commit_destination" '%s' "$commit"
    printf -v "$tree_destination" '%s' "$tree"
}

repository_assert_source_identity() {
    local root="$1" expected_commit="$2" expected_tree="$3" actual_commit actual_tree
    [[ "$expected_commit" =~ ^[a-f0-9]{40}$ ]] ||
        repository_die 'expected source commit is malformed' || return
    [[ "$expected_tree" =~ ^[a-f0-9]{40}$ ]] ||
        repository_die 'expected source tree is malformed' || return
    repository_read_source_identity actual_commit actual_tree "$root" || return
    [ "$actual_commit" = "$expected_commit" ] || repository_die 'source commit differs' || return
    [ "$actual_tree" = "$expected_tree" ] || repository_die 'source tree differs'
}

repository_read_fingerprint() {
    local path="$1" value
    repository_assert_regular_file "$path" 'fingerprint file' || return
    [ "$(wc -l <"$path")" -eq 1 ] ||
        repository_die "fingerprint file must contain one line: $path" || return
    IFS= read -r value <"$path"
    [[ "$value" =~ ^[A-F0-9]{40}$ ]] || repository_die "invalid fingerprint: $path" || return
    printf '%s\n' "$value"
}

repository_assert_public_certificate() {
    local certificate="$1" primary_file="$2" signing_file="$3" minimum_remaining="${4:-0}"
    local primary signing metadata packets home pub_count sub_count uid_count uat_count fpr_count
    local actual_primary actual_signing primary_algorithm signing_algorithm
    local primary_validity signing_validity uid_validity primary_capabilities signing_capabilities
    local signing_expires now
    local command_name
    for command_name in awk date gpg grep mktemp tr; do
        repository_require_command "$command_name" || return
    done
    repository_assert_regular_file "$certificate" 'public certificate' || return
    primary="$(repository_read_fingerprint "$primary_file")" || return
    signing="$(repository_read_fingerprint "$signing_file")" || return
    [ "$primary" != "$signing" ] || repository_die 'primary and signing fingerprints must differ' || return

    home="$(mktemp -d "${RUNNER_TEMP:-/tmp}/arch-linux-gpg.XXXXXXXX")"
    chmod 0700 -- "$home"
    metadata="$(GNUPGHOME="$home" gpg --batch --no-options --with-colons \
        --with-subkey-fingerprint --show-keys -- "$certificate" 2>/dev/null)" || {
        rm -rf -- "$home"
        repository_die 'public certificate cannot be parsed'
        return
    }
    packets="$(GNUPGHOME="$home" gpg --batch --no-options --list-packets -- \
        "$certificate" 2>/dev/null)" || {
        rm -rf -- "$home"
        repository_die 'public certificate packets cannot be inspected'
        return
    }
    rm -rf -- "$home"

    if grep -Eq '^:(secret key packet|secret sub key packet):' <<<"$packets"; then
        repository_die 'certificate contains OpenPGP secret packets'
        return
    fi

    pub_count="$(awk -F: '$1=="pub"{n++} END{print n+0}' <<<"$metadata")"
    sub_count="$(awk -F: '$1=="sub"{n++} END{print n+0}' <<<"$metadata")"
    uid_count="$(awk -F: '$1=="uid"{n++} END{print n+0}' <<<"$metadata")"
    uat_count="$(awk -F: '$1=="uat"{n++} END{print n+0}' <<<"$metadata")"
    fpr_count="$(awk -F: '$1=="fpr"{n++} END{print n+0}' <<<"$metadata")"
    [ "$pub_count" -eq 1 ] && [ "$sub_count" -eq 1 ] && [ "$uid_count" -eq 1 ] && \
        [ "$uat_count" -eq 0 ] && [ "$fpr_count" -eq 2 ] ||
        repository_die 'certificate must contain one primary, one valid text UID, no UAT and one subkey only' || return

    actual_primary="$(awk -F: '$1=="fpr"{print toupper($10); exit}' <<<"$metadata")"
    actual_signing="$(awk -F: '$1=="sub"{want=1; next} want && $1=="fpr"{print toupper($10); exit}' \
        <<<"$metadata")"
    [ "$actual_primary" = "$primary" ] || repository_die 'certificate primary fingerprint differs' || return
    [ "$actual_signing" = "$signing" ] || repository_die 'certificate signing-subkey fingerprint differs' || return

    primary_algorithm="$(awk -F: '$1=="pub"{print $4; exit}' <<<"$metadata")"
    signing_algorithm="$(awk -F: '$1=="sub"{print $4; exit}' <<<"$metadata")"
    [ "$primary_algorithm" = 22 ] && [ "$signing_algorithm" = 22 ] ||
        repository_die 'certificate primary and signing subkey must use Ed25519' || return

    primary_capabilities="$(awk -F: '$1=="pub"{print $12; exit}' <<<"$metadata" | tr -d '[:upper:]')"
    signing_capabilities="$(awk -F: '$1=="sub"{print $12; exit}' <<<"$metadata" | tr -d '[:upper:]')"
    [ "$primary_capabilities" = c ] ||
        repository_die 'certificate primary key must be certification-only' || return
    [ "$signing_capabilities" = s ] ||
        repository_die 'certificate subkey must be signing-only' || return

    primary_validity="$(awk -F: '$1=="pub"{print $2; exit}' <<<"$metadata")"
    signing_validity="$(awk -F: '$1=="sub"{print $2; exit}' <<<"$metadata")"
    uid_validity="$(awk -F: '$1=="uid"{print $2; exit}' <<<"$metadata")"
    case "$primary_validity$signing_validity$uid_validity" in
        *r*|*e*|*d*|*i*|*n*) repository_die 'certificate contains a revoked, expired, disabled or invalid key or UID'; return ;;
    esac

    signing_expires="$(awk -F: '$1=="sub"{print $7; exit}' <<<"$metadata")"
    [[ "$signing_expires" =~ ^[0-9]+$ ]] ||
        repository_die 'signing subkey must have a finite expiration time' || return
    [[ "$minimum_remaining" =~ ^[0-9]+$ ]] ||
        repository_die 'minimum signing lifetime is invalid' || return
    now="$(date +%s)"
    [[ "$now" =~ ^[0-9]+$ ]] || repository_die 'invalid current-time input for certificate check' || return
    [ "$signing_expires" -gt "$now" ] || repository_die 'signing subkey is expired' || return
    [ "$((signing_expires - now))" -ge "$minimum_remaining" ] ||
        repository_die 'signing subkey lifetime is below the required minimum' || return
}

repository_assert_private_signing_subkey() {
    local expected_primary="$1" expected_signing="$2" guard_path="$3" listing shape
    repository_assert_regular_file "$guard_path" 'offline signing descriptor guard' || return
    listing="$(/usr/bin/python3 -I "$guard_path" exec-private-gpg /usr/bin/gpg \
        --batch --no-options --no-autostart --with-colons --with-subkey-fingerprint \
        --list-secret-keys -- "${expected_signing}!" 2>/dev/null)" ||
        repository_die 'required private signing subkey is unavailable' || return
    shape="$(awk -F: '
        $1=="sec" {pc++; pa=$15; wanted="p"; next}
        $1=="ssb" {sc++; sa=$15; cap=$12; gsub(/[A-Z]/,"",cap); wanted="s"; next}
        wanted!="" && $1=="fpr" {if(wanted=="p") pf=toupper($10); else sf=toupper($10); wanted=""}
        END {printf "%d|%s|%s|%d|%s|%s|%s",pc+0,pf,pa,sc+0,sf,sa,cap}
    ' <<<"$listing")"
    [ "$shape" = "1|${expected_primary}|#|1|${expected_signing}|+|s" ] ||
        repository_die 'signer must expose one unavailable certification primary and one available signing-only subkey'
}

repository_verify_signature() {
    local keyring="$1" signature="$2" payload="$3" expected_signing="$4" expected_primary="$5"
    local status valid signer primary
    repository_require_command gpgv || return
    repository_assert_regular_file "$keyring" 'verification keyring' || return
    repository_assert_regular_file "$signature" 'detached signature' || return
    repository_assert_regular_file "$payload" 'signed payload' || return
    status="$(gpgv --status-fd 1 --keyring "$keyring" -- "$signature" "$payload" 2>/dev/null)" || return 1
    valid="$(awk '$1=="[GNUPG:]" && $2=="VALIDSIG"{print; n++} END{if(n!=1) exit 1}' \
        <<<"$status")" || return 1
    signer="$(awk '{print toupper($3)}' <<<"$valid")"
    primary="$(awk '{print toupper($12)}' <<<"$valid")"
    [ "$signer" = "$expected_signing" ] && [ "$primary" = "$expected_primary" ]
}

repository_assert_loopback_only_network() {
    local view="${1:-/proc/self/net/dev}" interfaces
    [ -f "$view" ] && [ ! -L "$view" ] || repository_die "unsafe network view: $view" || return
    interfaces="$(awk -F: 'NR>2 {gsub(/[[:space:]]/,"",$1); if($1!="") print $1}' "$view" | LC_ALL=C sort)"
    [ "$interfaces" = lo ] ||
        repository_die 'offline signing requires a network namespace containing only loopback'
}

repository_assert_clean_public_tree() {
    local root="$1" unexpected
    repository_assert_directory "$root" 'public tree' || return
    unexpected="$(find "$root" -mindepth 1 \( -type l -o ! -type f ! -type d \) -print -quit)"
    [ -z "$unexpected" ] ||
        repository_die "public tree contains a link or special object: $unexpected" || return
    unexpected="$(find "$root" -type f -links +1 -print -quit)"
    [ -z "$unexpected" ] || repository_die "public tree contains a hard-linked file: $unexpected"
}
