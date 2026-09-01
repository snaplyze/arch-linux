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
- `offline-sign-release.sh`: local signing and repository/release assembly; forbidden in CI.
- `run-offline-signing.sh`: loopback-only namespace wrapper.
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

Run only after separate authorization and outside CI. First create a fresh canonical
`/tmp/arch-linux-signing-home.XXXXXXXX` directory with mode `0700`, populate it locally with only the
accepted production signing subkey and public certificate through the separately approved
non-logging key-transfer procedure, stop its agent, then add the required marker:

```bash
printf '%s\n' 'arch-linux-offline-signing-disposable-v1' \
  >"$DISPOSABLE_GNUPGHOME/.arch-linux-disposable-signing-home"
chmod 0600 "$DISPOSABLE_GNUPGHOME/.arch-linux-disposable-signing-home"
gpgconf --homedir "$DISPOSABLE_GNUPGHOME" --kill all
```

`BUILD_METADATA_SHA256` and `UNSIGNED_MANIFEST_SHA256` are the independently recorded hashes from
the downloaded canonical build, not values newly accepted inside the signing operation. Invoke:

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

The signer accepts no passphrase/key file option and no automatic key retrieval. It uses an empty
derived environment plus user, PID, mount and loopback-only network namespaces, verifies the
canonical hash pair and every package before signing, constructs the exact release closure and
invokes the public verifiers. The wrapper stops its agent and deletes the marked disposable home on
success or failure. It refuses an unmarked, non-canonical or persistent home.

## Public verification

```bash
repository/verify-signed-repository.sh "$ARTIFACT_DIR/signed/repository" \
  --release-version "$VERSION" \
  --source-commit "$SOURCE_COMMIT" --source-tree "$SOURCE_TREE" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
repository/verify-release-assets.sh "$ARTIFACT_DIR/signed/assets" \
  --release-version "$VERSION" \
  --source-commit "$SOURCE_COMMIT" --source-tree "$SOURCE_TREE" \
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
Release ID plus the exact frozen commit/tree and build/snapshot hashes. It reads back exactly twelve
draft assets through the authenticated GitHub API, verifies their API digests, annotated tag,
checksums, signatures and full repository closure, then safely extracts and uploads the Pages
artifact. Production private material is never an Actions secret.
