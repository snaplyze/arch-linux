# Release process

A source candidate is not a release. The configured `release.yml` pipeline has standing authority
to sign and publish one immutable release after a successful CI-verified merge to `main`; no other
workflow or operator gains that authority from this document.

## Release immutability

Before preparing a newer release, read the repository setting:

```bash
gh api repos/snaplyze/arch-linux/immutable-releases
```

It must report `enabled: true` before publication. If disabled, obtain explicit authorization
to enable **Settings → General → Releases → Enable release immutability**. This is a repository
setting, not permission to sign or publish. GitHub applies it only to future releases, so attach
and verify the complete asset set while the release is still a draft. After publication, verify
the release API's `immutable: true` alongside its hashes and signatures. See
[GitHub's setting documentation](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes).

The former `1.0.0` and `1.0.1` objects are retired under separate authorization. Their recorded
results remain historical evidence for their original commits and inputs; they do not establish an
available current release. The installer offers self-updates only from a release whose API reports
`immutable: true`. Release-pinned bootstrap verification and platform-enforced release immutability
are separate properties.

## Verified publication record

Release 1.0.4 has completed immutable publication, Pages verification and public VM acceptance.
The [validation record](validation.md#verified-release-104) links its exact source identities,
signed evidence and workflow. Older results below remain historical and do not validate a later
source candidate.

## Historical 1.0.1 evidence (retired)

The former `1.0.1` release was published on 2026-09-06 with `immutable: true`. Before retirement,
its annotated tag resolved to commit
`bdb42154f55dac5c0d7cddfc2f0f57d493024354`, tree
`bccfbbbdd0458909da8af3cddc75a21b671724bb`. Installer SHA-256 is
`a9bb35e6799599c9f22d4171860928799c060de9d4a4450c9be379579ced3318`;
repository snapshot SHA-256 is
`c16921d6019d2d86c9c1e8098015a9d87b3fbf4cc7e9d3a0c8d20d316cf15e09`.

The full clean-source and release-host checks passed. One
[canonical package build](https://github.com/snaplyze/arch-linux/actions/runs/34038725132)
and independent local verification preceded offline signing. Nine fresh staged QEMU/KVM
scenarios covered Minimal, Stock, Marble, the separate GDM opt-in, storage/bootloader choices
and Linux dual boot. All completed actual installed-system checks and owned-runtime cleanup;
this does not claim every possible combination or Windows acceptance.

All 18 draft and published assets passed hashes/signatures/version/tag readback. The
[verified Pages deployment](https://github.com/snaplyze/arch-linux/actions/runs/34044910971)
passed HTTPS readback of all 25 repository objects. Fresh public-only Marble/GDM run
`marble-20260906T162218Z-f716125e` passed real LUKS boot, password login, Wayland,
lock/unlock, update, reboot/relogin, package integrity, zero failed units and image cleanup.
A separate fresh public VM passed signed old-to-new six-package delivery through normal
`pacman -Syu` and the actual unmodified 1.0.0 installer's signed self-update, atomic replacement
and restart into 1.0.1. It stopped at setup, without starting a second disk installation.

The supplemental run used reviewed test-only harness commit
`dff1a72ee5beee0e3a03e67d7999fac49f6ef948`, tree
`b5959ceb86681c9b4dce6ad7f10d05ffd45ae095` (PR #34, QEMU exec-readiness correction),
separately bound to the unchanged released product above. Its run ID is
`marble-20260906T180030Z-7ff430e2`; the earlier failed supplemental attempts remain FAIL.

Historical compatibility runs and failed diagnostic attempts remain separate from this record. They
must never be relabelled as acceptance for `1.0.2` or a later release.

## 1. Source candidate

The release pipeline starts from the exact successful online `main` merge. It derives a deterministic
release child containing only allowlisted version changes, records
`repository/release-origin.json` (schema 1) with the origin main commit/tree, release version,
transform schema and package revisions, and reconstructs the child from the origin's complete
mode-and-byte tree. It tests, builds and signs that child; the origin main commit/tree and release
child commit/tree are both bound into provenance. A generated child never bypasses review of the
origin merge, and no result from an earlier tree is transferred to it.

The manual **Run workflow** action resumes an existing release for the current reviewed `main`
commit; it cannot start a fresh candidate. To retry preparation before a tag exists, rerun that
commit's CI push run and let its successful completion trigger the release workflow.

The executor verifies its own process group and cgroup before acknowledging entry. A child that
finishes before the parent can inspect `/proc` is accepted only after a successful Bash child wait,
the exact protected acknowledgement and normal cgroup cleanup. Missing acknowledgement, non-child
or failed waits, live wrong process groups and detached descendants still fail closed. The privileged
regression deliberately completes one real executor before capture; it uses no speed threshold.

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

Before the publication freeze, compare intended package filenames and hashes with published
Pages objects. Any changed archive needs a higher `pkgver` or `pkgrel`, including changes caused
only by regenerated build metadata. Unchanged dependency minimums do not waive this rule.
Update the owning package metadata/tests and build the complete accepted closure again; do not
overwrite existing filenames, splice older packages into a canonical build or relabel its provenance.
An unsigned maintenance-review build is not automatically ready for publication.

## 2. One canonical Arch build

In one clean Arch environment, create the required unsigned package set as an unprivileged temporary
builder:

```bash
repository/build-packages.sh "$ARTIFACT_DIR/unsigned"
repository/verify-unsigned-build.sh "$ARTIFACT_DIR/unsigned"
```

The monthly A+B comparison is advisory and is not a release gate.

Fresh Arch containers initialize their disposable pacman trust database with
`pacman-key --init` and `pacman-key --populate archlinux` before `pacman -Syu`.
Otherwise an `archlinux-keyring` upgrade can report a failed scriptlet even when pacman exits
successfully. This machine-local pacman key is not the project production signing key;
it is destroyed with the container. Package/database signature policies are not relaxed.

## 3. Authorized Actions signing and repository assembly

The release pipeline records the exact canonical `BUILD-METADATA.json` and `UNSIGNED-SHA256SUMS`
SHA-256 values before entering its signing boundary. Only the `snapshot` and `finalize` jobs use the
`release` Environment and receive `ARCH_LINUX_SIGNING_KEY` and
`ARCH_LINUX_SIGNING_PASSPHRASE`. The adapter imports only the signing-only subkey into a fresh
temporary no-network boundary, signs the accepted closure, and destroys that material when the job
exits. The certification primary and recovery material remain outside Actions. Build, readback,
QEMU, draft, Pages, publish, PR, CI, maintenance and public-readback jobs receive neither signing
secret.

The root hash-pinned sealer and dedicated `arch-linux-signing` account procedure in
[repository tooling](../repository/README.md) remains the host-local recovery boundary. Its static
launcher preserves the exact FD 6/7/8/9 contract and the 14/18 closures; it does not redefine the
authorized Actions adapter.

For host-local recovery only, invoke the retained launcher in `snapshot` mode with the canonical
build arguments:

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

Snapshot emits `$SNAPSHOT_OUTPUT/assets` with exact 14 Phase-A assets and
`$SNAPSHOT_OUTPUT/repository` with the signed Pages tree. The Phase-A set is the former 12 files plus
byte-identical build metadata and unsigned manifest. Signed `RELEASE-SHA256SUMS` covers the exact 12
non-self files. The same closure requirements apply to the host launcher and Actions adapter.

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

After all three staged QEMU scenarios pass, the authorized `finalize` job must copy all 14 Phase-A
files byte-for-byte and add the signed acceptance JSON and signed compressed evidence archive for
exact 18. The JSON binds the exact Phase-A map/aggregate/manifest, release child commit/tree and
canonical source hash, build/snapshot inputs, three PASS verdicts, evidence at most 500 MiB and
`deferred=[]`. The bound child contains `repository/release-origin.json`, which records the reviewed
main commit/tree; public verification reconstructs the child from that origin.

For host-local recovery only, invoke the retained launcher in `finalize` mode:

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

The pipeline creates an annotated tag `$VERSION` on the deterministic release child and a draft
GitHub Release. It uploads exactly the eighteen verified assets without changing their names or
bytes, reads them back through the API, verifies hashes, detached signatures, installer version,
tag-to-child commit/tree and origin main provenance, then calls `pages.yml` with the numeric draft
Release ID and exact source/origin/tree/canonical-source/snapshot/build hashes. Pages performs
authenticated API readback and public-key-only verification before deployment. The pipeline then
verifies package/database objects over public HTTPS, publishes the immutable Release without
replacing an asset, and repeats unauthenticated asset and Pages readback.

GitHub cannot atomically deploy Pages and publish a Release. The Pages job rechecks the reviewed
`main` commit immediately before deployment; publication stops if that commit has advanced after
Pages deployment. While the reviewed `main` commit is unchanged, a retry resumes only the exact
existing draft and its already verified bytes. If `main` advances, its next successful CI run
prepares a new candidate; the earlier draft stays unpublished. Never upload replacement assets,
move the earlier tag or transfer its acceptance to newer source.

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

## 8. Updates

Installer changes are new immutable SemVer releases. Arch Linux
updates normally through `pacman -Syu`. Marble/profile changes increment the owning package's
`pkgrel` and are delivered through the signed Pages repository, so they do not require an installer
release. Source pins change only through a reviewed pull request.
Use the explicit [package-only Pages route](../repository/README.md#package-only-updates), with a
new package tag and verified signed snapshot. This is not a new installer release.

The maintenance watcher may only create or update an advisory issue; monthly A+B is advisory and
never blocks release. The configured release pipeline automatically signs and releases only its
exact verified release child after the online `main` merge. No workflow automatically merges,
rotates keys or changes a fingerprint, checksum, source pin or accepted ISO. There is no `arch-os`
synchronization. A signing key changes only through a separately authorized manual rotation
procedure.

## Required path summary

```text
SOURCE
  -> syntax/static/function/ShellCheck/secret checks
  -> one clean canonical Arch package build
  -> unsigned package and repository verification
  -> authorized Actions signing of the exact 14-file closure
  -> three QEMU scenarios
  -> immutable GitHub Release and verified Pages deployment
  -> one public final VM test
```
