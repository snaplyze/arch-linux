# Project-owned Arch packages

The package set is closed by [`repository/package-set`](../repository/package-set). Every package
commits canonical data-only `.SRCINFO`, immutable source identities and local source hashes.
PKGBUILDs are built only by an unprivileged temporary user.

## Packages

- `arch-linux-keyring`: installs the public project trust inputs and pacman repository policy.
- `arch-linux-marble-shell`: pinned Marble GNOME Shell assets.
- `arch-linux-colloid-gtk`: pinned GTK3, GTK4 and libadwaita theme assets; replaces `arch-linux-colloid-gtk3`.
- `arch-linux-colloid-icons`: pinned icon theme assets.
- `arch-linux-marble-profile`: user-session theme profile, compatibility checks, Stock fallback
  and a dependency on the independent extension bundle.
- `arch-linux-marble-gdm`: separate opt-in GDM Shell process overlay.
- `arch-linux-gnome-extensions`: curated extensions and exact legacy migration for Stock and Marble.

## Ownership boundaries

Packages may own only their reviewed project paths. Pacman does not own user home files, and
packages do not replace vendor GNOME Shell/GDM resources, PAM configuration or global environment
files. The Marble profile user service separately activates packaged GTK4/libadwaita CSS before
GNOME session applications start. It replaces user `gtk.css` and `gtk-dark.css` without backups,
preserves unrelated settings and removes only unchanged project wrappers during cleanup. See the
[Marble lifecycle](../docs/marble.md#gtk4libadwaita-and-existing-installations).

The GDM package installs
a systemd drop-in for `org.gnome.Shell@gdm.service`; its `G_RESOURCE_OVERLAYS` and `DCONF_PROFILE`
variables do not reach ordinary user sessions.

The profile and GDM helpers are idempotent. Pacman install/upgrade reconciles compatible assets;
removal deactivates them; reinstall restores them; an unsupported GNOME major returns to Stock.
Normal updates use `pacman -Syu`.

## GNOME 51 candidate

The candidate adds a seventh package, `arch-linux-gnome-extensions`, independent of appearance.
Both Stock and Marble install it; the Marble profile depends on it. The bundle owns five curated
extension UUIDs under `/usr/share/gnome-shell/extensions`, including Dash to Dock 109, Blur my Shell 74
and Just Perfection 37. Clipboard Indicator is the selected upstream PR 641 source; No Screenshot
Box retains version 6 with an explicit project metadata port. Their source pins, license grants,
bounded preparer and complete file manifest live in
[`arch-linux-gnome-extensions/`](arch-linux-gnome-extensions/). No upstream Makefile or extension code
runs during preparation; schema caches and Clipboard translations are compiled from pinned data.

The bundle's versioned provides/conflicts/replaces take over four corresponding AUR packages
through pacman. The user-session service separately removes only the exact known installer-created
No Screenshot Box tree when the verified system replacement is present. Edited or foreign local
copies remain and produce a shadowing diagnostic; extension preferences remain editable.

The reviewed profile tuples are GNOME 50 / GTK 4.22.x / libadwaita 1.9.x and GNOME 51 /
GTK 4.24.x / libadwaita 1.10.x. GDM keeps distinct reviewed GNOME 50 and 51 resources and
platform hashes. Both helpers retain deactivation for unsupported or mismatched inputs.
The upstream Marble source version remains 50.0.0; this candidate does not claim an upstream
Marble 51 release or successful live activation.

The new GNOME installer paths bootstrap the strict signed project repository for both Stock and
Marble. Stock remains free of Colloid/Marble theme packages; Minimal TTY remains independent of
these desktop inputs. A full new installer release is required: package-only mode cannot change
an old six-package baseline or the immutable installer's AUR requests. Historical six-package
build and acceptance records remain bound to their original inputs.

Before delivery, generated package revisions must exceed the active signed baseline. A source
`pkgrel` is not the final release-child revision; see the
[release transform](../docs/release-process.md#1-source-candidate). Source checks, real package
builds, signed old-to-new transactions and password-login functionality are separate gates.
As of 2026-10-09, the GNOME 51 candidate has not completed publication or real-session acceptance; see
[upgrade checks](../docs/testing.md#gnome-51-candidate-upgrade-acceptance).

## Validation

```bash
python3 repository/verify-package-metadata.py
while IFS= read -r package; do
  repository/validate-package-sources.sh --regenerate "packages/$package"
done < repository/package-set
bash tests/marble-checks.sh
```

A real package build remains a clean Arch task; metadata review or lifecycle simulation is not a
substitute for `makepkg` and pacman acceptance.
