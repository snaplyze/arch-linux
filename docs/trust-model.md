# Trust model

## Public trust root

`repository/trust/arch-linux.gpg` is the exact public certificate distributed with source and release
assets. It must contain one certification-only primary key, one future-expiring signing-only subkey
and no secret packets. Exact primary and signing-subkey fingerprints are stored beside it.

Users must compare those fingerprints through an independently trusted channel before first use.
The bootstrap additionally pins the certificate SHA-256 so account-level asset replacement is
detected, but a checksum and certificate obtained only from the same account are not independent
identity proof.

## Signed objects

The accepted signing subkey signs:

- every project package;
- `arch-linux.db.tar.gz` and `arch-linux.files.tar.gz`;
- the canonical repository manifest;
- installer and release checksum assets.

Verification rejects an unexpected signer, primary key, certificate shape, missing signature, extra
file, unsafe archive member or manifest mismatch. Pacman uses
`PackageRequired DatabaseRequired TrustedOnly`.

## Authority separation

- CI may lint source and build the canonical unsigned package set.
- Production private signing material remains offline.
- Offline signing consumes only an independently verified unsigned closure.
- Pages consumes only an already signed snapshot and re-verifies it using public trust.
- Stock GNOME does not depend on project repository availability.

No stage may weaken trust to make a failing release pass. Fingerprint, key, hash and pin changes are
manual, reviewed source changes.

## Expiry renewal and installed systems

Expiration does not destroy the private key. Before the existing signing subkey expires, its expiry
can be extended using the existing offline certification primary. This is a manual maintenance
operation, not a GitHub signing job and not automatic key rotation.

1. Verify the existing recovery set offline. Do not move private material into source, CI or a VM.
2. Extend the existing signing subkey's expiry using that primary; do not generate a replacement
   subkey for an ordinary renewal. Export only the refreshed public certificate for distribution.
3. Independently check the unchanged primary/signing fingerprints, the later expiry and absence of
   private packets. Update the tracked public certificate and its reviewed checksum references,
   increment `arch-linux-keyring`'s `pkgrel`, regenerate `.SRCINFO`, and review the change in a PR.
   Refresh the documented expiry/renewal dates from `maintenance/check-key-lifetime.py` as well.
4. Build, test and sign the updated keyring and repository. Publish the signed package update before
   the old certificate expires. The keyring package's upgrade hook populates pacman's keyring and
   updates its trust database; users receive the refreshed certificate through `pacman -Syu`.

Systems updated during that overlap do not need manual key import or a new installation. A machine
left offline past expiry may reject the repository before it can download the new keyring package.
Do not disable signature checks on that machine. Use independently authenticated refreshed public
trust and an explicitly documented manual recovery procedure instead. An old release bootstrap also
pins its original certificate bytes; use a newer reviewed installer release for new installations
after that original trust input expires. Existing installed systems use the delivered keyring.

The keyring regression suite exercises the existing same-subkey renewal and real upgrade hook with
ephemeral test keys. That is not authorization to renew the production key automatically.

### Recovery after missing the update window

This procedure is only for an existing installation whose already trusted primary and signing
subkey have not changed, and where ordinary renewal was published but the local certificate expired.
A revoked/compromised key or changed fingerprint needs the separate incident/rotation procedure,
not these commands. Check the system clock first; never roll it back to bypass expiration.

Obtain the refreshed **public-only** certificate and its SHA-256 through an independently
authenticated maintainer channel. A certificate plus checksum from the same unverified download
is not sufficient. Use a reviewed project checkout for its existing public-certificate verifier.
Set `WORK_DIR` to a private directory outside source containing `arch-linux-renewed.gpg`, and set
`EXPECTED_PUBLIC_SHA256` to that authenticated checksum. No private key or passphrase is needed.

From the reviewed checkout, verify before touching pacman's keyring:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
RECOVERY_PUBLIC_CERT="$WORK_DIR/arch-linux-renewed.gpg"
printf '%s *%s\n' "$EXPECTED_PUBLIC_SHA256" "$RECOVERY_PUBLIC_CERT" | sha256sum --check --strict - &&
bash -euc '
  source "$1/repository/lib/common.sh"
  repository_assert_public_certificate "$2" \
    "$1/repository/trust/primary-fingerprint" \
    "$1/repository/trust/signing-subkey-fingerprint" 0
' recovery "$REPO_ROOT" "$RECOVERY_PUBLIC_CERT"
```

Stop if either check fails. The verifier requires the exact fingerprints, the permitted certificate
shape, no private packets and a currently valid, non-revoked signing subkey. The original primary
must already be locally trusted on this installed system; do not add new ownertrust or locally sign
a new key as part of recovery. Import the authenticated renewal and perform a full update:

```bash
sudo pacman-key --list-keys 8C78098D1EAC609CBC73536FB7D2C17447B90CB2 &&
sudo pacman-key --add "$RECOVERY_PUBLIC_CERT" &&
sudo pacman-key --updatedb &&
sudo pacman -Syu
```

If an operation fails, stop and investigate. Keep `PackageRequired DatabaseRequired TrustedOnly`;
do not use a keyserver, `TrustAll`, disabled signature checks or an unsigned fallback. The full update
delivers the reviewed `arch-linux-keyring` package and its normal upgrade hook. Confirm its installed
version and the refreshed expiry with `pacman -Q arch-linux-keyring` and
`sudo pacman-key --finger 8C78098D1EAC609CBC73536FB7D2C17447B90CB2`.
See the [pacman-key manual](https://man.archlinux.org/man/pacman-key.8.en) for these operations.

## Rotation or compromise

A planned signing-subkey transition needs an overlap period in which the currently trusted release
can authenticate the next accepted public input. On suspected compromise, stop signing/deployment,
use the offline recovery plan, publish independently verified incident information and require an
explicit new trust bootstrap. Never silently replace a fingerprint.
