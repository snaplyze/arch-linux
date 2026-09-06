# Signed package repository

The optional Marble profile is delivered through a project-owned pacman repository. Stock GNOME is
not dependent on repository availability.

## Package set

`repository/package-set` is the exact ordered package allowlist:

1. `arch-linux-keyring`
2. `arch-linux-marble-shell`
3. `arch-linux-colloid-gtk3`
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

The Colloid icon input for 1.0.1 is `20260829-1`; the GTK3 input and GDM-critical icon hashes
are unchanged. See the [review and delivery boundary](maintenance.md#colloid-and-gum-review-september-2026).
An unsigned build or a source merge is not a Pages update. A new signed snapshot must carry
the higher package version before installed systems receive it through `pacman -Syu`.

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

## Offline signing

Production signing is local and explicitly authorized. Use the root hash-pinned sealer and generated
static launcher described in [repository tooling](../repository/README.md). The private home and
mode-`0600` passphrase pathname are supplied only as two FIFO lines; the launcher retains FD 6,
sealed memfd 7, capability FD 8 and lock FD 9. The independently accepted canonical build hashes are
mandatory inputs. Before invoking the launcher, stage the verified unsigned closure as the separate
root-owned, single-link `$ACCEPTED_UNSIGNED` copy described by the repository tooling. Prepare
`$SNAPSHOT_OUTPUT` as a missing name below a separate signing-account-owned mode-`0700` parent.
Neither variable may point at the native build directory or share a parent with private state:

```bash
set +x
printf '%s\n%s\n' "$PRIVATE_HOME" "$PASSPHRASE_FILE" | \
  /usr/bin/env -i "$SEALED_ROOT/repository/offline-signing-launcher" snapshot \
  --unsigned "$ACCEPTED_UNSIGNED" \
  --installer "$SEALED_ROOT/arch-linux-installer.sh" \
  --output "$SNAPSHOT_OUTPUT" \
  --release-version 1.0.1 \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
```

The launcher is invoked as host root only so it can validate the exact unique locked account; it
irreversibly drops to that account before reading either FIFO-supplied pathname. No production
private key, passphrase or recovery material is accepted through source files, CI,
command-line options or generated artifacts. The boundary uses an empty-derived environment and
fresh user/PID/mount/network namespaces, exposes only loopback, and destroys its private agent/socket
state on every exit. The signer verifies the independently accepted build hashes and
each package payload before creating package signatures, signed database/files indexes, a signed
canonical manifest, installer assets and a deterministic Pages snapshot.

## Verification

```bash
repository/verify-signed-repository.sh "$SNAPSHOT_OUTPUT/repository" \
  --release-version 1.0.1 \
  --source-commit "$SOURCE_COMMIT" --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
repository/verify-release-assets.sh "$SNAPSHOT_OUTPUT/assets" --phase-a \
  --release-version 1.0.1 \
  --source-commit "$SOURCE_COMMIT" --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
```

The verifiers require the exact public certificate and fingerprints, exact package/database file
closure, valid signatures from the accepted signing subkey, safe database archives and package
filenames that agree with the database.

## Pacman policy and lifecycle

Clients use:

```ini
SigLevel = PackageRequired DatabaseRequired TrustedOnly
```

There is no unsigned fallback, `TrustAll` mode or automatic fingerprint acceptance. Marble profile
install, upgrade, removal, reinstall and unsupported-GNOME fallback are package lifecycle behavior;
normal updates use `pacman -Syu`.

## Pages deployment

`.github/workflows/pages.yml` accepts a numeric draft Release ID and the exact frozen source/build
identities. It reads back exactly eighteen finalized uploaded assets through the authenticated API, proves the
annotated tag, API digests, archive checksum and signatures, safely extracts the snapshot, and
re-verifies every package/database object before uploading the Pages artifact. Actions contains no
private signing key.

For package-only updates, use the `packages` deployment mode described in
[repository tooling](../repository/README.md#package-only-updates). It accepts a separately tagged,
signed 14-file package-update bundle for an existing installer version. A Marble profile `pkgrel`
update therefore does not require a new installer release or replacement of old installer assets.
