# Initial public trust v1

This directory contains only the public bootstrap material for the project-owned pacman
repository:

- `arch-linux.gpg` — a minimized public OpenPGP certificate with one certification-only primary,
  one future-expiring signing-only subkey and no secret packets;
- `primary-fingerprint` — `9C603F25F83F4B0F4745D790D97919282A24E748`;
- `signing-subkey-fingerprint` — `B294D26BDAD5469EE334B0453DA0736C98322CCA`.

Every bootstrap and verifier checks the complete fingerprints, exact public-certificate bytes,
certificate shape, subkey expiration and detached signatures. The keyring package is bound to the
same three files by literal SHA-256 values. Pacman uses
`PackageRequired DatabaseRequired TrustedOnly`; automatic keyserver trust, `TrustAll` and unsigned
fallbacks are forbidden.

The certification primary and revocation certificate do not belong here and remain in protected
offline storage. The signing-only subkey and its passphrase are configured only as release
Environment secrets for the authorized `snapshot` and `finalize` Actions jobs. Each job imports the
subkey into a fresh temporary no-network boundary and destroys it on exit; no other job receives
either secret. Planned rotation first distributes the replacement subkey while the current signer
still authenticates repository and installer bytes. The next release switches fresh-bootstrap and
repository signatures. In that transition release the normal `arch-linux-installer.sh.sig` remains
the old-signer compatibility signature that older updaters authenticate with their already embedded
certificate; the new-signer fresh-bootstrap signature is `arch-linux-installer.sh.current.sig`.
The following release removes that transition asset and returns `.sig` to the new current signer.
Updaters never trust a co-downloaded key. Emergency revocation forbids that overlap and requires an
independently verified bootstrap, never an insecure bridge.

See [`../../docs/trust-model.md`](../../docs/trust-model.md) for the threat model and
[`../README.md`](../README.md) for build, offline-signing, verification and Pages commands.
