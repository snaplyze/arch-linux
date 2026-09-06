# Repository tooling

This directory implements a small fail-closed pipeline for the signed `[arch-linux]` package
repository. It deliberately separates unsigned building, offline signing and public verification.

## Files

- `package-set`: exact ordered package allowlist.
- `source-date-epoch`: canonical build/archive timestamp.
- `trust/`: public certificate and exact fingerprints; no secret packets.
- `verify-package-metadata.py`: source metadata checks and strict inspection of real package payloads.
- `build-packages.sh`: one clean unprivileged Arch build.
- `verify-unsigned-build.sh`: exact unsigned artifact closure and package metadata.
- `compare-package-builds.sh`: advisory A+B byte comparison.
- `seal-offline-signing-code.py`: root-only exact-tree sealer and static-launcher builder.
- `offline-signing-launcher.c`: sole production signing entry, compiled into the sealed closure.
- `run-offline-signing.sh` and `offline-signing-namespace.sh`: descriptor and full-namespace boundary.
- `offline-sign-release.sh`: exact-14 Phase-A snapshot signer.
- `offline-finalize-release.sh`: byte-preserving exact-18 acceptance finalizer.
- `acceptance-manifest.py`: canonical three-QEMU PASS and evidence binding.
- `snapshot-manifest.py`: canonical flat signed manifest.
- `verify-signed-repository.sh`: exact package/database/signature verification.
- `verify-release-assets.sh`: exact public release-asset verification.
- `safe-extract-snapshot.py`: bounded extraction without traversal, links or special objects.

## Package metadata

```bash
python3 repository/verify-package-metadata.py
while IFS= read -r package; do
  repository/validate-package-sources.sh --regenerate "packages/$package"
done < repository/package-set
```

The verifier requires all and only the packages in `package-set`, exact committed `.SRCINFO`,
immutable source identities, matching local source hashes, explicit project dependency edges and a
separate Marble GDM package. It rejects `sudo`, root `makepkg`, mutable source URLs and unexpected
source files.

## Build and verify unsigned packages

Run as an unprivileged user in a clean Arch environment:

```bash
repository/build-packages.sh "$ARTIFACT_DIR/unsigned"
repository/verify-unsigned-build.sh "$ARTIFACT_DIR/unsigned"
```

The build output contains six package files, `metadata/*.SRCINFO`, `UNSIGNED-SHA256SUMS` and
schema-2 `BUILD-METADATA.json`. The two manifests bind the exact source commit/tree, installer,
package set, source epoch, metadata and package bytes. Every real package archive is checked for its
exact payload, ownership, modes, dependencies, hooks, licenses and safe internal links. The output
contains no signatures, private trust material or unrelated directories.

The advisory comparison is:

```bash
repository/compare-package-builds.sh "$ARTIFACT_DIR/build-a" "$ARTIFACT_DIR/build-b"
```

## Offline signing

Run only after separate authorization and outside CI. Independently calculate the accepted commit,
tree and canonical mode/byte SHA-256. As host root, copy `seal-offline-signing-code.py` by its
independently recorded hash into a fresh root-private bootstrap directory, mode `0500`, and invoke
that copy through `env -i` and stdin `/dev/null`. It verifies the locked/nologin/no-home
`arch-linux-signing` account, captures the exact source, and builds a root-owned read-only closure
containing a fresh static PIE launcher without `PT_INTERP`.

Create the dedicated account once, only if it is absent. Do not repurpose an existing UID or group:

```bash
/usr/sbin/groupadd --system arch-linux-signing
/usr/sbin/useradd --system --gid arch-linux-signing --home-dir /nonexistent \
  --shell /usr/sbin/nologin --no-create-home arch-linux-signing
/usr/sbin/usermod --lock arch-linux-signing
```

