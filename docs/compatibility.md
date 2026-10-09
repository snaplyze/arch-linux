# Compatibility

## Platform matrix

| Component | Supported boundary | Safe fallback |
| --- | --- | --- |
| Installation media | Official Arch Linux x86_64 ISO, UEFI, Secure Boot disabled; accepted validation input is in `maintenance/accepted-arch-iso.json` | New media requires fresh qualification; latest availability is not acceptance. |
| Minimal TTY | Current Arch package set on x86_64 UEFI | Not applicable. |
| Stock GNOME | Current Arch stable GNOME/GDM/Wayland packages; candidate signed extension bundle requires the project repository | Stock remains the graphical baseline with vendor appearance and no Colloid/Marble themes. |
| Marble desktop | GNOME majors listed by `packages/arch-linux-marble-profile/supported-gnome-majors` with exact reviewed assets | Remove only Marble defaults; use Stock. |
| Marble GTK4/libadwaita | GNOME 50 + GTK 4.22.x + libadwaita 1.9.x; GNOME 51 candidate + GTK 4.24.x + libadwaita 1.10.x, with exact packaged CSS/assets | Deactivate project defaults and remove only unchanged project CSS wrappers. |
| Experimental Marble GDM | Separate reviewed GNOME Shell `1:50.5-1` and candidate `1:51.0-1` resources and exact service/session/vendor-dconf hashes | Keep the project overlay inactive and use Stock GDM. |
| Filesystems | Btrfs or ext4; optional LUKS2 root | Stop on validation or mount failure. |
| Boot | GRUB or systemd-boot on UEFI | Stop before installation when UEFI prerequisites fail. |
| Dual boot | Existing vfat ESP and distinct root partition on the selected disk; known selected-kernel/bootloader footprint must be free | Release 1.0.6 refuses collisions/uncertainty before root mutation; staged collision refusal, neighbor preservation and real boot passed. |

BIOS boot, non-x86_64 systems, enabled Secure Boot and unreviewed package/resource substitutions are
outside the support boundary.

The supported boundary is a requirement, not evidence that every combination was executed.
See [audit coverage and findings](PLAN.md#review-findings): F-01/F-02 for guard failure paths,
F-03 for shared ESP files and F-05 for supplemental VM acceptance. Accepted ISO is `2026.10.01`,
reviewed by the owner after fresh Minimal and Stock GNOME qualification with unchanged public
1.0.5. This media result remains separate from the nine staged 1.0.6 runtime scenarios recorded
in [validation](validation.md). Fresh public-only Marble/GDM acceptance passed separately with19 assertions.

## GNOME update rules

As of 2026-10-09, the GNOME 51 changes are an unpublished candidate; follow the
[update recovery checkpoint](PLAN.md#gnome-51-update-recovery--2026-10-09) for
source, package, installed-session and delivery status. Release 1.0.6's Marble
packages support GNOME 50 only. Installing newer Arch GNOME packages does not
make an older profile or extension compatible.

Stock GNOME follows Arch's normal full-system update path. Project packages must not introduce an
upper-bound dependency that blocks `pacman -Syu`. Marble compatibility is an activation decision:
only exact reviewed GNOME and asset inputs enable project defaults. Unknown versions and hashes
are intended to return the effective appearance to Stock after successful deactivation while
leaving updates available. A helper error or retained running greeter requires actual status/session
inspection; an unsupported version by itself is not proof that deactivation succeeded.

GNOME extension compatibility is evaluated per extension. A package being installed does not prove
that its metadata or runtime supports a new GNOME major. The signed VM evidence linked from
[validation.md](validation.md) records the checks for the verified release.
The staged Marble scenario checks the eight enabled profile extensions, including User Themes;
this does not establish support for a future GNOME major.

The candidate adds the independent seventh package `arch-linux-gnome-extensions` for Dash to
Dock, Blur my Shell, Just Perfection, Clipboard Indicator and No Screenshot Box in both Stock
and Marble. The Marble theme profile depends on it; extension fixes do not depend on theme
activation. Both new GNOME installer paths require the strict signed project repository, while
Stock retains vendor appearance and no Colloid/Marble theme packages. AppIndicator, Caffeine
and User Themes remain native Arch dependencies. A modified user-local extension can shadow its packaged replacement;
the migration preserves that user content and reports the conflict. Fresh-install
and existing-install upgrade results must be recorded separately. This transition
requires a new full installer release: package-only mode cannot add the seventh package to the
old six-package baseline or change the immutable 1.0.6 installer's AUR requests. The candidate
still requires separate [real upgrade/functionality checks](testing.md#gnome-51-candidate-upgrade-acceptance);
historical results and immutable assets must not be rewritten.

## Hardware and virtual machines

The QEMU/KVM/OVMF matrix proves the documented virtual hardware scenarios, not every physical
machine. GPU generation, firmware, RAID, unusual NVMe/USB bridges, vendor recovery layouts and
wireless devices may require manual Arch procedures. Select graphics drivers deliberately and keep
bootsplash disabled if it hides an encryption prompt on the target hardware.

## LUKS and separately enrolled TPM unlock

The installer uses LUKS2 password unlock; it does not enroll TPM policy. If you later enroll
TPM unlock yourself, test an independent password/recovery unlock before changing boot inputs.
PCR policies can depend on firmware, partition tables, bootloader, initrd or kernel command line;
updates to those inputs may prevent automatic unlock. Inspect your actual enrollment policy
and retest a full boot after the change. Use matching cryptenroll/cryptsetup versions when
creating enrollments: newer enrollment formats are not guaranteed to work with older unlock
software. See the [systemd 262 enrollment contract](https://github.com/systemd/systemd/blob/v262/man/systemd-cryptenroll.xml).
TPM behavior is outside this project's password-based VM acceptance.
