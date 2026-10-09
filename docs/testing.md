# Testing

A test result is valid only for the exact source tree and inputs that produced it. Use one of these
statuses: `EXECUTED_PASS`, `EXECUTED_FAIL`, `REVIEWED_ONLY`, `NOT_RUN_ENVIRONMENT` or
`NOT_APPLICABLE`.

## Local runner environment

All 18 job definitions in the five workflows select
`[self-hosted, Linux, X64, ubuntu-actions, arch-linux]`; their registered runner
is `ubuntu-actions-arch-linux`.
The provisioned runner uses the existing Ubuntu 26.04 VM with 4 vCPU and 12 GiB
guest RAM. Memory is allocated on demand, and virtio free-page reporting returns
free guest pages to the host. A real 2 GiB allocation/release probe changed host
RSS from 2250 to 4302 to 2366 MiB. This is a bounded reclamation measurement;
Linux page caches can remain resident, and idle memory need not fall to zero.
The QEMU matrix runs one scenario at a time. Desktop scenarios still require
8 GiB available guest memory and 32 GiB free disk at their actual preflight.

Host provisioning supplies QEMU/KVM, OVMF, genisoimage, jq, GnuPG, zstd, OpenSSL
and libarchive-tools. The runner belongs to `kvm`; workflows neither install
host packages nor widen device permissions or remove shared SDK/Docker data.
Packages inside the pinned job containers are installed by those containers.
The `arch-linux-ci` AppArmor profile permits user namespaces. Source/package
containers use `--security-opt apparmor=arch-linux-ci`,
`--security-opt seccomp=unconfined` and `--security-opt systempaths=unconfined`.
The last option permits the nested namespace's `/proc` mount; default Docker
masked paths blocked it in the actual pinned Ubuntu image. The full namespace
fixtures must pass without hosted deferral. Signing namespace preparation only probes this capability and never changes a host-global sysctl.

Root-owned job hooks clean only this runner's fixed workspace and job temporary
paths, rejecting symlinked ancestors and active mounts/containers. Runner
credentials and tool cache are outside these cleanup paths. The project has a
dedicated rootful Docker daemon; other projects retain their rootless daemons.
Rootful Docker grants guest-root authority, so these accounts are not an isolation
boundary between projects. External fork PR workflows require maintainer approval
after code review (`all_external_contributors`). This persistent shared setup
does not provide a fresh VM for each job.

Source preparation, validation and canonical readback explicitly set `umask 022`
in their command shells. The shared runner's `docker exec` started
with `0000`; Git index refresh can otherwise introduce group/other write access
and fail the protected canonical-source checks. Preserve executable bits and
normal source modes; do not solve a mode failure by weakening those checks or
making the private project home public. The provisioned job hooks are executable
`.sh` files.
Do not add workflow-wide deletion of SDKs, Docker images, guest caches or arbitrary
workspace paths. The hooks remove only the configured per-project workspace and
job temporary paths after job containers stop and their boundaries are checked;
they preserve the private project home, runner credentials and tool cache,
other projects and symlink targets outside the owned paths.

Migration acceptance on 2026-10-09:

