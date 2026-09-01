# QEMU acceptance harness

This directory contains the real-VM harness used only after source checks, one clean canonical Arch
package build and independent verification of the production-signed release assets are complete.

## Host requirements

- `qemu-system-x86_64` with KVM where available;
- OVMF firmware and a pristine VARS template;
- an accepted official Arch ISO;
- `qemu-img`, QEMU Guest Agent support, OpenSSL and Python 3;
- an absolute artifact/evidence directory outside the source tree.

`run.sh` creates a new qcow2 disk and copies independent OVMF VARS for every run. It refuses reused
run paths and binds all runs in one output root to one exact source/tree, ISO, production-signed
snapshot, build metadata and unsigned manifest. Use the same values for the three staged commands:

```bash
common=(
  --mode staged
  --iso "$ARCH_ISO" --iso-sha256 "$ARCH_ISO_SHA256"
  --output-root "$EVIDENCE_ROOT"
  --release-assets "$RELEASE_ASSETS"
  --release-version 1.0.0
  --snapshot-sha256 "$REPOSITORY_ARCHIVE_SHA256"
  --build-metadata-sha256 "$BUILD_METADATA_SHA256"
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256"
)
bash tests/vm/run.sh minimal-ext4-systemdboot "${common[@]}"
bash tests/vm/run.sh stock-gnome-btrfs-luks2-plymouth-grub "${common[@]}"
bash tests/vm/run.sh marble-gnome-btrfs-luks2-plymouth-systemdboot "${common[@]}"
```

The staged helper accepts only `arch-linux-repository-1.0.0.tar.zst` from the exact release-asset
closure. For every staged scenario it invokes the schema-2 release verifier with commit, tree,
build-metadata and unsigned-manifest hashes, checks the archive SHA-256, safely extracts it and
verifies the signed repository again. Minimal and Stock retain only its signed manifest and compact
object-hash map; Marble additionally serves the same public bytes over its disposable TLS transport.
The helper never creates a key or signs anything.

After the Release and Pages deployment have passed independent readback, run the public-only final
scenario. The payload contains harness identity and public URLs, not local installer, key, snapshot,
CA or repository bytes:

```bash
bash tests/vm/run.sh marble-gnome-btrfs-luks2-plymouth-systemdboot \
  --mode public \
  --iso "$ARCH_ISO" --iso-sha256 "$ARCH_ISO_SHA256" \
  --output-root "$EVIDENCE_ROOT" \
  --release-version 1.0.0 \
  --snapshot-sha256 "$REPOSITORY_ARCHIVE_SHA256" \
  --build-metadata-sha256 "$BUILD_METADATA_SHA256" \
  --unsigned-manifest-sha256 "$UNSIGNED_MANIFEST_SHA256" \
  --bootstrap-url https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.0/install.sh \
  --installer-url https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux-installer.sh \
  --public-key-url https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux.gpg \
  --pages-url 'https://snaplyze.github.io/arch-linux/repo/$arch'
```

The public guest independently downloads signed `RELEASE-SHA256SUMS`, the exact repository archive
and its detached signature from the canonical Release. It requires the signed/archive digest to
equal `--snapshot-sha256`, extracts only the archive manifest bytes, and requires the Pages manifest
and signature to be byte-identical. It then verifies schema-2 commit/tree/installer/build identities,
downloads all 23 signed-manifest objects from the canonical Pages HTTPS URL, checks every size/hash,
and verifies all six package plus both canonical database signatures with the exact public key.
Pages manifest bytes alone are not treated as proof of the enclosing archive digest.

Every completed or failed run retains a structured `result.json`; `FAIL` has a non-zero exit status
and exact failed phase and cannot be rendered as `PASS`. Retained evidence includes structured
identity/verdict data, input/tool hashes, the signed repository manifest and signature, its exact
per-package/database object map, a short compressed marker log, the final `qemu-img check`, and two
to four screenshots. Minimal retains two TTY frames; Stock retains LUKS, GDM password, desktop and
lock frames; Marble retains LUKS, GDM user-selection, GDM password and desktop frames. Stock also
proves `en_US.UTF-8` Language/Formats, `us,ru` layouts, preserved Super+Space plus Alt+Shift switching,
and all twelve Ptyxis Latin/Cyrillic shortcut pairs. Real password login, lock/unlock and the second
login are proved by HMP input plus QGA/logind session assertions, not screenshots alone.

After every PASS or FAIL, exact run-owned qcow2, OVMF VARS, payload ISO/tree, extracted repository
and TLS runtime are removed before credential scanning. The bounded scan reads only compact metadata
and evidence, never a qcow2, firmware image, ISO, socket or oversized raw log. Raw logs are then
reduced to the bounded marker log. No accepted Arch ISO copy is made. Cumulative retained evidence
under the common output root must remain at or below 500 MiB, and no run-owned QEMU/server process or
runtime credential may remain.

Do not report QEMU PASS from syntax checks or static review. A valid result requires the actual QEMU
process, fresh disk, independent firmware state and completed guest assertions.
