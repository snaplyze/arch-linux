# Compatibility

## Platform matrix

| Component | Supported boundary | Safe fallback |
| --- | --- | --- |
| Installation media | Current official Arch Linux x86_64 ISO, UEFI, Secure Boot disabled | Stop before disk changes. |
| Minimal TTY | Current Arch package set on x86_64 UEFI | Not applicable. |
| Stock GNOME | Current Arch stable GNOME/GDM/Wayland packages | Stock remains the graphical baseline. |
| Marble desktop | GNOME majors listed by `packages/arch-linux-marble-profile/supported-gnome-majors` with exact reviewed assets | Remove only Marble defaults; use Stock. |
| Experimental Marble GDM | Exact GNOME resource/service/session/vendor-dconf hashes accepted by its compatibility data | Keep the project overlay inactive and use Stock GDM. |
| Filesystems | Btrfs or ext4; optional LUKS2 root | Stop on validation or mount failure. |
| Boot | GRUB or systemd-boot on UEFI | Stop before installation when UEFI prerequisites fail. |
| Dual boot | Existing vfat ESP and distinct root partition on the selected disk | Stop before formatting on any identity mismatch. |

BIOS boot, non-x86_64 systems, enabled Secure Boot and unreviewed package/resource substitutions are
outside the support boundary.

## GNOME update rules

Stock GNOME follows Arch's normal full-system update path. Project packages must not introduce an
upper-bound dependency that blocks `pacman -Syu`. Marble compatibility is an activation decision:
only exact reviewed GNOME and asset inputs enable project defaults. Unknown versions and hashes
return the effective appearance to Stock while leaving system updates available.

GNOME extension compatibility is evaluated per extension. A package being installed does not prove
that its metadata or runtime supports a new GNOME major. The accepted matrix in
[validation.md](validation.md) records actual active extensions for the release under test.

## Hardware and virtual machines

The QEMU/KVM/OVMF matrix proves the documented virtual hardware scenarios, not every physical
machine. GPU generation, firmware, RAID, unusual NVMe/USB bridges, vendor recovery layouts and
wireless devices may require manual Arch procedures. Select graphics drivers deliberately and keep
bootsplash disabled if it hides an encryption prompt on the target hardware.
