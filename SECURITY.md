# Security policy

## Supported version

Security fixes target the current immutable release and the current default branch. Older releases
may remain available for reproducibility but do not receive indefinite support.

## Reporting

Do not disclose exploitable disk, privilege, signature or update weaknesses in a public issue before
coordination. Report privately to the repository owner with the affected version/tree, reproduction
steps, expected safety boundary and observed result. Do not include real credentials or private key
material.

## Installer boundary

The installer binds the selected physical disk and target partitions to stable identity data,
revalidates them immediately before mutation, rejects busy or ambiguous devices and cleans only
resources owned by the current run. PKGBUILDs execute under a disposable unprivileged account;
verified package bytes cross into the root executor only after the builder exits.

## Trust bootstrap

The release bootstrap pins the installer checksum, public-certificate digest, primary fingerprint
and signing-subkey fingerprint. It requires one certification-only primary key, one signing-only
subkey and no secret packets. Detached signatures are verified with `gpgv`. Users must compare the
fingerprints through an independently trusted channel before first use.

Pacman clients use `PackageRequired DatabaseRequired TrustedOnly`. An unavailable or invalid project
repository must not weaken Stock GNOME or activate an unsigned fallback.

## Signing authority

The certification primary, recovery shares and revocation material remain offline. The configured
`release.yml` pipeline permits only its `snapshot` and `finalize` jobs to receive the signing-only
subkey and passphrase through the protected release Environment. Each job imports that subkey into
a fresh temporary no-network boundary and destroys it on exit. PR, ordinary CI, build, QEMU, Pages,
maintenance and public-readback jobs receive neither signing secret. No private material belongs
in source, build outputs, logs or published assets.

The separate authorized host recovery path uses the hash-pinned root sealer and static offline
launcher, with a locked signing account, descriptor-bound private inputs and isolated namespaces.
Both paths require independently verified inputs and signed output verification. See the
[trust model](docs/trust-model.md#authority-separation) and
[release process](docs/release-process.md).

## Key incident

On suspected key loss or compromise, stop signing and repository deployment. Publish independently
verified incident information through trusted channels, revoke the affected credential according to
the offline recovery plan, and require explicit fingerprint verification for any replacement trust
root. Never rotate a key or accepted fingerprint automatically.
