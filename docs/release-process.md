# Release process

A source candidate is not a release. Production signing and publication require separate explicit
authorization.

## 1. Source candidate

Freeze one exact tree and run:

```bash
bash tests/source-tests.sh
git diff --check
```

Record the tree identity, input hashes and exact statuses. A source failure stops acceptance. Results
from an earlier tree are invalid.

## 2. One canonical Arch build

In one clean Arch environment, create the required unsigned package set as an unprivileged temporary
builder:

```bash
repository/build-packages.sh "$ARTIFACT_DIR/unsigned"
repository/verify-unsigned-build.sh "$ARTIFACT_DIR/unsigned"
```

The monthly A+B comparison is advisory and is not a release gate.

## 3. Offline signing and repository assembly

Move the downloaded and independently verified unsigned closure to the authorized offline signing
environment. Record the exact canonical `BUILD-METADATA.json` and `UNSIGNED-SHA256SUMS` SHA-256
values before entering the signing boundary. Create a fresh canonical mode-`0700`
`/tmp/arch-linux-signing-home.XXXXXXXX`, populate it locally with only the accepted signing subkey
through the separate non-logging manual key-transfer procedure, stop its agent, and add the exact
mode-`0600` disposable marker documented in [repository tooling](../repository/README.md). Then run:

```bash
GNUPGHOME="$DISPOSABLE_GNUPGHOME" GPG_TTY="$(tty)" \
  repository/run-offline-signing.sh \
  --unsigned "$ARTIFACT_DIR/unsigned" \
  --installer "$REPO_ROOT/arch-linux-installer.sh" \
  --output "$ARTIFACT_DIR/signed" \
  --release-version "$VERSION" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
```

The operation signs packages and repository databases, creates the signed manifest and release
assets, and verifies the resulting public closure. It must not run in CI. The wrapper exposes only
loopback inside fresh user/PID/mount/network namespaces, accepts passphrases only through pinentry,
and deletes the marked disposable `GNUPGHOME` on success or failure.

## 4. Independent verification

From a clean verifier that has only source public trust:

```bash
repository/verify-signed-repository.sh \
  "$ARTIFACT_DIR/signed/repository" \
  --release-version "$VERSION" \
  --source-commit "$SOURCE_COMMIT" \
  --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
repository/verify-release-assets.sh \
  "$ARTIFACT_DIR/signed/assets" \
  --release-version "$VERSION" \
  --source-commit "$SOURCE_COMMIT" \
  --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
```

Any missing, extra, linked, unsigned, wrongly signed or checksum-mismatched file stops release.

## 5. Three QEMU scenarios

Use `qemu-system-x86_64` with KVM, a new qcow2 disk per scenario, independent OVMF VARS copies and
one exact independently verified `arch-linux-repository-${VERSION}.tar.zst` for all three runs:

1. Minimal TTY, ext4 and systemd-boot.
2. Stock GNOME, Btrfs, LUKS2 and GRUB.
3. Marble, Btrfs, LUKS2 and systemd-boot with the separate Marble GDM opt-in and Stock fallback.

Each scenario must exercise the real ISO, installer and produced repository. Product failure is not
retried. One infrastructure retry is allowed only with a recorded concrete cause.

## 6. GitHub Release and Pages

After all three staged QEMU scenarios pass, create annotated tag `$VERSION` on the frozen commit and
create a draft GitHub Release. Upload exactly the twelve already verified assets without changing
their names or bytes. Download every draft asset again, verify hashes, detached signatures,
installer version and tag-to-commit-to-tree, then run `.github/workflows/pages.yml` with the numeric
draft Release ID and the exact source/tree/snapshot/build hashes. The workflow performs authenticated
API readback and public-key-only verification before deploying Pages. Verify package/database
objects over public HTTPS, publish the Release without replacing any asset, then repeat
unauthenticated asset and Pages readback.

## 7. Public final VM test

Run one additional VM test against the public immutable Release and Pages URLs. This is public
readback acceptance, not a substitute for pre-release source/build/QEMU checks. Record release API,
asset and repository byte identities separately. The public payload contains no local product
installer, key, snapshot, CA or repository. It downloads the tagged `install.sh`, runs
`--verify-only`, downloads and executes only the identical verified Release installer, verifies the
public key, and installs/updates Marble through the exact Pages repository before reboot and a second
real GDM password login. The guest must also verify signed public `RELEASE-SHA256SUMS`, require the
downloaded signed repository archive to match the frozen snapshot SHA-256, verify its detached
signature, and require its embedded signed manifest/signature to be byte-identical to Pages. It then
checks the manifest's exact source/tree/installer/build identity, downloads all 23 manifest objects
over canonical Pages HTTPS, and verifies every object hash/size plus all package and canonical
database signatures. A passed Pages manifest without this Release-archive binding is not sufficient.

Each staged and public scenario retains a compact structured PASS or FAIL verdict, signed manifest
identity and per-package/database hashes. FAIL includes a non-zero exit status and exact failed
phase. Heavy run-owned VM inputs are deleted before bounded credential scanning; cumulative evidence
remains at most 500 MiB.

## 8. Updates after 1.0.0

Installer changes are new immutable SemVer releases (`1.0.1`, `1.0.2`, and later). Arch Linux
updates normally through `pacman -Syu`. Marble/profile changes increment the owning package's
`pkgrel` and are delivered through the signed Pages repository, so they do not require an installer
release. Source pins change only through a reviewed pull request.

The maintenance watcher may only create or update an advisory issue; monthly A+B is advisory and
never blocks release. No workflow automatically merges, releases, signs, rotates keys or changes a
fingerprint, checksum, source pin or accepted ISO. There is no `arch-os` synchronization. A signing
key changes only through a separately authorized manual rotation procedure.

## Required path summary

```text
SOURCE
  -> syntax/static/function/ShellCheck/secret checks
  -> one clean canonical Arch package build
  -> unsigned package and repository verification
  -> local offline signing
  -> three QEMU scenarios
  -> immutable GitHub Release and verified Pages deployment
  -> one public final VM test
```
