# Arch Linux Installer

Arch Linux Installer is an interactive Bash installer for a current x86_64 Arch Linux system. It
preserves eight product choices: **Minimal TTY**, **Stock GNOME**, optional **Marble**, a separate
opt-in Marble GDM appearance, **ext4** or **Btrfs**, **GRUB** or **systemd-boot**, optional **LUKS2**,
and both fresh-install and dual-boot paths.

## Supported platform

Use release `1.0.1` from the official Arch Linux x86_64 installation ISO, booted in UEFI mode with
Secure Boot disabled and working network access. Legacy BIOS and non-x86_64 platforms are outside
the supported boundary. Back up all important data before starting: a fresh installation can erase
the selected physical disk.

## Release-pinned bootstrap

Run the immutable release bootstrap from the Arch ISO:

```bash
curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.1/install.sh | bash
```

The bootstrap is release-pinned. It downloads the installer, its SHA-256 file, detached signature
and `arch-linux.gpg`; validates the exact public-certificate digest and fingerprints; rejects secret
key packets; then launches only the verified installer bytes from a private root-owned directory.
For a verification-only run:

```bash
curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.1/install.sh | bash -s -- --verify-only
```

The certificate fingerprints must also be compared through an independently trusted channel. HTTPS,
a checksum and a signature fetched from the same account do not by themselves establish identity.
See the [trust model](docs/trust-model.md).

## Profiles and updates

- **Minimal TTY** installs the base system and networking without a graphical desktop.
- **Stock GNOME** installs unmodified GNOME, GDM and Wayland and remains the safe default.
- **Marble** is an explicit profile installed only through signed project packages.
- **Marble GDM** is a separate opt-in package. Its environment overlay is scoped only to the GDM
  Shell process; unsupported GNOME versions fall back to Stock.

The installer checks the latest immutable release at startup and offers a signed self-update when a
newer version is available. Re-running the new release-pinned bootstrap is the recovery path when an
in-place update cannot be authenticated. Marble packages and compatibility data update normally
through:

```bash
sudo pacman -Syu
```

A Marble profile update therefore does not require a new installer release. Removing the Marble
profile returns the user session to Stock; reinstalling it restores the package-owned profile.
Stock GNOME remains usable when the project package repository is unavailable.

## Versioning and maintenance policy

Installer changes after `1.0.0` are released as `1.0.1`, `1.0.2` and later SemVer versions. Arch
Linux itself continues to update through normal `pacman -Syu`. Marble/profile-only changes bump the
owning package's `pkgrel` and are delivered through the signed Pages repository; they do not require
a new installer release.

Source pins change only through a reviewed pull request. The maintenance watcher may create or
update one advisory issue, and the monthly A+B build remains advisory. Nothing automatically merges,
releases, signs, or changes a fingerprint, checksum, source pin or accepted Arch ISO. There is no
`arch-os` synchronization. Signing-key changes use a separate, explicitly authorized manual
rotation procedure.

## Development verification

Release [1.0.1](https://github.com/snaplyze/arch-linux/releases/tag/1.0.1) and its signed Pages
packages are published and verified. Fresh public installation and the actual installer/package
update paths passed. See the [release verification summary](docs/release-process.md#released-101).
`main` may later contain unreleased changes; a source merge alone does not publish an installer
or update Pages. Existing `1.0.0` assets and its tag are preserved.
See the [reviewed updates and delivery boundaries](docs/maintenance.md#external-source-inputs).

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

Private signing material is intentionally absent from source and CI. Offline signing, QEMU
acceptance and public release operations are separate stages described in the
[release process](docs/release-process.md).

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