If either name already exists, stop and let the sealer validate it rather than changing it. The
account must have one unique nonzero UID/GID, no supplementary groups, `/nonexistent`, nologin, a
locked shadow entry, and no running process. Persistent private material remains only encrypted in
the authorized external recovery directory; never sign directly from that directory and do not
change its mount ownership. Inside one root-controlled, no-network operation, follow that recovery
set's own `README.md` to verify/decrypt its exact archive into a fresh `tmpfs` directory. Import only
the public certificate and `signing-only-secret.asc` into a one-use GNUPGHOME owned by the signing
UID/GID at mode `0700`, and copy `key-passphrase` only to a one-use, nonempty, single-link file with
that ownership and mode `0600`. These are ephemeral signing authorities, not additional persistent
recovery copies. Keep their canonical paths in unexported shell variables with tracing disabled,
kill any preparation agent, require the signing UID to be quiescent, and destroy the exact tmpfs
work directory immediately after signing. Never import the full certification primary for routine
release signing.

The sealer has exactly five positional arguments after its pathname. This is the complete bootstrap
shape; `EXPECTED_SEALER_SHA256` and all accepted source identities must already have been recorded by
independent source review:

```bash
set +x
test -z "$(git -C "$SOURCE_ROOT" status --porcelain=v1 --untracked-files=all)"
test -z "$(git -C "$SOURCE_ROOT" clean -ndX)"
test "$(git -C "$SOURCE_ROOT" rev-parse HEAD)" = "$SOURCE_COMMIT"
test "$(git -C "$SOURCE_ROOT" rev-parse 'HEAD^{tree}')" = "$SOURCE_TREE"
test "$(sha256sum --binary -- "$SOURCE_ROOT/repository/seal-offline-signing-code.py" | awk '{print $1}')" = \
  "$EXPECTED_SEALER_SHA256"

BOOTSTRAP_DIR="$(mktemp -d /root/arch-linux-sealer.XXXXXXXX)"
install -m0500 -o0 -g0 -- "$SOURCE_ROOT/repository/seal-offline-signing-code.py" \
  "$BOOTSTRAP_DIR/sealer"
test "$(sha256sum --binary -- "$BOOTSTRAP_DIR/sealer" | awk '{print $1}')" = \
  "$EXPECTED_SEALER_SHA256"

# SEALED_ROOT must be missing. Its existing parent and every ancestor are root-owned,
# non-writable by group/others, and searchable by arch-linux-signing.
/usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
  /usr/bin/python3 -I "$BOOTSTRAP_DIR/sealer" \
  "$SOURCE_ROOT" "$SOURCE_COMMIT" "$SOURCE_TREE" "$SOURCE_TREE_SHA256" "$SEALED_ROOT" \
  </dev/null
```

The launcher drops privileges before parsing its signer arguments. Therefore stage the already
verified unsigned closure—and later each finalized QEMU run—once into a separate fresh accepted-input
root whose ancestors are searchable by the signing UID. Accepted directories are root-owned mode
`0755`; accepted files are root-owned mode `0644`, single-link and non-writable by the signer. Reject
links/special objects and compare the copied identities to the source before use. The exact QEMU
destination basenames remain `minimal-ext4-systemdboot`,
`stock-gnome-btrfs-luks2-plymouth-grub`, and
`marble-gnome-btrfs-luks2-plymouth-systemdboot`; a native mode-`0700` run directory is never passed
directly to the launcher.

One root-owned accepted-input staging shape is:

