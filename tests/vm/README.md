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

Every installed-system `firstboot` and `postreboot` launch starts paused with QEMU `-S`. The harness
binds one direct-framebuffer recorder to the exact QEMU PID/start identity and exact QMP peer, waits
for a strict P6 frame and authenticated `READY` ledger entry while QMP reports
`prelaunch`/not-running, and only then sends `cont`. This bounded boot section records through the
verified visual state and then closes. Immediately before reboot or poweroff, a distinct recorder
section reaches `READY`, records `shutdown-armed` before the guest transition is scheduled and stops
only after that exact QEMU process exits. The non-visual package-update interval between sections is
not claimed as visual evidence. Each append-only ledger orders frames by phase, section, sequence and
monotonic time and binds each temporary lossless compressed frame by SHA-256; ordered contact sheets
preserve every sample in sequence.

For Minimal, `qga_verify` must first prove the installed phase, multi-user target, active tty1 getty,
active tty and health prerequisites. Only then may the harness issue the exact allowlisted,
phase-specific non-secret framebuffer challenge. The challenge contains no Enter/Return, performs no
login or guest repair and must not use Ctrl+Alt+F1. A phase is ineligible unless the ledger proves the
strict order pre-challenge frame, challenge record and later post-challenge frame, with a non-zero
direct-framebuffer delta between the bound frames. It is not sufficient for two arbitrary frames to
differ, and a forced tty switch is not evidence that the guest naturally reached tty1.

The automated run result is provisional until independent visual review. The reviewer examines all
ordered contact sheets and the full-resolution candidate frames. If a contact-sheet cell is
uncertain, derive its zero-based sequence from the fixed 10-by-10 ordering, resolve that sequence in
the append-only ledger, verify the compressed object through the manifest's sole `fileHashes` map,
and reconstruct the full-resolution PPM only into a new private review directory outside the run
evidence. For example, for a first-boot/boot sequence:

```bash
stem=firstboot-boot
ledger="$RUN_ROOT/evidence/$stem-frame-ledger.jsonl"
binding="$(jq -er --argjson sequence "$SEQUENCE" '
  select(.e == "sample" and .n == $sequence) |
  [.ppm, .raw, .rawSha] | @tsv
' "$ledger")"
[ "$(printf '%s\n' "$binding" | wc -l)" -eq 1 ]
IFS=$'\t' read -r ppm_sha raw_name raw_sha <<EOF
$binding
EOF
raw_relative="frame-raw/$stem/$raw_name"
raw="$RUN_ROOT/$raw_relative"
manifest_sha="$(jq -er --arg path "$raw_relative" '.fileHashes[$path] // empty' \
  "$RUN_ROOT/evidence/frame-evidence-manifest.json")"
[ "$manifest_sha" = "$raw_sha" ]
[ "$(sha256sum -- "$raw" | awk '{print $1}')" = "$manifest_sha" ]
install -d -m 0700 -- "$PRIVATE_REVIEW_DIR"
output="$PRIVATE_REVIEW_DIR/firstboot-boot-$SEQUENCE.ppm"
gzip -cd -- "$raw" >"$output"
chmod 0600 -- "$output"
[ "$(sha256sum -- "$output" | awk '{print $1}')" = "$ppm_sha" ]
```

The private review directory must not be inside `$RUN_ROOT`; remove it after the review. OCR may
assist triage but is not proof of a tty, GDM state, login, desktop or clean shutdown. The signed-off
manual receipt records the verdict and binds the exact source commit, source tree, run ID and sealed
manifest. Its single `fileHashes` map binds every ledger, contact sheet, raw object and selected frame.
Screenshot count, an automated `result.json`, QGA, a frame delta or OCR alone cannot produce QEMU
PASS. After the receipt is complete, remove unselected raw frames and retain only the receipt,
manifest, compact ledgers and contact sheets, and two to four selected frames.

The harness leaves immutable `evidence/manual-review-template.json`, `result.json` with
`PENDING_VISUAL_REVIEW`, and the bounded `frame-raw/` tree. After review, derive a new
`evidence/manual-review-receipt.json` from the template without editing the template. Set `REVIEWER`
to the reviewer identity, then construct and read back the bounded receipt as follows. This fills
`pendingResultSha256` from the exact existing `result.json`, keeps `notes` empty, sets all five
existing confirmations to the JSON boolean `true`, and leaves every other template field unchanged:

```bash
: "${RUN_ROOT:?set the exact absolute run root}"
: "${REVIEWER:?set the reviewer identity}"
reviewed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
result_sha="$(sha256sum -- "$RUN_ROOT/result.json" | awk 'NF == 2 { print $1 }')"
[[ "$result_sha" =~ ^[a-f0-9]{64}$ ]]
receipt="$RUN_ROOT/evidence/manual-review-receipt.json"
[ ! -e "$receipt" ]
receipt_tmp="$(mktemp "$RUN_ROOT/evidence/.manual-review-receipt.XXXXXX")"
trap 'rm -f -- "$receipt_tmp"' EXIT
jq -cS --arg reviewer "$REVIEWER" --arg reviewed_at "$reviewed_at" --arg result_sha "$result_sha" '
  .verdict = "PASS" |
  .reviewer = $reviewer |
  .reviewedAt = $reviewed_at |
  .pendingResultSha256 = $result_sha |
  .confirmations |= with_entries(.value = true) |
  .notes = ""
' "$RUN_ROOT/evidence/manual-review-template.json" >"$receipt_tmp"
chmod 0600 -- "$receipt_tmp"
[ "$(wc -c <"$receipt_tmp")" -le 8388608 ]
jq -e --arg reviewer "$REVIEWER" --arg reviewed_at "$reviewed_at" --arg result_sha "$result_sha" '
  .verdict == "PASS" and .reviewer == $reviewer and .reviewedAt == $reviewed_at and
  .pendingResultSha256 == $result_sha and .notes == "" and
  (.confirmations | type == "object" and length == 5 and all(.[]; . == true))
' "$receipt_tmp" >/dev/null
ln -- "$receipt_tmp" "$receipt"
rm -- "$receipt_tmp"
trap - EXIT
[ "$(stat -Lc '%u:%a:%h' -- "$receipt")" = "$(id -u):600:1" ]
```

Finalize from the same clean frozen source checkout with the exact run path:

```bash
python3 -I tests/vm/frame-evidence.py finalize-review \
  --run-root "$RUN_ROOT"
```

The helper derives every pathname from the exact run root, re-hashes the sealed manifest closure,
binds the pending-result and completed-receipt hashes, durably stages the positive verdict, then
removes only the exact private raw tree and enforces the cumulative 500 MiB permanent budget. Until
`visual-review-verdict.json` says `PASS`, the scenario is not QEMU PASS.

After every PASS or FAIL, exact run-owned qcow2, OVMF VARS, payload ISO/tree, extracted repository
and TLS runtime are removed before credential scanning. The bounded scan reads only compact metadata
and evidence, never a qcow2, firmware image, ISO, socket or oversized raw log. Raw logs are then
reduced to the bounded marker log. No accepted Arch ISO copy is made. Cumulative retained evidence
under the common output root must remain at or below 500 MiB, and no run-owned QEMU/server process or
runtime credential may remain.

Do not report QEMU PASS from syntax checks or static review. A valid result requires the actual QEMU
process, fresh disk, independent firmware state, completed guest assertions, complete direct-frame
chronology and delta, and the bound independent manual-review receipt.
