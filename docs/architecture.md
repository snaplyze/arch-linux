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
chain starts. A non-zero stage stops subsequent stages.

`exec_init_installation` verifies the Arch ISO hostname, UEFI mode, disabled Secure Boot, network,
clock and package-manager readiness before any target-disk mutation.

`exec_prepare_disk` reproduces the accepted path-and-identity snapshot immediately before disk
changes. It also requires the whole selected storage tree to be idle: no mounted descendant, active
swap, active non-partition holder, pre-existing `/mnt` mount or occupied installer mapper. Fresh
installs create the exact GPT/ESP/root layout. Dual boot preserves the partition table and existing
vfat ESP. LUKS2 is opened before Btrfs or ext4 formatting. No later stage may reinterpret the chosen
disk.

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

The desktop stage installs only GNOME/GDM or is skipped for TTY. Stock configuration is applied
locally. Marble first verifies the project public certificate, exact fingerprints and strict
repository configuration, then performs a full `pacman -Syu`. Partial bootstrap state is removed if
that transaction fails before any project package is committed. Once a project package is installed,
the authenticated repository and trust path are retained so the package can be updated or removed;
the installer does not leave an unsigned or unauthenticated bridge.

## Failure and recovery boundaries

- Preflight failure changes no target disk.
- Property failure returns to the editor without mutating validation state.
- Disk-target path, identity or idle-state mismatch fails before `wipefs`, partitioning or
  formatting.
- Package or service failure stops its executor and leaves the log for diagnosis.
- Repository or signature failure leaves Stock install behavior available and does not authorize
  unsigned content.
- Unsupported Marble inputs remove only project activation and return the effective appearance to
  Stock; they do not block the system upgrade.
- Final unmount or encrypted-volume closure is permitted only for resources recorded by private
  markers and re-bound to the accepted target snapshot. Chroot and reboot remain explicit user
  choices.
