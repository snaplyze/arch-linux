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

Release-host acceptance additionally requires the unflagged and full namespace repository modes,
the root publication boundary, and both keyring modes:

```bash
bash tests/repository-checks.sh
bash tests/repository-checks.sh --require-full-namespace
/usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
  /usr/bin/bash --noprofile --norc tests/publication-root-check.sh </dev/null
bash tests/keyring-rotation-checks.sh
env ARCH_LINUX_PRIVILEGED_ACCEPTANCE=true bash tests/keyring-rotation-checks.sh
```

The mandatory full repository run ends only with
`REPOSITORY_CHECKS_RESULT schema=1 namespace_fixtures=full scenarios=10 signer=passed
release_closures=14+18 deferred=none`. Schema 1 here names the release-host acceptance result;
package build and repository metadata remain schema 2.

Do not run destructive installer paths on a development workstation. Use disposable virtual
machines and exact release inputs for installation acceptance.

## Repository root

Scripts must derive `REPO_ROOT` from `BASH_SOURCE`, `__file__` or `git rev-parse --show-toplevel`.
They must not depend on the caller's current directory or a named workstation. Use `mktemp`,
`RUNNER_TEMP`, `WORK_DIR`, `ARTIFACT_DIR` and `EVIDENCE_DIR` for generated data. Normal target-system
paths under `/usr`, `/etc`, `/var`, `/mnt` and `/tmp` are allowed when they are part of the product
contract rather than a developer-machine binding.

## Canonical checkout workflow

Use the checkout containing this file as the sole persistent local development checkout. Perform
local review, source changes, tests, commits, branch work and release-host acceptance there, and
switch feature or pull-request branches in place. Do not create additional local Git worktrees,
sibling clones, per-cycle source directories, copied or replacement source repositories, or a
whole-directory cutover for development. After a pull request is merged, return this same checkout
to `main` and update it by fast-forward only.

Mandatory ephemeral security boundaries remain permitted: protected GitHub Actions canonical and
validation clones, disposable package build directories and users, root-owned gate inputs, sealed
signing bootstrap and one-use signing input copies, test fixtures, qcow2 disks, OVMF variable stores
and VM payloads or read-only shares. They are not development source, must not be edited or committed,
and must be removed when their bounded stage ends, except for explicitly retained compact evidence
and pinned external inputs governed by the evidence policy.

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

Before production signing, independently bind the accepted Git commit/tree and canonical
mode-and-byte SHA-256, then copy the hash-pinned sealer into a fresh root-owned mode-`0700`
bootstrap directory as a mode-`0500` file. Execute that pinned copy only as host root with `env -i`,
the exact four-variable environment and stdin `/dev/null`. The sealer creates one immutable
root-owned exact-file closure and compiles a fresh x86-64 static PIE launcher with no `PT_INTERP`.

The generated `repository/offline-signing-launcher` is the sole production entrypoint. It runs only
as the locked, nologin, no-home, quiescent `arch-linux-signing` account with no supplementary groups.
Its FIFO stdin contains exactly two canonical pathnames: the existing private home and the mode-0600
passphrase file. Those pathnames never enter argv, environment, logs or evidence. The launcher
retains the home as FD 6, captures the passphrase into a fully sealed memfd 7, carries only its
one-shot capability on FD 8 and locks the home on FD 9. It closes ambient descriptors, disables
core dumps and dumpability, and never exposes private bytes to GitHub, a VM or `repo-add`.

Both launcher modes, `snapshot` and `finalize`, enter fresh user, network, PID and mount namespaces.
Namespace PID 1 binds only retained FD 6 at the fixed private home, keeps every agent socket on
private tmpfs, exposes loopback only, revalidates memfd 7 immediately before every GPG operation and
destroys every agent/socket when its supervisor dies. Direct, sourced, inner-script and CI entry
must reject before private access. The public key must remain one certification-only primary plus
one signing-only subkey with at least 180 days remaining; GPG receives the passphrase only through
FD 7. `repo-add --include-sigs` receives no private descriptor or key selector; database/files
signatures are added explicitly afterward.

`snapshot` emits exactly 14 Phase-A assets: the existing 12-file signed release closure plus
byte-identical `BUILD-METADATA.json` and `UNSIGNED-SHA256SUMS`. Signed `RELEASE-SHA256SUMS` covers
exactly the 12 non-self files. After three functional QEMU PASS results, `finalize`
copies all 14 bytes unchanged and adds the signed acceptance JSON and signed evidence `.tar.zst`,
forming exact 18. The JSON binds commit/tree/canonical source hash, build/unsigned/snapshot hashes,
the exact Phase-A name/hash/size map and aggregate, its manifest hash, three PASS verdicts,
evidence at most 500 MiB and `deferred=[]`.

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

## Practical VM checks

Use real QEMU/KVM, a fresh disk and independent firmware variables, and the recorded source,
ISO and signed package inputs. Run the installer and check the installed system: the selected
storage, encryption and bootloader; boot and network; the requested desktop; package integrity;
updates and another boot; no failed systemd units; clean shutdown and `qemu-img check`.
For GNOME, perform actual GDM password login and check the resulting Wayland session, lock/unlock
and profile. Do not replace login with autologin or start a session through QGA. QGA may run guest
diagnostics and verify the result of real user input.

Screenshots are optional diagnostic aids. A screenshot timeout is not an installation failure.
Do not impose frame timing, continuous recording, pixel challenges, contact sheets or mandatory
human review receipts. `tests/vm/frame-evidence.py` is a small screenshot helper, not an evidence
framework. Keep logs and results compact; remove owned temporary VM disks and firmware state.
Cover the supported product options, including dual boot and the separate Marble GDM opt-in.
For dual boot, check the newly installed OS normally. For the pre-existing neighbor, require
preserved partition/EFI/file identities and real boot, not network/service health or the
availability of OS administration tools that the installer does not provision there.
Do not describe an unexecuted variant or a static assertion as a successful installation.

## Secrets

Private OpenPGP/SSH keys, tokens, passphrases, recovery phrases/shares, revocation material and local
configuration never enter tracked files, CI, test fixtures or generated source archives. Public
`arch-linux.gpg` and published fingerprints are permitted and must contain no secret packets.

## Tree-bound results

Every result belongs to the exact source tree and input hashes that produced it. Never transfer a
PASS from another commit, tree, package set, ISO, VM disk, firmware state or public asset. Re-run the
applicable check after any source change.

## Development and fixes

When a problem appears, diagnose it, make a focused correction, add or update its regression test,
and repeat the affected checks. Continue development without artificial attempt or cycle limits.
Do not retry an unchanged failure indefinitely or weaken a real disk, signature or secret-safety
test to obtain PASS. Diagnostic-tool failures should be reported separately from product failures.
Use pull requests in the same canonical checkout; record the accepted commit and tree before
building. Source changes require fresh affected tests and newly bound build and VM results.
Preserve historical results honestly; never transfer a PASS to another candidate or replace
published bytes or tags. Ask for external access or authority only when it is actually required,
and continue independent eligible work where possible.

## Pins and keys

Never change a source URL, hash, package pin, accepted ISO, fingerprint, signing subkey or trust
certificate automatically. Advisory maintenance may report drift, but a human-reviewed source
change and all affected tests are required.

## Release authorization

Do not sign with production material, create or mutate a GitHub release, deploy Pages, publish
packages, rotate keys or change repository settings without a separate explicit authorization.
Source-candidate completion is not `RELEASED`.
