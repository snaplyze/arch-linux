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

## Rotation or compromise

A planned signing-subkey transition needs an overlap period in which the currently trusted release
can authenticate the next accepted public input. On suspected compromise, stop signing/deployment,
use the offline recovery plan, publish independently verified incident information and require an
explicit new trust bootstrap. Never silently replace a fingerprint.
