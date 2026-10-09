# Project review and modernization implementation plan

## GNOME 51 update recovery — 2026-10-09

Owner requests compatible Marble updates through `pacman -Syu`, review of current
upstream documentation, agent instructions for future desktop upgrades, and correct
documentation in newly generated release tags. Work remains in this checkout on
`main`; pre-existing README/testing/runner-checkpoint edits and the empty index are
preserved. Existing immutable releases and their evidence must not be rewritten.

| ID | Work and acceptance | Status |
| --- | --- | --- |
| G51-01 | Diagnose installed package/session state and upstream compatibility; bind findings to versions and authoritative sources. | DONE |
| G51-02 | Prepare reviewed package/extension upgrade paths, preserve user overrides and safe unsupported-version handling; reproduce failures before fixes and test recovery. | IN_PROGRESS: seven-package candidate; actual upgrade acceptance pending |
| G51-03 | Correct deterministic release documentation rendering; test independently differing source/document/release versions and preserve historical evidence. | DONE: deterministic overview/bootstrap/changelog rendering; 52 regressions PASS |
| G51-04 | Update agent, update/release and user documentation with package delivery and real upgrade acceptance requirements. | DONE for local candidate; publication reconciliation remains conditional |
| G51-05 | Independent diff review, affected checks and full source suite; record package, real session/VM and publication results separately. | Source/review, clean seven-package build and authentic legacy upgrade inputs PASS on their recorded trees; real signed upgrade, GDM/VM and publication NOT_TESTED |

