# Arch Linux Installer

Arch Linux Installer is an interactive Bash installer for a current x86_64 Arch Linux system. It
preserves eight product choices: **Minimal TTY**, **Stock GNOME**, optional **Marble**, a separate
opt-in Marble GDM appearance, **ext4** or **Btrfs**, **GRUB** or **systemd-boot**, optional **LUKS2**,
and both fresh-install and dual-boot paths.

## Supported platform

Use a published immutable release from the official Arch Linux x86_64 installation ISO, booted in UEFI mode with
Secure Boot disabled and working network access. Legacy BIOS and non-x86_64 platforms are outside
the supported boundary. Back up all important data before starting: a fresh installation can erase
the selected physical disk.

## Release-pinned bootstrap

Historical release 1.0.6 was published on 2026-10-04; its acceptance is recorded in the
[release evidence](docs/validation.md).

<!-- BEGIN release-bootstrap -->
The commands below pin immutable release **1.0.6**. Use them from the Arch ISO only after
confirming publication and acceptance in the [release evidence](docs/validation.md):

```bash
curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.6/install.sh | bash
```

For a newer version, use the release-pinned command in the
[latest published immutable GitHub Release](https://github.com/snaplyze/arch-linux/releases).
These examples pin 1.0.6; they do not track `main` or a moving latest-download URL.

The bootstrap is release-pinned. It downloads the installer, its SHA-256 file, detached signature
and `arch-linux.gpg`; validates the exact public-certificate digest and fingerprints; rejects secret
key packets; then launches only the verified installer bytes from a private root-owned directory.
For a verification-only run:

```bash
curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.6/install.sh | bash -s -- --verify-only
```
<!-- END release-bootstrap -->

The certificate fingerprints must also be compared through an independently trusted channel. HTTPS,
a checksum and a signature fetched from the same account do not by themselves establish identity.
See the [trust model](docs/trust-model.md).

## Release overview

<!-- BEGIN release-overview -->
As of 2026-10-09, the GNOME 51 recovery changes currently in this checkout are an unpublished
candidate. They add a shared signed extension package, reviewed desktop/GDM
compatibility and safe migration of the old local extension. They are not yet
available through `pacman -Syu`; see the [current gates](docs/PLAN.md#gnome-51-update-recovery--2026-10-09).
<!-- END release-overview -->

## Historical release acceptance

Release 1.0.6 delivers the installer guard, idle-probe, shared-ESP, account and recovery
corrections recorded in the [registry](docs/PLAN.md#review-findings), together with package and
repository verification hardening. All nine staged VM scenarios passed before its immutable
18-asset publication and Pages deployment.

Fresh public Release/Pages byte and signature readback and the separate public-only
Marble/GDM VM passed;
[validation](docs/validation.md) records their separate outcomes and preserves historical evidence.
Latest Arch media availability is distinct from the project's accepted ISO input; see
[compatibility](docs/compatibility.md).

## Profiles and updates

- **Minimal TTY** installs the base system and networking without a graphical desktop.
- **Stock GNOME** installs unmodified GNOME, GDM and Wayland and remains the safe default.
- **Marble** is an explicit profile installed only through signed project packages, including
  unified Colloid GTK3, GTK4/libadwaita and icon styling.
- **Marble GDM** is a separate opt-in package. Its environment overlay is scoped only to the GDM
  Shell process; unsupported GNOME versions fall back to Stock.

The installer checks the latest immutable release at startup and offers a signed self-update when a
newer version is available. Re-running the new release-pinned bootstrap is the recovery path when an
in-place update cannot be authenticated. Marble packages and compatibility data update normally
through:

```bash
sudo pacman -Syu
```

The Marble package lifecycle does not require a new installer release. The reviewed
[package-only procedure](repository/README.md#package-only-updates) now binds an exact package child
to the published installer; external package-only signing/publication still requires separate
authorization and is NOT_TESTED. Installed systems consume published signed packages through `pacman -Syu`.
Successful removal of the Marble helpers returns the user session to Stock; reinstalling restores
the package-owned profile when compatibility checks and activation succeed. Inspect the resulting
session; helper failures or foreign state require the [lifecycle checks](docs/marble.md).
The unified `arch-linux-colloid-gtk` package replaces `arch-linux-colloid-gtk3` during normal
updates. GTK4/libadwaita styling activates automatically on the next GNOME login, replacing existing
user CSS without backups; see the [Marble lifecycle](docs/marble.md#gtk4libadwaita-and-existing-installations).
Stock GNOME installs no Colloid theme packages or project user CSS. The new installer
uses the signed project repository for `arch-linux-gnome-extensions` in both graphical
profiles. Minimal TTY remains independent of it. The new package layout and installer
routing require a full release; they cannot be delivered as a package-only update
against the unchanged 1.0.6 installer.

## Versioning and maintenance policy

Installer changes use immutable SemVer releases. The [changelog](CHANGELOG.md) records
released changes; a source commit alone is not a published release. Arch
Linux itself continues to update through normal `pacman -Syu`. Marble/profile-only changes bump the
owning package's `pkgrel` and are delivered through the signed Pages repository; they do not require
a new installer release. This is the intended delivery policy; the present package-only route
limitation is tracked in [F-14 / DELIVERY-01](docs/PLAN.md#review-findings).

Source pins change only through a reviewed pull request. The maintenance watcher may create or
update one advisory issue, and the monthly A+B build remains advisory. The configured release
pipeline creates one immutable release only after a successful reviewed merge to `main`; it builds,
signs and tests a deterministic version-only child of that exact merge before publishing it. It
cannot merge source, change a fingerprint, checksum, source pin or accepted Arch ISO. There is no
`arch-os` synchronization. Signing-key changes use a separate, explicitly authorized manual
rotation procedure.

## Development verification

All five GitHub Actions workflows use the project runner `ubuntu-actions-arch-linux`
on the existing shared Ubuntu VM. PR and merged-main source CI passed for the
[migration](docs/PLAN.md#local-runner-migration--2026-10-08). Check the exact
[validation record](docs/validation.md) for installer, production-signing and
release acceptance on this runner. See the
[runner environment and operating boundaries](docs/testing.md#local-runner-environment).

Historical `1.0.0` and `1.0.1` evidence remains associated with its original inputs, but their
release/tag objects are retired and must not be used as current installation references. A successful
configured release pipeline creates the next immutable release and verified Pages deployment from
the exact merged `main` source and its separately bound release child. See the
[release process](docs/release-process.md) and the
[reviewed updates and delivery boundaries](docs/maintenance.md#external-source-inputs).

The normative source command is:

```bash
bash tests/source-tests.sh
```

A canonical unsigned package build requires a clean Arch environment and an unprivileged temporary
builder:

```bash
repository/build-packages.sh "$ARTIFACT_DIR/unsigned"
repository/verify-unsigned-build.sh "$ARTIFACT_DIR/unsigned"
```

Private signing material is absent from source. Only the configured `release.yml` workflow's `snapshot`
and `finalize` jobs receive the release-environment `ARCH_LINUX_SIGNING_KEY` and
`ARCH_LINUX_SIGNING_PASSPHRASE` secrets for the signing-only subkey; build, VM, PR, CI, Pages,
maintenance and public-readback jobs do not. The signing boundary, QEMU acceptance and release
operations are described in the [release process](docs/release-process.md).

## Documentation

- [Installation](docs/installation.md)
- [Configuration contract](docs/configuration.md)
- [Architecture](docs/architecture.md)
- [Marble lifecycle](docs/marble.md)
- [Package repository](docs/package-repository.md)
- [Testing](docs/testing.md)
- [Maintenance](docs/maintenance.md)
- [Security policy](SECURITY.md)

The project is distributed under GPL-3.0. Third-party attribution is isolated in
[NOTICE.md](NOTICE.md) and is not a runtime dependency or update source.
