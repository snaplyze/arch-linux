# Project review and modernization implementation plan

Single work registry: every task ID, its status, dependencies and acceptance live here; dated
evidence and exact identities live in [validation](validation.md); rules live in
[AGENTS.md](../AGENTS.md). One fact, one place. Update the current-state record in place; keep
conclusions, not logs. The pre-cleanup text (about 2450 lines of attempt logs) remains in Git:
`git show bfb29bcecfb77fbd5999454f9ed3fe5d899b7202:docs/PLAN.md`.

Statuses: TODO, IN_PROGRESS, BLOCKED (with return condition), DONE. Check results use the
vocabulary in [validation](validation.md#status-discipline). Source PASS alone never closes a build,
VM or publication obligation; a PASS never transfers between trees, children or inputs.

## Current state — 2026-10-11

- **Main:** audit fixes branch `fix/audit-2026-10-10-tasks` on top of `c248eae`. Releases are paused at
  the owner's request (2026-10-10). Since REL-INTENT-01 a merge never starts a release; a release
  needs an explicit `release.yml` dispatch on `main` after its push CI passed.
- **Latest published release:** 1.0.6 (2026-10-04). 1.0.7 is unpublished; no 1.0.7 tag, asset or
  Pages change exists.
- **Open problem:** the 914ec4d Stock scenario failed at `extension-firstlogin-dash` with the
  cause NOT_PROVEN. DIAG-01 now makes the next failure record its phase, exit status and reason
  tokens; the old evidence cannot be re-read.
- **Pause scope:** the owner paused releases and asked that product development start only on a
  separate assignment. Nothing may be dispatched to `release.yml` until the owner resumes releases;
  DIAG-01 and local disposable-VM work may start as soon as the owner assigns development.
- **Next ready task:** the G51-02 local reproduction of the Stock failure (needs an owner
  development assignment; a release dispatch also needs the owner's resume). The 2026-10-10 audit
  queue is otherwise closed; LOOP-01 is measured on the next candidate.
- **CI:** mode `self-hosted` (contract record). All 16 runner jobs use the owner's Linux labels;
  two jobs only call reusable workflows. `ci.yml` skips fork PRs. No workflow is incompatible with
  this mode. If the runner or Actions is unavailable, continue with direct local commands and record
  Actions as pending, never as PASS.

## GNOME 51 update recovery — 2026-10-09

Owner goal: restore Marble on GNOME 51 through ordinary `pacman -Syu`, review current upstream,
keep repeatable desktop-update instructions and publish correct documentation in a new immutable
release. Do not update or restart the owner's workstation; the owner updates after publication.

| ID | Result and acceptance | Status | Depends on |
| --- | --- | --- | --- |
| G51-01 | Installed package/session state and upstream compatibility diagnosed against versions and sources | DONE | — |
| G51-02 | — | P1 | BLOCKED | Owner assignment/resume | See sequence above; DIAG-01 is done | Local reproduction of the Stock failure |
| G51-03 | Deterministic release documentation rendering with differing source/document/release versions (58 regressions; 914ec4d frozen 29-file inventory PASS) | DONE (source) | — |
| G51-04 | All affected Markdown reconciled with the released inputs and results | TODO | G51-02 publication |
| G51-05 | Independent review, affected checks and full source suite on the final candidate; package, VM and publication results recorded separately | TODO | G51-02 |

### Confirmed cause and delivery design

- Workstation diagnosis (not candidate acceptance): Shell/Mutter/GDM 51.0, GTK 4.24.1,
  libadwaita 1.10.0; installed Marble Shell/GDM 50.0.0-7/-8, profile 1.0.0-10 support only
  50/4.22/1.9, so GDM reports `stock` and the GTK4 helper `inactive`. Blur 72, Clipboard
  Indicator 71 and local No Screenshot Box 6 are `OUT OF DATE`; Dash to Dock 106 is `ERROR` on the
  removed `pointerWatcher.js` import ([porting guide](https://gjs.guide/extensions/upgrading/gnome-shell-51.html)).
  Preferences remain; recovery needs a fresh login, not a settings reset.
- The seventh package, `arch-linux-gnome-extensions`, owns five reviewed extensions and replaces
  the four old AUR owners, including epoch-bearing versions. Both graphical profiles use the strict
  signed repository; Minimal stays independent. Only the exact installer-created local No Screenshot
  Box tree moves outside discovery; its inodes and held-FD writes survive, and modified or unknown
  copies and preferences stay untouched.
- The candidate keeps GNOME 50 and adds 51/4.24/1.10 plus a separately pinned GNOME 51 GDM
  composition. Dash 109, Blur 74 and Just Perfection 37 have reviewed support; Clipboard Indicator
  uses the unmerged upstream port and No Screenshot Box a project metadata port. Upstream Marble
  stays 50.0.0. Unknown future versions fall back safely; each major needs fresh review, real
  acceptance and signed delivery.
- A full installer release is required: unchanged 1.0.6 installs the conflicting AUR owners.
  Existing Marble systems update through `pacman -Syu`; old Stock systems without this repository
  need a separate authenticated bootstrap. No unsigned fallback or trust change.
- The release renderer now renders bounded overview/bootstrap sections and promotes one nonempty
  Unreleased changelog entry; old tags and assets are never rewritten.

### Current checkpoint and remaining gates

Paused at the owner's request on 2026-10-10. Release run 38079578147 (child 914ec4d) is CANCELLED:
source, build, unsigned and signed readbacks, five root gates, Phase A and Minimal passed; Stock
FAILED at `extension-firstlogin-dash` after a real GDM password/Wayland login and 7/7 enabled
extensions; Marble and supplemental scenarios were cancelled without a verdict. The earlier child
106dcc0 (run 38073967896) failed Stock preparation on the ambient-root guard, fixed by PR91
(`5676fd8`). Identities and hashes: [validation](validation.md#unpublished-release-107--current-state).

Remaining sequence for G51-02 (after the owner resumes):

1. DIAG-01, then reproduce the Stock Dash failure locally on a disposable VM, correct it with a
   regression and pass the scenario locally before any release dispatch (rule in AGENTS.md).
2. On one fresh child, pass all nine staged scenarios. Stock and Marble need real GDM password
   login, lock/unlock, full `pacman -Syu` and another boot; every expected extension (seven Stock,
   eight Marble) in both real-session rounds; strict core consumers require 36 Stock and 43 Marble
   assertions. Marble must reproduce the installed 1.0.6/AUR layout failure, prove the plain full
   transaction, preserve preferences and local-copy inode custody, and verify Shell/GTK/icons and
   optional GDM. Keep fresh install, storage/bootloader/encryption, dual boot, separate GDM opt-in
   and clean shutdown/disk checks. Never autologin, QGA-started sessions or parser-only results.
   This qualifies recovery on GNOME 51, not a binary 50→51 upgrade.
3. Verify the final signed 18-asset closure, immutable tag, Pages and independent public readback,
   then public-only Marble VM acceptance. Only signed public delivery proves the `pacman -Syu` path.
4. G51-04: reconcile the tracked Markdown inventory; bootstrap pins stay 1.0.6 until verified
   publication; refresh Arch values only from verified evidence; no automatic pin promotion.
5. Recheck the workstation's migration eligibility without changing it; report the update and the
   fresh-login/reboot requirement; qualify the unsupported-version fallback.

Unproven history that must not be "fixed" by workaround: the daec8e9 Marble fresh-user login
failure (cause unproven; no logout fix, pin change, extension disablement or timeout workaround was
justified) and the a6887ee GTK receipt defect (reproduced and corrected).

## Registry

Open and recent tasks. Findings are in [Review findings](#review-findings).

| ID | Finding | Pri | Status | Depends on | Result and acceptance | Next step |
| --- | --- | --- | --- | --- | --- | --- |
| DIAG-01 | F-17 | P1 | DONE (source) | — | `qga_verify` records the failing guest phase, stem and exit status; the classifier reads that phase's own stderr (a fixture showed the old last-32 lexical slice dropping it; whether it did in the 914ec4d run is unproven) and emits allowlisted `[a-z0-9-]` `stage`/`reason`/`feature` rows; caps, no free text, password-row drop; rows retained in `scenario.log.gz`, `result.json` contract unchanged. Hypotheses: H1 confirmed, H2 refuted for ordering, H3 true but not the cause. Commit `4507338`; harness regressions. A real VM failure is NOT_TESTED | — |
| G51-02 | — | P1 | BLOCKED | DIAG-01 | See sequence above | After DIAG-01 |
| SAFE-04 | F-19 | P2 | DONE (source) | — | Identity helpers return 1 for structurally unidentifiable nodes (empty reader, zram-like disk) and 2 for operational probe failures; uniqueness stops on 2 and skips 1 (such a node cannot equal a valid identity). A naive "any failure rejects" would have refused every disk next to an empty card reader. Commit `71a8ede`; function-checks regressions. Live ISO NOT_TESTED | — |
| SIMPLIFY-01 | F-20 | P3 | DONE (source) | — | Cause confirmed: `papers` is required by `sushi` (gnome group), so its removal always failed silently. One `pacman -Qq` query and one `pacman -Rn` of the installed subset; real failures stop; provider lines never remove the provider; `papers` dropped. Commits `16ab695`, `0d0198c`. A slim Stock/Marble VM install is NOT_TESTED (runs in the next staged candidate) | — |
| SIMPLIFY-02 | F-21, F-22 | P3 | DONE (source) | — | One `lsblk -P` per node, one inventory per picker/validation pass, idle check against the selected disk's forward topology by device number (review caught a path-only match; fixed in `0d0198c`). Stubbed `lsblk` calls before→after at 2/8/32 disks: picker 49/415/5479→8/20/68, validation 125/395/1475→24/54/174, idle 6→1. Identity material unchanged (differential fixture against the frozen old helpers); first redundant destructive-target proof removed, the recheck and handle checks stay. Commit `57463af`. Live ISO NOT_TESTED | — |
| CI-PIN-01 | F-23 | P3 | DONE | — | All 18 `download-artifact` uses pin the reviewed v5.0.0 `634f93cb`; `maintenance.yml` used v8.0.1 under a v5.0.0 comment. Commit `db6dac0`. Next scheduled maintenance run NOT_TESTED | — |
| TEST-01 | F-24 | P3 | DONE | — | Full `tests/source-tests.sh`, interleaved A/B on the same workstation and background load, two rounds: 204.3/217.5 s at `c248eae` → 171.3/172.1 s. Service probe 33 s → about 7 s (optional `{callMs, waitMs}` may only shorten timeouts; 63 checks kept + 10); release-source-checks about 29 s → 13 s (19 exact reruns removed, baseline built once per variant; 39 distinct tests). Marker-contract tests are not duplicates (unit vs finalizer integration vs producer). New SIMPLIFY-02 fixtures add about 4 s. Commit `13e4d58` | — |
| REL-SRC-PERF | TEST-01 | P3 | TODO | — | `repository/release-source.py` spawns about 18,800 `git` processes per `release-source-checks.py` run (per-file `show`, `hash-object`, `update-index` in `blob`/`source_hash`/`replace_tree`). Batch with `cat-file --batch`, `update-index --index-info` or `hash-object --stdin-paths`; accept with identical prepared trees/hashes and fewer subprocesses, measured A/B | Ready |
| G51-04 | — | P2 | TODO | G51-02 | See sequence | — |
| G51-05 | — | P2 | TODO | G51-02 | See G51 table | — |
| REL-INTENT-01 | F-15 | P1 | DONE | — | Release only by explicit dispatch on `main` with successful push CI for the exact head (PR #95, `bfb29bc`). A real dispatch is NOT_TESTED | — |
| CI-FORK-01 | F-16 | P1 | DONE | — | `ci.yml` skips fork PRs on main (PR #93, `5d16a08`) | — |
| LOOP-01 | F-18 | P1 | IN_PROGRESS | DIAG-01 | Rule written: local reproduction before a release dispatch (AGENTS.md, Development and fixes). Accept when the next accepted correction reaches release PASS with at most one release run | Measured on the next candidate |
| DOC-02 | F-25 | P3 | DONE | — | PLAN and validation compacted (PR #97, `c248eae`) | — |

Closed registry (detail at `bfb29bc`; evidence in validation). Residual limits are recorded, not
silently closed:

| ID | Finding | Result | Residual |
| --- | --- | --- | --- |
| SAFE-01 | F-01 | Explicit abort; mounted-root proof before markers and pacstrap | — |
| SAFE-02 | F-02 | Checked idle probes, including the AUR UID `find` scan | — |
| SAFE-03 | F-03 | Shared-ESP boot-file collisions refused before root mutation | — |
| TRUST-01 | F-04 | Bounded package decompression and archive traversal | — |
| CONFIG-01 | F-11 | Reserved target accounts rejected before destructive work | — |
| TRUST-02 | F-12 | Package/.db/.files identity and payload consistency | — |
| RECOVERY-01 | F-13 | Quiescent cleanup and bounded nonsecret recovery state | Live cancel/busy/crash VM paths NOT_TESTED |
| DELIVERY-01 | F-14 | Package-only provenance design and negative tests | NOT_TESTED until separately authorized: signed installed-system `pacman -Syu`, package revision increase, unchanged installer/assets/version, exact readback, unchanged latest SemVer |
| MON-01 | F-09 | Dated per-input advisory monitoring, per-major extension comparison | — |
| UP-01 | F-07 | Reviewed source decisions (below) | — |
| ARCH-01 | F-06 | Owner-reviewed 2026.10.01 ISO after real Minimal/Stock qualification | — |
| QA-01 | F-05 | All nine staged scenarios native PASS on 1.0.6 child 7af2209 | — |
| DOC-01 | F-08, F-10 | Current behavior docs and Marble selector text | — |
| GATE-01 | — | One exact candidate a9e4173 accepted (source, build, five root gates, review, PR59) | — |
| RELEASE-01 | — | Immutable 1.0.6 published with final 18 assets, Pages and public Marble VM PASS | — |
| F-26 | F-26 | Stale extension requirement in the plan corrected | — |

Setup tasks AS-1…AS-5 live only in [agent setup](agent-setup.md).

### DELIVERY-01 — package-only provenance and procedure

Design facts that remain binding: an explicit `repository/delivery-intent.json` package intent stops
a dispatched installer release before version allocation and grants no signing authority. The
package child has the exact reviewed package-main parent; only version, URL and diagnostic
substitutions and the package-origin record are allowed. Installer and bootstrap bytes must equal
the independently bound published release. Names, arches, epochs and pkgvers stay; every pkgrel
must increase, and a missing or stale pkgrel is rejected, never generated. Package Pages stays the
exact 14 assets and never becomes Latest; the installer closure stays the exact 18. Current code
rejects package mode until a normal installer release. Procedure: [repository](../repository/README.md).

### Source decisions (UP-01, 2026-10-03)

Retained pins; re-review only with new upstream evidence: Gum 0.17.0 (2.0.x strips ANSI styling in
piped `style`/`join`; sigstore verification NOT_TESTED); Colloid GTK (upstream diff touched only
unshipped switcher/Cinnamon code); Blur my Shell 72 on GNOME 50 (73 needs popup/shader/lifecycle
acceptance); Just Perfection 37.0 (unreleased UI fixes, no reproduced defect); Dash to Dock 106 on
GNOME 50 (109 is reviewed for the G51 candidate); Pikaur 1.33.3 (1.34 changes pkgbase and privilege
environment). Do not update GNOME 50 assets merely because 51 exists. Exact hashes:
[maintenance](maintenance.md) and `bfb29bc`.

## Review findings

P0 urgent critical (none confirmed); P1 high damage or blocks the current goal; P2 ordinary
correction; P3 low risk. Recorded ≠ description corrected ≠ product verified.

| ID | Pri | Finding | Task |
| --- | --- | --- | --- |
| F-01 | P1 | `exec_prepare_disk` reached success after a rejected guard | SAFE-01 |
| F-02 | P1 | Failed idle/UID probes read as empty, proving idle state | SAFE-02 |
| F-03 | P1 | Dual boot could overwrite a neighbor's generic ESP boot files | SAFE-03 |
| F-04 | P2 | Unbounded package decompression before rejection | TRUST-01 |
| F-05 | P2 | Supported options missing from release VM gates | QA-01 |
| F-06 | P3 | Accepted ISO drifted from current media | ARCH-01 |
| F-07 | P3 | Upstream pin drift needed review | UP-01 |
| F-08 | P3 | Latest-release summary stale | DOC-01 |
| F-09 | P2 | Monitoring incomplete, undated or wrong-major | MON-01 |
| F-10 | P3 | Marble selector text described GTK3 only | DOC-01 |
| F-11 | P2 | Username `root` accepted, failing late | CONFIG-01 |
| F-12 | P2 | Signed database records not cross-checked with packages | TRUST-02 |
| F-13 | P2 | Cleanup ran after failed worker reap and dropped markers | RECOVERY-01 |
| F-14 | P2 | Documented package-only route rejected by its own guards | DELIVERY-01 |
| F-15 | P1 | Every main merge started an installer release | REL-INTENT-01 |
| F-16 | P1 | Fork PR code could reach the self-hosted host on main | CI-FORK-01 |
| F-17 | P1 | VM failure evidence drops the guest phase, status and reason | DIAG-01 |
| F-18 | P1 | Release pipeline used as the debugging loop: 32 release runs since 2026-10-05, none successful | LOOP-01 |
| F-19 | P2 | Disk uniqueness passes when an identity probe fails | SAFE-04 |
| F-20 | P3 | 21 hidden-error chroot removals | SIMPLIFY-01 |
| F-21 | P3 | Repeated `lsblk` probing (N+1, N² in the picker); NOT_MEASURED | SIMPLIFY-02 |
| F-22 | P3 | Redundant first destructive-target proof before the idle check | SIMPLIFY-02 |
| F-23 | P3 | Mislabelled action pin comment | CI-PIN-01 |
| F-24 | P3 | Slow and shape-coupled source tests (measured once, serial) | TEST-01 |
| F-25 | P3 | PLAN 2450 and validation 4359 lines with duplicated identities | DOC-02 |
| F-26 | P3 | Plan required an agent extension contrary to the contract | Corrected |

Review focus that stays valid: a guard failure after an accepted handle stops every later stage;
probe errors never mean idle; a neighbor's ESP boot bytes survive; untrusted compressed input fails
within bounded resources; a new GNOME/package/ISO input either activates reviewed Marble or falls
back to working Stock.

## Current Arch context

Observations, not pins or compatibility proof; re-query before use. 2026-10-10 advisory: Shell 51.0-1,
GDM 51.0-1, GTK4 4.24.1-1, libadwaita 1.10.0-1; Plymouth/Bibata AUR heads unchanged. Accepted ISO
2026.10.01 (`684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5`). 2026-10-03:
linux 7.2.8, linux-lts 6.18.54, systemd 262, mkinitcpio 42.2, cryptsetup 2.8.8, GRUB 2.16.
The mkinitcpio 42 TPM2 notice is conditional guidance (the installer does not enroll TPM2); the
NVIDIA open-module transition is reflected in the driver prompt; AUR incidents reinforce manual
PKGBUILD review; the iptables nft default affects existing user rules only. ArchWiki was behind
Anubis protection and was not used as evidence.

## Local runner migration — 2026-10-08

DONE (PR #61, `7430a0b`): all jobs run on runner `ubuntu-actions-arch-linux` with labels
`[self-hosted, Linux, X64, ubuntu-actions, arch-linux]` in the shared `ubuntu-actions` VM
(4 vCPU / 12 GiB, on-demand memory with free-page reporting). Owner decisions: external fork PRs need
maintainer approval (`all_external_contributors`); the shared VM is not a disposable boundary and
rootful Docker can control it. QEMU runs one scenario at a time. Real KVM, namespace and signing
container probes passed as environment probes, not product acceptance. Details:
[testing](testing.md#local-runner-environment).

## Changed structure (2026-10-11)

| Was | Now | Why |
| --- | --- | --- |
| G51 table with run-by-run status prose; checkpoint of ~300 lines | G51 table + short checkpoint; identities in validation | One fact, one place |
| Deep audit coverage, cost and checkpoint sections | Findings and Registry rows; measurement kept in TEST-01 | Tasks remain. Coverage limits stay open (`bfb29bc` "Audit coverage"): AUR/chroot/recovery bodies and earlier F-01…F-14 fixes not re-read; launcher C, sealer and `acceptance-manifest.py` not re-read; VM guest phases not re-read; runtime performance not measured |
| `Scope and constraints`, baselines, mode notes, document-architecture table | Removed; rules in AGENTS.md, navigation in [docs/README](README.md) | Duplicated or stale (work on `main`, Goal state, `/tmp` paths) |
| Execution registry detail sections `### SAFE-01 …` to `### RELEASE-01` | Closed registry rows; full text at `bfb29bc` | All DONE; residual limits kept |
| `## Checkpoint` logs (2026-10-03/04, ~1200 lines) | Removed; 1.0.6 identities in validation | Superseded, partly contradictory (said IN_PROGRESS) |
| Deep-audit queue IDs | Same IDs in Registry; non-finite acceptances given measurable targets | Executable queue |
