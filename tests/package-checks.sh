#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
verifier="$repo_root/repository/verify-package-metadata.py"

python3 "$repo_root/repository/verify-package-metadata.py"
bash "$repo_root/repository/assert-public-key.sh" \
    "$repo_root/repository/trust/arch-linux.gpg" \
    "$repo_root/repository/trust/primary-fingerprint" \
    "$repo_root/repository/trust/signing-subkey-fingerprint"
while IFS= read -r package || [ -n "$package" ]; do
    test -f "$repo_root/packages/$package/PKGBUILD"
    test -f "$repo_root/packages/$package/.SRCINFO"
done <"$repo_root/repository/package-set"

command -v zstd >/dev/null 2>&1 || {
    printf 'package checks failed: zstd is required for payload fixtures\n' >&2
    exit 1
}

fixture_root="$(mktemp -d "${RUNNER_TEMP:-/tmp}/arch-linux-package-checks.XXXXXXXX")"
cleanup() {
    rm -rf -- "$fixture_root"
}
trap cleanup EXIT HUP INT TERM

python3 -B - "$repo_root" "$fixture_root" <<'PY'
import io
import pathlib
import sys
import tarfile

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
profile = root / "packages" / "arch-linux-marble-profile"
keyring = root / "packages" / "arch-linux-keyring"
trust = root / "repository" / "trust"

profile_dependencies = [
    "arch-linux-keyring>=1.0.0",
    "arch-linux-marble-shell>=50.0.0",
    "arch-linux-colloid-gtk3>=20260808",
    "arch-linux-colloid-icons>=20260817",
    "bash",
    "coreutils",
    "dconf",
    "gnome-shell",
    "gnome-shell-extensions",
    "grep",
    "pacman",
]


def pkginfo(package, version, dependencies):
    lines = [
        f"pkgname = {package}",
        f"pkgbase = {package}",
        f"pkgver = {version}",
        "arch = any",
        "license = GPL-3.0-only",
    ]
    lines.extend(f"depend = {dependency}" for dependency in dependencies)
    return ("\n".join(lines) + "\n").encode()


def add_directory(archive, name):
    entry = tarfile.TarInfo(name)
    entry.type = tarfile.DIRTYPE
    entry.mode = 0o755
    entry.uid = 0
    entry.gid = 0
    entry.mtime = 0
    archive.addfile(entry)


def add_file(archive, name, data, mode=0o644, uid=0):
    entry = tarfile.TarInfo(name)
    entry.mode = mode
    entry.uid = uid
    entry.gid = 0
    entry.mtime = 0
    entry.size = len(data)
    archive.addfile(entry, io.BytesIO(data))


def add_link(archive, name, target):
    entry = tarfile.TarInfo(name)
    entry.type = tarfile.SYMTYPE
    entry.linkname = target
    entry.mode = 0o777
    entry.uid = 0
    entry.gid = 0
    entry.mtime = 0
    archive.addfile(entry)


def add_parents(archive, paths):
    directories = set()
    for name in paths:
        if name.startswith("../") or name.startswith("."):
            continue
        parent = pathlib.PurePosixPath(name).parent
        while parent != pathlib.PurePosixPath("."):
            directories.add(parent.as_posix())
            parent = parent.parent
    for name in sorted(directories, key=lambda value: (value.count("/"), value)):
        add_directory(archive, name)


