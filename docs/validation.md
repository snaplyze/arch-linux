# Validation and evidence

Validation is layered and tree-bound. No old report or status document is evidence for the current
source candidate.

## GNOME 51 candidate — 2026-10-09

The [active plan](PLAN.md#gnome-51-update-recovery--2026-10-09) records the installed
GNOME 51 regression and the seven-package recovery candidate. No new release,
signed package update, real GDM/upgrade VM or public pacman delivery has been
accepted for it. Historical release 1.0.6 evidence below remains unchanged.

Scoped native checks used installed Shell/Mutter/GDM 51.0, GTK 4.24.1 and libadwaita
1.10.0. The existing Shell/GTK stylesheets parsed. An isolated DynamicUser,
headless Wayland session loaded eight Marble extensions with enabled state 1 and
empty extension errors. Shell's diagnostic Eval interface rejected functional
exercises: menu/clipboard/screenshot behavior, visual appearance, password login,
lock/unlock and real package migration are NOT_TESTED by that smoke check.
All owned transient units, processes and headless input fixtures were removed.

Native disposable package builds for the final extension bundle, profile and dual
GDM payload passed the production archive verifier. A separate private installed
package database copy resolved the proposed profile/bundle upgrade with
`pacman --print -Su`; it did not install packages. The exact scoped receipts and
source checks are in the plan. The legacy GTK3 VM scenario does not create the old
four AUR extension owners or the user-local No Screenshot Box tree, so that
existing scenario cannot establish the new upgrade's acceptance.

The candidate now adds a separate mandatory staged 1.0.6-to-GNOME-51 migration
with actual AUR build inputs, an independent manifest digest, password logins,
preference/custody checks and exact package replacement through `pacman -Syu`.
Its source regressions are separate from execution: no real VM result is recorded
yet. Its eight-extension enabled-state check also leaves behavioral extension
acceptance open.

The full clean Arch build subsequently passed `repository/build-packages.sh` and
`repository/verify-unsigned-build.sh` for all seven packages. A separate host-side
unsigned-build verification passed and matched the clean committed inputs. The
disposable container used the pinned Arch image
`sha256:714acd1eef9ae997d95691b1c5220ada0076185b77857c1813f02de0fa83cf7b`,
a non-root builder and read-only source; it was removed after completion.

| Unsigned candidate binding | Exact value |
| --- | --- |
| Source commit | `6b13bbd993faca85fcdd20e40d8ae3993443182d` |
| Source tree | `275464258dd8d4663c5d1265a91b991b18b7aa53` |
| Build metadata SHA-256 | `8ba8ccf2619870623798263568304815513b11b1fa71688bb75484b3d7a13ac0` |
| Unsigned manifest SHA-256 | `28f66a4bf871c29379354190ce37849fa9274a27129b556fcc12ac940f925f0b` |
| Build and verification log SHA-256 | `416c5b2e37e9c7871afd006baef522090340b5da59ceb253343b9c0b28facb7f` |

This receipt covers raw-source package revisions only. It does not establish
the future release child's upgrade revisions, production signing, real package
migration, GDM acceptance or public delivery. Later documentation edits preserve
this original source identity.

Additional source/test-boundary receipts bind commit
`d81f0a07a5962e47317251745789ddc3b727e75d`, tree
`f3d7f15e26f80ddcc2a590224fccf011d8b37540`:

| Executed check | Result and log SHA-256 |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` | PASS; `296434ddd3e019d9594bcfd1843f58bb07fbf803feed35de2a01f74bd07bfcae` |
| Exact empty-environment root publication check from AGENTS.md | PASS, exact 14/18 closures, four namespaces, supervisor-death cleanup and no deferrals; `07dba168db2f1564cb18cc4e014d1b18d8215cf876b5a2e37a49a3a8ef86f644` |
| Ordinary `bash tests/keyring-rotation-checks.sh` | PASS; `fe74de28be8117dfe6234912abb3b070041be1080d16e6aad4f41d3618fe4d45` |
| `env ARCH_LINUX_PRIVILEGED_ACCEPTANCE=true bash tests/keyring-rotation-checks.sh` | PASS, full namespace fixtures, ten scenarios, signer passed, no deferrals; `4129134eac1c23c902481e0788166ee76242817b9fc4534f1355754e48821281` |

The root checks used disposable fixture keys and a pinned Arch container with
private tmpfs test directories. Earlier overlayfs attempts rejected directory
link counts before private signing access; no production check was weakened to
accommodate the container. Privileged fixtures used an independently verified
private Docker cgroup subtree and an owned disposable loop-backed disk. All
containers, loops, mapper and child cgroups were removed; host device metadata
was unchanged. These checks do not establish production signing.
Subsequent functional-harness changes require fresh affected
checks and do not inherit these receipts.

The full source suite subsequently passed functional candidate commit
`a1a3d2683de1f21fa3fcd3f926b901b087bae908`, tree
`ecbf5bd73e547338f4639c37ec9d1ef0e27a6983`; log SHA-256
`7f1c29d8bc24346e1ac969a5812e8dda8470ca6a25f2092effbb22586370ca1c`.
This includes 126 runtime fixtures, seven functional-evidence checks, the exact
33-assertion Marble contract and full repository namespaces with no deferrals.
The separate native GTK probe startup is not GNOME behavior or VM acceptance.
The exact root publication command also passed on that same `a1a3d26` identity,
including the six behavior-receipt requirements and full 14/18 fixture closures;
log SHA-256 `1561bc69968f00829813e9c1d6253cb264c4535717d57ce36aac5ccc51cb61ea`.
Its disposable container and immutable source bundle were removed. Later
upgrade-input helper fixes do not inherit this tree-bound receipt.

Authentic legacy upgrade-input preparation subsequently passed on clean commit
`7a61c40fd42087928e1a2611d02f3ed059dbbfc1`, tree
`ea4367c55601b3c4c920759e5ecf90468e519613`. Execution used
`python3 tests/vm/prepare-gnome51-upgrade-inputs.py --source-root "$PWD" --output "$INPUT_DIR"`
with an absent output directory and the pinned disposable Arch builder. The
preparer returned the manifest digest through stdout; independent worker and
root calls to `verify_inputs(source_root, input_dir, expected_manifest_sha256)`
both passed with that trusted digest supplied separately.

| Legacy-input binding | SHA-256 |
| --- | --- |
| Canonical manifest, exact 15 payloads | `4df9dfb4bb0089d4dca0db10c75173e414d417f38d6d6ad013a0b3f1320a4972` |
| Blur my Shell 72-1 archive | `1ed802469128a4b5c88c60c6a4c4109fc30499d2f3814abb6eeb338da5f4e164` |
| Clipboard Indicator 71-1 archive | `ccefdda5329aee53fa73d441adef92be5539e61b87f6c950265d9d2499a493c2` |
| Dash to Dock 1:106-1 archive | `8c0a05c958ec098ecc40a9e43876d89bb9df21a084a2f9e9b421417189e6523e` |
| Just Perfection 37-1 archive | `8bc46a4d26fe068adaa9dd046331d92269d5787267e9ad32434f12473d9dbc6d` |
| Original local No Screenshot Box archive | `6b1c5184579ca03dc9bf0ad6ded39d99e618c8baf4577ff5391cfa185eb0736e` |
| Preparation log | `28f34f07f25f22bf3c16c3fd543933ab5b113c1f9fed1b2a864fd1086bccd048` |

The closure also contains the ten pinned release 1.0.6 assets. Production archive
and metadata checks verify all four packages, including the Dash epoch and the
sole Clipboard conflict declared by its original hash-bound `.SRCINFO`. Public
inputs and compact logs are retained at
`/tmp/arch-linux-g51-upgrade-inputs.k7RaB53Q`; the owned container and temporary
recipes were removed. This is input preparation, not an installed upgrade or a
GNOME behavior PASS, and it does not transfer to the future release child's
different source identity.

The complete source suite then passed clean commit
`c5a2b8f77947b6a146eebef6808141971e363283`, tree
`4b644f379744507178d2f8dc85c947dc64a84533`, with the final legacy-input fixes and
their documented preparation receipt. Command:
`PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`; exit 0, log SHA-256
`3d4822005934279fe6e625c23554633663bd7743cce851ed5ac8f6978e90614a`.
This includes all 17 upgrade-input regressions, 126 runtime fixtures, 29-page
documentation/link checks, ShellCheck and the full repository result:
`schema=1 namespace_fixtures=full scenarios=10 signer=passed release_closures=14+18 deferred=none`.
The checkout remained clean. This is source acceptance, not the outstanding
production-signed upgrade, GDM/functionality/appearance or public-delivery gates.

## Prepared release 1.0.7 — failed pre-signing attempt

[PR #65](https://github.com/snaplyze/arch-linux/pull/65) merged the GNOME 51
candidate after local source checks and
[PR CI 37878611896](https://github.com/snaplyze/arch-linux/actions/runs/37878611896)
passed. [Main CI 37878934364](https://github.com/snaplyze/arch-linux/actions/runs/37878934364)
then passed and triggered configured
[Release 37879163690](https://github.com/snaplyze/arch-linux/actions/runs/37879163690).
Preparation and the canonical seven-package build passed. The separate readback
failed because the checkout's public trust certificate was group/other writable;
the existing source-mode guard rejected it after metadata hashes matched. Signing,
all QEMU stages, draft/tag creation, Pages and publication were skipped. This
attempt is terminal FAIL and is not a released-version claim.

| Prepared source binding | Exact value |
| --- | --- |
| Accepted PR candidate | `34da98bb34ed57a795e498104c6cf5321b1467d2` |
| Accepted main | `63c9e6c9e80321112405e32f8c6cef0b4ed59ef4` |
| Candidate/main tree | `4209061d00423d88e62acfcb1bba1761e1fb417c` |
| Candidate/main canonical SHA-256 | `0f363c1ac3e3dc9d754791e5bbe664f0e00d514de46267f95e8a627a9a38cf76` |
| Prepared release child | `5ee1439b67b7d83368c416961cfe6230661f2e08` |
| Prepared child tree | `0b961977a85951e804c4cf014698c11e6d495789` |
| Prepared child canonical SHA-256 | `33984ddf16639f9d812953d8272477b6dd0a3b2353bb12f6874b35fa2659eebf` |
| Source transport bundle SHA-256 | `130fdc4dc74a457da8cc5ccdd486478f96fdf16301af1c518854f3349e7a4153` |
| Unsigned artifact ZIP SHA-256 | `95def8b35972a76272e5b87cc5bee038897cb4f7b12fe53fd31961246eca855c` |
| Build metadata SHA-256 | `6d3dc4c4043477723b764649d218ad74a33884a6ec6a6fccd972df77094d6b6f` |
| Unsigned manifest SHA-256 | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |

The root independently reconstructed the deterministic child from accepted Git
objects, verified the downloaded transport bundle and its exact head, and matched
the full mode-and-byte canonical hash. No checkout, Git ref or existing worktree
content changed during that verification. Generated README commands pin 1.0.7;
the release overview no longer labels the tree an unpublished candidate. These
source facts do not establish publication. Generated package versions are keyring
`1.0.0-9`, Shell `50.0.0-8`, GDM `50.0.0-10`, profile `1.0.0-12`, extension bundle
`1.0.0-7`, Colloid GTK `20260808-11` and icons `20260829-7`.
The independent artifact download matched its ZIP digest, both metadata digests,
source commit/tree and all fourteen unsigned-manifest members (seven packages and
seven source metadata files). These transport checks do not override the failed
production readback or transfer this build receipt to a corrected future child.

The corrected readback was then exercised in a disposable pinned Arch container
with the original child and actual downloaded seven-package artifact. The
original verifier reproduced the exact trust-file error at mode `0666`; the
corrected workflow's protected-source and verification steps passed, including
both artifact digest checks. The shared fixture remained `0666`, while the
canonical trust file was root-owned `0644` and verifier bytes were unchanged.
Changing the protected trust file to a writable mode produced the required
nonzero rejection. Limits were two CPUs, 4 GiB and 256 processes with Docker init;
the owned container and large fixture were removed. Native replay log SHA-256:
`b875a3cb1b2bafd5a03ae198b2a33276cbb4c12436b94868314140d92046f421`.
Executed freeze/verify workflow-block SHA-256 values:
`d46880619bc391cbf0d6e7ace2eb87bdbc26e291d91b2d3fa1c6db726fb8ec6e` /
`d00b47bdebcedc3a21efad43c6e041d9418c8bf59895498656268fdb3fcf2b7f`.
This closes the native correction check, not a future release child's CI,
signing, VM or public acceptance.

## Prepared release 1.0.7 — second failed pre-signing attempt

[PR #66](https://github.com/snaplyze/arch-linux/pull/66) delivered the protected
readback correction after the full local source suite and exact-head
[CI 37880505032](https://github.com/snaplyze/arch-linux/actions/runs/37880505032)
passed. [Main CI 37880765176](https://github.com/snaplyze/arch-linux/actions/runs/37880765176)
passed and triggered [Release 37880984567](https://github.com/snaplyze/arch-linux/actions/runs/37880984567).
This is a new prepared child, distinct from the failed attempt above; no old
receipt is transferred to it. Preparation and canonical seven-package build
passed. The protected source passed readback, which then failed at the existing
unsigned-package mode guard. Signing, all VM stages, tag/draft creation and
publication were skipped; the run is terminal FAIL.

| Prepared source binding | Exact value |
| --- | --- |
| Accepted PR candidate | `6647443346414c1c225ad7649f7e67e4c6d639d6` |
| Accepted main | `aa462e1bdfafa5df29b994d0795a9066a2e2cfe9` |
| Candidate/main tree | `40003be954e025d0c82aad905c2d4c1cee704f6d` |
| Candidate/main canonical SHA-256 | `6f7fc682f32df4c627f5270f208adde604fed3d3c6d198a522f1efda3eab6a3d` |
| Prepared release child | `3c3b237104ef0b7482b787767a4ce8c0c2e890a0` |
| Prepared child tree | `552a3b0d1172929d9b7e0916a0e9437610f7dcaf` |
| Prepared child canonical SHA-256 | `2bf3d89832ab1c9c87bdb0aba4438731adc6066e69b8e8608471b7f51bdac25d` |
| Source transport bundle SHA-256 | `7a94373a80df74acea964035ee09ad623ead87b1da906c968390d5d7d0983feb` |
| Unsigned artifact ZIP SHA-256 | `3adbe2184ccbdf44874dec774db03cbc5d572c8fdf3aed7c2dea1b3bd1648b44` |
| Build metadata SHA-256 | `a2dbc5f1f97271a7a3d822aeb8bbd0b43825f28387b1ce2f8908c61da04b6275` |
| Unsigned manifest SHA-256 | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |
| Failed readback log SHA-256 | `1f7a6b91059915ea10da32994c4effbf74a20714816332239911e6bb5aadc6b2` |
| Local full source-suite log SHA-256 | `9d2d593f59f79191abcc24c4b78ca02947c81f6e81f0f882184af7736eb25143` |
| PR CI log SHA-256 | `a18ff65ce180015602949a7ec96e5b6eefca9adf425ee6fd04d0a72bce8a4e36` |

Independent deterministic reconstruction, downloaded bundle verification and
mode-and-byte canonical hashing matched the prepared identity without changing
the checkout, refs or existing documentation edits. Independent artifact
transport checks matched the ZIP digest, source binding and fourteen manifest
members. The first replay's intentionally writable checkout did not cover
action-extracted artifact modes; it cannot close this later failure. Publication,
real GNOME/GDM migration and public recovery are not yet accepted.

The expanded native replay passed with this attempt's actual artifact. It
reproduced the original unsigned-package mode rejection using a controlled
`0666` file, executed the exact corrected protected-input workflow blocks,
matched both metadata digests and all seven package archives, then rejected a
writable protected archive. Normalization preserved hashes; the unsafe source
fixture stayed `0666`, protected source became `0644`, and artifact directories /
files became `0755` / `0644`. The actual snapshot regression clone prefix under
ambient umask `000` also produced safe checker files and passed public-certificate
verification. Native log SHA-256:
`5c676e29a3e41656e3a9d3554b20d8ee6bc5ff54019c005d5b5149854ed4e750`.
This validates the correction in a disposable two-CPU / 4-GiB container, not a
new configured release run. Containers and large fixtures were removed.

## Prepared release 1.0.7 — third failed pre-signing attempt

[PR #67](https://github.com/snaplyze/arch-linux/pull/67) delivered protected
artifact normalization and the snapshot checker clone's step-local umask.
The full local source suite, exact-head
[CI 37881982047](https://github.com/snaplyze/arch-linux/actions/runs/37881982047)
and [main CI 37882323462](https://github.com/snaplyze/arch-linux/actions/runs/37882323462)
passed. Configured [Release 37882590902](https://github.com/snaplyze/arch-linux/actions/runs/37882590902)
prepared a new child; canonical seven-package build and the separate readback
job passed. Snapshot namespace preflight, source sealing, both full repository
modes and the publication-root fixture passed. Ordinary keyring checks printed
their result but exited nonzero during cleanup: a test GPG socket disappeared
between directory enumeration and deletion. That command is FAIL; privileged
keyring checks and production signing were skipped. The run is terminal FAIL,
with all VM, tag/draft and publication stages skipped.

| Prepared source binding | Exact value |
| --- | --- |
| Accepted PR candidate | `d60f41b00456082596ea0727a9ac493dc6442182` |
| Accepted main | `3e0a57f5bdcd3abf648048a4fad9b28d72ddf383` |
| Candidate/main tree | `22a4787d05341263e4d796b84578b10fa53ae98f` |
| Candidate/main canonical SHA-256 | `02cca1f852caa2c89b5d9ceb404dc540593f78db40422421ed819a478b159415` |
| Prepared release child | `dc01f6e2b3b96cf124c249b8b733069de9cb19c0` |
| Prepared child tree | `5f09b51634bc8399fa003aaa553f2108f76f03ee` |
| Prepared child canonical SHA-256 | `144a9df5197738e46f986ecc3d2f9d73da62347c10fe14e252981b2773459442` |
| Source transport bundle SHA-256 | `f64e74d8cdf9fb4912ef2710628cc847fcca2502ab47b6e2a42614cd93372ad7` |
| Unsigned artifact ZIP SHA-256 | `6caafcbe7d568229a3cce16cb0610cb042de2265f3b21edb18fb5a213f861929` |
| Build metadata SHA-256 | `358e2e1ce9676985daadd213259ce02bf916241b12bbb6923383b1a750f653b8` |
| Unsigned manifest SHA-256 | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |
| Local full source-suite log SHA-256 | `5669fc92ba84158870c8f3030cc4af43d9c65b354725fa28688e60334b4681f8` |
| PR CI log SHA-256 | `df317ee72ff728cc0aff25839ae472742f09feaa059e0eb28739f96d07e56f7d` |
| Failed snapshot-gate log SHA-256 | `e988768854c207227e650df9fb29db74891e802f4254e955188481b06f6b6415` |

Independent reconstruction matched the downloaded source bundle's exact child,
tree and canonical mode-and-byte hash without altering refs or current edits.
Independent unsigned-artifact transport verification also matched all fourteen
manifest members, exact source binding and metadata digests. The configured
readback PASS belongs to this child only. Publication-root's signing messages
belong to ephemeral fixture keys, not production signatures. Its result was
`PUBLICATION_ROOT_CHECK_RESULT schema=1 closure=sealed snapshot_assets=14 final_assets=18 fifo=passed memfd=passed namespaces=4 pid1=passed agent=passed supervisor_death=passed signer=passed deferred=none`.
No production signing, VM or publication PASS is implied.

The local follow-up changes only test cleanup and its regressions. It validates
the three fixture GPG homes before scoped shutdown, tolerates only disappeared
directory entries, propagates other cleanup errors and requires the fixture root
to be absent. The exact socket race was reproduced with real GNU find; 25
regressions pass, including unsafe roots/homes, shutdown/delete errors and a
retained root. Actual private-agent/control isolation also passed, requiring
the same responding control-agent PID before/after with automatic restart
disabled. Independent review found no cleanup implementation issue. The full
source suite and both actual keyring commands then passed on frozen candidate
`b819ab95354828825cd23d2b5c924ab9c1ea45c3`, tree
`e7786d4fdad1810cd90af9c773f04f4ec87f99b5`, canonical SHA-256
`85f40ed226901100c03a1b72424dfef5a244df3511bd0b7b7ccf943aa25af83c`.
Source log SHA-256: `0bb9cbf92d04b027d77e7aa9e8c8499c017b93c927bcff81bc6fdda3832e457e`.
Ordinary / privileged logs:
`fe74de28be8117dfe6234912abb3b070041be1080d16e6aad4f41d3618fe4d45` /
`ed3726a10b67301b391a7b5a61ebf297b53e478d7cd5d9580fbf38ae2a6ad08f`.
Both commands exited zero; privileged acceptance reported full namespaces, ten
scenarios, signer PASS and `deferred=none`. The isolated container used two CPUs /
4 GiB, private cgroup namespace and immutable source. Its loop/mapper/cgroup
resources and container were removed; host device metadata was unchanged. These
results bind that test candidate and ephemeral keys, not a future release child.

## Verified release 1.0.6 — 2026-10-04

[Configured run37214392242](https://github.com/snaplyze/arch-linux/actions/runs/37214392242)
produced [immutable release1.0.6](https://github.com/snaplyze/arch-linux/releases/tag/1.0.6),
Release ID403102824, published2026-10-04T16:22:59Z with exactly18 assets after verified Pages deployment.
[PR59](https://github.com/snaplyze/arch-linux/pull/59) passed required Source checks before squash;
this same checkout returned to main by fast-forward. The candidate and originmain share exact
mode-and-byte source identity; the version-only release child is bound separately.

| Binding | Exact value |
| --- | --- |
| Pre-merge accepted candidate | `a9e417304e9883aa354f5ed2cda6a9ead0438eec` |
| Origin main | `696b420bc93415d44bb3ab64b35df7539cbbe87b` |
| Origin/candidate tree | `2d3e7f1abf454c462586cb5450ae1c79d3ccee0a` |
| Origin/candidate canonical SHA-256 | `6d8da82f8008f9d8d002f8a9bd0bb3c60b7db6530eb4894657ad0fcfd38d6250` |
| Release child | `7af2209be497a0a5f0e314cd8cc20f691e52b064` |
| Release tree | `83bd2d9de7d4883b08fbb81c78cce8fe0d36374d` |
| Release canonical SHA-256 | `f6b6517655429ca06afb1cd241d971fe4ccb02352a231020145853ed8b7185ff` |
| Annotated tag object | `54d1208417e872bb08b5b9128752d36030205145` |
| Accepted October ISO SHA-256 | `684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5` |
| Repository snapshot SHA-256 | `25a129f7fa0f91d9ec85d0418ba938dd62e7fea0052838f76b89b3292a795496` |
| Build metadata SHA-256 | `b8cbf4689bac5ad75403a5fc2a1f17e8415a706b5c076d84bb2511e0dfecefec` |
| Unsigned manifest SHA-256 | `b5115ae0838e9c5f01a7fb14a5f32843e2c213ba6ebb31674ea2522f10c05639` |
| Harness SHA-256 | `3409f1b2f1f1bd8c689eccafa1d5f27de009b0a6e0dc74c4086aa0fe28c2e2fb` |

`EXECUTED_PASS`: clean `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` (source35/native0;
includes full namespace10/signer14+18/deferrednone), canonical unprivileged six-package build and
separate fresh container verification, and these five actual release-host commands in a disposable
installed real-root VM, each native0 with its mandatory marker:

```bash
bash tests/repository-checks.sh
bash tests/repository-checks.sh --require-full-namespace
/usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
  /usr/bin/bash --noprofile --norc tests/publication-root-check.sh </dev/null
bash tests/keyring-rotation-checks.sh
env ARCH_LINUX_PRIVILEGED_ACCEPTANCE=true bash tests/keyring-rotation-checks.sh
```

Source35 log SHA-256 `051ee2f2183995c1f493e2e9e70fc40ade36b01d0a7aae9ea36df9ef7fa531cd`;
actual root gate log SHA-256 `f7ae55b1d7f844793827efd03be39c024dfa178df892081e06550f60a85d9456`.
Before/after source identities match; real UID map, quiescent captured PIDs and healthy images
were independently checked before exact-owned cleanup. These fixtures prove pre-merge boundaries,
not production signing. The later configured child build/readback/signing is a separate successful
execution, with actual bundle graph checked in memory without a development checkout or Git import.

| Actual new-child staged scenario | Status | Assertions |
| --- | --- | --- |
| `marble-gnome-btrfs-luks2-plymouth-systemdboot` | EXECUTED_PASS | 26 |
| `marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm` | EXECUTED_PASS | 17 |
| `minimal-dualboot-ext4-systemdboot` | EXECUTED_PASS | 17 |
| `minimal-ext4-systemdboot` | EXECUTED_PASS | 14 |
| `stock-gnome-btrfs-grub` | EXECUTED_PASS | 23 |
| `stock-gnome-btrfs-luks2-plymouth-grub` | EXECUTED_PASS | 22 |
| `stock-gnome-btrfs-luks2-plymouth-systemdboot` | EXECUTED_PASS | 21 |
| `stock-gnome-btrfs-systemdboot` | EXECUTED_PASS | 21 |
| `stock-gnome-ext4-systemdboot` | EXECUTED_PASS | 21 |

All nine results bind the same exact child, ISO, harness, signed snapshot and build/unsigned inputs.
Real password login, Wayland, lock/unlock, update/reboot, integrity, no failed units, clean poweroff
and image health passed where required.
Live installer cancellation, busy-resource cleanup and crash-path VM injection remain NOT_TESTED.
RECOVERY-01 accepts the specified source actual-handler failure/cancellation and concurrent
retention regressions; the nine successful scenarios do not establish those additional live paths. Plain Stock Btrfs/GRUB's23 assertions include real
read-only filesystem snapshot boot and normal-root return/owned cleanup; encrypted GRUB22 is
normal encrypted installation coverage. Marble26 additionally covers honest helper failure and
explicit GDM deactivation. Native result bytes and process chronology were independently checked.

`EXECUTED_PASS`: exact14 Phase-A, original14 byte-identical in finalized18, new acceptance/evidence
signatures, full production evidence validation, native core result hashes and `deferred=[]`.
The signed [acceptance JSON](https://github.com/snaplyze/arch-linux/releases/download/1.0.6/arch-linux-acceptance-1.0.6.json)
binds the full Phase-A map; evidence is1,948,353 bytes, below500MiB. Exact published asset map:

| Asset | Bytes | SHA-256 |
| --- | --- | --- |
| `BUILD-METADATA.json` | 737 | `b8cbf4689bac5ad75403a5fc2a1f17e8415a706b5c076d84bb2511e0dfecefec` |
| `RELEASE-SHA256SUMS` | 1107 | `d0c99ad072dc00ad61a639868e555fe2922671c32d0d8a049153e8d5146fc1cc` |
| `RELEASE-SHA256SUMS.sig` | 118 | `dc40d8940a3708339c2f018faa784e43dbf2054f6f0216acb36de77e6f14e42b` |
| `UNSIGNED-SHA256SUMS` | 1326 | `b5115ae0838e9c5f01a7fb14a5f32843e2c213ba6ebb31674ea2522f10c05639` |
| `arch-linux-acceptance-1.0.6.json` | 5283 | `13e6d8fa2139664fb7bab45042da0b156961f748e96fd656fc9d3c5bb5b23228` |
| `arch-linux-acceptance-1.0.6.json.sig` | 119 | `b159941b5d3b945c2799a2dec4efb304ab4704461526b84272a00b4bc0f10a1b` |
| `arch-linux-acceptance-evidence-1.0.6.tar.zst` | 1948353 | `c1d2a282d13d78eb95eff0ebe77544ee232b4214f6f81cd32fe1a20969db47a1` |
| `arch-linux-acceptance-evidence-1.0.6.tar.zst.sig` | 119 | `3b03534ec13401ab21c398c36488b6646c3b54b5ece42760e7227cae25e31780` |
| `arch-linux-installer.sh` | 402255 | `ebb90209b6d407f8bb54091ef4112267852269bf5744af9c54df8a8308dff55a` |
| `arch-linux-installer.sh.sha256` | 90 | `a3ef1368b540a44b802fc041c128c201a91815d647550841d96a0eea534ac776` |
| `arch-linux-installer.sh.sig` | 119 | `f98ad9d66e69ddaf36d57e0a3eb519bb16507c6079cfe92fd41adc7a622b0d0c` |
| `arch-linux-repository-1.0.6.tar.zst` | 5732653 | `25a129f7fa0f91d9ec85d0418ba938dd62e7fea0052838f76b89b3292a795496` |
| `arch-linux-repository-1.0.6.tar.zst.sha256` | 102 | `b357b8e150c74db7872d12309562ea2986686b0780545b444bf668c7f5361f8f` |
| `arch-linux-repository-1.0.6.tar.zst.sig` | 119 | `bd8b72494b61ba462a37de3af0e24d71c956f99335660b3226c0b9338643caa8` |
| `arch-linux.gpg` | 568 | `8959dfd96fd94349d505f18a6d3ef0a3bfcd9fad53291343388f787f9dbb9c6f` |
| `install.sh` | 28213 | `ee9f9c085acf6c8d2519fb8d76003da101740052afe5bf2a16bbc8957506f663` |
| `primary-fingerprint` | 41 | `7e12b5e2a2ce9ed2881e06d80054a969465eea72f917282f25f27ae02cf66824` |
| `signing-subkey-fingerprint` | 41 | `471e476b51923eb1afe73609a7ef4aef3fbc1e1c2b09ba3f77e9f1f349643b69` |

`EXECUTED_PASS`: unauthenticated HTTPS Release18 byte equality to accepted finalized18 and
annotated tag→child/run binding; all25 Pages files (23 named objects plus manifest/signature)
match the independently safe-extracted signed snapshot. Public API requires immutable=true and
exact canonical asset sizes/digests; downloads require exact size, EOF and SHA-256 under a30m
outer process deadline. Root and independent read-only checks accepted actual bytes.

Proof receipts: source graph `f719cf2597cb02edd34b7dbe560cb06891896dc5b89d0cd56ac29a702a8e2579`,
Phase-A `7838f402db5be938d7649f40abb733df73bb560fbebf0a43bb3a8e51b66ec16a`,
final18 `b69d534ce6755cf9af235edb804d3e05bb05a9660b1b1570f3e95721f02227c5`,
public bytes `957a3c88f0e95d5405f6fa8bb048d195684848939c9d174e9d0c49ad3311bb67`.
They are retained with compact native evidence in the existing external evidence register;
no signing secrets, VM disks or generated package outputs enter source.

`EXECUTED_PASS`: fresh public-only Marble/GDM VM, native0 with19 assertions. The configured
workflow completed SUCCESS. Public run `marble-20261004T162511Z-cc51576a` consumes only
immutable tagged bootstrap/verified Release installer and signed public Pages. It passed actual
HMP password login and Wayland, lock/unlock, full update, reboot/second login, package integrity,
zero failed units, clean poweroff, no matching QEMU process and healthy image. The compact
public artifact11308433140 binds the same accepted child/source/ISO/harness/snapshot/build inputs;
its manifest/signature and23 repository objects match the signed archive and public byte proof.
Native result SHA-256 `13de92af4ecc355529ae734674a7966529c62209adbb7d0d066ebf523b0d25e8`;
public archive SHA-256 `a227c1c3078672beea8c66163e2add16815ce2f43253963c7d6502d437fb1f4f`.
Public19 and staged26 remain distinct: staged-only legacy/helper-failure/removal checks are
not relabeled as public execution. Optional screenshots are retained as diagnostic evidence.

Local final-document verification uses `python3 tests/docs-checks.py`, `git diff --check` and
`PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`. Working-doc source36 passed native0;
the clean document-commit command/tree/receipt is bound in the existing register.
It does not replace or relabel the release-child VM/source identities above.

Clean local documentation commit `30d4a162ed99141c4ccd2b43273a90f1fda0b756` (tree `895fb77ea77e2f66ef5bf8cbb49ba6f21572004b`, canonical SHA-256 `368587520f60e525c9ede887e08b139e77aa42597dbbfc6da2705422339c04d6`) passed `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`, source37/native0/session71065; log SHA-256 `ad9f3e402e3bcfaf772d44c3b88ec422e4eba3df6a948b91d7dcd8610ece3ccd`. This result belongs to that exact documentation tree. Later documentation edits require fresh applicable checks; the evidence register preserves each exact tree/result.
Historical predecessor failures, 1.0.5 media qualification and older release results retain their
original identities. Final documentation was initially retained in localmain commits. A subsequent
explicit owner request authorizes checked PR/main publication of these documents. Record its exact
outcome in the same evidence register after publication. This publication requires no new installer release.

## Historical audit record

The [single registry](PLAN.md#review-findings) records the October 2 review and October 3
documentary follow-up, coverage, open findings and exact check outcomes. Documentary corrections
do not fix product defects. Fresh builds, production signing, crash/race acceptance, real account
creation and real VM installation were not executed by this follow-up; they remain NOT_TESTED
(`NOT_RUN_ENVIRONMENT` in the check-status vocabulary below).

## Public readback of release 1.0.5

October 3 execution independently downloaded all 18 immutable [1.0.5 Release assets](https://github.com/snaplyze/arch-linux/releases/tag/1.0.5),
checked their API size/SHA-256 map, exact-12 `RELEASE-SHA256SUMS` coverage and all five
release detached signatures against the committed public certificate and exact signing subkey.
Public trust files match the committed bytes. The Pages manifest and signature match the signed
repository archive bytes; all 23 named repository objects match size/hash, and the manifest,
two databases and six packages pass detached signature verification. The semantic database
checker additionally accepted the real published database/package pair.

| Binding | Value |
| --- | --- |
| Release commit | `61add3e0b2c20adbbdd425494eae02ddec0a3bac` |
| Release tree | `b5ca51e80277d93541d00a305490ac818d629a33` |
| Canonical source SHA-256 in signed acceptance | `02816596c2e2e72cddb31b357723660685e4c77fce929c76b04f5e21dee18d37` |
| Repository archive SHA-256 | `79413af54fca28fc1afef9fbfe6dea24875470d1a3cd65a6c459eb85bde26474` |
| Build metadata SHA-256 | `c6d7a812737b41e52e8ea3cb59613ac2ceb0e4a0e601d44f6de99820661972da` |
| Unsigned manifest SHA-256 | `97a821f50df2ab7a523107e0b9f7f956fcce6cc02189437d758c4c429bc6deae` |

Historical status: `EXECUTED_PASS` for public byte/signature readback. At that readback README commands pinned 1.0.5.
Its signed acceptance still describes the three historical September ISO runs; it is not an
October installation or corrected-candidate PASS. Subsequent corrected-release execution is recorded above and in [the registry](PLAN.md#execution-registry). The verified 1.0.4 evidence below
keeps its original identity and outcomes.

## Verified release 1.0.4

[Release 1.0.4](https://github.com/snaplyze/arch-linux/releases/tag/1.0.4) was published on
2026-09-17 with `immutable: true` and exactly 18 assets. Its annotated tag resolves to commit
`c4c46588b8eab987c3c29e6548b81bd2f6b4217f`, tree
`b973c979e781e06af30fb18f0855b9724c941e0c`. The reviewed origin main commit is
`e4e68bb58ef3a61c2de9938223a4fd214d2f6e76`. These identities describe that release, not later
changes to `main`.

The [Release workflow](https://github.com/snaplyze/arch-linux/actions/runs/35164378553)
completed successfully. Its build, independent artifact readback, signing-boundary checks, staged
VM matrix, finalization, annotated tag, Pages deployment and immutable publication passed.

| Executed scenario | Result | Functional assertions |
| --- | --- | --- |
| Minimal TTY / ext4 / systemd-boot | EXECUTED_PASS | 14 |
| Stock GNOME / Btrfs / LUKS2 / GRUB | EXECUTED_PASS | 22 |
| Marble / Btrfs / LUKS2 / systemd-boot / Marble GDM | EXECUTED_PASS | 24 |
| Public-only Marble installation from Release and Pages | EXECUTED_PASS | 19 |

The signed [acceptance JSON](https://github.com/snaplyze/arch-linux/releases/download/1.0.4/arch-linux-acceptance-1.0.4.json)
and [evidence archive](https://github.com/snaplyze/arch-linux/releases/download/1.0.4/arch-linux-acceptance-evidence-1.0.4.tar.zst)
contain the three staged results and their exact input bindings. Both have detached signatures in
the Release. The final public VM result is a separate workflow artifact; it does not modify the
already published acceptance JSON. Public attempt 3 passed; the earlier HTTP download failure and
connection reset remain failed attempts, not relabelled successes.

The staged Marble run includes legacy GTK3-package replacement, fresh-user activation and startup
of Nautilus, Ptyxis, Settings and Boxes in both color-scheme states. Startup checks and diagnostic
captures do not establish exhaustive visual compatibility. No new claim about every storage,
bootloader, dual-boot or physical-hardware combination follows from this three-scenario release.

## Source evidence

Contains exact source identity and the commands/statuses for syntax, version, bootstrap, static,
function, Marble, package metadata, documentation, portability, secret, agent, maintenance,
repository fixture and ShellCheck tests. It must not include generated package or VM outputs.

## Build evidence

Contains the clean Arch environment identity, canonical unsigned package closure,
`UNSIGNED-SHA256SUMS`, package metadata and verifier result. Monthly A+B comparison is advisory and
is recorded separately from the required canonical release build.

## QEMU evidence

Contains the accepted ISO identity, QEMU/OVMF versions, new qcow2 and independent VARS identities,
scenario configuration, installer/repository identities and a structured result. The exact release
matrix is Minimal TTY/ext4/systemd-boot, Stock GNOME/Btrfs/LUKS2/GRUB and
Marble/Btrfs/LUKS2/systemd-boot with the separate experimental Marble GDM opt-in. All three staged
runs bind the same independently verified production-signed repository archive, source commit/tree,
build-metadata hash, unsigned-manifest hash and frozen Arch ISO hash.
The staged inputs are the exact 14 Phase-A assets, whose signed checksum manifest covers exactly 12
non-self files. Finalization is allowed only after all three functional PASS results and preserves all
14 bytes while adding signed acceptance JSON and evidence archive for exact 18.

Each scenario retains a short compressed installer log, input and tool hashes, the signed repository
manifest/signature and package/database hashes, functional assertions and a structured PASS or FAIL.
A FAIL includes the failed phase and non-zero exit status. Check actual GDM password login and the
resulting Wayland session, lock/unlock, update and repeated login. Screenshots help diagnose the
result but are optional; no sampling interval or human receipt is required.

After each scenario remove its qcow2, OVMF VARS, payload, extracted repository and TLS runtime,
check that its QEMU/server processes exited, and retain `qemu-img check`. Never retain passwords,
private keys, passphrases or recovery material. Keep reports compact and separate from source;
the release evidence archive has a 500 MiB storage cap, not a frame timing or visual certification
requirement. Do not scan VM disks as if they were text logs.

## Release evidence

Contains signed repository/release-asset verification, immutable release asset identities, Pages
readback and the final public VM result. It is created only after the corresponding operations and
cannot retroactively change source/build/QEMU results. For the generated release child, provenance
also binds the exact successful origin main commit/tree and the deterministic transform record.
The acceptance JSON binds the commit/tree/canonical source SHA-256, build/unsigned/snapshot hashes,
the exact Phase-A name/hash/size map and aggregate, its manifest hash, three PASS verdicts,
evidence no larger than 500 MiB and `deferred=[]`.

The final public Marble/GDM VM carries no local product bytes: it downloads the immutable tagged bootstrap, verifies the Release installer and
public key, executes only that verified installer, and obtains project packages and databases from
the exact public Pages URL under `PackageRequired DatabaseRequired TrustedOnly`. Public readback
verifies signed `RELEASE-SHA256SUMS`, the exact archive digest and signature, byte equality between
the archive and Pages manifests/signatures, schema-2 source/build identity, all 23 Pages object
hashes/sizes, and all package/canonical-database signatures. Merely echoing an expected archive hash
or validating an unbound Pages manifest is not public readback evidence.

## Status discipline

Use exactly one status per check: `EXECUTED_PASS`, `EXECUTED_FAIL`, `REVIEWED_ONLY`,
`NOT_RUN_ENVIRONMENT` or `NOT_APPLICABLE`. Record exact commands for executed tests. Absence of a
required environment is not a PASS.
