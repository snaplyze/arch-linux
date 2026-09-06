# Installation

## Prepare

Use the current official Arch Linux x86_64 ISO in UEFI mode. Disable Secure Boot, connect to the
internet and synchronize the system clock. Back up every important file before opening the
installer. Record each candidate disk's model, serial and capacity with `lsblk` and select the
resolved device deliberately.

Use the single release-pinned bootstrap command in the [README](../README.md). It downloads
`install.sh` from the immutable `1.0.1` tag, never from `main`, and the bootstrap then downloads and
verifies the release installer, checksum, detached signature, public certificate and both
fingerprint files. The verified installer starts as root from an exact root-owned mode-`0700`
single-link file inside its private root-owned mode-`0700` working directory. Every ancestor is
root-owned and not writable by group or others; the user-owned download directory is removed before
the installer starts.

For a non-destructive public-release or QEMU readback, run the same immutable bootstrap in
verification-only mode:

```bash
curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.1/install.sh | bash -s -- --verify-only
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

## Minimal TTY

Choose the core preset or set `ARCH_LINUX_DESKTOP_ENABLED=false`. The result is a bootable Arch base
with NetworkManager and no display manager. Shell enhancement is independently optional; the core
acceptance scenario keeps it disabled. Marble trust and packages are never bootstrapped by this path.

## Stock GNOME

Choose the desktop preset and `stock` for both appearance prompts. GNOME, GDM and Wayland are the
only graphical path. Ptyxis is the desktop terminal. The system receives the reviewed editable
extension defaults, Bibata cursor, locale-matched GNOME Formats and optional Latin/Russian layouts
with verified shortcut alternatives.

For the accepted encrypted scenario, choose Btrfs and LUKS2, perform a real GDM password login, then
verify lock/unlock, reboot and `pacman -Syu`. GDM authentication is password-only.

## Marble

Choose `marble` only after Stock has been offered. The installer bootstraps the public project
certificate and strict signed repository, then installs the Marble Shell, Colloid GTK3/icons and
compatibility profile. GTK4/libadwaita CSS stays Stock.

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

The generated config binds the selected disk to an opaque identity derived from stable device
properties. Dual boot additionally binds both existing partitions; fresh installs require those
partition identities to remain empty until the installer creates the layout. The executor reproduces
the accepted identity snapshot immediately before mutation and refuses a disk with mounted
descendants, active swap, active holders, an existing `/mnt` mount or an occupied `cryptroot`
mapping. Cleanup may release only mounts and mappings marked as created by that exact accepted run.

## Completion

After successful installation, choose reboot, unmount or a temporary chroot. Keep the generated
data-only config and local installer log private and only as long as useful. The log is not a
general-purpose sanitized artifact: review it and remove credentials, identifying disk information
and other private data before sharing any excerpt. Verify the first boot, network, failed-unit count
and full system update.