def write_profile(name, mutation="positive"):
    dependencies = list(profile_dependencies)
    if mutation == "deps":
        dependencies[-1] = "curl"
    files = {
        ".PKGINFO": pkginfo("arch-linux-marble-profile", "1.0.0-1", dependencies),
        ".BUILDINFO": b"pkgname = arch-linux-marble-profile\n",
        ".MTREE": b"#mtree\n",
        ".INSTALL": (profile / "arch-linux-marble-profile.install").read_bytes(),
        "usr/lib/arch-linux-marble-profile/update-compatibility":
            (profile / "update-compatibility").read_bytes(),
        "usr/share/arch-linux-marble/supported-gnome-majors":
            (profile / "supported-gnome-majors").read_bytes(),
        "usr/share/libalpm/hooks/90-arch-linux-marble-profile.hook":
            (profile / "90-arch-linux-marble-profile.hook").read_bytes(),
        "usr/share/licenses/arch-linux-marble-profile/LICENSE-project":
            (profile / "LICENSE-project").read_bytes(),
    }
    if mutation == "hook":
        files["usr/share/libalpm/hooks/90-arch-linux-marble-profile.hook"] += b"# changed\n"
    if mutation == "license":
        files["usr/share/licenses/arch-linux-marble-profile/LICENSE-project"] += b"changed\n"
    if mutation == "path":
        files["../escape"] = b"unsafe\n"
    link_path = "usr/share/arch-linux-marble/supported-gnome-majors"
    if mutation == "link":
        del files[link_path]

    with tarfile.open(output / f"{name}.tar", "w", format=tarfile.PAX_FORMAT) as archive:
        add_parents(archive, files | ({link_path: b""} if mutation == "link" else {}))
        for path, data in sorted(files.items()):
            mode = 0o755 if path == "usr/lib/arch-linux-marble-profile/update-compatibility" else 0o644
            uid = 1000 if mutation == "owner" and path.endswith("LICENSE-project") else 0
            if mutation == "mode" and path.endswith("90-arch-linux-marble-profile.hook"):
                mode = 0o600
            add_file(archive, path, data, mode=mode, uid=uid)
        if mutation == "link":
            add_link(archive, link_path, "../../../../etc/passwd")


def write_keyring():
    files = {
        ".PKGINFO": pkginfo("arch-linux-keyring", "1.0.0-1", ["pacman"]),
        ".BUILDINFO": b"pkgname = arch-linux-keyring\n",
        ".MTREE": b"#mtree\n",
        ".INSTALL": (keyring / "arch-linux-keyring.install").read_bytes(),
        "usr/share/pacman/keyrings/arch-linux.gpg": (trust / "arch-linux.gpg").read_bytes(),
        "usr/share/arch-linux-keyring/primary-fingerprint":
            (trust / "primary-fingerprint").read_bytes(),
        "usr/share/arch-linux-keyring/signing-subkey-fingerprint":
            (trust / "signing-subkey-fingerprint").read_bytes(),
        "usr/share/licenses/arch-linux-keyring/LICENSE-project":
            (keyring / "LICENSE-project").read_bytes(),
    }
    with tarfile.open(output / "positive-keyring.tar", "w", format=tarfile.PAX_FORMAT) as archive:
        add_parents(archive, files)
        for path, data in sorted(files.items()):
            add_file(archive, path, data)


write_keyring()
write_profile("positive-profile")
for case in ("owner", "mode", "path", "deps", "hook", "license", "link"):
    write_profile(f"wrong-{case}", case)
PY

python3 -B - "$verifier" <<'PY'
import importlib.util
import tarfile
import sys

spec=importlib.util.spec_from_file_location('package_verifier',sys.argv[1])
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
name='usr/share/icons/Colloid-Dark/status/symbolic/network-wireless-signal-excellent-symbolic.svg'
target='usr/share/icons/Colloid-Dark/status/symbolic/nm-signal-100-symbolic.svg'

def regular(path):
    entry=tarfile.TarInfo(path); entry.type=tarfile.REGTYPE; entry.mode=0o644
    return entry

def symlink(path, link):
    entry=tarfile.TarInfo(path); entry.type=tarfile.SYMTYPE; entry.mode=0o777; entry.linkname=link
    return entry

positive={name:symlink(name,'nm-signal-100-symbolic.svg'),target:regular(target)}
if module.resolve_internal_regular_member(positive,name) is not positive[target]:
    raise SystemExit('Colloid internal symlink did not resolve to its package member')

def rejected(label,members):
    try:
        module.resolve_internal_regular_member(members,name)
    except SystemExit:
        return
    raise SystemExit(f'unsafe Colloid symlink fixture accepted: {label}')

