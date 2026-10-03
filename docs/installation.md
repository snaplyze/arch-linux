# Installation

## Prepare

Before using destructive paths, read the [open installer findings](PLAN.md#review-findings)
F-01–F-03. Guard/error-path and shared-ESP corrections are being implemented locally and are not present in the published 1.0.5 installer.
Identity metadata alone does not establish that these failure paths are safe.

Use the current official Arch Linux x86_64 ISO in UEFI mode. Disable Secure Boot, connect to the
internet and synchronize the system clock. Back up every important file before opening the
installer. Record each candidate disk's model, serial and capacity with `lsblk` where available,
and select the resolved device deliberately. A metadata-less virtio disk is supported through its
kernel disk sequence and boot-local identity, which the installer rechecks before changes. For a
metadata-less emulated SATA or SCSI disk, use virtio or configure stable model/serial metadata;
other metadata-less controller types are not supported.

Use the single release-pinned bootstrap command in the [README](../README.md). It downloads
`install.sh` from the documented immutable release tag (the verified example is `1.0.5`),
never from `main`, and the bootstrap then downloads and
verifies the release installer, checksum, detached signature, public certificate and both
fingerprint files. The verified installer starts as root from an exact root-owned mode-`0700`
single-link file inside its private root-owned mode-`0700` working directory. Every ancestor is
root-owned and not writable by group or others; the user-owned download directory is removed before
the installer starts.

For a non-destructive public-release or QEMU readback, run the same immutable bootstrap in
verification-only mode:

```bash
curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.5/install.sh | bash -s -- --verify-only
```

This mode completes the HTTPS download, checksum, certificate/fingerprint, secret-packet,
detached-signature and root-owned stable-copy checks, prints one installer SHA-256 success line,
and launches nothing. It narrowly removes both temporary directories before returning. Root can
use verification-only mode without a controlling terminal; a non-root caller still needs sudo
authority for the root-owned proof. Any other argument is rejected.

## Interactive flow

Use the README launch command without arguments. The bootstrap copies only the verified release
inputs into a private root-owned directory, removes its root-only GnuPG verification state, confirms
the exact six-file closure again, freezes the installer inode and digest, and changes to that
directory before execution. The installer creates the exact 43-key schema-1 `installer.conf` there.
The config is non-executable data and contains no password.

The installer asks for account, locale, console, filesystem, bootloader, target disk, encryption,
desktop and feature choices. Advanced tuning includes the kernel, mirror country, dual boot,
desktop extras, Btrfs tools, Samba, VM support and second layout. Review the final summary before
confirming the destructive stage.
Choose an ordinary unused account name, not `root`. Published 1.0.5 accepts that
reserved name and fails later during account creation. The source candidate now refuses known
reserved users/groups before disk work; [CONFIG-01](PLAN.md#config-01--reject-predictable-account-collisions)
records the tested correction and pending corrected-child installation.

## Minimal TTY

Choose the core preset or set `ARCH_LINUX_DESKTOP_ENABLED=false`. The result is a bootable Arch base
with NetworkManager and no display manager. Shell enhancement is independently optional; the core
acceptance scenario keeps it disabled. Marble trust and packages are never bootstrapped by this path.

## Stock GNOME

Choose the desktop preset and `stock` for both appearance prompts. GNOME, GDM and Wayland are the
only graphical path. Ptyxis is the desktop terminal. The system receives the reviewed editable
extension defaults, Bibata cursor, locale-matched GNOME Formats and optional Latin/Russian layouts
with verified shortcut alternatives. `evolution-data-server` is installed explicitly so the GNOME
CalendarServer integration has its `libecal` runtime dependency in slim installations.

At the first real user login, a one-time initializer applies the selected GNOME Formats and keyboard
settings. Each required operation is read back before it is recorded as complete. Its combined
stdout/stderr log, state and success marker are private to the user; a failed required operation
leaves the autostart entry in place for an idempotent retry, and the entry is removed only after the
success marker has been written.

For the accepted encrypted scenario, choose Btrfs and LUKS2, perform a real GDM password login, then
verify lock/unlock, reboot and `pacman -Syu`. GDM authentication is password-only.

## Marble

Choose `marble` only after Stock has been offered. The installer bootstraps the public project
certificate and strict signed repository, then installs the Marble Shell, unified
`arch-linux-colloid-gtk` package for GTK3/GTK4/libadwaita, Colloid icons and compatibility profile.
Marble automatically applies its GTK4/libadwaita CSS before GNOME session applications start,
replacing existing user `gtk.css` and `gtk-dark.css` without backups. Stock installs no Colloid
theme packages or project user CSS.

The next prompt separately offers Stock GDM first or `marble-experimental`. Experimental GDM is
accepted only for exact reviewed GNOME inputs; any ordinary compatibility mismatch leaves Stock GDM.
See [marble.md](marble.md) for ownership and fallback details.

## Filesystems and dual boot

A fresh install erases the selected whole disk, creates a GPT, a 1 GiB vfat ESP and a root
partition, then formats the root as Btrfs or ext4. LUKS2, when enabled, protects the root partition.

Dual boot does not rewrite the partition table or format the ESP. Select an existing vfat ESP and a
distinct root partition on the same exact disk. The root target is formatted. GRUB enables OS
detection and a visible menu; systemd-boot preserves vendor EFI directories but may install its
fallback loader. Back up the existing ESP and recovery material before proceeding.
Published 1.0.5 does not preflight shared boot-file collisions; do not use it for such a layout.
The source candidate inspects the accepted ESP handle in a private read-only mount namespace
before root encryption/formatting, rechecks identity and idle state afterward, and checks again
before package installation. It refuses existing selected-kernel/initramfs/fallback/microcode
files and its systemd-boot or GRUB write footprint, including FAT case variants and unsafe
ancestors. Custom kernels are refused for dual boot because their write footprint is unknown.
There is no automatic deletion, renaming or partition redesign to resolve a collision.
The new VM fixture tests refusal with whole ESP/root hashes, then a separately noncolliding
neighbor through update and real boot. Actual corrected-child VM execution remains pending
[SAFE-03 / RELEASE-01](PLAN.md#safe-03--preserve-neighbor-esp-bytes).

The generated config binds the selected disk to an opaque identity derived from stable device
properties. Dual boot additionally binds both existing partitions; fresh installs require those
partition identities to remain empty until the installer creates the layout. The executor reproduces
the accepted identity snapshot immediately before mutation and refuses a disk with mounted
descendants, active swap, active holders, an existing `/mnt` mount or an occupied `cryptroot`
mapping. Published 1.0.5 retains [F-01/F-02](PLAN.md#review-findings) failure-path gaps. The corrected
source explicitly aborts on failed inventories and rejected later handles; real VM acceptance
is separate from its executed source regressions.
Cleanup may release only mounts and mappings marked as created by that exact accepted run.

## Completion

After successful installation, choose reboot, unmount or a temporary chroot. Keep the generated
data-only config and local installer log private and only as long as useful. The log is not a
general-purpose sanitized artifact: review it and remove credentials, identifying disk information
and other private data before sharing any excerpt. Verify the first boot, network, failed-unit count
and full system update.
On failure or cancellation, do not assume all resources were released. Published 1.0.5 retains
the unsafe reap/cleanup ordering from [F-13](PLAN.md#review-findings). Corrected source requires
proved worker quiescence before storage teardown and preserves only validated operational
markers in a separate private recovery directory after failure, clearing password/runtime logs.
Real cancellation/cleanup VM acceptance remains under RELEASE-01.
Do not infer ownership or manually remove mounts/mappers from a name alone.
