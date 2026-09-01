#!/usr/bin/env bash
set -euo pipefail
umask 077
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
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

for command_name in git gpg gpg-connect-agent gpgconf python3 sha256sum tar zstd; do
    command -v -- "$command_name" >/dev/null 2>&1 || {
        printf 'repository check failed: required command absent: %s\n' "$command_name" >&2
        exit 1
    }
done

signing_hash='0000000000000000000000000000000000000000000000000000000000000000'
unmarked_home="$(mktemp -d /tmp/arch-linux-signing-home.XXXXXXXX)"
chmod 0700 -- "$unmarked_home"
if GNUPGHOME="$unmarked_home" bash "$repo_root/repository/run-offline-signing.sh" \
    --build-metadata-sha256 "$signing_hash" \
    --unsigned-manifest-sha256 "$signing_hash" >/dev/null 2>&1; then
    printf 'repository check failed: unmarked disposable GNUPGHOME accepted\n' >&2
    exit 1
fi
[ -d "$unmarked_home" ] || {
    printf 'repository check failed: refused unmarked GNUPGHOME was deleted\n' >&2
    exit 1
}
rm -rf -- "$unmarked_home"

marked_home="$(mktemp -d /tmp/arch-linux-signing-home.XXXXXXXX)"
chmod 0700 -- "$marked_home"
printf '%s\n' 'arch-linux-offline-signing-disposable-v1' \
    >"$marked_home/.arch-linux-disposable-signing-home"
chmod 0600 -- "$marked_home/.arch-linux-disposable-signing-home"
GNUPGHOME="$marked_home" gpg-connect-agent --homedir "$marked_home" /bye >/dev/null 2>&1
if GNUPGHOME="$marked_home" bash "$repo_root/repository/run-offline-signing.sh" \
    --build-metadata-sha256 "$signing_hash" >/dev/null 2>&1; then
    printf 'repository check failed: incomplete signing digest authority accepted\n' >&2
    exit 1
fi
[ ! -e "$marked_home" ] && [ ! -L "$marked_home" ] || {
    printf 'repository check failed: marked disposable GNUPGHOME survived failure cleanup\n' >&2
    exit 1
}

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
    "$fixture_project/packages" "$fixture_packages"
PACKAGE_FIXTURE_OUTPUT_DIR="$fixture_packages" bash "$repo_root/tests/package-checks.sh" >/dev/null
cp -- "$repo_root/repository/lib/common.sh" "$fixture_project/repository/lib/common.sh"
printf '%s\n' arch-linux-keyring arch-linux-marble-profile >"$fixture_project/repository/package-set"
cp -- "$repo_root/repository/source-date-epoch" "$fixture_project/repository/source-date-epoch"
cp -- "$repo_root/repository/safe-extract-snapshot.py" "$fixture_project/repository/safe-extract-snapshot.py"
cp -- "$repo_root/repository/snapshot-manifest.py" "$fixture_project/repository/snapshot-manifest.py"
cp -- "$repo_root/repository/verify-release-assets.sh" "$fixture_project/repository/verify-release-assets.sh"
cp -- "$repo_root/repository/verify-signed-repository.sh" "$fixture_project/repository/verify-signed-repository.sh"
cp -- "$repo_root/repository/verify-unsigned-build.sh" "$fixture_project/repository/verify-unsigned-build.sh"
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
    "$fixture_project/repository/snapshot-manifest.py" \
    "$fixture_project/repository/verify-release-assets.sh" \
    "$fixture_project/repository/verify-signed-repository.sh" \
    "$fixture_project/repository/verify-unsigned-build.sh" \
    "$fixture_project/repository/verify-package-metadata.py"
chmod 0644 -- "$fixture_project/repository/package-set" "$fixture_project/repository/source-date-epoch"
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
    tar --sort=name --format=ustar --owner=0 --group=0 --numeric-owner --mtime='@0' -cf - repo |
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
    RUNNER_TEMP="$release_verify_temp" "$fixture_project/repository/verify-release-assets.sh" "$1" \
        --release-version 1.0.0 \
        --source-commit "$source_commit" \
        --source-tree "$source_tree" \
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

printf 'repository checks passed (schema-2 identity, exact release closure, signatures, and archives)\n'
