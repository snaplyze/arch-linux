# Configuration

## Schema 1 format

`installer.conf` is a strict data file. It contains all 43 keys below exactly once as
`KEY=plain-value`. The loader accepts those keys in any order; the generator emits the canonical
documented order. The file has no comments, blank lines, shell quotes, escapes, arrays,
continuations or executable syntax. `ARCH_LINUX_LOCALE_GEN_LIST` joins multiple entries with `;`.

The loader requires a regular, non-symlink file owned by the current user, rejects group/world
writes and limits the file to 65,536 bytes. It rejects an unknown, missing or duplicate key and
commits values only after the complete file passes lexical validation. The installer never applies
`source`, `.`, `eval` or command substitution to this file.

The generated file may contain an empty value before its selector runs. The completed installation
contract is stricter: `validate_properties` requires every context-relevant value and checks
cross-field rules. The password is runtime-only and never appears in `installer.conf`.

## Complete allowlist

| Key | Accepted value and meaning |
| --- | --- |
| `ARCH_LINUX_INSTALLER_CONFIG_VERSION` | Exactly `1`. |
| `ARCH_LINUX_HOSTNAME` | Lowercase DNS-style hostname, 1–63 characters. |
| `ARCH_LINUX_USERNAME` | Lowercase account name beginning with a letter, up to 32 characters. |
| `ARCH_LINUX_DISK` | Absolute `/dev/...` whole-disk path selected for installation. |
| `ARCH_LINUX_BOOT_PARTITION` | Absolute `/dev/...` ESP path on the selected disk. |
| `ARCH_LINUX_ROOT_PARTITION` | Absolute `/dev/...` root path on the selected disk. |
| `ARCH_LINUX_DISK_IDENTITY` | SHA-256 identity derived from the selected disk's size, model and WWN or serial; required and uniquely resolvable before acceptance. |
| `ARCH_LINUX_BOOT_PARTITION_IDENTITY` | SHA-256 identity derived from the parent-disk identity, PARTUUID, start and size of the selected ESP; required for dual boot and empty before a fresh layout is created. |
| `ARCH_LINUX_ROOT_PARTITION_IDENTITY` | SHA-256 identity derived from the parent-disk identity, PARTUUID, start and size of the selected root partition; required for dual boot and empty before a fresh layout is created. |
| `ARCH_LINUX_FILESYSTEM` | `btrfs` or `ext4`. |
| `ARCH_LINUX_BOOTLOADER` | `grub` or `systemd`. |
| `ARCH_LINUX_DUAL_BOOT_ENABLED` | Boolean; preserves layout and reuses an existing ESP when `true`. |
| `ARCH_LINUX_BTRFS_SNAPPER_ENABLED` | Boolean; applicable to Btrfs. |
| `ARCH_LINUX_BTRFS_ASSISTANT_ENABLED` | Boolean; applicable to Btrfs. |
| `ARCH_LINUX_ENCRYPTION_ENABLED` | Boolean; enables LUKS2 for the root filesystem. |
| `ARCH_LINUX_TIMEZONE` | Zoneinfo name such as `Europe/Moscow`. |
| `ARCH_LINUX_LOCALE_LANG` | Locale identifier without encoding suffix, such as `ru_RU`. |
| `ARCH_LINUX_LOCALE_GEN_LIST` | `;`-separated locale.gen records, for example `ru_RU.UTF-8 UTF-8;en_US.UTF-8 UTF-8`. |
| `ARCH_LINUX_REFLECTOR_COUNTRY` | Optional comma-separated Reflector country names. |
| `ARCH_LINUX_VCONSOLE_KEYMAP` | Console keymap identifier. |
| `ARCH_LINUX_VCONSOLE_FONT` | Optional console font identifier. |
| `ARCH_LINUX_KERNEL` | Lowercase Arch package name beginning with a letter or digit; remaining characters are limited to lowercase letters, digits, `.`, `_`, `+` and `-`. |
| `ARCH_LINUX_KERNEL_ARGS` | Optional space-separated kernel arguments restricted to letters, digits and `. _ - = , : + / @ % [ ]`. |
| `ARCH_LINUX_MICROCODE` | `intel-ucode`, `amd-ucode` or `none`. |
| `ARCH_LINUX_CORE_TWEAKS_ENABLED` | Boolean. |
| `ARCH_LINUX_MULTILIB_ENABLED` | Boolean. |
| `ARCH_LINUX_AUR_HELPER` | `paru`, `paru-bin`, `paru-git`, `yay`, `trizen`, `pikaur` or `none`. |
| `ARCH_LINUX_BOOTSPLASH_ENABLED` | Boolean; controls Plymouth and related boot-menu behavior. |
| `ARCH_LINUX_HOUSEKEEPING_ENABLED` | Boolean; enables the project housekeeping set. |
| `ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED` | Boolean; installs the fixed minimal Fish plus Starship profile. |
| `ARCH_LINUX_DESKTOP_ENABLED` | Boolean; `false` selects minimal TTY, `true` selects GNOME/GDM. |
| `ARCH_LINUX_GNOME_THEME_PROFILE` | `stock` or `marble`; Stock is first and default. |
| `ARCH_LINUX_GDM_THEME_PROFILE` | `stock` or `marble-experimental`; Stock is first and default. |
| `ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER` | `mesa`, `intel_i915`, `nvidia`, `amd`, `ati` or `none`. |
| `ARCH_LINUX_DESKTOP_EXTRAS_ENABLED` | Boolean. |
| `ARCH_LINUX_DESKTOP_SLIM_ENABLED` | Boolean; keeps the GNOME core application set when `true`. |
| `ARCH_LINUX_DESKTOP_KEYBOARD_MODEL` | XKB model identifier, normally `pc105`. |
| `ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT` | Primary XKB layout identifier; keep a Latin layout first. |
| `ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT` | Optional primary XKB variant identifier. |
| `ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND` | Optional second XKB layout identifier. |
| `ARCH_LINUX_SAMBA_SHARE_ENABLED` | Boolean; guest-writable share remains opt-in. |
| `ARCH_LINUX_VM_SUPPORT_ENABLED` | Boolean; installs detected guest integration. |
| `ARCH_LINUX_ECN_ENABLED` | Boolean; controls installer-network ECN handling. |

Boolean values are the lowercase literals `true` and `false`. Empty strings are represented by
nothing after `=`. Values cannot contain carriage returns, line feeds or tabs.

## Cross-field validation

- Disk targets must resolve to the same selected whole disk and reproduce their accepted physical
  identities. Fresh and dual-boot layouts have distinct identity rules described in
  [installation.md](installation.md).
- Snapper and Btrfs Assistant settings apply only to Btrfs; the installer accepts their persisted
  values for ext4 but does not run those Btrfs-only stages.
- When desktop installation is disabled, GNOME/GDM appearance, desktop extras and desktop keyboard
  values remain parseable persisted data but are not applied.
- When desktop installation is enabled, experimental GDM is effective only with the Marble
  desktop selection and after its package and compatibility checks pass.
- GDM always requires an explicit password login.
- The second desktop layout is optional; when present the primary Latin layout remains first.

Edit with a plain-text editor and preserve every key. On any parser or validation error, use the
interactive repair flow; do not execute the file in a shell.
