# Signed package repository

The optional Marble profile is delivered through a project-owned pacman repository. Stock GNOME is
not dependent on repository availability.

## Package set

`repository/package-set` is the exact ordered package allowlist:

1. `arch-linux-keyring`
2. `arch-linux-marble-shell`
3. `arch-linux-colloid-gtk`
4. `arch-linux-colloid-icons`
5. `arch-linux-marble-profile`
6. `arch-linux-marble-gdm`

The GDM package remains separate and is never implied by selecting the Marble user profile. Package
metadata and immutable source bindings are checked with:

```bash
python3 repository/verify-package-metadata.py
while IFS= read -r package; do
  repository/validate-package-sources.sh --regenerate "packages/$package"
done < repository/package-set
```

The Colloid icon input is `20260829-1`; the pinned GTK upstream source and GDM-critical icon hashes
are unchanged. `arch-linux-colloid-gtk` packages GTK3, GTK4 and libadwaita assets together and
replaces the legacy `arch-linux-colloid-gtk3` package during normal updates.
See the [review and delivery boundary](maintenance.md#colloid-and-gum-review-september-2026).
The historical `1.0.1` snapshot and its package-delivery evidence remain records of their original
inputs; its retired release/tag objects are not a current Pages publication reference. An unsigned
build or source merge alone is still not a Pages update; changed package bytes need a new
version/pkgrel.

## Canonical unsigned build

Run once in a clean Arch environment as an unprivileged temporary builder:

```bash
repository/build-packages.sh "$ARTIFACT_DIR/unsigned"
repository/verify-unsigned-build.sh "$ARTIFACT_DIR/unsigned"
```

The verifier requires exactly one unsigned package per allowlisted name, exact committed `.SRCINFO`,
schema-2 source/build identity, `.BUILDINFO`, `.MTREE`, a canonical checksum list and no signatures
or unexpected objects. It decompresses every real package and checks its exact package-specific
payload, ownership, modes, dependencies, hooks, licenses and bounded internal symlinks.
Release 1.0.6 bounds compressed and expanded bytes, aggregate payload, individual members,
extension headers, member count and inspection time, with resource-limited decompressor children
and checked cleanup. See [inspection limits](#unsigned-archive-inspection-limits).
The historical [F-04 / TRUST-01 finding](PLAN.md#review-findings) is closed; passing a bounded
inspection still does not authorize installation or replace signature verification.

## Signing boundary

The configured `release.yml` pipeline is authorized after a successful reviewed merge to
`main`. It reconstructs and tests a deterministic version-only release child, binds both that child
and the origin main commit/tree, and then gives only its `snapshot` and `finalize` jobs the
release-environment `ARCH_LINUX_SIGNING_KEY` and `ARCH_LINUX_SIGNING_PASSPHRASE` secrets. Those jobs
import only the signing-only subkey into a fresh temporary no-network boundary and remove it on exit.
Build, QEMU, PR, CI, Pages, maintenance and public-readback jobs receive neither secret.

The independently accepted canonical build hashes are mandatory inputs. The adapter signs the exact
14-file Phase-A closure, QEMU consumes that closure, and finalization preserves its 14 bytes while
adding the signed acceptance JSON and evidence archive for exact 18. It must never import the
certification primary, recovery material or pass private authority to `repo-add`.

The root hash-pinned sealer and generated static launcher remain the host-local signing entrypoint
for the documented recovery boundary. Its private home and mode-`0600` passphrase pathname are
supplied only as two FIFO lines; it retains FD 6, sealed memfd 7, capability FD 8 and lock FD 9.
Before invoking it, stage the verified unsigned closure as the separate root-owned, single-link
`$ACCEPTED_UNSIGNED` copy described by the repository tooling. Prepare `$SNAPSHOT_OUTPUT` as a
missing name below a separate signing-account-owned mode-`0700` parent. Neither variable may point
at the native build directory or share a parent with private state:

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

The host launcher is invoked as root only so it can validate the exact unique locked account; it
irreversibly drops to that account before reading either FIFO-supplied pathname. No production
private key, passphrase or recovery material is accepted through source files, command-line options
or generated artifacts. The host boundary uses an empty-derived environment and
fresh user/PID/mount/network namespaces, exposes only loopback, and destroys its private agent/socket
state on every exit. The signer verifies the independently accepted build hashes and
each package payload before creating package signatures, signed database/files indexes, a signed
canonical manifest, installer assets and a deterministic Pages snapshot.

## Verification

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
```

The verifiers require the exact public certificate and fingerprints, exact package/database file
closure, valid signatures from the accepted signing subkey, safe database archives and package
filenames that agree with the database.
Release 1.0.6 also cross-checks `.db` name/version/size/hash/embedded-signature fields and
`.files` package identities/file lists against the verified package set, rejecting inconsistent
records. The historical [F-12 / TRUST-02 finding](PLAN.md#review-findings) is closed.
These semantic checks supplement the mandatory genuine signatures and hash bindings.

## Pacman policy and lifecycle

Clients use:

```ini
SigLevel = PackageRequired DatabaseRequired TrustedOnly
```

There is no unsigned fallback, `TrustAll` mode or automatic fingerprint acceptance. Marble profile
install, upgrade, removal, reinstall and unsupported-GNOME fallback are package lifecycle behavior;
normal updates use `pacman -Syu`.

## Pages deployment

`.github/workflows/pages.yml` is called by the release pipeline with a numeric draft Release ID and
the exact frozen source/build identities. It reads back exactly eighteen finalized uploaded assets
through the authenticated API, proves the
annotated tag, API digests, archive checksum and signatures, safely extracts the snapshot, and
re-verifies every package/database object before uploading the Pages artifact. The Pages job contains
no signing secret or private key.

For package-only updates, use the `packages` deployment mode described in
[repository tooling](../repository/README.md#package-only-updates). It accepts a separately tagged,
signed 14-file package-update bundle for an existing installer version. A Marble profile `pkgrel`
update therefore does not require a new installer release or replacement of old installer assets.
The delivered tooling implements strict package-child provenance and requires version-only
normalization to exact published installer/bootstrap bytes. Future installer/bootstrap behavior
changes require a new accepted installer release before package-only delivery. External package delivery remains separately authorized and
NOT_TESTED; local source validation does not prove signed installed-system upgrade or deployment.
See [DELIVERY-01](PLAN.md#delivery-01--package-only-provenance-and-procedure).

## Unsigned archive inspection limits

Package verification rejects input above 128 MiB compressed, 512 MiB expanded tar or aggregate
payload, 32 MiB per member, 1 MiB per extension header, 100,000 physical headers or logical
members, and 16 nested extension headers. Integrity checking, decompression and traversal
share a 60-second deadline; zstd children have 512 MiB address-space and CPU limits and are
reaped on rejection. Limits are fixed in the verifier, without environment/CLI overrides.
GNU sparse encodings are rejected before map parsing; this package closure does not use them.
Solaris PAX receives the same extension bounds as other recognized extension formats.

The October 3 preliminary clean Arch inventory built all six packages as a disposable non-root
user with the pinned build-container input. Observed maxima: compressed 5,271,971 bytes; tar
61,429,760 bytes; payload 35,432,571 bytes; member 1,245,973 bytes; 41,216 members; verifier
1.196 seconds. Policy provides at least eightfold byte, twofold entry and fiftyfold measured
wall-time headroom. This inventory sizes the inspection policy; it is not the frozen candidate's
canonical build or installation acceptance. A changed package closure requires fresh inventory
and independently verified canonical output before release.