Confirmed host evidence: GNOME Shell/Mutter/GDM 51.0; GTK 4.24.1 and libadwaita
1.10.0. Installed Marble Shell/GDM remain 50.0.0-7/-8, profile 1.0.0-10.
The published profile supports GNOME 50 + GTK 4.22 + libadwaita 1.9 only; GDM reports
`stock`, GTK4 helper reports `inactive`. Blur my Shell 72, Clipboard Indicator 71
and user-local No Screenshot Box 6 report `OUT OF DATE`; Dash to Dock 106 reports
`ERROR`, with a missing `resource:///org/gnome/shell/ui/pointerWatcher.js` import.
The [GNOME 51 porting guide](https://gjs.guide/extensions/upgrading/gnome-shell-51.html)
confirms this API removal. Enabled-extension preferences remain present. Shell,
GTK and icon user overrides are absent, so compatible defaults can recover without
resetting user preferences. A new login is necessary to load updated extensions.

Release documentation finding: `repository/release-source.py` formerly substituted
only bootstrap URLs matching the installer's source version (1.0.2), while README
and installation commands pinned 1.0.6. The candidate now renders bounded canonical
bootstrap blocks for the selected child version and promotes exactly one nonempty
Unreleased changelog section. Historical acceptance remains bound to its original
release. Existing immutable tag 1.0.6 and its bytes are not modified.
Live readback of that tag confirmed its README still directs readers to 1.0.5
and describes old audit status; correcting main after publication did not change
the frozen tag. The new pre-freeze renderer addresses future release commands and
overview text rather than rewriting that historical release.

Current implementation: the seventh package `arch-linux-gnome-extensions` owns
five reviewed non-distribution extensions and four versioned AUR replacements.
Stock and Marble use it through the strict signed repository; Marble profile
depends on it, while theme removal preserves it. The new installer removes both
profiles' obsolete AUR/local-extension installation paths. Minimal TTY remains
repository-independent. Exact package/build/signature closure checks expand to
seven; the outer 14/18 release asset closures and historical six-package evidence
remain unchanged. A full installer release is required: package-only delivery
cannot change the old package set, and the unmodified 1.0.6 installer would install
conflicting AUR owners after the new profile. Old Stock installations have no
project repository; their migration is a separate authenticated bootstrap gate.

The user service moves only the exact known installer-created local No Screenshot
Box tree into private custody outside GNOME extension discovery. It retains the
original directory and inodes, including later writes through held descriptors;
modified/unknown copies stay active and are reported. User preferences remain
untouched. Independent review reproduced a check-to-unlink data-loss race in the
initial candidate; recursive deletion was removed and 27 migration regressions
now pass. Custody is a move, not an extra settings copy, and package removal does
not erase or reactivate it.

A read-only execution of the candidate's exact snapshot predicate against this
machine's local No Screenshot Box passed: all six file hashes, both directories,
ownership and safe modes match the supported legacy tree. This establishes its
eligibility for migration, not execution of that migration.

Upstream review: Dash to Dock 109 and Blur my Shell 74 have GNOME 51 catalog
releases; Just Perfection 37 already supports 51. Clipboard Indicator uses the
reviewed candidate from [upstream PR 641](https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator/pull/641)
(still unmerged when checked). No Screenshot Box uses pinned GPL source with a
project metadata port. Upstream Marble remains 50.0.0. The candidate retains
GNOME 50 and adds a separately pinned GNOME 51 GDM composition/platform closure;
profile GTK tuples are exactly 50/4.22/1.9 and 51/4.24/1.10. Unknown versions and
unverified resource changes remain fail-closed.

Scoped evidence: Marble lifecycle regressions, exact seven-package metadata and
archive fixtures, 13 desktop routing checks, 27 migration checks and all six
pinned-input preparation checks pass. Native Shell 51 / GTK 4.24 parsers accepted
the CSS. An isolated DynamicUser headless GNOME 51 session loaded all eight
Marble extensions with state 1 and no extension errors; it did not establish
actual menu/clipboard/screenshot behavior, visual appearance or GDM login. The
final standalone extension bundle and profile built with actual makepkg in an
isolated, network-disabled DynamicUser unit and both passed the production archive
verifier. Bundle archive SHA-256 is
`dc5b328e7f3c73aa5b23b0c4f6c9c13612407a0c1923a76fb361dd6626ab10cb`, profile
`817445a1860b21d196c76efb933a4272630c8bd6eb431f0f0e39df2a1bd5d063`.
These are raw-source package revisions, not installable upgrade recommendations.
A private copy of the actual installed package database resolved the proposed
profile revision 12 and bundle revision 7 with `pacman --print -Su`; no transaction
or signature-delivery PASS is implied. Both units and owned temporary copies were
removed. Repository checks passed with full namespaces, ten scenarios, signer
PASS, exact 14/18 closures and no deferrals. The final VM harness covers seven packages, Stock repository routing and GNOME
50/51 GDM selection; 115 executable fixture checks pass. Independent review found
that the initial selector retained Arch's `1:` epoch; real epoch-bearing regressions
reproduced the failure and passed after stripping the epoch. The historical
six-package GTK3 verifier remains unchanged. Actual GDM package build and production
archive verification passed (26 assets/eight licenses), archive SHA-256
`fb6864f33f5e3848a7ecad120242d0e5f3bf589aa703382556b2192e70712038`.
`bash tests/source-tests.sh` passed for committed candidate `6b13bbd`, including
full repository namespaces with no deferrals; source log SHA-256
`020ee4630814f771412a97b2788aa034eef15aef66c94833a7d7e673831546a0`.
`git diff --check` passed.
The 29-page Markdown inventory retains historical identities and separates current
candidate instructions. Generated release overviews/commands/changelog are tested
against differing source, documentation and child versions.

The complete canonical seven-package build and separate unsigned-build verification
also passed for `6b13bbd`, in a disposable pinned Arch container with a non-root
builder, read-only source and limits of two CPUs / 4 GiB. An independent host-side
verifier passed and matched the clean source commit/tree, installer, package-set
and unsigned-manifest hashes. The container was removed; public build artifacts
and compact receipts remain under `/tmp/arch-linux-g51-canonical.t7zpjgm5` for the
remaining bounded checks. Exact identities are in
[validation](validation.md#gnome-51-candidate--2026-10-09). These are raw-source
package revisions, not the future release child's upgrade revisions, production
signatures or installed-system acceptance.

Checkpoint: concurrent runner documentation and atime-only recovery fixes are
preserved on main `bc135f0` (following PR #62). This task has made no host upgrade,
live session restart, production signing or publication. The advisory detected
GNOME/GTK drift; unavailable AUR queries are errors, not evidence of no update.
Real signed upgrade/GDM/functionality, release and public pacman delivery remain
open. The existing GTK3 migration scenario leaves the extension bundle installed;
it does not construct the old four AUR owners or local No Screenshot Box copy.
Its PASS must not close the new migration gate. Source is reviewable locally.
GitHub rules for main currently require a pull request and successful `Source checks`;
the checkout contract requires an owner exception before a PR branch is created.
The owner subsequently granted the branch/delivery exception recorded below. The canonical unsigned
build receipt binds `6b13bbd`; subsequent documentation edits do not relabel that
receipt. The eventual release child still requires its own build, signatures,
actual old-AUR/local-extension migration and runtime acceptance.

Additional migration gate implemented locally: the original GTK3 test remains
unchanged, with a separate mandatory staged transition from authenticated release 1.0.6, all four
actual pinned AUR packages and the exact local extension to the signed candidate.
The preparer builds AUR packages as a disposable unprivileged builder; the
guest must prove that the bundle was absent, record user settings, perform actual
GDM password logins before/after plain `pacman -Syu`, and verify replacement,
custody, settings and active profile. The finalizer must require the new assertion
and compact input/session evidence. Source/runtime fixtures and the strict
repository consumer pass, including rejection of changed receipts, missing
evidence and missing or repeated session markers. Independent review found that
an input manifest could be rewritten with its AUR payload; consumption now
requires the digest returned directly by trusted preparation, verified again
after the input copy. Docker cleanup also handles timeout after daemon-side
creation using the exact per-run ownership label. These checks do not establish
actual migration or extension behavior: eight enabled states leave the separate
Clipboard/Dash/Blur/No Screenshot Box functional checks open.
The candidate now additionally drives three behaviors through real QMP keys and
pointer input after migration and after reboot: Clipboard history/copy/paste,
Dash-specific app launch and No Screenshot Box capture on release with a disabled
control. A small ordinary GTK probe observes synthetic values only. Six distinct
assertions and run/session/probe-bound receipts are mandatory in the finalizer.
Independent review fixed canonical run-ID handling, live process/start identity,
root-frozen probe hash binding and rejection of renamed old screenshot inodes.
All 126 runtime fixtures, seven evidence-consumer tests and native isolated GTK
startup passed. These are source/native-probe results, not execution of the six
GNOME behavior assertions. Actual signed VM migration and Blur/appearance checks
remain open. The full source run caught an outdated assertion-producer fixture;
it now invokes the real new helper with only VM/input observations stubbed and
checks the complete 33-assertion Marble closure.
Official AUR Git TLS failed; the official
Arch AUR mirror reproduced all four existing archive, `.SRCINFO` and hardened
PKGBUILD hashes without changing the trusted pins. Upstream source builds remain
part of the actual input-preparation gate.

The expanded source candidate `79623c4` passed the full source suite, including
121 VM fixture checks, 15 upgrade-input checks and full repository namespaces
with no deferrals. Its source log SHA-256 is
`57d5b5f32f4b4240e14b0e01de55803b36fe3bd9ec0dc42f3866bec318da3a8a`.
Real input preparation found an outdated Arch keyring in the pinned container
before any AUR build. Authenticated `archlinux-keyring` upgrade from
20260727 to 20260909 passed in a disposable diagnostic container; preparation now
requires it before the full system upgrade, following the
[Arch package-signing guidance](https://wiki.archlinux.org/title/Pacman/Package_signing#Upgrade_system_regularly).
That change alone did not fix the large transaction's GPGME failure. A controlled
repeat with Docker `--init` passed all 422 signed packages with unchanged trust and
resource limits; peak task count was 16/256 with no limit hits. The preparer now
requires an init process to reap orphaned children. Sequencing/failure fixtures
pass. This did not relax package signature checks; the subsequent complete
four-package preparation is recorded below. Owned preparation/diagnostic
containers were removed.

Release-host diagnostic attempt for `6b13bbd`: ordinary and required-full-namespace
repository modes passed in the disposable Arch container. The publication-root
test then rejected the fixture because its dedicated signing account had not
been provisioned; the two root keyring modes did not run. This is an incomplete
test-environment attempt, not a five-command or production-signing PASS. The
container was removed; the next integrated attempt must provision the same locked
account as the configured release setup before running those checks.
The `79623c4` attempt provisioned that account and again passed both repository
modes, but the sealed launcher's snapshot mode rejected the container boundary.
The cause was Docker overlayfs directories reporting one link, violating the
existing strict directory identity check. A private tmpfs fixture, without a
source or safety-policy change, passed the complete publication-root test for
`d81f0a0`, including supervisor death and exact 14/18 closures. Ordinary and full
privileged keyring checks also passed. The latter used only its own verified
Docker cgroup subtree and disposable loop-backed disk; all owned resources were
removed and host device metadata stayed unchanged. These
disposable test keys do not establish production signing. Exact receipts are in
[validation](validation.md#gnome-51-candidate--2026-10-09).
The full source suite also passed `d81f0a0`, log SHA-256
`296434ddd3e019d9594bcfd1843f58bb07fbf803feed35de2a01f74bd07bfcae`.
The expanded functional candidate `a1a3d26` then passed the complete source suite,
including the 33-assertion producer/consumer contract and full repository
namespaces without deferrals; log SHA-256
`7f1c29d8bc24346e1ac969a5812e8dda8470ca6a25f2092effbb22586370ca1c`.
Real input preparation built the old Blur, Clipboard and Dash packages, then
rejected the Dash handoff because makepkg retains its `1:` epoch in the archive
filename. The focused fix copies those unchanged bytes to the already agreed
epoch-free VM input filename while retaining exact epoch-bearing `.PKGINFO`
validation. Sixteen input checks passed, including byte-preserving copy and wrong
version rejection. That incomplete output and its owned container were removed.
The subsequent `4f3b120` attempt built all four actual packages, then rejected the
Clipboard archive's existing `clipboard-history` conflict. Exact, hash-bound
original `.SRCINFO` records confirmed that this is the only declared conflict
among the four recipes. The verifier now requires precisely that conflict for
Clipboard and none for the others, while still rejecting provides, replaces and
install authority. Seventeen input regressions pass, including unexpected,
duplicate and missing conflict cases. No unsigned package was installed on the host.
The independent publication-root rerun also passed for `a1a3d26`, with the new
functional-evidence consumer and fixture; its original tree binding is retained
in validation rather than transferred to later helper changes.

Complete legacy-input preparation and two independent verification executions
passed on clean commit `7a61c40`, tree
`ea4367c55601b3c4c920759e5ecf90468e519613`. All four real AUR packages pass the
production archive/metadata guards; ten original release assets and the local
extension match their authenticated pins. The exact 15-file payload closure is
bound to independently captured manifest SHA-256
`4df9dfb4bb0089d4dca0db10c75173e414d417f38d6d6ad013a0b3f1320a4972`.
The root verifier used that literal trusted receipt rather than accepting a hash
derived from the mutable manifest. Compact logs and public inputs remain in
`/tmp/arch-linux-g51-upgrade-inputs.k7RaB53Q`; its container and temporary recipes
were removed. Full identities are in validation. This closes preparation only;
the clean release child must prepare its own tree-bound inputs and execute the
actual migration, the baseline and both recovery GDM logins, and six functional
assertions before acceptance.

Final local source checkpoint: `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`
passed on clean candidate `c5a2b8f`, including all 17 upgrade-input regressions,
126 runtime fixtures, documentation/link checks for 29 Markdown files,
ShellCheck and full repository namespaces with ten scenarios, exact 14/18
closures and no deferrals. Exact commit/tree/log identities are in validation.
All delegated work has returned; no owned build/diagnostic container remains.
Remote main remains `bc135f0` and the latest public release remains 1.0.6.
The delivery candidate was merged through [PR #65](https://github.com/snaplyze/arch-linux/pull/65).
On 2026-10-09 the owner explicitly granted full permission
for `fix/gnome51-upgrade-20261009` in this same checkout, protected PR/merge and
the configured release process. Preserve the candidate commits on that branch
and return the canonical checkout to main by fast-forward after the accepted
squash merge. No additional checkout, trust change or historical asset replacement
is needed. Actual signed upgrade/GDM/functional and
appearance acceptance, publication and public pacman recovery remain open.
The final pre-authorization candidate `bb62952`, tree
`dbf40c5f12331ba6e45ceaa2b9aed55788b10a2b`, also passed the complete source suite;
log SHA-256 `94b73f0fdee0f508886d09c8412485401863d4a18ff126221e97ba2b004670c9`.

Authorized delivery preflight found the same missing init process in the
canonical package-build container. It now uses `--init`; all five Arch dependency
bootstraps authenticate an `archlinux-keyring` refresh immediately before the full
system/dependency upgrade. Signing containers already had init. The previously
reproduced large-transaction failure and successful 422-package control justify
this focused alignment; signing-job failure is not claimed as reproduced.
Real workflow-step regression execution rejects missing ordering and a failed
keyring refresh before any full transaction (seven failing subcases before the
fix; all 21 Actions release checks now pass). Independent review found no remaining
issue in the initial three-file change. The full suite then exposed an older
static check that required init/populate to be immediately adjacent to the full
upgrade. That check now requires the authenticated refresh too and rejects its
removal. The identical readback and advisory build bootstraps were aligned after
six additional failing subcases reproduced their omission. Pins, signature policy and signing authority are
unchanged. The preceding full source run on `1424dfc` passed with log SHA-256
`0d7bcd9247303efb95933c44be89636f407b881be4b461fe1a953a63d5a6d71d`;
the corrected delivery head requires fresh source/CI checks.
Read-only delivery-runner checks confirmed runner 21 online/idle, exact pinned
Arch Docker image, runner-account Docker access and KVM API 12, four vCPUs,
12 GiB total memory with more than 8 GiB available, and over 32 GiB free workspace
storage. The QGA channel belongs to the documented `ubuntu-actions` VM under
`qemu:///session`. No shared setting, service or workload was changed; these
readiness checks do not substitute for the release's actual nested-QEMU run.

PR candidate `7a632ea` passed the full local source suite (log SHA-256
`d186c9d19131a0213d58f964c60de2739815c83683068781b18ffa5510a2be72`).
[CI 37878221431](https://github.com/snaplyze/arch-linux/actions/runs/37878221431)
then failed the custody fixture: ext4 reused the just-freed inode when the test
unlinked and recreated identical bytes. An independent runner-account experiment
reproduced reuse three times out of three. The corrected fixture allocates its
replacement while the original is live, asserts distinct device/inode identity,
then replaces the pathname; the unchanged production verifier must reject it.
The focused test and independent review pass. Its one tiny runner fixture was
removed. No failed CI result is treated as acceptance.

Protected delivery accepted candidate `34da98bb34ed57a795e498104c6cf5321b1467d2`,
tree `4209061d00423d88e62acfcb1bba1761e1fb417c`, canonical source SHA-256
`0f363c1ac3e3dc9d754791e5bbe664f0e00d514de46267f95e8a627a9a38cf76`.
The full local source suite passed (log SHA-256
`15b415ead68e0e5ec8262b04e7add1b23efdefb1fadf5c97a9b282fc01c36a24`), and
[PR CI 37878611896](https://github.com/snaplyze/arch-linux/actions/runs/37878611896)
passed with full namespaces, ten scenarios, signer and exact 14/18 closures,
no deferrals (CI log SHA-256
`ae3ac0bfecb2496cc6fba017ec978541c182125d26fc06ebcf312c451cb37f7f`).
PR head/base, mergeability, required checks and empty review-comment state were
rechecked before exact-head squash merge. Accepted main is
`63c9e6c9e80321112405e32f8c6cef0b4ed59ef4`, with the same tree and canonical hash.
This checkout returned to main by fast-forward; all candidate commits remain on
the task branch. [Main CI 37878934364](https://github.com/snaplyze/arch-linux/actions/runs/37878934364)
passed and triggered configured [Release 37879163690](https://github.com/snaplyze/arch-linux/actions/runs/37879163690)
for that exact accepted main. Release-child preparation and canonical unsigned
build passed, but the separate artifact readback failed before signing: the
checked-out public `repository/trust/arch-linux.gpg` was group/other writable.
The strict verifier rejected that source mode after both metadata digests passed.
The run is terminal FAIL; signing, all QEMU stages, draft/tag creation, Pages and
publication were skipped. The prepared child is `5ee1439` for 1.0.7; independent deterministic
reconstruction and source-bundle verification passed. Exact identities and seven
generated package versions are in validation. Independent download checks match
the artifact digest, both metadata hashes and every member of the fourteen-file
unsigned manifest, but do not close the failed production readback. The focused
correction gives readback a root-owned independent clone of the exact child,
with safe ancestor, ownership, mode, Git identity and artifact digest checks
before and after verification. The shared checkout is not chmodded; the
source-mode guard and pinned input bytes remain intact. Eighteen readback-specific
negative mutations and independent review passed. A bounded native replay against
the failed run's actual seven-package artifact passed: the original verifier
rejected mode 0666, the corrected workflow accepted the protected exact clone,
and making that clone writable was rejected. Original unsafe checkout modes and
verifier bytes stayed unchanged. Native log SHA-256 is
`b875a3cb1b2bafd5a03ae198b2a33276cbb4c12436b94868314140d92046f421`.
The disposable container and large test inputs were removed. Post-job cleanup removed the runner checkout's
Git directory, so the original file mode cannot be measured again and its
checkout umask remains an inference, not a separately observed fact.
Signing, real VM migration/functionality, publication and public recovery remain
open. This progress record is local until the final documentation reconciliation
is published.

Readback correction delivered through [PR #66](https://github.com/snaplyze/arch-linux/pull/66).
Exact head `6647443346414c1c225ad7649f7e67e4c6d639d6`, tree
`40003be954e025d0c82aad905c2d4c1cee704f6d`, passed the full local source suite
(log SHA-256 `9d2d593f59f79191abcc24c4b78ca02947c81f6e81f0f882184af7736eb25143`)
and [CI 37880505032](https://github.com/snaplyze/arch-linux/actions/runs/37880505032)
(log SHA-256 `a18ff65ce180015602949a7ec96e5b6eefca9adf425ee6fd04d0a72bce8a4e36`).
After exact-head/base/check/review-thread verification, protected squash merge
produced main `aa462e1bdfafa5df29b994d0795a9066a2e2cfe9` with the same tree and
canonical SHA-256 `6f7fc682f32df4c627f5270f208adde604fed3d3c6d198a522f1efda3eab6a3d`.
This checkout returned to main by fast-forward; candidate history remains on
`fix/gnome51-release-readback-20261009`.
[Main CI 37880765176](https://github.com/snaplyze/arch-linux/actions/runs/37880765176)
passed and triggered [Release 37880984567](https://github.com/snaplyze/arch-linux/actions/runs/37880984567).
Child preparation and canonical seven-package build passed. The protected source
check now passed in the actual readback job, which then rejected a downloaded
package's mode (`unsigned package mode differs`). This second run is terminal
FAIL before signing; VM and publication stages were skipped. The first native
replay reproduced source checkout modes but did not reproduce action-extracted
artifact modes. Correction now covers the downloaded-input boundary explicitly,
with deterministic public-file modes in an owned protected directory and an
expanded native replay. Symlinks, special objects and hardlinks are rejected
before normalization. Executed workflow regressions reject the original package
mode failure and pass after byte-preserving normalization; 23 Actions tests and
26 readback mutation checks pass. Lookahead review also reproduced a new-shell
umask failure in the snapshot regression clone: a controlled ambient mask 000
produced mode 0666 and failed; step-local mask 022 fixed it. This is a fixture
reproduction, not a previously executed snapshot failure. Independent review
found no remaining material issue in the four-file correction. Production
package mode/byte guards remain unchanged.
The expanded native replay passed against this attempt's actual seven-package
artifact, including controlled mode-0666 failure before normalization, unchanged
bytes afterward, protected-archive tamper rejection, and the real release clone
prefix under ambient mask 000. Native log SHA-256:
`5c676e29a3e41656e3a9d3554b20d8ee6bc5ff54019c005d5b5149854ed4e750`.
The full source suite passed before this evidence prose (log SHA-256
`74018840ade4c96650db680758e8268cca5de2e8c27232264d3e574de5724a71`).
Owned containers and large replay fixtures were removed. A tiny no-network probe
on the idle actual runner confirmed directory link counts of two under both
`/var/lib` and `/run`; the local Docker count of one does not establish a runner
signing-boundary failure. No host setting or signing authority changed.
Exact child and failed-run identities are retained in validation. Signed VM
acceptance and public recovery remain pending.

## Local runner migration — 2026-10-08

Owner request: move all five GitHub Actions workflows for `snaplyze/arch-linux`
to local runners while preserving source checks, package verification, signing,
QEMU acceptance and protected-main delivery. Historical starting baseline:
clean `main` / remote `cf1e46925756cd43ce2bb176ae26de6b6908ad70`; all 18 job
definitions selected `ubuntu-24.04`, and the public repository had no registered
local runner. The accepted migration is now on `main` at
`7430a0b3e2b04ad66bd36a215eb1e494a404962a` ([PR #61](https://github.com/snaplyze/arch-linux/pull/61)).

- **DONE:** owner chose manual review before external fork PR execution.
  GitHub `actions/permissions/fork-pr-contributor-approval` was updated and read
  back as `all_external_contributors` (previously `first_time_contributors`).
- **DONE (2026-10-09):** owner chose the existing shared `ubuntu-actions` VM.
  After idle-only shutdown/start it has 4 vCPU / 12 GiB guest RAM, on-demand
  allocation and virtio free-page reporting. A real 2 GiB allocation/release
  changed host RSS from 2250 to 4302 to 2366 MiB; 1936 MiB was returned.
  Same Boxes domain/UUID/disk retained. Guest time was about 584 seconds slow;
  chrony now permits stepping after resume. All three existing runner services
  recovered, including the stopped github-actions listener, without replacing credentials.
- **DONE:** official runner 2.338.0 archive verified against its release SHA-256;
  `ubuntu-actions-arch-linux` registered through a short-lived API token and
  confirmed online. User `runner-arch-linux`, a private project home, project
  tool cache and systemd service; no owner-supplied token or PAT copied to the VM.
  Dedicated rootful Docker storage/socket; existing rootless daemons preserved.
  QEMU/OVMF and host verifier dependencies installed; KVM group and an actual
  device-open/API-version startup check replace Ubuntu's inaccurate external
  `test -w` result. Cleanup fixture removed owned root files while preserving a
  symlink target outside the job paths and rejecting the wrong caller.
- **DONE:** all 18 job definitions in the five workflows on accepted `main` select
  `[self-hosted, Linux, X64, ubuntu-actions, arch-linux]`. Host package installation,
  global SDK/Docker deletion and device chmod
  removed; QEMU matrix limited to one job. Hosted namespace deferral removed;
  dedicated container profiles permit the real namespace checks without changing
  the shared host AppArmor sysctl. Final full source suite passed with
  `namespace_fixtures=full`, `deferred=none`; actionlint 1.7.12 passed with the
  two API-confirmed custom labels. Independent review found the KVM startup
  check issue described above, corrected and verified by the actual operation.
- **VM PROBES PASS:** real nested KVM initialized four CPUs and an 8 GiB guest;
  QMP reported acceleration enabled. The pinned Ubuntu container's unprivileged
  full namespace probe and the pinned Arch signing container's actual helper
  both passed; host namespace sysctl remained 1. These are environment probes,
  not installed-system or production-signing acceptance.
- **DONE — source CI and migration delivery:** protected-main [PR #61](https://github.com/snaplyze/arch-linux/pull/61)
  merged after [Source CI 37850459758](https://github.com/snaplyze/arch-linux/actions/runs/37850459758)
  passed for exact PR head `2825b37b28a57bdb77933c7328e2c86ce487f452` on
  `ubuntu-actions-arch-linux`. [Manually dispatched main CI 37850869082](https://github.com/snaplyze/arch-linux/actions/runs/37850869082)
  passed on the same runner for merged main `7430a0b3e2b04ad66bd36a215eb1e494a404962a`.
  This establishes actual self-hosted source CI and delivery of all five workflow
  selectors; it does not establish execution of their other jobs.
- **NOT_RUN — product/runtime gates:** full installer scenarios, production signing,
  release and public readback on this runner remain unrun. The 8 GiB nested KVM
  result above covers initialization only; no published release assets were replaced.
- **Documentation preparation — 2026-10-09:** owner requested README/testing/plan
  reconciliation with this accepted state. The prepared scope uses the same
  protected-main PR/check procedure and avoids triggering an unrelated release.
  Local documentation/link checks (`python3 tests/docs-checks.py`, 29 Markdown
  files) and `git diff --check` passed; no workflow, source, test or configuration
  changes belong to this documentation follow-up.

PR #61 live CI exposed three environment contracts absent from local probes:
runner hooks require `.sh` filenames, the checkout leaf must permit traversal
by container validation users, and this Docker runtime starts `docker exec`
with umask `0000` (unlike `docker run`, which used `0022`). Hook names and the
checkout leaf were corrected without changing private project-home permissions.
Source preparation, validation and canonical readback now explicitly set
`umask 022`; regression checks reject removing it. The readback mask also
prevents Git's index refresh from reopening `.git/index` with group/other write
access. Both failures were reproduced in the pinned container; package and
canonical source mode checks remain strict.

The current release workflow starts after a successful main push CI, including
workflow-only changes. The established documentation-publication procedure can
avoid an unrelated installer release: first require successful exact-head PR CI,
then squash with `[skip ci]`; explicitly dispatch CI against the merged main for
separate verification (its event does not satisfy the release job's push gate).
This does not establish QEMU, signing or release acceptance on the new runner.
The shared persistent VM is not a disposable job boundary: approved workflows
with rootful Docker access can control the guest. Fork approval requires actual
code review; separate runner accounts do not isolate this authority from the
other projects. Earlier product work and historical evidence below remain a
separate scope.

> Current mode (2026-10-04): owner-authorized autonomous implementation of the full registry.
> Reuse completed agent setup, audit and planning outcomes; do not restart them.
> Use bounded `codex-orchestrator` / `superpowers:subagent-driven-development`,
> subject to [AGENTS.md](../AGENTS.md).
> This is the single product improvement registry. Update statuses and checkpoint here.

**Goal:** устранить подтвержденные риски установщика, принять актуальные входы Arch Linux,
проверить поддерживаемые варианты и завершить доставку в main новым immutable-релизом.

**Architecture:** сохранить текущие границы installer/bootstrap, подписанных пакетов,
изолированного signing и tree-bound acceptance. Исправления выполнять точечно; документы
разделить по пользовательским задачам, справке, объяснениям и процедурам сопровождения.

**Tech stack:** Bash, Python 3, C static PIE, pacman/makepkg, GnuPG, systemd namespaces,
QEMU/KVM/OVMF, GitHub Actions/Pages.

**Spec:** поручение владельца от 2026-10-02; нормативный [AGENTS.md](../AGENTS.md),
[compatibility](compatibility.md), [validation](validation.md), [release process](release-process.md).

## Scope and constraints

Текущее поручение от 2026-10-03: автономно выполнить все 15 обязательных ID реестра
и их под-планы до проверенного результата, включая GATE-01 и RELEASE-01. Предыдущий
документальный аудит завершен и не повторяется. Исполнение начато в том же checkout
на main; исторические ограничения аудита ниже относятся только к тому поручению.
Новый Goal активирован штатным инструментом; запись и приемка находятся здесь.
Релиз выполняется лишь после локальной приемки через заданный pipeline. Исключение
для PR-ветки, review новых pins и отдельная внешняя package-only authority сохраняются;
запросы нужны только перед соответствующей зависимой операцией, после независимой работы.

- Единственный физический checkout, работа на main; не создавать worktree/clone для разработки.
- Сохранить существующие dirty изменения владельца, индекс, настройки, модели и права.
- Stock GNOME — default; Minimal, Marble и отдельный GDM opt-in сохраняются.
- Сохранить ext4/Btrfs, GRUB/systemd-boot, LUKS2, fresh install и безопасный dual boot.
- Ошибка определения диска, занятости или подписи останавливает зависимое действие.
- `PackageRequired DatabaseRequired TrustedOnly`; никаких unsigned fallback и автоматических pins.
- Не запускать destructive installer на рабочей машине; только disposable VM.
- Не менять ключи/отпечатки/источники автоматически. Предложенные новые входы требуют
  человеческого review и соответствующих тестов до принятия.
- Продуктовые проверки и артефакты не смешивать с настройкой агентов AS-1…AS-5.
- Владелец явно разрешил включить все текущие изменения, включая чужой baseline, в commits.
  Более поздние конкурентные правки сохранять и проверять отдельно; конфигурационные
  backup/recovery-механизмы не создавать.
- Не публиковать детали эксплуатируемых проблем в issues без координации по [SECURITY.md](../SECURITY.md).

## Baseline: 2026-10-02

Аудит выполнялся в физическом корне этого репозитория на main:

| Identity | Observed value |
| --- | --- |
| HEAD / origin main API | `0d7ce452dfd8d8e4a8ecdf96a25caa22a4600263` |
| HEAD tree | `59cb42d0f8fb71a7ee357c6a3beca4d7783b153f` |
| Existing work | Modified `AGENTS.md`; untracked `.codex/`, `docs/agent-setup.md` |
| Index | Unchanged during audit; source suite ran against actual dirty working bytes |
| Source inventory | 178 tracked paths; installer 7,533 lines |
| Latest release API | `1.0.5`, immutable, 18 assets, published 2026-09-17 |
| Release commit / tree | `61add3e0b2c20adbbdd425494eae02ddec0a3bac` / `b5ca51e80277d93541d00a305490ac818d629a33` |
| Release parent | Current main HEAD above; deterministic release child, not main itself |
| GitHub main rules | PR required, squash only, strict `Source checks`, resolved review threads, no deletion/non-fast-forward |

Live checks used GitHub read-only API. The classic branch-protection endpoint returned 404;
the branch endpoint and `rules/branches/main` confirmed ruleset protection. Do not interpret
the classic endpoint's 404 as permission to push directly.

External audit artifacts: `/tmp/arch-review-20261002-5t64vzw6` contains hash/mode baseline,
unchanged-index hash, source log, harmless reproducers, ISO/package/key reports and public
release metadata. These temporary files are supporting evidence, not persistent plan dependencies;
the commands, identities and outcomes needed to continue are recorded here. No private material.
This is a historical temporary location from the previous audit, not a required input or an
external report for the 2026-10-03 assignment. All continuation evidence is kept in this registry.

### Documentary audit baseline: 2026-10-03

Physical repository root verified by `pwd -P`; native local client `codex-cli 0.160.0`.
At 07:14 UTC the branch was main, HEAD/tree matched the October 2 identities above.
The index was clean and its SHA-256 was
`33c6aa782ec89baf5fe3108a65a0d504d94ac17ce3363c54e89d684343e308c8`.
Existing changes before this audit: modified `AGENTS.md` and `docs/README.md`; untracked
`.codex/`, `docs/PLAN.md`, `docs/agent-setup.md`. These are preserved as the baseline,
not attributed to this new task. An in-memory byte/mode manifest covers 183 tracked and
visible untracked files; own document edits are compared separately. No backup/config clone.

Root is the sole editor. Three existing read-only specialists cover installer/error-path gaps,
trust/release/planning gaps and current primary-source drift; no recursive delegation.
Installed child cap is 3; active role definitions take precedence. No model, reasoning,
permission, global settings or orchestration changes are part of this audit.

The unchanged product baseline allows reuse of confirmed F-01…F-10 evidence. The new pass
checks gaps, documentary claims and mutable external facts; historical tests are not relabelled
as fresh. Scope and per-area coverage below will be updated as evidence is confirmed.

### Executed checks and limitations

| Check | Status | Evidence / limit |
| --- | --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` | EXECUTED_PASS | Exit 0; `all required source tests passed`; full marker below |
| `git diff --check` before document edits | EXECUTED_PASS | Exit 0 |
| Baseline byte/mode + index comparison | EXECUTED_PASS | No baseline changes during audit |
| Actual `exec_prepare_disk`, privileged effects stubbed | EXECUTED_FAIL | Guard rejection followed by executor result 0; defect F-01 |
| Actual `target_storage_is_idle`, probes stubbed with exit 2 | EXECUTED_FAIL | Accepted idle state despite failed probes; defect F-02 |
| Extracted actual boot-entry write, temporary directory | EXECUTED_FAIL | Existing neighbor `main.conf` overwritten; defect F-03 |
| `python3 maintenance/check-arch-iso.py` | EXECUTED_PASS | Detector reports September → October drift; this is not ISO acceptance |
| `python3 maintenance/check-sources.py --network` | EXECUTED_PASS | Advisory report; no automatic changes; drift is not compatibility proof |
| `python3 maintenance/check-key-lifetime.py` | EXECUTED_PASS | Healthy public signing subkey, 706 days remaining, expiry 2028-09-08 |
| Download acceptance JSON/signature + `gpgv` using committed public certificate | EXECUTED_PASS | Release 1.0.5 acceptance signature exit 0; downloaded bytes match API digests |
| Existing GitHub CI / release workflow | REVIEWED_ONLY | API says success; not freshly executed by this audit |
| Fresh clean Arch build, production signing, root publication/keyring acceptance, QEMU | NOT_RUN_ENVIRONMENT | Not executed in this planning assignment; require dedicated bounded execution |
| Full current release archive/Pages verification | REVIEWED_ONLY | API metadata and signed acceptance checked; all published bytes not reverified here |

Source fixture marker:

```text
REPOSITORY_CHECKS_RESULT schema=1 namespace_fixtures=full scenarios=10 signer=passed release_closures=14+18 deferred=none
```

This PASS does not invalidate the negative reproductions, prove current installation behavior,
or transfer September's VM PASS to October's ISO/packages. The signed 1.0.5 JSON binds three
historical PASS results to ISO `be845803…61c91`, with `deferred=[]` under that release contract.

## Audit coverage

Coverage refers to the unchanged product bytes at HEAD `0d7ce45` plus the October 3 documentary
baseline. `Проверено` means the stated read-only/static or executed check was completed, not
formal proof or production acceptance. Runtime gaps are explicit. No dead-code removal is proposed
from file size alone; consumed entrypoints/helpers were traced through callers and tests.

| Area / key scenario | Coverage | Evidence and remaining limit |
| --- | --- | --- |
| Instructions/client/physical root/Git/dirty/index | Проверено | Native Codex 0.160.0, main/HEAD/index and 183-path manifest; only audit wording/docs may change |
| Requirements/registry/dependencies/statuses | Проверено | Existing F/task IDs preserved; source vs derived-child vs public gates separated; DOC-only completion separate |
| Bootstrap/self-update/public trust | Частично | Prior bootstrap review retained; source reads trace root handoff/fingerprints; no new public bootstrap execution |
| Configuration/account/preflight | Частично | Parser and semantic source paths reviewed; F-11 actual-function stub evidence; real user creation NOT_TESTED |
| Identity/busy checks/fresh/ext4/Btrfs/LUKS | Частично | Prior F-01/F-02 evidence retained; additional unchecked AUR scan reads; physical hotplug/mutation NOT_TESTED |
| Dual boot/ESP/GRUB/systemd-boot/snapshots | Частично | Generic boot-file writes and isolated neighbor fixtures traced; no fresh real boot or module-pair validation |
| AUR/dependencies/user privilege/files/sudoers | Частично | Pins/.SRCINFO/cgroup/account/target-UID handoff traced; operational scan failure gap F-02; live builder NOT_TESTED |
| Failure/cancellation/cleanup/concurrency | Частично | Actual exit handler with all effects stubbed reproduces F-13; no live kill/mount/crash injection |
| Package metadata/payload/performance/resources | Частично | F-04 retained; verifier code inspected; no clean package build or compression-bomb stress test |
| Repository database/package consistency | Частично | Actual database heredoc accepts inconsistent in-memory records F-12; no live production signature exercise |
| Signing sealer/launcher/FD/namespace authority | Частично | Follow-up reads capture/account/drop/capability/seals/namespace/cleanup; no demonstrated new bypass; no exhaustive race proof |
| CI/build/release/Pages/package-only lifecycle | Частично | Workflows/callers/provenance guards reviewed; live release/main API refreshed; F-14 route contradicted by source guards |
| Marble/GDM/GTK activation and lifecycle | Частично | Prior lifecycle evidence retained; deactivation errors scoped in docs; no fresh GDM/Wayland/rendering/update |
| Tests/source regressions and doc commands | Частично | Existing tests inspected; prior PASS preserved; final safe suite/check outcomes recorded at checkpoint |
| External Arch/packages/ISO/extension/upstream maintenance | Проверено | Live official API/advisory snapshot October 3; no accepted pin update; APIs do not prove mirror/runtime availability |
| Deployment/real QEMU/physical hardware | Не проверено | Outside documentary audit; NOT_TESTED, no signing/release/VM provisioning/host dependency mutation |
| MDX/notebooks/executable docs | Неприменимо | No such file is in the allowed edit set; only Markdown prose and one AGENTS audit clause edited |
| General cleanup/structural reorganization | Неприменимо | Explicitly excluded; navigation and historic IDs/content retained |

## Review findings

P0: urgent critical impact (none confirmed). P1: high damage potential and blocks a new candidate
until corrected/regression-tested. P2: ordinary correctness/risk correction or acceptance gap.
P3: low-risk documentary/maintenance improvement. Type and confidence are separate from priority;
priority alone does not authorize a new feature or automatic version upgrade.
Line references below belong to the audited bytes; use named functions after edits.

| ID | Priority / evidence | Finding and consequence | Owner task |
| --- | --- | --- | --- |
| F-01 | P1 / reproduced with stubs | `exec_prepare_disk`, installer lines 3375–3520: `assert… && command` suppresses errexit on assertion failure. Post-open rejection can skip mkfs/mount yet reach success. `activate_storage_marker` checks the snapshot, not a mounted root. Downstream pacstrap writing into an unmounted `/mnt` is an inferred risk, not executed. | SAFE-01 |
| F-02 | P1 / reproduced with stubs | `target_storage_is_idle`, lines 2236/2243/2253/2258: unchecked process-substitution statuses turn failed findmnt/swapon/lsblk probes into empty observations; operational error can authorize mutation without proof of idle state. | SAFE-02 |
| F-03 | P1 / write reproduced, boot not run | Dual boot shares ESP at `/mnt/boot`; `exec_pacstrap_core` lines 3637/3736/3743/3750/3850 install generic kernel/initramfs paths and overwrite main entries/config. Existing neighboring Linux can lose its root options/boot bytes. Current neighbor fixture isolates files under `EFI/ali-neighbor` and `neighbor.conf`, avoiding these collisions. | SAFE-03 |
| F-04 | P2 / source evidence | `verify_package_archive`, metadata verifier lines 695–735, and `verify_package_tar` line 608: unbounded zstd test/decompression and `getmembers()` can consume disk/CPU/memory before unsigned package rejection. Denial of service, not proven code execution or authority bypass. | TRUST-01 |
| F-05 | P2 / coverage gap | Release workflow runs three staged variants; dual boot, Marble with Stock GDM and complementary storage/boot choices have harness support but are absent from this release gate. Documentation honestly limits the claim; supported options still require fresh supplemental acceptance. | QA-01 |
| F-06 | P3 / verified drift | Accepted ISO 2026.09.01 differs from current 2026.10.01. Accept new state only after real VM checks; this is not an installer failure. | ARCH-01 |
| F-07 | P3 / verified drift | Gum major version and Colloid/SPDX/AUR snapshots changed. Inspect new source/licensing/ABI before choosing update or retaining reviewed pins. | UP-01 |
| F-08 | P3 / documentation freshness | README/installation/validation explicitly preserve 1.0.4 baseline while latest is 1.0.5. Links remain valid; latest-state summary is incomplete, not proof of broken installation. | DOC-01 |
| F-09 | P2 / monitoring gap | `maintenance/sources.json` observes GNOME/GDM but omits kernel, systemd, mkinitcpio, cryptsetup, pacman and GTK/libadwaita compatibility inputs; daily jobs check only key lifetime. Issue #24 says ISO unchanged while today's detector reports drift. No observation date is rendered, so old monthly findings can appear current. | MON-01 |
| F-10 | P3 / UI mismatch | `select_gnome_theme_profile`, installer around line 2825, describes Marble as GTK3 while implementation/summary includes GTK4/libadwaita. | DOC-01 |
| F-11 | P2 / actual-function fixture | Username syntax/semantic validators accept `root` (installer `properties_value_is_valid`, `validate_properties_with_reporter` line 2367, `select_username` line 2535); `useradd` line 3847 necessarily conflicts with target root after disk/package/boot work. No real account/disk operation executed. | CONFIG-01 |
| F-12 | P2 / actual heredoc, in-memory archives | `inspect_database_archives`, `repository/verify-signed-repository.sh` lines 44–79, validates .db filenames and .files desc/list counts, not package name/version/size/hash/embedded signature or .db/.files semantic correspondence. Wrong records pass; genuine outer signatures/hash bindings are still required. | TRUST-02 |
| F-13 | P2 / exit-handler stubs | `trap_exit`, installer lines 6770/6776/6782, runs storage cleanup after failed worker reap, then unconditionally deletes runtime markers even after failed cleanup. Remaining resources lose ownership/control evidence; unknown worker quiescence is not respected. No live process/mount race executed. | RECOVERY-01 |
| F-14 | P2 / conflicting source/procedure guards | `repository/README.md` package-only procedure says build exact main under existing published installer version. Main VERSION is 1.0.2; deterministic children use their new version/bytes. `offline-sign-release.sh:111` rejects version mismatch; `pages.yml:165` rejects changed installer/bootstrap. Current main cannot follow that documented route to unchanged later release. | DELIVERY-01 |

### Consolidated deltas and disposition

F-02 also covers `aur_builder_uid_scan_target_mounts`, installer lines 5744/5759:
`[ -z "$(find …)" ]` discards operational `find` failure and can falsely prove UID emptiness.
Other modes check `find` status. This shares the unchecked-observation root cause; no new duplicate ID.
SAFE-02 acceptance must reject empty-output failure and partial-output failure in target scan and
cleanup readback before privileged package handoff. No exploit or live privilege bypass is claimed.

F-09 also covers `maintenance/check-sources.py:208–218`: `shellMajor` is recorded but ignored while
the greatest extension `pk` is chosen across all shell majors. It can report unrelated-major drift;
metadata does not verify downloaded bundle hashes or establish missing future-major support.
Current No Screenshot Box metadata happens to match tag 72860 for majors 45–50; 51 is absent.
MON-01 owns per-accepted-major comparisons and explicit missing/error observations.

F-07 is **not** an automatic update list. Existing `docs/maintenance.md` already records retained
Colloid GTK pin (upstream diff concerned unshipped Cinnamon/switcher code) and retained Gum 0.17
because Gum 2.0.0 stripped ANSI styling in piped `style`/`join`. Fresh Gum 2.0.2 is only a new
review candidate. Reuse those decisions; inspect only new evidence/diffs before changing a pin.

Effort is a planning estimate: S = localized; M = cross-helper/tests; L = multi-boundary design
and runtime acceptance. Implementation risk reflects required regressions and compatibility,
not unbounded time promises. Every row is **учтена**; document state below records only prose.
The following table is the historical documentary-audit baseline, before implementation.
Its **НЕ ИСПРАВЛЕНО** / **NOT_TESTED** values are preserved as historical evidence, not current
execution statuses. Current source/runtime acceptance is the execution registry and checkpoint below.

| ID | Type / priority rationale | Documents corrected in this audit | Effort / implementation risk | Product disposition / decision |
| --- | --- | --- | --- | --- |
| F-01 | Дефект; P1, false success before downstream target writes | architecture, installation, compatibility, SECURITY, README, testing | M / high, all storage branches | НЕ ИСПРАВЛЕНО; SAFE-01, explicit stage abort + mount proof |
| F-02 | Дефект; P1 disk-idle proof missing; related AUR UID probe is source-only risk | architecture, installation, compatibility, SECURITY, README, testing | M / high, operational-error vs empty-state semantics | НЕ ИСПРАВЛЕНО; SAFE-02 checked probes/validated topology and target scans |
| F-03 | Дефект; P1 neighboring boot files at risk | architecture, installation, compatibility, SECURITY, README | M / high, dual-boot preservation | НЕ ИСПРАВЛЕНО; SAFE-03 pre-mutation collision refusal, no silent partition redesign |
| F-04 | Риск; P2 resource exhaustion, not authority bypass | package-repository, SECURITY, README | M / medium, bounds must accept genuine packages | НЕ ИСПРАВЛЕНО; TRUST-01 bounded traversal/decompression |
| F-05 | Риск; P2 supported-option and runtime fallback acceptance gaps | testing, compatibility, marble, architecture | L / medium, VM resources/provenance | НЕ ИСПРАВЛЕНО; QA-01 required supplemental and error-path acceptance |
| F-06 | Улучшение; P3 current media differs from accepted evidence | compatibility, maintenance | M / medium, real media qualification | НЕ ПРИНЯТО; ARCH-01 qualified ISO only after required real checks |
| F-07 | Улучшение; P3 review drift, existing justified no-update decisions | maintenance and this registry | M / medium, breaking CLI/source/license inputs | Review required; upgrades only proposals until reviewed; UP-01 may retain pins |
| F-08 | Улучшение; P3 later release observation missing from current summary | README, validation | S / low for summary; public re-verification separate | Docs corrected; product НЕ ПРИМЕНИМО; full 1.0.5 closure/Pages still NOT_TESTED |
| F-09 | Риск; P2 stale/incomplete or wrong-major monitoring | maintenance | M / medium, report compatibility and advisory truth | НЕ ИСПРАВЛЕНО; MON-01 dated/per-major/complete-input monitoring |
| F-10 | Дефект; P3 truncated UI description | marble | S / low | НЕ ИСПРАВЛЕНО; DOC-01 future selector-text fix with preserved values |
| F-11 | Дефект; P2 deterministic invalid input fails late | configuration, installation | S–M / low | НЕ ИСПРАВЛЕНО; CONFIG-01 reserved-account rejection before mutation |
| F-12 | Дефект; P2 signed malformed database can break package resolution | package-repository, testing | M / medium, pacman metadata semantics | НЕ ИСПРАВЛЕНО; TRUST-02 package/database cross-checks |
| F-13 | Дефект; P2 cleanup ordering and recovery-marker loss | architecture, installation | M / medium, cancel/error handling | НЕ ИСПРАВЛЕНО; RECOVERY-01 quiescence and bounded nonsecret state |
| F-14 | Дефект процедуры; P2 current-main route rejected by its guards | repository README, package-repository, release-process, README, testing | L / high, provenance and separate publication authority | НЕ ИСПРАВЛЕНО; DELIVERY-01 design/acceptance, no weakened trust or implied new authority |

Resolution, dependencies, file ownership and executable acceptance for each product row are in its
owner task below; this table is the sole finding/status registry, not another implementation queue.
There is no confirmed P0 or unverified defect promoted from a hypothesis. Optional redesigns
(GNOME 51 activation, Gum upgrade, UKI/kernel namespacing, wholesale document/module refactor)
remain proposals requiring separate design; current requirements can be met by reviewed retention,
Stock fallback or fail-closed refusal. General cleanup is excluded from this audit.

Reviewed components: immutable bootstrap and self-update; config ownership/data-only parsing;
disk/partition identities and handles; idle checks, markers/cleanup; ext4/Btrfs/LUKS and boot;
package selections, AUR builder privilege/cgroup containment; signed build/snapshot/finalization;
Actions secret transfer and release/Pages boundaries; Marble/GDM lifecycle and compatibility;
source/fixture/VM tests, maintenance, documentation and ADRs.

No additional signing-authority bypass was substantiated. Launcher C, FD/namespace guards and
sealer received selective boundary review, not exhaustive formal verification. Physical hotplug,
GPU/firmware coverage and every boot combination remain unproved. Custom GTK4 CSS replacement
without backup is explicit documented behavior, not newly classified as an accidental defect.
Keep that user-visible consequence clearly documented; changing it would require separate design.

## Current Arch context

Snapshot first queried October 2 and refreshed on 2026-10-03 UTC using official package/ISO APIs;
fetch again before implementation/freezing inputs. Stable mirrors may lag API records.
Stable package versions are observations, not new project pins or proof of compatibility.

| Input | Accepted/current observation | Planned treatment |
| --- | --- | --- |
| Official ISO | Accepted 2026.09.01; current 2026.10.01, included kernel 7.2.7 | ARCH-01 |
| Current stable kernels | linux `7.2.8.arch1-2`; linux-lts `6.18.54-2`; linux-zen `7.2.8.zen1-2` | Resolve all selected kernels/headers and boot affected paths |
| systemd / mkinitcpio | `262-1` / `42.2-1` on October 3 (October 2 snapshot was `42.1-1`) | Password-based LUKS, sd-encrypt, sd-volatile, update/reboot checks |
| cryptsetup / GRUB / pacman | `2.8.8-1` / `2:2.16-1` / `7.1.0.r9.g54d9411-2` | Runtime boot/transaction and AUR dependency review |
| Arch keyring | `20260909-1` | Clean disposable build keyring; separate from project key |
| Arch GNOME Shell / GDM | `1:50.5-1` / `50.3-1`, matching accepted inputs | Preserve current reviewed assets; GDM out-of-date flag is advisory |
| GTK4 / libadwaita | `1:4.22.5-1` / `1:1.9.4-1` | Existing declared Marble compatibility; actual lifecycle/rendering checks |
| GNOME upstream | 51 released 2026-09-16; Arch stable observations above remain 50 | Prepare unknown-major fallback; do not claim Arch stable already moved to 51 |
| Gum | Pin 0.17.0; release 2.0.2 | Review breaking CLI changes before replacement |

New ISO SHA-256: `684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5`.
Accepted previous hash: `be8458032f8105e60ee2a3067f950b6e3c007ee51b38dac50e8b48e765561c91`.

Arch's 2026-09-22 mkinitcpio >=42 notice concerns TPM2 PCR-bound unlock policies.
The installer uses systemd/sd-encrypt but does not enroll TPM2. Treat this as conditional
post-install guidance for TPM-enrolled systems, not a demonstrated password-unlock defect.

Official news RSS was also checked. NVIDIA's transition to open modules and removal of Pascal/
older support is already reflected in the installer prompt and driver selection (lines 2959,
4315–4352); preserve that boundary and test package resolution for each kernel. The June AUR
malicious-update notice reinforces manual PKGBUILD/install-script review; a changed ref is not
evidence that these project pins are malicious. The April iptables nft-default notice is relevant
to users' existing firewall rules, with no direct installer-managed firewall migration identified.

Primary sources:

- [Official Arch download metadata](https://archlinux.org/download/) and [October release](https://archlinux.org/releng/releases/2026.10.01/).
- [Arch packages](https://archlinux.org/packages/): core/any for mkinitcpio/keyring,
  core/x86_64 for core binaries, extra/x86_64 for linux-zen/GTK/GNOME; direct current observation URLs below.
- Fresh direct observations: [mkinitcpio API](https://archlinux.org/packages/core/any/mkinitcpio/json/),
  [GNOME Shell API](https://archlinux.org/packages/extra/x86_64/gnome-shell/json/),
  [GDM API](https://archlinux.org/packages/extra/x86_64/gdm/json/) and
  [extension metadata](https://extensions.gnome.org/extension-info/?uuid=no-screenshot-box%40screenshot).
- [mkinitcpio TPM2 intervention notice](https://archlinux.org/news/mkinitcpio-42-requires-manual-intervention-for-tpm2-based-unlocking-of-luks-devices/).
- [GNOME 51 release notes](https://release.gnome.org/51/) and [Gum releases](https://github.com/charmbracelet/gum/releases).
- [Official Arch news RSS](https://archlinux.org/feeds/news/), [NVIDIA support transition](https://archlinux.org/news/nvidia-590-driver-drops-pascal-support-main-packages-switch-to-open-kernel-modules/),
  [AUR incident notice](https://archlinux.org/news/active-aur-malicious-packages-incident/) and
  [iptables nft-default notice](https://archlinux.org/news/iptables-now-defaults-to-the-nft-backend/).
- [Current advisory issue #24](https://github.com/snaplyze/arch-linux/issues/24): historical monthly summary, not today's complete package acceptance.
- [Release 1.0.5](https://github.com/snaplyze/arch-linux/releases/tag/1.0.5) and [successful workflow](https://github.com/snaplyze/arch-linux/actions/runs/35253762920).

ArchWiki System maintenance returned an Anubis access-denied page in this run. Its contents
were not treated as read evidence; use accessible official notices/package metadata and retain
this limitation. No attempt was made to bypass site protection.

## Document architecture

Apply [Diátaxis](https://diataxis.fr/) by purpose and
[Write the Docs principles](https://www.writethedocs.org/guide/writing/docs-principles/)
for maintained, task-oriented pages. This does not require a new framework or mass renaming.

| Purpose | Canonical existing location | Responsibility |
| --- | --- | --- |
| Entry and guided first install | `README.md`, `docs/installation.md` | Supported platform, pinned bootstrap, preflight and one normal path |
| Task procedures | `docs/marble.md`, `docs/package-repository.md`, `docs/maintenance.md`, `docs/release-process.md` | Install/update/remove/fallback, reviewed inputs, delivery |
| Reference | `docs/configuration.md`, `docs/compatibility.md` | Exact options/schema, supported versions/fallback; no duplicated instructions |
| Explanation and decisions | `docs/architecture.md`, `docs/trust-model.md`, `docs/decisions/` | Why boundaries exist; immutable ADR history |
| Verification | `docs/testing.md`, `docs/validation.md`, `tests/vm/README.md` | Commands/matrix vs dated evidence/identities vs harness usage |
| Work tracking | `docs/PLAN.md` | This registry, dependencies, acceptance and short checkpoint |
| Agent setup | `docs/agent-setup.md` | Historical setup-only AS IDs; no product authority or duplicate roadmap |

`docs/README.md` is the navigation index. Keep URLs and headings stable where possible;
do not create PROGRESS/ROADMAP/audit archives duplicating this plan. After each accepted task,
update only its owning behavior/reference/evidence page and this registry. Release history stays
in CHANGELOG; current acceptance stays in validation with exact inputs, never overwritten PASS.

## Review focus

1. Guard failure after an initially accepted handle must stop every later stage and marker activation.
2. Probe errors/malformed topology must never mean idle; valid empty swap/mount state must work.
3. A neighbor sharing ordinary ESP paths must retain boot bytes and real boot through new OS updates.
4. Untrusted compressed input must fail within bounded resources with children/tempfiles cleaned.
5. New GNOME/package/ISO inputs must either activate reviewed Marble or fall back to working Stock.

## Execution registry

Task states: TODO, IN_PROGRESS, BLOCKED, DONE. Check results use the exact statuses defined in
[validation](validation.md). A task becomes DONE only when its acceptance is met; source PASS alone
does not close build/VM/publication tasks. Every fix: reproduce → focused correction → useful
regression → affected tests → independent review where material → status update.

| ID | Priority | Dependencies | State | Deliverable |
| --- | --- | --- | --- | --- |
| SAFE-01 | P1 | none | DONE | Explicit abort and mounted-root proof |
| SAFE-02 | P1 | none | DONE | Checked idle-probe results |
| SAFE-03 | P1 | SAFE-01, SAFE-02 | DONE | Reject shared ESP boot-file collisions before root mutation |
| TRUST-01 | P2 | none | DONE | Bounded package decompression and archive traversal |
| CONFIG-01 | P2 | none | DONE | Reserved target-account rejection before destructive work |
| TRUST-02 | P2 | TRUST-01 | DONE | Package/.db/.files identity and payload consistency |
| RECOVERY-01 | P2 | SAFE-01, SAFE-02 | DONE | Quiescent cleanup and bounded nonsecret recovery state |
| DELIVERY-01 | P2 | TRUST-02 | DONE | Compatible package-only delivery source/procedure |
| MON-01 | P2 | none | DONE | Dated advisory coverage of boot/desktop inputs |
| UP-01 | P3 | MON-01 | DONE | Reviewed external-source decisions and synchronized metadata |
| ARCH-01 | P2 | ISO qualification independent; corrected-candidate tests after SAFE-01…03, UP-01 | DONE | Owner-reviewed October ISO after actual Minimal/Stock PASS; corrected-child runtime remains RELEASE-01 |
| QA-01 | P2 | SAFE-01…03, TRUST-01/02, CONFIG-01, RECOVERY-01, UP-01 | DONE | Fresh child7af2209/run37214392242 all9 nativePASS incl plainGRUB23 snapshotruntime and MarbleGDM26; strict finalizer assertion regression accepted |
| DOC-01 | P3 | Corrected selector and source behavior prose; final release records under RELEASE-01 | DONE | UI copy and final behavior docs; prose correction is not product fix |
| GATE-01 | P1 | all above | DONE | Exact a9e4173 source35/build/five-realroot/independent review PASS; PR59 requiredCI/squash and main696b420 FF accepted; immutable input receipts retained |
| RELEASE-01 | final | GATE-01 | DONE | Immutable1.0.6 child7af2209 exactPhaseA14/all9PASS/final18/Pages/publicbytes/publicMarble19 accepted; PR59/main696b420 delivery and final local documentation recorded |

GATE-01 depends on preceding source/pre-merge deliverables only. DELIVERY-01 closes at reviewed
source/design/regression acceptance; actual package-only publication requires separately defined
authority/resources and is not silently added to the standing installer-release exception.
DOC-01's corrected facts do not require waiting for code implementation; only future behavior
descriptions/selector code and complete new product acceptance do. No document task depends back
on RELEASE-01. ARCH-01's old-product media qualification can proceed independently; final corrected
product acceptance still belongs to RELEASE-01. This avoids blocking independent work or a cycle.

SAFE/UP/QA tasks close their source/fixture and pre-merge acceptance only. Runtime obligations
on the authoritative signed release child are explicit substeps of RELEASE-01 and remain
NOT_RUN_ENVIRONMENT until that pipeline executes. GATE-01 does not depend on a future child.

### SAFE-01 — stop after rejected guards

Files: `arch-linux-installer.sh` (`exec_prepare_disk`, `activate_storage_marker`, `exec_pacstrap_core`),
`tests/function-checks.sh`, `tests/installer-boundary-checks.py`, `docs/architecture.md`.
Interface: preserve assertion predicates; failed assertion or absent/wrong `/mnt` yields nonzero stage.

- [x] Add actual executor regressions injecting rejection after initial handle acceptance, including
  ext4/Btrfs and encrypted/unencrypted branches; pin no later command and no active marker.
- [x] Replace unsafe guard chains with explicit termination before mutation; assert actual accepted
  mounted root before active mount marker and before pacstrap. Preserve existing owned cleanup.
- [x] Run `bash tests/function-checks.sh`, `python3 tests/installer-boundary-checks.py`,
  then full source suite. Require original negative fixtures to reject and normal fixtures to pass.

### SAFE-02 — fail closed on idle-probe errors

Files: installer (`target_storage_is_idle`, storage membership helpers,
`aur_builder_uid_scan_target_mounts`), `tests/function-checks.sh`.
Interface: operational failure/malformed input returns nonzero with a clear diagnostic.

- [x] Add tests for each probe failing, malformed rows, missing selected disk, mounted descendant,
  swapfile on target, holder and occupied /mnt/mapper; include valid empty mounts/swap.
- [x] Capture outputs with checked statuses and validate topology; distinguish findmnt's documented
  no-match result from execution/parsing failure. Do not infer idle from a broken membership lookup.
- [x] Run function/source checks; no mutation command may occur after uncertain idle state.
- [x] Check `find` exit status in AUR UID-empty and cleanup readback modes; fail on no-output/partial-output
  errors before claiming target emptiness or crossing the privileged package handoff.

### SAFE-03 — preserve neighbor ESP bytes

Files: installer (pre-mutation dual-boot validation and boot paths), `tests/function-checks.sh`,
`tests/vm/guest/bootstrap.sh`, `tests/vm/guest/verify.sh`, `tests/vm/run.sh`, installation/compatibility docs.
Decision: implement fail-closed collision rejection first; do not silently redesign partitioning
or introduce new UKI/kernel namespaces. Noncolliding dual boot remains supported.

- [x] Add fixtures with pre-existing `loader/entries/main.conf`, fallback entry, selected kernel/initramfs
  and GRUB config; reproduce overwrite in temporary files and pin rejection before root formatting.
- [x] Define exact write footprint including bootctl fallback/shared configs; preserve foreign content
  or reject an unsupported collision before any disk mutation. Explain conflict/action to the user.
- [x] Run function/harness/source checks. Add mandatory disposable VM gates proving colliding neighbor remains unchanged
  after safe refusal and noncolliding dual boot installs and boots both OSes after update.
  Execute those authoritative child gates under RELEASE-01; pre-merge source acceptance must not
  be described as their runtime PASS.
- [x] Record partition/EFI/file identities; do not claim Windows testing from a Linux neighbor.

### TRUST-01 — bound unsigned archive inspection

Files: `repository/verify-package-metadata.py`, `tests/package-checks.sh`, `tests/repository-checks.sh`.
Interface: same valid-package acceptance, deterministic rejection on resource limits; no private authority.

- [x] Derive production compressed/expanded/member/count/time bounds from clean package inventory
  with explicit headroom; encode and document exact limits before accepting a candidate.
- [x] Add small fixtures exceeding reduced test limits, excessive tar headers, truncated frames,
  aggregate/member-size violations; require child exit, bounded rejection and temporary cleanup.
- [x] Stream bounded decompression/traversal; enforce time/resource limits on integrity test too.
  Keep every existing byte/metadata/path/signature validation intact.
- [x] Run package/repository/source checks and verify all six real clean unsigned-build packages still pass.

### MON-01 — useful, dated upstream monitoring

Files: `maintenance/sources.json`, `maintenance/check-sources.py`, `maintenance/update-advisory-issue.py`,
`.github/workflows/maintenance.yml`, `tests/maintenance-checks.py`, `docs/maintenance.md`.

- [x] Add observed UTC time/source identity to advisory output and issue rendering; show age of
  preserved monthly results during daily key-only updates. Error stays distinct from unchanged.
- [x] Cover kernel variants, systemd, mkinitcpio, cryptsetup, GRUB/pacman/keyring and GTK/libadwaita;
  use correct package architecture endpoints and meaningful full version comparison.
- [x] Test dated key-only preservation, missing/error/old reports, package epoch/pkgrel and
  extension compatibility per accepted shell major. Separate pinned-tag identity from latest release.
- [x] Run maintenance/source checks and read-only network report. Issue updates remain existing
  authorized workflow behavior; this task must not add signing secrets, automatic remediation or ACL changes.

### CONFIG-01 — reject predictable account collisions

F-11. Files: installer (`properties_value_is_valid`, `validate_properties_with_reporter`,
`select_username`, target account creation), `tests/function-checks.sh`, configuration/installation docs.
Dependencies: none. Effort S–M, low risk; preserve schema and valid ordinary names.

- [x] Add parser/semantic/selector `root` and known base-account collision regressions; require
  refusal before `exec_prepare_disk`, not just eventual `useradd` failure.
- [x] Define reserved names from the supported target/base and actual builder naming contract,
  not workstation passwd data. Keep ordinary unused names valid and retain target-side checks.
- [x] Run function/source checks; valid-user corrected-child VM acceptance remains under RELEASE-01. No real account
  creation or destructive installation on the development workstation.

### TRUST-02 — package/database semantic consistency

F-12. Files: `repository/verify-signed-repository.sh` (`inspect_database_archives`),
`tests/repository-checks.sh`, package-repository/testing docs. Dependency: TRUST-01 bounds.
Effort M, medium risk; retain pacman semantics and signature/trust gates.

- [x] Add wrong/missing/duplicate name/version/architecture/size/SHA256/PGPSIG and mismatched
  `.files` identity/list negatives, using ephemeral keys for any signed fixture.
- [x] Cross-check database records against independently verified package bytes/metadata and
  embedded signatures; enforce `.db`/`.files` record and payload-list correspondence.
- [x] Use faithful positive fixtures plus real clean Arch `repo-add --include-sigs` output;
  minimal fake filename-only records are not semantic acceptance.
- [x] Run repository/source checks and real signed readback under RELEASE-01. Signature and
  semantic/availability acceptance remain separate.

### RECOVERY-01 — safe failed teardown

F-13. Files: installer (`trap_exit`, reap/storage orchestration), `tests/function-checks.sh`,
architecture/installation docs. Dependencies: SAFE-01, SAFE-02. Effort M, medium cleanup/cancel risk.

- [x] Exercise actual exit handler with stubbed reap failure, busy unmount, mapper-close failure,
  success and cancellation; pin ordered outcomes and correct nonzero status.
- [x] Require proved worker quiescence before storage teardown. On cleanup failure keep only bounded,
  validated, private nonsecret operational ownership/control markers and report remaining resources.
  Always clear password state; do not retain unsanitized logs/commands/secrets.
- [x] This is operational-marker retention, not configuration backup/recovery; do not copy config
  or agent instructions. Success still removes owned runtime.
- [x] Run function/source checks. This source deliverable accepts the actual-handler stubbed
  failure/cancellation and concurrent-retention regressions above. Live installer cancellation,
  busy-resource cleanup and crash paths remain NOT_TESTED until bounded disposable VM error
  acceptance executes; ordinary successful installation/shutdown does not prove them.

### DELIVERY-01 — package-only provenance and procedure

F-14. Future files: `repository/release-source.py`, signing version/source-identity validators,
Pages/release routing, release-source/actions regressions, repository/release/maintenance docs.
Dependency: TRUST-02. Effort L, high provenance/delivery compatibility risk.

- [x] Design package-source identities binding reviewed package changes and byte-identical published
  installer/bootstrap; reconstruct/verify any allowed transform, without a persistent editable clone
  or weakening version/source/byte guards.
- [x] Define package-only intent versus automatic main installer-child routing. Current standing
  signing/publication exception is limited to its configured installer closure; any changed external
  route requires concrete separate authorization and resources.
- [x] Test changed installer, wrong source/version, missing package revision, inconsistent DB and
  package-tag Latest selection rejection; preserve 14/18 separation.
- [x] Local source/design acceptance closes only that deliverable. External acceptance remains
  NOT_TESTED until separately authorized: signed installed-system `pacman -Syu`, package revision
  increase, unchanged existing installer/assets/version, exact readback and unchanged latest SemVer.

Accepted local implementation design: explicit installer/packages intent, default installer when
absent; package intent suppresses automatic installer publication without granting signing.
A deterministic package child has exactly the reviewed package-main parent. Only existing
version/URL/diagnostic substitutions and package-origin record are allowed; transformed
installer/bootstrap modes and bytes must exactly equal the independently bound published
release. Current behavior corrections reject package mode until a normal installer release.
Origin binds reviewed main/tree, transformer, installer release/source/assets and active signed
repository baseline build/unsigned/snapshot hashes plus all six package identities/revisions.
Initial package mode retains names/arches/epochs/pkgvers and requires each pkgrel to increase;
missing/stale revisions reject, never auto-generated. Existing deterministic bundle restore and clean Git source identity bind the package child
for build; no self-verifying archive/caller-asserted identity mode is introduced. Ordinary
Git/sealed modes stay strict.
Package Pages remains exact14 and cannot select package tag as Latest; installer final closure
remains exact18. No changed external signing/publication route is authorized. monitoring owns
release-source/build identity/Pages/intent guard regressions; root owns prose and integration.

These local source resolutions do not imply new package publication authority; external acceptance remains separately authorized.

### UP-01 — choose and validate external updates

Files: affected PKGBUILD/`.SRCINFO`, installer pins, `maintenance/sources.json`, relevant tests/NOTICE.

- [x] Reuse documented Gum 2.0.0 and Colloid GTK no-update decisions; review only new evidence/diffs.
  Fetch fresh advisory; assess Gum 2.0.2 CLI/API/assets relative to that review, Colloid GTK commit
  `6c2dc658…` → `fe11342f…`, SPDX `c4a7237e…` → `31ba1a50…`, and changed AUR/extension refs.
  Record exact full proposed identities and decision update/retain with reason in this task.
- [x] Review source/license/build/dependency changes; human review precedes accepting new URLs/hashes.
  Do not update GNOME 50 assets merely because upstream GNOME 51 exists.
- [x] Synchronize owning pins, source hashes, `.SRCINFO`, metadata and package revisions together;
  any changed published package filename requires increased pkgver/pkgrel.
- [x] Run UI smoke for every used Gum command; metadata/source checks; canonical unprivileged clean
  Arch build and independent verification remain GATE-01; implement affected desktop/boot VM checks in QA-01
  and execute them against the authoritative child under RELEASE-01.


### October 3 source decisions (UP-01)

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
and unnecessary for the retain decision. Canonical corrected-child build and runtime gates
remain GATE-01/RELEASE-01. Compact review receipts stay outside source; this registry is the
canonical decision record.

### ARCH-01 — accept current media and runtime

Files: `maintenance/accepted-arch-iso.json`, `tests/vm/run.sh`, `tests/vm/guest/bootstrap.sh`,
`tests/vm/guest/verify.sh`, `tests/vm/harness-checks.sh`, compatibility/testing/maintenance docs; installer only
for reproduced incompatibilities with regression tests.

- [x] Independently review official ISO metadata/hash/signature through trusted Arch verification;
  retain accepted ISO bytes outside checkout. Do not install/download new host packages for this audit.
- [x] Validate desktop target resolution in disposable fully updated Arch using
  `python3 tests/desktop-package-checks.py --live`; resolve chosen AUR dependencies/ABI too.
- [x] Add reviewed public-mode Minimal/Stock media-qualification support to the harness: current
  `run.sh` permits public mode only for Marble. Preserve independently downloaded verified old product
  bytes and separate product/harness identities; add routing regressions before using new scenarios.
- [x] Qualify exact 2026.10.01 image with Minimal and Stock real QEMU using the existing immutable
  1.0.5 bootstrap/installer and signed public inputs before changing accepted ISO state. Use fresh
  disks/VARS and bounded resources; these runs establish media qualification for that old product,
  not PASS of the corrected candidate. Rerun affected source checks after accepted-state change.
- [x] Add checks for current systemd/mkinitcpio (October 3: 262 / 42.2), LUKS password prompts, GRUB/systemd-boot, selected kernels,
  Btrfs snapshot boot/module pairing, full update and another boot. Add conditional TPM PCR guidance;
  execute corrected authoritative child coverage under RELEASE-01.
- [x] If GNOME 51 reaches stable during execution, requery packages and test Stock/fallback first;
  new Marble support requires reviewed assets/extension metadata/lifecycle/real GDM checks.

### QA-01 — behavioral and VM coverage

Files: existing tests and VM harness, `.github/workflows/release.yml`, testing/validation docs. Prefer actual function failure injection
over more literal-string assertions; preserve static policy checks where they are appropriate.

- [x] Integrate F-01…04 reproductions into maintained regressions; characterize missing cases without
  an arbitrary coverage percentage. Do not weaken security tests to make the suite green.
- [x] Preserve three required staged release scenarios on one exact signed snapshot and accepted ISO.
- [x] Implement mandatory workflow gates for all six complementary scenarios already listed in `tests/vm/README.md`, including
  unencrypted Btrfs/GRUB, ext4 Stock, encrypted Stock systemd-boot, Marble Stock GDM and Linux dual boot.
  Add SAFE-03 collision-refusal fixture and boot/update preservation checks.
- [x] Track linux/linux-lts/linux-zen and graphics/firmware boundaries honestly; add focused cases
  when changed code/packages affect them. Virtual GPU PASS does not prove physical NVIDIA/AMD support.
- [x] Make gates require actual password GDM login/Wayland/lock/unlock, update/reboot, integrity, no failed units,
  clean shutdown, `qemu-img check`, owned resource cleanup. Screenshots remain optional diagnostics.
- [x] Exercise deactivation/helper failure separately from ordinary unsupported-version fallback;
  require honest failure/status and actual session/greeter inspection, not inferred successful Stock.
- [x] Wire the supplemental jobs as mandatory dependencies before `finalize`, bound to the same
  child commit/tree, snapshot and ISO. Keep supplemental evidence separate from the exact
  three-verdict signed acceptance schema and preserve 14/18 closure. Run harness/source checks
  pre-merge; actual production-child execution is RELEASE-01 acceptance, not a QA-01 pre-merge claim.

### DOC-01 — current information without duplicate authority

Files: README, CHANGELOG, docs index/installation/configuration/compatibility/architecture/Marble/
testing/validation/maintenance/release process, installer appearance choice text and its regression.

- [x] Preserve Diátaxis navigation prepared by this review; remove duplication by linking canonical
  reference and procedure pages, not by mass moving files or adding another roadmap.
- [x] Verify full 1.0.5 public closure/Pages and record its separate identity before refreshing latest
  release examples/summary. Preserve historical 1.0.4 evidence as historical; do not relabel it.
- [x] Align appearance prompt with GTK3/GTK4/libadwaita implementation without changing selector values.
  Document safe dual-boot collision refusal, supported/current-vs-accepted inputs and conditional TPM note.
- [x] Run `python3 tests/docs-checks.py`, source suite and `git diff --check`; commands/links/options
  must match final implementation. Check language clarity and copyable normal installation path.

### GATE-01 — accept one exact candidate

Dependencies: every preceding source/pre-merge task accepted; no unresolved P1 or deferred
pre-merge-required tests. Production-child/post-publication gates are RELEASE-01 obligations.

- [x] Recheck main/origin/dirty/index and ownership; stable independent security review of final changes.
  No simulated independent review. Resolve material findings and rerun affected checks after correction.
- [x] Run `bash tests/source-tests.sh` and `git diff --check` on final candidate; bind commit/tree and
  canonical mode-and-byte source SHA-256, package inputs, tool versions and selected ISO.
- [x] In an authorized disposable release-host boundary execute unflagged + full-namespace repository,
  exact root publication and both keyring modes listed in AGENTS. Fixture signing uses ephemeral keys.
- [x] Build once canonically as disposable unprivileged builder and independently verify unsigned outputs.
  Do not create production signing authority to satisfy a pre-merge check. Record clean-build environment
  and preliminary checks; they do not transfer to the later deterministic release child.
- [x] Verify all mandatory child source/build/signing/VM gates are implemented and block finalization
  on failure. Record bounded resources before execution. Production Phase A/exact-18 and authoritative
  VM execution belong to RELEASE-01 after main delivery, before tag/publication where applicable.
- [x] Freeze evidence for exact inputs; any source correction invalidates affected downstream PASS.
  Package reproducibility A+B remains advisory, not an invented blocking release criterion.

### RELEASE-01 — main, annotated tag and immutable release (last)

Target: `snaplyze/arch-linux`, protected main and its configured `release.yml`/Pages target.
Owner requested this as the end of the plan. Do not publish during review/planning.

- [x] Confirm fresh GATE-01 and resources for the next candidate. Owner exception for a ready PR
  branch in this checkout, adopted baseline commits and required merge is already granted;
  preserve protected-main requirements and exact accepted input bindings.
- [x] Commit reviewed authorized paths; deliver through required Source checks and squash PR merge.
  Return this same checkout to main and fast-forward only. This is delivery to main, not a rejected
  direct-push attempt and not another development clone.
- [x] Let configured `release.yml` derive/test/build/sign a fresh version-only child from accepted main.
  Do not create a competing manual tag/release; let pipeline select unused SemVer and annotated tag.
  Live inventory selected 1.0.6 for run37214392242. Query inventory before any future version; do not hardcode the next SemVer.
- [x] Require successful child source/build/signing, three staged plus supplemental gates before
  finalization; exact 14 bytes unchanged → exact 18 finalized assets, signed acceptance/evidence.
- [x] Observe immutable Release/tag, verified Pages deployment and public readback, then fresh
  public-only Marble/GDM VM. These public checks necessarily happen after publication; distinguish
  all pre-publication checks passed from final public acceptance passed.
- [x] Record origin main and child commits/trees, tag object, run URL, assets/hashes and final public
  result in validation. Keep old releases/tags/bytes intact. Post-publication defect gets new reviewed
  fix/release; no tag movement, deletion, changed-input retry or signing-key rotation.
- [x] Mark DONE only with actual main delivery, immutable tag/release and successful public acceptance.
  If external gate fails, record exact blocker/next safe action and retain local accepted result.

## Checkpoint

### Post-release Markdown reconciliation — 2026-10-04

Owner requested a complete Markdown freshness check after accepted immutable 1.0.6. The scope is
all 29 tracked Markdown files, including `.github/pull_request_template.md`; this is a documentation
follow-up, with no new product gate or publication. README and other current reference pages now
reflect delivered package provenance, bounded archive inspection, database semantics, corrected
Marble prompt, completed snapshot-runtime acceptance and current 1.0.6 publication. The PR template
matches the canonical single build/independent verification, advisory A+B comparison and optional
screenshots. Dated audit findings, old releases/ISO qualification, design decisions, retained pins
and setup-only evidence retain their original scope; unrelated release-neutral pages need no edits.

`AGENTS.md` now requires inventory and reconciliation of every tracked Markdown file after successful
release/public acceptance, with accurate historical evidence, final checks and explicit local-versus-
published documentation status. Before completing this follow-up, bind the final review, exact
changed paths and fresh source-suite result in the existing frozen-final-gate-candidate.json
evidence register.
This reconciliation changes no signing, product inputs, workflow or permissions. The owner
subsequently authorized publication of all final documentation to protected main through a checked
squash PR. Its exact CI/merge/main identities and remote outcome belong in the same evidence
register; skip only the duplicate main push CI after successful PR checks to avoid another release.

### Current implementation checkpoint — 2026-10-04

All15 mandatory IDs are accepted. Product delivery and public acceptance are complete; final
local document-commit verification is bound in the existing evidence register. Exact candidate a9e417304e9883aa354f5ed2cda6a9ead0438eec,
tree2d3e7f1abf454c462586cb5450ae1c79d3ccee0a/canonical6d8da82f8008f9d8d002f8a9bd0bb3c60b7db6530eb4894657ad0fcfd38d6250,
passed clean source35 (native0/session27887), canonical6-package build+freshverify
(native0/session24365), and all5 realroot gates (native0/session18189), each independently reviewed.
PR59 CI37214061906 PASS, guarded published-branch main-ref CAS, squash and same-checkout main FF
produced originmain696b420bc93415d44bb3ab64b35df7539cbbe87b with unchanged tree/canonical bytes;
mainCI37214269376 PASS. Exact6 owned root VM targets were removed after accepted evidence,
independent review, PID/consumer/identity/imagehealth guards; build outputs and compact evidence retained.

Configured [run37214392242](https://github.com/snaplyze/arch-linux/actions/runs/37214392242)
derived child7af2209be497a0a5f0e314cd8cc20f691e52b064/tree83bd2d9de7d4883b08fbb81c78cce8fe0d36374d,
canonicalf6b6517655429ca06afb1cd241d971fe4ccb02352a231020145853ed8b7185ff, version1.0.6.
Actual bundle graph proof0/session45041, PhaseA14 proof0/session60683, all9 staged nativePASS
(collector0/session20614; counts14/17/21/21/21/22/17/26/23), and final18 proof0/session10065
were accepted and independently reviewed; original14 unchanged, signed evidence1948353B/deferredempty.
Immutable Release403102824 was published2026-10-04T16:22:59Z after verified Pages deployment;
annotated tag54d1208417e872bb08b5b9128752d36030205145 points to the accepted child.
Unauthenticated HTTPS public18+Pages25 exactbyte proof0/session81772 ran under an explicit30m
outer deadline. Fresh configured publicMarbleGDM VM PASS19/native0 (publicartifact11308433140),
real HMP/password/Wayland/lock/update/reboot, two bootIDs/no-QEMU/imagehealth accepted.
ResultSHA13de92af4ecc355529ae734674a7966529c62209adbb7d0d066ebf523b0d25e8;
release watch0/session50451, terminalSUCCESS. No PASS transferred from older releases or failed predecessors. Final documentation was initially retained on localmain. The later explicit owner request
authorizes a separate documentation PR/main publication, without a new installer release. Independent final result review and clean documentation source37 passed. Goal completion requires
the final outcome-record check recorded in the same register, without adding another project scope.

Evidence register: the existing frozen-final-gate-candidate.json, finalizeCandidate entry, preserves
all native logs/receipts/hashes/attempts and historical remountCandidate failure. Earlier checkpoints
below are historical; this record and the execution registry describe current state. Final source36
working-document suite passed0/session93550 before final public wording. Docs29/diff checks are
rerun after that wording; the clean final document-commit source result is retained in the same register.
Live installer cancellation/busy-resource/crash VM paths remain NOT_TESTED as a documented
limitation beyond the explicitly accepted RECOVERY source regressions.

Clean local documentation commit `30d4a162ed99141c4ccd2b43273a90f1fda0b756` (tree `895fb77ea77e2f66ef5bf8cbb49ba6f21572004b`, canonical SHA-256 `368587520f60e525c9ede887e08b139e77aa42597dbbfc6da2705422339c04d6`) passed `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`, source37/native0/session71065; log SHA-256 `ad9f3e402e3bcfaf772d44c3b88ec422e4eba3df6a948b91d7dcd8610ece3ccd`. This result belongs to that exact documentation tree. Later documentation edits require fresh applicable checks; the evidence register preserves each exact tree/result.

2026-10-02: root plus two independent read-only reviewers and one primary-source researcher
completed bounded audit. Root independently reran both harmless installer reproductions and the
temporary boot-entry overwrite snippet. Source suite passed on original dirty checkout; baseline
files/index stayed unchanged throughout audit. Planning changes are `docs/PLAN.md` and docs index only.
Independent plan review identified and corrected the pre-merge/child-acceptance dependency cycle
and made supplemental workflow gates mandatory. Follow-up review found no remaining material cycle;
its public-mode Minimal/Stock harness caveat is now an explicit ARCH-01 implementation step.
First document-inclusive source run failed portability due to a concrete home path in this plan;
the path was removed, and targeted documentation/portability checks passed. The final full source
rerun completed with exit 0 and full marker on October 2 (prior turn result); this remains historical,
not a fresh October 3 execution.

2026-10-03 documentary follow-up: F-01…F-10 retained; F-02/F-09 expanded for shared root causes;
F-11…F-14 added with four owner tasks. Affected factual descriptions were corrected as findings
arrived. Root independently executed the actual DB heredoc on in-memory inconsistent archives
(accepted), lexical username check (`root` accepted), and exit handler with all effects stubbed
(reap refused → storage cleanup → runtime removal). First DB mock attempt raised a fixture TypeError;
correcting recursive `tarfile.open` mocking produced the observed result. No product changes.
Three required specialists finished read-only; final stable-doc review and safe check outcomes follow.

Historical audit boundary: at this October 3 checkpoint implementation awaited a separate
assignment and all product tasks were TODO. The later owner-authorized autonomous checkpoints
below supersede that boundary; the execution registry above gives current statuses.

Completion of this document means REVIEW_PLANNED, not SOURCE_ACCEPTED or RELEASED.

### October 3 check record

EXECUTED_PASS: `python3 tests/docs-checks.py` (29 Markdown files),
`python3 tests/portability-checks.py`, `python3 tests/agent-contract-checks.py`.
Executed against documentary edits; no product/runtime PASS inferred. Read-only GitHub latest/main
API still reports immutable 1.0.5/18 assets and protected main at the baseline HEAD.
EXECUTED_PASS: `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`, exit 0 on October 3,
with isolated temporary fixtures. Two cases reported skipped in the 12-case test group; this does
not establish full privileged/live acceptance. Output captured in memory, no permanent raw log.
The suite preceded only the final README lifecycle qualification and this result/checkpoint prose;
affected documentation/contract/portability checks were rerun afterward.

Independent stable-document review confirmed preserved IDs, unimplemented product status and no
material dependency cycle. Its remaining unconditional README lifecycle statement was qualified;
no new product finding or implementation was introduced. Local heading links were checked separately
(50 anchors). `git diff --check` passed.

Baseline byte/mode/index guard: exactly 15 Markdown paths changed in this turn; no removed/new paths,
no product/test/dependency/CI/config bytes or modes changed. HEAD and index unchanged; branch main.
Earlier user/setup dirty files and untracked settings retained. This audit is complete as
documentary research; build, release-host privileged/full acceptance, fresh VM scenarios, signing
and public closure verification remain NOT_TESTED in this turn. No implementation or publication.

### Autonomous implementation checkpoint — 2026-10-03

Full finite scope: all 15 execution-registry IDs and their listed acceptance; no new optional
obligations. Goal active. Physical root verified, Codex 0.160.0; main HEAD/tree unchanged
from baseline, upstream +0/-0, no staged paths. Existing 15 dirty Markdown files and
untracked `.codex/`, `docs/PLAN.md`, `docs/agent-setup.md` retained; no attribution or commit
of previous work. Runtime permits four concurrent agents including root; active named role
definitions used, no configuration/model/permission changes.

Initial wave ownership: storage_guards SAFE01/02; monitoring MON01; archive_limits TRUST01.
These assignments are closed and later routing below supersedes them. Root owns registry,
all current prose, integration and remaining prerequisites. No overlapping edits, recursive
agents, Git mutation or publication. Stable source suite follows completed source edits.

Host prerequisite probe: KVM readable/writable; qemu/qemu-img/makepkg/zstd/bsdtar available;
noninteractive sudo succeeds. User Docker socket access fails; do not change group/ACL.
Root-mediated bounded disposable container may be used after inspecting service/resources.
Available host memory around 7 GiB including reclaimable cache, /tmp tmpfs 14 GiB free;
serialize heavy build/VM resources and retain outputs outside source.

Implementation progress: SAFE-01/02 source fixes and focused regressions delivered by
storage_guards; independent read-only review by monitoring is active. MON-01 delivered;
independent archive_limits review found no material issue. TRUST-01 delivered, all six
preliminary clean packages pass verifier; independent monitoring review found Solaris PAX
and GNU sparse pre-parser bypasses. Root reproduced five failing subcases, added bounds /
sparse rejection, and 15 archive tests now pass; narrow re-review and stable source suite
remain. Limits/inventory headroom documented in package-repository reference.

Public 1.0.5 readback executed: exact 18 assets match API sizes/SHA256; committed public
trust bytes match; five detached release signatures and exact-12 manifest pass. Pages
manifest/signature match signed archive bytes; all 23 named objects pass size/SHA256,
manifest + two database + six package signatures pass. Source identity stays released
61add3e0 / b5ca51e8; no new candidate or new real VM PASS inferred. Compact inputs/evidence
retained outside source in generated implementation artifact directory.

TRUST-02 now owned by archive_limits (signed-repository semantic helper/fixtures and exact
sealer inclusion); storage_guards owns ARCH/QA harness + supplemental workflow gates,
not installer. Root owns archive review fixes/docs and integration. Full source gate waits
for stable integrated files. A new reviewer spawn hit the runtime thread limit; existing
separate implementers perform real independent cross-review instead of simulated review.

First integrated source boundary: `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`
exit 0, `all required source tests passed`, full namespace schema-1 marker, all10 scenarios,
signer passed, exact14+18, deferred none. This run covers integrated SAFE01/02, TRUST01/02,
MON01, initial CONFIG01 and ARCH/QA source slices. Two legacy environment-specific tests
remain reported skipped; no live/privileged release-host/VM result is inferred. Logs are
generated outside source. Registry/document-only updates after this run require affected
document checks; further code changes require fresh affected/source checks.

Acceptance: SAFE01/02 independent review's three findings fixed and scoped re-review passed;
TRUST01 two parser findings fixed and scoped re-review passed, all6 real clean packages
reverified after fixes. TRUST02 independent storage_guards review and actual published
repo-add pair pass. MON01 independent review clean. These five pre-merge source IDs are
DONE; authoritative corrected-child runtime obligations remain under RELEASE01.

CONFIG01 independent review found additional predictable base/desktop user/group names.
Root added confirmed names and both target passwd/group probes; scoped independent
actual-function review and function suite PASS. Source deliverable accepted.
ARCH/QA routing/workflow source slice delivered: explicit public media-qualification flag
for Minimal/ext4 + Stock/ext4, released-product hashes via annotated tag, strict clean
harness gate retained; matching Ubuntu/Arch OVMF pairs; nine staged matrix instances with
separate core/supplemental artifacts, exact3 core acceptance schema retained. Remaining:
independent review, SAFE03 collision gate, deactivation/error acceptance and real qualification.

Live desktop prerequisite: fully updated disposable Arch container, all28 unique official
desktop transactions resolved (`LIVE_PACKAGE_RESOLUTION_PASS`, installation NOT_RUN).
No host dependencies/accounts/settings changed. All owned containers removed via --rm.
Official October ISO metadata/hash/signature verified separately; accepted state remains
September until actual Minimal+Stock qualification and human pin review.

Current routing/acceptance update: CONFIG01 complete fixed base/desktop user+group set, both
target getent lookups fail closed except status2, ordinary names retained. Independent actual-
function probes and function suite PASS; corrected-child installation remains RELEASE01.
ARCH/QA independent review found an unconditional result-schema expansion; worker corrected
it and actual producer→unchanged finalizer exact-key tests PASS. No other material findings.
archive_limits now owns SAFE03+RECOVERY01 installer/function/boundary slice; storage_guards
prepares remaining QA runtime coverage read-only; monitoring prepares DELIVERY01 design.
Root owns all prose/registry. No code source suite claimed after these newer corrections.
October ISO SHA256 684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5
and signature PASS using installed trusted Arch public certificate, signer
3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C. Accepted ISO remains September: real Minimal/
Stock qualification, clean harness candidate and human-reviewed pin remain prerequisites.

Runtime prerequisite attempt: actual preflight on exact October ISO refused Minimal at
3,506,392KiB available (requires4GiB) and Stock at3,455,836KiB (requires8GiB). Host holds
three unrelated QEMU processes; no stop/reclaim or memory-threshold weakening authorized.
Both are NOT_RUN installation results. Return condition: available scenario memory plus
clean accepted canonical harness. Current GitHub main ruleset21994796 requires PR and
Source checks, strict status policy; ordinary branch-protection endpoint404 does not
remove that ruleset. No protection changes or bypass attempted.

QA remaining source ownership: storage_guards owns run.sh + guest/verify.sh + focused
regressions; archive_limits owns guest/bootstrap.sh + harness-checks.sh plus installer tests.
Neighbor identity transfer coordinated between these writers. Approved bounded snapshot
fixture in existing unencrypted Stock Btrfs/GRUB: production-generated entry, read-only
snapshot identity, actual volatile overlay lowerdir and kernel/initramfs/modules proof,
real GDM login and return to normal root before exact fixture cleanup. No new scenario,
handwritten boot entry, product Snapper setting or signing schema change. Runtime NOT_RUN.

External prerequisite read-only check: Actions enabled with selected-action policy; release
Environment exposes both configured signing-secret names. Values were not accessed, shown
or transferred; name presence does not prove usable signing material. No credential request
or setting change is needed at this stage. Mandatory live results still pending.

QA runtime slice independently accepted after actual Marble update-pair omission was
reproduced (four failing public/staged cases), corrected and narrow rereview passed.
Runtime regressions28PASS, source/harness routing reviewed, realVM remains NOT_RUN.
DELIVERY independent review found duplicate JSON intent keys could select installer route;
root reproduced3failures, duplicate-rejecting all-depth decoder corrected,32testsPASS and
narrow independent rereview passed. One design gap remains being implemented by archive_limits:
old active snapshot archive hash must be recorded/bound as originally required; do not drop
that accepted provenance identity. storage_guards now independent SAFE03/RECOVERY reviewer;
monitoring reviews only new documentation consistency. Final integrated source suite waits
for stable DELIVERY correction and resolved material findings.

SAFE03 independent source review found no material issue;22boundary/function/harness
checksPASS. Whole ESP/root hash refusal and after-update actualneighborboot gates implemented;
realcorrected-child VM execution remains RELEASE01. RECOVERY same-runtime late-writer race
reproduced in actualexit+retention with concurrentfixture; storage_guards now owns focused
installer/boundary correction, archive_limits owns only DELIVERY oldsnapshot binding.
Root source/fullgate remains pending stablecode plus independent recovery/DELIVERY rereview.

Stable source boundary ready: RECOVERY race correction24boundary/functionchecksPASS;
separate private recovery closure, canonical validated markers, oldworker runtime removed,
allocation/unsafeparent/pretargedfailure fixtures covered. monitoring independent rereview
active. DELIVERY oldsnapshot identity restored as required: mandatory repositorySnapshotSha256,
derivedannotatedbaselineTag, immutableoldReleaseAPI + actualboundedarchiveSHA+manifestbyte
identity; explicitoldbuild/unsignedhashes inorigin.37release-source/16actionsPASS, actual
published1.0.5 archivePASS. storage_guards narrow oldsnapshot review active. Root now runs
final integrated source suite; no code writer active, no Git/permissions/publication actions.

Integrated implementation acceptance: `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`
source-integration-4.log EXIT0, allrequiredsourcepassed, fullnamespace schema1 scenarios10
signerpassed exact14+18 deferrednone. Prior integration2 failed preserved Pages authenticated
asset guard; root used bounded authenticated asset API without weakening test. Integration3
failed obsolete running-kernel literal; replaced with actual pairing behavior regressions
(upgrade-before-reboot, postbootstale, mixedmodules, wrongkernelbytes),5remediationtestsPASS
and independent narrowreviewclean. DOC final contradictions corrected and rereviewclean.
RECOVERY separateclosure24boundary and independentrace rereviewclean; DELIVERY oldsnapshot
37provenance+16actions, realpublicarchive, source-mutation and deadline/reap independentprobes
PASS. These source pre-merge IDs are DONE; actualruntime/privileged/build/production/public
acceptance remains GATE01/ARCH01/RELEASE01, not inferred from fixtures.

RAM increased after unrelated work ended; fresh Minimal preflightPASS at9,047,980KiB, KVM
and storagePASS. Stock preflightPASS at9,468,384KiB (KVM/storage/clockPASS), logs outside source. No unrelated VM/process was stopped.
2026-10-03 owner explicitly authorized the same-checkout PR branch exception only when
changes are ready for main: after accepted premerge gates, push/PR/required Source checks/
squash merge, then return main fast-forward. No extra source checkout or protection bypass.
Owner clarified explicit adoption of all current changes, including other authors' baseline,
into the reviewed commit. Both baseline adoption and the ready-candidate PR exception are
now authorized; do not request them again. Goal ACTIVE. MainHEAD before integration is
0d7ce452dfd8d8e4a8ecdf96a25caa22a4600263, index initially empty. Revalidated every retained
working-source receipt file byte/mode unchanged, public client settings remain unchanged.
Root stages only the enumerated reviewed tracked changes plus the exact existing .codex
files, PLAN/setup and four new regression/verifier files, then runs final source checks
before the local main commit. Prior desktop28 transactions PASS, installation NOT_RUN.
Both bounded GATE preparations completed read-only: canonical build mounts current clean
checkout read-only in the retained pinned Arch Docker image, unprivileged disposable builder,
2CPU/2GiB/256pids/90min, followed by fresh-container independent unsigned verification.
Release-host acceptance requires one disposable full Arch VM: root-owned immutable gate
input with exact Git identity, guest-only locked signing fixture account, namespaces/cgroup/
loop/device-mapper, unflagged and full repository modes, exact isolated-root publication,
ordinary and privileged keyring modes. No production keys or host permission/account changes.
Root verified retained image digest and canonical clean-source guard. Build/release-host gates
remain NOT_RUN; all mandatory workers are completed, no acceptance process is running.
Next dependent step after final source PASS: explicit owned/adopted-path integration/localmain
commit → cleanharness October Minimal/Stock qualification → humanreview acceptedISO → final
tree-bound source/release-host/unsignedbuild gates → authorized PRdelivery → configured
deterministic-child release/runtime/publicacceptance. Entirefiniteobjective remains incomplete.

Local reviewed candidate44540017c2d8981bfbe2bdd1901e0136bc0621cc committed on main after
source-candidate-5.log EXIT0 (exact fullnamespace14+18 deferrednone); tree
c13f8201886810453a5d8a598071c136e4ea2711, canonicalSHA
75cbe126cc6a8f8b771fa5dd170f3cbf603bf56f0f75dd9dd9eb3f9930978dbc. Independent
187-file/mode/stability review PASS, no material unresolved source finding then. Canonical
unprivileged build and separate fresh-container verification both EXIT0/all6packages:
gate-build.qSAJfyHY; metadataSHAa086d4c9a33f3b9cb5a46cc8eacd3afc9b1596c4b94845900009ed4754288a97,
unsignedSHA9082ed8df7eff6b726e8a528ac461a14e7d870b340a490274726c3dd1c1b842e.
Owned containers removed. These results belong only to4454001; final candidate remains pending.

ARCH actual October Minimal attempt minimal-20261003T145600Z-b3895c93: unchanged public1.0.5
installer zeroexit, completed installation and real firstboot/QGA; overall FAIL at readback
command availability (verify.sh1347), not a successful media qualification. Evidence retained
compactly outside source, owned QEMU/disk/VARS cleaned. Diagnostic tool prerequisite missing
on newly supported Minimal media route; jq is required by public readback and not provisioned
by published Minimal VM support. QA/ARCH correction is necessary bounded harness work, not
an installer/pin change: storage_guards owns run.sh/guestverify/runtime regressions; root owns
PLAN. Add explicit prerequisite phase restricted to media qualification, useful missing-tool
diagnostic and actual regression; review/test/newcleanharness commit before fresh VM rerun.
Old FAIL remains historical; no PASS or new pin accepted. Root release-host payload is prepared
but not launched, must regenerate against final accepted tree. Current official observation at
2026-10-03T14:59:45Z: GNOME50.5/GDM50.3, systemd262/mkinitcpio42.2; GNOME51 condition not met.

QA media-tool correction accepted: independent narrow review no material finding,
36 actual-helper/routing regressions PASS; full source-media-fix-6.log EXIT0/exact fullnamespace
14+18 deferrednone. Committed harness1b45bbaf2cdf30f4e97f8bfcf9546272f055b376, tree
c030057d45a4c81947f662b3bbbf08c908481b37, canonicalSHA
d90ceb1247724305281a400aa17220f4398966d563d8535d0322267f18d59d36.
Product installer/bootstrap/package/trust bytes remained unchanged by this correction.

ARCH October media qualification ACTUAL PASS on the same1b45bba harness and unchanged
public1.0.5 product61add3e0b2c20adbbdd425494eae02ddec0a3bac/treeb5ca51e80277d93541d00a305490ac818d629a33:
Minimal minimal-20261003T151714Z-2c0c2415, Stock stock-20261003T152418Z-552739f5. Exact ISO
684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5; signatures/public
Release+Pages binding PASS. Minimal13assertions, Stock20assertions include firstboot/network,
fullupdate/anotherboot/no failedunits/cleanpoweroff/qemu-img/ownedcleanup; Stock realGDM
password+Wayland/lock-password-unlock/secondrealpasswordlogin PASS. Both owned disks/VARS/
QEMU cleaned; compact retained evidence6,167,963B/9,242,126B outside source. Original failed
Minimal remains a separate historical FAIL; it is not relabelled. Corrected product acceptance
still belongs to RELEASE01's authoritative child, not these old-product media runs.

Human ISO review requested only now with concrete validated patch outside source:
proposed-accepted-arch-iso.patch/json; accepted pin remains2026.09.01 until owner decision.
Commit-all-baseline and ready PR exception remain authorized, never request again.
Independent mandatory release-host execution assigned archive_limits on immutable1b45bba
input in fresh gate-release-host-1b45bba VM (4GiB/2vCPU/16GiBdisk, check RAM>=5GiB/free24GiB).
This is the first actual release-host fixture/environment run, not a transferred final-candidate
PASS. If accepted pin/docs changes finaltree, applicable final gates must bind that newtree.
Root owns source/PLAN; worker guest-only fixture changes and exactownedcleanup, no production
keys/hostpermissions/settings/Git/publication. Next: await exactrootfixtures and ISOdecision,
apply only reviewed media state/docs → final stable candidate source/build/root gates → ready
PRdelivery → configured release pipeline + publicacceptance. Entire goal remains incomplete.

Owner explicitly accepted ISO2026.10.01 after both real qualification PASS results. Applied
only proposed accepted-state JSON and targeted compatibility/maintenance prose; September
baseline/history retained. Exact SHA684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5.
Affected source checks and final candidate freeze are next; no pin approval remains pending.
First five release-host fixture commands on immutable1b input exposed provisioning gaps:
chroot blocks CLONE_NEWUSER; publication stdin boundary failed; parted/partprobe absent.
Ordinary keyring PASS only. Preserve failed logs; archive_limits converts the same owned VM
to real guest-root boot and adds guest-only parted, then repeats unchanged five commands.
These are environment failures, not established source regressions or final GATE acceptance.

ARCH pre-merge source/media deliverables accepted: runtime records actual systemd/mkinitcpio,
checks installed kernel/initramfs/module pairing before update and after reboot, and retains
LUKS/bootloader/Btrfs real-boot routes. Conditional TPM PCR guidance present. GNOME51 is not
in stable at the recorded official observation; that conditional expansion is not triggered.
Corrected-child execution remains mandatory RELEASE01 acceptance, not a transferred media PASS.

Accepted ISO affected verification: source-accepted-iso-7.log EXIT0, exact repository
fullnamespace/scenarios10/signerpassed/14+18/deferrednone; maintenance-accepted-iso.log EXIT0,
docs29 and diff checks PASS after checklist prose updates. These are pre-freeze results;
next clean candidate gets an exact-tree source receipt and fresh canonicalbuild/root gates.

Owner-reviewed ISO candidate eb10c615be0bce36d3ed58676ff0e7700ca94d41, tree
fef6d8d02506154504622eca9247b370d6e4173a, canonicalSHA
c129cb275f8cfaea57e6d4e7358cb89c299670a976ba347932a291071c6f8012.
Narrow independent pin/provenance review PASS; source-clean-iso-8.log EXIT0 on clean candidate
with exact fullnamespace14+18/deferrednone. First realguest1b release-host results: repository
ordinary/full PASS0; keyring ordinary/privileged PASS0, exact required markers. Publication
FAIL1 reproduced after initial accepted-input sealing succeeded: its synthetic fixture omits
new mandatory repository/verify-database-metadata.py, so sealer rejects incomplete closure.
No compiler/production-key cause. storage_guards owns only publication fixture + useful
actions-signing regression; root owns PLAN. Preserve first failures, fresh exactcandidate
source/build/root gates after fix; no affected PASS transferred. Entire GATE/RELEASE incomplete.

First release-host evidence accepted honestly: gate-release-host-1b45bba/evidence/receipt.json
records real installedguest statuses0/0/1/0/0, exact identitybefore/afterequal, strictfourPASS
markers and preceding chroot failures separately. Cleanpowerdown, both qemu-img checks and
ownprocess absence verified; worker removed only recorded disks/raw/VARS/kernel/initrd/ISO/
inputarchive. No mandatory VM remains from that attempt. Related publication fixture wrapper
was CLI-only; new DB verifier imports its bounded API. Focused correction preserves canonical
hash/owner/mode/nlink/identity checks and exposes only verified captured Python code on import;
actual API integration and wrong-input regressions required before new exactcandidate VM.

Publication fixture correction frozen in tests/publication-root-check.sh and
tests/actions-signing-checks.py only: genuine mandatory DB verifier copied; existing metadata
wrapper retains CLIexecv and canonical owner/mode/nlink/identity/hash checks, runpy exposes
the already captured hash-verified code with canonical__file__/nonmainname. RED incomplete
requiredclosure and RED importedwrapperCLI reproduced, then GREEN realDBrecords/boundedAPI/
wronghash/wrongowner/unchangedCLI. Focused13testsPASS with2expectedrootonlySKIP; Bashsyntax/
ShellCheck/diffPASS. Independent stable review and fullsource/currentcandidate VM remain
required; no root-publication PASS claimed from source/mock checks.

Publication fixture independent narrow review PASS on stable2filehashes, no material finding.
Full source-publication-fixture-9.log EXIT0 exactfullnamespace14+18/deferrednone. Only final
checkpoint prose follows that full run; docs29/diff rechecked before commit. Next frozen
candidate receives clean fullsource receipt, fresh canonicalunprivilegedbuild+independent
verification and allfive actual release-host guest gates. Reusable guest recipe now installs
linux+parted, provisions immutableRO source, realguestboots before gates (no chroot gates).
Retain exacthistorical1b0/0/1/0/0; acceptance is incomplete until new publication succeeds.

GATE01 accepted exact00cde4fcabfb3f805b8f15565b331fec424a4ec9/tree
96927d2bf87665e93b4cd0f516e46509a104a96b/canonicalSHA
3ea372b30f853ec6e36bee38d24f369d6f63e7748c38d7716ec7ca1a6293e643. Clean
source-final-clean-10.log EXIT0 fullnamespace14+18/none; canonicalbuild+freshindependentverify
EXIT0 sixpackages gate-build.W7Jo60Od. MetadataSHA785c9d8105fd59f994b971b3b69e50c2cc10c93e1cfb1a656d57cddad03f1cef;
unsignedSHA9082ed8df7eff6b726e8a528ac461a14e7d870b340a490274726c3dd1c1b842e.
Final realguest evidence gate-release-host-00cde4f/evidence/receipt.json: allfive EXIT0/exact
requiredmarkers, sourceidentity before/afterequal, cleanpowerdown/qemuimg/ownedcleanup PASS.
Root independently checked native5logs/hashmap/statuses/identity. Hostwrapper ANSI-footer
parser EXIT1 separately recorded; native command results are actualPASS, not inferred.
Stable independent source/pin/fixture reviews PASS. No owned containers/VMs remain.

Authorized samecheckout PR51 created/pushed; Sourcechecks run37136155046 SUCCESS then
squashmerge74c18c98fe1b3ca5817de8f55fd7280d210daf81 at2026-10-03T16:17:59Z.
Accepted fourcommits preserved on local/remote deliver/installer-hardening-20261003; local
main safely aligned to preserved originbase while on PRbranch, then returned/FFonly to
mergedmain. Its tree exactly96927d2bf87665e93b4cd0f516e46509a104a96b. No forcepush/reset/
clean/stash/extra checkout. Newmain CI37136338034 IN_PROGRESS; configured Release should
automatically follow success. Production-child source/build/signing/9VM/final18/tag/Pages/
freshpublicMarble NOT_RUN yet. Entirefinite Goal remainsACTIVE/incomplete. This checkpoint
prose is a later local documentation update, not transferred product acceptance for a newtree.

Main CI37136338034 SUCCESS. Automatic configured Release37136479088 active, prepareSUCCESS
selected unused1.0.6 and deterministicchild5ab0ae8ea947a1684251ab8360d4f351f164d2c0/
tree510544f9a37a70298e1e230adf27ab52770ce6d0/canonicalSHA
e5f0ed9f733d7cf6b68e0c36ddc77f1421ea26ec44d09036fdc46f397ab40d84.
Publicnonsecret sourceartifact bundleSHA0bfab6e7a982b2bb9ca542595b9cb690f8ea4ae96eebe95d91c664914877a059
verified outside source; no localchildcheckout/restoration. Main74c/tree96927 bound separately.
CIchild canonical unsignedbuild in progress; snapshot/9VM/finalize/publicacceptance pending.
Root watcherhandle35328 logs release-37136479088-watch.log; no manualdispatch/publication.

Release37136479088 PhaseA exact14/signatures/metadata/payloads independentlyPASS; receipt
release-37136479088-phase-a-receipt.json SHA55313429ce5ff7d7d0a88c1ae3c1a21526bccd7750387646346a9c7f1417ded1.
Minimal staged14actualassertionsPASS minimal-20261003T163142Z-661679c7, boundexactchild/
snapshot/build/ISO. FiveCI VMjobsSUCCESS so far; twoFAIL, two stillrunning; finalization blocked.
StockBtrfsGRUB grub-20261003T163124Z-727cb55d FAIL snapshot-boot beforegrub-reboot, after20
actualinstall/login/update/rebootassertionsPASS. Official grub-btrfs4.14 withinstallerUUIDdisabled
producesdevice-root; selector+snapshotruntime assumeUUID-only. Authenticgenerator-shaped
device-rootRED/UUIDGREEN reproduce mismatch. Generatedcfg/traceback was lostbycompaction, so
historicalexactrootargument is supportedinference, not recoveredrawproof. PreserveFAIL.
Stockext4 stock-20261003T163120Z-8c1541cd FAILfirstboot after7assertions; gdm-user-session
timeout300s. Optionaldiagnostic capture afterReturn+3s stilluserlisttile; harness sentpassword
withoutactivationguard. Delayedgreeter helperfixture reproduceslostselection/secret-before
activation. No credential/product defect established.

Root reopens QA/GATE onlychangedpremises; allotherclosedwork/media/pins preserved.
storage_guards solewriter run.sh/guestverify/runtimechecks forcombinedfocusedfix: exact
independentlybound snapshot root identity in selection+runtime; bounded normalGDM activation
via newstable rootpasswordworker afterbaseline+realHMPReturn, then settle and existingactual
gdm-password/Wayland user checks. OfficialGDMresearch: worker creation is conversation-start
proxy, NOT exactfocusedpassword-entryproof; this limitation must remain explicit. No pixels/
autologin/QGAstarted session/DBuspassword/unsafeEval/securityrelaxation. Retainneededbounded
nonsecret failure diagnostics. Otherworkersreadonly; rootownsPLAN. RemainingactualVMs continue
independently; no changed-input rerun or prematurepublication. Newcorrectedcandidate will get
fresh source/build/root/readyPR thenautomaticnewchild allnine/publicgates; GoalACTIVE.

First authoritative child run37136479088 completedFAIL; rootdownloadedall9compactartifacts
and independentlymatchedeachsource/tree/installer/snapshot/build/unsigned/ISO binding.
SixactualPASS: Minimal14, StockencryptedGRUB22, StockBtrfssystemdboot21, Stockencrypted
systemdboot21, Marbleopt-inGDM26, MarbleStockGDM17 assertions. ThreeactualFAIL: Stockext4
firstboot7; StockBtrfsGRUBsnapshotprepare20; Minimaldualbootinstall-archiso0.
Their resultJSON/archivehash receipts remainoutside source under release-37136479088-vm.
Finalize18/tag/draft/Pages/publish/publicVM allSKIPPED, notNOT_TESTEDsuccess; publiclatest
API still1.0.5 fromSeptember17. Rootwatcher35328 endedEXIT1, no ongoingCIVMjob. Thirddualboot
preinstallationfailure assignedarchive_limits boundedreadonlydiagnosis; storage_guards only
writer current3harness files. ResetcurrentGATEchecklist fornewcandidate, preservingaccepted
00cde4f evidence. Newmain/child requiresfreshaffectedsource/build/root/runtime bindings; no
failedoldchildpublished, no changed-input rerun/tagmovement/assetreplacement.

Focused harness correction complete in five VM files only. Snapshot selector/runtime now bind
the actual target partition and its UUID/PARTUUID while retaining exact subvolume, overlay,
read-only lower filesystem and kernel/initramfs checks. GDM requires a new stable verified
password-conversation worker after baseline and a settle/recheck before keyboard input;
this is a conversation-start guard, not proof of password-field focus. Actual gdm-password
Wayland login, lock/unlock, update and second login remain mandatory runtime acceptance.
Dualboot negative full-installer probe now exposes its separate runtime-password prompt on
serial before normal READY. Protected bridge allows exactly two stage-bound deliveries only
for that scenario, preserving exact refusal status/cause, whole partition hashes and neighbor
checks. Secrets remain outside argv/env/config/log/evidence. Producer actual-input regression
RED then ten cases GREEN; host/runtime regressions RED then GREEN. Independent review caught
short READY matching against the producer's complete identity line; actual printf-format
regression RED3 then corrected full host-bound suffix GREEN. Stable runtime51, actions-release16,
harness/syntax/ShellCheck/diff checks PASS, QEMU NOT_RUN. First source-harness-fixes-11.log
EXIT0/fullnamespace14+18/none predates the READY correction and is retained as intermediate
evidence only. Final independent review PASS on stable five-file hashes after READY correction.
source-harness-fixes-12.log EXIT0, exact fullnamespace/scenarios10/signerpassed/14+18/none and
all required source tests passed; no material unresolved finding. Root verified stable hashes,
main74c18c9/index empty/exact six dirty paths/no untracked source. QA source acceptance DONE;
fresh frozen-candidate build/root gates, ready PR/new automatic child/allnine VM/final18/public
acceptance remain. Goal ACTIVE. Guest-runner preflight meets resources, generated-only ANSI
footer parser fixed with wrong/duplicate/missing-summary rejection; no historical receipt changed.

Corrected GATE accepted exact85e36c241957090b77c2c1c0de111021ad3b3039/tree
4c7df65e727ae7066fd64271c69159849f57fcf7/canonicalSHA
1a1ec5f6a33d449c8215406f1e37ccefc7d01f7d2b890ad884044fce2fbb46a7. Clean
source-harness-clean-13.log EXIT0/fullnamespace14+18/none; stable independent review PASS.
Canonical sixpackage build and fresh independent readonly-output verification EXIT0,
gate-build.jwr9gzlq. MetadataSHA8d1c8d9b4459d6d5a715520201bd4680b8d988092ce725db3c97f451315a53cd;
unsignedSHA671b5a271049b38a33cd014e01693b730e24a3a0bd6565f8d93a5667f7f2ea89. First generated
container lacked dconf (EXIT4); provisional retrieval stopped/reaped137 to complete canonical
dependency preflight; both historical attempts retained, no source change. Final containers removed.
Actual guest gate-release-host-85e36c2 first provisioning failed on slow official Python signature
retrieval before any acceptance command. Fresh retry1 ordinary verified retrieval succeeded;
misplaced guest-only timeout directive was ignored, not credited as mitigation. Allfive native
commands EXIT0/exactonce requiredmarkers; sourceidentity before/after equal, wrapper0, cleanpowerdown,
both qemu-img checks and exactownedcleanup PASS. Root independently checked logs/receipt hash map/
identities/removedpaths. Receipt gate-release-host-85e36c2-retry1/evidence/receipt.json retained.
No source/pin/mirror/trust/host setting changed during environment correction. GATE01 DONE.

PR52 https://github.com/snaplyze/arch-linux/pull/52 Sourcechecks37142521407 SUCCESS; squashmerge
38cc6e6d7d3581fffa23ce45ab44b6c641e036c6 at2026-10-03T18:02:17Z, treeexact4c7df65e.
Candidate85 preserved local/remote deliver/vm-handshakes-20261003; localmain safely aligned to
verified preserved originbase74c while on PRbranch, then returned main and FFonly to mergedmain.
No forcepush/reset/clean/stash/extra checkout. Newmain CI/configured automatic Release pending.
This is later local checkpoint prose; accepted candidate/build/guest results retain exact85 binding.
New deterministic child must independently pass source/build/signing/allnine realVM/final18/public
acceptance. First child6PASS3FAIL/skippedpublication remains historical, not relabeled. Goal ACTIVE.

MainCI37142717508 SUCCESS; new configured Release37142858691 automatic prepareSUCCESS,
unused1.0.6 selected live. Exactchild3d560f304cd8a7ee49555b80721588c62d379b55/tree
d152706d87da62cb05510e5bcd729e68f2158f4f/canonicalSHA
c104048e1eeb465ddce08dbf9eb56c9aca7d6e429541b1533d63846aa7baf50e. Publicnonsecret sourcebundle
SHAeef6ffe932fc52f58bf8e8f1c7ba0c5740231121c7b63855bf4336003e3ceb76 verified outside source;
no localchildcheckout/restore. Rootwatcher74469 logs release-37142858691-watch.log. Buildactive;
PhaseA/9VM/final18/publicacceptance pending. monitoring boundedindependent freshPhaseA proof,
root owns results/PLAN/integration; priorfailedrun37136479088 unchanged. GoalACTIVE.

Freshchild prepare/build/independentreadback/snapshot jobs SUCCESS. PhaseA exact14 independently
PASS; receipt release-37142858691-phase-a-receipt.json SHA
49259cb8ed3a0cfaba422fee3b45e0a659415f032ea8fe8ec699ea7f75cd2f89. Root checkedactual14
filename/mode/size/hash map, child/main/source identity and sixpackage metadata bindings.
BuildmetadataSHAf72b4e44567d82f13f216f0d56acd4d63bd4671c7b416769b6bdd6ecd3c5780c;
unsignedSHA32fbaba5fc8dc2c1020d8b5c1288d772205c32817598242384fe3b3a5ad152cb;
snapshotmanifestSHAe24160a453931dfa820a6d04c74fd471070a4b9723db2e68b04c056db54a528c;
snapshotarchiveSHAa79cbf5ec98985a23e4a025746ee36a1cd58eae49cfc6b6c8ce208dfe06b2a98.
Cryptographic/publiccertificate/productionDB/6payload APIs and deterministicversion-only source
derivation PASS; no childcheckout/downloadedcode executed, no source-bound wholevalidator run
against another tree. Allnine actualVM active; no verdict transferred from firstfailedchild.
Final18/tag/Pages/publicacceptance pending; GoalACTIVE.

FreshactualMinimal PASS14 on exact3d560f3 snapshot/ISO/harness, resultnativebytes preserved.
Freshdualboot FAIL12 atpostreboot afterfixedcollision/passwordstage andactualinstallation;
no old0assertionFAIL relabeling. Rootchecked source/tree/build/unsigned/snapshot/manifest/ISO
and immutable-main sevenfileharnessdigest against downloaded nativeartifact origins. Independent
archive_limits boundedreadonly diagnosis assigned onlynewpostrebootcause; othereightVMs continue,
no cancellation orchanged-inputrerun. Finalization/publication remainblocked by actualdualbootFAIL.
Receipt under release-37142858691-vm, currentqueue RELEASE01; GoalACTIVE.

Dualbootnewcause verified: native neighbor-select line2552 exits32 mountingESP read-only a
second time while acceptedESP alreadyRW at/boot. InstalledOS postreboot/collision checksPASS;
neighbor selection/boot NOT_TESTED. LinuxRO/RWsuperblock mismatch explains EBUSY, but retained
stderr/errno absent, so mechanism is supportedinference; actualhelper model RED32 reproduced.
Archive_limits nowsolewriter guestverify+harnesschecks for validatedownedRO bind of accepted
existing/boot, exactFSROOT/source/readonly proof, preserved primarymount and6hash/identity/cleanup
checks. storage_guards boundedreadonly diagnosis of freshMarbleFAIL4firstboot separately;
useimmutablemain38 baseline, no overlappingwriter. QA/GATE reopened onlynewchangedpremises;
exact85 evidence and newMinimal14/StockBtrfs21PASS retained honestly. No newchildPASS transfer.
RemainingVMs continue; no unchangedretry/cancellation/prematurepublication. GoalACTIVE.

Neighborfix stable in guestverify+harnesschecks: actualoldorchestration RED32 then12GREEN
cases preserve original /boot mount, exactaccepted source/vfat/FSROOT/, ownedRO bind/recheck/
cleanup failure semantics and all6hash/UUID/PARTUUID readback. Syntax/ShellCheck/harness/runtime51
PASS, actualcorrectedneighborboot stillNOT_RUN. Archivefinished; guestverifyownership transferred
to storage for GDM area only, preserve neighborfix. FreshMarble actualprelogin andlegacy-install
PASS, then gdm-activation-baseline FAIL genericdispatch2587. Compaction removedrawreason, so
guard subcause unknown/productdefect notestablished. Actualhelperfixtures show legitimateopening
greeter and securitymetadatafailure indistinguishable; add boundednonsecretper-guarddiagnostics.
Independentlyreproduced one-shot baseline readiness defect will use existingbounded300s
wait_for_greeter beforecapture; checkphase/identity/security rejection remainstrict and password
withheld. No fieldfocus claim/autologin/pixelproof. NextactualVM decideshistoricalguardcause if
itrecurs. Storage solewriter guestverify/run/runtime, rootPLAN. GATE checklist reset onlyaffected
review/source/build/guest/freeze; exact85 PASS remains historical. GoalACTIVE.

Combined neighbor/GDM slice frozen in guestverify/harnesschecks/runtimechecks only; run.sh
unchanged61243a67. GDM actual-helper newtests RED12failures then expandedruntime54PASS;
initial inventory refactor shadow caught/fixed beforefreeze. Baseline waits existing300s legitimate
activegreeter contract; laterchecks immediate/anchoredstrict, everyguard fixednonsecretstep/reason,
inventory failures controlledwithoutarbitrarytracebacks. Worker metadata/UID/parent/exe/cgroup/
startidentity/security retained; no password onfailedprobe. Neighborfunction unchanged across
writerhandoff SHA3341dac96a6eaeff8b5184ab96140fc6e416469aa9812db725fe7bbf67a498f6.
Stable guestverify9bb61f28/runtime8f50ff1e/harnesscheckse4194359; runtime54/harnessneighbor12/
actions-release16/syntax/ShellCheck/diffPASS. monitoring bounded independent stable3file review;
rootfreshfullsource thenexactcandidatebuild/guest/readyPR/newchild pending. Secondchild currently
6actualPASS2FAIL, oneGRUB stillrunning; no newVM verdict transferred/oldinputretry. GoalACTIVE.

Secondchild37142858691 terminalFAIL, actual9 native scenario evidence independently bound to
3d560f3/tree/digests/ISO/immutable-main sevenfileharness:6PASS3FAIL. NewStockext4 PASS21,
StockBtrfsGRUB FAIL20 snapshot-boot (snapshotprepare advanced; newcause investigation),
dualboot FAIL12 postreboot neighborreadback, Marbleoptin FAIL4 baselineguard unknown.
Final18/tag/draft/Pages/publish/publicVM actuallySKIPPED; public1.0.5 unchanged. No failedrun
retry/publication/changedinputs. Fullsource-neighbor-gdm-14 EXIT1: real jq E2BIG transport
defect, verify133542B exceeds Linux128KiB singleargv; staticfixture correctly rejects.
Transport correction frozen: --rawfile hostread + documentedQGA input-data base64, fixed
small FD3 loader gives guest childstdin /dev/null and preserves27args/exactscriptbytes.
Actual>128KiB regressions RED E2BIG and rawfile-only missingstdin, runtime55/static unchanged/
harnessneighbor12/actions16/syntax/ShellCheck/diffPASS; actualVM NOT_RUN. NewGRUB failure
proved snapshot-prepare accepted1entry/PASS20, then actualsnapshotQEMU QGA300 timeout; guest
bootcauseUNKNOWN because compactor discardedserial/stderr/identity. Archive solewriter
run.sh+harnesschecks bounded sanitized bootdiagnostics/compactionregression, guest/runtime
frozen. Nextbuild recipe gate-build.aNHF629V preparedonlyNOT_RUN; exactcandidate andresourceGO
required. RootPLAN/Git/integration. GATE/QA/RELEASE remainIN_PROGRESS;
all exact85 evidence historical only, no newPASS transfer. GoalACTIVE.

Focused correction combinedslice stable: verifiedownedRO ESPbind + GDM boundedgreeterbaseline/
controlledreason diagnostics + completepublicscript QGA stdintransport + snapshotsafe fixedboot
classifications/identity and optionalscreenshot ontimeout. Stableindependentmonitoring reviewPASS;
actualproduction fixtures runtime55/neighbor12/bootdiagnostics6, syntax/ShellCheck/diffPASS.
Fullsource-neighbor-gdm-snapshot-15 EXIT0 includes exactfullnamespace10/signerpassed/14+18/none
and allrequiredsourcePASS. Currentsource-byte hashes run0dfa6f6a/guest9bb61f28/runtimec67dc0b4/
harnessa4e9fbcb; static89a107d7 unchanged. Docscheckpoint nowrecords source15 and resets onlynew
RELEASE candidate steps, priorPR51/52/childfailures preserved. Root explicitfivepathcommit +clean
fullsource16, exactfreshcanonicalbuild and5realguestgates next. Snapshotguestcause remainsUNKNOWN;
newdiagnostic evidence actualVM NOT_RUN. No product/bootsetting change inferredfromtimeout.
Preparedbuild gate-build.aNHF629V and guest gate-release-host-next.l955b_49 NOT_RUN, waitfrozen
identity/resourceGO. All15-ID finite scope retained;12DONE, QA/GATE/RELEASE IN_PROGRESS. GoalACTIVE.

Exact738de12 GATE accepted: cleanfullsource16 EXIT0 SHAaa475dd6a57efcd685253d6182d1284f1e15d207d1cef26aeac34da017c39490;
canonical6build/freshverify0 rootnative14filemodehashbindingPASS metadata1472bdab/unsigned022059d5,
receipt53ccf823;5realguestgates0 exactfull10/14+18/none, publicationsealed14/18/FIFO/memfd/ns4/
pid1/agent/supervisordeath, keyringordinarypartial5 andprivilegedfull10, exactbefore/afteridentity.
Guestreceipt ed783b11743542d9b91ff00f02bac51f1f314bc5466255901417dd2f4c222e68; rootchecked
allnativeSHA/markers/PIDstart/imagehealth and8recordedheavyfilesremoved; noownVM/containerleft.
PR53 SourceCI37147291681SUCCESS/squashmerge2026-10-03T19:19:53Z; samecheckout mainFF to
1a16609bb8ed14ec351b6e8224ccd6ca5536b85f/treefe51ad86dc98b350f26a7e1aa8ce4ec31883d944,
canonicalSHAe51914a70c0abd7b5275ea309d3bd87a2da860f4aaf78c20d631ed6acd98c1a8 unchanged.
Own738 candidatepreserved local+remote deliver/vm-readback-20261003; noreset/force/bypass.
MainCI37147497511SUCCESS → freshautomaticRelease37147640933, liveunused1.0.6, child
bb613cea7e59d85b70da3360971d737990f1b959/tree911f92dd4acdb87681c4ebe345efad628027add5/
canonicalSHA6631bafea6ff9635640d7c6a666dba281fee92bd0fc3291ab5786367b4a50ae1. Actualpublic
sourcebundle fff2b971c657d6e1ed93c3443c168f788b38c4698abcbff716b9efbbf48070d7 verified
withoutchildcheckout/import. NewPhaseA exact14 independently/rootactualmapPASS, receipt
639c67bd47127472185a97a4071a3aeafbc84a82ee2e08fa88da39527625da7f; build6f9b3b68,
unsigned32fbaba5, snapshotarchivebaf2a225, manifest a5832c2e. NooldchildPASS transfer.
Freshactualnative7PASS/1FAIL/1GRUBrunning: Minimal14, dualboot17(realbothOSboots/6neighborEFI
hashes+UUID/PARTUUID afterupdate/reboot), Stockext4/Btrfssystemdboot21 each, encryptedStock
systemdboot21/GRUB22, MarbleStockGDM17. MarbleoptinFAIL4 coarsefirstboot; initialroot inference beforefirstlogin correctedafterreadback:
GDM baseline/check/settled, reallegacy/migrated/fresh-user logins+logout andGTK4 light/dark smoke
PASS. Actualfailure return-user-login verify1940 wait_for_enabled_extensions exact8 notproven180s.
Underlying missing/unexpectedset vsqueryfailure UNKNOWN because helper discardsstatus/set/stderr;
actualhelper fixtures prove missing/queryexit1 indistinguishableemptydiag. Necessary controlled
GNOME_EXTENSION_DIAGNOSTIC distinguishes readonlyqueryfailure/mismatch/knownids/count/stateenum
on timeout, preserves exact8/180s andlogin/integrity/cleanup, no autoenable/reset/guessedfix.
Storage solewriter guestverify/runtime; archive solewriter run/harnesscompactorretention, rootPLAN.
CurrentGDM wait/transport fixedactualrealVM behavior; historicalsecondMarblecause remainsUNKNOWN.
No openingrace attribution/unchangedretry. GRUBsnapshot actualFAIL20, thirdRelease/watch86144 terminal1/FAIL7PASS2FAIL. Allfinal18/tag/draft/
Pages/publish/publicVM actuallySKIPPED. Newcontrolledsnapshot serialinspected/noerrorcodes and
root-viewedtimeoutframe show GRUBsnapshotmenu, kernelneverbooted. Source-supportedmechanism:
grub-btrfs outer submenu callsconfigfile, freshcontext copiesonlyexportedvars, currentcontinuous
grub-reboot path losesdefault/timeout atboundary. Installer/productconfig notdefectivebythisproof.
Rootselected strictlyrunowned one-shotselector exporting validatedinnerdefault+timeout then
existingproductionconfigfile; preserveproductionentries/kernelargs/bytes andreadonlylowerdir/
volatileoverlay/modulepair/realpasswordlogin/normalreturn. Archive nowsolewriter snapshotareas
guestverify/run/harness/runtime, storage extensiondiag frozen guestcfb37345/runtimef35cfdcd
(58runtime/static/harness/syntax/ShellCheck/diffPASS). No overlap; preserveextensionmarkerretention
runffcc539b/harness7eb77182. BoundedrealGRUB semanticfixture authorized onlydisposabletoolcontainer
1CPU512MiB128pids10min/freshminiQEMU512MiB1CPU2min, nohostinstall/signing/config; actual
productVM acceptance remainsnewCI. Final18/public blockedbytwo actualfailedrequirements; no publication/rerun/cancellation. RootPLAN and assignedfocusedharnesschanges dirty onmain;
codeimmutable1a sourceinputs unchanged. Rootreceipt.snapshotDiagnosticCandidate contains exact
acceptedgate/delivery/14proof/8native bindings. All15 scope retained, GoalACTIVE.

Current focused slice frozen: guestccfa0853/runtime05fa77e4/harness0dbf85e5/runffcc539b.
Actual helper regressions runtime64/harness/static/syntax/ShellCheck/diff PASS, including owned
selector creation/production regeneration failure/changed fragment cleanup refusal and finite
known-extension State diagnostics (eight readonly queries bounded5s, no raw fields). Selector
uses only validated inner title/default/timeout exported before existing production configfile;
production grub-btrfs.cfg byte hash retained through generation/runtime. Snapshot identity,
readonly lowerdir, volatile overlay, kernel/initramfs pair, real login and normal return stay required.
Actual GRUB2:2.16-1 miniEFI old route stalled20s and required owned termination; canonical
exported helper reached exactleaf and exited naturally. Root independently matched input/serial
hashes, verified both PID/start identities absent and exact owned container absent; EFI/VARS
removed, compact receipt retained at grub-semantic-1a16609/receipt.json. This is mechanism proof,
not product VM PASS. Marble actual underlying extension failure remains UNKNOWN.
Fullsource17 EXIT0 SHA c454818d31bc6f91548e2c95952a90aecef99eac11427a75fcb36538a4b78b86
with exact fullnamespace10/signerpassed/14+18/deferrednone and all required source tests.
Independent monitoring stable four-file review PASS: runtime64/harness/syntax/ShellCheck/diff
EXIT0 and source hashes unchanged; no material findings. Root will commit only reviewed five
paths, run clean fullsource18, bind exact new commit/tree/canonicalSHA, then fresh build and
five real guest gates. Prepared generated build gate-build.j5w5ze90 and guest
gate-release-host-next.cbszbvzz are NOT_RUN, prior738 evidence remains historical. No installer,
package, repository/trust or accepted ISO inputs changed. All15 scope retained:12DONE,
QA/GATE/RELEASE IN_PROGRESS. Root owns PLAN/Git; no source writer active; GoalACTIVE.

October4 checkpoint: exactc39fe52/treeff0293/canonicaled7e4ec1 accepted clean source18
EXIT0 SHA727d294d4a03e410e09823a771bf264be67b1addcb3af60518012fe5aac14255,
canonical six-package build + separate readonly verifier0 (receipt gate-build.j5w5ze90/receipt.json),
and five actual installed-root gates0 with strict full10/14+18/none, sealedpublication and bothkeyring
markers. Root independently verified native hashes/modes/exact14 unsignedclosure/identity/PIDs/
threeimagehealth logs and eightownedheavyfiles removed; guestreceipt51186886c16fb3db2588ff66a7f8f91b243b586af235054ec11059aa0c482e7c.
PR54 SourceCI37152233238 SUCCESS, squashmerge2026-10-03T20:41:09Z, samecheckout mainFF
f9d14ce7940f1f19f57d3717f67bc832eb59188e with unchangedtree/canonicalbytes; owncandidate
preserved local+remote deliver/snapshot-selector-20261003, no reset/force/workloss.
MainCI37152428414 SUCCESS → fresh automaticRelease37152580086, pipeline-selectedunused1.0.6,
childebb168bd9627a017f9b481e90d2157cd3847d420/tree06b20d4664765c780d7275b3d9a5ecf91d3ec16e/
canonical840b8e563a128798b61918fedcb8de5c4aa83c2fed68b7a25a31126f323bb469. Rootbundleverify0
requires exactmainf9, bundleSHA4d80361d2abafcfcd52c2f49f12ff1f3cd106af0698b048c4b4819797859cd6a,
no childcheckout/objectimport. FreshPhaseA proof exact14/signatures/cert/schema2/DB/6payload/
in-memorydeterministicderive PASS; receipt88ba57ac2e42358a89eb004eadc2ace78b87b9408dec6b314987f474ad986ace.
Root independently rehashed14mode/size/map and actualthreeoutergpgv signatures with committedtrust.
Fourthrelease terminalFAIL7PASS2FAIL; allnine nativecompactJSON bound to exactchild/ISO/snapshot
and immutable-main sevenfileharness920093472d678bf08c5822ece1788303822aa5502fd92a1732b76e2fe7856a1e.
PASS: Minimal14, dualboot17(actualbothOSboots), Stockext4/Btrfssystemdboot21 each, encryptedStock
systemdboot21/GRUB22, MarbleStockGDM17. FAIL: StockBtrfsGRUB20 snapshot-boot now QGAready
then snapshot-prelogin verify_snapshot_runtime return1 (callerline1434 loses guard); wrapper
productioncfg hash validation/preparation PASS, no QGAtimeout. Exactfailingguard UNKNOWN.
Primarysystemd262 source overlays /sysroot in place, covering lowerBtrfs; current lowerdirpathname
helper rejects modeled legitimate topology. This is reproduced verifier hypothesis, not proof
of actualfirstguard. Archive read-only bounded cause investigation/realLinuxsemanticproposal.
Marbleoptin4 coarsefirstboot actualreturn-user-login: controlledtimeout proves querysuccess,
expected8/actual0/missing8, disable-user-extensions=true, allknown8 initialized. Whyflagbecametrue
UNKNOWN; officialGNOME50 early-start OnFailure service is possiblewriter, no actualjournal yet.
Existing originallogout is already gnome-session-quit --logout --no-prompt; forcedlogout attribution
is unsupported. Storage readonly causal investigation; no autoenable/reset/weakening.
Final18/tag/draft/Pages/publication/publicVM actuallySKIPPED; public1.0.5 unchanged. RootPLAN
updated in place, generated frozen-final-gate-candidate.json preserves allfour attempts/receipts.
All15 original scope retained:12DONE, QA/GATE/RELEASE IN_PROGRESS; GoalACTIVE.

Next bounded decisions: Marble requires known Shell/recovery-unit typed readback beforelogout
and at extensiontimeout, retaining only fixed units/enums/counts/hashes through failed-evidence
compaction. Normal gnome-session-quit, exacteight/180s/login/cleanup remain unchanged. Acceptance:
actualfunction RED→GREEN recovery/normal/malformed/unavailable/redaction cases, stable review,
fresh source/build/realprivileged gates and next authoritative child actualShellcause evidence.
Storage soleguestverify/runtime editor; monitoring solerun/harness editor. GRUB fix notselected yet:
archive owns only bounded outside-source realLinuxsemanticfixture (one4GiB2CPU/512MiBdata
disk/freshVARS/approvedISO/privateguestnamespace/15min) to distinguish hiddenlower topology
and surviving directmount evidence through roottransition. Require exact snapshotRO/subvol/
UUID/PARTUUID/marker groundtruth, no unrelatedROremount/cmdline-only PASS; native compactreceipt
and ownedPID/imagehealth/cleanup. RootPLAN/Git/acceptance, all15queue retained, GoalACTIVE.

Continuation decision: actual Linux7.2.7/systemd262 fixture linux-overlay-semantic.88uzwp4d
completed overlay/pivot/detach EXIT0; root verified four native stage records, retained lowerFD
readonly/device/marker and disappearing lower pathname/mountinfo, exact input/log hashes, both
PID/start identities absent and image health. Receipt47280322058eabaf365d8abcb4513640d962086c7451389b479d714e750be093.
Only detached-layer mechanism proof, not installed-system acceptance. Independent monitoring
found upper/work tmpfs also unmounted by systemd: inaccessible upperpath absence plus freshRO
remount/cmdline/backingdevice cannot establish live marker origin. Proposed triangulation rejected;
strict snapshot guards retained. Next QA01 slice adds finite per-guard SNAPSHOT_RUNTIME_DIAGNOSTIC
through command-substitution stderr and failed-evidence compactor, meaningful guard/redaction
regressions, no raw cmdline/path/environment and no acceptance weakening. Archive sole snapshot
guest/runtime editor; monitoring sole compactor/harness editor; frozen Shell diagnostics preserved.
Shell slice independent stable review PASS, fullsource19 EXIT0 SHA
8c62a81a004c7b1aa19d7f9abb056f3346582b3f7d384a5c3c1ebc8076928d57; actual Shell cause still
UNKNOWN until next authoritative VM. Storage bounded readonly late-layer API investigation;
no initrd/production boot instrumentation selected. Root PLAN/Git/acceptance, GoalACTIVE, all15
IDs retained:12DONE and QA/GATE/RELEASE IN_PROGRESS. No released bytes/tags changed.

Focused snapshot diagnostic slice accepted: actual26 per-guard failures plus rootargument through
command substitution yield empty stdout/single finite stderr marker; unknown values redacted.
Runtime74/static/harness/syntax/ShellCheck/diff EXIT0, independent stable four-file review PASS.
Full source20 EXIT0 with fullnamespace10/signerpassed/14+18/deferrednone/allrequiredtests;
source-shell-snapshot-diagnostics-20.log SHAb7f6ff095d93f454af775949a4434de3b0ddec0d52c87ddb225d17a516f53d37. This working-tree result precedes
final candidate freeze; source/build/privileged/actualVM/public gates remain required for new tree.
Bounded primary-source research rejected name_to_handle_at lower-origin handle as data-source
proof: copy-up can preserve lowerorigin while serving upperdata. Selected next mechanism experiment
only: uniquePID synchronous marker read through actual systemd overlay observed at Btrfs backing
read using guest-only BTF/BPF, exactinode/rootid/fsUUID/immutableRO and pairedsuccessfulreturn;
copied-up tmpfs samebytes negative must yield no lowerproof. First BPFfixture.JKZMITD2 terminalFAIL:
actual256MiBcowspace prerequisite corrected to2GiB inside4GiBguest, fullSyu/BTF/bpftrace0.27 PASS,
qualifiedprobe rejected modulebtrfs-not-loaded. Unqualified empty-stderr discriminator lacked native
status, no attachPASS inferred; data-origin proof NOT_PROVEN/uppernegative NOT_RUN. Four genuine
overlay stages, native hashes/PIDs/imagehealth independently verified; five exactownedheavyfiles
removed, compactreceipt23c1b599d3326c8c312d2696263e2676d6e9784ae7fc2f5f5c4eee45ce02ce62 retained.
Next changed-prerequisite prooffixture.j7ml4zpm: unqualified matched entry/return withknowninode,
parent-namespace retained native statuses/errors, actualsamebytes upper-copyup negative. Storage
sole generated probe editor; root checker/PLAN/acceptance owner; archive sole other generated fixture
editor/executor; root review GO before launch. Fresh4GiB2CPU/512MiBowneddata/privateguestnamespace/approvedISO/freshVARS/max15min,
explicitresourceGO, no host/productioninitrd/kernel/GRUB modifications. Native proof+hashes/PID/
imagehealth/exactownedcleanup required. Rootdiagnostics commit8614564 clean source21 EXIT0 SHA
73c9a9602e39f6046c95e53a55d671f8b435489ba2e3a384dc470627afb8c1aa, tree98e4ebc/canonical211f43ac
accepted before this checkpoint; source4files frozen. No production verifier replacement selected.

Proof experiment j7ml4zpm attempts retained once: first actual native1 tracefs ENOENT; second
actual native2 missing private `/tmp`; neither reached paired read proof. Third actual original-root
BTF compile/attach native0 emitted ATTACHED+COMPLETE pending0, but strict preflight correctly
FAIL on pointer-signedness and two discarded-delete-return compiler warnings. Only before-stage
groundtruth executed; positive/upper-copyup negative NOT_RUN, product acceptance false. Root
verified all receipt hashes, native output, absent PID572985 and healthy image; receipt
ffca7d70370bcb295c04157e5cb1117253e5d1d4100c61e70e7d8248d17a579a. Aggregate live upper435s/900s.
Fourth warning correction passed actual original-root compile/attach preflight native0 with
empty stderr and only78B controlled stdout. Actual detached-overlay Btrfs marker read returned
17B plus EOF0, but strict proof FAIL because signed FSID bytes serialized with `ffffff` prefixes.
Upper-copyup negative NOT_RUN; no proof PASS transferred. Root all hashes/native outputs/four
stages/PID574773 absence/imagehealth accepted, receipt93db02208929d63b54af6b9f9ef7d14ac41e802f189183be02644ff3c110a33f.
Fifth unsigned-byte correction actual semantic proof PASS: preflight/positive/negative native0,
empty stderr/warnings, exact284B positive returns17+EOF0 from expectedinode266/root257/UUID/RO;
actual same-byte upper copyup still reads17B but zero Btrfs READ rows (95B negative) accepted.
Root independently re-ran strict checker against retained native buffers, all hashes/four stages/
PID576318 absence/imagehealth verified; receiptac600c248f6c001a196d4e09c6225826d879b1b4990261b1908fd4b31e330b5d.
Exact owned heavy resources removed after immutable attempt5 history; cleanedreceipt
bc2c95c3a173a9583e72350c0edc51f4c3488cf3905eb419d20c4d5055a3ca40. Source unchanged; this is
mechanism acceptance only, not installed snapshot or product PASS. Aggregate725s/900s,175s
remaining for required actual backing-mount RO/single-physical-device/entry-return stability
field extension: storage sole generated probe/checker editor, archive other fixture/executor,
root integration/review/PLAN. Sixth generated extension RED17failures+3errors→GREEN10tests and
independent stable review passed, but actual native compile FAIL134: entry BPF stack limit
exceeded,2451B stderrSHA0be1830a8f5e1b04ccf85b1f605df409e0439f9b29bec95ca8915892952fae11.
Only before stage ran; physical/mount fields and positive/negative NOT_RUN. Root all hashes,
exact sixth-only native suffix/PID583853 absence/imagehealth verified; original appended logs
retained and old COMPLETE false wrapper0 match rejected. Receipt3c9941aa86c66583529afd41f09dc7da07b6d1a4d4651f85c67f9e02eb16176f;
exact owned cleanup after immutable attempt6 history, cleanedreceipt
3264918fecf9014f401fa524837af7c46cee7f05d5be67e82039cd201927ce34. Generated fresh-log exclusive
creation guard/regressions fix historical-match hazard. Original live upper869s/900s retained;
31s insufficient for another fresh boot, no automatic seventh. Next changed algorithm: small
incremental map groups reduce stack use while retaining every field and entry/return comparison;
root bounded next experiment decision required, no kernel-limit increase or check weakening.
Future production proof must additionally bind actual backing mount RO and single physical
partition identity via actual guest BTF; UUID/root property alone is insufficient. Independent
review requires marker FD opened under root overlay without symlinks/mount crossings and with
matching root mount ID; expected snapshot root ID/inode captured before boot; dynamic marker
length, bounded paired read/EOF, strict warning/drop/pending rejection and owned cleanup. Tool
installation belongs to existing GRUB update transaction before reboot, not a second upgrade
during snapshot preparation. Existing cmdline/kernel/EFI/package/service/network guards retained.

Next focused implementation decision: generated observer uses48 exact scalar map cells with
immediate stores/comparisons and four small CORE/UUID/DEVICE/STATE records keyed by paired-read
event1..2; strict consumer rejects missing/duplicate/mixed/gapped groups. Prior869s and original
900s ceiling retained; changed algorithm will receive a separate210s maximum live stage only
after stable review, cumulative bound1079s, no attempt reset or kernel limit override. In
parallel root solely edits guest/verify.sh and runtime-checks.py for the independent marker
reader leaf: root-relative openat2 BENEATH/NO_SYMLINKS/NO_XDEV, same root mount ID, safe regular
owned file, exact dynamic run-id bytes/EOF and stable before/after identity. RED→GREEN precedes
helper; no runtime integration until backing proof ready. Other source files remain frozen;
new source gates required after integration, historical source21 belongs only to8614564.

Reader leaf accepted independently: nine focused regressions and full runtime83 tests EXIT0
(14.569s); exact Linux openat2 mount/symlink/metadata/bytes/stable-identity rejection verified.
Reader remains unused until integration, installed guest NOT_TESTED; new fullsource gate pending.
Stage7 scalar-map generated observer stable root/independent12 tests PASS; fresh exact-input
VM launched PID589570/start106487408 after resourceGO,210s live cap/prior869 retained. Native
compile/physicalmount proof/upper negative pending, no product PASS inferred.

Stage7 terminal FAIL: actual entry compiler stack exceeded, native153/wrapper1 on freshlogs.
Only before-stage ran; positive/negative/effective features NOT_RUN. Root all retained hashes,
native status/stage/PID absence/image health verified; receipt24aa3f6443bf5681b6728bb61921f42626f576a256eefa39ec6ada259700dcb3.
Full8192B native stderr advertised hash is guest-only; retained4096B excerpt independently
verified, no full-output claim. Live141s/cumulative1010s preserved; exact owned cleanup
authorized after immutable history. Next hypothesis is six small attached entry/return pairs (CORE, UUID_A, UUID_B, MOUNT_DEVICE,
FS_STATE, DEV_STATE), with bounded tuples and every old field retained. Each group binds
start position/request count/end position/retval for the same single-thread reader FD;
independent ordinal mixing was rejected by review. Stage8 preparation only: cap240s, prior
1010s retained/cumulative planned1250s, no source integration or VM launch before stable
generated review and resourceGO. Exact stage7 owned cleanup receipt
0b98faafb17d6766624fdf8bc2da6cb2e8590c1ede181dfba2e4d5f6dec22978; retained history unchanged.

Six-group stable generated review accepted: all48 fields retained, tuples10/17/17/15/17/13
words and printf payloads at most128B; root/independent14 checker regressions EXIT0.
Before nativeGO, focused required fix: END unsignedsum can cancel MAXinflight+broken1 to0.
Root and independent review confirmed arithmetic; proposed map-failure path NOT_REPRODUCED.
Replace with booleanOR of all12 nonzero counters and regress actual emitted predicate.
Stage8 remains NOT_LAUNCHED; same prior1010/cap240, sourceintegration NOT_RUN.

Focused counter correction RED→GREEN15 tests and independent stable review PASS: reconstructing
oldsum reproduces oldprobe hash, all12 counters exactly once/newOR and actualexpression
regressions accepted. Final generated probe dca09cc3/checker eb18e0f5, payloadISO8ebc7f7b,
preparation0450e6f1 closure independently verified. Stage8 GO after resource recheck, max240s
/prior1010 retained; actual canonical31B root-overlay reader with six commonfield groups and
upper-copyup negative. Native results pending, no sourceintegration/product PASS inferred.

Stage8 terminal diagnostic FAIL: compiler warnings filled native8192B stdout, native153/
wrapper1; stdout f4fc1bcd and215B stderr de033bb5 fully retained/advertised hashes matched.
Signed map-counter arithmetic and redundant uint64 casts are confirmed. Compile/attach after
warningcap UNKNOWN; no inferred stack PASS/FAIL, positive/negative/features NOT_RUN. Root
all hashes/nativebeforegroundtruth/PID599435 absence/imagehealth accepted; receiptccee6050.
Exact owned cleanup after immutable attempt8 history, cleanedreceipt29114359. Actual live
upper140s/cumulative1150 retained. Next focused generated typing correction preserves every
field/comparison and strictwarning rejection; sourceintegration still NOT_RUN.

Focused type correction accepted stable root/independent review: signed bounded inflight
+1/-1 and28 redundant U64 casts removed; raw pointer casts/unsigned narrow UUID widening,
all48 identity fields, six call groups and OR12 cleanup predicate unchanged. RED1→GREEN16
self-tests; native warnings after oldcap remain UNKNOWN. Stage9 exactprobe4f413093/checker
d1d9a324/ISO b2b2fe9e/preparationf784f0f6 closure verified, GO after fresh resource recheck:
max240s/prior1150 retained/planned1390, no automatic10. Nativecompile/proof pending.

Stage9 actual strict compile/attach PASS: native0/78B stdout84d653d4/empty stderr, exact
controls plus permitted blank lines, no compilerwarning. Native IR programcount NOT_TESTED,
no data-origin proof inferred. Generated feature observer then FAIL on its single-record
mountpoint assumption: covered lower and effective overlay legitimately share pathname.
Before+covered actual groundtruth verified; positive/negative NOT_RUN. Root all input/native
hashes/PID602092 absence/imagehealth accepted, receipt38493b32; actual142s/cumulative1292
retained. Exact owned cleanup authorized. Focused stage10 preparation: choose actual openedFD
mnt_id and exact overlay mountinfo record, stableFD identity; strict stackedmount regressions.
Same frozenprobe/checker, new240s max/planned1532/noreset; no sourceintegration or productPASS.

Stage9 exactownedcleanup complete, cleanedreceipt d614370e. Stage10 focusedfeaturefix
RED actualstackedrecords→GREEN6 tests plus independentstable review/syntax/ShellCheck PASS.
Actualreader mount_id/identity helper selectsone effectiveFD-overlay mountrecord, checks
stability, finitefeatureJSON unchanged/no rawpaths. Feature6ee44db6/preparationf815383c/ISO
d3c499f5 closure independently verified; probe4f413093/checkerd1d9a324 unchanged. Stage10GO
with fresh resource recheck, cap240/prior1292 retained/planned1532. Full backingpositive/
uppernegative still pending, sourceintegration NOT_RUN; QA/GATE/RELEASE remain open.

Stage10 actual full semantic proof PASS: preflight/positive/negative native0, exact retained
buffers and six common-field groups independently checked by root; lower31B+EOF resolves
to expected root257/inode266/UUID/RO backing mount/sole physical254:1, real same-bytes upper
copyup produces zero Btrfs read events. All4 held-FD groundtruth stages PASS including detached
oldroot; effective module metacopy/redirect/index/xino Y despite absent listed options, so
absence is not inferred off. Receipt9a35ba94; installed-product acceptance remains NOT_TESTED.
Executor automatic protection error occurred after actual launch; root adopted existing
PID604035/start106807536 within unchanged240s bound, no second launch/protection changes.
Wrapper status NOT_CAPTURED; actual guest COMPLETE/native0/PID absence/imagehealth verified.
Actual upper145s/cumulative1437s, original history and caps retained. Exact3 owned heavyfiles
removed after accepted hashes/health; cleaned receipt 0f18e176ef2e0121cef09a7e01e3ea8e1ab191731dc0cbadc2cef4e7690ffb49.
Next ready work delegated to storage_guards: sole writer guest/verify.sh+runtime-checks.py
for selfcontained observed-read integration, strict12-field preboot state, independent RO
readback, tool in existing exact GRUB update and useful regressions. Root PLAN/evidence and
monitoring independent read-only proof review; all final fresh gates still required.

Independent monitoring stage10 native review PASS:29 compact hashes/exact framed buffers,
pinned checker positive1data+1EOF versus upperzero, fourgroundtruth stages/effectivefeatures
and nativecontrol completeness all agree. No installed-system acceptance inferred.

Production integration first test boundary: embedded proven observer/consumer, strict12-field
preboot identity, private namespace/RO readback/tracer cleanup and exact GRUB update-tool route
implemented by storage_guards. Initial full runtime run has28 old8-field fixture mismatches,
no unrelated failure reported; fixtures and meaningful helper/cleanup regressions in progress.
Stable independent review/fullsource/build/root/installed child gates not yet executed.

Production integration focused acceptance:92 runtime tests PASS15.782s plus syntax/ShellCheck/
diff. Original30 guard negatives retain their precise finite reasons; producer4f413093 and
reader2c95755d unchanged. Independent stable review accepted integration except overly broad
second-GRUB tool route; root also bounded independent marker read before cat. Actual-helper
RED6failures→GREEN2 and final92tests PASS confirm exact snapshot-only tool route and unsafe/
oversized/failed marker metadata rejection before reading. Frozen guest5fee2674/tests38dfc4e7;
focused rereview and fullsource pending, installed new candidate NOT_TESTED. No fresh BPF
experiment or source-setting change; next final clean candidate/build/root/child acceptance.

Final focused stable review PASS (monitoring) and full source23 EXIT0/native session74362:
`PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`, log SHA256
acc6b52196776d2774b7598af5c271dc31105eacf181d3d8344de6244623dd12, full namespace10/
signer/14+18/deferrednone and all required source tests. Exact five authorized paths are ready
for local candidate commit; clean tree-bound source/build/five real-root gates follow before
new protected-main PR delivery. Historical fourth child stays7PASS/2FAIL/public1.0.5 unchanged.


Clean candidate27b4a5f passed source24 (log caa62924), fresh unsigned build and
independent verification (receipt29b01ce0), and all five actual release-host root gates
(receipt89816e1; exact owned cleanup ed3d54e2). These results remain bound to that
candidate; they do not prove installed release acceptance. PR55 required Source checks
run37187167926 then FAILED only lifecycle fixture ownership: CI runtime directory UID1001
versus hardcoded requested UID1000 produced correct `early_sentinel=unknown`.
Production verifier unchanged. Focused fixture correction uses actual UID/GID, models CI
UID1001 and rejects foreign ownership for both absent/present sentinels; RED→GREEN and
94 runtime tests PASS. Independent narrow monitoring review PASS for all four actual
owner/presence cases, stable runtime886edcd6/guest5fee2674. New exact source/build/five root
gates precede updating the same PR55; no unchanged CI retry or acceptance transfer.
QA-01/GATE-01/RELEASE-01 remain open; fourth child7PASS/2FAIL and immutable public1.0.5
remain historical. Next prepared build t3c0kny3/root bv6a7sh0 are not executed yet.


Fixture correction accepted in clean c3e110df/tree3cdc8e42/canonical77e77d34:
source26 native0, 94runtime/full10/signer14+18/deferrednone, log4e395848;
fresh build+independent read-only verification native0, receipt696cd2c6; all five actual
release-host root gates native0/ordered0, independent monitoring review PASS,
receipt1d38bd9f before exact8 owned-heavy cleanup; four launcher socket paths already absent, final901f7be8.
Receipt collector first checked terminal marker in wrong console channel (exit1/no receipt);
correct strict serial channel + streaming1MiB hashes accepted without repeating gates.
PR55 corrected required CI37188447011 SUCCESS (previous failed37187167926 retained),
protected squash merged 2026-10-04T08:20:54Z; same checkout main fast-forward to870f89655e5,
exact tree/mode-byte identity retained, fresh main CI37188622423 SUCCESS. PR candidate is
preserved locally/remotely; no protected-main bypass or foreign work loss.

Fifth immutable release attempt37188752155 executing: main870f89655e5 → childaaff86062546,
treee0a6725e8c3e/canonicalf1a2232ff7ad/version1.0.6. Actual source bundle requires that exact
main, hashcfd6d892 verified without object import. Prepare/build/readback/snapshot native
jobs SUCCESS; public Phase-A exact14/signed12/schema2/DB six payloads/deterministic child
verification native0 and independent review PASS, receiptf0c444b9. All nine hosted real VM
scenarios running with accepted October ISO; results NOT_ACCEPTED yet. Final18/tag/Pages/
public readback/public VM remain pending. No historical PASS transferred to new child;
QA-01/GATE-01/RELEASE-01 remain IN_PROGRESS and the full15-ID scope is unchanged.


Fifth run37188752155 terminal FAILURE/nativewatch1: all9 authenticated results retained;
seven graphical variants FAIL0assertions at install-archiso with actualinstallerexit1,
Minimal and dualboot install complete then FAIL3assertions at firstboot. Finalization/
publication skipped; no1.0.6 tag/assets, immutable1.0.5 unchanged. Independent install-entry
comparison confirms unchanged installer/bootstrap/workflow/ISO/packages/trust; new verifier
runs only after installation. Compact archives discard ordinary installer error details,
so seven installer causes remain UNKNOWN and snapshot/Shell were not reached there.
Direct Minimal job evidence shows qga-client87 correlated-response timeout30s before guest
verification starts; new script210267B vs141202B. Actual-client partialsync/requestwrite
reproducer RED2TimeoutErrors→GREEN after both sends use sendall,96runtimePASS and narrow
independent review PASS; peer/owner/socket identity/caps/timeout unchanged. This confirms
transport mechanism, not yet native VM recovery or installer-failure cause.
Root typed failure capture privately classifies bounded rawlogs into fixedclass/line/status
before scrub/compaction; no commands/paths/package values. Six meaningful actual-helper/
scrubber/compactor fixtures PASS after rejecting rawGUEST_FAIL command retention; foreign
symlink contents preserved outside owned run, oversize rejected. Narrow review/fullsource
and committed diagnostic slice pending; next focused localreal Stock diagnostic uses the
previous accepted public1.0.5/October inputs to examine changed upstream premise, without
relabeling ISO/product acceptance or retrying the unchanged hosted matrix.

Narrow diagnostic review found atime-only false rejection: actual parser RED→GREEN now
compares identity/content metadata excluding access time, retaining nanosecond mtime/ctime
negatives. Six compaction cases + three metadata cases PASS. Source27 first run FAIL at
old static compact fixture expecting rawGUEST_FAIL retention; no source PASS claimed.
Static regression now requires typed runtime failure preservation, rejects raw command
output and still excludes quoted QGA request text; fresh source checks pending.

Focused final monitoring review PASS after atime correction, frozen runa99990f9/harness96a3cddd/static5282f2a4.
Source28 `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` native0/session67186,
log SHA256 8d99b2bd68ae62df695b5964230b071a4c560e451db70f7a54172e0475f985d8,96runtime and full repository10/signer14+18/deferrednone.
Local diagnostic commit1952675995f4568ef38a6a0676f6d7341f5f83f9/treefb00b468739abba1be078b2f6bd6223ce2dacc78
passed clean source29/native0/session82938 (log SHA25652e577aa8e51c5a189011efdba1ab23973a42ac6c4d86a273e6382dc945db8c0).
It owns exactly PLAN/static/harness/qga-client/run/runtime; installer/bootstrap/pins/trust/workflow unchanged.
Actual public1.0.5 Stock diagnostic/native0/session82922 passed20 assertions including full210267B
QGA transport, genuine GDM password/Wayland/lock/unlock/update/reboot; result SHA256
91ba844bde08edafe299d349c1b6e4b19553a1ce1a3369b3d89a372c303f7998.
This examined changed upstream premises, without ISO reacceptance or new-child acceptance.
A bounded installation-only diagnostic used exact fifth Phase-A childaaff86062546/installer278965467a7e
and approved October ISO with readonly payload; no new hosted pipeline or source copy.
First generated-runner attempt failed identity alphabet before VM creation (native1); actual
full emitter RED→GREEN preserves unsafe-input rejection and prior logs. Second attempt/session47299
completed real installation (install_outcome0 and exact completion status0). Wrapper/native1 arose
at diagnostic cleanup; image check has no errors, recorded QEMU/bridge absent and exact heavy/raw/socket
resources absent. Independent monitoring confirmed these facts, but no overall PASS is transferred.
Actual cleanup/canonical-wait regression with owned children/Unix sockets/native qemu-img reproduced
RED native1 for already-unlinked sockets, then GREEN5 cases after accepting absence only once exact
writers are quiescent. Replacement/symlink/unhealthy negatives remain; generated-runner-only fix and
historical native1 retained. No repeated installation: the child installer itself completed; hosted
seven-variant causes remain unreproduced. Next fresh source/build/five-root gates and protected-main
delivery of the evidenced QGA fix/typed diagnostics; nine-variant/final18/public acceptance remains open.

Sixth delivery PR56 merged2026-10-04T10:12:14Z to maind22bf5791fc22e556f22b1dfc661c2f4efa69fdc,
with accepted211892bd/tree2c9d422a/canonicalc0b714fb. Clean source30 PASS/native0/session34757
(log4f129aaa84b863a6f986b9672336c3bad5d4e9acc1940cbfba02681624760e9c), fresh build+verify0/0/session68751,
five real-root gates0/session60207 before/after exactsource; compactreceipt44d3667cdd6d6eebeb494c2c328546988a552c2ce75ab5bf600b134959b3a2cb.
PRSourceCI37194359454 and mainCI37194605119 SUCCESS; branch retained, samecheckoutmainFFclean.
Fresh run37194737694 child07f377ba21abff27a71b6f2110f9998d292c3e51/tree7b67274e1c6379c6b3ac66bf2163aee05241a239,
canonical0913150db5170208db4db2bee9aaa345a46503c02582479ccea320d2085f9eeb; sourceartifact independentlybound.
Prepare/build/readback/snapshot nativeSUCCESS; exact14 Phase-A independentproof accepted receipt
9b5b0b2fe40becf098a7764d0caca0a4fe48c952fa0be301d2bf09173435801f. Actual MinimalPASS14/dualbootPASS17,
Stockext4PASS21/StockBtrfssystemdbootPASS21,StockLUKSsystemdbootPASS21/GRUBPASS22,MarbleStockGDMPASS17
andMarbleGDMPASS26 authenticate this child/ISO/harness: all8PASS andStockGRUBFAIL20. Seven earlier
installer failures not reproduced; both QGA timeouts and priorShellfailure recovered inthisnative matrix.
Run37194737694 terminalFAIL/nativewatch1; finalization/publication skipped, no new1.0.6 release.
StockBtrfsGRUBFAIL20 during snapshot preparation (caller4233), before snapshot reboot or BPF observation;
entry selection and owned selector passed. No final18/public acceptance or release claim.
QA-01 focused state-storage decision: keep /boot shared state and strict root/regular/nlink1/12-field/FD
stability guards; accept0600 normally, or exactly0700 only with read-only FAT_IOCTL_GET_ATTRIBUTES proof
on the same FD. No general mode relaxation, filesystem remount, source pins or signing changes.
Reason: installer FAT fmask0077 synthesizes0700; the actual loader rejects that as ownership, while600passes.
Native failing state metadata absent, so first require bounded real disposable VFAT RED→GREEN regression,
including POSIX700/ioctl failure/foreign-owner/unsafe-mode/malformed/stability negatives. Apply same policy
to early runtime guard and full loader, with fixed finite preboot diagnostic stages; preserve all37 reasons.
Root and independent monitoring accepted this narrow design; source implementation waits for real FAT proof.
Real FAT fixture attempt1 native1/session38236 stopped before mkfs: virtio serial sysfs path absent,
not a product/FAT verdict. Exact owned VM stopped, image health PASS; original result retained.
Independent fixture review required finite create/health deadlines, corrected before GO; total600s,
offline2CPU/2GiB/256MiB target. Correct serial-path fixture regression then fresh bounded attempt.

Real FAT attempt2/session59266 executed all11 actual guest cases: FAT0700/oldloaderRED/proposedFDGREEN,
POSIX600PASS and POSIX700/ioctl-error/foreign-owner/unsafe-mode/hardlink/changedmetadata/malformedstate
reject. Guest COMPLETE11/EXIT0, exactPIDgone/imagehealthPASS, independent monitoring accepted. Native
wrapper1 retained: firstcase followed UEFI terminal reset on same line, so startswithcount10. Bound
offline readback native0 +14regressionsPASS; receipt7ad673be0bbf82d02cdc3f24f4cd81bf1377835a2c37ba98a76a220bcdf6469e.
No thirdVM: both attempts exactownedheavy cleanup native0; compactfailed/proof evidence retained.
This proves the guest prototype mechanism, not installed snapshot acceptance; implement narrow shared
FD policy now, retaining all37 runtime reasons and fresh downstream candidate/release gates.

Focused source correction: common same-FD metadata policy now serves full state loader and early
metadata-only guard; 0600 normal, exactly0700 only successful read-only FAT ioctl. UID0/regular/nlink1,
bounded4097 read/exact12 fields/FDidentity remain; full validation stays at the original runtime stage.
Final UUID/PARTUUID probes, state-validation and grub-reboot explicitly stop before PASS and emit only
fixed preboot steps. Actual loader/policy/CLI/failure sequencing regressions RED→GREEN; native runtime
100PASS/session44123 and affected Bash/ShellCheck/diff0/session12517. Root diagnostic compaction
RED1→GREEN0 and independent monitoring PASS; raw/suffix/credential negatives retained. Stable final
guest/runtime review PASS (monitoring actual4targeted + failure reasons/syntax/ShellCheck/diff);
clean source/build/five-root/nextchild9VM acceptance remains pending.

Seventh delivery PR57 merged to mainb49165f9499c7b395119feb8b0039d3d314d2437,
treea19bef424f9adb0be6910590cf1a495bc3c23fad/canonical53317d952698eb30aa7cc785e86a174456c308b6c9e3ccdbdd703a1453502a74.
Clean source31 native0/session11964 (logf857c420854ac3f93b5ed29d7640a1d8a30c2852aa6fe38a249c9a9d190489fa),
fresh build/verify0/session66583 and five real-root gates0/session72672 accepted;
exact owned heavy resources removed after health/quiescence, compact evidence retained.
PR CI37199115141/mainCI37199343777 SUCCESS; same checkout returned main FF.
Fresh configured run37199471699 child4514c3a949bc16d869a55101227365c0a38e34d6,
treecd75164a593588a38c785cbc9e04b72cf28ccc60/canonical5b6b364a3321e41f50bd52ff293b55e08ac681bd4219a846d4f20b629d2c89c6.
Actual source graph proof accepted after correcting verifier ordering; first native0 receipt
retained as superseded, corrected receipt8f646b01e96e758225ee6c7fb0a243de1112c7ebbc6d3e69784a69f2a3c76317.
Signed Phase-A14 accepted, receipt6bc7d466539ce7a06c8bfc321176028096ce5112c0ccda9d0783b19b82ba7ec2.
All nine authenticated native results collected: eight PASS and StockBtrfsGRUB FAIL20 at
snapshot-boot; final Marble PASS26. Run terminal FAILURE/nativewatch1/session33933;
finalization, publication and public readback skipped. FAT preparation recovered and actual
snapshot boot/backing/kernel/EFI/package/network guards passed before snapshot-prelogin
reason=failed-units. Failed service identity was not retained, so the remount-fs/overlay
hypothesis is not yet a native cause. Preserve zero-failed-units acceptance; add checked,
finite service diagnostics and reproduce the lifecycle before any product correction.
No final18/public1.0.6 acceptance or completion claim; QA-01/GATE-01/RELEASE-01 remain open.

Snapshot failed-unit readback now checks native query status: actual nonzero/empty query
reproduced an old false PASS and now rejects. Bounded5s/4096B queries emit only counts,
five fixed public unit enums and finite Result/code/status; unknown names, descriptions
and errors are discarded. Zero-failed-unit acceptance and all37 reasons remain intact.
Worker runtime104PASS/native0/session96207, affected syntax/ShellCheck/diff0/session30689;
root actualhelper3PASS after correcting one mistyped test selection (native1 retained).
Independent monitoring source review PASS; host compaction RED1→GREEN0, storage_guards
actualproducer review PASS. Committed fixture now retains full summary and per-unit row
and rejects raw/lookalike/credential logs. This is diagnostics/query correction only.
Bounded offline remount fixture attempt1/native1/session61288 reached normalBtrfs remounter
exit0, but transient unit wrapper timed out: --wait plus RemainAfterExit=yes waits for
deactivation although native unit is success/active/main0. Overlay not reached; no cause
or fixture PASS claimed. ExactPID absent/imagehealthy/no-visible-consumers; owned heavy
cleanup native0, compact receipt/log retained. Correct finite nonblocking unit readback
and LF/CRLF parsing before a new attempt. Attempt2/native1/session8358 passed normal
CLI/unit but stopped at overlay setup before native exec; no overlay verdict transferred.

Historical diagnostics candidate: commitc54613c67f4404f644ebcab996f0c0c142cde2a9,
tree0c5287e35a403cfdd3d9835c5d997109a012f725 on local main, clean/ahead1, not pushed.
Source32 native0/session42275 (logbda7d77c4ef488135a46f45067078682063224cc60e54a0e508bdba0f1d488d2),
104runtime/full10/signer14+18/deferrednone PASS. This corrects failed-query false PASS and
retains typed diagnostics; no new product/build/installed-acceptance claim.
Installed diagnostic attempt1/native1/session69047 stopped before installer because fixture
serial/model violated canonical bootstrap; exact dispatch regression corrected,30checksPASS.
Attempt2/native1/session67697 used exact seventh-child installer and reviewed c546 harness:
install/normalprelogin/full signed update/reboot/snapshotprepare PASS; snapshot-prelogin
query success,count1,unknown0,unit=systemd-remount-fs,result=exit-code,code=exited,status1.
No snapshotdesktop/GDMlogin PASS; healthy/quiescent native0, heavy retained for bounded review.
Actual semantic attempt3/native0/session22189 with verified top-mounted overlay and fixed
nonblocking lifecycle: normal Btrfs CLI0/unit success active main0; same Btrfs fstab on
overlay CLI1/unit exit-code failed main1. Four-case receipt accepted, imagehealthy/quiescent;
this reproduces remount root cause, not installed correction acceptance. Prior attempts retained.
Focused correction: Btrfs+GRUB-only isolated Python ExecStartPre, unchanged vendor
ExecStart/ordering. Normal Btrfs is an exact no-op. The helper requires the expected
systemd overlay topology and unique volatile=overlay argument; retained root/etc/fstab
mount identities, root ownership, bounded bytes and immediate pre-rename recheck. It
atomically changes only the volatile-upper root row, preserving supported generic/security
options and all nonroot bytes; unknown options/ambiguous roots/unsafe files fail closed.
No config backup or persistent lower rewrite. Native snapshot lower proof remains required.
Transform RED missing emitter then12GREEN; independent topology RED14tests1failure then
17GREEN including bounded cmdline, changed mounts/files, partial writes, fsync/rename and
exact temporary cleanup. Independent integration review PASS. Actual install/routing
regressions RED missing helper and BtrfsGRUB config-only branch then7GREEN; three other
filesystem/bootloader combinations never activate helper/Python, config failure stops.
Source-suite hook and architecture prose updated; Bash/ShellCheck/diff/29doc/portability
PASS. Installer functions and24boundary tests native0/session1402; zero-failed-unit gate
and all37 runtime reasons unchanged.
Native same-helper prototype attempt1/native1/session78672 (frozen emitteda5a30286b828f07a549fb587d5796a04d6abc8a01b909683847c3fa43c3df85d):
six native cases reached. Normal CLI/unit0; originaloverlay CLI/unit1; adaptedoverlay
CLI/unit0 with unchanged vendor remounter, nonroot bytes/lowerfstabSHA/RO property preserved.
Secure setup failed BEFOREhelper at target-only remount32; exact native cause unknown.
A fixture-fstab libmount dry-run reproduces lookup/replay, but does not prove guest errno;
not an eight-case PASS. Normal/adapted claims are mechanism-only, not installed boot ordering.
Changed fixture now uses explicit overlay source/type/target; actual libmount dry-run
RED oldfstab replay / GREEN fstabskip,16offline tests PASS. Next native8-case acceptance
includes nodev/nosuid/noexec preservation with unchanged production helper/checker.
Prototype attempt2/native1/session89960 did not enter the payload: fixed50s HMP dispatch
arrived in UEFI editor (zero REMOUNT markers). Root stopped exact owned launcher;
quiescent/imagehealthy, no helper/security verdict. A new bounded handoff plus actual
guest READY barrier must precede payload; no generic escape stripping or weakened parser.
Actual firmware geometry varies (firstbyte mismatch1286, row25 versus24), so strict
historical7302-byte-prefix preparation was stopped beforeGO. Changed semantic-only probe
uses exact kernel/initrd from approved ISO and its canonicalargs plus serial/status output;
finite VGAgetty-start witness and actual nonce-bound guestREADY precede payload. Captured
complete preREADY framing is bounded/hash-bound perrun, native closure remains strict;
UEFI/installed boot ordering still require fresh productionchild acceptance.
Directboot attempt3/native1/session59271 reached colored Getty but plain-only witness
withheld all probes; attempt4/native1/session92167 accepted that exact witness, yet three
nonce probes produced noREADY (113B firmware framing only), zero payload/nativecases.
Working source33: PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh native0/session37572,
logSHAed45ec902cffe9da0163d3dc57e59fb2e52b42daa2ea4bc0009afc0204273ef6; all required checks/full10/signer14+18/deferrednone.
Dirty workingtree result; clean candidate commit/tree and downstream gates remain pending.
Both quiescent/imagehealthy; no product verdict. Independent read-only check found
byte-identical successful HMP helper and supported READY characters. Serial override
creates separate getty; VGA autologin completion/focus remains unknown. Next finite
probe restores canonical ISO arguments, bounded boot wait and actual nonceREADY before
payload; production helper/security/native closure unchanged.
Prior semantic/native attempts preserved; closed heavy resources removed exactly after
health/quiescence/PID/path/consumer checks. Installed diagnostic heavy remains retained.
Root owns source/registry and final acceptance; storage prepares fresh generated build/root
recipes without binding or running another VM. Native attempt5/native0/session24354: canonicalISO args and actual nonceREADY reached.
Eight CLI/unit cases normal0, originaloverlay1, adapted0, secure0; unchanged native
remounter and emitteda5 helper, nodev/nosuid/noexec/nonroot bytes/lowerfstabSHA and RO
property verified. Receipt79cdb96e014c181283052514cff253e868d6c93d26acfb1b045d43f8dae573c2;
quiescent/imagehealthy. Independent monitoring actual hash/parser/helper/native/lower/security
review PASS, no material finding. Semantic fixture/synthetic cmdline only, installed boot
ordering remains required. Optional VGA showed tty1 automatic root shell; late second
capture failed after the completed VM removed its socket, separate diagnostic failure.
After accepted full nativeproof: fresh clean source,
build/verify/five-root gates, ready authorized PR/main delivery, new configured child9VM,
final18/public gates. No mask/reset/failed-unit exemption, source-pin/signing change or
repeated closed FAT/BPF proof. Full15-ID scope and QA-01/GATE-01/RELEASE-01 remain open;
no final18/public1.0.6/completion claim.

Current continuation: same physical checkout main9291d995f0d7857d493917c330a2714e4f904bd1,
tree586fc2d8bf25dfddc33aea03813ce44add763466, origin equal, accepted PR58 squash/mainFF.
Clean e310 candidate source34/native0/session85155 logb91729a3b35265adda368968f0caadfb2a32c23a32c57035a7b8a54e59af7110;
fresh six-package build/separateverify0/session74206 and five-realroot0/session77494,
independent reviews PASS. Owned transient heavy removed exactly, compact proof retained.
MainCI37210132492 passed; eighth configuredrelease37210253900 child1079a9f58a2a4cc23db4744484e7a3050f1764af,
tree8eb507bc626764b47768158784469825d5559450, canonical331ca490c3f35cbf6e84bd99241b1c4275b57d779551f7f4b15405be0b470007,
version1.0.6 UNPUBLISHED. Actual sourcegraph readback0/session17203 plus independent review;
main188 plus releaseorigin1 = child189 (oldfixed188 diagnostic failed first, history retained).
PhaseA14 native0/session74032, proofd2fd6039a0f6c922924808a1d9d3143c77663fce404f1aea6377adb7bded7e83,
independent signatures/trust/source/package review PASS. All9 actualnative VM results bound
and collected0/session96962: Minimal14,dual17,Stockext4 21,StockBtrfssystemd21,StockLUKSsystemd21,
StockLUKSGRUB22,MarbleStockGDM17,MarbleGDM26,plainStockBtrfsGRUB23. The latter proves real
filesystem snapshot boot/desktop/return after remount correction. LUKSGRUB22 is normal
installation/login/update/reboot only; repository snapshotVerification is not filesystem boot.
Terminal releaseFAIL at finalizejob111464818903, before secret handoff; tag/release/Pages/public
skipped, original public1.0.5 unchanged. Root reproduced actual full public snapshot_contract
and three directory_run inputs: MinimalPASS14,StockPASS22,MarbleFAIL QEMU assertion closure differs.
Independent diagnosis: actual producer emits gdm-helper-failure-honest and gdm-explicit-deactivation
after second-gdm-login-wayland; strict consumer EXPECTED_ASSERTIONS omits them (24 versus26).
Source correction must retain all26 ordered checks and missing/reordered/unknown/failure rejection.
storage_guards owns only acceptance-manifest.py and actions-release-checks.py; root owns this
checkpoint/integration/final acceptance. Next stable correction/public-input replay/regression,
fresh source/build/five-root gates, ready PR/new configuredchild/all9/final18/public; old run
not retried with changed inputs and no priorPASS transferred. All15 originalIDs remain in scope.
Final record updates are local main docs/validation/checkpoint; a separate remote documentation
publication gate is not in the agreed plan. Do not trigger an unsolicited second installer release
merely to publish final checkpoint prose; report the remote-doc limitation honestly.
Focused finalizer correction frozen: production adds only the two required IDs in the
real producer order. Actual run_marble_acceptance + record_assertion under bounded VM/QGA
stubs emits26 (never derived from consumer EXPECTED list); real assertion-validation AST
statements RED1 old24 → GREEN0 new26. Missing either/both, reordered pair, unknownextra
and FAILstatus reject. Full17 actions-release checks native0; independent stable review PASS.
Root full authentic public three-directory replay RED1 Marble closure → GREEN0 all14/22/26,
no private handoff/signing/final18 claim. Next commit exactthree authorized paths, bind fresh
clean source35/build/five-realroot gates, PR/newconfiguredchild; predecessor9PASS remains historical.
