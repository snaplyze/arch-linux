# QEMU acceptance harness

This directory contains the real-VM harness used only after source checks, one clean canonical Arch
package build and independent verification of the production-signed release assets are complete.

## Host requirements

- `qemu-system-x86_64` with working KVM;
- OVMF firmware and a pristine VARS template;
- an accepted official Arch ISO;
- `qemu-img`, QEMU Guest Agent support, OpenSSL and Python 3;
- an absolute artifact/evidence directory outside the source tree.

On a GitHub Linux runner, create a distinct mode-`0700` output directory for each matrix job, make
`/dev/kvm` readable and writable by the runner, then run the preflight for that exact scenario before
`run.sh`. The preflight verifies the accepted ISO digest, runner clock, available RAM and storage,
KVM access and a stopped QEMU KVM-acceleration probe. It is safe to run before release assets are
downloaded into the job workspace.

```bash
install -d -m 0700 -- "$RUNNER_TEMP/qemu-evidence"
sudo chmod a+rw /dev/kvm
bash tests/vm/preflight.sh \
  --scenario marble-gnome-btrfs-luks2-plymouth-systemdboot \
  --iso "$ARCH_ISO" --iso-sha256 "$ARCH_ISO_SHA256" \
  --output-root "$RUNNER_TEMP/qemu-evidence"
```

`run.sh` creates a new qcow2 disk and copies independent OVMF VARS for every run. It refuses reused
run paths and binds all runs in one output root to one exact source/tree, ISO, production-signed
snapshot, build metadata and unsigned manifest. Commands sharing an output root must run
sequentially: the final retention measurement includes that entire root. For concurrent scenarios,
give each one its own generated output root, keeping all accepted source/ISO/package hashes equal;
otherwise another live VM disk would be counted as retained evidence. These are disposable VM
data directories, not additional development checkouts.
Use the same values for the three sequential staged commands:

```bash
common=(
  --mode staged
  --iso "$ARCH_ISO" --iso-sha256 "$ARCH_ISO_SHA256"
  --output-root "$EVIDENCE_ROOT"
  --release-assets "$RELEASE_ASSETS"
  --release-version "$RELEASE_VERSION"
  --snapshot-sha256 "$REPOSITORY_ARCHIVE_SHA256"
  --build-metadata-sha256 "$BUILD_METADATA_SHA256"
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
)
bash tests/vm/run.sh minimal-ext4-systemdboot "${common[@]}"
bash tests/vm/run.sh stock-gnome-btrfs-luks2-plymouth-grub "${common[@]}"
bash tests/vm/run.sh marble-gnome-btrfs-luks2-plymouth-systemdboot "${common[@]}" \
  --legacy-release-assets "$LEGACY_RELEASE_ASSETS" \
  --legacy-release-version "$(jq -r .version tests/vm/legacy-marble-release.json)" \
  --legacy-snapshot-sha256 "$(jq -r .snapshotSha256 tests/vm/legacy-marble-release.json)"
```

The main staged Marble case additionally requires the ten public legacy assets from the immutable
release recorded in `legacy-marble-release.json`: build metadata, unsigned manifest, signed
`RELEASE-SHA256SUMS`, the three public trust files, and the repository archive with its checksum and
signature. Place only those files in `$LEGACY_RELEASE_ASSETS`. The harness verifies their signatures,
hashes and exact file set before using the old profile and GTK3 packages. It compares the migrated
package set with the fresh candidate, then tests a new ordinary user's real GDM login and light/dark
application startup. This establishes package migration; it does not rerun the old installer or
prove visual equivalence from process checks. The release workflow downloads these same inputs.

The same staged arguments also support these complementary cases:

```bash
bash tests/vm/run.sh stock-gnome-ext4-systemdboot "${common[@]}"
bash tests/vm/run.sh stock-gnome-btrfs-systemdboot "${common[@]}"
bash tests/vm/run.sh stock-gnome-btrfs-grub "${common[@]}"
bash tests/vm/run.sh stock-gnome-btrfs-luks2-plymouth-systemdboot "${common[@]}"
bash tests/vm/run.sh marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm "${common[@]}"
bash tests/vm/run.sh minimal-dualboot-ext4-systemdboot "${common[@]}"
```

The last case prepares a small neighboring Linux installation inside the disposable VM only.
It reuses its EFI partition, selects partition 3 for the new Arch root, checks that the neighboring
files and boot entry survive, and actually boots both systems. This is a Linux dual-boot test,
not a claim to have installed or tested Windows. No host disk is prepared by this command.
Network and service health are required in the newly installed OS. The pre-existing neighbor
is checked for preservation and real boot, not its DNS, service health or administration tools;
the installer does not provision those in that OS.

The main staged Marble case additionally exercises GDM administrator-profile fallback and restore,
then real pacman removal and reinstallation followed by password logins. The Stock-GDM Marble case
checks that the optional GDM package is absent and the greeter retains its Stock environment.

