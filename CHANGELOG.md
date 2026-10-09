# Changelog

Release entries describe their immutable tagged source. Package-only updates can be delivered
separately through the signed repository; see [package delivery](docs/package-repository.md).

## Unreleased

- Prepare the GNOME 51 Marble profile tuple alongside GNOME 50, with distinct reviewed GDM
  platform/resource closures and unsupported-input deactivation.
- Add the independent `arch-linux-gnome-extensions` seventh package for Stock and Marble,
  replacing four AUR packages through pacman. Make the Marble profile depend on that bundle.
  Retire only the exact installer-created No Screenshot Box local payload and preserve modified copies and editable preferences.
- Bootstrap the strict signed project repository for both GNOME installer options while keeping
  Stock free of Colloid/Marble themes. Require a full new installer release for this closure and
  behavior transition; package-only mode cannot change the historical six-package baseline.
- Preserve Clipboard Indicator's selected upstream PR and No Screenshot Box's project metadata
  port provenance; require real signed-upgrade, password-login and functionality acceptance
  bound to the delivered release.

- Retain bounded extension-probe failure diagnostics for desktop lookup and GTK
  process, activation, mapping and focus. Keep diagnostic observations separate
  from functional acceptance and retain the Shell recovery condition result.
  Preserve only allowlisted public stack module names for logout-crash diagnosis.

- Prevent archive-inspection deadline signals from stranding subprocess wait locks.
  Preserve time/resource limits, child cleanup and the caller's signal state.

- Render release-pinned bootstrap commands and prose from the selected release version,
  independently of the installer source floor and earlier documentation pin. Keep historical
  release dates and acceptance evidence bound to their original inputs. Keep installation
  recommendations outside generated blocks consistent with the selected pin, and link
  mutable acceptance status to exact evidence instead of freezing unqualified status claims.
- Bind authored changes to the deterministic release child without claiming publication or
  acceptance. Source checks, installation acceptance and release/public readback remain separate
  gates; see [release evidence](docs/validation.md).

## 1.0.6 — 2026-10-04

- Publish immutable release child `7af2209be497a0a5f0e314cd8cc20f691e52b064` after all nine
  staged VM scenarios passed. The exact 18 finalized assets and Pages deployment are published;
  fresh public Release/Pages byte readback and public-only Marble/GDM acceptance passed.
  See [release evidence](docs/validation.md).
- Reject uncertain disk/idle probes, reserved account names and shared-ESP write collisions before
  destructive work. Require worker quiescence before storage cleanup and retain only validated,
  bounded recovery state after failed teardown.
- Strengthen package/database identity and resource checks while retaining mandatory signatures and
  the isolated signing boundary.
- Adapt only the volatile overlay's root fstab row before the unchanged systemd remounter so GRUB
  Btrfs snapshots boot with their read-only lower root preserved.

## 1.0.5 — 2026-09-17

- Record the immutable published release at commit `61add3e0b2c20adbbdd425494eae02ddec0a3bac`.
  October public readback verified all 18 assets, their signatures and the signed Pages repository;
  see [readback evidence](docs/validation.md#public-readback-of-release-105).
- This entry records published bytes and historical acceptance. Later installer corrections
  belong to 1.0.6; October media qualification remains bound to its separate inputs.

## 1.0.4 — 2026-09-17

- Replace `arch-linux-colloid-gtk3` with the unified `arch-linux-colloid-gtk` package for GTK3,
  GTK4 and libadwaita, preserving automatic pacman replacement and the six-package set.
- Apply Marble GTK4/libadwaita CSS automatically at GNOME login, before session applications start,
  including new users and upgraded installations. Handle deactivation, removal, reinstall, custom XDG paths and unsupported
  versions; activation replaces existing user CSS without backups.
- Update the reviewed Marble GDM compatibility inputs to GNOME Shell 50.5.
- Add signed legacy-package migration, fresh-user login and GTK application startup checks in
  light/dark modes. Preserve exact installed-package checks despite compatibility providers.
- Fix the test harness's GNOME session environment and Welcome-dialog logout handling; provision
  Boxes only in the acceptance guest. Correct UID-sensitive fixtures, the signing-agent observer
  race and Ubuntu `vercmp`/`bsdtar` test dependencies.
- Publish an immutable 18-file release after all three staged VM scenarios passed; verify public
  downloads, Pages and a public-only Marble installation. See [evidence](docs/validation.md#verified-release-104).

## 1.0.3 — 2026-09-10

- Use mkinitcpio's systemd-native `sd-volatile` path for GRUB Btrfs snapshots and configure
  grub-btrfs entries with a read-only lower root plus a temporary writable overlay.
- Enable one filesystem-scoped Btrfs scrub timer instead of scheduling duplicate subvolume jobs.
- Make required first-login GNOME settings transactional with readback, private combined logging,
  idempotent retry state and a success marker; add the explicit CalendarServer dependency.

## 1.0.2 — 2026-09-09

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

## 1.0.1 — historical, release/tag retired

- Update reviewed GNOME extension and Colloid icon inputs and validate six-package update delivery.
- Correct completed-executor observation and QEMU startup readiness without weakening containment.
- Retain the original verification record in the
  [historical release evidence](docs/release-process.md#historical-101-evidence-retired).

## 1.0.0

- Provides Minimal TTY, Stock GNOME and optional Marble profiles, with Marble GDM as a separate
  opt-in.
- Supports fresh installation or dual boot, ext4 or Btrfs, GRUB or systemd-boot and optional LUKS2.
- Uses a release-pinned, signed bootstrap and a strict signed package repository.
- Keeps production signing offline and publishes only independently verified repository snapshots.
