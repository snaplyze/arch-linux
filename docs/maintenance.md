# Advisory maintenance

Maintenance detects drift; it does not change source, accepted hashes, pins, keys or releases.

## Public signing key expiry

```bash
python3 maintenance/check-key-lifetime.py
```

The existing maintenance workflow checks the tracked public certificate daily, as well as on a
manual run. It updates the same advisory issue without erasing unresolved monthly findings.
Warnings begin 210 days before expiry; manual renewal is due at 180 days, with urgent/critical
warnings at 90/30 days. Repeated unchanged warnings do not generate issue updates. Production
signing still requires at least 180 days remaining.

On an existing issue, a changed key warning (or recovery from a warning) also posts one comment:
the [GitHub comment endpoint triggers notifications](https://docs.github.com/en/rest/issues/comments#create-an-issue-comment).
Editing the issue description alone is not used as the notification mechanism. The updater checks
its latest bot notice before posting, including after a lost response, and preserves monthly
findings. Initial healthy checks and unchanged daily reports stay quiet. Subscribe to the advisory
issue and configure your GitHub notification delivery preferences; this does not override a muted
account or guarantee email delivery.

The current signing subkey expires on **2027-08-24 at 11:42:46 UTC**; the renewal cycle begins
**2027-02-25**. These dates are read from the public certificate, not silently updated trust pins.
GitHub never renews a key or handles private material. Follow the
[manual renewal procedure](trust-model.md#expiry-renewal-and-installed-systems).

GitHub scheduled runs may be delayed and public repositories with no activity can have schedules
disabled. Check Actions periodically and keep a separate maintainer calendar reminder; a workflow
is not a guaranteed real-time alarm. See [GitHub schedule limitations](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

## Accepted Arch ISO

`maintenance/accepted-arch-iso.json` records the reviewed official x86_64 ISO. The detector validates
the exact official Arch API source and can compare current metadata without modifying accepted
state:

```bash
python3 maintenance/check-arch-iso.py
```

Updating accepted ISO state is a separate human-reviewed task. At minimum, a new ISO requires fresh
Minimal TTY and Stock GNOME QEMU acceptance before the committed state changes.

The September 2026 baseline was reviewed with official ISO `2026.09.01` and installed GDM
`50.3-1`, GNOME Shell `1:50.4-1`, Linux `7.2.3.arch1-2` and Ptyxis `50.1-1`. Fresh Minimal,
Stock Btrfs/LUKS2/GRUB and Marble Btrfs/LUKS2/systemd-boot with opt-in Marble GDM passed.
The graphical runs included real password login, Wayland, lock/unlock, update and repeat login;
Marble also passed fallback and package removal/reinstallation. All runs shut down cleanly,
passed `qemu-img check` and removed their owned runtime.

These are compatibility results for unchanged released product and harness commit
`94d8e9e72fefc38e790942763c615801d49eff97`, tree
`aae94e9c5eb8b381570cb51e141bf5c0b9ff3c57`, not a new release or a PASS for later product changes:

- Minimal: `minimal-20260906T085524Z-3f5be618`.
- Stock: `luksgrub-20260906T085525Z-77f65b3a`.
- Marble: `marble-20260906T090802Z-576b0797`.

The ISO SHA-256 is recorded in `maintenance/accepted-arch-iso.json`; its detached signature was
verified against official Arch public trust. The existing signed repository snapshot SHA-256 was
`d3e7dd50ffaeb7d8538a5eab32fe4a5e27ff3e4d9f0dfaa071aadff2e278c619` for all three runs.
No installer/package pin, production certificate or published 1.0.0 asset changed for this review.

## External source inputs

`maintenance/sources.json` lists only sources currently used by the installer or package recipes:
Arch packages, GNOME, Marble, Colloid, GNOME extensions, pinned AUR inputs, Gum, the Starship preset
and license/source provenance. Offline binding is mandatory:

```bash
python3 maintenance/check-sources.py
```

A scheduled or manual advisory run may query upstream services:

```bash
python3 maintenance/check-sources.py --network --report "$ARTIFACT_DIR/source-advisory.json"
```

Findings are informational. The workflow creates or updates one advisory issue and performs no
commit, merge, release, signing, pin update, key rotation or remediation pull request.

Arch versions recorded as full package versions retain epoch and pkgrel during comparison;
legacy pkgver-only entries compare pkgver only. A tagged upstream is checked against its exact
tag (peeled for annotated tags), not an unrelated default-branch HEAD. A configured latest-release
endpoint is checked separately, so newer releases still produce an advisory. Missing tags and
network errors remain visible; none of these checks changes the accepted inputs.

### Reviewed extension update: Just Perfection 37

The unreleased installer source pins Just Perfection 37 after the 2026-09-06 review of
[upstream tag 37.0](https://gitlab.gnome.org/jrahmatzadeh/just-perfection/-/tree/37.0)
at `ae48fd2d75a5747bbda1bdb2b039e9a3384ddf4c` and AUR commit
`f84ccdef0316a572471c282763b52dd5901e87b6`. The installer and `maintenance/sources.json`
bind the same AUR archive, committed metadata and hardened PKGBUILD hashes. The source test
uses byte-exact public AUR fixtures, runs the installer's actual hardening block without
executing PKGBUILD, and rejects stale version-36 identities and changed dependency metadata.

Version 37 fixes pending timer/signal cleanup and translations, retains GNOME 45–50 support
and adds GNOME 51 metadata. The settings schema, manager, entrypoint, stylesheet and build
script bytes are unchanged from 36; the dependency closure remains `git` and `gnome-shell`.
The exact released commit is accepted, not a later development HEAD with download statistics.

Both versions were built by a disposable unprivileged makepkg user in clean Arch containers
using image `archlinux:base-devel@sha256:714acd1eef9ae997d95691b1c5220ada0076185b77857c1813f02de0fa83cf7b`.
Regenerated metadata, package contents and the existing AUR archive verifier passed.
The reviewed version-37 package SHA-256 was
`286bb78f8fc1fc05b1f1338c90b965673b40563098a9ec4db0bd2bdb21f8a23e`.
This focused AUR build is not a new canonical project-package release build.

Fresh Stock `luksgrub-20260906T101759Z-8fd2f0d5` and Marble
`marble-20260906T101800Z-3808e87e` runs passed runtime compatibility on GNOME Shell `1:50.4-1`
and GDM `50.3-1`. Each first installed unchanged signed 1.0.0, then upgraded the hash-verified
local AUR package from 36 to 37 before the first user login, without a trust-policy override.
Real GDM password login, Wayland, lock/unlock, `pacman -Syu`, reboot/relogin, package integrity,
zero failed units, clean shutdown and `qemu-img check` passed. Marble additionally passed
fallback, restoration, removal and reinstall with fresh password logins. D-Bus checks found
Just Perfection 37 and Blur 72 active, system-installed and error-free in four Stock and eight
Marble phases. Both runs removed their temporary disks and firmware state.

These results bind released product/harness commit `94d8e9e72fefc38e790942763c615801d49eff97`,
tree `aae94e9c5eb8b381570cb51e141bf5c0b9ff3c57`, the September ISO and signed snapshot above,
and the separate one-use compatibility operator SHA-256
`5384ee252c40df8ced19adfa8a315b55e0dc04b0012e331c63a4cccc52a4a5ea`.
Their verdict is `COMPATIBILITY_PASS`, `releaseAcceptance=false`: not a fresh-install PASS
for a modified installer or a new release. No production key or signed-release verifier changed.

Blur stays at [released v72](https://github.com/aunetx/blur-my-shell/releases/tag/v72),
commit `444df605b34529dfab7be77d0f434bf54a6dd4cc`; its AUR input is unchanged. The detected
development HEAD contains unreleased popup/shader/pipeline changes, not a released v73.
Keep that advisory visible until a separately reviewed update is justified.

Published 1.0.0 bootstrap, assets, tag and Pages remain unchanged. The new installer pin is
unreleased and requires the next installer release to reach release-pinned fresh installs.
These extensions are AUR packages, not project Pages packages: this change does not deliver
Just Perfection 37 to existing systems through `pacman -Syu`. Project Marble/profile and public
keyring packages retain their separate signed Pages/pacman update path.

## A+B reproducibility

Two independent clean Arch builds are compared monthly as advisory evidence:

```bash
repository/compare-package-builds.sh "$ARTIFACT_DIR/build-a" "$ARTIFACT_DIR/build-b"
```

A mismatch updates the same advisory issue but does not block the normal release path. The required
release build is one clean canonical Arch build.
The daily key-only run does not rebuild packages or query every external source.

The comparison returns 0 for exact match, 1 for a verified mismatch, and 2 for verification/usage
errors. The issue distinguishes differing bytes from an unavailable comparison. No package member,
including `.BUILDINFO` or `.MTREE`, is excluded to obtain a match.

Both disposable Actions build containers use `WORK_DIR=/tmp/arch-linux-canonical-work`.
makepkg records the actual build/start directories in `.BUILDINFO`; a random directory would
otherwise cause different archives even with identical installed payloads. The directory must not
exist and must be disjoint from source and output; the builder creates and owns it exclusively,
then removes it on completion. Do not point WORK_DIR at existing data or run concurrent builds at
that same path in a shared environment. Local builds without WORK_DIR retain isolated `mktemp`
directories. Build environments can still drift independently; actual mismatches remain advisory.
