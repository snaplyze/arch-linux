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

Production signing is local and explicitly authorized. Prepare a new mode-`0700` canonical
`/tmp/arch-linux-signing-home.XXXXXXXX`, transfer only the accepted signing subkey into it through
the separate protected local procedure, stop its agent and create the mode-`0600` marker described
in [repository tooling](../repository/README.md). The independently accepted canonical build hashes
are mandatory inputs:

```bash
GNUPGHOME="$DISPOSABLE_GNUPGHOME" GPG_TTY="$(tty)" \
  repository/run-offline-signing.sh \
  --unsigned "$ARTIFACT_DIR/unsigned" \
  --installer "$REPO_ROOT/arch-linux-installer.sh" \
  --output "$ARTIFACT_DIR/signed" \
  --release-version 1.0.0 \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
```

No production private key, passphrase or recovery material is accepted through source files, CI,
command-line options or generated artifacts. The wrapper uses an empty-derived environment and
user/PID/mount/network namespaces, exposes only loopback, and deletes the explicitly marked
disposable key home on every exit. The signer verifies the independently accepted build hashes and
each package payload before creating package signatures, signed database/files indexes, a signed
canonical manifest, installer assets and a deterministic Pages snapshot.

## Verification

```bash
repository/verify-signed-repository.sh "$ARTIFACT_DIR/signed/repository" \
  --release-version 1.0.0 \
  --source-commit "$SOURCE_COMMIT" --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
repository/verify-release-assets.sh "$ARTIFACT_DIR/signed/assets" \
  --release-version 1.0.0 \
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
identities. It reads back exactly twelve uploaded assets through the authenticated API, proves the
annotated tag, API digests, archive checksum and signatures, safely extracts the snapshot, and
re-verifies every package/database object before uploading the Pages artifact. Actions contains no
private signing key.
