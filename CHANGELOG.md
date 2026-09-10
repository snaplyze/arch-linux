# Changelog

## Unreleased

- Authorize the guarded GitHub Actions release pipeline after a CI-verified `main` merge. It derives,
  tests and signs a deterministic version-only release child while separately binding the origin
  main commit/tree. Only `snapshot` and `finalize` receive the release-environment signing-only
  subkey and passphrase; all other CI jobs remain without signing authority.
- Retire the historical `1.0.0` and `1.0.1` release/tag objects without relabelling their evidence
  as acceptance for a later release.

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

- Use mkinitcpio's systemd-native `sd-volatile` path for GRUB Btrfs snapshots and configure
  grub-btrfs entries with a read-only lower root plus a temporary writable overlay.
- Enable one filesystem-scoped Btrfs scrub timer instead of scheduling duplicate subvolume jobs.
- Make required first-login GNOME settings transactional with readback, private combined logging,
  idempotent retry state and a success marker; add the explicit CalendarServer dependency.

## 1.0.0

- Provides Minimal TTY, Stock GNOME and optional Marble profiles, with Marble GDM as a separate
  opt-in.
- Supports fresh installation or dual boot, ext4 or Btrfs, GRUB or systemd-boot and optional LUKS2.
- Uses a release-pinned, signed bootstrap and a strict signed package repository.
- Keeps production signing offline and publishes only independently verified repository snapshots.