rejected('escape',{name:symlink(name,'../../../../../../../../etc/passwd')})
rejected('missing',{name:symlink(name,'missing.svg')})
rejected('cycle',{
    name:symlink(name,'cycle.svg'),
    name.rsplit('/',1)[0]+'/cycle.svg':symlink(name.rsplit('/',1)[0]+'/cycle.svg',name.rsplit('/',1)[1]),
})
PY

for archive in "$fixture_root"/*.tar; do
    zstd -q -T1 -f -o "${archive%.tar}.pkg.tar.zst" -- "$archive"
done
cp -- "$fixture_root/positive-profile.tar" "$fixture_root/not-zstd.pkg.tar.zst"

if [ -n "${PACKAGE_FIXTURE_OUTPUT_DIR:-}" ]; then
    [ -d "$PACKAGE_FIXTURE_OUTPUT_DIR" ] && [ ! -L "$PACKAGE_FIXTURE_OUTPUT_DIR" ] || {
        printf 'package checks failed: PACKAGE_FIXTURE_OUTPUT_DIR is not a real directory\n' >&2
        exit 1
    }
    install -m0644 -- "$fixture_root/positive-keyring.pkg.tar.zst" \
        "$PACKAGE_FIXTURE_OUTPUT_DIR/arch-linux-keyring-1.0.0-1-any.pkg.tar.zst"
    install -m0644 -- "$fixture_root/positive-profile.pkg.tar.zst" \
        "$PACKAGE_FIXTURE_OUTPUT_DIR/arch-linux-marble-profile-1.0.0-1-any.pkg.tar.zst"
fi

python3 "$verifier" --verify-package \
    "$fixture_root/positive-keyring.pkg.tar.zst" arch-linux-keyring
python3 "$verifier" --verify-package \
    "$fixture_root/positive-profile.pkg.tar.zst" arch-linux-marble-profile

expect_package_rejection() {
    local label="$1" expected="$2" archive="$3" result
    if result="$(python3 "$verifier" --verify-package "$archive" arch-linux-marble-profile 2>&1)"; then
        printf 'package checks failed: negative fixture accepted: %s\n' "$label" >&2
        return 1
    fi
    grep -Fq -- "$expected" <<<"$result" || {
        printf 'package checks failed: %s hit the wrong rejection: %s\n' "$label" "$result" >&2
        return 1
    }
}

expect_package_rejection owner 'archive uid/gid differs from 0' \
    "$fixture_root/wrong-owner.pkg.tar.zst"
expect_package_rejection mode 'archive mode differs' \
    "$fixture_root/wrong-mode.pkg.tar.zst"
expect_package_rejection path 'unsafe archive path' \
    "$fixture_root/wrong-path.pkg.tar.zst"
expect_package_rejection dependencies '.PKGINFO dependencies differ' \
    "$fixture_root/wrong-deps.pkg.tar.zst"
expect_package_rejection hook 'payload bytes differ from reviewed source' \
    "$fixture_root/wrong-hook.pkg.tar.zst"
expect_package_rejection license 'payload bytes differ from reviewed source' \
    "$fixture_root/wrong-license.pkg.tar.zst"
expect_package_rejection link 'unsafe symlink target' \
    "$fixture_root/wrong-link.pkg.tar.zst"
expect_package_rejection compression 'not a Zstandard frame' \
    "$fixture_root/not-zstd.pkg.tar.zst"

if [ -n "${PACKAGE_ARTIFACT_DIR:-}" ]; then
    shopt -s nullglob
    while IFS= read -r package || [ -n "$package" ]; do
        artifacts=("$PACKAGE_ARTIFACT_DIR/${package}-"*.pkg.tar.zst)
        [ "${#artifacts[@]}" -eq 1 ] || {
            printf 'package checks failed: real artifact closure differs for %s\n' "$package" >&2
            exit 1
        }
        python3 "$verifier" --verify-package "${artifacts[0]}" "$package"
    done <"$repo_root/repository/package-set"
    shopt -u nullglob
    bash "$repo_root/repository/verify-unsigned-build.sh" "$PACKAGE_ARTIFACT_DIR"
fi
printf 'package checks passed\n'
