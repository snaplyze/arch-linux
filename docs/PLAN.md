# Project review and modernization implementation plan

> Current mode (2026-10-03): owner-authorized autonomous implementation of the full registry.
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
| QA-01 | P2 | SAFE-01…03, TRUST-01/02, CONFIG-01, RECOVERY-01, UP-01 | DONE | Regression tests and mandatory child VM gates implemented |
| DOC-01 | P3 | Corrected selector and source behavior prose; final release records under RELEASE-01 | DONE | UI copy and final behavior docs; prose correction is not product fix |
| GATE-01 | P1 | all above | IN_PROGRESS | Frozen, independently reviewed pre-merge source/unsigned-build candidate |
| RELEASE-01 | final | GATE-01 | TODO | Main delivery, child build/signing/VM acceptance, tag/release and public readback |

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
- [x] Run function/source checks; actual stop/cleanup and races remain NOT_TESTED until bounded
  disposable VM error acceptance executes.

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

- [ ] Recheck main/origin/dirty/index and ownership; stable independent security review of final changes.
  No simulated independent review. Resolve material findings and rerun affected checks after correction.
- [ ] Run `bash tests/source-tests.sh` and `git diff --check` on final candidate; bind commit/tree and
  canonical mode-and-byte source SHA-256, package inputs, tool versions and selected ISO.
- [ ] In an authorized disposable release-host boundary execute unflagged + full-namespace repository,
  exact root publication and both keyring modes listed in AGENTS. Fixture signing uses ephemeral keys.
- [ ] Build once canonically as disposable unprivileged builder and independently verify unsigned outputs.
  Do not create production signing authority to satisfy a pre-merge check. Record clean-build environment
  and preliminary checks; they do not transfer to the later deterministic release child.
- [ ] Verify all mandatory child source/build/signing/VM gates are implemented and block finalization
  on failure. Record bounded resources before execution. Production Phase A/exact-18 and authoritative
  VM execution belong to RELEASE-01 after main delivery, before tag/publication where applicable.
- [ ] Freeze evidence for exact inputs; any source correction invalidates affected downstream PASS.
  Package reproducibility A+B remains advisory, not an invented blocking release criterion.

### RELEASE-01 — main, annotated tag and immutable release (last)

Target: `snaplyze/arch-linux`, protected main and its configured `release.yml`/Pages target.
Owner requested this as the end of the plan. Do not publish during review/planning.

- [ ] Confirm GATE-01 and authorization/resources for this candidate. Main requires PR; current
  contract requires an explicit owner exception for switching a PR branch in this checkout.
  Request that exception only when a concrete accepted result is ready to deliver; no bypass/force push.
- [ ] Commit only owned reviewed paths; deliver through required Source checks and squash PR merge.
  Return this same checkout to main and fast-forward only. This is delivery to main, not a rejected
  direct-push attempt and not another development clone.
- [ ] Let configured `release.yml` derive/test/build/sign the version-only child from accepted main.
  Do not create a competing manual tag/release; let pipeline select unused SemVer and annotated tag.
  Current latest is 1.0.5; do not hardcode 1.0.6 before querying live inventory.
- [ ] Require successful child source/build/signing, three staged plus supplemental gates before
  finalization; exact 14 bytes unchanged → exact 18 finalized assets, signed acceptance/evidence.
- [ ] Observe immutable Release/tag, verified Pages deployment and public readback, then fresh
  public-only Marble/GDM VM. These public checks necessarily happen after publication; distinguish
  all pre-publication checks passed from final public acceptance passed.
- [ ] Record origin main and child commits/trees, tag object, run URL, assets/hashes and final public
  result in validation. Keep old releases/tags/bytes intact. Post-publication defect gets new reviewed
  fix/release; no tag movement, deletion, changed-input retry or signing-key rotation.
- [ ] Mark DONE only with actual main delivery, immutable tag/release and successful public acceptance.
  If external gate fails, record exact blocker/next safe action and retain local accepted result.

## Checkpoint

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

Current next action is audit verification only. Implementation stays stopped pending a separate
assignment; then initial safety work is SAFE-01/SAFE-02 and independent tasks may proceed.
All product tasks remain TODO. No staging/commit/push/merge/tag/signing/deployment/new release.

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
