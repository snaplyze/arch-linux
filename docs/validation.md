# Validation and evidence

Validation is layered and tree-bound. No old report or status document is evidence for the current
source candidate.

## Source evidence

Contains exact source identity and the commands/statuses for syntax, version, bootstrap, static,
function, Marble, package metadata, documentation, portability, secret, agent, maintenance,
repository fixture and ShellCheck tests. It must not include generated package or VM outputs.

## Build evidence

Contains the clean Arch environment identity, canonical unsigned package closure,
`UNSIGNED-SHA256SUMS`, package metadata and verifier result. Monthly A+B comparison is advisory and
is recorded separately from the required canonical release build.

## QEMU evidence

Contains the accepted ISO identity, QEMU/OVMF versions, new qcow2 and independent VARS identities,
scenario configuration, installer/repository identities and a structured result. The exact release
matrix is Minimal TTY/ext4/systemd-boot, Stock GNOME/Btrfs/LUKS2/GRUB and
Marble/Btrfs/LUKS2/systemd-boot with the separate experimental Marble GDM opt-in. All three staged
runs bind the same independently verified production-signed repository archive, source commit/tree,
build-metadata hash, unsigned-manifest hash and frozen Arch ISO hash.

Each scenario retains two to four necessary screenshots, a short compressed marker log, exact input
and tool hashes, the production-signed repository manifest/signature, its exact per-package/database
object hashes, a structured PASS or FAIL verdict and the final `qemu-img check`. A FAIL verdict has a
non-zero exit status and exact failed phase. HMP password input and QGA/logind assertions must prove
real `gdm-password` Wayland login, lock/unlock, update, reboot and the second login; Stock also proves
`en_US.UTF-8` Language/Formats, `us,ru` layouts, both GNOME switch directions and all twelve Ptyxis
Latin/Cyrillic shortcut pairs. Screenshots or QGA alone are insufficient. After each scenario,
delete the exact run-owned qcow2, OVMF VARS, payload ISO/tree, extracted repository and TLS runtime
before scanning only bounded compact metadata/evidence for credentials; never grep VM disks,
firmware, ISOs, sockets or oversized logs. Verify that no run-owned QEMU/server process remains.
Total permanent evidence for the acceptance cycle is at most 500 MiB and contains no password,
private key, passphrase or recovery material.

## Release evidence

Contains signed repository/release-asset verification, immutable release asset identities, Pages
readback and the final public VM result. It is created only after the corresponding operations and
cannot retroactively change source/build/QEMU results. The final public Marble/GDM VM carries no
local product bytes: it downloads the immutable tagged bootstrap, verifies the Release installer and
public key, executes only that verified installer, and obtains project packages and databases from
the exact public Pages URL under `PackageRequired DatabaseRequired TrustedOnly`. Public readback
verifies signed `RELEASE-SHA256SUMS`, the exact archive digest and signature, byte equality between
the archive and Pages manifests/signatures, schema-2 source/build identity, all 23 Pages object
hashes/sizes, and all package/canonical-database signatures. Merely echoing an expected archive hash
or validating an unbound Pages manifest is not public readback evidence.

## Status discipline

Use exactly one status per check: `EXECUTED_PASS`, `EXECUTED_FAIL`, `REVIEWED_ONLY`,
`NOT_RUN_ENVIRONMENT` or `NOT_APPLICABLE`. Record exact commands for executed tests. Absence of a
required environment is not a PASS.
