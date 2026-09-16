# Marble profiles

## Stock is the baseline

Stock GNOME is always the first and default appearance choice. It includes the product's functional
GNOME baseline—Ptyxis, Bibata, locale-aware Formats, layouts and the reviewed extension profile—while
retaining distribution Shell, GDM, GTK3/GTK4/libadwaita styling and package-owned resources. Bibata is the
product's editable cursor default; it does not replace distribution-owned cursor files.
TTY and Stock installations do not bootstrap the Marble package repository.

## Marble desktop

Marble desktop is an explicit opt-in delivered by native packages from the strict signed project
repository. It applies the reviewed Marble blue/filled/dark GNOME Shell theme, Colloid Dark GTK3
theme, Colloid GTK4/libadwaita system-color stylesheet and Colloid icon theme. Official User Themes
is added to the editable extension list.

The desktop profile does not replace system fonts, lock user dconf,
change the Bibata cursor or write another package's files. Its compatibility helper exposes project
defaults only for an explicitly supported GNOME major with exact reviewed asset hashes. A mismatch
removes only those project defaults and leaves packages installed and updateable with Stock active.

## Experimental Marble GDM

After Marble desktop is selected, the installer asks a second question. Stock GDM remains first and
default. The experimental option combines an exact reviewed Stock GNOME Shell base with the Marble
visual layer and named Colloid icons, then exposes them only to the GDM Shell service.

This option changes appearance only. GDM continues to require the normal user-selection and password
flow, and PAM authentication remains unchanged.

The package owns its combined CSS, reviewed SVGs, helper, compatibility metadata, dconf profile and
database, systemd drop-in input, hooks and licenses below project paths. It does not overwrite the
distribution Shell gresource, GDM/PAM files, `/etc/dconf`, `/var/lib/gdm`, user homes,
`/usr/share/icons/default` or GTK4/libadwaita CSS.

Activation requires exact GNOME resource, service, session, vendor-dconf and asset hashes; trusted
root ownership/modes; a safe service-readable path chain; successful GLib overlay lookup; and the
expected one-key dconf result. An administrator-defined GDM dconf profile is authoritative and keeps
the project overlay inactive.

Package hooks remove only exact project activation before a relevant package transaction, reload
the user manager without restarting GDM, then revalidate after the transaction. Foreign or unsafe
state is preserved and reported. A running greeter retains its already loaded environment until it
exits; reboot is required if post-transaction manager reload cannot be confirmed.

## Fallback and removal

Unknown GNOME versions, changed inputs or ordinary incompatibility keep Stock and do not block a full
system update. Removing or reinstalling Marble must leave all project packages ownership-clean and
must not alter vendor resources. Repository outage or signature failure prevents Marble package
installation but does not weaken or damage the Stock path.

Acceptance requires the QEMU scenarios in [testing.md](testing.md) and current results in
[validation.md](validation.md). Reference framebuffer images show the intended visual states:

- [GDM user selection](images/marble-gdm-user-selection.png)
- [GDM password](images/marble-gdm-password.png)
- [Marble desktop](images/marble-desktop.png)
- [Marble lock screen](images/marble-lock-screen.png)

## GTK4/libadwaita and existing installations

`arch-linux-colloid-gtk` replaces `arch-linux-colloid-gtk3` and contains GTK3, GTK4 and
libadwaita assets from the same pinned source. The Marble profile requires the new package.
Stock GNOME does not install either theme package or activate user CSS.

The GNOME user service `arch-linux-marble-gtk4.service` applies the packaged stylesheet before
`gnome-session-pre.target`, so session applications start with the profile already active.
It replaces `gtk.css` and `gtk-dark.css` under `$XDG_CONFIG_HOME/gtk-4.0` (normally
`~/.config/gtk-4.0`) **without backups**, including existing custom styles. It replaces
symlinks themselves, not their targets; unrelated files such as `servers` are preserved.
On logout, profile deactivation or removal it removes only its own unchanged CSS wrappers.
Previous custom styles are not restored. Light/dark switching follows system colors.

Existing Marble systems receive the same configuration through `pacman -Syu` followed by
logout/login; new users receive it on first GNOME login. GTK 4.22.x/libadwaita 1.9.x with
GNOME 50 are initially supported. Unsupported combinations disable the project defaults.
Use `/usr/lib/arch-linux-marble-profile/gtk4-session status` in the user session to inspect
activation. No global `GTK_THEME` override or automatic Flatpak permission changes are used.
