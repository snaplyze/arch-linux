# Project-owned Arch packages

The package set is closed by [`repository/package-set`](../repository/package-set). Every package
commits canonical data-only `.SRCINFO`, immutable source identities and local source hashes.
PKGBUILDs are built only by an unprivileged temporary user.

## Packages

- `arch-linux-keyring`: installs the public project trust inputs and pacman repository policy.
- `arch-linux-marble-shell`: pinned Marble GNOME Shell assets.
- `arch-linux-colloid-gtk`: pinned GTK3, GTK4 and libadwaita theme assets; replaces `arch-linux-colloid-gtk3`.
- `arch-linux-colloid-icons`: pinned icon theme assets.
- `arch-linux-marble-profile`: user-session profile, compatibility checks and Stock fallback.
- `arch-linux-marble-gdm`: separate opt-in GDM Shell process overlay.

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
