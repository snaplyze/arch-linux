# Testing

A test result is valid only for the exact source tree and inputs that produced it. Use one of these
statuses: `EXECUTED_PASS`, `EXECUTED_FAIL`, `REVIEWED_ONLY`, `NOT_RUN_ENVIRONMENT` or
`NOT_APPLICABLE`.

## Required source suite

```bash
bash tests/source-tests.sh
```

It executes:

- Bash syntax and installer version smoke;
- release-bootstrap regression fixtures;
- static installer and trust-policy checks;
- installer function behavior, including disk/destructive and AUR boundaries;
- Marble install, upgrade, remove, reinstall and fallback simulation;
- package metadata and source pin checks;
- documentation/local-link, portability and secret scans;
- agent contract and advisory-maintenance checks;
- signed-repository positive fixtures, negative signatures and malicious archive fixtures;
- ShellCheck.

Individual commands are listed in [AGENTS.md](../AGENTS.md). Static reading must be reported as
`REVIEWED_ONLY`, never as an executed test.

## Clean Arch package build

The required release build runs once in a clean Arch environment under a non-root temporary builder:

```bash
repository/build-packages.sh "$ARTIFACT_DIR/unsigned"
repository/verify-unsigned-build.sh "$ARTIFACT_DIR/unsigned"
```

The scheduled A+B comparison is advisory:

```bash
repository/compare-package-builds.sh "$ARTIFACT_DIR/build-a" "$ARTIFACT_DIR/build-b"
```

If no genuine clean Arch environment with `makepkg` is available, report
`NOT_RUN_ENVIRONMENT`; do not replace it with metadata inspection.

## Repository signatures

`bash tests/repository-checks.sh` uses an ephemeral test key only. Repository and package manifests
remain schema 2. The test's release-host result is the separate schema-1 full-namespace,
ten-scenario, signer-passed, no-deferral acceptance marker; it also proves repository negatives plus
exact-14 Phase-A and exact-18 finalized closures. Release-host acceptance additionally runs
`bash tests/repository-checks.sh --require-full-namespace`, the exact empty-derived root
`tests/publication-root-check.sh` command from `AGENTS.md`, and ordinary plus privileged
`tests/keyring-rotation-checks.sh`. These fixtures do not constitute production signing.

## QEMU acceptance

Do not report QEMU PASS unless all of these are real and fresh:

- `qemu-system-x86_64`;
- the accepted Arch ISO;
- a new qcow2 disk per scenario;
- an independent OVMF VARS copy per scenario;
- captured installer/repository identities and scenario evidence.

Required scenarios are Minimal TTY, Stock GNOME, and Marble plus separate Marble GDM. A
release acceptance run uses the exact combinations Minimal/ext4/systemd-boot,
Stock/Btrfs/LUKS2/GRUB and Marble/Btrfs/LUKS2/systemd-boot. Every run is a fresh install with KVM,
a new qcow2 and an independent OVMF VARS copy; all three consume one exact independently verified
production-signed snapshot. Real login, lock/unlock, `pacman -Syu`, reboot, repeated login, package
integrity, zero failed units, clean shutdown and `qemu-img check` are mandatory. A representative
dual-boot path is checked separately. See [VM commands](../tests/vm/README.md).
Stock additionally checks Language/Formats, input layouts and terminal shortcuts. Every run retains
its input identities, a compact installer log, functional assertions, `qemu-img check` and a
structured PASS or FAIL. Screenshots are optional diagnostic aids: missing a frame or a slow capture
does not turn a successful installation into a product failure.

The runner performs actual GDM password input, verifies the resulting Wayland session and exercises
lock/unlock and the second login. QGA inspects the installed system but does not manufacture a login.
Minimal must reach its working TTY without a forced VT switch. There is no continuous recorder,
frame-timing threshold, pixel challenge or manual-review receipt. If a functional check fails,
investigate and fix the cause, add a regression check, and rerun the affected checks on the new inputs.
Keep source, package and actual VM results distinct.

## Release/public acceptance

Production offline signing, immutable Release creation, verified Pages deployment and the final
public VM readback are separate stages. Source or synthetic signature tests cannot be promoted to
those statuses. Staged QEMU consumes only the exact 14-file Phase-A closure. After three functional
PASS verdicts, launcher `finalize` preserves those 14 bytes and adds signed acceptance JSON/evidence
for exact 18; installer-release Pages deployment accepts only that final closure. Later
[package-only updates](../repository/README.md#package-only-updates) use a separately tagged,
verified 14-file snapshot with the installer unchanged. The final public VM uses only the tagged public bootstrap, immutable Release
installer/key assets and the public Pages repository; local installer, key, snapshot, CA and
repository bytes are forbidden from its payload. Inside the public guest, signed
`RELEASE-SHA256SUMS` binds the expected archive digest, the archive detached signature is verified,
and its manifest/signature must be byte-identical to Pages. The guest validates schema-2
commit/tree/installer/build identities, all 23 Pages object sizes/hashes and all package/database
signatures before `PUBLIC_RELEASE_PAGES_BINDING_PASS` may be recorded.
