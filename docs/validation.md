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
The staged inputs are the exact 14 Phase-A assets, whose signed checksum manifest covers exactly 12
non-self files. Finalization is allowed only after all three reviewed PASS verdicts and preserves all
14 bytes while adding signed acceptance JSON and evidence archive for exact 18.

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

Each installed-system `firstboot` and `postreboot` process starts paused with `-S`. Before `cont`, an
exact-head direct-framebuffer recorder must bind the exact QEMU PID/start identity and QMP peer and
write its first strict P6 frame and `READY` while QMP reports `prelaunch`/not-running. It records the
bounded boot section through the verified visual state. A distinct recorder section starts
immediately before reboot/poweroff, records `shutdown-armed` before the transition request, and ends
only after the exact PID exits. For Minimal,
phase-specific `qga_verify` and framebuffer prerequisites precede an allowlisted non-secret challenge
that has no Enter/Return, does not log in or repair the guest and never sends Ctrl+Alt+F1. The ledger
must bind a strict pre-challenge, challenge and post-challenge chronology and a non-zero framebuffer
delta for both first boot and post-reboot. Arbitrary differing screenshots do not satisfy this gate.

Automated success is provisional. An independent manual review of the ordered contact sheets and
full-resolution selected frames is mandatory; uncertain manifest-bound frames are reconstructed from
the temporary lossless raw closure into a separate private directory before finalization. OCR may
assist navigation but is not evidence. The receipt binds the exact source commit/tree, run ID and
frame-evidence manifest; its one `fileHashes` map binds every ledger, contact sheet, temporary raw
object and selected-frame name/hash together with the fixed sheet geometry; the manifest
does not contain per-cell records. Screenshot count, automated verdicts, QGA, delta or OCR alone never prove QEMU PASS.
After review, remove unselected raw frames and retain the receipt, compact manifest/ledgers/contact
sheets and two to four selected frames within the same 500 MiB cumulative budget.

## Release evidence

Contains signed repository/release-asset verification, immutable release asset identities, Pages
readback and the final public VM result. It is created only after the corresponding operations and
cannot retroactively change source/build/QEMU results.
The acceptance JSON binds the commit/tree/canonical source SHA-256, build/unsigned/snapshot hashes,
the exact Phase-A name/hash/size map and aggregate, its manifest hash, three PASS verdicts,
evidence no larger than 500 MiB and `deferred=[]`.

The final public Marble/GDM VM carries no local product bytes: it downloads the immutable tagged bootstrap, verifies the Release installer and
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
