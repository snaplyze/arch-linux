# Release process

A source candidate is not a release. Production signing and publication require separate explicit
authorization.

## 1. Source candidate

Perform local review, source changes, tests, commits and release-host acceptance from the same
canonical checkout. Switch pull-request branches in place; do not create local per-cycle worktrees,
sibling clones or copied source repositories. Generated build, signing, VM and evidence data remains
outside the source tree. Ephemeral CI, package-build, signing, test and VM isolation remains
mandatory and does not become development source.

Validate the clean source candidate before freezing its exact identity:

```bash
bash tests/source-tests.sh
git diff --check
```

Record the tree identity, input hashes and exact statuses, then freeze only after all required
source gates pass. A source failure stops acceptance of that candidate. Results from an earlier
tree are invalid for a corrected candidate.

If a defect is found, diagnose it, correct the source and add a regression test in the same
canonical checkout. Repeat affected checks, build/sign the corrected inputs and run the applicable
VM scenarios. There is no artificial cycle or attempt limit. Keep old results associated with their
actual inputs; never transfer a PASS or replace published bytes or tags. A diagnostic-tool problem
is distinct from a broken installed system.

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
values before entering the signing boundary. Follow the root hash-pinned sealer and dedicated
`arch-linux-signing` account procedure in [repository tooling](../repository/README.md). Supply the
canonical private-home and passphrase paths only as the launcher's two-line FIFO input; never place
either in argv, environment, logs or evidence. Invoke the generated static launcher in `snapshot`
mode with the canonical build arguments. The linked runbook is mandatory: it contains the exact
five-argument sealer invocation, account policy and ownership/mode preconditions. In particular,
persistent private bytes remain encrypted only in the one authorized external recovery directory.
Routine signing decrypts/imports only the signing-only export into one-use tmpfs objects inside the
same no-network operation, and destroys them afterward. The accepted unsigned/QEMU inputs are
root-owned readable copies (never their native mode-`0700` run roots), while the missing
snapshot/final output names share a separate signing-owned mode-`0700` parent.

```bash
set +x
printf '%s\n%s\n' "$PRIVATE_HOME" "$PASSPHRASE_FILE" | \
  /usr/bin/env -i "$SEALED_ROOT/repository/offline-signing-launcher" snapshot \
    --unsigned "$ACCEPTED_UNSIGNED" \
  --installer "$SEALED_ROOT/arch-linux-installer.sh" \
    --output "$SNAPSHOT_OUTPUT" \
  --release-version "$VERSION" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
```

The launcher is entered as host root, validates the unique locked signing account, then drops all
root identity before it reads the FIFO pathnames. The operation emits `$SNAPSHOT_OUTPUT/assets`
with exact 14 Phase-A assets and `$SNAPSHOT_OUTPUT/repository` with the signed Pages tree. The
Phase-A set is the former 12 files plus byte-identical build metadata
and unsigned manifest. Signed `RELEASE-SHA256SUMS` covers the exact 12 non-self files. The launcher
retains private authority only through FDs 6/7, uses capability FD 8 and lock FD 9, exposes loopback
only inside fresh user/PID/mount/network namespaces and removes every private agent/socket on exit.

## 4. Independent verification

From a clean verifier that has only source public trust:

```bash
repository/verify-signed-repository.sh \
  "$SNAPSHOT_OUTPUT/repository" \
  --release-version "$VERSION" \
  --source-commit "$SOURCE_COMMIT" \
  --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
repository/verify-release-assets.sh \
  "$SNAPSHOT_OUTPUT/assets" --phase-a \
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
3. Marble, Btrfs, LUKS2 and systemd-boot with the separate Marble GDM opt-in.

Each scenario exercises the real ISO, installer and produced repository. Verify installation,
boot and networking, selected storage/bootloader/encryption, the expected desktop and packages,
updates, reboot, zero failed units, clean shutdown and `qemu-img check`. For GNOME, perform GDM
password login, check Wayland, lock/unlock and repeat login after reboot. Check dual boot and any
product options not covered by these three cases separately.

Use the runner's functional PASS/FAIL directly. Ordinary screenshots are optional diagnostics,
not a separate certification step. Remove owned temporary VM resources and retain compact logs
and results. Investigate failures, correct the cause and repeat affected checks; do not loop an
unchanged error or weaken real disk/signature/secret protections.

## 6. GitHub Release and Pages

After all three staged QEMU scenarios pass, invoke the sealed launcher in `finalize` mode. It must
copy all 14 Phase-A files byte-for-byte and add the signed acceptance JSON and signed compressed
evidence archive. The JSON binds the exact Phase-A map/aggregate/manifest, commit/tree/canonical
source hash, build/snapshot inputs, three PASS verdicts, evidence at most 500 MiB and `deferred=[]`.

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

Then create annotated tag `$VERSION` on the frozen commit and create a draft GitHub Release. Upload
exactly the eighteen already verified assets without changing
their names or bytes. Download every draft asset again, verify hashes, detached signatures,
installer version and tag-to-commit-to-tree, then run `.github/workflows/pages.yml` with the numeric
draft Release ID and the exact source/tree/canonical-source/snapshot/build hashes. The workflow performs authenticated
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
Use the explicit [package-only Pages route](../repository/README.md#package-only-updates), with a
new package tag and verified offline-signed snapshot. This is not a new installer release.

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
