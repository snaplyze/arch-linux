# Changelog

## Unreleased

- Keep four 32-bit codec/SDL libraries that moved to AUR: build exact reviewed
  sources through the isolated builder, preserving upstream checksums and source
  signatures, library payload checks, and the SDL2 virtual-provider dependency.
- Resolve official package transactions before retrying downloads; report an
  unresolved target immediately instead of repeating the same invalid request.

- Keep the private bootstrap umask out of target-system file creation; preserve
  pacman download-user access without disabling its sandbox or changing DNS.
- Reuse the unambiguous `us`, `ru`, and `uk` console choices for the primary
  desktop layout; preserve explicit overrides and the optional second layout.
- Refresh multilib databases together with a full system upgrade.
- Add executable regressions for umask inheritance, private state, keyboard
  selection and package-command failure propagation.

## 1.0.0

- Provides Minimal TTY, Stock GNOME and optional Marble profiles, with Marble GDM as a separate
  opt-in.
- Supports fresh installation or dual boot, ext4 or Btrfs, GRUB or systemd-boot and optional LUKS2.
- Uses a release-pinned, signed bootstrap and a strict signed package repository.
- Keeps production signing offline and publishes only independently verified repository snapshots.
