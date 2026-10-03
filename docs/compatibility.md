# Compatibility

## Platform matrix

| Component | Supported boundary | Safe fallback |
| --- | --- | --- |
| Installation media | Official Arch Linux x86_64 ISO, UEFI, Secure Boot disabled; accepted validation input is in `maintenance/accepted-arch-iso.json` | New media requires fresh qualification; latest availability is not acceptance. |
| Minimal TTY | Current Arch package set on x86_64 UEFI | Not applicable. |
| Stock GNOME | Current Arch stable GNOME/GDM/Wayland packages | Stock remains the graphical baseline. |
| Marble desktop | GNOME majors listed by `packages/arch-linux-marble-profile/supported-gnome-majors` with exact reviewed assets | Remove only Marble defaults; use Stock. |
| Marble GTK4/libadwaita | GNOME 50, GTK 4.22.x and libadwaita 1.9.x with reviewed packaged CSS/assets | Deactivate project defaults and remove only unchanged project CSS wrappers. |
| Experimental Marble GDM | Reviewed GNOME Shell `1:50.5-1` resource and exact service/session/vendor-dconf hashes | Keep the project overlay inactive and use Stock GDM. |
| Filesystems | Btrfs or ext4; optional LUKS2 root | Stop on validation or mount failure. |
| Boot | GRUB or systemd-boot on UEFI | Stop before installation when UEFI prerequisites fail. |
| Dual boot | Existing vfat ESP and distinct root partition on the selected disk; known selected-kernel/bootloader footprint must be free | Source candidate refuses collisions/uncertainty before root mutation; published 1.0.5 lacks that guard, corrected-child VM acceptance pending. |

BIOS boot, non-x86_64 systems, enabled Secure Boot and unreviewed package/resource substitutions are
outside the support boundary.

The supported boundary is a requirement, not evidence that every combination was executed.
See [audit coverage and findings](PLAN.md#review-findings): F-01/F-02 for guard failure paths,
F-03 for shared ESP files and F-05 for supplemental VM acceptance. Accepted ISO remains
`2026.09.01`; availability of `2026.10.01` is advisory until ARCH-01 qualifies it.

## GNOME update rules

Stock GNOME follows Arch's normal full-system update path. Project packages must not introduce an
upper-bound dependency that blocks `pacman -Syu`. Marble compatibility is an activation decision:
only exact reviewed GNOME and asset inputs enable project defaults. Unknown versions and hashes
are intended to return the effective appearance to Stock after successful deactivation while
leaving updates available. A helper error or retained running greeter requires actual status/session
inspection; an unsupported version by itself is not proof that deactivation succeeded.

GNOME extension compatibility is evaluated per extension. A package being installed does not prove
that its metadata or runtime supports a new GNOME major. The signed VM evidence linked from
[validation.md](validation.md#verified-release-104) records the checks for the verified release.
The staged Marble scenario checks the eight enabled profile extensions, including User Themes;
this does not establish support for a future GNOME major.

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
