# Architecture

## Entry point and runtime state

`arch-linux-installer.sh` is the product entry point. Before `main`, `runtime_init` applies the
runtime trust gates, then creates a private temporary directory and installs `ERR` and `EXIT` traps.
Runtime state is kept in `ARCH_LINUX_*` variables. `installer.conf` is a schema-1 data file and
`installer.log` contains subprocess progress; neither is source code.

In non-debug mode, no config, log or temporary runtime path may be initialized until the process is
root; the real current directory is root-owned mode `0700`; every ancestor is root-owned and not
group/world-writable; and the exact executing `${cwd}/arch-linux-installer.sh` is a root-owned
mode-`0700`, single-link regular file. The runtime binds and rechecks CWD/source device and inode
identities. The self-updater stages beside that protected source, verifies the replacement before
and after its atomic move, and never restarts from a temporary or unbound path.

## Setup phase

`main` performs the interactive setup:

1. Enforce the root and trusted-working-directory requirements.
2. Initialize the pinned `gum` UI and offer a signature-verified self-update.
3. Load a complete data-only config or collect values through `select_*` prompts.
4. Validate all properties without mutation, then offer interactive repair separately.
5. Show the exact disk and login summary and require final confirmation.

Every persisted selector calls `properties_generate`. The generator writes a private temporary file,
validates every value and atomically replaces `installer.conf`. The parser commits no runtime value
until the entire file, ownership, mode, size, exact 43-key set and types pass. The stored disk
identity and, for dual boot, both partition identities are part of that accepted state.

Release 1.0.6 checks dual-boot ESP collisions through the retained accepted partition
handle, inside a private read-only mount namespace. It checks the selected supported kernel,
reserved initramfs/fallback/microcode and bootloader write footprint, rejecting FAT case aliases
and unsafe ancestors. After the probe closes, identity/idle/handle checks run before root
mutation; mounted ESP identity/footprint is checked again before pacstrap. Valid existing
`loader/entries.srel` containing exactly `type1\n` is preserved. Refusal never edits neighbor
files or changes partition layout.

## Executor phase

Installation runs in this fixed sequence:

```text
exec_init_installation
  -> exec_prepare_disk
  -> exec_pacstrap_core
  -> exec_enable_multilib
  -> exec_install_aur_helper
  -> exec_install_bootsplash
  -> exec_install_housekeeping
  -> exec_install_shell_enhancement
  -> exec_install_graphics_driver
  -> exec_install_desktop
  -> exec_install_vm_support
  -> exec_finalize_arch_linux
```

Each executor owns a reviewable failure boundary. Work runs in a background subshell, writes to the
process log and is observed by the UI. Executors do not prompt: all choices are complete before the
chain starts. A non-zero stage stops subsequent stages. Release 1.0.6 explicitly aborts after
rejected destructive guards and failed/ambiguous idle probes, with actual-executor regressions.
[Validation](validation.md) records source checks and staged installation acceptance separately.

`exec_init_installation` verifies the Arch ISO hostname, UEFI mode, disabled Secure Boot, network,
clock and package-manager readiness before any target-disk mutation.

`exec_prepare_disk` reproduces the accepted path-and-identity snapshot immediately before disk
changes. It also requires the whole selected storage tree to be idle: no mounted descendant, active
swap, active non-partition holder, pre-existing `/mnt` mount or occupied installer mapper. Fresh
installs create the exact GPT/ESP/root layout. Dual boot preserves the partition table and existing
vfat ESP. LUKS2 is opened before Btrfs or ext4 formatting. No later stage may reinterpret the chosen
disk. The shared-ESP guard rejects existing kernel, entry and bootloader write-footprint collisions
before root mutation; it does not delete or rename neighboring files to make room.

## Chroot phase

