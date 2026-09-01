# Repository agent contract

This file is the only normative contract for automated coding agents. Other agent-specific files
may only point here. Product documentation explains the implementation but does not override these
rules.

## Project structure

- `arch-linux-installer.sh`: interactive setup and the privileged installation executor.
- `install.sh`: immutable release bootstrap and installer signature verification.
- `packages/`: project keyring, Marble profile, Marble GDM and pinned package sources.
- `repository/`: canonical build, verification, offline signing and signed-snapshot tools.
- `tests/`: source, installer-function, Marble, package and repository regression tests.
- `maintenance/`: advisory monitors for the Arch ISO and current external source inputs.
- `.github/workflows/`: exactly four no-production-secret workflows.
- `docs/`: current product, testing, release and trust documentation.

Generated configuration, logs, package outputs, virtual disks, firmware state, acceptance evidence
and all private signing material are not source.

## Allowed commands

Run these commands from the repository root, or compute that root from the invoking script:

- `bash tests/source-tests.sh`
- `bash tests/bootstrap-checks.sh`
- `bash tests/static-checks.sh`
- `bash tests/function-checks.sh`
- `bash tests/marble-checks.sh`
- `bash tests/repository-checks.sh`
- `python3 repository/verify-package-metadata.py`
- `python3 maintenance/check-sources.py`

A clean Arch environment may additionally run:

```bash
repository/build-packages.sh "$ARTIFACT_DIR/unsigned"
repository/verify-unsigned-build.sh "$ARTIFACT_DIR/unsigned"
```

Do not run destructive installer paths on a development workstation. Use disposable virtual
machines and exact release inputs for installation acceptance.

## Repository root

Scripts must derive `REPO_ROOT` from `BASH_SOURCE`, `__file__` or `git rev-parse --show-toplevel`.
They must not depend on the caller's current directory or a named workstation. Use `mktemp`,
`RUNNER_TEMP`, `WORK_DIR`, `ARTIFACT_DIR` and `EVIDENCE_DIR` for generated data. Normal target-system
paths under `/usr`, `/etc`, `/var`, `/mnt` and `/tmp` are allowed when they are part of the product
contract rather than a developer-machine binding.

## Installer invariants

Preserve Minimal TTY, Stock GNOME, Marble, separate Marble GDM opt-in, ext4, Btrfs, GRUB,
systemd-boot, LUKS2, fresh install and dual boot. Do not change the meaning of prompts,
`installer.conf`, partitioning, bootloader, encryption or installation phases without a reproduced
bug and a regression test. Stock GNOME remains the default graphical profile.

## Disk and destructive invariants

Never weaken physical-disk identity capture, target partition identity, the immediate pre-mutation
recheck, busy-device detection, ambiguity rejection or holder/swap/mount checks. Cleanup may remove
only resources recorded as created by that exact installer run. A mismatch or uncertainty must stop
before the destructive operation.

## Package and signing boundaries

PKGBUILDs run only as a disposable unprivileged builder; never run `makepkg` as root. Root may consume
only independently verified package bytes. Pacman trust remains
`PackageRequired DatabaseRequired TrustedOnly`. Package and repository database signatures are
mandatory. CI may build unsigned packages but must never receive a production private key,
passphrase, recovery material or signing authority. Do not introduce unsigned fallback, `TrustAll`,
automatic fingerprint acceptance or keyserver bootstrap.

## Marble and GDM boundaries

Marble is installed only by project packages and updates through `pacman -Syu`. Profile changes must
not require a new installer release. Marble GDM remains a separate opt-in. Its resource and dconf
overlays must be scoped to the GDM Shell systemd service; the user GNOME Shell must not inherit them.
Do not overwrite vendor-owned GNOME/GDM resources. Unsupported GNOME versions must deactivate the
profile safely and retain Stock. Installation, upgrade, removal, reinstall and fallback require
regression coverage.

## Required source tests

Before a source candidate, run `bash tests/source-tests.sh`. That command includes Bash syntax,
version smoke, bootstrap, static, installer-function, Marble lifecycle, package metadata,
documentation links, portability, secret, agent-contract, maintenance, repository positive/negative
signature fixtures and ShellCheck. Record the exact command and status; a code review is not an
executed test.

## Evidence separation

Keep source, package-build output, QEMU evidence and release/public-readback evidence separate.
Source archives must not contain ISO images, qcow2 disks, OVMF variable stores, package outputs,
logs or earlier acceptance evidence. A result from one layer does not prove another layer.

## Secrets

Private OpenPGP/SSH keys, tokens, passphrases, recovery phrases/shares, revocation material and local
configuration never enter tracked files, CI, test fixtures or generated source archives. Public
`arch-linux.gpg` and published fingerprints are permitted and must contain no secret packets.

## Tree-bound results

Every result belongs to the exact source tree and input hashes that produced it. Never transfer a
PASS from another commit, tree, package set, ISO, VM disk, firmware state or public asset. Re-run the
applicable check after any source change.

## Bounded remediation

For a source-candidate task, perform one coherent implementation pass and at most one coherent
test-fix pass. Do not start a third architectural rewrite. Freeze the source tree before packaging
the candidate.

## Product failure

A reproducible product failure stops acceptance. Do not mask it with retries, weaker checks,
changed fixtures or a removed negative test. Report one primary blocker when it remains.

## Infrastructure retry

One retry is permitted only for a demonstrated transient network or infrastructure failure. Record
the concrete reason. A product failure is not retryable.

## Pins and keys

Never change a source URL, hash, package pin, accepted ISO, fingerprint, signing subkey or trust
certificate automatically. Advisory maintenance may report drift, but a human-reviewed source
change and all affected tests are required.

## Release authorization

Do not sign with production material, create or mutate a GitHub release, deploy Pages, publish
packages, rotate keys or change repository settings without a separate explicit authorization.
Source-candidate completion is not `RELEASED`.