```bash
# ACCEPTED_INPUT_ROOT must be a reviewed missing absolute path below safe root-owned ancestors.
test ! -e "$ACCEPTED_INPUT_ROOT" && test ! -L "$ACCEPTED_INPUT_ROOT"
install -d -m0755 -o0 -g0 -- "$ACCEPTED_INPUT_ROOT"
cp -a --no-preserve=ownership -- "$UNSIGNED_SOURCE" "$ACCEPTED_INPUT_ROOT/unsigned"
# Run the next three copies only after their functional result.json reports PASS.
cp -a --no-preserve=ownership -- "$MINIMAL_RUN_SOURCE" \
  "$ACCEPTED_INPUT_ROOT/minimal-ext4-systemdboot"
cp -a --no-preserve=ownership -- "$STOCK_RUN_SOURCE" \
  "$ACCEPTED_INPUT_ROOT/stock-gnome-btrfs-luks2-plymouth-grub"
cp -a --no-preserve=ownership -- "$MARBLE_RUN_SOURCE" \
  "$ACCEPTED_INPUT_ROOT/marble-gnome-btrfs-luks2-plymouth-systemdboot"
test -z "$(find "$ACCEPTED_INPUT_ROOT" -mindepth 1 \
  \( -type l -o \( ! -type f ! -type d \) \) -print -quit)"
test -z "$(find "$ACCEPTED_INPUT_ROOT" -type f ! -links 1 -print -quit)"
find "$ACCEPTED_INPUT_ROOT" -type d -exec chmod 0755 -- {} +
find "$ACCEPTED_INPUT_ROOT" -type f -exec chmod 0644 -- {} +
ACCEPTED_UNSIGNED="$ACCEPTED_INPUT_ROOT/unsigned"
ACCEPTED_MINIMAL_RUN="$ACCEPTED_INPUT_ROOT/minimal-ext4-systemdboot"
ACCEPTED_STOCK_RUN="$ACCEPTED_INPUT_ROOT/stock-gnome-btrfs-luks2-plymouth-grub"
ACCEPTED_MARBLE_RUN="$ACCEPTED_INPUT_ROOT/marble-gnome-btrfs-luks2-plymouth-systemdboot"
```

For snapshot, omit the three QEMU copies because they do not exist yet. Before either launcher call,
re-run the public verifier appropriate to every accepted input, compare a sorted name/size/SHA-256
inventory to its independently accepted source, and then make no further input change.

Prepare a separate missing output name below an existing directory owned by
`arch-linux-signing:arch-linux-signing` at mode `0700`. Accepted inputs, sealed source, ephemeral
private home and output must be pairwise disjoint. Both `$SNAPSHOT_OUTPUT` and `$FINAL_OUTPUT` below
must be absent before invocation. Before copying, resolve every variable to a reviewed absolute path;
never use an empty value or a broad filesystem root as a destination.

Immediately before invocation, enter a root shell in a fresh network namespace, confirm it has no
IPv4/IPv6 route, prepare the tmpfs signing home as described above, and set
`PRIVATE_HOME` and `PASSPHRASE_FILE` to those ephemeral paths. A safe preparation follows this shape;
`RECOVERY_EXTRACTED` is the already validated exact eight-file tmpfs extraction produced by the
external recovery runbook:

