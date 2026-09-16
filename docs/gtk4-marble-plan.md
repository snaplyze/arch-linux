# Marble GTK 4/libadwaita implementation plan

Approved intent: Marble automatically includes Colloid GTK 3 and GTK 4/libadwaita;
Stock includes neither Colloid package nor its user CSS. Existing Marble installations
converge with new installations after a signed package update and a new GNOME login.

## Decisions

- Rename `arch-linux-colloid-gtk3` to `arch-linux-colloid-gtk`, with versioned provides
  and unversioned replaces/conflicts for the former name. Keep six project packages.
- Keep the pinned upstream source. Build GTK 3, GTK 4 and the dedicated libadwaita
  system-color stylesheet in staging; never run the upstream HOME-mutating installer mode.
- The profile depends on the new package; CSS activation is automatic before GNOME apps.
- Replace existing gtk.css/gtk-dark.css without backups (explicit user choice).
  Preserve unrelated GTK configuration and symlink targets. Removal restores stock styling,
  not the previous CSS. Remove only exact project-owned activation files.
- Do not change the running workstation's appearance during development.
- Use the existing checkout and feature branch; preserve signing and release boundaries.

## Tasks

1. Rename/package theme and migrate metadata, dependencies, source monitors and checks.
   Add staged libadwaita CSS/assets and validate their deterministic hashes.
2. Implement a user-session helper and pre-session systemd service with apply/remove/status,
   idempotence, no-backup replacement, safe symlinks, cleanup and offline-user removal.
3. Integrate profile compatibility, lifecycle hooks, installer descriptions, Stock/Marble
   assertions and fresh-versus-upgraded acceptance. Update user documentation.
4. Run affected tests, full source checks, package builds and available VM acceptance;
   review the complete change. Report each evidence layer without claiming unrun checks.

## Integration contract

- Theme payload: /usr/share/arch-linux-marble/gtk4/gtk.css with resources below assets/.
- Profile publishes /var/lib/arch-linux-marble/gtk4-enabled only after compatibility checks.
- User helper: /usr/lib/arch-linux-marble-profile/gtk4-session; commands apply, remove,
  status and root-only remove-all. apply additionally respects effective gtk-theme.
- User service: arch-linux-marble-gtk4.service, wanted by and before gnome-session-pre.target;
  apply on start, remove on stop. Failures must not prevent GNOME login.
- User GTK files import the packaged CSS using an absolute file URI. State records paths,
  never previous CSS bytes. remove-all drops privileges before accessing user files.
- Compatibility initially GNOME 50, GTK 4.22.x and libadwaita 1.9.x; unsupported combinations
  deactivate project defaults. Existing package hashes and validation remain enforced.

## Acceptance

- Helper regression tests cover fresh/existing CSS, repeated activation, custom XDG config,
  external symlinks, removal after user modification, unrelated files and no backups.
- Stock VM has no Colloid packages or CSS. Marble VM uses Colloid in GTK 3 and libadwaita;
  first login, relogin, new user, upgrade and removal are covered.
- Compare new versus upgraded package versions, CSS hashes and helper status. Check Nautilus,
  Ptyxis, GNOME Settings, file dialogs and Boxes including light/dark rendering.
- Run tests/source-tests.sh, canonical package validation and applicable disposable VM checks.
- Publish only through the repository's existing reviewed, signed release workflow.

## Progress

- Implemented the unified package, legacy migration metadata, staged GTK 4/libadwaita
  payload, profile compatibility checks and automatic per-user session activation.
- Updated installer, release metadata transformation, documentation and Stock/Marble
  VM assertions; retained the six-package release closure.
- Added regression coverage for helper ownership/removal, migration metadata and
  release-generated versioned provides. Independent integration review found no blocking
  defect; helper review identified cleanup edge cases addressed with regressions.
- A full source suite and canonical six-package build passed on an intermediate candidate.
  Re-run both against the final reviewed source identity before reporting completion.
- Release acceptance remains pending: real old-package-to-new-package pacman migration,
  fresh-versus-upgraded parity, new-user GNOME login and named-application light/dark
  rendering. Existing VM update assertions do not prove the legacy migration scenario.
- The development workstation has not been migrated. Deploy through the existing signed
  release workflow, then update installed Marble packages and start a new GNOME session.