The staged helper accepts only `arch-linux-repository-$RELEASE_VERSION.tar.zst` from the exact release-asset
closure. For every staged scenario it invokes the schema-2 release verifier with commit, tree,
build-metadata and unsigned-manifest hashes, checks the archive SHA-256, safely extracts it and
verifies the signed repository again. Minimal and Stock retain only its signed manifest and compact
object-hash map; Marble additionally serves the same public bytes over its disposable TLS transport.
The helper never creates a key or signs anything.

After the Release and Pages deployment have passed independent readback, run the public-only final
scenario. The payload contains harness identity and public URLs, not local installer, key, snapshot,
CA or repository bytes:

Public mode resolves product identity from the annotated release tag, not from the current test
checkout. A reviewed test-only fix may run from a later clean descendant, provided installer,
bootstrap, packages, repository/trust and maintenance inputs are unchanged. The retained
`harness-source.txt` records both commits/trees; `harness.sha256` records the actual test bytes.
This does not transfer an old PASS to a new product or replace released assets. The project
repository still requires database signatures even though official Arch repositories normally
use their own `DatabaseOptional` policy.

```bash
bash tests/vm/run.sh marble-gnome-btrfs-luks2-plymouth-systemdboot \
  --mode public \
  --iso "$ARCH_ISO" --iso-sha256 "$ARCH_ISO_SHA256" \
  --output-root "$EVIDENCE_ROOT" \
  --release-version "$RELEASE_VERSION" \
  --snapshot-sha256 "$REPOSITORY_ARCHIVE_SHA256" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256" \
  --bootstrap-url "https://raw.githubusercontent.com/snaplyze/arch-linux/$RELEASE_VERSION/install.sh" \
  --installer-url "https://github.com/snaplyze/arch-linux/releases/download/$RELEASE_VERSION/arch-linux-installer.sh" \
  --public-key-url "https://github.com/snaplyze/arch-linux/releases/download/$RELEASE_VERSION/arch-linux.gpg" \
  --pages-url 'https://snaplyze.github.io/arch-linux/repo/$arch'
```

The public guest independently downloads signed `RELEASE-SHA256SUMS`, the exact repository archive
and its detached signature from the canonical Release. It requires the signed/archive digest to
equal `--snapshot-sha256`, extracts only the archive manifest bytes, and requires the Pages manifest
and signature to be byte-identical. It then verifies schema-2 commit/tree/installer/build identities,
downloads all 23 signed-manifest objects from the canonical Pages HTTPS URL, checks every size/hash,
and verifies all six package plus both canonical database signatures with the exact public key.
Pages manifest bytes alone are not treated as proof of the enclosing archive digest.

By default, `run.sh` attaches the target as `virtio-blk-pci` without serial, vendor or product fields.
The guest therefore proves the trusted virtio sysfs ancestry, kernel `diskseq` and current boot ID
used by the installer identity fallback; it never treats a missing physical-disk identity as valid.
`--target-disk-metadata identified` restores the older serial/model fixture only for diagnosis.

## Results and diagnosis

Every completed or failed run retains a structured `result.json`: `PASS` means the actual
functional scenario and cleanup completed; `FAIL` includes a non-zero exit status and failed phase.
The run retains input/tool hashes, the signed repository manifest and object hashes, a short
compressed installer log, functional assertions and `qemu-img check`.

The runner performs real password input and checks the resulting `gdm-password` Wayland session,
lock/unlock, package update, reboot and second login. Stock also checks Language/Formats, input
layouts, switching and terminal shortcuts. Minimal checks its installed multi-user system and TTY.
QGA runs diagnostics; it does not log the user in or replace the installation.

If the installer exits before creating its log (for example, a dependency download fails), the
guest reports its actual exit status and powers off. Missing diagnostic logs must not hide that
failure or leave the host waiting for an installation that has already stopped.

`frame-evidence.py` captures ordinary diagnostic screenshots from the actual QEMU display. They
are optional: capture errors are warnings, not OS failures. There is no continuous recorder, timing
threshold, pixel challenge, contact sheet or separate manual receipt. Inspect screenshots when they
help explain a functional problem; do not infer successful login from a screenshot alone.

After every PASS or FAIL, the runner removes its qcow2, OVMF VARS, payload, extracted repository and
TLS runtime. It scans only compact metadata/logs for credentials and checks no owned QEMU/server
process remains. It does not copy the accepted Arch ISO. Keep retained results compact and outside
the checkout.

When a functional check fails, diagnose and fix the cause and rerun the affected scenario with fresh
VM state. Do not reuse an old PASS for changed source or packages. Run the complementary cases above
before claiming coverage of those options; support in the CLI is not an executed VM PASS.

## Unified Colloid GTK acceptance

Stock assertions require no Colloid theme packages or project GTK4 CSS imports. Marble assertions
check the unified `arch-linux-colloid-gtk` package, reviewed GTK4 payload and automatic user service
activation. These checks do not establish legacy package replacement or application rendering.
Run the separate [GTK migration acceptance](../../docs/testing.md#marble-gtk-migration-acceptance)
against previous and candidate signed snapshots, including fresh-versus-upgraded parity, a new user
login and light/dark application observations. Record unexecuted checks as `NOT_RUN_ENVIRONMENT`.