`exec_pacstrap_core` creates the base system under `/mnt`; subsequent helpers execute through
`arch-chroot`. Package installation helpers keep argv boundaries. The AUR execution contract permits
metadata evaluation, source preparation and PKGBUILD code only under a dedicated disposable builder,
never the target account. The builder receives no installer secrets, password, supplementary groups,
sudo rule or package-manager authority. Its complete process tree must stay in a dedicated cgroup;
success and failure cleanup kill every descendant, prove the cgroup empty, then remove the account
and home. Strictly allowlisted `.SRCINFO` dependencies are installed in a separate root step;
`makepkg` runs with `--nodeps`, and only copied root-staged package bytes with the exact requested
identity are passed to `pacman -U`.
UID-emptiness and readback probes check `find` status as well as output; an inventory error
refuses the handoff. [SAFE-02](PLAN.md#safe-02--fail-closed-on-idle-probe-errors) records the correction.

The desktop stage installs only GNOME/GDM or is skipped for TTY. Stock configuration is applied
locally. Marble first verifies the project public certificate, exact fingerprints and strict
repository configuration, then performs a full `pacman -Syu`. Partial bootstrap state is removed if
that transaction fails before any project package is committed. Once a project package is installed,
the authenticated repository and trust path are retained so the package can be updated or removed;
the installer does not leave an unsigned or unauthenticated bridge.

The Marble profile also manages per-user GTK4/libadwaita CSS through a service ordered before
`gnome-session-pre.target`. Pacman supplies system-owned assets; the service replaces user CSS
without backups and cleans up only unchanged project wrappers. Its activation, compatibility and
removal rules are described in the [Marble lifecycle](marble.md#gtk4libadwaita-and-existing-installations).

For Btrfs with GRUB, the core stage builds the systemd initramfs with mkinitcpio's `sd-volatile`
contract. It configures grub-btrfs snapshot entries with `systemd.volatile=overlay` and read-only
root flags, so a selected snapshot is mounted as the lower layer while writes go to a temporary
overlay. The snapshot and its lower layer remain unchanged; `/home` and the separate ESP retain
their normal mount scope. Before the unchanged vendor `systemd-remount-fs` command runs, a
Btrfs/GRUB-only prestart helper adapts the volatile upper's `/` fstab row to overlay and retains
its generic VFS/security options. Other rows stay byte-identical. Normal Btrfs is a no-op;
unexpected topology, ambiguous rows and unsupported options fail closed. The readonly snapshot's
fstab is never rewritten. With a separate ESP, generated entries use the current matching kernel
and initramfs pair available in `/boot`; the VM additionally checks that the running kernel release
has a matching `/usr/lib/modules` tree in the selected root and in the initramfs payload. This is a
userspace snapshot rollback contract. A snapshot that predates a kernel update can contain only an
older module tree, so it requires a separately retained kernel/initramfs pair before it is a valid
historical-kernel rollback target; the installer does not synthesize that pair through an unverified
boot service.

Btrfs scrub is filesystem-scoped. A Btrfs installation enables one `btrfs-scrub@-.timer` for the
root filesystem; `/home` and `/.snapshots` are subvolumes and do not receive duplicate timers.

GNOME's one-time user initializer runs in the real user session. Required settings use a set,
readback and private combined log; an atomic per-step state file makes retries idempotent. The
success marker and removal of the autostart entry happen only after every required setting passes.
An unsuccessful run keeps the autostart entry for a later attempt. The desktop package set includes
`evolution-data-server` explicitly because GNOME's CalendarServer integration may load its `libecal`
library even when the rest of the GNOME group does not pull that dependency into a slim installation.

## Failure and recovery boundaries

- Preflight failure changes no target disk.
- Property failure returns to the editor without mutating validation state.
- Release 1.0.6 stops before mutation on rejected target guards and uncertain/error idle probes.
  Actual-executor failure injection and staged VM results remain separate evidence layers.
- Package or service failure stops its executor and leaves the log for diagnosis.
- Repository or signature failure leaves Stock install behavior available and does not authorize
  unsigned content.
- Ordinary unsupported Marble inputs remove project activation and return to Stock when deactivation
  succeeds. Unsafe/foreign state or a deactivation error can require manual inspection; the audit
  does not turn that error into successful runtime fallback.
- Final unmount or encrypted-volume closure is permitted only for resources recorded by private
  markers and re-bound to the accepted target snapshot. Chroot and reboot remain explicit user
  choices.
Release 1.0.6 blocks storage teardown until workers are proved quiet.
On failed teardown, it creates a separate private generated recovery directory
with reserialized validated ownership markers and a bounded nonsecret receipt. It does not retain
worker logs or reuse their writable runtime path; password state is cleared. Allocation/validation
failure refuses retention. Source race regressions cover late worker writes; successful VM
shutdown does not establish the outcome of every cancellation or busy-resource path.
