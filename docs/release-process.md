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
  "$ARTIFACT_DIR/snapshot/repository" \
  --release-version "$VERSION" \
  --source-commit "$SOURCE_COMMIT" \
  --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
repository/verify-release-assets.sh \
  "$ARTIFACT_DIR/snapshot/assets" --phase-a \
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

For every installed `firstboot` and `postreboot`, launch QEMU paused with `-S`, bind the direct
framebuffer recorder to the exact QEMU PID/start identity and QMP peer, require its `READY` ledger
record with QMP `prelaunch`/not-running before `cont`, and record the bounded boot section through
the verified visual state. Start a distinct shutdown section immediately before each transition;
require `READY` and `shutdown-armed` before scheduling it, then record until that exact PID exits. Minimal
must complete phase-specific `qga_verify` and framebuffer prerequisites before its allowlisted
non-secret no-Enter challenge. Ctrl+Alt+F1 is prohibited. The ledger must prove strict
pre-challenge/challenge/post-challenge chronology and a non-zero framebuffer delta in both phases.

Treat the automated scenario result as provisional. An independent reviewer must inspect the
ordered contact sheets and full-resolution frames (reconstructing uncertain manifest-bound raw
frames into a separate private directory before finalization) and issue a receipt bound to the exact
source commit/tree, run ID and frame-evidence manifest. The manifest binds every ledger,
contact sheet, temporary raw object and selected frame by hash, plus the fixed sheet geometry; it
does not contain per-cell records. OCR and screenshot count are not proof. Remove
unselected raw frames only after review; retain the receipt, compact manifest/ledgers/contact sheets
and two to four selected frames, and keep cumulative evidence at or below 500 MiB. No staged or
public QEMU PASS exists from the automated result alone.

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
