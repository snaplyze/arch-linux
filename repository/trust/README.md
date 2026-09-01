# Initial public trust v1

This directory contains only the public bootstrap material for the project-owned pacman
repository:

- `arch-linux.gpg` — a minimized public OpenPGP certificate with one certification-only primary,
  one future-expiring signing-only subkey and no secret packets;
- `primary-fingerprint` — `8C78098D1EAC609CBC73536FB7D2C17447B90CB2`;
- `signing-subkey-fingerprint` — `0AA6F2237FB9674623B6E824428D56A84F558F7C`.

Every bootstrap and verifier checks the complete fingerprints, exact public-certificate bytes,
certificate shape, subkey expiration and detached signatures. The keyring package is bound to the
same three files by literal SHA-256 values. Pacman uses
`PackageRequired DatabaseRequired TrustedOnly`; automatic keyserver trust, `TrustAll` and unsigned
fallbacks are forbidden.

The certification primary, private signing material, passphrase and revocation certificate do not
belong here. They must remain in protected offline storage. Planned rotation first distributes the
replacement subkey while the current signer still authenticates repository and installer bytes. The
next release switches fresh-bootstrap and repository signatures. In that transition release the
normal `arch-linux-installer.sh.sig` remains the old-signer compatibility signature that older
updaters authenticate with their already embedded certificate; the new-signer fresh-bootstrap
signature is `arch-linux-installer.sh.current.sig`. The following release removes that transition
asset and returns `.sig` to the new current signer. Updaters never trust a co-downloaded key.
Emergency revocation forbids that overlap and requires an independently verified bootstrap, never
an insecure bridge.

See [`../../docs/trust-model.md`](../../docs/trust-model.md) for the threat model and
[`../README.md`](../README.md) for build, offline-signing, verification and Pages commands.