| Check | Exact source | Result |
| --- | --- | --- |
| [PR Source CI 37850459758](https://github.com/snaplyze/arch-linux/actions/runs/37850459758) | `2825b37b28a57bdb77933c7328e2c86ce487f452` | PASS on `ubuntu-actions-arch-linux` |
| [Manually dispatched main CI 37850869082](https://github.com/snaplyze/arch-linux/actions/runs/37850869082) | `7430a0b3e2b04ad66bd36a215eb1e494a404962a` | PASS on the same runner after [PR #61](https://github.com/snaplyze/arch-linux/pull/61) merged |

A nested KVM probe initialized four CPUs and an 8 GiB guest with acceleration
reported enabled. That covers startup only. Full installer scenarios, production
signing, release and public readback have not run on this runner. Source CI success
also does not mean that all 18 job definitions have executed. Later edits require
new results bound to their own exact source; migration evidence does not transfer.

## Required source suite

```bash
bash tests/source-tests.sh
```

The package-migration checks require `vercmp`. On Ubuntu 24.04 it is supplied by
`makepkg`; the CI dependency setup installs that package explicitly.

It executes:

- Bash syntax and installer version smoke;
- release-bootstrap regression fixtures;
- static installer and trust-policy checks;
- installer function behavior, including disk/destructive and AUR boundaries;
- Marble install, upgrade, remove, reinstall and fallback simulation;
- package metadata and source pin checks;
- documentation/local-link, portability and secret scans;
- agent contract and advisory-maintenance checks;
- signed-repository positive fixtures, negative signatures and malicious archive fixtures;
- ShellCheck.

Individual commands are listed in [AGENTS.md](../AGENTS.md). Static reading must be reported as
`REVIEWED_ONLY`, never as an executed test.
The maintained suite includes actual-executor/idle-probe failure regressions for F-01/F-02,
reserved-account tests for F-11, faithful signed database/package semantic negatives for F-12,
and actual exit-handler fixtures for F-13. Predicate or literal assertions alone do not prove
a whole executor. The earlier passing suite and documentary audit are historical; the final
integrated suite and runtime acceptance for 1.0.6 are separately bound in [validation](validation.md#verified-release-106--2026-10-04). Later changes require fresh applicable checks.
Exit-handler late-writer retention now uses an isolated marker closure with a maintained
synchronized regression; independent source review and actual VM error acceptance remain separate.

## Clean Arch package build

The required release build runs once in a clean Arch environment under a non-root temporary builder:

```bash
repository/build-packages.sh "$ARTIFACT_DIR/unsigned"
repository/verify-unsigned-build.sh "$ARTIFACT_DIR/unsigned"
```

For a reproducibility comparison, give both independent disposable build environments the same
absolute `WORK_DIR` (for example, a missing `build-work` directory below each temporary builder's
home). The builder refuses an existing workspace and removes its own workspace on exit. Without
this setting, random temporary paths enter makepkg's `.BUILDINFO` and make archive hashes differ
even when installed payloads are identical.

The scheduled A+B comparison is advisory:

```bash
repository/compare-package-builds.sh "$ARTIFACT_DIR/build-a" "$ARTIFACT_DIR/build-b"
```

If no genuine clean Arch environment with `makepkg` is available, report
`NOT_RUN_ENVIRONMENT`; do not replace it with metadata inspection.

## Repository signatures

`bash tests/repository-checks.sh` uses an ephemeral test key only. Repository and package manifests
remain schema 2. The test's release-host result is the separate schema-1 full-namespace,
ten-scenario, signer-passed, no-deferral acceptance marker; it also proves repository negatives plus
exact-14 Phase-A and exact-18 finalized closures. Release-host acceptance additionally runs
`bash tests/repository-checks.sh --require-full-namespace`, the exact empty-derived root
`tests/publication-root-check.sh` command from `AGENTS.md`, and ordinary plus privileged
`tests/keyring-rotation-checks.sh`. These fixtures do not constitute production signing.

## QEMU acceptance

Host provisioning installs `libarchive-tools`, which provides `bsdtar`. The staged
and public VM jobs check its availability without installing packages on the
persistent runner. The harness uses it to inspect
signed package metadata during legacy Marble migration.

Do not report QEMU PASS unless all of these are real and fresh:

- `qemu-system-x86_64`;
- the accepted Arch ISO;
- a new qcow2 disk per scenario;
- an independent OVMF VARS copy per scenario;
- captured installer/repository identities and scenario evidence.

Required scenarios are Minimal TTY, Stock GNOME, and Marble plus separate Marble GDM. A
release acceptance run uses the exact combinations Minimal/ext4/systemd-boot,
Stock/Btrfs/LUKS2/GRUB and Marble/Btrfs/LUKS2/systemd-boot. Every run is a fresh install with KVM,
a new qcow2 and an independent OVMF VARS copy; all three consume one exact independently verified
production-signed snapshot. Real login, lock/unlock, `pacman -Syu`, reboot, repeated login, package
integrity, zero failed units, clean shutdown and `qemu-img check` are mandatory. A representative
dual-boot path is a separate required supplemental acceptance case alongside the three core workflow
matrix entries. The release workflow makes all six complementary scenarios mandatory release
jobs and requires them before finalization; their evidence stays separate from the three core
signed verdicts. The nine-scenario workflow is deployed. Release 1.0.6 child7af2209 passed all nine scenarios against its exact signed snapshot and
October ISO, then finalized18 and immutable publication succeeded. The separate fresh public Marble/GDM VM passed19 assertions; exact outcomes and identities
are in [validation](validation.md).
Current acceptance remains tracked in
[QA-01 / RELEASE-01](PLAN.md#qa-01--behavioral-and-vm-coverage).
See [VM commands](../tests/vm/README.md).
Stock additionally checks Language/Formats, input layouts and terminal shortcuts. Every run retains
its input identities, a compact installer log, functional assertions, `qemu-img check` and a
structured PASS or FAIL. Screenshots are optional diagnostic aids: missing a frame or a slow capture
does not turn a successful installation into a product failure.

The runner performs actual GDM password input, verifies the resulting Wayland session and exercises
lock/unlock and the second login. QGA inspects the installed system but does not manufacture a login.
Minimal must reach its working TTY without a forced VT switch. There is no continuous recorder,
frame-timing threshold, pixel challenge or manual-review receipt. If a functional check fails,
investigate and fix the cause, add a regression check, and rerun the affected checks on the new inputs.
Keep source, package and actual VM results distinct.

The Stock Btrfs/GRUB snapshot check must prove that the marker read through the current overlay
came from the expected read-only snapshot on the accepted physical partition. A detached or
covered lower mount can disappear from pathname-based `findmnt` lookup; checking a separately
mounted snapshot alone does not prove the source of the overlay read. The verifier binds the
pre-reboot snapshot root ID, marker inode and physical-device numbers, uses a root-relative
single-file reader, and observes the underlying Btrfs read and stable entry/return identities.
The bounded observer fails on missing records, warnings, drops or incomplete cleanup. Its tool
is installed only in that disposable scenario's existing update transaction. The separate
read-only snapshot readback and all boot, partition, kernel, EFI and service checks remain
required. A disposable overlay mechanism test is not an installed snapshot-boot PASS; release 1.0.6 has executed the full installed-system check with 23 PASS assertions.
Its identity is recorded in [validation](validation.md); the mechanism-only predecessors remain historical.

## Marble GTK migration acceptance

The main staged Marble VM scenario requires the signed legacy release fixture recorded in
`tests/vm/legacy-marble-release.json`, in addition to the candidate snapshot. The host authenticates
both repositories before use. The guest records the fresh candidate package set, installs the
legacy profile and GTK3 theme from the strict signed repository, enters a real GDM session, then
runs `pacman -Syu` against the candidate and logs in again. It checks replacement of
`arch-linux-colloid-gtk3`, package-version parity, the packaged GTK4 hashes and active session CSS.
The pinned legacy profile supports GNOME 50 only. Its first session must have
Colloid on 50, or Adwaita with absent project alias/defaults on GNOME 51; other
majors are not qualified by this test. Real login, exact package versions and
absence of legacy GTK4 wrappers remain required before the update. The upgraded
session must activate the candidate profile normally.
This is a real package migration from legacy profile/theme state; it does not rerun the old
installer or claim coverage of every customization on an existing workstation.

The scenario also creates a new ordinary user, authenticates through GDM with virtual keyboard
input, checks automatic GTK4 activation, dismisses GNOME’s first-login Welcome dialog with Escape,
then verifies logout and returns to the original user. Light/dark application
startup checks run through the real GNOME user-manager environment and cover Nautilus, Ptyxis,
Settings and Boxes. Because Boxes is not part of the normal installer application set, the
acceptance guest provisions signed `extra/gnome-boxes` only for this smoke check; the installed
product defaults remain unchanged. Optional captures are diagnostic aids. Process startup alone
does not establish correct rendering. Inspect the captures or the live VM for styling defects
before claiming visual acceptance.

Existing lifecycle phases cover removal, reinstall and GDM fallback; source tests separately
exercise unsupported GTK/libadwaita fallback, edited CSS preservation and unrelated GTK settings.
Stock checks require absence of Colloid packages and project CSS imports. Keep these evidence
layers distinct and bind results to the exact candidate, legacy fixture and harness identities.
Until each check executes, report it as `NOT_RUN_ENVIRONMENT`; source tests and builds alone do
not establish migration, real-session or visual acceptance. See [VM commands](../tests/vm/README.md).

## GNOME 51 candidate upgrade acceptance

The GNOME 51 implementation adds a seventh package, `arch-linux-gnome-extensions`, for five curated
extensions in both Stock and Marble. The theme profile depends on this independent bundle.
The source suite checks archive bounds, metadata, payload inventories,
versioned AUR replacement metadata and conservative user-local migration. The explicit pinned-input
extension preparation check is separate:

```bash
python3 tests/profile-extension-checks.py --input-dir "$EXTENSION_INPUT_DIR"
```

`EXTENSION_INPUT_DIR` contains the reviewed archives named by
[extension-sources.json](../packages/arch-linux-gnome-extensions/extension-sources.json).
Without that option, the source-only run explicitly skips the actual upstream-payload build;
passing synthetic archive tests does not close the clean Arch package-build gate. Parser-only CSS
checks and mocked package/session tests do not establish GDM appearance or extension behavior.

Fresh-install acceptance must use the new installer for both GNOME options: each bootstraps the
strict signed project repository and installs the extension bundle. Minimal TTY must retain its
independence, and Stock must retain vendor appearance and absence of theme packages. The immutable
1.0.6 installer and historical six-package package-only mode cannot qualify this changed path.
A new full installer release is required; no historical fresh-install PASS transfers to it.

The main staged Marble scenario additionally requires independently hash-bound
[GNOME 51 upgrade inputs](../tests/vm/README.md): the signed 1.0.6 six-package
baseline, four actual pinned AUR builds and the exact local v6 archive. The release
workflow prepares them with a disposable non-root builder and passes its manifest
digest directly to the harness. Missing or changed inputs stop dispatch. The
guest proves the old installation before plain `pacman -Syu` and real GDM login,
then checks package replacement, settings, original-directory custody and eight
active extensions. The finalizer requires that assertion and the bound evidence.
This extends the GTK3 migration test with its platform-specific legacy baseline.
Enabled-state checks alone cannot establish extension behavior. The harness additionally requires real
keyboard/pointer actions after migration and after reboot: an otherwise unused
Dash extension shortcut must launch a disposable GTK app; Clipboard history must
restore and paste two synthetic values; No Screenshot Box must save the selected
area on pointer release, with a disabled-setting control requiring an explicit
capture action. The finalizer requires all six distinct behavior assertions and
compact receipts bound to the run, actual session and hashed probe source.
Missing observations, stale receipts and enabled-state-only results fail.
The app and captured guest images are temporary test outputs, not a visual
evidence framework. These checks leave Blur rendering, menu appearance and the
remaining behavioral checks below separate; they are not executed VM acceptance
until the exact signed candidate is actually run.

Real acceptance must bind the older installed state, new signed package set, GNOME/GTK/libadwaita
versions and harness inputs, then execute these checks in a disposable installation:

1. Establish old Stock and old Marble installations with the four replaced AUR extensions,
   preserving existing preferences. Include the older theme profile only for Marble and
   the exact installer-created No Screenshot Box v6 local tree. Record package versions,
   local payload hashes and the editable settings before the transaction.
2. For older Stock systems without the project repository, first perform reviewed authenticated
   trust setup and record its exact public inputs; pacman alone cannot discover an unconfigured
   repository. Update through the strict signed repository with normal `pacman -Syu`. Require replacement of
   the four AUR packages, higher package versions and package integrity. Verify that only the exact
   legacy local No Screenshot Box tree is retired; a separately modified copy must survive and
   report shadowing. Check that preferences and unrelated user files remain intact. Stock must
   receive the independent bundle without Colloid/Marble theme packages; Marble must retain its
   separate profile dependency.
3. Perform an actual GDM password login and inspect the Wayland user session. Exercise dock
   launch/window switching, Blur my Shell behavior, Just Perfection settings and restoration,
   Clipboard copy/history/paste, and No Screenshot Box selection/capture and disable behavior.
   Metadata support, an enabled flag or process startup alone is insufficient.
4. For Marble, check the GNOME 51 / GTK 4.24.x / libadwaita 1.10.x profile and separate opt-in GDM overlay,
   including appearance, GTK applications, lock/unlock, reboot and another password login.
   Repeat applicable GNOME 50 / GTK 4.22.x / libadwaita 1.9.x retention and unsupported-input
   fallback checks. GDM must match its exact reviewed platform/resource hashes and leave ordinary
   user Shell resources and environment unaffected.
5. Exercise package removal/reinstall and extension disable/restore paths, check journal/helper
   diagnostics and zero failed units, then cleanly shut down and check the VM disk.

Clipboard Indicator's selected PR and No Screenshot Box's project metadata port require these
functional checks specifically. Do not substitute autologin or a QGA-started session for password
login. Consult [validation](validation.md), the signed acceptance for the exact delivered release
and the [recovery checkpoint](PLAN.md#gnome-51-update-recovery--2026-10-09) for current
GDM/functionality/VM and publication results; report every unexecuted gate separately.
Historical release 1.0.6 results retain their own source and input identities.

## Release/public acceptance

The authorized release workflow signs only in its release-environment `snapshot` and `finalize`
jobs; all other CI jobs have no signing secret. Immutable Release creation, verified Pages deployment
and the final public VM readback are separate stages. Source or synthetic signature tests cannot be
promoted to those statuses. Staged QEMU consumes only the exact 14-file Phase-A closure. After three functional
PASS verdicts, launcher `finalize` preserves those 14 bytes and adds signed acceptance JSON/evidence
for exact 18; installer-release Pages deployment accepts only that final closure. Later
[package-only updates](../repository/README.md#package-only-updates) use a separately tagged,
verified 14-file snapshot with the installer unchanged. The delivered tooling resolves the local
[F-14](PLAN.md#review-findings) provenance incompatibility through its explicit package child;
external package signing/deployment and installed-system upgrade remain separately authorized
and NOT_TESTED. The final public VM uses only the tagged public bootstrap, immutable Release
installer/key assets and the public Pages repository; local installer, key, snapshot, CA and
repository bytes are forbidden from its payload. Inside the public guest, signed
`RELEASE-SHA256SUMS` binds the expected archive digest, the archive detached signature is verified,
and its manifest/signature must be byte-identical to Pages. The guest validates schema-2
commit/tree/installer/build identities, all manifest-listed Pages object sizes/hashes and all package/database
signatures before `PUBLIC_RELEASE_PAGES_BINDING_PASS` may be recorded.