```bash
# Run this as host root, then execute the remaining preparation and one launcher invocation
# inside the resulting shell.
/usr/bin/unshare --net --mount --propagation private --fork \
  /usr/bin/bash --noprofile --norc

set -Eeuo pipefail
set +x
umask 077
ulimit -c 0
test -z "$(/usr/bin/ip -4 route show)"
test -z "$(/usr/bin/ip -6 route show)"
SIGNING_UID="$(id -u arch-linux-signing)"
SIGNING_GID="$(id -g arch-linux-signing)"
SIGNING_WORK="$(mktemp -d /dev/shm/arch-linux-release-signing.XXXXXXXX)"
chmod 0711 -- "$SIGNING_WORK"
PRIVATE_HOME="$SIGNING_WORK/gnupg"
PASSPHRASE_FILE="$SIGNING_WORK/key-passphrase"
cleanup_signing_work() {
  status=$?
  trap - EXIT HUP INT TERM
  set +e
  if [[ "$SIGNING_WORK" =~ ^/dev/shm/arch-linux-release-signing\.[A-Za-z0-9]{8}$ ]] &&
      [ -d "$SIGNING_WORK" ] && [ ! -L "$SIGNING_WORK" ]; then
    setpriv --reuid="$SIGNING_UID" --regid="$SIGNING_GID" --clear-groups \
      env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin \
      gpgconf --homedir "$PRIVATE_HOME" --kill all >/dev/null 2>&1
    find "$SIGNING_WORK" -xdev -depth -delete
  else
    printf 'Refusing unsafe signing-work cleanup target\n' >&2
    status=1
  fi
  exit "$status"
}
trap cleanup_signing_work EXIT HUP INT TERM
install -d -m0700 -o "$SIGNING_UID" -g "$SIGNING_GID" -- "$PRIVATE_HOME"
install -m0600 -o "$SIGNING_UID" -g "$SIGNING_GID" -- \
  "$RECOVERY_EXTRACTED/key-passphrase" "$PASSPHRASE_FILE"
setpriv --reuid="$SIGNING_UID" --regid="$SIGNING_GID" --clear-groups \
  env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin \
  gpg --batch --no-options --homedir "$PRIVATE_HOME" --import \
  <"$RECOVERY_EXTRACTED/arch-linux.gpg"
setpriv --reuid="$SIGNING_UID" --regid="$SIGNING_GID" --clear-groups \
  env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin \
  gpg --batch --no-options --homedir "$PRIVATE_HOME" --import \
  <"$RECOVERY_EXTRACTED/signing-only-secret.asc"
setpriv --reuid="$SIGNING_UID" --regid="$SIGNING_GID" --clear-groups \
  env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin \
  gpgconf --homedir "$PRIVATE_HOME" --kill all
for attempt in {1..100}; do
  ! pgrep -u "$SIGNING_UID" >/dev/null 2>&1 && break
  sleep 0.05
done
! pgrep -u "$SIGNING_UID" >/dev/null 2>&1
```

Run that block and the launcher below inside the same network-disabled operation. On every exit,
kill the ephemeral agent again, verify that no process of the signing UID remains, then delete only
the exact `SIGNING_WORK` path after checking its `/dev/shm/arch-linux-release-signing.` prefix. Exit
the temporary network namespace after cleanup. Repeat this recovery-to-tmpfs procedure from scratch
for `finalize`; never retain the snapshot signing home or passphrase across the QEMU stage.

```bash
set +x
printf '%s\n%s\n' "$PRIVATE_HOME" "$PASSPHRASE_FILE" | \
  /usr/bin/env -i "$SEALED_ROOT/repository/offline-signing-launcher" snapshot \
    --unsigned "$ACCEPTED_UNSIGNED" \
    --installer "$SEALED_ROOT/arch-linux-installer.sh" \
    --output "$SNAPSHOT_OUTPUT" --release-version "$VERSION" \
    --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
    --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
```

Invoke the launcher as host root. It revalidates the exact unique locked account and then irreversibly
drops to that account before reading either private pathname. The sealed root and all ancestors must
be root-owned, non-writable and searchable by the signing account; keep the separate sealer bootstrap
directory mode `0700`. Do not substitute shell tracing,
argv, exported variables or chat for that two-line FIFO. The
launcher retains the home as FD 6, seals the passphrase in memfd 7, uses capability FD 8 and lock FD
9, and enters fresh user/network/PID/mount namespaces with private tmpfs agent sockets. Inner scripts
reject direct, sourced and CI use before private access. The signing subkey must be signing-only and
have at least 180 days remaining. `repo-add --include-sigs` receives no private authority.

After all three staged QEMU functional results report PASS, use the same launcher with
the complete nine-option finalizer contract. QEMU run paths are accepted read-only copies; the output
name is still missing below the same signing-owned mode-`0700` output parent:

```bash
set +x
printf '%s\n%s\n' "$PRIVATE_HOME" "$PASSPHRASE_FILE" | \
  /usr/bin/env -i "$SEALED_ROOT/repository/offline-signing-launcher" finalize \
    --phase-a "$SNAPSHOT_OUTPUT/assets" \
    --output "$FINAL_OUTPUT" \
    --release-version "$VERSION" \
    --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
    --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256" \
    --snapshot-sha256 "$SNAPSHOT_SHA256" \
    --minimal-run "$ACCEPTED_MINIMAL_RUN" \
    --stock-run "$ACCEPTED_STOCK_RUN" \
    --marble-run "$ACCEPTED_MARBLE_RUN"
```

