# Advisory maintenance

Maintenance detects drift; it does not change source, accepted hashes, pins, keys or releases.

## Preparing a GNOME update

Start with the current Arch Shell, Mutter, GDM, GTK and libadwaita package versions
and the relevant [GNOME Shell porting guide](https://gjs.guide/extensions/upgrading/).
Review every enabled extension's source and compatibility metadata. AUR snapshots
and user-local extension archives do not gain a pacman update path by appearing
in the installer. Keep source identity, licenses, package ownership and migration
for those inputs in the same review as the profile.
The GNOME 51 implementation uses the theme-independent `arch-linux-gnome-extensions`
bundle for both graphical profiles. Verify new-install routing and the previous
installer's behavior before selecting package-only delivery; a changed package
set or installer requires a full release.

Qualify the full transition from the last signed installation: upgrade through
pacman, log in through GDM, exercise all expected extensions, confirm the chosen
theme and optional greeter, lock/unlock, update and boot again. Preserve user
preferences and modified local extension copies. Test fallback and recovery as
different transitions. A parser test, catalog support declaration, advisory check
or new package revision does not replace that acceptance.

Ship the verified signed repository before promising that `pacman -Syu` restores
existing machines. Keep unqualified inputs and unpublished candidates explicit in
the [plan](PLAN.md#gnome-51-update-recovery--2026-10-09). Do not disable version
checks, freeze individual Arch packages or relabel old VM results to avoid Stock
fallback. For the GNOME 51 transition, upstream Marble remains 50.0.0; the project
implementation retains its provenance and composes a separately pinned GNOME 51 GDM
base. The unmerged Clipboard Indicator port and the No Screenshot Box metadata
port require their own functional acceptance. Future GNOME/GTK/libadwaita versions
need fresh qualification and signed delivery; a normal full update alone does not
establish compatibility for unknown inputs. Current exact acceptance and delivery
results belong in [validation](validation.md) and the signed release acceptance.

The [dated audit snapshot and registry](PLAN.md#current-arch-context) distinguish observed drift
from accepted inputs and reviewed no-update decisions. Reports record UTC observation time,
manifest path/SHA-256, and each queried source's identity and
result, including unchanged and error outcomes. Daily key-only updates preserve monthly findings
and their original date, while displaying their age; results older than 35 days are marked stale.
Undated legacy reports remain unknown and cannot close an issue as current clean evidence.
Coverage includes linux/linux-lts/linux-zen, systemd, mkinitcpio, cryptsetup, GRUB, pacman,
Arch keyring, GTK3/GTK4 and libadwaita. New package entries use the October 3 official API
observations as advisory comparison baselines; they do not pin installer packages or qualify them.
An `unchanged` value in an old advisory is not today's media qualification.

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

The current signing subkey expires on **2028-09-08 at 04:25:31 UTC**; advisory warnings begin on
**2028-02-11** and the renewal cycle begins **2028-03-12**. These dates are read from the public
certificate, not silently updated trust pins.
GitHub never renews a key or handles the certification primary or recovery material. The authorized
release pipeline temporarily imports only the signing-only subkey in its two signing jobs. Follow the
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
The committed input is `2026.10.01`, SHA-256
`684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5`.
The owner accepted this exact pin after official metadata, hash and trusted Arch signature
verification and fresh Minimal/Stock qualification on October 3. The unchanged public 1.0.5
product and harness commit `1b45bbaf2cdf30f4e97f8bfcf9546272f055b376` were bound separately.
Minimal `minimal-20261003T151714Z-2c0c2415` passed 13 assertions; Stock
`stock-20261003T152418Z-552739f5` passed 20, including real GDM password login, Wayland,
lock/unlock, full update and repeat login after another boot. Both passed clean shutdown,
`qemu-img check` and owned-resource cleanup. These are media qualification results, not
acceptance of later installer changes. Compact evidence and the preceding diagnostic failure
remain separately recorded in [the project registry](PLAN.md).

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
and license/source provenance. Arch comparisons retain epoch and package release; mkinitcpio and
keyring use `core/any` endpoints, core binaries use `core/x86_64`, and linux-zen/GTK/GNOME use
`extra/x86_64`. Extension tags are compared only within the recorded accepted Shell major;
missing or malformed compatible versions are errors. Pinned upstream tag identity is checked
separately from the latest release, so an unchanged accepted tag cannot hide a newer release.
The installer can fall back from a failed AUR recipe clone to the package branch
of the [official read-only Arch mirror](https://archlinux.org/news/recent-services-outages/).
That is a transport fallback for the same pinned commit and content hashes, not a
source update. Advisory AUR query failures still remain errors; do not report
`unchanged` merely because another transport is available.
Offline binding is mandatory:

```bash
python3 maintenance/check-sources.py
```

Offline reports say `validated`, which proves local binding only. Network reports say `unchanged`,
`advisory` (drift), or `error` (one or more failed queries, with other findings retained).
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

### GNOME Shell 50.5 compatibility inputs

The current Marble GDM compatibility source uses Arch GNOME Shell `1:50.5-1` and upstream
GNOME Shell tag `50.5`, commit `dd8bec9326c2416e7b65b8bc9db4e62126a4fe8b`. The reviewed
package SHA-256 is `bd564f61a97fe0a0eacc3a2dd27e679186da04d52197a4a285567f6181f299e5`;
the pinned upstream archive SHA-256 is
`098c2123bb18ba8970c84a9b21908070cc534e5cd646412dd448f4eb3c0da543`.
The package recipe and advisory source inventory bind these exact inputs.

The recorded GNOME Shell 50.4 results below and in the September ISO baseline remain historical
results for their original package bytes. They do not establish 50.5 compatibility. The updated
inputs passed fresh builds and Stock/Marble QEMU acceptance in release 1.0.4; see the
[release evidence](validation.md#verified-release-104). Future input changes require new acceptance.

### Reviewed extension update: Just Perfection 37

The 1.0.1 installer source pins Just Perfection 37 after the 2026-09-06 review of
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
commit `444df605b34529dfab7be77d0f434bf54a6dd4cc`; its AUR input is unchanged. At the September review, the detected
development HEAD contained unreleased popup/shader/pipeline changes; v73 was not released then.
The October review below records its subsequent release.
Keep that advisory visible until a separately reviewed update is justified.

This historical review did not change the then-published 1.0.0 bootstrap, assets, tag or Pages. The
new installer pin reached release-pinned fresh installs through the separately verified 1.0.1
installer release before both release/tag objects were retired.
These extensions are AUR packages, not project Pages packages: this change does not deliver
Just Perfection 37 to existing systems through `pacman -Syu`. Project Marble/profile and public
keyring packages retain their separate signed Pages/pacman update path.

### Colloid and Gum review, September 2026

The Colloid icons source update uses upstream commit
[`ceac6608ecd0e40025cbc2ebbd32bf0e0f4ebc6a`](https://github.com/vinceliuice/Colloid-icon-theme/commit/ceac6608ecd0e40025cbc2ebbd32bf0e0f4ebc6a)
and package version `20260829-1`, not a replacement for the published `20260817-1` bytes.
The complete upstream diff adds six application SVGs and fifteen relative aliases for
Google Messages/Tasks, Shelly, Kingdom Hearts and Zcode; no existing file, installation
script or license changes. The SVGs contain bounded embedded PNG artwork, no script or
external resource reference. The existing cache exclusion, exact export-path cleanup,
dangling-link rejection and GDM icon hash contract are retained. The verifier additionally
requires all six new artwork hashes; regression fixtures reject each missing new icon.
Minimum dependencies in Marble/profile and GDM remain valid and do not need to change.
This does not waive the publication revision rule: any rebuilt archive with different
bytes must receive a new filename/version, including metadata-only rebuild differences.

The clean unprivileged Arch six-package build passed from commit
`9ccc03f30119d1c60857fdbfcc6b6b5940332dae`, tree
`a8284d9144511c476b394b598c694e3078d51d34`; regenerated `.SRCINFO` and independent
host verification passed. The icon package SHA-256 was
`bc5c00c0a5b5a260a27e54d64af6edabe3a810a3e76b0e9d94193ce705a13924`.
Comparing both real icon packages found 29 added paths (including Dark status aliases),
no removals and unchanged bytes/types/modes/owners/link targets for all existing payload.
The new artwork's real hash verifier rejected a deliberately modified SVG.

Fresh QEMU/KVM run `marble-20260906T115612Z-5356a635` produced `COMPATIBILITY_PASS`,
`releaseAcceptance=false`. It first installed unchanged signed 1.0.0, then installed
that separately verified unsigned local icon package with `pacman -U`, without changing
pacman trust configuration. Real GDM password login, Wayland, lock/unlock, `pacman -Syu`,
reboot/relogin, zero failed units, package integrity and Stock fallback passed. After
removal and signed-repository reinstall, the reviewed local upgrade was repeated before
another real login. Seven guest phases checked the six artwork hashes and actual GTK
icon lookup; both upgrades triggered the normal cache/profile/GDM hooks. Clean shutdown,
`qemu-img check` and removal of owned runtime passed.

This result binds the existing September ISO and signed snapshot above, released
product/harness commit `94d8e9e72fefc38e790942763c615801d49eff97`, tree
`aae94e9c5eb8b381570cb51e141bf5c0b9ff3c57`, and one-use compatibility operator SHA-256
`98ea49203e3453e5e7d25518c1915a67fc00e0e4b40ef8ee1d0f7f4db0ab45bc`.
The package build identity is separate from the released installer and these later
documentation changes. It is not a new signed snapshot, Gum2 test or installer release.

Colloid GTK stays at `6c2dc65865628bda9fdc8157a30cd5eda6fd41f9`: the complete diff to
[`fe11342f37f124f1b29d44cf33e9a06053f4bba2`](https://github.com/vinceliuice/Colloid-gtk-theme/commit/fe11342f37f124f1b29d44cf33e9a06053f4bba2)
only changes Cinnamon styling and adds a standalone GTK4 switcher. Neither is packaged
or invoked by the project. The unified `arch-linux-colloid-gtk` recipe now builds GTK3,
GTK4 and libadwaita assets from the retained pin. The project profile activates the
packaged stylesheet automatically before GNOME session applications start; the upstream
switcher is not introduced into installed systems. Stock retains distribution styling.
The historical icon acceptance above does not prove this GTK migration; see the separate
[migration acceptance requirements](testing.md#marble-gtk-migration-acceptance).

Gum stays at `0.17.0` after review of [v2.0.0](https://github.com/charmbracelet/gum/releases/tag/v2.0.0).
The new official x86-64 archive and Sigstore checksum bundle were verified. Real controlling-PTY
comparisons of both binaries preserved prompt defaults, input, masking, selection, cancellation,
multiline submission and spinner exit codes. However, v2's `style` and `join` now strip ANSI
formatting when stdout is a pipe; the installer uses that output in command substitutions.
The same real-PTY tests retained styling with 0.17.0 and lost it with 2.0.0. This is a reviewed
no-update decision, not an installation failure or a new release gate. A later Gum upgrade must
deliberately adapt these wrappers and test the changed installer in a VM; changing only the
version/hash/size would not preserve the existing UI. Do not force colors globally into selected
values or logs. No Gum 2.0 installer acceptance is claimed.

Source acceptance and delivery are separate. The following delivery record is historical: the
then-updated icons were delivered by the verified, offline-signed 1.0.1 snapshot on Pages. A separate fresh public VM installed the six
original signed 1.0.0 packages, then upgraded all six to the exact new versions and hashes through
normal `pacman -Syu`, with unchanged signature policy and clean package integrity. The actual
1.0.0 installer also verified, replaced itself and restarted into immutable 1.0.1. See the
[historical release summary](release-process.md#historical-101-evidence-retired); earlier unsigned compatibility results above
are not relabeled as release acceptance. An installer release is not required solely for a
profile/icon package change. Never replace published release assets. Platform-enforced
immutability for future releases is a separate [publication setting](release-process.md#release-immutability).
Keep genuine upstream advisories visible even when review concludes that the accepted pin
should not change.

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

### October 3, 2026 source review

Fresh advisory/source review retained every accepted pin. These proposals were reviewed, not
accepted as new source inputs; URLs, hashes, package versions and trust bytes remain unchanged.

| Input | Exact proposed upstream identity | Decision |
| --- | --- | --- |
| gum | `879f048103adf0214b85943b52d8d65b08d772c5` | retain 0.17.0; 2.0.2 still strips command-substitution ANSI style/join |
| colloid | `fe11342f37f124f1b29d44cf33e9a06053f4bba2` | retain; diff changes only unshipped switcher/Cinnamon |
| spdx | `31ba1a50e5397e00a304dbadc76531740e89ee48` | retain |
| blur | `425761d5504941899cfb8cda24202d829024c622` | retain released72; proposal73 requires new runtime acceptance |
| justPerfection | `6e82a6ebf8e9578f2ffe4e06b88f5d23f600b947` | retain released37.0; unreleased HEAD has two UI fixes but no reproduced current defect |
| dashToDock | `36529d37c0eb805b04dfd647e5295860771b23ea` | retain106; optional109 proposal needs GNOME50 runtime acceptance |
| pikaur | `ae8a9c7787ffc87399b12477fbfc4268ac525fbb` | retain1.33.3; optional1.34 proposal changes pkgbase/srcinfo and opt-in privilege environment behavior |

Gum 2.0.2 Linux x86-64 asset 585508723 is 4,963,495 bytes, SHA256
`d842e06d93dbed90af48cb8dd10698db6f22e331fc40346bb37bbc753109edc2`. API digest and
published checksums agree. Sigstore bundle cryptographic verification was NOT_TESTED because
cosign is unavailable; this candidate was not accepted. Real controlling-PTY smoke covered
nine used commands and 28 expected case/version outcomes. The existing style/join command-
substitution behavior remains incompatible with Gum 2; fixture-only write/pager mistakes
were corrected and receipts preserve both attempts.

Colloid's three-commit diff changes only unshipped switcher/Cinnamon files. The sole consumed
SPDX LGPL-2.1-only text is byte-identical (26,001 bytes, SHA256
`5749785c8bdefafcb5d798270ed0a967036fe2ca63dcedade1627565dfef81d2`). Blur v73 is now
released: 118 commits / 105 changed files require fresh popup/shader/lifecycle acceptance;
its observed development HEAD `67bbf7236f64a4e03b87982971f45584499802fb` declares 74.
Just Perfection has three unreleased UI-fix commits with no reproduced current defect.
Dash to Dock 109 changes 56 commits / 20 files, including startup geometry, timeout and input.
Pikaur 1.34 changes 24 commits / 41 files, including pkgbase/srcinfo and opt-in privilege
environment behavior. No dependency/license change was found for the latter two proposals.

Proposed AUR identities: Blur `f23a49d84b3b62ca2c23bbdec7763329c555fd38`, Dock
`91c4de013bd43db027ece31f1dba96fd06a6d924`, Pikaur
`9b3b01867ab9b8db88765a1dd69029ecae604d62`. Six accepted-package metadata checks, offline
source checks and accepted AUR SRCINFO bindings passed. Candidate builds/VMs are NOT_TESTED
and unnecessary for the retain decision. The retained pins subsequently passed the canonical
corrected-child build and runtime gates in release 1.0.6; see [validation](validation.md#verified-release-106--2026-10-04).
Those results do not qualify the unaccepted proposals. Compact review receipts stay outside source;
[the project registry](PLAN.md) is the canonical decision record.