It copies the 14 Phase-A bytes unchanged and adds the signed acceptance JSON and evidence archive,
producing exact 18. The acceptance consumer independently binds the tracked Arch ISO; each distinct
helper/config payload ISO; QEMU PID/start identities; completed functional assertions,
repository objects and runtime markers; clean shutdown, image check and process cleanup.
Screenshots are optional diagnostics, not a separate visual certification step.

`BUILD_METADATA_SHA256` and `UNSIGNED_MANIFEST_SHA256` always come from the independently accepted
canonical build, not from the signing operation.

## Public verification

```bash
repository/verify-signed-repository.sh "$SNAPSHOT_OUTPUT/repository" \
  --release-version "$VERSION" \
  --source-commit "$SOURCE_COMMIT" --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
repository/verify-release-assets.sh "$SNAPSHOT_OUTPUT/assets" --phase-a \
  --release-version "$VERSION" \
  --source-commit "$SOURCE_COMMIT" --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
repository/verify-release-assets.sh "$FINAL_OUTPUT" --finalized \
  --release-version "$VERSION" --source-commit "$SOURCE_COMMIT" --source-tree "$SOURCE_TREE" \
  --source-tree-sha256 "$SOURCE_TREE_SHA256" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
```

The repository verifier checks exact regular-file modes/link counts, certificate bytes/fingerprints,
manifest signature and closure, every package signature, database/files signatures and aliases, safe
database archive members and database package filename closure. The release verifier checks the
exact release asset set, hashes, signatures, installer version/source identity and safely extracted
repository snapshot.

## Pages

Pages deployment is public-key-only. `.github/workflows/pages.yml` receives the numeric draft
Release ID plus the exact frozen commit/tree/canonical hash and build/snapshot hashes. It reads back
exactly eighteen draft assets through the authenticated GitHub API, verifies their API digests, annotated tag,
checksums, signatures and full repository closure, then safely extracts and uploads the Pages
artifact. Production private material is never an Actions secret.

### Package-only updates

For a Marble/profile update, increment the owning package's `pkgrel` in a reviewed PR, regenerate
`.SRCINFO`, test the change and merge it. Build and verify that exact main commit, then use the same
offline `snapshot` signing operation. Do not change the installer version or its published assets.
Test package upgrade and the affected desktop behavior on an installed system.

Create a separate annotated `packages-YYYYMMDD.N` tag on that package source commit and a draft
package Release named exactly as the tag. Upload the 14 verified Phase-A files. These are a signed
package-update bundle; they do not certify or replace an installer release. Dispatch `pages.yml`
on main with `deployment_kind=packages`, `package_tag`, its numeric `release_id`, the existing
installer `release_version`, and the exact new source/build/snapshot hashes. The workflow requires
the installer release to be published already, rejects changes to `install.sh` or the installer
under that old version, and verifies all 14 files and package/database signatures before deployment.

After HTTPS readback and a successful installed-system `pacman -Syu`, publish the package Release
without replacing bytes. Explicitly exclude it from GitHub's Latest installer selection:
`gh release edit "$PACKAGE_TAG" --draft=false --latest=false`. Confirm afterward that the
repository's `/releases/latest` API still names the existing SemVer installer release, not the
`packages-YYYYMMDD.N` tag. The installer updater intentionally accepts only SemVer release tags;
a package-only release must not hide that installer from older clients. Do not rely on GitHub's
[automatic Latest selection](https://cli.github.com/manual/gh_release_create).
Future package updates use a new package tag. There is no automatic
signing, release or merge. The normal `deployment_kind=release` path still requires the finalized
18-file installer release with its three functional VM results.
