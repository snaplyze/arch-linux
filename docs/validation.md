# Validation and evidence

Validation is layered and tree-bound. No old report or status document is evidence for the current
source candidate.

## GNOME 51 candidate — 2026-10-09

This historical section records initial source/native/unsigned checks, including
the exact `6b13bbd` and `d81f0a0` identities below. At that stage no new release,
signed package update, real GDM/upgrade VM or public pacman delivery had been
accepted. Later prepared-child and signed-snapshot records below retain their
separate identities; consult the [active plan](PLAN.md#gnome-51-update-recovery--2026-10-09)
for current delivery status. Historical release 1.0.6 evidence remains unchanged.

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

The source candidate added a separate mandatory staged 1.0.6-to-GNOME-51 migration
with actual AUR build inputs, an independent manifest digest, password logins,
preference/custody checks and exact package replacement through `pacman -Syu`.
Its source regressions were separate from execution: this initial record contains
no real VM result. Its eight-extension enabled-state check also did not establish
behavioral extension acceptance.

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

## Prepared release 1.0.7 — fourth failed pre-signing attempt

[Release 37884673557](https://github.com/snaplyze/arch-linux/actions/runs/37884673557)
failed during build after the ordinary-keyring cleanup correction and successful main CI.
This candidate has its own identity; earlier failed attempts remain failed.

| Input | Exact value |
| --- | --- |
| Reviewed main | `7203ec6d2650add1477325e60670629702246495` |
| Main tree | `74d877af34047cbdf38e67494f5f6f87407b8cb8` |
| Deterministic release child | `9143b7726a21f7f3e1629f850379b671b3b9ee53` |
| Child tree | `015c773af5e9001fa905a3496929169685b391c9` |
| Canonical child mode-and-byte SHA-256 | `6c8fd3f79fdae321cf5fa40d0f6e12200ed03c4f0166d9895c3c7d772e221290` |
| Source bundle SHA-256 | `44aff551aceb99a3389147995c3701f1d29211070613ad54e6fbfcc184bc990f` |
| Source artifact | `11595129285` |
| Source transport SHA-256 | `7584d9889a26833c1ed6efb48a7a6eeb3a179bdc4fbc4b4d544fc8103c372f8c` |

Independent source ZIP closure/digest, bundle verification and deterministic child
reconstruction passed. The canonical checkout, existing refs and pending
Markdown bytes were unchanged. The child's complete source suite passed. Build
failed while fetching the pinned Dash to Dock archive from GNOME Extensions:
curl error 35, TLS unexpected EOF. The keyring package built, but the canonical
seven-package artifact did not complete. Signing, QEMU and all publication stages
were skipped. Failed build log SHA-256:
`f8d06c37bee466b0a3d4fdc985882f92ae22ab1012a78dfe98822536c59756b0`.
This external download failure does not establish a package or signature defect.

## Prepared release 1.0.7 — failed same-input retry

After a same-runner download matched the unchanged Dash to Dock pin, successful
main CI attempt 2 triggered
[Release 37885316974](https://github.com/snaplyze/arch-linux/actions/runs/37885316974).
Independent source transport verification passed for artifact `11595912002`,
ZIP SHA-256 `8b3da8b5acc64b711c0659d0b0891cf2002b586dd4d863e3c296a2f18916255d`.
Both `identity.json` and `source.bundle` are byte-identical to run 37884673557:
child `9143b7726a21f7f3e1629f850379b671b3b9ee53`, tree
`015c773af5e9001fa905a3496929169685b391c9`, canonical SHA-256
`6c8fd3f79fdae321cf5fa40d0f6e12200ed03c4f0166d9895c3c7d772e221290`.
No source, source pin or trust change was made for this retry. Source checks passed,
but the same pinned Dash download received HTTP 503 on all four attempts. The
canonical build did not complete; readback, signing, VM and publication were
skipped. Failed log SHA-256:
`0c5d5b6165ae6b3ed930e4f7f433703730a45be682849f7278b03684bf5da622`.
A separate workstation request reproduced HTTP/1.0 503 through synthetic DNS;
subsequent bounded response inspection identified the OpenShift “Application is
not available” page. Resolving through public DNS while preserving the exact
HTTPS hostname, certificate verification and URL also returned 503. An independent
runner probe reproduced the failure with both plain curl and makepkg flags.
No diagnostic payload was accepted as an archive; no DNS/TLS/pin setting changed,
and all owned probe containers were removed. The present evidence points to the
application/ingress being unavailable during those attempts. After the owner's
explicit goal resume, four exact pinned GNOME Extensions downloads passed on the
actual runner without retries, all HTTP 200 and matching hashes. CI attempt 3 was
requested for unchanged main `7203ec6`; this availability evidence does not relabel
either failed release run or establish signed delivery.

## Prepared release 1.0.7 — retry after upstream recovery

Successful main CI attempt 3 triggered
[Release 37888302371](https://github.com/snaplyze/arch-linux/actions/runs/37888302371)
after all four pinned GNOME Extensions archives were available on the runner.
Source artifact `11597535545` passed independent ZIP digest and exact two-file
closure checks, SHA-256
`2bb886e9a9f8a10005a03b729037cd4396c1689dd79cf5c786bc57e74096aa60`.
Identity JSON and source bundle are byte-identical to the previous attempts:
reviewed main `7203ec6d2650add1477325e60670629702246495`, release child
`9143b7726a21f7f3e1629f850379b671b3b9ee53`, tree
`015c773af5e9001fa905a3496929169685b391c9`, canonical mode-and-byte SHA-256
`6c8fd3f79fdae321cf5fa40d0f6e12200ed03c4f0166d9895c3c7d772e221290`.
The child's source suite and clean canonical build passed. Independent transport
verification matched all fourteen unsigned-manifest members, seven package names
and source commit/tree. Exact transport receipts:

| Object | SHA-256 / identity |
| --- | --- |
| Canonical unsigned artifact | `11596764540` |
| Artifact ZIP | `9fc8309aa9bb7bcf266b1124a3ec4021deb8753950857085dd857cb678581c6c` |
| BUILD-METADATA.json | `ba78b339ebfcdd9fd82e488577e91a1203b9e074f1c366566ab62847414b4ebc` |
| UNSIGNED-SHA256SUMS | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |

The package byte set matches the seven versions recorded for the first 1.0.7
attempt; this child's build metadata retains its own identity. The protected
readback and snapshot jobs passed. Both full repository modes, publication-root
and ordinary/privileged keyring commands succeeded before production signing.
Required full/privileged receipts have `deferred=none`; the ordinary keyring mode's
expected privileged deferral was closed by the following privileged command.
Snapshot job log SHA-256:
`45cb4d545d1a33b488b1476f1a02161994fe7a17eeb90b7397b5024f3a68430d`.
Its early snapshot/finalize messages belong to ephemeral publication fixtures;
the later production snapshot operation completed at 05:31:15 UTC.

| Signed Phase-A object | SHA-256 / identity |
| --- | --- |
| Artifact | `11597980161` |
| Artifact ZIP | `ad8e0a51abc44ea08f49b6ca2446f8375ac607732e8117934f727c8ea6b4c913` |
| Repository snapshot | `032449b92ae8c922fd5b6afe2e5be2f8298e73e4b2aa696fb9a9a3152e8f495a` |
| RELEASE-SHA256SUMS | `f4daf35541ddc05caa979e5469f1ab970db42f4068308641d7729093c58f1d44` |

Root independently verified the exact fourteen-file ZIP closure/digest, every
member of the twelve-file signed manifest, unchanged trust bytes, matching
BUILD/UNSIGNED hashes and the manifest/installer/archive signatures. GPGv bound
them to signing subkey `B294D26BDAD5469EE334B0453DA0736C98322CCA` under primary
`9C603F25F83F4B0F4745D790D97919282A24E748` in a fresh public verification home.
This transport/signature verification does not establish installed behavior.
Actual Minimal TTY scenario `minimal-20261009T053309Z-44dd08b9` completed with
`status=PASS`, `exitStatus=0` and all fourteen assertions. Evidence includes plain
`pacman -Syu`, new boot ID, zero failed units, clean shutdown, successful final
`qemu-img check` and absence of its QEMU process. Artifact `11598290558` has ZIP
SHA-256 `6a1117ed1e19270243cf3f461524fa4cacd94b776ddd57c3994c669169bec2f8`;
the inner `.tar.gz` SHA-256 is
`25d5880add9620966cdbcd2109e6cdbafe4422e055d83ea75615299e8ba85c07`.
Source commit/tree, build/unsigned/snapshot hashes match the exact candidate above.

Production-consumer replay against this actual evidence rejected it with
`QEMU harness manifest row differs`. The evidence producer's `harness_files`
sequence places the two GNOME 51 preparation inputs before guest bootstrap/verify;
`HARNESS_FILES` in the acceptance consumer expects the reverse ordering. The
exact ordered-closure guard correctly exposes this integration defect. The
observed Minimal installation PASS is retained; final acceptance is not PASS.
The workflow is terminal CANCELLED: Stock GNOME was interrupted and its evidence
packaging had no completed result; queued scenarios/finalization/publication did
not run. Runner cleanup completed, its temporary evidence root disappeared and
no project QEMU process remained. Cancelled Stock log SHA-256:
`55343615b61bdd1645fd0707a35248779bf6aa152bf3157c3f818cda43aaa9df`.
No tag, immutable release or Pages deployment was produced by this attempt.

The focused two-file correction reorders only the consumer tuple and adds an
actual-producer regression with negative closure/hash/readback cases. Independent
review found no issue; nine evidence and 25 Actions regressions passed. Replaying
the complete production `snapshot_contract` and `directory_run` against the
unchanged actual Minimal evidence now passes with consumer file SHA-256
`7aca0ba1f89c8a0a193ceb8cc4bc19d8172d257f05f3b22e164f0ac2bd5b505c`.
Result JSON SHA-256 is `45995b7b0b5bdbeaa27c0413774bc5a9c780cbc6fb1a308df735695bbcddc30a`,
harness SHA-256 `d722051e656f6f0bbcdd4087cb129d23c152ddbef649993564acf0e47e24322b`.
This diagnostic replay validates the fix against real input; it does not transfer
the old child's VM PASS to the forthcoming corrected child.

## Unpublished release 1.0.7 — harness-order correction

[Release 37890827364](https://github.com/snaplyze/arch-linux/actions/runs/37890827364)
ran from the protected PR #69 merge after successful main CI. It was cancelled
before publication to correct a contradictory installation recommendation in
the frozen documentation; its signed snapshot and actual Minimal result retain
their own identities below.

| Input | Exact value |
| --- | --- |
| Reviewed main | `4924cb8676ed76b6e4e3475c9287a6fd40bc96c7` |
| Main tree | `b984e46f50503242845602d6c0752c0df4b4504d` |
| Deterministic release child | `5d291a967970c4aba6712af66ebc7dc0ddbb94a3` |
| Child tree | `7c99a254773d768d0181c3d9774c973d3b291058` |
| Canonical child mode-and-byte SHA-256 | `32d64e315d8cb37a9df3ffe3c0206f35f164a5a5deb4d267f41bdea61736fd75` |
| Source bundle SHA-256 | `014fbfab2ab89523afb0e19c4d10910d1439a059bce207cd6771ee0293ee7646` |
| Source artifact | `11597543806` |
| Source transport SHA-256 | `5a9cdfc6638eb51f69070f517f9071b740f91f4e436908429dfd2ddb0b2cff1f` |

Independent ZIP closure/digest, bundle verification and deterministic source-child
reconstruction passed; refs, checkout and pending Markdown were unchanged.
The child's source suite, canonical seven-package build and protected artifact
readback passed. Independent transport verification matched source identity,
package names and all fourteen unsigned-manifest members.

| Unsigned object | SHA-256 / identity |
| --- | --- |
| Canonical artifact | `11598268604` |
| Artifact ZIP | `855a559fb5c3c07e570cdd16e7667a6f280b38a45d09040b87d125364f8a735e` |
| BUILD-METADATA.json | `4323460ecddb9c5d309008a0cf144ec4f8af4b13f9aded4329f47bfd5a0c12ed` |
| UNSIGNED-SHA256SUMS | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |

Package bytes reproduce the earlier reviewed seven-package set; build provenance
is specific to this child. Snapshot job `113692422714` passed both full repository
modes (`namespace_fixtures=full`, ten scenarios, fourteen/eighteen closures,
no deferrals), the full root publication boundary and ordinary/privileged keyring
modes. Production signing completed for this child. Independent readback passed
the ZIP digest and exact fourteen-file closure, all twelve manifest-member hashes,
unchanged public trust bytes, unsigned provenance and all three public-key
signatures. The retained signer is the published signing-only subkey; no new
trust was accepted.

| Signed Phase-A object | SHA-256 / identity |
| --- | --- |
| Artifact | `11598089613` |
| Artifact ZIP | `e4745e02f975a8a33bee8f2205a1db4bde0e7793edbf6ae7f559cf390bee9c10` |
| Repository snapshot | `938304fae3c866ac4abba1bd8dc950ada61319f979af10aa0bec7e52c6ffa7c6` |
| RELEASE-SHA256SUMS | `22a512b4aca045228c39fcab87e4e10f99ea39575b6a46f0cb2890ef1b36fd84` |
| Snapshot job log | `0941bc479bfcd03be971dcd3889891add2c9f323dcfcb96fe569187564e484b7` |

The actual Minimal run `minimal-20261009T060459Z-d019ec7a` completed all fourteen
assertions, including plain `pacman -Syu`, a different boot ID, clean shutdown,
QEMU exits, image integrity and no owned process. Its artifact uploaded before
the workflow/job completed as cancelled. Independent readback passed the exact
transport digest, production evidence unpacker and strict `directory_run`
consumer without changing assertion order or weakening any check. This validates
the harness-order correction on actual evidence, not just a fixture.

| Minimal evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11598936098` |
| Artifact ZIP | `5fd5f4058639eb8e03616be8a9bbd597581786b4cfde8e904d78285a9e7e7e4e` |
| Evidence archive | `e9cd274c286bb64369dd908af7dde76290de8e18fec2c0ff8e80057d3249cd10` |
| result.json | `043dd303c1ea8138b5253ec1aebd07004dc9e1985b6657e507a1683e5190d4c6` |
| Actual consumer | `7aca0ba1f89c8a0a193ceb8cc4bc19d8172d257f05f3b22e164f0ac2bd5b505c` |
| Cancelled job log | `e114564f1a114bd65319626189d44280216406b7e50524c424b163e283d6e863` |

The remaining eight scenarios did not execute. No finalizer, tag, immutable
release or Pages publication occurred. This child's Minimal PASS cannot be
transferred to the documentation-corrected child.
An independent read-only runner check after cancellation found no QEMU process
referencing the exact project evidence prefix and confirmed that the evidence
base was absent; no QEMU process entry was unreadable.

## Prepared release 1.0.7 — pre-freeze documentation correction

[Release 37893328836](https://github.com/snaplyze/arch-linux/actions/runs/37893328836)
was triggered by successful main CI after the protected PR #70 merge.

| Input | Exact value |
| --- | --- |
| Reviewed main | `85e12ab388683d3e03fa01507f7c20fe923a2e23` |
| Main tree | `a52be050556749c7ebf72101bf1c864b73cba9c1` |
| Deterministic release child | `c5d655394527f0dda61ceb80e33a2968ac6a14df` |
| Child tree | `53ccd5ee9dc4594d31258f900aad7cc9ab54aca1` |
| Canonical child mode-and-byte SHA-256 | `eb0ae3b50117e2ef4ecf99c11450abc262dcbfd11d4fa7bf2945da2236cf57b9` |
| Source bundle SHA-256 | `26d60740d03c2b56896e5717e05d8b18743c0ac1a2e8428e05247da0a6c25376` |
| Source artifact | `11599232660` |
| Source transport SHA-256 | `57b8cbc6e61a8d56993b9fe7ce021c1e097d633d683d2a519e2bba9984dab2c2` |

Independent exact ZIP closure/digest, bundle verification and deterministic child
reconstruction passed without changing refs, checkout or pending documentation.
Direct inspection of the generated child confirmed consistent 1.0.7 installation
guidance and a release-neutral documentation index. Package/signing, staged VM
and public results must be recorded for this child; earlier children do not qualify them.

The child's source suite, seven-package clean build and protected artifact
readback passed. Independent transport checks passed all fourteen unsigned
manifest hashes, the exact sixteen-file closure and schema-2 metadata bound to
this child, the pinned source epoch, installer and package set. Package bytes
reproduce the previously reviewed set; provenance belongs to this new child.

| Unsigned object | SHA-256 / identity |
| --- | --- |
| Canonical artifact | `11599163430` |
| Artifact ZIP | `06c67acae7a7d3fe65e1ce19c8022dbe04c82fa2b8cc306490377fab8f863ea0` |
| BUILD-METADATA.json | `34cfa0b74d1b9fe65b9acc32e121a021394d6a1407ec9c3ec7a44df71dc963dc` |
| UNSIGNED-SHA256SUMS | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |

Snapshot job `113700394739` passed both full repository namespace modes, the
sealed root publication boundary and ordinary/privileged keyring modes, then
signed this child's Phase-A snapshot. Independent transport and public-key
readback passed the exact fourteen-file closure, twelve signed-manifest member
hashes, unchanged trust bytes, build provenance and all three signatures.

| Signed Phase-A object | SHA-256 / identity |
| --- | --- |
| Artifact | `11599438552` |
| Artifact ZIP | `df56323f8b12e9975e3116faf6792cd1d8cb26e2fb3ffb4dfe90f09b9b04b67f` |
| Repository snapshot | `2ca04153f61e5e895ae4a81636cbe393d4bfe4b2eeef86069ff22a8a93d047a9` |
| RELEASE-SHA256SUMS | `e60ee6df0e8699373684ba65dedba18663f1bc939933abdf8e0aea4523f33b59` |
| Snapshot job log | `d9e2535b985809bd34ebf3a4b0deeff1c706f023cecbeb6f70621ace698d50a3` |

Actual Minimal run `minimal-20261009T063441Z-24431663` passed all fourteen
assertions, including installed boot/network, no failed units, plain `pacman -Syu`,
reboot, clean shutdown and image/process cleanup. Independent archive readback
and the production strict `directory_run` consumer passed for this exact child.

| Minimal evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11598854844` |
| Artifact ZIP | `3d9b151c8a7cbe217f493618efd612f44cddb5bfc6ccdca22459b6b07a329109` |
| Evidence archive | `94867fd2de4265c4ac15891e2c36ab8d40391e65f8981bfe8ddae0a93a9794c7` |
| result.json | `2ff4b06eb9a48dd1f3875c3480185989ac6bc136954a56a9d5ae37004d571065` |

Core Stock GNOME with Btrfs/LUKS2/Plymouth/GRUB failed before installer execution:
`luksgrub-20261009T064815Z-f3539f2c`, phase `install-archiso`, exit 1, no assertions.
The host reported `Arch ISO bootstrap did not reach the installer` after its
300-second marker deadline. The final observed serial bytes contained OVMF/ISO
menu output; console handoff means this does not establish a boot-menu hang.
No runtime password was delivered, and no GNOME installation result is implied.
The compact artifact retains no screenshot. Its generated image/process cleanup
receipts remain distinct from the failed bootstrap.

| Failed Stock evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11599694216` |
| Artifact ZIP | `aa7bc1f4195c8f309580df38c06a6e645d30d5ac92a0f7d5b6e356be6bef55c0` |
| Evidence archive | `cd013150b955de415b02e67a0b741df59dce9f6989961620f0e4ed19f723c84e` |
| result.json | `b14c53d9be8df9681feb516bf6ef2deeb1da752207828658fdf76e613f987d77` |
| Job log | `e4d79f48f80c83d9fd0f029cf6d2b68950948eed7d55afa05bb130bc678195dd` |

Transport, safe unpacking and exact source/snapshot identity checks passed;
the result remains FAIL. Core Marble job `113701361591` then failed before VM
launch while preparing authentic legacy AUR inputs. The installer archive guard
used `/usr/bin/python`, which is absent on the Ubuntu runner; the runner provides
`/usr/bin/python3`. The call returned 127, so no Marble VM result or archive was
produced. Its job log SHA-256 is
`6cb769393abd70bc47c0034a8107e16b97242eb43b58bcd893b5d8476e39256a`.
Read-only runner inspection also found Arch's `/usr/lib/libarchive.so` absent;
Ubuntu provides `/usr/lib/x86_64-linux-gnu/libarchive.so.13`. Changing only the
interpreter would not repair the entire guard. The correction uses a separate
pinned Arch verifier and preserves the production installer guard unchanged.
This host-tool failure establishes no GNOME/profile verdict.

Supplemental Stock/ext4 run `stock-20261009T070018Z-1ca6689d` independently failed
in `install-archiso`, exit 1, with no assertions. Safe artifact unpacking and exact
source/snapshot binding passed; the result remains FAIL. A passive QMP frame,
bound to its actual process/socket, showed the fully booted Arch ISO tty1 root
prompt at 95.84 seconds without visible bootstrap output. It supports a missing
console-readiness gate; it does not prove a boot-menu hang or memory-pressure
cause. The frame is diagnostic only, not installation acceptance.

| Supplemental Stock evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11600199867` |
| Artifact ZIP | `51e1f69d77fb82d5afb461129ce681bd94a0ea10bfbd384e6acc6631a8b0e419` |
| Evidence archive | `ebf9ac39e259b41bb34f67a6332ae6ec58b1ca54579a1a95c651bae9b071c90b` |
| result.json | `307ccefddc56a34fa53148be38d6c8850c0af379297fd55f3c91f5aa75837ff2` |
| Passive PPM frame | `2783698be4369684fe78f0ed258ed8d4c22261c52dabc16b555722bf428e2471` |

The workflow is cancelled. Final read-only cleanup found no QEMU referring to
its project evidence prefix, no unreadable QEMU process and no evidence root.
The owned external screenshot temporary directory was removed. Remaining staged
scenarios, Marble migration and public acceptance are pending; latest immutable
publication is still 1.0.6. This matrix cannot finalize or publish, and none of
its results transfer to a corrected source candidate.

The subsequent native Ubuntu adapter check passed four synthetic valid archive
guards and rejected an archive with forbidden extended attributes. Both batches
used separate pinned Arch verifiers, authenticated provisioning, disconnected
network and the unchanged full installer guard. All owned containers and remote
fixtures were removed. This is adapter acceptance, not an actual legacy AUR
build, installed-system result or production signing result.

| Native verifier binding | SHA-256 |
| --- | --- |
| Preparer source | `34ba80de23663c389f90673cabe05a9de435795bcd45ce7adcef4a9f3624c0d8` |
| Unchanged installer | `3d2301282ab1bcf70a55a1c70697342b514cd573c75d8acdcabace79582b1c1f` |
| Unchanged baseline | `d354a97e4348bd75fa51e06a993b1dd6f1ec695d4412c3e5736f93a899fa1e62` |
| Retained native log | `13f85abb95fb32f6d0d836d3d04e2c7bd3df0646a05d61375a221b7ba468f176` |

Boot-only run `bootnonce-20261009T072151Z-626fede9` passed using the exact frozen
readiness/HMP helpers from `run.sh` SHA-256
`1d85c21d81040b066a2148d4b68c01550cebdd8e81bb34507a06ab1786f43644` and the accepted
ISO `684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5`.
The first public nonce executed after the 60-second quiet period but shared a
line with OVMF ANSI output; the exact-line parser correctly rejected it. The
second completed nonce was accepted at boot +84.757 seconds. This experiment
demonstrated no lost input and does not establish the cause of earlier failures.
No installer, bootstrap or credentials were executed. QEMU exit and image check
returned zero; owned processes, sockets, disk, firmware variables, ISO and runner
directory were removed. Independent receipt/file-hash and frozen-function
readback passed. Receipt SHA-256:
`87d2b5466a47c3566b09ec8c1562cf313e257fb545cb18b211e18abbb8d6009a`.

Protected-main [PR #71](https://github.com/snaplyze/arch-linux/pull/71) delivered
both harness fixes. Exact-head [CI 37899088629](https://github.com/snaplyze/arch-linux/actions/runs/37899088629)
passed; its log SHA-256 is
`629c7729a8bd698b943666f6152181af9a40358b92cc93a2392f1e2f80c9882d`.
Accepted head `102a1807ebc5a9b6388d66b571e2b496df22b464` and merged main
`4c50728344ac07f61b90e274855eeecc38a683fe` share tree
`74080fe468a541fddea3edd801af98195d3dba67` and canonical source hash
`c3c0975f869f795c8db5110ca525cabe95a107763a66c0b87819a84c5d1579d0`.
These source and bounded native results do not replace fresh full installation,
signed release and public acceptance for the resulting release child.

Main [CI 37899499406](https://github.com/snaplyze/arch-linux/actions/runs/37899499406)
passed; log SHA-256
`447438896776a0e16bbb2194a1bff35b908ab1da5bf22d4b2817899c0b274e76`.
It triggered [Release 37899808850](https://github.com/snaplyze/arch-linux/actions/runs/37899808850),
whose source transport and deterministic child were independently verified.
Refs, index and dirty document bytes were preserved; actual generated bootstrap
instructions pin 1.0.7. No earlier child VM result applies to this source.

| New candidate binding | Exact identity / SHA-256 |
| --- | --- |
| Origin main | `4c50728344ac07f61b90e274855eeecc38a683fe` |
| Origin tree | `74080fe468a541fddea3edd801af98195d3dba67` |
| Deterministic release child | `018ef177b164c15263afc4904b99c5b826774bdd` |
| Release tree | `ec3b07c9d52d159a63dd02cd6e82cfbe8bf73c83` |
| Canonical release source | `24f3cd89f067cec03dc79d20ce70e7a98281b97ef728d4c4dd19632333e0d4f6` |
| Source artifact | `11601449903` |
| Source transport ZIP | `43cc8347c1f73c9cb65ef1641cb874a986c4bc4331ede49ee92064b5c9158c94` |
| Source bundle | `9345d165621519ce31af386d3c08cdfeaafb398d5432ca4e83ddad928696dda5` |

The child source suite, canonical seven-package build and protected artifact
readback passed. Independent unsigned readback verified the API ZIP digest,
exact sixteen files/fourteen checksum rows, complete schema-2 metadata against
the child source/tree and pinned epoch `1787529600`, and actual package identity,
dependencies, provides/conflicts/replaces, licenses, BUILDINFO and MTREE. It used
read-only child blobs; a validator bound to the different local main tree was
not treated as acceptance of the child.

| Unsigned build binding | SHA-256 / identity |
| --- | --- |
| Artifact | `11601991052` |
| Transport ZIP | `3ae2a0076e6ffaf9a4392a63640956e131cd0b30c2b7299e5a524d48399269ed` |
| BUILD-METADATA.json | `b0d87e7b575ddcd153118b0a7edf959d3361189797164588a7b275c32ddba802` |
| UNSIGNED-SHA256SUMS | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |
| Package set | `6654c025c4b2203597122117a04be4c36df45936fa99764788d5e68c200e4a5a` |

Snapshot job `113721097178` passed both full repository modes (ten scenarios,
signer PASS, exact 14/18 closures, no deferrals), the root publication boundary
and ordinary/privileged keyring modes before production signing. Independent
artifact readback verified exact fourteen files, twelve manifest rows, unchanged
source/trust/build bytes, three signatures from the pinned signing subkey and
the production snapshot contract's 25 objects.

| Signed staging binding | SHA-256 / identity |
| --- | --- |
| Phase-A artifact | `11602561385` |
| Transport ZIP | `d06f824c8440e8aa87614153662181807b651839ddd9ce4ae06ae65f67d54380` |
| Repository snapshot | `1034d8bc558f5226a5dcc3b15b131ff20d6af97c108fe928132b71b6346dc42c` |
| RELEASE-SHA256SUMS | `8f6888f968d173d8be60146037e0e93ed3e803d3f1fcb919b9ce211e830eb130` |
| Snapshot job log | `e005bd14a393d9b574fbe3473dd013780d8715f4ef28ac682e7c18b7cedae372` |

Fresh Minimal run `minimal-20261009T074530Z-b1c03967` passed all fourteen assertions:
the actual installer exited zero, the installed system booted, network and units
passed, plain `pacman -Syu` succeeded, reboot changed its boot ID, and shutdown,
image check and owned-process cleanup passed. Independent retained-artifact
readback and the production strict `directory_run` consumer passed for this
exact source, build and signed snapshot.

| Minimal evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11601873555` |
| Transport ZIP | `f0f97d8dec312b4451038d6ae480b13753e1d8d9b8704376defd311928cbfb33` |
| Evidence archive | `42bca945cf40a05a9d278cf109e801d9017e96760020c53b774f761e1a72f6a0` |
| result.json | `330768216db92f44e13c301c717d453dbbe190a10d393de682da5becd53f0f05` |

Core Stock run `luksgrub-20261009T075431Z-677a4ce8` failed in `install-archiso`
with no assertions. Its retained log contains the complete bound READY record,
`LUKSGRUB_QEMU_INSTALLER_EXIT status=1` and the corresponding installer failure
marker. Thus bootstrap readiness succeeded and the installer itself failed; the
host's two-hour message was misleading on early shutdown. No specific underlying
installation cause is established by the compact `unclassified` diagnostic.
The owned run directory, sockets and exact QEMU process were confirmed absent.

| Failed Stock evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11602473477` |
| Transport ZIP | `b1659176f29087618b7f3a4d427c8b021c55eb9d261cac3b04fc912e28835588` |
| Evidence archive | `ef30e64f7e4b1c51a06a3ef72a434d2b3876150806d9a9ab9d585f4d551769b0` |
| result.json | `f1bc86a1fac7c5508a4832efe156b65198da1004cce0d3751eeeb3cb1b9c7c39` |
| Job log | `17c6013568160e184d35498b16d6bc6545ae6c8a1e6ca78453b892b4849902a8` |

A bounded runner kernel-journal query for 08:00–08:03 UTC returned no records;
this provides no positive OOM evidence and cannot rule out an unrecorded event.
A local nested-function reproduction independently found that the unquoted ERR
trap stack shifted the line argument (`line outer`). The correction preserves
numeric line, complete stack and exit status without retaining extra raw data.
Harness outcome regressions distinguish reported installer failure, guest/bridge
termination and deadline. These diagnostic fixes do not establish the cause or
repair of this installation failure.

Core Marble run `marble-20261009T080614Z-c46c195d` likewise failed in
`install-archiso` with no assertions, after its exact bound READY record and with
`MARBLE_QEMU_INSTALLER_EXIT status=1`. Legacy AUR package preparation and the
separate Arch verifier progressed successfully to the actual VM, so the former
Ubuntu interpreter/library boundary did not recur. Compact diagnostics do not
identify the underlying installation cause. Its owned run directory, sockets and
exact QEMU process were confirmed absent.

| Failed Marble evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11603670955` |
| Transport ZIP | `f7059f67583188d484b70c5a39c817f04ae0b816081f9f7eef2528ca252d8774` |
| Evidence archive | `df87e8505974028c4cf86d3e3c91128936656b8f6c5b0df1f6cbb9260910ffe7` |
| result.json | `9f4a633902a36b60d38af85ef1771711b65f076818a6b6ce6986ffc1bc70ef2c` |
| Job log | `922f30e98a98bb3080174e8533301301a385f3f3f85d8483a40702f62fdd33b3` |

Supplemental Stock/ext4 run `stock-20261009T081505Z-214caad6` also exited 1
during `install-archiso`, with no assertions. Independent transport/source/build/
snapshot binding checks passed; this is failed evidence, not runtime acceptance.

| Failed Stock/ext4 evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11604007327` |
| Transport ZIP | `673482e5a9ea8cdf5887f161137078202d48f2865e6a8bb0b459cde14b0417f1` |
| Evidence archive | `a06e8f91cdb76592e700802b3d60f7e14c7b72fff251ae30133976e670740dfe` |
| result.json | `352012cf9463808cbe7edc8b64abb667ec275381ad9a3b2ed12dbc089676d2fe` |

A read-only observer bound to this exact release source/installer captured
status `1`, function `exec_install_desktop`, and malformed line/caller `main`
before normal raw-log compaction. Only allowlisted function/status fields were
retained. This rules out a failure confined to Btrfs/LUKS, but does not yet identify
the failing desktop command. Remaining staged cases, migration/appearance and
public acceptance are pending. The failed matrix cannot finalize or publish.

Supplemental Stock/Btrfs/systemd-boot run `btrfs-20261009T082358Z-3bc6e0b2`
also failed during `install-archiso`, with no assertions. Independent transport
and source/build/snapshot binding passed. The live observer again captured
`exec_install_desktop` / status `1` / malformed caller `main`; its command did not
match a single desktop source statement, so no command identity is claimed.

| Failed Stock/Btrfs evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11604576165` |
| Transport ZIP | `59f413e39e8bfc9c2f7c68cb163f08bd9947da53317520d229e9120cad590588` |
| Evidence archive | `948afea8f16a91805bf6451fb50504af05cfc50324ffe472e46da02407a2e11e` |
| result.json | `2feb83e67b63786357a201375cf76caff9ebe6f3fff30037bbf014e96b95ab7f` |

Separately, public `git ls-remote` probes of the pinned Bibata AUR repository on
the workstation and runner failed TLS negotiation at approximately 08:38 UTC
(OpenSSL unexpected EOF / GnuTLS non-proper termination). The runner probe used
an empty Git configuration and disabled credential prompting. This establishes a
transport failure at probe time, not the cause of an earlier VM installation.

Plain Btrfs/GRUB run `grub-20261009T083429Z-15bd385a` also failed during
`install-archiso` with no assertions. Early live observation identified `return 1`
in `exec_install_desktop` and a curl diagnostic, but preceded final log replay;
it cannot identify the failed package or transport. The following encrypted Stock
run `luks-20261009T084314Z-1bb69772` failed earlier in `exec_install_bootsplash`.
An observer waited for its exact final-log END marker and captured AUR TLS EOF /
`fatal: unable to access`, four retries replayed twice, and no pacman or signed
repository retries. This establishes AUR recipe transport failure for that run.
Both artifacts passed independent transport and source/build/snapshot binding.

| Failed supplemental evidence | Plain Btrfs/GRUB | Encrypted Btrfs/systemd-boot |
| --- | --- | --- |
| Artifact | `11604403130` | `11604529820` |
| Transport ZIP | `75dde24eaf336d49eee9522da185ffad8fe77a6c511c5da41946455c9b109ba1` | `8a1b8805641daeab26ec69c1f80c494d042862ffd853d617786ca7b2fd4d9815` |
| Evidence archive | `99bf8d26c3bf2312952fa7a9bc8888d6a22f63e5da779594b36c0b2f3e1fdee7` | `ac5604ab6258a46f70829850a0c1c58a2417f39477770dea30c6610e0976256d` |
| result.json | `c7813a138164ad097cafb8786b432183a593185d2cdbda8cf76f278e131d61ea` | `0b3cb4dd2ed9cd45dc8a3ec5eddef92ddd31bf3fea18cc4555f000f680ce6052` |

Workflow 37899808850 is terminal CANCELLED. The remaining Marble/Stock-GDM job
was interrupted during input preparation and dual boot did not execute. Cancellation
API readback SHA-256: `99587aace659fb978a0c6762b3d33378678806997f0c52a60a70c6afd2ceec98`.
No project QEMU process, evidence run directory or GNOME-input builder/verifier
container remained after cancellation. Latest public release remains 1.0.6; no
1.0.7 tag, release or Pages publication was produced by this failed candidate.

The focused correction adds the official Arch read-only mirror only after a failed
AUR clone, in the same unprivileged scope and a separate attempt directory. All
existing recipe and output pins remain mandatory. Executed fixture transport /
real Git identity tests and independent review passed; real installation with the
new fallback remains pending. Git/TLS failure classification and early-installer
outcome handling now have regressions that preserve only typed nonsecret metadata.
Native transport-only verification cloned the actual official mirror package
branches for `bibata-cursor-theme-bin` and `plymouth-theme-archlinux`, checked out
their existing commits, and verified Git archive, SRCINFO and the installer's
actual pure hardening output against every pin. Git configuration/hooks were
isolated; both operations had a 120-second deadline. No PKGBUILD, package build
or VM executed, and owned recipe inputs were removed. Installer binding:
`da938ece6a946b69b33b6b9fd91abf6b380906cae8c5ede59f1cc1188ae5ff0f`;
receipt SHA-256: `b06fee0370385cca151eb44a1a275f534470cd15145e321f146ee8147cf37c0a`.
The corrected source passed `bash tests/source-tests.sh`, including the full
namespace result (10 scenarios, signer passed, 14+18 closures, no deferrals);
log SHA-256: `dd8054d820d2561f8c4b66c6b24ab48f86c41cd88fbff31d07c915c27cf69e9c`.
Independent fallback and diagnostic reviews reported no material findings. These
local source/transport results do not establish a successful installation or
publication. Exact protected PR CI and the fresh release child remain pending.

[PR #72](https://github.com/snaplyze/arch-linux/pull/72) subsequently passed
[CI 37908363960](https://github.com/snaplyze/arch-linux/actions/runs/37908363960)
for exact head `30e623d54696536cc19954ae6be35c8592a40588`; CI log SHA-256
`58d433b501f3cd4cf3b0702d67aa4adb71250906c4fbf65d996fd83b4a3f593f`.
Protected squash merge produced main `168f3eb41beff0e0b7de8c6bf1a41dabb576d60c`.
Both commits share tree `5b6af7369af8370e9415811c4872499fda06cba3` and canonical
source SHA-256 `07cfbf9fe946835ff6c1c53edcff7027a9f95ea72724f7e8f579f7993e9f38e8`.
The sole canonical checkout returned to main by fast-forward and these identities
were independently verified.
[Main CI 37908778844](https://github.com/snaplyze/arch-linux/actions/runs/37908778844)
passed; log SHA-256:
`1936ae3c601990ef663e893b4ab1c14e92cad34769001921f1a5c244a32f514a`.
It triggered [Release 37909100627](https://github.com/snaplyze/arch-linux/actions/runs/37909100627).
Independent source transport, bundle and deterministic transformation verification
passed. Actual generated README / installation instructions pin 1.0.7; local refs,
index and dirty documents were preserved. No previous child result applies.

| New candidate binding | Exact identity / SHA-256 |
| --- | --- |
| Origin main | `168f3eb41beff0e0b7de8c6bf1a41dabb576d60c` |
| Origin tree | `5b6af7369af8370e9415811c4872499fda06cba3` |
| Deterministic release child | `8ad8ef1ca1cada7398fbb825f856661503912bd8` |
| Release tree | `eda0102dd1a65f60e37d581e04988d199e67f59b` |
| Canonical release source | `2e53fa77f70848a2e7be78435251b858d5f71a3435ec0863d13af3d3eb7f8213` |
| Source artifact | `11604824811` |
| Source transport ZIP | `8cabfac7e8b321d117c8524d2bd290e7c78c61452b887dd4813cc3312d6d3b43` |
| Source bundle | `2ee96e66b904c52073f32d950525288f40714c56d043c167d96f28739681838e` |

The clean seven-package build passed. Independent unsigned readback verified the
API transport digest, exact sixteen-file closure, fourteen manifest rows, schema-2
metadata and pinned epoch `1787529600`. Actual PKGINFO/BUILDINFO/MTREE were compared
with the exact child SRCINFO. A temporary source export was first checked against
the child's complete Git file/mode/byte closure, made read-only, and used to run
the unchanged production package validator for all seven packages; all passed.
That export was removed afterward. The unsigned shell verifier was not claimed
for this independent export because it has no Git identity; its source/manifest
bindings were checked separately. Equal package bytes to an earlier build do not
replace the newly verified BUILD metadata binding.

| Unsigned build evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11605768729` |
| Transport ZIP | `e49bdd371e336a85fd5ddb9590f13e4b410f870beb47a319658db14de2c516f9` |
| BUILD-METADATA.json | `25e9768bb91a514ec7fa9be81a658b357c46b6b4d17d82dd7480143702d542c0` |
| UNSIGNED-SHA256SUMS | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |
| Package set | `6654c025c4b2203597122117a04be4c36df45936fa99764788d5e68c200e4a5a` |
| Child installer | `389598dabc68c4f3d3fca1cf220fa7a60ee54ea20284e8e63b275cb24c2027e2` |

Protected unsigned readback and Phase-A signing passed for this child. Independent
root readback verified the API transport digest, exact fourteen-file closure,
twelve signed manifest rows, three detached signatures and byte identity of the
source/bootstrap/trust/build inputs. The production snapshot contract verified
twenty-five repository objects. Signing used the existing authorized subkey and
did not publish a release.

| Signed Phase-A evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11606073320` |
| Transport ZIP | `edc61e7ca61ea08180ebd0dcb5dfb15f166d7399e27343fa38df80aaff094b7f` |
| Repository snapshot | `2a06fb9a979c04d0bcd8cffb6c5fc530dfd32287d7defe963898d76f7e6abd25` |
| RELEASE-SHA256SUMS | `0d38dc8f4020fc7bc2552b6bc3f6af3661a0c4981e8c82ae42b403a3ce36f246` |

The signing job's complete log independently confirms unflagged/full repository
checks with ten scenarios, signer PASS, exact 14/18 closures and no deferrals;
the root publication boundary with four namespaces; ordinary keyring mode and
the full privileged keyring mode. Log SHA-256:
`2321cb7c24f93666623718403c64244ddc51e5b39f662a6449552f3110dfde82`.

The fresh staged Minimal TTY run `minimal-20261009T091559Z-d577c657` passed
fourteen assertions, including actual installation, plain `pacman -Syu`, another
boot, no failed units, clean shutdown and disk integrity. Independent readback
matched this child's exact source/build/snapshot bindings and the unchanged
production `directory_run` consumer passed. Artifact `11606695634` has transport
SHA-256 `e4b2ad9d8b7b476a4d9e66bdaa55cbd7516f609b9d55c333b3226ae8e84d4bb2`,
archive `9cd12c2167b312c491baf5786bb326fe0eda2789ac1d67c51518cae788a00f22`
and result JSON `3707cd1f5246a81cb9a23be256540df478e06ba61f7e5b96f45b94bb3a5a077e`.

The fresh Stock LUKS/GRUB run `luksgrub-20261009T092345Z-8196defb` failed
during `install-archiso`, with installer exit 1 and no accepted assertions. The
retained compact diagnostic reports `download` and `script-error line=4895
status=1`. A bounded passive final-log observer identifies the stack
`exec_install_bootsplash main main`, the Plymouth AUR call and five exhausted
attempts; TLS errors are present. This does not identify whether the mirror
transport, a later builder boundary or the package build failed. Subsequent
bounded passive observation of Marble run `marble-20261009T093657Z-c35c70ab`
found the source-defined warning at line 6885 specifically naming
`plymouth-theme-archlinux`: no validated package was accepted. That observation
was made before the final installer log and is not a completed VM result.
Artifact `11606907459` has transport SHA-256
`8d1a94e572fc06a8a39cb40934602fea669288f7f63a1948b9a538bfb3e108ac`,
archive `b74aa6da037f4e849a500dd2346ea3297ed92832b8ca56dd3f010ab76c9342b7`
and result JSON `9673fc4929f94352b4d45558bdf19bc5addb7778541beb59181c3db967e1556d`.
The readback helper deliberately rejected its non-PASS result after independently
checking source/build/snapshot bindings; that rejection is not a second failure.

The workflow was cancelled after the rejecting path boundary was reproduced.
Cancellation readback SHA-256:
`effc84e622a257d23dc6d2c5b2f2ab6cdf88da3460667454848a787ad48af4d3`.
The interrupted Marble run and six queued scenarios establish no
acceptance. Finalization, immutable publication, Pages/public readback and the
public Marble VM remain pending; no old VM result transfers. Public latest
remains 1.0.6.

Private workstation resolution against this exact signed snapshot passed with
the current local package database and existing official sync databases. The
print-only command used private config, database, cache, hook, public-keyring and
log paths with `--debug --noconfirm -Sup --print-format '%r/%n %v'`; it performed
no sync or transaction. Strict project policy remained `PackageRequired
DatabaseRequired TrustedOnly`; detached signatures for all seven packages and
the repository database were verified against the actual copied public keyring.
Pacman selected Colloid GTK `20260808-11`, icons `20260829-7`, extensions
`1.0.0-7`, keyring `1.0.0-9`, GDM `50.0.0-10`, profile `1.0.0-12` and Shell
`50.0.0-8`. Libalpm debug confirmed all four installed AUR extension owners
(Dash, Blur, Clipboard and Just Perfection) on the remove list without manual
uninstall. Host local-database hashes stayed unchanged and both owned fixture
trees were removed. Compact receipt SHA-256:
`ddf9361df3d1f6c92eb9d5ed9e31c592ad3cc681a8d9817f74a76c25254ad43c`.
This establishes dependency/replacement resolution only, not package delivery,
signature checking by an executed transaction, installation or session behavior.

### Mirror build output correction

The actual production `aur_package_output_path_is_safe` rejects
`src-plymouth-theme-archlinux-1-mirror/...pkg.tar.zst` and accepts
`src-plymouth-theme-archlinux-mirror-1/...pkg.tar.zst`. The newly introduced mirror
directory therefore prevented successful builds from reaching archive validation.
The original transport fixture stopped after immutable source identity and missed
this downstream path contract. The focused one-line correction preserves that
predicate and the exact canonical containment check while placing `mirror` before
the bounded attempt number.

The transport fixture now passes its actual selected directory through the
production package-output predicate for primary and mirror success. Six negative
cases retain rejection of attempts 0/6, the old suffix, nesting, traversal and the
wrong archive extension. `bash tests/function-checks.sh` failed on the unchanged
installer at the path predicate and passed after the correction. Red log SHA-256:
`148a4ff9cc898274e5a7ce56ac489a941bc8960135dcae09c1ce68a3b50981b5`;
green log SHA-256:
`4adf519549d53685d755e06cc1179b90ad94039bd4871ee2699df12ef6d55640`.
Independent review found no material issue. `PYTHONDONTWRITEBYTECODE=1 bash
tests/source-tests.sh` passed, including full repository namespaces, ten scenarios,
signer PASS, exact 14/18 closures and no deferrals. Source log SHA-256:
`7e5f7d66e8918d6fcc6f32808bcbecbd9e72760a36c4f00a148a4a3ca1c7ea79`.
Documentation/agent-contract checks and `git diff --check` passed separately.
After workflow cleanup the runner had zero project QEMU processes, zero current
evidence runs and zero active private-Docker containers. The exact owned observer
was stopped only after command-identity verification. The new protected
candidate/build/signature/VM/publication gates remain pending.

[PR #73](https://github.com/snaplyze/arch-linux/pull/73) subsequently passed
[CI 37913814911](https://github.com/snaplyze/arch-linux/actions/runs/37913814911)
for exact head `5ea2c38078a447fd56866bcb4e536c9e29f338fd`; CI log SHA-256
`4eb7fc16ae282c702059800d8eff6e55de5df20f9f112d43eddde954b1366e96`.
Protected squash merge produced main `cadd63d6b9191e928182f70d3cd2aa1cffffcb36`.
Both commits share tree `ef4b7a2376a5c7600a515715eb1c0b9a7b8fe127` and canonical
source SHA-256 `ed99ddbc6de359d8b27ff8b079989f2f5863d41def6a2d80b7a3c6845af46f1b`.
The canonical checkout returned to main by fast-forward; all three identities
were independently verified.
[Main CI 37914195356](https://github.com/snaplyze/arch-linux/actions/runs/37914195356)
passed, log SHA-256
`6fe9bfe2ca02eff3b1d30b0f721c06369edff3756de58a24d5502de689569282`,
and triggered [Release 37914520768](https://github.com/snaplyze/arch-linux/actions/runs/37914520768).
Independent source artifact transport, bundle and deterministic transformation
checks passed. Generated README / installation instructions pin 1.0.7; local
refs/index/dirty documents were preserved.

| Corrected child binding | Exact identity / SHA-256 |
| --- | --- |
| Origin main | `cadd63d6b9191e928182f70d3cd2aa1cffffcb36` |
| Origin tree | `ef4b7a2376a5c7600a515715eb1c0b9a7b8fe127` |
| Deterministic release child | `35ff8df8951a4e0a7d9f2e8a70c68027573ee62a` |
| Release tree | `58395adfbf7df2ab2246bc8a1ba0136af2ef2637` |
| Canonical release source | `bcdc8fdd2ef4ab86c3b3efcc16322fc0ec6f4c3b6e3ac6750ceba7b5540172fd` |
| Source artifact | `11609550603` |
| Source transport ZIP | `1af22ca4280c6a7b0076254cf97604bfa2d27cd8e879f88523b9c6c32f6190c4` |
| Source bundle | `4eca267a05133e925c76392244b5a2db93bd30ebeba62a666f54483907f74f9b` |

The fresh clean seven-package build passed. Independent unsigned readback checked
the API ZIP digest, exact sixteen-file closure, fourteen manifest rows, canonical
schema-2 BUILD source binding and pinned epoch `1787529600`. Actual
PKGINFO/BUILDINFO/MTREE and SRCINFO comparisons passed. All seven unchanged
production package validators passed against a read-only exact-child export whose
full file/mode/byte closure was checked before use; that export was removed.
The unsigned shell entrypoint was not claimed for the export without Git metadata;
its identity/manifest bindings were independently checked. Package revisions are
the same seven recorded above, but the BUILD binding was verified afresh.

| Corrected unsigned evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11609866188` |
| Transport ZIP | `f369ecbefc1fc5d161a6361261f38efb4abada8ac2585ac53a685b0f6a41fdd5` |
| BUILD-METADATA.json | `98b3e03e720a4ac76dc0372817a50f05989cd458491adb52fbf6e283c6e6e295` |
| UNSIGNED-SHA256SUMS | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |
| Package set | `6654c025c4b2203597122117a04be4c36df45936fa99764788d5e68c200e4a5a` |
| Child installer | `e6228b0f655d5551eaf5cc8d085ea8111b24df3930b27cc78700d0944432ff71` |

Protected unsigned readback and Phase-A signing passed for this corrected child.
Independent root readback verified exact fourteen-file closure, twelve signed
manifest rows, three detached signatures, source/trust/build byte identity and
the production snapshot contract's twenty-five repository objects.

| Corrected signed Phase-A evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11609936947` |
| Transport ZIP | `0daad30b7a4128c8af3a262ea1819276a5a57bfb906d6cb50d749bd6b91a31db` |
| Repository snapshot | `3b575cea722e9b466199c02c3f3b780862eb154cc70371937c0c5cb98fba8d05` |
| RELEASE-SHA256SUMS | `78b2ee95cae252a1004597bd7eaf050fdc4f203bc45930a7fc28983e69135301` |
| Complete signing-job log | `43ebf3a99b866857704a0fcb3d688f252a7edf824588276990241e8ded5378f3` |

The complete log confirms both repository modes with full namespaces, ten
scenarios, signer PASS, exact 14/18 closures and no deferrals; the four-namespace
root publication boundary; ordinary keyring mode and the full privileged mode.
Fresh Minimal TTY run `minimal-20261009T100800Z-cf218bc1` passed all fourteen
assertions. Independent readback checked exact source/build/snapshot bindings and
the production `directory_run` consumer passed. Artifact `11609224009` has
transport SHA-256 `7c6147e6adfbb953ea1e4fe5e43848816dc585325be0622f77b815a7fba42c8a`,
archive `0daaffe5f3d6a9840ff685b196bb967d44c3e77da7b57664e04772b24cc52039`
and result JSON `744990f5463b4f374ad9fff030ad8053e327c42375c6ee194e8d18f75c0decfe`.
The run includes actual installation, plain `pacman -Syu`, another boot, no failed
units, clean shutdown and final disk integrity.
The subsequent Stock runtime outcome and strict-consumer rejection are recorded
below. Other staged results, finalization, immutable publication, Pages/public
readback and the public Marble VM remain pending. No result from child `8ad8ef1`
transfers to this corrected child.

Bounded passive readback of Stock run `luksgrub-20261009T101639Z-5fff4e42`
observed both corrected Plymouth/Bibata mirror paths and successful installer
Bootsplash, GNOME Desktop and Finalize Arch Linux markers. The VM reached the
installed desktop. This records progress beyond the previously rejecting step,
not completion of the session/update/reboot checks or full VM/GNOME acceptance.
Compact observation SHA-256:
`065b3fdcfacc44f8982164923f2eead7e02736685a5192e5ec017407cd8eb18c`.

Stock run `luksgrub-20261009T101639Z-5fff4e42` subsequently passed all 22 runtime
assertions, including real password login, lock/unlock, plain `pacman -Syu`,
encrypted GRUB reboot, package integrity and clean shutdown/disk checks.
Independent transport/source/build/snapshot readback passed, but the unchanged
strict consumer rejected the retained evidence closure: its sole extra file was
`repository-runtime.sha256`. Direct invocation of the identity validator also
reproduced `QEMU identity contains an unexpected row` for the actual final
`repository_server_port` row. The producer emits both for Stock's new signed
repository; the consumer still restricts them to Marble. Runtime PASS therefore
does not establish accepted evidence or release readiness.

| Stock runtime / rejected consumer evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11610472570` |
| Transport ZIP | `faab46c674f19e284fd5ba1e574a1b37568c9ece09f640d499e024504c36aad0` |
| Archive | `e6dccca2da39a3e89c61e492235c70b7bd55232f5a3c5ea6f83fe8f98e2bca5d` |
| Result JSON | `42bf26f6445dbf43a4f966d60b88b2298dd45dc5ef56219f20a6c3da8baeb39b` |

The focused correction requires and validates both runtime bindings for Stock
and Marble, retains Marble-only legacy/migration evidence and keeps Minimal's
rejection of repository-runtime extras. Three focused regression tests failed
against the old consumer and passed after the correction. Missing, malformed,
zero, reordered or extra runtime rows; missing/invalid/duplicate ports; Stock
migration extras; and Minimal repository extras remain rejected. Both complete
repository/publication fixture builders and the static identity fixture were
updated. Independent review found no material issue.

The corrected full `directory_run` consumer passed against the actual retained
Stock artifact. This is a debug replay under working consumer SHA-256
`ed131e3312b0fd846a4affb3866fb3a7c36aad17af1966849b06fe467de5e522`,
not acceptance of a new source child or a replacement of the old failure.
Replay receipt SHA-256:
`32f93ab4b8f6c438cd8800c15f10fa75bb82409584f4822eee9a4216532b7df0`.

`python3 tests/actions-release-checks.py` passed all 28 tests; static checks,
Bash syntax, ShellCheck and `git diff --check` passed. The ordinary repository
run exercised full namespaces, ten scenarios, signer PASS, exact 14/18 closures
and no deferrals. Its log SHA-256 is
`20ac7e16a11df7423a9db707de8b6093b64bf2bc95750c94c47a9094b8902930`.
Before the following legacy-session harness correction,
`PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` passed; log SHA-256
`020be0d06495ab5165bee052e37110cf7f6d0872f927ce3ab17f2ff94922abcc`.
A fresh privileged root publication run
remains required for the changed fixture; local source/ordinary checks do not
establish that gate. No result will transfer to a new source child.

Marble run `marble-20261009T103634Z-0f756344` subsequently failed during
`legacy-login` after four successful assertions. Installation, encrypted unlock,
initial GDM prelogin and signed legacy package installation succeeded; the compact
guest diagnostic records runtime line 3861/status 1. The full job log identifies
the failing phase. Later legacy migration, GNOME 51 recovery and extension
functional acceptance were not reached. Initial GDM screenshot readback shows
the composed greeter, but does not establish the later desktop/migration gates.

| Marble failure evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11610869843` |
| Transport ZIP | `56c17c00c5d4f6480b10ab9c50a0b214ce87cbdfd6c34f0f89f237b75c09164a` |
| Archive | `fcddf92226c7b1e40f6957f7aeb5195266fff136d8196b63a4d0fec4234b51e2` |
| Result JSON | `e256b6e8bfbe80918779cbe3ed36687b1f81b9c01ca15fe06665c4b55399333c` |
| Complete job log | `b59cd9547f2bd34f606ba07b0f307dec827983e5cbf4a3916d90c47f94ca5db5` |

Release 37914520768 is cancelled before finalization or publication. Interrupted
and unrun scenarios establish no acceptance. Root cleanup readback found zero
project QEMU processes, zero current evidence runs and zero active private-Docker
containers. The exact owned passive observer was stopped only after command
identity verification. No tag, release asset or Pages publication was changed.

Exact QGA composition prepends ten lines, mapping runtime 3861 to the frozen
`verify_legacy_user_session` GTK-theme assertion at source line 3851. The exact
legacy manifest binds release 1.0.3, source
`bc7147f1fe42a0d406adf75448c3f63fa127b4bc`, profile `1.0.0-4` and GTK3
`20260808-4`. That profile's supported-major file contains only 50; its helper
successfully removes the owned alias/defaults for an unsupported major. The
failed VM proves the Colloid equality did not hold, but does not retain the
actual GTK value. The harness correction therefore requires the supported
Colloid baseline on 50, or Adwaita and absent project alias/defaults on 51;
unknown majors fail. Existing real GDM/Wayland, UID, exact package-version and
GTK4 wrapper absence checks remain. The subsequent candidate session must still
activate Marble and GTK4 normally; no product compatibility or preference-reset
change is involved.

Three executed session regressions failed on five old-code cases. An intermediate
run additionally exposed Bash errexit's compound-condition exemption: an existing
regular activation file could pass the loop. The final predicate explicitly
returns failure for existing files or symlinks. All three focused regressions and
all 134 guest runtime tests pass; runtime log SHA-256
`1c4687ed3ea743128eb695ddeeec2333e2376e9911894a55c5d6e4c39e9d448f`.
The complete `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` also passed,
including full repository namespaces, ten scenarios, signer PASS, exact 14/18
closures and no deferrals. Independent review found no material issue. A new
installed Marble run and downstream privileged/public gates remain required;
none of these source fixtures is a VM verdict.

The final `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` passed after
reconciling the failure records and testing documentation; log SHA-256
`50f502bd6ca943f816a181559ca95b8547126d1ae252c7e4c935eaadf7e0a0d3`.
[PR #74](https://github.com/snaplyze/arch-linux/pull/74) passed exact-head
[CI 37921242937](https://github.com/snaplyze/arch-linux/actions/runs/37921242937)
for accepted head `c0a56659a222420dcef1fff34357b60b82e19543`; CI log SHA-256
`4ea111b627870b74f15cdd34390bcf844d651285a4494ba4d288d4dac26c1199`.
Protected squash merge produced main `b10e1158824d8191640f22b4a9f8e591aa59be92`.
Both commits share tree `485c84c5fd7845ca8b62ccd0a528b40bebf086b6` and canonical
source SHA-256 `108d566251c4bfc25c6880e9dc7443c01d4fe3b29fba0ebb0c8a4c05374e46c4`.
The same checkout returned to main by fast-forward and independently verified
those identities.
[Main CI 37921663176](https://github.com/snaplyze/arch-linux/actions/runs/37921663176)
passed, log SHA-256
`ddfe3fa91f9c9a99ea3beb5f98e212e90f7a1597ac96e9a9241dee3e8849185e`,
and triggered [Release 37921973159](https://github.com/snaplyze/arch-linux/actions/runs/37921973159).
No earlier build or VM result is transferred to the new release child.

Independent source transport, bundle and deterministic transformation checks
passed for the new child. Generated README/installation instructions pin 1.0.7
and the release overview is rendered for that version. Canonical refs, index and
the dirty checkpoint documents were preserved during readback.

| Consumer/baseline corrected child | Exact identity / SHA-256 |
| --- | --- |
| Origin main | `b10e1158824d8191640f22b4a9f8e591aa59be92` |
| Origin tree | `485c84c5fd7845ca8b62ccd0a528b40bebf086b6` |
| Release child | `a35fa3e7f238e4c3f3d675eed7c346e1d536c2d6` |
| Release tree | `e1a15708f2ef8b4bb69731a375c978c8bcaf7b93` |
| Canonical release source | `b5cd21912b4b33a5f05c635861925f3da5085f963731d7c9add59dd709cdc51c` |
| Source artifact | `11611603725` |
| Source transport ZIP | `3dc5da88ab799ea9812efc679aca295bc37709cc706a675023a59c1cf3831703` |
| Source bundle | `4810bce49cd18039324971bd33e694a14b28a5f75b7dbc168fc4e1d77ff9a258` |

The clean seven-package build and protected artifact readback passed. Independent
unsigned readback verified the API ZIP digest, exact sixteen-file closure,
fourteen unsigned rows, canonical schema-2 source binding and pinned epoch
`1787529600`. All seven PKGINFO/BUILDINFO/SRCINFO and PKGBUILD digest comparisons
passed, as did 19,564 MTREE file size/hash comparisons. All seven unchanged
production payload validators passed against the full Git-blob/mode/closure and
canonical-hash-verified read-only exact-child export, removed afterward. This is
scoped readback, not a claim that the full Git-bound unsigned shell entrypoint ran
against the export without Git metadata. Protected CI readback passed separately.
The seven package versions are unchanged from the preceding candidate, but their
new BUILD binding and retained bytes were checked afresh.

| New unsigned readback | SHA-256 / identity |
| --- | --- |
| Artifact | `11612443048` |
| Transport ZIP | `9d1043938fb5156147c64ffadf6417077598347ea031e350040d8abb4101620a` |
| BUILD-METADATA.json | `ea4d1475f233b72c966353c323f5412e5fbe989b11d01efb12813c4567c95d7d` |
| UNSIGNED-SHA256SUMS | `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37` |
| Scoped independent receipt | `1716b1fdcb6de35302716aeebf212a51abe27d7d40e8fad18449dcf0f3fe8b9b` |

Phase-A signing passed. Independent transport and signature readback verified
the exact fourteen-file closure, twelve signed manifest rows, three detached
signatures and all twenty-five repository objects against this child's source,
build and unsigned inputs.

| New signed Phase-A readback | SHA-256 / identity |
| --- | --- |
| Artifact | `11612224733` |
| Transport ZIP | `bbcff4f064e67f4ada7d7ca07dad4daf1ab7ff84bfeb2f493bdd1e3e00bebec1` |
| Repository snapshot | `df8a056a3e54fcd8f580466f4965ca3c031a6c56094d7bfaba78ef667194b68e` |
| RELEASE-SHA256SUMS | `ed90641907fc5d531067770bc2924b6e14b04509a3939c19a485ac7bea83b73e` |
| Complete signing-job log | `1d0388f9c38f165b3a2b22284e4c0397d120c50e370889a8e4a3eb148117c68a` |

The complete log independently confirms unflagged and explicit full repository
modes with ten scenarios, signer PASS, exact 14/18 closures and no deferrals;
the corrected root publication fixture with all four namespaces and no deferrals;
ordinary keyring mode and the separate full privileged keyring mode. These are
fresh executions for this child, including the changed Stock runtime fixture.
The staged VM matrix is running. Finalization, publication, Pages/public readback
and the public Marble VM remain open.

The new child's `minimal-ext4-systemdboot` run
`minimal-20261009T111955Z-7432e167` passed all fourteen runtime assertions.
Independent API transport, exact source/build/snapshot binding and the frozen
`a35fa3e7` strict core consumer also passed. No GNOME or publication acceptance
follows from this Minimal result.

| New Minimal VM evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11613985216` |
| Transport ZIP | `5b97bd51236295c4d94ec736266870866853974a83fcb38e0a0182c6a85e2435` |
| Evidence archive | `5f3d6e76be2fbf660f84335c90774e18d395dc5b4de235a4beb64181ec47253b` |
| Result JSON | `591540d88021dd7f337d3826b4c95eeb2b9c0ea81422f29b0ddda9040abaae8e` |

The current child's `stock-gnome-btrfs-luks2-plymouth-grub` run
`luksgrub-20261009T113627Z-bcd8ac14` subsequently passed all twenty-two assertions,
including real GDM password login, lock/unlock, update and another boot.
Independent API transport/source/build/snapshot readback and the frozen strict
core consumer passed, exercising the corrected Stock runtime-manifest and port
identity contract. The Marble upgrade and publication gates are still open.

| New Stock VM evidence | SHA-256 / identity |
| --- | --- |
| Artifact | `11613678217` |
| Transport ZIP | `0d1ce7d2a6f48fe6740d3033578fe641bcc273a7cb211cf360698464100dbd48` |
| Evidence archive | `17f7a55d591d77555c987c3861ab5f468744bb9afcf61c7fc9eeb5c8a3a11914` |
| Result JSON | `ca372005c5fa1ddc34e33c78d71d0839f7063a441703b48826b4c729732e0463` |

Core Marble subsequently failed in run `marble-20261009T115401Z-7138c8f4`, phase
`install-archiso`, with zero completed runtime assertions. Job 113794670441 reports
`Arch ISO bootstrap did not reach the installer` at 12:01:24 UTC: the host did not
observe the expected readiness marker, so credential delivery never ran. During
the attempt, the installer diagnostic log was 7,302 bytes and the serial log
7,482 bytes, with no completed installer phase. The compact diagnostic classifies
the cause as unknown; it does not establish a GNOME, AUR or package failure.
Raw logs were removed by the normal evidence-compaction boundary. Bootstrap and
serial-protocol investigation remains open before a retry; the six independent
supplemental scenarios continue. No Marble migration or functional PASS is implied.

| Current Marble bootstrap failure | SHA-256 / identity |
| --- | --- |
| Artifact | `11613864835` |
| Transport ZIP | `e38d81f011abf50f784868d4e1283232844ceec2ce5a22d7b0cd3660734ccda5` |
| Evidence archive | `22043f742b393b4047ae79618ab0da2fab80bd8ece117c65f599489674a938bd` |
| Result JSON | `8463437ce09dbfa1a1b01e384916b374755bf30347298c6d8c6649417e17b881` |
| Complete job log | `c232d16da44f45e1f3d801571f3af2cbe6a567e500d234b4eb3e34c46cbaf4b1` |

The independent supplemental `stock-gnome-ext4-systemdboot` run
`stock-20261009T120352Z-ddf6f332` passed twenty-one assertions. API transport,
source/tree/build/snapshot and result readback passed; the strict three-core
consumer is not applicable to this supplemental scenario. This result does not
close the failed Marble bootstrap.

| Current supplemental Stock ext4 VM | SHA-256 / identity |
| --- | --- |
| Artifact | `11614559938` |
| Transport ZIP | `8a56dad146f36fe27183069b97b5e277cb166ea9028bd99abaa09c5ba1c09ced` |
| Evidence archive | `ea1d082a3519f262f4670ac256709e7e0b9c42e004abfe3976cbf1f51b008eb8` |
| Result JSON | `22bcadf0ca881f39679c75d7bb4a47a00ba713bc7bcbf1b8f6d87b3502f0095e` |

Supplemental `stock-gnome-btrfs-systemdboot` subsequently passed twenty-one
assertions in run `btrfs-20261009T121700Z-f9f1fae6`. Independent transport,
source/tree/build/snapshot and result readback passed; the core-only strict
consumer is not applicable.

| Current supplemental Stock Btrfs VM | SHA-256 / identity |
| --- | --- |
| Artifact | `11615163925` |
| Transport ZIP | `376697f9caf09d570c57eee6d1784e21b5681ea6f222ecf3be75b61ed0a8f549` |
| Evidence archive | `4e4150c8dd01c03088f4c5f7bcd8f92e3581824eb34117630b3943251b93d5b8` |
| Result JSON | `d0ed70bd91fd71dbcf2d1ad8129e95e6cf318f8d5fffc67872b997e7a35157b5` |

Supplemental `stock-gnome-btrfs-grub` passed twenty-three assertions, including
snapshot boot and return, in run `grub-20261009T122917Z-79465487`. Independent
transport, source/tree/build/snapshot and result readback passed; the core-only
strict consumer is not applicable.

| Current supplemental Stock Btrfs/GRUB VM | SHA-256 / identity |
| --- | --- |
| Artifact | `11616601602` |
| Transport ZIP | `e6f789bd1ce5538d1464ee2e6c0f839354fdee02f9d0250c2e71273f6fb14b0f` |
| Evidence archive | `1de7a74615aa5d47aaf1430ffde33d2465b4438fb233f7f5b3e1543945b2a9ab` |
| Result JSON | `3f2eb15a7c54d714bad4b4c46b789e40939b004f62b2d452a8d4f98040429245` |

Supplemental `stock-gnome-btrfs-luks2-plymouth-systemdboot` passed twenty-one
assertions in run `luks-20261009T124645Z-8ee5cc74`. Independent transport,
source/tree/build/snapshot and result readback passed; the core-only strict
consumer is not applicable.

| Current supplemental Stock Btrfs/LUKS2/systemd-boot VM | SHA-256 / identity |
| --- | --- |
| Artifact | `11617490629` |
| Transport ZIP | `d123fb0ffc4b08b9841cb893311f3944b527d0afef63a59f603f167ed70aac40` |
| Evidence archive | `5ec925be1f68ffbedd46ac45fe3285b8ad67888023519c2c38a473e5bf7bc00c` |
| Result JSON | `13acadadf448e4395888db887c495c0f146d52861a2c91821d6e8594349b0fa8` |

While that installation was active, a passive read of its installer log confirmed
the completed Bootsplash phase, a primary Plymouth AUR build path and no mirror
build path. This is a scoped transport observation, separate from the complete
VM verdict above. Observation receipt SHA-256:
`57da5f04501dde2a732c7237a1ad397df1c7d44fb897bf8f773aa4a6c35047f8`.

Supplemental `marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm` passed
seventeen assertions in run `marblestock-20261009T130025Z-2a5cd945`. Its effective
blue-dark Shell, Colloid GTK3/GTK4/libadwaita, icons, Bibata and eight enabled
extensions passed, together with real GDM password login, lock/unlock, strict
`pacman -Syu`, repeat login, package integrity and clean shutdown. Stock GDM had
no Marble GDM package or resource overlay. Independent transport and
source/tree/build/snapshot/result readback passed; the core-only strict consumer
is not applicable. This fresh-install result does not prove the separate core
Marble legacy/GNOME 51 migration or extension functionality gates. Supplemental
dual boot was still pending at this milestone.

| Current supplemental Marble/Stock-GDM VM | SHA-256 / identity |
| --- | --- |
| Artifact | `11617916145` |
| Transport ZIP | `fa0fe6589cfbe4c0e1218edc14c32e5ed8460e317a2ef0b73b0b25fb8f9f5df1` |
| Evidence archive | `9b939b329e58ff460310c8083db1288e8fcf86a93404aeeea7d85c033757b267` |
| Result JSON | `4416b5c1ae89f35790f7164d193489d19c367b8d7628c925f82adf8ac891086b` |

The retained `firstboot-desktop.ppm` was inspected as an optional diagnostic.
It shows the blue-dark rounded Shell and Colloid dock icons, with the first-login
welcome modal dimming/obscuring much of the desktop. No post-reboot desktop frame
was retained. This limited visual inspection does not replace functional checks.

Supplemental `minimal-dualboot-ext4-systemdboot` passed seventeen assertions in
run `dualboot-20261009T131425Z-4e94aabd`, including collision refusal before
mutation, preserved neighbor/EFI identities and real neighbor boot. Independent
transport, source/tree/build/snapshot and result readback passed; the core-only
strict consumer is not applicable. All eight scenarios other than core Marble
now have independently verified PASS artifacts (156 assertions in total).

| Current supplemental dual-boot VM | SHA-256 / identity |
| --- | --- |
| Artifact | `11618930163` |
| Transport ZIP | `2e7953f0a11f3f72fa71430ec81a89e0716bec0bb3b89f3d2ddc29c4790ed833` |
| Evidence archive | `9bae91ad6a14bc4de12504f781e342536cf6c015593cef408ff1e71ff2abe959` |
| Result JSON | `d16b6c02b04a1cf8bcf9b84663baad00af44f73cc29f2a2b723dfce6e78b61d0` |

A separate passive diagnostic read of the earlier active Stock ext4 run found exactly one
expected READY substring and one fully source-bound READY line, no foreign
run/scenario marker, the diagnostic installer-BEGIN marker, structured installer
log records, two password-prompt strings and one boot nonce acknowledgement.
Only fixed counters/booleans were emitted; no credentials, input or source changes
were involved. This checks the observer used for the next Marble attempt, not
the cause of the failed attempt whose raw bytes were no longer retained.
Read-only source review confirms that the guest emits READY before starting the
installer log tail or installer. The ttyS1 sink's size alone does not prove those
statements ran. No source correction is justified yet. An early request to rerun
only failed job 113794670441 was rejected by GitHub with HTTP 403 because the
workflow was still running; that request left run attempt 1 unchanged. A diagnostic
retry with unchanged source, ISO and signed snapshot had to wait until the independent
matrix jobs finished. The original failure
artifact, compact bytes and complete job log are retained separately.
The failed attempt also retains its fifteen-file GNOME 51 baseline manifest,
SHA-256 `14d4dc69a179ad4a4613826b3db1cfcf4da1bad02aa73d9c3018501a6587bfb0`.
The normal preparer rebuilds four legacy AUR archives from unchanged reviewed
recipes for a fresh attempt; their generated bytes receive new independent
run-specific hashes. This does not claim byte identity of all generated test
fixtures across attempts or transfer any failed attempt's result.

After all independent scenarios completed, attempt 1 ended `failure` solely for
the core Marble bootstrap; finalization and publication were skipped. GitHub then
accepted `POST /actions/jobs/113794670441/rerun` with debug logging disabled.
Run 37921973159 attempt 2 started at 13:27 UTC with only core Marble job
113841142300 active. Main/source/ISO/build/signed-snapshot inputs are unchanged.
A separate local readback stage contains byte-identical copies of the fourteen
public Phase-A inputs; the failed attempt's evidence remains untouched. This is
a separate retry, not a Marble or publication PASS.

Fresh run `marble-20261009T133129Z-36d5e155` reached exactly one source-bound
READY line, the installer-BEGIN marker and two password-prompt strings, then
started the installer. The earlier readiness failure did not reproduce; its
exact cause remains unproven. The passive bootstrap observer completed its
bounded task and was stopped without affecting runner/guest processes. This
closes only the retry's bootstrap stage, not its migration/runtime gates.
The new fifteen-file baseline manifest is
`521c2998cd2f355f9699f34f0f8786e09c8dbef40734da6722c82b5b2a350b31`:
all source/baseline/recipe identities and eleven fixed files match the first
attempt; precisely the four rebuilt legacy AUR archives have new byte hashes.

Read-only review of the exact pinned
[download action](https://github.com/actions/download-artifact/blob/634f93cb2916e3fdff6788551b99b062d0335ce0/src/download-artifact.ts#L125)
and its bundled toolkit confirms `listArtifacts({latest: true})` selects the
highest artifact ID per name before applying the core pattern. An executed
duplicate-name fixture against that bundled filter passed. The pinned upload
action defaults to `overwrite: false`; this workflow does not request deletion.
Thus no old failure artifact needs removal. Actual retry upload and finalizer
selection are separate gates: upload subsequently created artifact 11620967409
while retaining failed artifact 11613864835. Finalizer selection remains
unexecuted because the retry failed before full Marble acceptance.

Attempt 2 ended `failure` at 13:55 UTC in `gnome51-baseline-install`, after seven
PASS assertions. Installation, scoped Marble GDM, real legacy GTK3 migration,
light/dark application launches and fresh-user/return-user GDM sessions passed.
The failure was after successful return-user login, before the actual 1.0.6/AUR
baseline transaction or extension recovery. Runtime diagnostic lines 3927/4020
reported status 127 and line 4021 status 1. The ten-line QGA input prefix maps
these to `gnome51_download_inputs`, the baseline `jq` producer and the six-package
count guard. A bounded execution of the actual functions reproduced missing
`jq`: Bash process substitution lets its caller return success with empty output,
then the count guard fails. The staged guest does not provision this test-only
dependency; public-media mode has a separate prerequisite. Correct the staged
prerequisite before state mutation and propagate producer failures; do not weaken
the baseline, package signature or six-package checks.

Retry artifact ZIP SHA-256:
`1aa2d0c314622e03187ff0c7611636b99adf06aefe15d47aaee97417f17333bb`;
evidence archive:
`5cbffa72a000ee27b619b3d18a25c0b0af9204cd24952f6fc402bac9d4119d72`;
FAIL result:
`2d41b892ebcc1ad0b7e72bc9683b9190c3f38cfbde2c33d670be12ed9ea463e3`;
complete job log:
`3f4ae48c39313c553765ab1a78ed3644c3739dc661b39a8faaf2dcd283f1d966`.
Independent transport, extraction and source/snapshot binding succeeded; the
readback rejected the FAIL result before invoking the strict core consumer. Finalization, tag, Pages,
publication and public acceptance were skipped. All eight other scenario PASS
results remain bound only to child `a35fa3e7...` and its signed inputs.

The focused harness correction provisions official `extra/jq` before migration
state changes or logout, preserving the effective package signature/trust policy
and checking the installed package, signature validation, executable ownership
and integrity. Checked buffered manifest producers reject failed, partial or
empty output before consuming it. A separate executed large-listing fixture
reproduced SIGPIPE from `pacman -Ql | grep -q`; consuming the complete listing
retains the required extension path match and producer status. Product package
dependencies, source pins, installer behavior and signing policy are unchanged.
Five focused regressions and all 138 guest-runtime checks passed; Bash syntax,
ShellCheck, independent review, documentation checks (29 files) and the full
`bash tests/source-tests.sh` passed. The repository fixture result was
`schema=1 namespace_fixtures=full scenarios=10 signer=passed release_closures=14+18 deferred=none`.
The final documented candidate repeated the required source suite successfully;
log SHA-256 is `1b3bcb05696c78eddddc1b5ec3cafbb96b11d5298ab274f7ee36fd1f7589be1f`.
[PR75](https://github.com/snaplyze/arch-linux/pull/75) passed exact-head
[CI 37942358566](https://github.com/snaplyze/arch-linux/actions/runs/37942358566)
and merged at 14:15 UTC. Accepted head
`2ece4cb3758a5791ecee88df7a5613989a093370` and main squash
`322e3318768db8634083b9684d5ac4c212e58572` share tree
`67eafc97ab8702920032c64b8193b6b51ed6b243` and canonical source SHA-256
`98b226ec3f498b4662ad80d5dc0b88ce376d8d6405e2dcbf02196e0f4e1fd408`.
PR CI log SHA-256 is
`9a1f4b3c8855b7cfb71b061fe1a9b6f72c802c1a6d14a00e4020479d9afc1bfb`;
main CI 37942859021 also passed (log SHA-256
`d12de67f426344084c60f3bc649271083d96bcfd91ea0fb5455f36f1a7a1e890`).
[Release 37943281539](https://github.com/snaplyze/arch-linux/actions/runs/37943281539)
started from main `322e3318768db8634083b9684d5ac4c212e58572`. Preparation job
113862894103 passed and emitted child `cd436147e2d4ce7b9886c62004fcfd9a520af915`,
tree `3e5120be4863a0550f6f70a879400d3d4ffb36e3`, canonical source SHA-256
`0d43a71e3e6aedddbbf15df15d961d5efc3ffd3f87a6b9677a992cdd46ae4d11`.
Source artifact 11622531850 has ZIP SHA-256
`74288073b237fb8f6cb895122a022180efebca6ea1b676f2f5f9379dd9512d16` and
bundle SHA-256 `f7d1f2cfad986f9eb8f02db39f0554d53f4176c6eceada2470f0aab44aa78455`.
Independent transport and deterministic transformation verification passed;
the README correctly pins 1.0.7 while preserving historical 1.0.6 evidence.
Installer SHA-256 remains
`e6228b0f655d5551eaf5cc8d085ea8111b24df3930b27cc78700d0944432ff71`.
Build job 113863212881 and protected readback 113865232676 passed. Unsigned
artifact 11622142666 has ZIP SHA-256
`9b41c7e51718672f7f550f9f7c8f8748662fb5a2471dcb8993e216b299ffc963`.
BUILD metadata SHA-256 is
`b16b582859c8c7fe4ce198d2ebc549b4661e7f30796e53b2f4d7573bd23d0599`;
UNSIGNED manifest SHA-256 remains
`cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`.
Fresh independent scoped readback passed exact sixteen-file closure/fourteen
checksum rows, schema-2 provenance, all seven package metadata/recipe bindings,
19,564 MTREE file hash/size checks and all seven production payload validators.
Its 212-file immutable verifier export matched Git modes/bytes and canonical hash
and was removed afterward. This is separate from the protected CI Git-bound
unsigned verifier, which also passed. Receipt SHA-256 is
`5ff8c194c19e2325d331c2d5f13609e02fd2f05cbc3ad683ed03aa480abaa0a6`.
Package versions remain keyring 1.0.0-9, extensions 1.0.0-7, Shell 50.0.0-8,
GTK 20260808-11, icons 20260829-7, profile 1.0.0-12 and GDM 50.0.0-10.
Signing job 113865627922 passed all five release-host gates: both full repository
runs (ten namespace scenarios, signer, 14+18 closures, no deferral), root
publication (four namespaces, sealed closure, FIFO/memfd/PID1/supervisor cleanup),
ordinary keyring (five scenarios; privileged mode explicitly deferred there), and
privileged keyring (all ten, no deferral). Complete log SHA-256:
`fc022dc3ca2ee7fbca6d317b8de78c0890c67db9fcd6ec69a912a9620530cc33`.
Phase-A artifact 11622463794 has ZIP SHA-256
`4688cd58af2e520a7d2ebef0af287102b0d075197bd3f88239a268e26157a863`;
signed snapshot SHA-256
`ed6497b22138bc0c67ce8e9688fac019a304e8b15697ccf9aa1d8a9621fd2567`;
RELEASE manifest SHA-256
`b4bac97921c5e771159439ae606fbe360e97f7799d1bf3468cd95f34e78ac859`.
Independent readback passed exact fourteen-file closure, twelve signed manifest
rows, three detached signatures, unchanged build/unsigned bytes and the complete
25-object repository contract. Fresh Minimal run
`minimal-20261009T143203Z-693dec46` (job 113867108199, artifact 11623646226)
passed fourteen assertions and the frozen `cd436147...` strict consumer.
Its harness SHA-256 is
`b98451df6622c892dd7e5ec7ac391e3266fc5b9cb5968014cbcb00c60188b241`;
artifact ZIP SHA-256
`bf94f41d3e5a7ad718b2b573c61d493f47434dfa55496781e61483821bcb69b6`;
archive SHA-256
`66ff423c3580fcac09beb9b9e1b14d94929d76ab2d42aa1bb5e782653e4308e4`;
PASS result SHA-256
`b934762e32bf7248766c4fa810039a536852a73b83d6d2e5513fd03b85e99e0a`.
Core Stock job 113867108207 failed at 15:04 UTC in run
`luksgrub-20261009T144431Z-32513158`: `guest verification failed: unlock`,
phase `firstboot`. Installation and real GDM login preceded the failed check;
the cause remains under diagnosis. Complete job-log SHA-256 is
`cffaeef025b74ab798aebe0da494543fcc4c8efbdc61a04b3ff5f1d499a653e2`.
Independent artifact readback verified source/tree/build/snapshot bindings and
retained the FAIL result with fifteen preceding PASS assertions. ZIP SHA-256:
`2ec6b8150e5e06f8b6cbee0986918391ef8458230b3b4dd973cf3fea2bcd92ec`;
archive SHA-256:
`9d3d4c1b4aee5864a59d65ffca27138dfd281eebe01f1c32237c8ce50e844574`;
result SHA-256:
`c9798f690d9cc1727161f93431de5cdaaa6c0e96d9c8eb73b39b3df0bc4e8ebe`.
The strict core consumer was not run because the failed result was rejected first.
The retained typed diagnostic maps to guest source line 4737: `LockedHint` did
not become `no` within 120 seconds, before later session/integrity checks.
The optional pre-input frame shows the target user's English-layout lock screen
without a password field; the preceding successful `a35fa3e7...` run's equivalent
frame shows the focused password field. This supports a readiness-timing
hypothesis, not a proven PAM failure or product diagnosis. The compact closure
intentionally omits raw QGA status and stderr; do not reconstruct missing evidence.
Read-only review of GNOME 51
[AuthPrompt](https://github.com/GNOME/gnome-shell/blob/51.0/js/gdm/authPrompt.js) and
[UnlockDialog](https://github.com/GNOME/gnome-shell/blob/51.0/js/ui/unlockDialog.js)
confirms that prompt creation and authentication questions are asynchronous. AT-SPI could provide a semantic
password-field readiness predicate, but its availability under lock has not been
executed; it is not a justified production/harness change from this evidence alone.
Complete the independent scenarios, then perform at most one unchanged-input
Stock retry and preserve the failure. A recurrence requires fresh diagnosis,
not repeated retries or weakened authentication/session checks.
Core Marble job 113867108423 also failed at 15:24 UTC. Run
`marble-20261009T151109Z-6d94ec12` passed the earlier seven assertions and the corrected
`jq` prerequisite. Its retained baseline marker proves six signed 1.0.6 packages,
four actual AUR owners, the exact local v6 tree and real `gdm-password` login with
preferences preserved. Blur, Clipboard and No Screenshot Box reported `OUT OF DATE`;
Dash reported `ERROR`. The next `gnome51-upgrade` check failed at runtime line 4115.
For this core Marble scenario, QGA prepends ten manifest/probe lines: the actual
source line is 4105, the plain `pacman -Syu` command, **not** logout at source 4115.
Stock has neither prefix, so its earlier line 4737 mapping remains correct.

Artifact 11625408747 ZIP SHA-256:
`b0d57ec36c504cee41fa96036e36f4a93bfbf968d3c42f5d962f4be7ea0465d1`;
archive SHA-256:
`d5ab60da513283bdbf2859a553c980df458e7b917c308e8d67f1f4aa7b0232c9`;
FAIL result SHA-256:
`452274cf4573623c3027998a54c54c17b2e9863e1b8964e69670dd566ad8e271`;
complete job-log SHA-256:
`c4602e8e907e15aaae3debe4a698e636d2a98550837f5c5ad01e8622f172722b`.
Independent transport and source/tree/snapshot binding passed; the failed result
was rejected before the strict consumer. Recovery login and functional extension
checks did not execute. A bounded fixture of the actual HTTPS handler reproduced
HTTP 304 for a different candidate database when the last-downloaded baseline
has a later modification time. Independent native ALPM reproduction then used the authentic signed 1.0.6 and
candidate databases in a private pacman root/GPG directory with required trusted
package/database signatures. Baseline `-Syy` passed. After the same server-path
switch, ordinary `-Syu` returned 1: the candidate DB request returned HTTP 304,
its detached signature returned HTTP 200, and pacman rejected the mismatched
pair as an invalid PGP signature. A forced candidate refresh passed under the
same strict trust. Baseline DB SHA-256 was
`9ec4656abf86534e88c433afbd1857a666549b7eae4c864a3c7a55f8764f8d30`;
candidate DB SHA-256 was
`9f014118c6534443e90e5dba1d5977d981a1d2a1668577d693fa8f25e61bc7e3`;
the newly downloaded candidate signature SHA-256 was
`c97eb95845be23738c3322ec2525d4e4a24fb102c4150951e0cd0d3e8c5cc6a8`.
A separate private filesystem-only replacement fixture installed the four actual
legacy AUR archives and candidate bundle without archive-owned file conflicts.
It used `-dd --noscriptlet`, assumed dependencies and disabled signatures in its
private configuration; it does not qualify strict trust, dependencies, hooks,
unowned runtime files or a real full-system upgrade. The strict signed-database
reproduction above is separate. These reproductions changed
neither the workstation's package database/configuration nor the live VM.

The source's extraction order gives the baseline a later file mtime than the
candidate. [libalpm's download implementation](https://gitlab.archlinux.org/pacman/pacman/-/blob/master/lib/libalpm/dload.c)
uses the cached basename's timestamp and fetches a detached signature even after
304; [libcurl's time-condition contract](https://curl.se/libcurl/c/CURLOPT_TIMECONDITION.html)
can also suppress the body based on a response's Last-Modified header.
The focused test-server correction must ignore conditional time requests and omit
Last-Modified while serving the same immutable verified bytes. Keep the promised
plain `pacman -Syu`, TLS and signature checks unchanged. This mechanism is reproduced
and matches the source sequence; the omitted live pacman stderr prevents claiming
direct observation of that exact error in the failed VM. The tentative unchanged
Stock retry is superseded by fresh acceptance of the forthcoming changed harness.
Supplemental Stock ext4/systemd-boot job 113867108197 completed successfully at
15:40 UTC with twenty-one assertions, including unlock, update and repeat login.
Run `stock-20261009T152753Z-71e34bf1`, artifact 11626777134, passed independent
supplemental transport/source/tree/Phase-A/result binding. Because the checkout's
HTTP harness had changed, its exact ordered harness hash was reconstructed from
frozen `cd436147...` Git blobs; the production unpacker also matched that child.
No strict core-consumer result is claimed for this supplemental scenario.
ZIP SHA-256: `4534180d17603241fadeee4c6f1cdef69c8659fa03c516a4a2a15cb012aa522f`;
archive SHA-256: `8b57d440db380c3d0b1a8422b4bf7818bd4a5706fdf3446c929024b39c9d9bd3`;
result SHA-256: `0504d2581f8aa7fb99611633d66a0c577d04ebb98ac0af6812eb7414c6e236b3`. After the focused correction passed, the superseded release run was
cancelled; the other five unfinished supplemental scenarios were cancelled.
The final run is CANCELLED with two scenario jobs PASS, two FAIL and five cancelled.
Finalization, immutable publication, Pages and public acceptance did not run.

The two-file correction leaves production packages, pins, TLS and plain `-Syu`
unchanged. Its actual TLS/`curl -z` regression first failed thirteen subcases;
a separate control proved that merely ignoring If-Modified-Since still lets
libcurl suppress an HTTP 200 body when Last-Modified remains. After correcting
both conditions, two focused tests and all 140 guest-runtime tests passed,
including repeated GET and HEAD with equal, newer and future cache timestamps.
Independent review found no material issues. The full
`bash tests/source-tests.sh` passed with full namespace fixtures, ten scenarios,
signer and 14+18 closure checks, and no deferral. Source-suite log SHA-256:
`249c781f61d3a64ba5dc191ab3421c372e8fa90d8b0247235dc1ce2d0006a34f`;
runtime log SHA-256:
`e4058004d7225d7143e9db6d21194233083b325e8c28852724a3aba7735e1727`.

An independent native Pacman 7.1.0/libalpm 16.0.1 repeat used the corrected production
server over actual TLS and the same strict signed-database trust. Baseline refresh
and then ordinary candidate `-Syu` passed; both candidate requests returned 200 and
both installed sync-file hashes matched the signed inputs above. No packages were
installed: this is metadata refresh/signature-pairing acceptance, not a full
dependency transaction or VM/session PASS. The test certificate was trusted only
inside a disposable mount namespace; workstation CA files were unchanged.
Temporary private GPG/TLS fixture keys, server and agent were removed after the check.
Nonsecret receipt SHA-256:
`7c6d5a301514e02d7a0b358cf52b84853acbd6ab6ad503223e727c052fa65e7f`;
server-log SHA-256:
`de6d7d91af0d59ec4a20057a077ba82128aa18670d9727aecd3f189c1a0ab65b`;
plain candidate `-Syu` log SHA-256:
`02a40f6898d62f137b38a172156662482be6f52a1f91a94bd085694f9e8b72c5`.
The final documented candidate repeated the full source suite successfully,
with log SHA-256 `33e0222c913bb464950827313aff6ad0c1d7ae058b0e289a3e150ff6b64ac08c`.
[PR76](https://github.com/snaplyze/arch-linux/pull/76) passed exact-head
[CI 37954160765](https://github.com/snaplyze/arch-linux/actions/runs/37954160765)
and the protected squash merge at 15:50 UTC. Accepted head
`d956d77ff0d234a2b9a513b8c6810f028c5af347` and merged main
`0d6b246cd5e6fb3cde8818be33d70bc6d32e8392` share tree
`97943ffe495d5085f3496335f467c00679eb2796` and canonical source SHA-256
`35d6c1698ff310f27cdebf365118f2a9520a048982be2ad316a815908127f91c`.
PR CI log SHA-256:
`11e76eb575f5e49c72f8c259572bb758d448ba256163a508bc5f03ba6252f085`.
The sole checkout returned to main by fast-forward. Main CI 37954693122 passed;
its log SHA-256 is `75d8119b4f3bb6f1c5808b23e27293de68df7ebef7e58625b1e1a3eecca0cdde`.
[Release 37955123850](https://github.com/snaplyze/arch-linux/actions/runs/37955123850)
started from the accepted main. Preparation job 113903575096 passed and emitted
child `00d97e3ee254cee318b8bce7c51ebbf3e64c2c95`, tree
`ace4eba07963cb19586069c8dba1027711858072`, canonical source SHA-256
`76d771a0b2e025f70775fd4cc22a12982c381eae659d33a4070e916955f3402a`.
Source artifact 11627477376 ZIP SHA-256:
`5bbaf57a3432332765dd659d78409b50a58255839c609c4bcb2d0a3f93c292c5`;
bundle SHA-256: `0c8bb4c6f5f3fe92ec49e859187dd6cc7252d31fcebc953f6022f8d8e1ddee82`.
Independent source transport/deterministic transformation passed, including correct
1.0.7 README/bootstrap pins and preserved historical identities. Relative to the
preceding child, only two evidence documents, release-origin metadata and the two
test files differ; product/installer/package/trust/maintenance inputs are unchanged.
A further bounded read-only review checked Clipboard ordering, Dash launch and
No Screenshot capture controls against the actual bundled sources and found no
material mismatches. That review does not replace the still-pending functional VM
checks after update and reboot. Clean build job 113903756240 and protected
unsigned readback 113906648886 passed. Unsigned artifact 11628170960 ZIP SHA-256:
`17a022c8854d3827e2c9ca6011bf684edb5fc62137de69ee048381c7fe072db0`;
BUILD metadata SHA-256:
`e8d54e692ce68517a0f22e3389b4d1c1d2b86e27be0f12ce6a123ad6f22d721f`;
UNSIGNED manifest SHA-256 remains
`cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`.
Independent scoped verification passed the exact sixteen-file/fourteen-row closure,
schema-2 provenance, all seven package/recipe/SRCINFO/BUILDINFO bindings, 19,564
MTREE file checks and seven production payload validators. The 212-file read-only
verifier export was mode/byte/canonical-hash checked and removed afterward.
Receipt SHA-256: `57775e5abb45ad3e06cedc2f25236e77d97123982fb05a26c66e1f922a7e9679`.
All seven package versions remain as recorded for the preceding child. This scoped
verification is separate from the protected Git-bound unsigned verifier, which
also passed. Phase-A signing job 113907144469 passed all five release-host gates:
both full repository modes (ten scenarios, signer, 14+18 closures, no deferral),
root publication (sealed closure, four namespaces, FIFO/memfd/PID1/supervisor),
ordinary keyring (five scenarios, privileged mode explicitly deferred there), and
privileged keyring (ten scenarios, no deferral). Complete job-log SHA-256:
`4c32a4bcd8d643a652a35fb4290246f5ae73d2d4b656b29ee49c6f40c6388130`.
Phase-A artifact 11628675564 ZIP SHA-256:
`4084fa04290e349c03ec94087e8ef126e4b825e8df8c891a9e3904b0ea16308c`;
snapshot SHA-256:
`ce5dc8a17f8325ba292883f5df8cc0d96ebc7ca958b2f014f9158a2064ffe23a`;
RELEASE manifest SHA-256:
`63d327847aff31ce2ffe6438ae1215b9b60527a129b61461ecc19b12221d31ac`.
Independent readback passed exact fourteen-file closure/twelve signed rows,
three detached signatures, unchanged build/unsigned bytes and all 25 repository
objects. Staged Minimal job 113908703980 passed all fourteen assertions, including
ordinary update, reboot, unit health and clean disk shutdown; independent readback
and the frozen strict consumer passed. Run ID:
`minimal-20261009T160925Z-dd37331b`; artifact 11627924847 ZIP SHA-256:
`f545ab92a8b5bb6c8b738f7c5a3d9064d3b89cde81b86401ae0bad768e6fd537`;
evidence archive SHA-256:
`92b245b729f8bd28cecb074bebaa5764de74f65e7b3f575a6b5b0945c4ef4cac`;
result SHA-256:
`dc48def6e442c13c3715cfb71f9742a03bca4bc90c2362ea6e15481ca3315699`.
Core Stock job 113908703986 passed all twenty-two assertions, including real GDM
login, lock/password unlock, ordinary update and repeated encrypted boot/login.
Independent readback and the frozen strict consumer passed. Run ID:
`luksgrub-20261009T161926Z-33fba858`; artifact 11630682519 ZIP SHA-256:
`63c7d4ab8b76af7a09273627d1ce0ed933db9a4c913d8073cbe63b84be46ca6a`;
evidence archive SHA-256:
`84e28a402f6ffa3e66f0ebba55c477c1c21108bdeafab8f362bd1181661cb97c`;
result SHA-256:
`56cfa7b20510b856fe6b37228bafbed175f464eb2e5a835c685a2a751bdc242b`;
complete job-log SHA-256:
`2e3bd1036462e67dc80e57bc93175a16c36e84c894cbf8d3ff4137f287f1b2c2`.
The preceding child's lock failure remains recorded; this changed-child PASS
does not prove its exact cause. Source-bound live observation separately saw
Plymouth and Bibata use primary AUR, with no mirror attempt. The compact artifact
does not retain those transport rows, so this is not an artifact-derived claim.
Core Marble job 113908704005 failed at `return-user-login` after successful
legacy theme update, GTK4 light/dark app checks and fresh-user password login/logout.
Only four assertions had been committed to the verdict; the later three grouped
assertions and GNOME 51 baseline/upgrade/functional checks were not reached.
Run ID: `marble-20261009T164217Z-b00eee3b`; artifact 11632891691 ZIP SHA-256:
`0f8858dea4dfb0345de6179dc427a98938cc9f0f435f64dee107034c4aed747c`;
archive SHA-256: `ca0473eacfa190093758d1d59f797f1f4b6df7d8c2cd1b52f9a440daa0471c2d`;
result SHA-256: `97bbf24cb35e2f3c7f277b0f5e6649f4fd5b7c05ed28f80a9c4189ccb98e74fe`;
complete job-log SHA-256:
`aca43ff0d890f0bd1071f11d1f21bf412010811cb184828ef875d187d0dcb60e`.
API transport, exact archive/source/tree/Phase-A bindings passed before rejection
of the FAIL verdict; the strict core consumer was not run. At return login all
eight known extensions were INITIALIZED, the global disable boolean was true,
and the upstream recovery service had started. Before original-user logout the
boolean was false and its early-failure sentinel was present. The observer queried
the wrong `org.gnome.Shell@wayland.service`; official
[GNOME 50](https://github.com/GNOME/gnome-session/blob/50.0/data/gnome.session.conf)
and [GNOME 51](https://github.com/GNOME/gnome-session/blob/51.0/data/gnome.session.conf)
start `org.gnome.Shell@user.service`. Zero timestamps/invocations/failure counts
therefore do not exclude a real Shell failure. The upstream
[60-second sentinel](https://gitlab.gnome.org/GNOME/gnome-shell/-/blob/51.0/js/ui/extensionSystem.js#L54-74)
and [conditional recovery unit](https://gitlab.gnome.org/GNOME/gnome-shell/-/blob/51.0/data/org.gnome.Shell-disable-extensions.service)
explain the disabled state, but do not identify the triggering signal/timeout or
extension. Preserve that protection and user preferences; a corrected bounded
observer with event chronology is required before attributing the failure.
Supplemental Stock ext4 job 113908703984 passed all twenty-one assertions,
including ordinary update, repeated GDM login and lock/unlock. Independent
readback passed source/tree/Phase-A bindings and the ordered harness digest
reconstructed from frozen child Git blobs; its strict core consumer is not
applicable. Run ID: `stock-20261009T170557Z-5b47c779`; artifact 11633430585 ZIP
SHA-256: `3173444468d836b7e9e66519bc5ee3c9c1dd822e6fe84d340152755e94bd2f29`;
archive SHA-256: `1b57b4c241c78c75072f5f1edddef190722f463b5462b7da8b24c76b5c4d79bb`;
result SHA-256: `7acfca7e6513c2f33fd3f033d70c6589709ab559e676b48008fe46ffae48864a`.
After the diagnostic correction was verified, root cancelled the superseded
unpublished workflow. Terminal API readback confirms three PASS, one FAIL and
five cancelled scenarios (Stock Btrfs/systemd-boot, Stock Btrfs/GRUB, Stock
LUKS/systemd-boot, Marble with Stock GDM and dual boot). Their pending acceptance
is NOT_TESTED. Finalization, tag/release creation, Pages and public VM acceptance
did not run. No earlier child's VM results transfer to the diagnostic candidate.
These source results do not establish the still-pending real
GNOME 51 migration or transfer any old VM result to a changed child.

The focused diagnostic correction observes the shared GNOME 50/51 `@user`
instance, keeps the recovery unit unchanged and adds a bounded typed event
timeline with current-boot monotonic timestamps plus a pre-query checkpoint anchor.
The original observer's RED fixture missed actual `@user` failure/timeout events;
its log SHA-256 is `872b8900940ffb33bf8cdc33e5df583c05742512224a1b9a20c23c78248ccd3e`.
The checkpoint RED log SHA-256 is
`6052a5d0c4106d15462ad4453c7d1dc4a53c4898b6946aa3336c715fefa96b7f`.
Only validated public unit/event/result/exit fields are emitted, after the entire
window validates; unknown IDs remain unclassified counts, while invalid numbers,
fields or exhausted bounds yield unknown without a partial timeline. No journal
message, arbitrary identifier, command line or private path is retained. Upstream
crash protection, preferences, login timing and acceptance requirements are unchanged.
Final seventeen lifecycle fixtures passed (focused log SHA-256
`fced11b1a7f4c85700b9fd1e784859e281346688b86a2a4a4940bab9ea3f08e2`);
`python3 tests/vm/runtime-checks.py` passed all 145 checks (log SHA-256
`bd5f2fa05859324038df9e4a29ca0915df047bf4c674d14d192c985ec1235175`).
Bash syntax, source modes and diff checks passed. Independent read-only review
found no material issues. `bash tests/source-tests.sh` passed, including full
namespace repository scenarios (ten, signer, 14+18 closures, no deferral); initial
source log SHA-256:
`a6b537d94f41f90981680b01ef40337ae6ad968082fda203901c93beddb06f6a`.
The documented full source run also passed; log SHA-256:
`41bd86806aad9d6f5fc2903427367771d0cb2f3057d8d11569136fe7ea62d4cc`.
Repeat the full suite after this final cancellation/evidence reconciliation before
protected delivery. The real VM cause and recovery are not yet established.

The final documented source suite passed before protected delivery, again with
full namespace repository acceptance (ten scenarios, signer, 14+18, no deferral);
log SHA-256: `7090c49dcc709d55cf11bb5010acfc54a9ebdcf16ea0468a784275d946445b0a`.
[PR77](https://github.com/snaplyze/arch-linux/pull/77) delivered accepted head
`2c56173ccaf64563f45584b3be55cdc436c5c280`, tree
`b8168dbb671a485f4201019d6f49f45a3fba1736`, canonical source SHA-256
`95149838c8061ba813e9f099d69044d8e390d3055407ea49e7daf75cf81f12eb`.
Exact-head CI 37966226074/job 113941140536 passed; complete log SHA-256:
`dfdf8d96a6d47e48539a286ff9b827791fd4f5e998b1208f38cb1ba8cc6df55d`.
Live head/base, strict required check, mergeability and absence of unresolved
review threads were rechecked before the protected squash merge at 17:30:41 UTC.
Merged main `30ebf25cd70f8f76140996dcf54b2445198f1b84` has the same tree/canonical
hash. The sole checkout returned to main by fast-forward; fresh main CI
37966792524/job 113943032612 passed. Its complete log SHA-256:
`77c10c517d9b463b906a246b6deab9e882d98502c116507030d35a0bbaaf3047`.
This diagnostic delivery does not resolve the underlying Shell recovery or
transfer earlier VM acceptance to its future child.
[Release 37967163595](https://github.com/snaplyze/arch-linux/actions/runs/37967163595)
preparation job 113944278004 passed and emitted child
`a7730ddab4dd88fede3f8ca83489806f559d6a0f`, tree
`c74e5208e3d768d7ed2ec464a4918d982341a496`, canonical source SHA-256
`0c1a91daf4b2a9a3ac6da658d3df3c5baec9e4636cfad061e2c38f1e2ed7460f`.
Source artifact 11633049217 ZIP SHA-256:
`7679705f50c31840c5fff289e034b7a99651504c779a437704d4dbe7260a464a`;
bundle SHA-256: `521dd46a25f85515ce359f342cca1c1405a11f886214ea7515a54a327a011302`.
Independent source transport/deterministic transformation verification passed,
including 1.0.7 README/bootstrap pins and preserved historical identities.
Relative to the preceding child only two evidence documents, release-origin
metadata and two diagnostic/test files differ; product/installer/package/trust/
maintenance inputs are unchanged. Installer SHA-256 remains
`e6228b0f655d5551eaf5cc8d085ea8111b24df3930b27cc78700d0944432ff71`.
The frozen ordered ten-file harness SHA-256 is
`6ffa142e1b100cedb9a75c7d63323b49f4cdedd2474e2ff126a947066ff250ab`.
This value was independently recomputed from all ten frozen Git blobs and matched
the first VM result and its exact `harness.sha256` bytes; it corrects the earlier
provisional checkpoint calculation, without changing source or acceptance.
Build job 113944400778 and protected unsigned readback job 113946250869 passed.
Unsigned artifact 11633982973 ZIP SHA-256:
`148ebb90728809ec3344fb3e5f98cd2d5c474521d395812daac9c7298613b042`.
BUILD-METADATA SHA-256:
`440a80edf483e3598996e250e091eaf61ae51338e6a78ce39ff3441a5e4b037e`;
UNSIGNED-SHA256SUMS SHA-256:
`cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`.
Independent scoped readback verified schema 2, the exact sixteen-file closure,
fourteen manifest rows, seven package metadata/build/recipe/payload predicates
and 19,564 MTREE files. Its receipt SHA-256 is
`253c8a55ed8fb9bcebd999f78904b539c0e5c5fd8367051c196683e5a62e889f`;
this scoped verification is distinct from the protected Git-bound unsigned gate.

Snapshot job 113946790203 passed all five release-host gates: both full namespace
repository modes (ten scenarios, signer, 14+18, no deferral), sealed root
publication and ordinary/privileged keyring modes. Complete job log SHA-256:
`0718d790e7db000386ba270edca358a35dabf9b9b0be5570effe87ca45660a2f`.
Independent Phase-A artifact 11634665554 ZIP SHA-256:
`06a3fcf3eea20f5821989e0a4561dcd557b111dfad2e3a5e59bd200699c77663`.
The exact fourteen-file closure, twelve signed manifest rows, three detached
release signatures, unchanged BUILD/UNSIGNED bytes and twenty-five repository
objects passed verification against the frozen child and retained trusted keys.
Repository snapshot SHA-256:
`e42a653aa11fb97d1dcfd30bf3f3c8a29f5dcd7ed02ca0fe025655e42c84f29c`;
RELEASE-SHA256SUMS SHA-256:
`acc4ddab359d19d2c4dd9005cb85875e3703b7353a31c7c27f589bcd2b75c281`.
Fresh staged Minimal job 113948320735 passed all fourteen actual assertions;
run `minimal-20261009T174827Z-236b0b76`, artifact 11634678345.
ZIP SHA-256:
`f98936db319ad0744572b07f2fba14d152e0e99c536d7f1c3fdac2146e853a4b`;
evidence archive SHA-256:
`2e3d3bedaa367322acbe26db284f7108d58a639ddbd4302ecbaab86db4721b4c`;
result SHA-256:
`6a627ae9754323e10730dbf5c61bef6343980f62d028f5736716a9905c9cfdd8`.
Independent artifact/binding/readback and frozen production strict core consumer
passed. Fresh core Stock job 113948320895 also passed all twenty-two assertions;
run `luksgrub-20261009T180414Z-0d731136`, artifact 11637351069.
ZIP SHA-256:
`6def36bc44ef3992a7040a310b690f3416de6d6a7e25f78130fa70b4994f5be5`;
evidence archive SHA-256:
`ec182977f638b002cd7f0b7e24007b8dfa255cf770a55158af983983e4454cd2`;
result SHA-256:
`f34a25811ce8be82ee38319e2d9e88580126488018262c9ad7aceafcc540d063`.
Its independent binding/readback and frozen strict core consumer passed. The
source-bound live runtime helper observed primary AUR build paths for Plymouth
and Bibata and no mirror transports; the compact artifact does not retain those
transport rows or exact installed official package versions. Those observations
are not a package-version acceptance receipt.

Core Marble job 113948320682 failed at 18:24:14 UTC before preflight or VM creation.
The initial accepted Arch ISO HTTPS transfer stopped around 520 MiB of 1.52 GiB
with `curl` exit 56 and OpenSSL `unexpected eof while reading`. SHA-256 validation
and the VM harness were not reached; no QEMU artifact/result exists. Complete job
log SHA-256:
`580d2b0ecbdfa9b7de127e9f2d143b2e7e2e3e2501ec80e4822c4f0378f87472`.
This is a transport/preparation failure, not a GNOME/package functional verdict.
The remaining independent staged VMs continue. After this attempt ends, repeat
only the failed job and dependent gates with the unchanged a773 source, accepted
ISO/hash and existing signed Phase-A bytes. Preserve the failed attempt and bind
every later result independently; do not rebuild, repin or transfer a result from
other inputs. Finalization/publication/public acceptance remain pending. The prior
disabled-extension cause remains unestablished.

Supplemental Stock ext4 job 113948320675 failed at 18:42:10 UTC after seven
actual PASS assertions through the Stock GDM greeter. Run
`stock-20261009T182959Z-917de063`, artifact 11637449686, source/tree a773/c74e.
ZIP SHA-256:
`ae751d112d9c5be215a7e7d7803e97b440507822cc05cce248c294cf3a969bc9`;
evidence archive SHA-256:
`32d76e172dcc0d4563948fc688e81050f4c0f863862aeccd6b8a0d9109e61a1c`;
result SHA-256:
`540918ae0330d2a7c34c0ea2f3f18431903a2c33c06c8218cfebafd39feef8bc`.
Complete job log SHA-256:
`2c7455a3abe673ade117945dbfad69066ea45e3bc21910dc273c7fefcdb64728`.
Artifact digest/safe unpack/source/tree/Phase-A/frozen harness bindings passed;
the real result is FAIL (exit 1), and the reader correctly rejected its PASS
predicate. Strict core consumption does not apply to this supplemental scenario.
Retained firstboot diagnostics report guest lines 522 and 3110, status 2. The
frozen caller is the bare `gnome-extensions list` inventory query, before its
existing bounded readiness poll; no GNOME-51 phase prelude offsets apply here.
The [official GNOME 51 tool implementation](https://github.com/GNOME/gnome-shell/blob/51.0/subprojects/extensions-tool/src/command-list.c)
returns 2 for proxy/ListExtensions failure and 1 for invalid arguments. The exact
live failure was not retained and transient startup versus permanent Shell failure
is unestablished. Process/session-bus presence alone does not prove Extensions API
readiness; the existing poll must succeed before inventory is queried.

The two inventory queries now follow the existing readiness poll in Stock and
both Marble branches. No product/settings/deadline/expected-set changes were made.
Executable fixtures retain the actual source call sequence and poll while mocking
the API's unavailable-to-ready transition. The original HEAD control produced four
failures (Stock/Marble/fallback/removed); corrected code passed two focused tests,
including twenty persistent/missing/unexpected/post-readiness negative cases, and
all 147 runtime checks. Native private D-Bus testing was not performed; these are
source/control results, not real-session acceptance. RED log SHA-256:
`5ca69d74d92948c4177d27d76894ad9b5d0b8ec2811ea99f4de6919de9bd11d0`;
focused GREEN SHA-256:
`2a9bb4c7c7e5ccbe6f42780eea3399b86ef99869a6c3f43505fbcec987dede98`;
full runtime log SHA-256:
`3a4cbd3df9bc974312d24d024bb9db3417f35454c3be82b9ea598e5354d72963`.
Bash syntax, modes and diff checks passed; independent read-only review found no
material issues and confirmed fail-closed negative behavior. Protected delivery
and newly bound VM gates are pending. The earlier unchanged-input ISO retry
plan is superseded by this changed harness candidate. The local release procedure
also now restricts specific-job retries to pre-evidence failures with verified
absence of colliding artifacts: attempt-free names cannot be overwritten or deleted
to hide a failed result. Its focused independent review passed. The old Shell
logout/recovery cause remains unproved; none of these test changes fixes it.

The initial full `bash tests/source-tests.sh` passed, including the mandatory
full namespace repository marker: ten scenarios, signer, 14+18, no deferral.
Complete log SHA-256:
`1bdb00516f84bb7cfd06c3ecd097d3afaad8d3f1a0aeb925bdab567275e1b2ef`.
Cancellation for the changed-candidate handoff then completed: run 37967163595 is
CANCELLED, with two PASS, two FAIL and five cancelled staged jobs. The assigned
independent readback finished: Minimal/core Stock strict PASS, supplemental Stock
ext4 FAIL, five cancelled with no artifacts. Core Marble's separate pre-VM transport
failure is the second FAIL. Only three QEMU artifacts exist. Finalization/signing
of acceptance, tags, Release, Pages and public VM did not run. The source-bound
runtime helper returned an empty list after cancellation; that is a bounded runner
observation, not a global resource inventory. Preserved receipt SHA-256 values:
Minimal `310999209dc3d9738bc2f412bc6a6773ccd1e77b2cc6790d2109ba87aff92f22`,
core Stock `d68c69383460cdfe7066064b58204965c755d5bb6fcaf44267f8fab40d3f1406`,
Stock ext4 `a154ae7a4fe0605cc7847f40356de176bdcefd14b49b5b6dd5bcf438c5ddd5f3`.
The documented full suite also passed after that cancellation reconciliation,
again with full namespace repository acceptance (ten scenarios, signer, 14+18,
no deferral); complete log SHA-256:
`59a0d999f465f1454f896e87c98e7fa1ed8b9c1a69cf3f9233f14781c1fc5caf`.
This final result prose follows the executed suite; documentation/link/diff checks
and exact-head CI are required before protected delivery. None of the old VM
results transfers to the changed harness candidate.

[PR78](https://github.com/snaplyze/arch-linux/pull/78) delivered accepted head
`1f1242c7ee8cf6eebc2a823c2bce74cb3c607f79`, tree
`cff8a588c6eb873d4c069106816ee937e07c438d`, canonical source SHA-256
`b71fe4aff19a89935de644af66f5cc6749e90b69c2f1db105e04e1296da84eee`.
Exact-head CI 37977462863/job 113979239989 passed; complete log SHA-256:
`3cd061945410f3ca3331db3c8c0049f12cd87eecd53895f991cfc11c54482a7e`.
The required check belongs to app 15368 and the exact accepted head. Live head/base,
CLEAN/MERGEABLE status and all review threads (none) were rechecked; protected
squash merge completed at 19:08:02 UTC. Merged main
`65f67132d9e2f657672f58033b75c6af0cca9028` has the same tree/canonical hash. The
sole checkout returned to main by fast-forward, with the index preserved. Main CI
37978123346/job 113981467059 passed; complete log SHA-256:
`62ee7e6e02994e74f2f5ea245da94f2b4791a5eb0db2e02f7fe200b2ea6bd194`.
[Release 37978505750](https://github.com/snaplyze/arch-linux/actions/runs/37978505750)
preparation job 113982761309 passed and emitted child
`1274611da69b5eb78990f7c01fd8350215a58d49`, tree
`bd7e3f81d17cc7e942be2c1964523a577d53f328`, canonical source SHA-256
`01b3ec2f4f2868f71b45d0bc11c68779eb95572e5f2713be3496bb97b825ec80`.
Source artifact 11639648807 ZIP SHA-256:
`e1c4c8c3b222a753e91ef277f6ee3fb6e32ba44919e28aba111a5a3f8df2bfe0`;
bundle SHA-256: `f3182042fb0bb99614592f1fd67aa3f52de97eb925fa49428263dee5bddf9bee`.
Independent source transport and deterministic transformation verification passed,
including 1.0.7 README/bootstrap pins and preserved historical identities. The
frozen ordered ten-file harness SHA-256, recomputed directly from the Git blobs:
`2941348bff3390fd38aa010e70796f868d7b2a02d4166b0f088075869b71c08b`.
Installer SHA-256 remains
`e6228b0f655d5551eaf5cc8d085ea8111b24df3930b27cc78700d0944432ff71`.
Build job 113982865078 and protected unsigned readback job 113984622626 passed.
Independent scoped unsigned readback verified artifact 11640565543, exact sixteen
files/fourteen manifest rows, seven packages, 212 source modes/bytes, all 19,564
MTREE files and seven unchanged production payload validators. ZIP SHA-256:
`f3ab462d7c1713b756fcf2aa3cc5d452bc06510884232f13a346c23bbb282e2d`;
scoped receipt SHA-256:
`f315f577c8186ab20d6661f4cc371fb172f53d9974fa5b4fb27c2ae77de1f6cd`.
This independent scope does not replace the protected Git-bound shell entrypoint.
BUILD-METADATA SHA-256:
`161c4df1dce548486be91dd230db91d254ef83ace5a753886db32534b7a73fd3`;
UNSIGNED-SHA256SUMS SHA-256:
`cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`.
Snapshot job 113985013173 passed both full namespace repository modes, the root
publication boundary, ordinary and privileged keyring modes, then signing.
Complete snapshot job log SHA-256:
`8c08ef94e9b610b747c656b6631f52af3b47e5558c24e5700b235bdacecd8510`.
Independent Phase-A readback verified artifact 11640486444: fourteen assets, twelve
signed manifest rows, three release signatures and twenty-five snapshot objects.
ZIP SHA-256: `90ee40800d65d7a42151cd989a3b190c687e0d5ca6ed007b709f716794f74fbe`;
repository archive SHA-256:
`a4ce97bd9a479e7ae816638d1a84f7064c4470994836e38766cd3fae4ae3002e`;
RELEASE-SHA256SUMS SHA-256:
`700304ea1462922c309d55a804009ba7c5d3b8711008f53bc536c5f1dd0623cc`.
Fresh Minimal job 113986280484 passed fourteen assertions; its frozen strict core
consumer also passed. Run `minimal-20261009T192426Z-6e2c89e3`, artifact 11640872585:
API ZIP SHA-256 `e92438131c4206cc1512d3788ec1f6bb4ba077137d5671b79e65356441d2f3aa`;
evidence archive SHA-256
`2f6cfe1565a45f396e9fc5f4edca658b1c3c4fd2307ff34f6ddba0a8866bd227`;
structured result SHA-256
`bc30e628b28338eeb5197c993bff3242e04862bf46d0e6d249b3c20cf59141ca`;
independent receipt SHA-256
`2e0f79e35ec37a6e42180435771202ff0be2396f1230cac220eaef48d0797720`.
Fresh core Stock job 113986280483 passed twenty-two assertions and its frozen strict
consumer. Run `luksgrub-20261009T193601Z-57be1996`, artifact 11642550334:
API ZIP SHA-256 `be34db44e53556a4494be57fd443240d71a371dbfe0fb3e78e9206ecf8515ea8`;
evidence archive SHA-256
`d5b7467fadb7d7f34c2b18d948996950d1c43fdd8f72c3103f21d0cdfe04f887`;
structured result SHA-256
`b9b122f600b174972bc26329159d898317c21dc6142c1db806ecae9a8cb6aa95`;
independent receipt SHA-256
`4b85e78596917ff8f067c4c2ac64bcbe06795e095965bec58ca52853fb077e03`.
Source-bound runtime observation recorded both Plymouth and Bibata primary AUR
build paths, with no mirror transport. This does not expose exact official package
patch versions, which remain NOT_OBSERVED in compact evidence.
Core Marble job 113986280344 failed at `return-user-login`, firstboot exit status 1,
after four recorded assertions. Run `marble-20261009T195923Z-a1ae373a`, artifact
11642599197: API ZIP SHA-256
`859800c9b3ffc4c220ff6826ae58e87677a7b4aaf89fa11d5650951f5f545570`;
evidence archive SHA-256
`17d1fbbda1612996e48befb846c1b5c960b92a3805c4eb62916279b4b30556f0`;
structured result SHA-256
`0240d9b7fbcd7fa2638178a30212e2b40a45b84d2a29dae7c965e7df717a26f5`;
independent failure receipt SHA-256
`9a290fe3dbe6c4c1e79d8acc5073eecbbfc096e80eab659b4b44d7830ba55dbf`;
complete job log SHA-256
`ef89d5c72b1a716277f28a037222566e79549bcacecc8d8560ac303fac66223b`.
API digest, safe unpack, source/tree/Phase-A and frozen harness bindings passed;
the PASS consumer correctly rejected FAIL. A full strict PASS is not applicable.
The scenario reached the legacy GTK migration, GTK4 app smoke, fresh-user login/
logout and original-user return, but not the separate GNOME-50/51 upgrade phase.
Global disable was false with the sentinel present before original logout; actual
user Shell age was 39.287 seconds. At timeout the return Shell age was 183.283
seconds, global disable true, eight known extensions INITIALIZED and sentinel
absent. The correct `@user` unit was observed, but `journal_query=unknown` leaves
recovery timing/cause unproved; current inactive recovery-unit state cannot rule
out earlier execution because systemd may collect it.
An independent read-only native control reproduced a diagnostic-window defect:
the exact broad query returned 129 valid-timestamp Shell application records,
all without MESSAGE_ID, so the existing all-window validator rejected it. The
same UID/units/OR groups filtered to the four known systemd lifecycle MESSAGE_IDs
returned one typed started event. A retained native control executed the actual new
producer request builder and parser: broad query 129 records/50,012 bytes/reason
`window-exhausted`; filtered query one record/457 bytes/typed started event/query
ok. The receipt contains only public command fields and bounded aggregates, not
raw journal; SHA-256:
`325444d26dff2a292887eb9242541ab14f76d3594f4c797c4d2b7bcafc6737c1`.
This demonstrates lost diagnostic chronology, not the actual guest query's
rejection reason. A filtered query, finite rejection
reason and immediate post-logout/early-return observations were implemented.
A HEAD control produced eighteen failures in five focused tests; the corrected
focused run passed twenty tests and the fresh full runtime run passed all 150.
RED log SHA-256:
`7d2952867b04c95f8ea77a6707ccc487653e133662e2d2a979985db3c17f6443`;
focused log SHA-256:
`2aaec1794039c6ea772704638aa7c6e5c8be5932795eacb3067bab83b8a5fa1c`;
fresh full runtime log SHA-256:
`d244d69148d27ab31606cd7a8a0f095d9ea00db9f26c1f7e36c016caf7b517dc`.
No settings reset, longer delay or product correction is justified yet.
An earlier full-runtime repeat failed thirteen subcases of the independent TLS
fixture: curl attempted port 443 rather than the server's ephemeral port. The
existing producer creates the final readiness pathname before writing the port,
while its consumers wait only for pathname existence; this exposes an empty-port
race. The failed run did not retain the read port, so its exact interleaving remains
unproved. Isolated TLS and a fresh full repeat passed; the prior FAIL is retained,
log SHA-256 `3f8275e512b2426bbe212ccbfe09155891fd4b6a7ee485c6d3f0d64aa3509e0b`.
A deterministic actual-server pre-write pause reproduced final readiness exposure
against HEAD (one failure in two tests). The corrected server writes/fsyncs/closes
an owned same-directory mode-0600 temporary file, then publishes with no-overwrite
`os.link` and removes only its temporary file. The controlled pause now keeps
readiness absent until complete port publication; real TLS GET returns exact bytes.
Existing regular-file/symlink identity and content preservation passed. No HTTP,
TLS, timeout or package acceptance policy changed.
Atomic control RED log SHA-256:
`de76d85395791282727dc75bea0b7a0377633d426cee2708e27044afca6f835e`;
GREEN log SHA-256:
`eebf5532fefc25f421deb2e218f6fa6e45631d5eec0577316740170dc9cc638d`;
combined focused twenty-four PASS log SHA-256:
`fd179a4163ab1526761f70a643e5e215dec3fad400c8d4b731a6d7759a9344c6`;
fresh full runtime 152 PASS log SHA-256:
`aee42c9d4ce8d9723e87313b4ac0b92154020b9a29649d37ccef87c5d7bf2a1a`.
This proves the publication defect; the prior intermittent test's exact empty-port
interleaving remains an inference. Independent review of the stable three-file
implementation found no material issues in grouping, privacy, checkpoints,
descriptor/temporary-file cleanup or no-overwrite publication. The reviewer did
not rerun tests. `bash tests/source-tests.sh` then passed for the combined candidate,
including all 152 runtime checks and full namespace repository acceptance:
schema 1, ten scenarios, signer passed, release closures 14+18, no deferral.
Complete source-suite log SHA-256:
`e46ee181875e9e79fdb601814ec07fec5d49a8c79d00c4acbbba17fc7e91bc22`.
This result prose follows that executed suite; final documentation/diff checks
and exact-head protected CI remain required. No old VM result transfers to the
changed harness; the actual Marble recovery cause remains open.
Fresh Stock ext4 job 113986280411 passed twenty-one assertions. Supplemental
readback verified source/tree/Phase-A and frozen harness; the strict core consumer
is not applicable. Run `stock-20261009T202125Z-f6a5e449`, artifact 11643772203:
API ZIP SHA-256 `d1a1c310edb11c8f867c9d42be6f6c317d66cf62b715eb02154816f1bf6d946d`;
evidence archive SHA-256
`6cb77f47702a19c79e42afa7618b104173beabd0b054841aad8a615b519e2705`;
structured result SHA-256
`5d12db917cfb1eb824676c8171b826280c29cbba775cb014bc11f900be3175f7`;
independent receipt SHA-256
`a142105464c49ae46991d2b44c214c1a7a42183150c32cf1911c5b933ec308d6`.
After the corrected observer/readiness candidate passed source/review and PR79 was
created, the failed old release was cancelled. Terminal cancellation is confirmed:
three PASS, one FAIL, five cancelled. Btrfs job 113986280570, GRUB 113986280493,
LUKS/systemd-boot 113986280332, Marble/Stock-GDM 113986280515 and dual boot
113986280389 have no scenario artifacts. The bounded source-specific runtime
observer returned no remaining runs; this is not a global resource inventory.
No finalization/tag/release/Pages/public VM occurred. The retained results belong
to 127461 only and do not transfer to the changed diagnostic harness.
[PR79](https://github.com/snaplyze/arch-linux/pull/79) holds accepted source candidate
`d802ed29a991403af89816e6ab1cb442f114f1ea`, tree
`19969b851e0b985eceb9e1b972af2b0ac476cf36`, canonical source SHA-256
`79c542b68188a75e606006a455f745d0baef9f0adad00fff3674a6258b8d1f98`.
Required exact-head CI 37988082025/job 114014985049 passed, including full namespace
repository acceptance; complete log SHA-256:
`757ba53076e4345da8653dc49d2c0344871e57dd708cf5b9c6615c41f6f9685a`.
The required Source checks run belongs to app 15368 and the exact accepted head.
Live head/base, CLEAN/MERGEABLE state and all review threads (none) were rechecked.
Protected squash merge completed at 20:42:55 UTC; main
`69377c37a47c03c5f2d091d7cdea25a25d3cf5da` has the same tree/canonical source hash.
The sole checkout returned to main through a fast-forward fetch, preserving the
index and root-owned post-candidate evidence updates. Fresh main CI 37988828109
remains in progress. At 21:00 UTC, source-bound read-only outer-QGA observation
confirmed source wrapper PID 80048, package wrapper 118477 and archive-limit
test 118480 waiting in `futex_do_wait`, with zombie child 118560. No environment,
raw arguments or private process data were exposed; protected executable links
remained protected. `tests/package-archive-limits.py` invokes the real verifier
with short integrity/decode deadlines. Timeout/reaping diagnosis is open; this
is a source-check obstruction, not evidence of a desktop regression. The shared
runner has not been restarted. New child/build/VM/public gates remain open.
Public latest is 1.0.6; workstation packages/settings have not been changed.

### Archive inspection alarm/wait-lock race

The main CI obstruction has a deterministic local reproduction: the one-shot
`SIGALRM` is delivered immediately after CPython acquires `_waitpid_lock`, before
its `try/finally` release is established. Raising `SystemExit` at that point
leaves the lock held; verifier cleanup kills the child but its subsequent wait
blocks on the same lock. This matches the observed sleeping parent/zombie child,
although that original process has no Python stack trace. The official
[Python signal guidance](https://docs.python.org/3/library/signal.html#note-on-signal-handlers-and-exceptions)
describes this asynchronous exception hazard. The regression injects a real
signal into real subprocess waiting, with an independent five-second timeout.
Against unchanged main, integrity and decode cases both timed out:
`python3 -B tests/package-archive-limits.py ArchiveLimits.test_alarm_in_wait_lock_acquisition_reaps_before_pending_signal_delivery`
— EXECUTED_FAIL, two subcase errors; log SHA-256
`4e8c9fd07b33b78b66858ab5583378d1daef0c656e560f1dca6a8eb792a58344`.
The one-shot injector disarms the original timer before delivery, preventing a
second artificial alarm from accidentally rescuing the deadlocked cleanup.
After this reproduction, the hung main CI 37988828109 was cancelled; terminal
job 114017496279 completed at 21:04:55 UTC. Container/network cleanup passed,
and the bounded source-specific process observer returned no remaining source
wrappers (not a global inventory). Complete cancelled-job log SHA-256:
`07ed84f2b8fdc7b2c377fe6e1d3e9bd8f1045965aa6dd4c9cc0a544a55026ef5`.
The corrected candidate remains pending. No shared runner restart, host update
or protection change was performed.

The first focused correction masks `SIGALRM` only over native timed wait and
kill/reap/pipe-close, leaving launch, decoder and parser alarms active. Its
real-signal acquire-gap test passed (log SHA-256
`fa9a20fc6cee27d7eee932bb3a85d98cefb2bb2b3415368c1d0b77464408636d`);
all sixteen archive tests passed (log SHA-256
`96b21696486ebfcaa651771e71d6e88d4ed2691a3f09cf4df6bd98621c927840`).
`bash tests/source-tests.sh` also passed, with full namespace acceptance, log
SHA-256 `aa9c0d2c7fb5176de5373d9a13c5a7c2a833145f78128b5a9bf5982e9f7f36ea`.
This working-tree result is historical, not an accepted candidate: independent
review found a second mask-acquisition race. CPython changes the native mask
before checking pending Python signals and returning its old value; an
exception there prevents assignment of the original mask. Cleanup can then
restore the already-blocked mask. Review reproduced the leaked blocked alarm;
[CPython signal implementation](https://raw.githubusercontent.com/python/cpython/3.14/Modules/signalmodule.c)
confirms that call ordering. A pre-mutation mask snapshot and exceptional-return
regression are required, followed by fresh archive/source checks and review.
No protection or timeout is intentionally weakened to obtain PASS.

The revised correction snapshots the original mask before acquiring a child;
mutating block operations cannot replace that snapshot. Nested cleanup performs
kill/reap/pipe-close even when blocking changes the mask and raises before
returning. Deterministic exceptional-return RED reproduced both mask leakage
(wait entry) and an unreaped child (early cleanup), log SHA-256
`d5fff522e1296c789cefcea3190dd79d63b8cc1e788e33031dfa29f40e4e8853`.
The corrected test passed, including caller mask/handler/periodic timer, reaping,
pipe closure and temporary cleanup, log SHA-256
`1dd935566e54e8d6820f2832d578c7e92ab37d2875ad2381e9ce18769488507a`.
`python3 -B tests/package-archive-limits.py` passed all seventeen tests, log
SHA-256 `97095c3d9bf11f31f6f9a94f544ed65c6e9b940fec12d048f4ee971a48a4547f`.
Independent revised-delta review found no material issues and reran both focused
tests successfully. Launch/decoder/parser alarms, native monotonic deadlines,
resource caps and process-group cleanup remain intact; blocking OS reap after
SIGKILL retains its existing operating-system limitation. The original hung CI
has no captured Python stack, so its exact interleaving remains an inference
from matching process state and a reproduced real-signal race. Fresh full source
checks subsequently passed: `bash tests/source-tests.sh`, EXECUTED_PASS,
including all seventeen archive tests, 152 VM runtime checks and
`REPOSITORY_CHECKS_RESULT schema=1 namespace_fixtures=full scenarios=10 signer=passed release_closures=14+18 deferred=none`.
Complete final working-tree suite log SHA-256:
`0c4342ecb9ee7b37faf57a13a9d598701352ab8707073379e8b8a9e312e3656c`.
Protected exact-head CI, fresh main/build/VM/public delivery remain required;
no new release is claimed.
[PR80](https://github.com/snaplyze/arch-linux/pull/80) holds clean candidate
`ba63e63f372595bf64b0052e39cfd06ae40a1e65`, tree
`5e87a40a9d071d62cbe8643efa5d2b976bd934c1`, canonical source SHA-256
`a1d7d39900a69114f015ac7e1d1a91b6c2a60f72d7b446c18a8be5a3c515361f`.
Required exact-head CI 37992671357/job 114030600961 passed all source checks,
including seventeen archive tests, 152 runtime tests and full namespace/signer/
14+18/no-deferral acceptance. Complete CI log SHA-256:
`67127037cf121a95669b54a42ea6edb215d481d1150386642201626b2ba9147b`.
The required check belongs to app 15368 and the exact accepted head. Live head/
base, CLEAN/MERGEABLE state and all review threads (none) were rechecked before
protected squash merge at 21:23:10 UTC. Main
`6ef601b805325f9e886c335a48a16366a96e3797` has the accepted tree/canonical hash.
The sole checkout returned through fast-forward fetch, preserving the empty
index and exact SHA-256 of both root-owned post-candidate documents. Fresh main
CI 37993132347/job 114032185995 passed the full required suite, including full
namespace repository acceptance. Complete main-CI log SHA-256:
`a21aeb3fd2fd399684f1a96f5eab6ee8cec9db4eedf137e03979213c8607dc08`.
New child/build/VM/public gates remain required; public latest stays 1.0.6
and the workstation is unchanged.

The additional `python3 maintenance/check-sources.py --network --report ...`
advisory observed forty sources at `2026-10-09T11:21:02+00:00`: fourteen unchanged,
fourteen drift and twelve error records. All errors were direct AUR Git queries;
the structured overall result is `error`, even though this advisory command
exits zero. Arch reports Shell `1:51.0-1`, GDM `51.0-1`, GTK `1:4.24.1-1` and
libadwaita `1:1.10.0-1`, matching the candidate's reviewed platform. Marble latest
remains 50.0.0; the No Screenshot Box catalog endpoint responds for the retained
GNOME-50 v6 input. That catalog response does not qualify its project GNOME 51
port or replace functional VM testing. Other drift findings remain advisory;
no source pin or acceptance baseline was automatically changed.
Manifest SHA-256:
`c146c1234307d6b616a356c0abfafaee195bcfc66dbee8daabda12c1024b5353`;
report SHA-256:
`04bd863584a32dd6965ecb4710dca3b301e4dd3a4a928494090c462069b7f416`.

After the owner's report that AUR had recovered, fresh direct `git ls-remote`
queries for Plymouth and Bibata succeeded. The repeated full network advisory at
`2026-10-09T11:43:40+00:00` queried all forty sources successfully: 23 unchanged,
17 drift and zero errors; all twelve direct AUR Git observations succeeded.
Overall status is `advisory`, not an error and not a no-drift verdict. Plymouth
and Bibata HEADs still match their retained reviewed commits. The source manifest
is unchanged; new report SHA-256 is
`9134962413715a93c25c038a97b97c0182d879dd50a3df447d68427f2d4f50cc`.
A further direct availability check at 19:28 UTC succeeded for Plymouth and Bibata;
both HEADs still match the retained commits. This is a fresh transport observation,
not a replacement for the forty-source advisory or installed-system acceptance.
The earlier failed queries are not rewritten. Primary AUR remains the first clone
attempt; only a clone failure selects Arch's official GitHub mirror, after which
the same immutable commit, archive and metadata predicates apply. The existing
primary-success fixture requires zero mirror calls. No source pin, release input
or workstation package changed for this availability recovery.
The subsequent GitHub API readback still reports Clipboard Indicator PR 641 as
open/unmerged, with head `39a0f9077daca21a62adaa975eb6a03bda499f27`, exactly the
candidate's retained source. Its real functional acceptance remains required.

Independent read-only classification of that fresh advisory against main
`b10e1158824d8191640f22b4a9f8e591aa59be92` found no additional GNOME 51 blocker.
Eight findings are rolling Arch package observations; four concern historical
extension source/recipe inputs superseded by the signed bundle. Paru/Pikaur are
optional helper proposals, while Gum 2 remains subject to the previously
reproduced styling incompatibility. The exact
[Colloid comparison](https://github.com/vinceliuice/Colloid-gtk-theme/compare/6c2dc65865628bda9fdc8157a30cd5eda6fd41f9...fe11342f37f124f1b29d44cf33e9a06053f4bba2)
still changes only unshipped Cinnamon/switcher files; the consumed SPDX license
text retains its earlier byte-identity decision. These are scoped review results,
not new PTY or VM results. The monitor's GNOME 50 accepted observations remain
unchanged pending the actual GNOME 51 upgrade, GDM and public-delivery gates;
supported profile tuples and accepted advisory observations are distinct.

## Prepared release 1.0.7 — archive deadline and filtered lifecycle candidate

[Release 37993529797](https://github.com/snaplyze/arch-linux/actions/runs/37993529797)
started after successful main CI for `6ef601b805325f9e886c335a48a16366a96e3797`,
tree `5e87a40a9d071d62cbe8643efa5d2b976bd934c1`. Prepare job 114033566501,
clean build 114033659829 and protected unsigned readback 114035580665 passed.
Independent source transport readback
and deterministic child transformation passed:

- source child: `a5cb4b5859fc82918e2b8c7b8f5c897b7a62a376`;
- source tree: `039c18216f7c47c0e3469df47da65052cdaeef44`;
- canonical source SHA-256: `34fe262d3a202e46dedee283e43b38bf3342db40f6698d422018900c6a9a1849`;
- source artifact 11645787579 ZIP SHA-256: `4fda86dacaf8721f8a71867b8b5addec187e605b80a06c0eb80421d2383b19dc`;
- bundle SHA-256: `1f6c3cbb14b142cf7013d700dc47cfb57bb08718ef8efb2fa73850036300ccb7`;
- installer SHA-256: `e6228b0f655d5551eaf5cc8d085ea8111b24df3930b27cc78700d0944432ff71`;
- frozen ten-file harness SHA-256: `98731115e4df3004378c69134a0cb38a23d14b4e6d80e55b5f7e51d334219995`.

Independent unsigned artifact readback passed separately from the full Git-bound
CI entrypoint: artifact 11646058244, 6,133,654 bytes, ZIP SHA-256
`8d2d1f3afcbaf583dadd829b084373eed4d83d1d7ce646d4fc02568b9946207b`;
BUILD metadata SHA-256
`3e60a6d2e8f488081137ac145d27667af09276c35b26bd9b7258aa6cc4f064e4`;
UNSIGNED manifest SHA-256
`cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`.
Exact sixteen files/fourteen manifest rows, schema-2 source closure (212 files,
including bytes and Git modes), pinned epoch 1787529600, seven PKGINFO/BUILDINFO/SRCINFO/recipe
closures, 19,564 MTREE files and all seven production payload validators passed.
The temporary immutable source export was removed. Receipt SHA-256:
`a25afa31bfbf53799a5000332506661781f5e80996b9333dbf680b69b3e1a08f`.

| Package | Candidate version |
| --- | --- |
| arch-linux-keyring | 1.0.0-9 |
| arch-linux-gnome-extensions | 1.0.0-7 |
| arch-linux-marble-shell | 50.0.0-8 |
| arch-linux-colloid-gtk | 20260808-11 |
| arch-linux-colloid-icons | 20260829-7 |
| arch-linux-marble-profile | 1.0.0-12 |
| arch-linux-marble-gdm | 50.0.0-10 |

Snapshot job 114035905275 passed all five release-host gates (unflagged/full
namespace repository acceptance, root publication boundary, ordinary and
privileged keyring modes) and Phase-A signing. Complete snapshot log SHA-256:
`424dfcfe0d7e9c01a3dccff4f70f386241fe8a8b6738699914935f0cc151e401`.
Independent Phase-A readback passed: artifact 11645864418, ZIP SHA-256
`c680f54a7dcc315f0bfb7385336b4c2450f2ceeb16c09501424740b27597b508`;
exact fourteen assets/twelve signed-manifest rows, three release signatures and
twenty-five snapshot objects. Repository archive SHA-256:
`152a42b0dffdb6fcdf5df3f5b407e76328c317d162aa9c661e6b46aac5ef3575`;
RELEASE manifest SHA-256:
`461fe7456a31a58d9bb59e57e3610c7214eef18b5a34a7159e1eec1313d00196`.
BUILD and UNSIGNED bytes equal the independently verified unsigned artifact.
Fresh nine-scenario QEMU matrix started. Minimal job 114037244655 passed fourteen
assertions and the frozen strict consumer. Run
`minimal-20261009T213920Z-50e837bb`, artifact 11647180639:
ZIP SHA-256 `3b45994061f39dea3c136127026e54cfc1f6035e1cad70594b580366f56bb9dc`;
evidence archive `233ee3ce82ba70bdab459f1e414eb4c044dd07ae09ac53dcdae3c12313f21067`;
result `ca20ff90f07aaa5fdf6656f8b2034ae2c2c9651646289d2f869ca8cf677446ca`;
independent receipt `7121218c0890d0571aef266021db529972d60da1aded9e251b1673a2a65cfa65`.
Source/tree/installer/frozen harness/Phase-A/ISO bindings were independently
verified. Core Stock job 114037244800 passed twenty-two assertions and its
frozen strict consumer. Run `luksgrub-20261009T214752Z-4b3840f4`, artifact
11647880303: ZIP SHA-256
`afe4670b8039b442a393a6ac15b9b4577e6dc41f8b51491771220211c68cc5ed`;
evidence archive `dbe30178eb692618d080245053779b481d11be1449207c63751140d8d9f8c336`;
result `9594a60d7b69d7d76ceb7294881d4aa0b95351c4e654145d931175d9bc17e43f`;
independent receipt `bec60784ac1cd66e9603232a0118e73d555659e2e6031fc356c74d16e8f838f1`.
Its source/tree/installer/frozen harness/Phase-A/ISO bindings were independently
verified; real login/lock/update/reboot closure passed. Primary Plymouth and
Bibata AUR paths were observed without mirror transport. Exact official patch
versions are NOT_OBSERVED in this compact evidence. Prior child results remain
historical. Supplemental Stock ext4 job 114037244698 passed twenty-one assertions.
Run `stock-20261009T222235Z-e6fd0d60`, artifact 11647899177: ZIP SHA-256
`253c7fd54874d45c4b65681e18092ce53618282bfccd4752202bb26cb75e7a69`;
evidence archive `5ae4db4400f4f915ae6650e74d44941aea2fdaffd27cd976c14bc2851cd74c70`;
result `bb03f3eaa534aeebf4ae5e4c99fb2e9bacb10aa19c462cef2ea7f6dfdbe58c83`;
independent receipt `fbea8d65ddddca7a35a37da76ae836bdb5d430f1743cb6e14e1ed8c7ba4efc67`.
Exact child/tree/Phase-A/frozen-harness bindings passed; the strict core consumer
is not applicable to this supplemental scenario.

Core Marble job 114037244740 failed at `extension-upgrade-dash`, firstboot,
exit status 1. All eight preceding assertions passed, including authenticated
six-package 1.0.6 + four pinned AUR owners + exact installer local-v6 migration
by plain signed `pacman -Syu`, preservation of preferences/original directory
custody, real GDM login and all eight extensions active. Functional Dash launch
has no receipt after its thirty-second wait; Clipboard/No Screenshot Box and
postreboot functional checks were not reached. The exact failing mechanism is
not yet established. Prepare emitted a successful-check stderr warning, but
probe stderr was not retained in the compact failure artifact.

Run `marble-20261009T220435Z-69bacdab`, artifact 11648431621:
ZIP SHA-256 `72d2b5eb76ed010f1f56451c3a8c1f55754e29d853f42f1c75a66cc52a7e8c27`;
evidence archive `3a6fcfde76c76014941a498142ddb203deeba59a2394abf96c48c32b6749e826`;
result `b3d6d4650b343871362d85a81490ec3a889fc737abe24da97e79f7ed84530adb`;
failure receipt `fb82502a44409ed400f59c882485869394eb5743fbe29ae305e45bac346c76c2`;
complete job log `8ce799e7a760b31ac9ac66a73d2919eb9a3a84c43d65a434140b997de8e2fb14`.
API transport/safe unpack/source/tree/Phase-A/installer/ISO/frozen ten-file
harness bindings passed. The frozen PASS consumer correctly rejected FAIL;
full successful-core validation is not applicable. The remaining scenarios were
subsequently cancelled as recorded below; finalization/publication was blocked by
this result.

The filtered lifecycle observer now supplies actual chronology. Original Shell
start 110859663 us, before-logout checkpoint 149965885 us (39.106 s), extensions
enabled/early sentinel present. Shell process exit at 152861317 us is
`dumped`, status 11; unit failure at 152869955 us is `core-dump`, followed by
recovery-unit start at 152874474 us. After-logout checkpoint 163423701 us reports
extensions enabled; the returned session at 201908500 us remains enabled.
Both journal windows parsed successfully (seven/eight records), with no timeout
and no rejected/unclassified event. This proves a real SIGSEGV during logout,
without a retained stack proving its cause. Recovery-start alone does not prove
its settings command executed. This run did not reproduce disabled extensions
on return; no guard was disabled or settings reset to obtain that result.

Correction of earlier progress wording: the recorded baseline line explicitly
reports `shell_major=51 old_incompatible=4`. It reproduces an already-upgraded
GNOME 51 machine with the old signed project/AUR/local owners, then repairs that
layout through pacman. It does not establish a binary GNOME-50-to-51 upgrade.
That distinct major-transition acceptance is NOT_TESTED here. Source versions,
old-owner recovery and actual GNOME runtime majors must remain separate.

Read-only primary-AUR recheck at 2026-10-09T22:31 UTC succeeded for
`plymouth-git` and `bibata-cursor-theme` through `git ls-remote ... HEAD`.
Observed HEADs were respectively `9f9f75a18d8dd1d23ba2dbb6572eb4729fece9bd`
and `8b38756aa61bc7c782e41e117523c32ed6fdf57b`. These mutable observations
do not change reviewed source pins. The installer still attempts the primary
first and uses the [Arch-maintained read-only AUR mirror](https://github.com/archlinux/aur)
only after clone failure, in a separate directory with unchanged commit/archive/
SRCINFO/PKGBUILD verification. This transport check does not establish a build
from the new HEADs.

Focused probe-observation correction on main `6ef601b805325f9e886c335a48a16366a96e3797`
adds source/PID/exact-argv-bound process-started, app-activated, window-mapped and
window-focused observations. Its readonly validation mode never creates or
modifies functional process custody. Timeout remains FAIL; compaction now retains
that failure and typed diagnostics. A bounded exact synthetic desktop GIO lookup
emits only lookup/executable/first-favorite flags. It does not establish Shell
application-cache resolution. An already-exited probe yields unknown observations,
not proof it never started. Recovery unit `ConditionResult` is typed yes/no/unknown;
no raw journal/core/stack or unrelated preference data is exported.

Regression RED: three tests, one failure/six subcase errors, log SHA-256
`5eda52aea6c271e96f19a7863e5977d79bd10819ccc27edab61b57840865b151`.
Focused final twenty-seven tests passed (6.804 s), log
`633e3faa38652c27722ecef8b787181f02ef46d029b6dfd4b22827e41bf770d4`.
`python3 tests/vm/runtime-checks.py` passed all 156 tests (29.192 s), log
`0b507ab38faf4f33bd78e29203dcaad329332cdeedd85583c1e8575ebc0668a2`.
Native GJS checks used isolated XDG/GSettings contexts and did not activate GTK.
Independent stable four-file review found no material issue and independently
ran six targeted tests (1.553 s, PASS). The first full source run passed the
156 runtime checks and full namespace/signer/14+18 repository fixtures, then
failed ShellCheck on literal-JavaScript interpolation and unquoted diagnostic
reason strings (log `eceb5809acf9b4bcef6741e9c356d34b187fdd4e1f15b83f1f761aa988e8665b`).
Root quoted the fixed reason values and documented the literal JavaScript at
the exact SC2016 site. The corrected `bash tests/source-tests.sh` then passed,
including 156 runtime tests, all seventeen archive checks and the full
namespace/signer/14+18/no-deferral repository result; log SHA-256
`47e2b782d39b4f94dd522a67e5914b5e8d01a12d9a3b87c831622e22d68d22d3`.
This is the pre-stack-module-observer working revision, not acceptance of that
subsequent addition. Fresh source/protected delivery and VM gates remain pending. These changes improve failure observation; they do not
prove a correction of the Dash launch failure or the Shell SIGSEGV.

Primary-source review of [GJS 1.90 stack dumping](https://gitlab.gnome.org/GNOME/gjs/-/blob/1.90.0/gjs/stack.cpp#L24-37)
and [SpiderMonkey ESR 140 backtrace formatting](https://github.com/mozilla-firefox/firefox/blob/FIREFOX_140_17_0esr_RELEASE/js/src/vm/JSObject.cpp#L3088-L3114)
confirmed that the standard SIGSEGV dump provides module filenames, pointers,
line numbers and bytecode offsets, but no JavaScript function names. The focused
observer now retains only allowlisted public module labels and typed timing,
without raw messages, paths, pointers, line/offset values or cores. The exact
current-boot UID/Shell-unit/stream filter and frame grammar precede the bounded
129-record window; query time/output limits remain five seconds/262 KiB. Entire
windows validate before output. Unknown/private/foreign modules retain counts
only; the known Dash `fileManager1API.js` is explicitly allowed. It can associate
observed modules with the logout chronology; it cannot by itself prove which
module caused the SIGSEGV. The strict query treats journalctl no-match exit 1 as
unknown, not proven query failure or proven absence of frames. No upstream
candidate has been promoted.

Stack-attribution RED: two tests/ten subcase errors, log
`35cc921c723428a3f8dd7003e5871927ee42a3f482f3dbdbe4c36a1b24f21437`.
Four focused tests passed, log
`d8bca44dbe93f046a4333e65ede715d6273bcf9b8bf455b533c6fa75e4b5f40c`.
The final `python3 tests/vm/runtime-checks.py` passed 160 tests (31.012 s),
log `83a6a0847bfac0d6a47b0ac61746d1987d6c1520f40f2e8a1b2befd372591785`;
ShellCheck/syntax/diff/modes passed. Independent stable review found no material
issue and ran four targeted tests plus the updated formatter test. The first
full run after attribution passed 160 runtime tests and package/docs checks, then
portability rejected a concrete home name inside a negative fixture; log
`051bcfe5c6a59df8953a4f8d078c60e5ae7f404acb586b60efed0cbbb94cedcf`.
The fixture now constructs that private path from a test account variable, with
unchanged runtime bytes/rejection semantics; portability passed. The final
`bash tests/source-tests.sh` completed with exit 0: 160 runtime checks, seventeen
archive checks, documentation/portability/secret/agent checks, ShellCheck and
`REPOSITORY_CHECKS_RESULT schema=1 namespace_fixtures=full scenarios=10
signer=passed release_closures=14+18 deferred=none`. Log SHA-256
`7149587b4ec1111340cf9a930a28ce1ae098d4d0d585c5e1672388542746f209`.
Protected delivery/build/VM/public acceptance remains required. Obsolete failed
run 37993529797 is terminal CANCELLED: three PASS results (Minimal 14, Core
Stock 22, supplemental Stock ext4 21), Core Marble FAIL after eight assertions,
and five cancelled scenarios. Stock Btrfs systemd-boot reached seven installer
phases but no installed-runtime verdict/artifact; the other four cancelled
scenarios were queued/unrun. Its cancelled job 114037244680 reports job cleanup
complete at 22:54:09 UTC; log SHA-256
`4e0dab9d59a0bd8882dd1fb4f02647199750b921313159fc43766ee1925b50e9`.
The exact-source runtime observer returned no eligible record; that is not a
global host-resource inventory. No publication or workstation update occurred.

[PR81](https://github.com/snaplyze/arch-linux/pull/81) accepted final head
`5e162f6656ae196d7aa438f46d3cc57e23be4d4a` (implementation parent
`7c766594b8c86a9ca34387375caf9f6215128d26`). Exact-head CI 38001915628 /
Source checks job 114061747912 passed: 160 runtime checks, all seventeen archive
checks, full namespace/signer/14+18/no deferral and ShellCheck. CI log SHA-256
`471bc1efa309895f1eb7a8f64ce49f4e48d0be2a86b895a963212dee18cff1b7`.
The required check belongs to app 15368; exact head/base, clean/mergeable state
and absence of unresolved review threads were checked before protected squash.
Merge completed at 2026-10-09T23:03:03Z; main
`2414cef10db033f1807bf0a3729a259c5bdea6af`, tree
`2db191f5f9194d5cc95540f0ff1dbccc835b542e`, canonical SHA-256
`6762d0ef84a3532950005e5317d0cf462970340232cfbedf74d4483e6e4f0478`.
The sole checkout returned to main by fast-forward; index/working tree were clean
before root-owned documentary receipt updates. Pre-freeze independent review
inventoried all twenty-nine tracked Markdown files and found no mandatory stale
release claim outside renderer blocks. README/installation child rendering and
post-publication reconciliation remain separate gates. Fresh main CI 38002450811
/ job 114063479730 passed; log SHA-256
`f85c02651aa09972763d61e694980a8b72bf61a3abfe2170f205dfdda1b246a6`.

[Release 38002781657](https://github.com/snaplyze/arch-linux/actions/runs/38002781657)
prepared child `a5e41978f40e8596a6cee9d96b1139e6a11c93c2`, tree
`bb96b604ad236c6817f63fe7bf3105100eea1036`, canonical SHA-256
`659b492d48c4c584ca59d81ec7ec84f836f33278a3e1ace36410d6f88d13adcd`.
Prepare job 114064561779 passed. Independent source artifact 11649849132 readback
passed: ZIP SHA-256 `2979bd2b10e19443b2230a4d6f67f4b8ebbf75224eee5332c5b9206e333b37d4`,
bundle `7a714abdc8a5f259e9a0b554b5c9d9fe30d40761e0ba27428c27290119e89f85`,
receipt `a11334dc472fdbc3c0bd41a43482eccabf263a2966ece5ada73d9659eab29f33`.
Main/child/deterministic transformation, exact installer and generated 1.0.7
README/installation bootstrap pins were verified. Installer SHA-256
`e6228b0f655d5551eaf5cc8d085ea8111b24df3930b27cc78700d0944432ff71`;
frozen ten-file harness aggregate
`bcf965237c5a9feb458b6d92e6b51101dd237075209e551cc82aef884d583960`.
Clean build job 114064630959 and protected unsigned readback job 114066043084
passed. Independent unsigned artifact 11649319044 readback passed: exact sixteen
files/fourteen manifest rows, 212 immutable Git blobs/modes, seven package
metadata/payload validators and 19,564 MTREE files. ZIP SHA-256
`9c5abe3803e3bbdcc9b9176a86f29e97e641471df45eed470020c038ff8d2766`;
BUILD-METADATA SHA-256
`dfb16f7f6ae9ea0d05ac643f02f9853306e80b500a454a53046060e65a79bdaa`;
UNSIGNED-SHA256SUMS SHA-256
`cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`;
independent receipt SHA-256
`21926bb31648a01e2c72217daf9b54fceda8ebd8189f91c684689908f5fe8892`.
The independent validators are scoped checks, separate from protected CI and
signing. Snapshot job 114066294101 passed, including both full repository runs,
the root publication boundary and ordinary/privileged keyring modes. Snapshot
job log SHA-256
`541a6086b0f7c2068706acf9cfc908f8e3b1a08427a96be6184830aa7f19dc24`.
Independent Phase-A artifact 11650196765 readback passed: fourteen assets,
twelve signed checksum rows, three trust-bound signatures and twenty-five
snapshot objects. ZIP SHA-256
`9542201205f810177e77d507b1fd5e54f68d78002bb2806bc836a9117e3bf3b9`;
RELEASE-SHA256SUMS SHA-256
`e22a25679f247867a1fb6f3f19c9e37cf9bd45a9fb39c0e3ab65d3bebf73ffb3`;
repository archive SHA-256
`4d0a82cd4492be7c53c0511ed20b6bede5810f8464306c0f98d30d1e7e7ea446`;
receipt SHA-256
`414d7aa43bbde511e6748d6b5c2c62c54d72535c3fe848afe7778e28814b8462`.
Nine fresh VM jobs materialized; Minimal job 114067261370 is active. A read-only
outer-QGA metadata query was unavailable (guest agent not responding); this is
an observer error, not a VM product verdict. No shared service was restarted.
VM/final/public gates remain pending. No old child PASS belongs to these inputs.

At 23:33 UTC the official AUR primary Git endpoints again answered both bounded
`git ls-remote ... HEAD` checks with native status zero. Observed advisory HEADs:
Plymouth `3347bb2b0ace31f6fa07e080f2886cd04e3fea1d`,
Bibata `5d418e2c328f988b0b5c4fc51e6ca9619bfda293`. Accepted source pins remain
unchanged. This endpoint check does not prove which transport an active VM used;
that requires its installer evidence.

Local documentary receipt checks after these updates passed:
`PYTHONDONTWRITEBYTECODE=1 python3 tests/docs-checks.py` (twenty-nine files)
and `git diff --check`. This is a local documentation check, not new source,
package or VM acceptance. Log SHA-256
`6a6e948ba88d743c6182cfdfb1313216dc038a3c3fa6032c9492e3538174d696`.

Independent official-source freshness check at 2026-10-10 00:01 UTC found
unchanged Arch metadata: [Shell](https://archlinux.org/packages/extra/x86_64/gnome-shell/)
1:51.0-1, [Mutter](https://archlinux.org/packages/extra/x86_64/mutter/) 51.0-1,
[GDM](https://archlinux.org/packages/extra/x86_64/gdm/) 51.0-1,
[GTK4](https://archlinux.org/packages/extra/x86_64/gtk4/) 4.24.1-1,
[libadwaita](https://archlinux.org/packages/extra/x86_64/libadwaita/) 1.10.0-1
and [GJS](https://archlinux.org/packages/extra/x86_64/gjs/) 2:1.90.0-1.
[GNOME MR !4214](https://gitlab.gnome.org/GNOME/gnome-shell/-/merge_requests/4214)
remains open; the [Arch Shell recipe](https://gitlab.archlinux.org/archlinux/packaging/packages/gnome-shell/-/blob/main/PKGBUILD)
still consumes the 51.0 tag without that shutdown correction. This is advisory
research, not VM acceptance or causal proof. No source pins were changed.

Narrow upstream control-flow review added previously missing evidence.
At exact [51.0 source](https://gitlab.gnome.org/GNOME/gnome-shell/-/blob/2177bdf9624b2d285de7c1d34274073d3769d6b8/js/ui/extensionSystem.js#L54),
the manager's shutdown callback deletes the recovery marker; it does not disable
extensions. Its ordinary `_disableAllExtensions()` lifecycle/settings routine
is not wired to whole-Shell shutdown. At [MR head](https://gitlab.gnome.org/GNOME/gnome-shell/-/blob/b0ee94efe41c77bb84ec0da1a11092e76ebbd0d7/js/ui/extensionSystem.js#L99),
manager disable first drains pending operations, then synchronously disables
active extensions in reverse order and removes the marker. The corresponding
[main callback](https://gitlab.gnome.org/GNOME/gnome-shell/-/blob/b0ee94efe41c77bb84ec0da1a11092e76ebbd0d7/js/ui/main.js#L220)
runs a GLib loop until its asynchronous shutdown handlers settle. This source
inspection does not establish ordering against backend disposal, the VM crash
cause, a faulty curated extension or a runtime fix. Do not port the candidate
wholesale on this evidence; inspect the next bound symbolic/recovery receipts.

The stalled read-only observer remained unavailable on a second finite QGA
query. A strict, batch SSH alternative rejected an unknown host key; trust
settings were preserved. The outer VM's CPU and disk counters continued to
advance, but those unbound counters do not establish progress of the nested
scenario. No shared daemon or VM was restarted. The current public job remains
active without a product verdict; await its compact bound artifact.

Read-only timeout review distinguishes the outer job from installer completion.
The QEMU job has a 330-minute overall limit; the accepted-ISO transfer precedes
the harness and uses curl retries without a per-transfer maximum. The harness
starts its 7,200-second installer-marker wait only after ISO readiness and
bootstrap. Job 114067261370 started at 23:16:55 UTC, so its outer deadline is
approximately 04:46:55 UTC on October 10; elapsed time does not identify its
current phase. Ordinary harness failure runs cleanup and writes a FAIL result
for the always-run evidence upload. A hard job timeout can interrupt that upload.
These are source-reviewed bounds, not an executed timeout or installer verdict.

At the October 10 continuation, public terminal logs established that Minimal
job 114067261370 downloaded the complete accepted ISO at 23:18:21 UTC, verified
its hash and passed KVM preflight at 23:18:24. The outer job cancelled at
04:47:08 after its overall limit; packaging found no completed result and no
Minimal artifact was uploaded. The subsequent stalled harness stage remains
unknown; the accepted-ISO transfer was not the cause of this delay.

Three fresh FAIL artifacts were read back against exact child `a5e41978`, its
tree, the ten-file harness aggregate and the four signed Phase-A input hashes.
Their verdicts remain FAIL; the strict PASS consumer correctly rejected them.

| Scenario / artifact | Run ID | Passed assertions | Failure receipt SHA-256 |
| --- | --- | ---: | --- |
| Core Marble / 11661472121 | `marble-20261010T052637Z-b587669b` | 4 | `b18c80648589b21a23b5849f1c93b3bb8dc1404eacfc5ee3bc737efed965520e` |
| Core Stock LUKS/GRUB / 11661380256 | `luksgrub-20261010T044845Z-75c295a0` | 15 | `31a5f8f78cdaa0035b726d1418525ddce6aac6cb51cf8e044c7e6cd349cc37f3` |
| Supplemental Stock ext4 / 11661984270 | `stock-20261010T061215Z-ca780fae` | 15 | `444bbbbde7ebda7b20324b0f2d16c485000fddad204117096cba70452cfffe31` |

Marble failed the fresh named-user session wait (QGA script line 4827, frozen
source line 4817 after its ten-line manifest/probe prefix). Before original-user
logout, extensions remained enabled and the early-failure marker was absent.
The filtered event window then recorded Shell killed with signal 9 and unit
result `timeout`; the recovery unit started, but its later condition/ExecStart
remain unknown. This is not the earlier SIGSEGV, and the stack query supplied
no attributed frame. Authentication/UI readiness versus session startup remains
unresolved. Stock carries no prefix in these phases: both errors map directly
to source line 4913, the required `LockedHint=no` assertion after password input.
An optional pre-input Stock screenshot showed a password field, but it does not
prove PAM readiness, credential delivery or successful authentication. Preserve
all real-login and unlock requirements; do not reset settings or disable guards.

The cancellation request for the remaining release jobs succeeded after these
mandatory core failures. The terminal inventory is three FAIL and six cancelled;
the last active Stock job's runner cleanup completed at 06:55:46 UTC. This is
job-bound cleanup evidence, not a global resource inventory. The supplemental observer stopped because of service usage
limits; root owns remaining observation. A fresh finite outer-QGA probe after
the job transition still reported an agent error, and the workstation remains
unchanged. Next source work is bounded phase/authentication diagnostics before
any unproven input or product correction; no repaired desktop/publication claim.

### Subsequent local diagnostic candidate — 2026-10-10

Host phase begin/end observations expose only controlled scenario/source/run
identities. Authentication failure diagnostics retain bounded current-boot GDM
PAM event types and monotonic timestamps for the selected account, never raw PAM
messages. Invalid windows reject atomically; unknown queries remain unknown.
These observations do not establish successful authentication or identify the
desktop defect. Diagnostic or UID lookup failure preserves the original guest
failure status; no settings, credentials or acceptance thresholds are changed.

The actual `qga_verify` function, invoked by a conditional caller with `die`
returning failure, incorrectly accepted six rejection cases: guest exit failure,
missing marker, invalid capture, truncated output, invalid PID and failed start.
The regression first failed all six cases, then passed after explicit returns
were added to construction, transport, capture and evidence failure paths.
Successful large-script stdin transport remains covered; rejected checks do not
emit phase-end observations. This is a harness correction, not an attribution of
the preceding VM authentication failures.

`python3 tests/vm/runtime-checks.py` passed 167 tests (native exit 0).
Its log SHA-256 is
`f9a39a3b79b9a0ddf65a3104b9349b4e435a3c3eeddcc7503a671ccd21a729bd`;
the conditional-caller RED and focused GREEN logs are respectively
`55c73f7f9bb08a85549057f40b5ca693544c94173c2a1aef28050a9527a6f85e`
and `03ebe586969d0c313493c684396484301c0f73da846ff5b2fc5127235d5b1ec8`.
The first 166-test run failed three extracted-function fixtures because the new
progress helper was missing; those fixtures now include the actual helper and
retain readiness-before-bootstrap/credential-delivery assertions.
The first complete source run stopped in another extracted-wrapper fixture,
whose exact-stdout check lacked the actual progress helper. The fixture now
checks functional output separately and requires an end observation only for a
successful check; `bash tests/static-checks.sh` passed. Independent review also
reproduced returning-error fallthrough in the public repository capture subtree.
That finding is now corrected across capture, signature, retention and identity
writing. The actual-helper regression replays only those four original HEAD
helpers in memory: ten rejection cases falsely accepted before the fix; success
and all ten rejection cases passed afterward. RED/GREEN log hashes are
`c31713247398cc863fa6e3b99ea5349e8cfc4610b68bc068df731cf441267538`
and `7353875edd6441957ed5d8c364864a1e9278c4e660b2ed4e5eaf77b41b407ebb`.
The expanded runtime suite passed 168 tests, log SHA-256
`58e9dda986f3aa94de951bb0fac72a1c67900d05d29a9b54a07dfdb27704753b`.
An additional actual-QGA conditional-call case rejects a failed public capture
without emitting an end observation. Independent read-only review found the P1
resolved and no remaining material findings; four focused methods passed,
including the eleven nested public-capture cases. Controlled GPG responses prove
failure propagation, not actual signature or VM acceptance.

`bash tests/source-tests.sh` passed (native exit 0), including 168 runtime tests,
full repository acceptance (`namespace_fixtures=full scenarios=10 signer=passed
release_closures=14+18 deferred=none`) and ShellCheck. The subsequent changes are
only this result/checkpoint prose; the final documentation tree will be checked
again before protected delivery. No PASS is transferred from the previously
frozen child to these edits.

[PR82](https://github.com/snaplyze/arch-linux/pull/82) merged normally at
2026-10-10T07:32:12Z after the required exact-head Source checks and independent
review. Accepted head was `7d3c3801e29a9909e83051a17afff94cb66760a0`; resulting
main is `1e9c33d233f75066f88774d8c67f31903eeb5236`. Both bind tree
`a6c75fa26ed1363c3bdc1fc77b82854544af86dc` and canonical source SHA-256
`88201818783fdcfa565e4af1155f5d43fa48d5d1c397da5427c061d289d155e9`.
The final local source suite passed before commit, log SHA-256
`24b68ee88e0886c27e68947f9d69b511a3b24df91a8aef2cdbb93087873e588f`.
[PR CI38034505407/job114162038749](https://github.com/snaplyze/arch-linux/actions/runs/38034505407/job/114162038749)
passed 168 runtime tests, full repository scenarios and ShellCheck; the downloaded
log SHA-256 is
`48ab16f09790bc26287b0781ddfa8f3aeb7737e58b8046e83f6cbed9d14384e8`.
Before merge the live head/base matched, state was CLEAN/MERGEABLE, Source checks
were successful from app15368, there were no review threads, and the rules
required squash with zero approvals. The same clean checkout returned to main
by fast-forward. Main CI38034759530/job114162778020 passed; its downloaded log
SHA-256 is `6c5c53e0e6739c1951f6009c0c5bcbe9cacf8d639671311007ba7f97d7c5ac52`.
Fresh configured release
[38034970799](https://github.com/snaplyze/arch-linux/actions/runs/38034970799)
started from that exact main; new child/build/VM/public results are not yet
established. This later local checkpoint prose is not part of that accepted
source tree.

Fresh release38034970799 prepare/job114163397445 passed. Independent source
artifact11663765383 readback passed (native exit 0), with ZIP SHA-256
`3508d9ab751cc87664414daa478d3298dcfb06c17b464d44cfec46d04f74adc9`
and source bundle SHA-256
`492111cc974be0f0f8b68f598943dac914e4746c0132941219cd7f6eb63540fe`.
The verified deterministic child is `f62fcfba58c4df020ae44288099854c193348ce7`,
tree `13935a041cab61ac15bdee4d6d79617aba6ed6b5`, canonical source SHA-256
`3885ec4b187637b818ca477e13294701dac805437e88bd5371084dcef5efe73c`.
Installer SHA-256 remains
`e6228b0f655d5551eaf5cc8d085ea8111b24df3930b27cc78700d0944432ff71`;
the new ten-file harness is
`20ec8b2fceb52c7063cea05346ec54fd4b12cbfd2966b38b7bd5202944eb6720`.
Generated README and installation bootstrap blocks both use 1.0.7. The source
receipt SHA-256 is `89ab40747b2db72ba57dc2a8e17a30be0396faf7be532fd328a0306885361b11`;
objects were imported without changing references, the index or dirty checkpoint
documents. Clean build/job114163442094 is running; package/signature/VM/public
acceptance is not yet established for this child.

Clean build/job114163442094 and protected unsigned readback/job114164289158
passed. Independent unsigned artifact11663640966 readback also passed (native
exit 0), ZIP SHA-256 `1a8e4276dd26c6f42fa563610d919baa71465d67df1bcc8a9d89a23fd1e412b1`.
The exact schema-2 BUILD-METADATA SHA-256 is
`8d4fc8320dba2a10797f21bd2ef531f68d242063dc1c9950f95ef7264ddcb24d`;
UNSIGNED-SHA256SUMS is
`cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`.
All seven package metadata/payload validators passed against 64 exact child
package/trust/verifier blobs; `.PKGINFO`, `.BUILDINFO`, `.MTREE` and committed
`.SRCINFO` were checked. An immutable temporary validation fixture was removed
at the bounded readback's end; Git state and dirty documents were preserved.
The first independent attempt rejected a main-versus-child `.SRCINFO` mismatch:
the diagnostic had omitted the child's deterministic package-release changes.
It failed before creating unsigned output; the corrected readback used exact
child bytes. This was a diagnostic-tool failure, not a package defect or a retry
with changed release inputs. Snapshot signing/job114164447992 is running;
signed Phase-A, VM and public results remain pending for this child.

Snapshot/job114164447992 passed all five root acceptance gates: ordinary and
required-full repository fixtures each ended with full10/signer/14+18/none;
root publication reported the sealed closure and all FD/namespace/PID1/agent
boundaries passed; ordinary keyring mode reported the expected five scenarios
with privileged work deferred; privileged keyring mode passed full10/none.
The terminal log SHA-256 is
`8121aee158712c496de76d86f8953d21dc895556a6c9fc6c7e4a8d87ed363991`.
Independent Phase-A artifact11664575714 readback passed (native exit 0): exact
fourteen assets, twelve signed manifest rows, three outer signatures, and
twenty-five snapshot objects; BUILD-METADATA/UNSIGNED-SHA256SUMS match the
independently checked unsigned bytes. ZIP SHA-256 is
`00bf077a9903dc0b0f4d7ecf920da4957c67a79e61bc85ba4aa9c9b054197056`;
RELEASE-SHA256SUMS is
`7757c9a3bc5850ed6c339f9f052452ca6ed1c4d6ede0a3e457292f5afb9db5aa`;
repository archive is
`66f16102b5ae186b5007889f884903726c61fa32bbc99506dc44decf165173b4`.
The Phase-A receipt SHA-256 is
`abdfe0e9757f7bbf60b55234538c2704d9d14255d418f21da56a14e798791707`.
Nine fresh VM jobs materialized. Core Minimal/job114165043594 began its combined
ISO-download/scenario step at 07:45:53 UTC; eight other scenarios are queued.
The step state alone does not prove a boot, installer phase or guest progress.
No VM, finalized18 or public result is yet established for this child.

Core Minimal/job114165043594 subsequently failed firstboot after three assertions
confirmed accepted ISO, actual installer execution and normal installation
completion/poweroff. New phase observations show source binding at 07:47:22 UTC,
ArchISO/bootstrap/credential gate complete at 07:50:55, installer completion at
08:01:51, firstboot verification beginning at 08:02:36 and rejected guest status
at 08:02:41. The typed guest diagnostic is status3/source line1098, followed by
caller3088; Minimal carries no manifest/probe prefix. This maps to
`systemctl is-active --quiet NetworkManager.service` before the existing
`nm-online -q --timeout=60` call. Status3 alone does not establish activating,
inactive or failed service state; it does not attribute the older hard timeout.

FAIL artifact11663608194, run `minimal-20261010T074722Z-d3f5cff4`, ZIP SHA-256
`0d2afe745f0b248292288ffc9e25f1ba7d6357ccdf57f56e86e72a283ba4ffe4`
and archive SHA-256
`4249c3969c7f6a7417465b0a49c652cec32bdd61a500b41dc35070a03602a89f`
match the exact f62fcfba child, new ten-file harness and signed Phase-A hashes.
The strict PASS readback correctly rejected the FAIL result; separate failure
binding checked those identities and preserved the three preceding assertions,
without a PASS-consumer claim. Its result SHA-256 is
`7e7bb1a54cce50035b571aefa193c3d2a10fa4c8822f6ca0c41916eb89a2ae20`.
Publication cannot pass this attempt. At 09:18 UTC the root requested normal
cancellation after Core Stock LUKS/GRUB/job114165043582 had executed more than
75 minutes without accessible phase evidence. No current Stock verdict or cause
is inferred from that interruption. Terminal logs and any partial artifact still
require readback. The actual `verify_common` fragment reproduced status3 before its
readiness wait with a delayed-activation fixture. Moving only the existing
`nm-online -q --timeout=60` line before both active-service checks makes that
fixture pass. Five negative cases reject network timeout, inactive manager,
inactive guest agent, failed DNS and failed-unit output. This preserves service,
agent, connectivity, DNS, failed-unit checks and timeouts.

Worker execution: `python3 tests/vm/runtime-checks.py` passed 169 tests;
`bash tests/source-tests.sh` exited zero, including the revised 169-test runtime
suite and full repository namespaces10/signer14+18/deferrednone. Outputs were
retained in the worker tool transcript, not a separately hashed logfile. The
checked source-file SHA-256 values are
`64c776b5cee4c4265211892217d3705246dd69399c48e54ae21454686e0be47f`
(`tests/vm/guest/verify.sh`) and
`48c70a520b8355b9a883ad1827b17e2adef8cc59037d7c4d13ebb7c13a9b161e`
(`tests/vm/runtime-checks.py`). Independent read-only review found no material
issue and executed the focused six-case method plus scoped diff checks with
exit zero. Root integrated `bash tests/source-tests.sh` also exited zero; retained log
SHA-256 `e558bd09d12b53cf6a36cb37b8bbe39d06b2f843100dfe455e1b00b11058886c`,
including full repository namespaces10/signer14+18/deferrednone. Only this final
receipt prose followed that run; documentation/diff checks were repeated.
These are local source results; a fresh accepted child and real VM
transaction remain required. Status3 alone still does not establish the actual
failed guest service state or explain the earlier hard timeout.

Protected [PR83](https://github.com/snaplyze/arch-linux/pull/83) contains the
readiness correction; exact-head Source checks remain required. A further
bounded observer correction duplicates the existing `QEMU_PROGRESS` payload as
a standard GitHub notice. The original helper validated phase/state only;
scenario, commit, tree and run identifiers were raw. Both output forms now use
bounded allowlisted identifiers, with invalid values replaced by `-`, and retain
the original schema without a timestamp. Invalid phase/state emits nothing;
begin/end placement and acceptance conditions are unchanged. The RED regression
reproduced missing notices and identifier injection (log SHA-256
`b0737e54d0bdb1e7242af0f96146501da9e87c31a571aefb423ecac12d1451f3`).
Focused five tests, full 171-test runtime suite and static checks passed; runtime
log SHA-256 `ddbf550c281253de1a519aed65776ff6c845ed95311a123d6c2eb1368663738e`.
An initial runtime fixture-output filter failure was corrected and its separate
log retained. Independent read-only review found no material issue, ran five
focused tests and checked all nine actual run prefixes. Root integrated
`bash tests/source-tests.sh` exited zero, including 171 runtime tests, 29-document
checks, full repository namespaces10/signer14+18/deferrednone and ShellCheck.
Its retained log SHA-256 is
`a9c6b3978db1503127bcd12117a4fceb29977b888c8290eb364579f1770b1a5e`.
Only receipt prose followed that run; documentation and diff checks are repeated
before committing. This source PASS is not VM recovery or public delivery.
Live notice visibility is NOT_TESTED: the active Stock check run exposed zero
annotations when queried; this does not prove that future notices are available
before a job completes. No workflow, timeout or VM assertion was weakened.

The release is terminal CANCELLED; Stock ended at 09:19:19 UTC. Its retained
job-log SHA-256 is
`7598c0fd5ddd8b226fae177f189106d30d6d14e96bdedbe20a842f9542253e7c`.
The last observed phase was installer-completion (begin 08:09:16 UTC), with no
end marker before cancellation at 09:19:12 UTC. This scenario did not establish
firstboot or GNOME authentication acceptance. The archive step lacked
`result.json`, and no Stock artifact was uploaded. Runner-owned cleanup reported
completion; orphan VM processes were terminated by the runner. The cause of
the incomplete installation and missing cancellation evidence remains under
diagnosis. These observations do not convert interruption into a product FAIL
or prove that the normal two-hour installation deadline would have failed.

PR83 head `b1cab9dbaa9e8b7e6d2b46f3d6b5c10c8b4cc896` passed exact-head
[CI38041152745](https://github.com/snaplyze/arch-linux/actions/runs/38041152745);
retained job-log SHA-256
`2c50fc5166932cfad9633d3d9aad52cf401c71ecc34a60144824a8c8629884e7`.
This PASS belongs to that head, not the following cancellation correction.

An actual-helper subprocess regression reproduced direct SIGINT/SIGTERM
returning zero, finalizing storage but omitting FAILURE/result metadata. The
signal trap previously reused the preceding command's status. Separate signal
traps now exit130/143 through the single EXIT cleanup, and the installer wait
sets its actual `installer-completion` phase. The staged workflow's final
invocation uses `exec bash`, removing the intervening step shell. The tests
extract actual cleanup, result builder, wait and phase code; both signals produce
one finalization and nonzero FAIL metadata, and the executed workflow invocation
does not resume its shell. RED log SHA-256
`a982379376259e06fca1cc4baadc5e65d668638e171f35fe2fa36eda466df84a`;
GREEN log SHA-256
`78897bee628c2237d72d1bac3907b55850a3f471c92bbb4762c8bf7b5dcfb7e2`.
Runtime173, actions-release28, static, agent-contract and Bash syntax checks pass.
Independent read-only review found no material issue and executed both focused
methods (both signals, actual failure metadata, one finalization, shell handoff).
Root `bash tests/source-tests.sh` exited zero with runtime173, documents29, full
repository namespaces10/signer14+18/deferrednone and ShellCheck. Retained log
SHA-256 `c42cc42d23ba71e621063e6fbeda1e2a89add113cd84598ef2f7050dd9a7ac1c`.
Only receipt prose followed this run; documentation and diff checks are repeated
before committing. Exact-head CI and fresh VM/public acceptance remain required.

The [runner cancellation protocol](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-cancellation)
signals the step entry process, waits 7.5 seconds, sends TERM, then waits 2.5
seconds before killing the process tree. Existing cleanup may take longer;
this focused correction preserves its resource identity checks and compaction
and does not establish reliable artifact delivery under that deadline. The
historical cancellation log does not reveal which signal reached the harness.
Real cancelled-run evidence delivery is NOT_TESTED; an interruption is never a
successful installation or migration receipt.

Protected [PR83](https://github.com/snaplyze/arch-linux/pull/83) merged at
2026-10-10T09:35:29 UTC after mandatory exact-head
[CI38041607403](https://github.com/snaplyze/arch-linux/actions/runs/38041607403)
passed for `66f02733f6efcf45a833cfb4a997da3cc5444620` (GitHub app15368).
CI log SHA-256
`d2d7fcdf27b6656341f07ec491a612bd7a431bdc6e2aef968eae0166c5d6d38b`.
The sole checkout returned to main by fast-forward at
`e4c96c0a1a5731f50f82f34741d39f48c6828f6f`, tree
`d82c165928402cb3d35cd2cf0a9869ca09c162c6`, canonical source SHA-256
`206474be7fe62b7f8cd370faad107726a70cdd93ae0dfe028fb67bd821e0e3ec`.
[Main CI38041929663](https://github.com/snaplyze/arch-linux/actions/runs/38041929663)
passed; job-log SHA-256
`f8b14a4263f79466708998a482addafa081eba98bbcb6a28680f369ff14a2e7c`.
These source receipts do not close the fresh package, VM or public delivery
gates; the workstation remains unchanged and 1.0.7 is unpublished.

Fresh configured [release38042159246](https://github.com/snaplyze/arch-linux/actions/runs/38042159246)
prepared deterministic child `912cfae4ca53f9a9d6d6c208bb69f19a37dfbd64`, tree
`6128fed500a8619a7f6ed40a8fc1021073b32daf`, canonical source SHA-256
`ecb64c25c5620861d0e5a56e71ce7ef015be658980a481bdaffca3c16976c2c4`.
Prepare/job114184389202 passed. Independent artifact11666177590 readback
verified ZIP SHA-256
`73e90fb8e8944227c68f3b0bb4a0227f583caafdb181e72e60a2806b9fb1a882`,
bundle SHA-256 `c6da7ba522ea7a99d55b0a917842c032bf18c737b75b15fe82526a30f20ffc1e`,
origin/child identities, deterministic derivation and generated 1.0.7 README and
installation pins. Independent source receipt SHA-256
`07b5c83608d95315afa74cad32028cf7bb45d35b7f38364865139e6a7dae4725`.
Installer SHA-256 remains
`e6228b0f655d5551eaf5cc8d085ea8111b24df3930b27cc78700d0944432ff71`;
the new ten-file harness SHA-256 is
`4fe500a0fe82a4f163c5fe5e6812d1562abaaa7885e7550e706f16402bfcc872`.

Clean build/job114184446041 passed. Independent unsigned artifact11665754216
readback verified ZIP SHA-256
`17cbf941b60ac564a63f02efcc44e44e68bdb97bb20f0a65666e46a9ad3e8626`,
seven packages, 64 frozen child source blobs and 42193 MTREE rows. BUILD metadata
SHA-256 `3e317d9e7f643224d58ea65747ada58e5b627c6e1ababc3e8e6dd5cc19ecc2b2`;
UNSIGNED manifest SHA-256
`cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`.
The unsigned receipt SHA-256 is
`2188ed920865492e3bcfe19e803b45f132657c5461b4758e3ade5f26e418cc23`.
Package bytes reproduce the previous unpublicized build; changed BUILD metadata
binds the new source. No prior VM result is transferred. Protected readback/
job114185577203 passed.

Snapshot/job114185858151 passed all five root gates: unflagged and full namespace
repository modes (both scenarios10/signer14+18/deferrednone), sealed root
publication boundary, ordinary keyring mode and privileged keyring mode
(scenarios10/deferrednone). Retained signing-job log SHA-256
`86040556a062eb83e88a80625638281a8ecf056db287a8dfd9e47e91e5e1e0ad`.
Independent signed Phase-A artifact11665494830 readback verified exact fourteen
assets, twelve signed manifest rows, all three outer signatures and twenty-five
repository objects. ZIP SHA-256
`103e53c38fa97c36b85af79891d98c238b6444480087ab534ce733c5eb16496e`;
RELEASE manifest SHA-256
`36ca5c8faa753f075f9afaa679f877d68551e032818a4a618dfec2d727c8c5f1`;
repository archive SHA-256
`c84a1ebd22e31071c884cdaec226e53c6e9b9f28d88791bc6cff1d9baaf59faa`.
BUILD and UNSIGNED bytes match the accepted unsigned input; independent Phase-A
receipt SHA-256
`d354e9e8d17fedf86983136582382639b8b54d7177f02b10f99a9ad0c61e68de`.
Core Minimal/job114186502498 started at 09:51:53 UTC; other scenarios are queued.
An early active-check annotation query returned an empty list; notice visibility
is still NOT_TESTED. No new VM/public PASS or published 1.0.7 exists yet.

Independent read-only immutable-doc audit of child912cfae4 inventoried all 29
Markdown files. README/installation pins are correct; no old 1.0.6 installation
command outside generated blocks was found. Dated/attempt-bound older release,
FAIL and CANCELLED records remain historical. One stale README sentence called
implemented package-only tooling a present F-14 limitation, contradicting the
delivered source/design records. Root corrected the source wording to describe the
implemented route within unchanged accepted closure, the full-release requirement
for GNOME51's seventh package, and separate authority/NOT_TESTED external package
delivery. This child must not be published with that stale wording. Current
Minimal evidence, if delivered, remains bound to this child; corrected frozen
documentation requires a fresh accepted candidate, not transferred VM PASS.
Independent diff review confirms the correction, valid affected links and honest
remaining gates. The review's minor receipt-tense finding is corrected. Root
`bash tests/source-tests.sh` exited zero (runtime173/docs29/full repository
namespaces10/signer14+18/deferrednone and ShellCheck). Retained source log SHA-256
`75c9cb1b438ee32944ebac7e698f0a8feec6f11a7cd8e0be90e7681aee56395e`.
Only receipt prose followed; docs/diff checks are repeated before committing.
Protected PR/exact-head CI and corrected freeze/VM/public acceptance remain open.

[PR84](https://github.com/snaplyze/arch-linux/pull/84), head
`6664c26269daec059d33996bf8a7bb6c07dddafe`, tree
`1564c1c59b7de775e14c6d20041f0f8b224fcbc6`, canonical SHA-256
`3c21fd05adb476c81aee46c7ea59c87f00bfe398467b78efa56c8f2ecb2469a8`,
contains the corrected documentation. CI38043349657/job114187848865 is running.

Minimal/job114186502498 passed at 10:11:30 UTC. Independent artifact11667201074
readback verified transport ZIP SHA-256
`b7f36568a56f726b2565bdf7be6171fa9258f0d50be5ae3532da2539e5fdb7f3`,
archive SHA-256 `03e75c419cf7d091161c35011cff4f4129b2071ad0d2aae0a6dad5fb61e34887`,
result SHA-256 `54ab98ce071a4c52e0fc5fa2e0d44a01a536ab25d0b358ab7184a32b438814c1`,
exact child912cfae4/tree6128fed5, ten-file harness, ISO and all four signed Phase-A
input hashes. The actual frozen strict core consumer exited zero; consumer
SHA-256 `ed131e3312b0fd846a4affb3866fb3a7c36aad17af1966849b06fe467de5e522`.
All fourteen assertions passed: accepted ISO/exact installer/normal completion,
UEFI/ext4/systemd-boot, Minimal TTY, installed console, network/DNS, no failed
units, real full pacman Syu, new boot ID/console, no failed units after reboot,
clean shutdown, zero QEMU exits and image/no-owned-process checks. This confirms
the readiness correction for this child, not GNOME desktop recovery or the
corrected documentation candidate. Terminal log SHA-256
`56b9212ab4f7887966bc50a2a3de328d9631214e65198ca1d77236f12d39dc26`.

Root requested normal cancellation after Minimal completion to prevent immutable
publication with the audited stale README. Release38042159246 is terminal
CANCELLED; remaining VM cases are interrupted/unexecuted, not product FAIL.
The terminal log contains all sixteen paired plain/notice phase observations.
After job completion the API exposed ten progress annotations (plus one unrelated
warning). Active queries had exposed none; live visibility was not established.
The [actual runner2.338.0 source](https://github.com/actions/runner/blob/v2.338.0/src/Runner.Worker/ExecutionContext.cs)
limits retained issues to ten per type in a step while still logging later
messages. Notices therefore supplement the full plain phase log; they are not
a complete phase record or evidence of immediate active-job API availability.

The cancelled next Stock job114186502587 ended before VM execution, during a
download. Its terminal log SHA-256 is
`1f71143f7f632c1dbc6a8a02dfdf76cbbe9bb997ea3013a6d1ed18e030ce431e`;
runner cleanup reported completion. This is not a cancelled-harness artifact
acceptance test and does not establish whether VM cleanup fits the signal grace.

PR84 merged at 10:16:33 UTC after exact-head CI38043349657 passed for head6664c262
(app15368); CI log SHA-256
`777751e5fa808b55e9f1b96287f2faa23be6f124f894341f3535948a2e95b624`.
Local main fast-forwarded to `289fda52896f3df684798d5789a48ae3e1e71543`, tree
`1564c1c59b7de775e14c6d20041f0f8b224fcbc6`, canonical SHA-256
`3c21fd05adb476c81aee46c7ea59c87f00bfe398467b78efa56c8f2ecb2469a8`.
The root's uncommitted evidence notes stayed byte-identical across the return;
the index stayed clear. [Main CI38044336202](https://github.com/snaplyze/arch-linux/actions/runs/38044336202)
is running. Corrected frozen inputs, native GNOME and public delivery still need
their own acceptance; the workstation remains unchanged and 1.0.7 unpublished.

Main CI38044336202 passed; retained job-log SHA-256
`a8a0b08bd75afcbe89a06bb2f59657a2b620f71783ab2d5d94d7eb1ce664edbb`.
Configured [release38044528734](https://github.com/snaplyze/arch-linux/actions/runs/38044528734)
prepared corrected child `2e5484905556d13dcd2aae88949b9d1b6cf1b78f`, tree
`73f928cc919ab4c119f00c162f0c619acc984820`, canonical SHA-256
`68c8e2bb9e7b6428ca84aa70c48a7673c44f2cc599c5fc58e54be4da4375f48a`.
Prepare/job114191271350 passed. Independent source artifact11666791697 readback
verified ZIP SHA-256
`a799d6e3662b378c8c57c627be4c55d763f6fdd1ad8c68dd2287d265d1b269a3`,
bundle SHA-256 `f992d3a4053b03fd61e3054cca84aaceab910baeb7e36f00b3c2ea6577b7c2ee`,
origin/child identities, deterministic derivation and generated README/installation
1.0.7 pins. Clean build/job114191322190 and protected unsigned readback/job114192131158
passed. Independent unsigned artifact11667252246 readback also passed for the exact
child: seven packages, sixty-four immutable source blobs and 42,193 MTREE rows.
Transport SHA-256 `3ae180480be6969efb27621d83724961b579337ede38369055fda6865a8b0096`,
build-metadata SHA-256 `15f419735e1e159a8919f77d5177433b01ef480484fe8b6814b1d17de95ff640`,
unsigned-manifest SHA-256 `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`.
The independent all-Markdown audit found another immutable-documentation
defect: `docs/release-process.md` called its dated 1.0.6 evidence the "Latest
delivered release". Root requested normal cancellation before signing; run ended
CANCELLED at 2026-10-10T10:26:51Z. Snapshot signing, QEMU and publication did not
execute. The heading was made explicitly historical, with the evidence unchanged.
Independent semantic inventory of all twenty-nine tracked Markdown files completed:
no other unqualified older-current-release claim or stale generated installation
command was found. Dated/attempt-bound records retain their identities. Fresh signed package, VM and public gates remain open;
prior Minimal14 PASS belongs to child912cfae4 and is not transferred.
Root `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` passed with 173 runtime
tests, full namespace10/signer14+18/deferrednone and ShellCheck; retained log
SHA-256 `9e37d3f0ee1df623c160175ad65ad8ada93eabbc92bcd9d666b246942cad22c7`.
Only receipt prose followed; final documentation/diff checks are repeated.

Documentation [PR85](https://github.com/snaplyze/arch-linux/pull/85) binds the historical-heading
correction and retained attempt evidence to head `6975a6ec2a79db5deeb67604034290b2eb31b38e`,
tree `6fd5f0bdcb1fcdf0efee8151f8ebe57425c46054`, canonical SHA-256
`a277fd803424df5b0d766683455d9283281a7aa0339c7f2d1d13c4ebd69ff866`.
Exact-head CI38045178691/job114193147981 passed; retained log SHA-256
`e025f0f8f0bf60d6b6b4d222039bf7913181498ca9da262a906a9866780672a0`.
Protected squash merge completed at 2026-10-10T10:35:25Z; main is
`09e30447552bde29b748d508f675a95ef03670ee`, with the same tree/canonical
source identity. The sole checkout returned by fast-forward; the uncommitted
root evidence note remained byte-identical and the index clear. Main
CI38045432264 passed; retained log SHA-256
`8191cfb1a3db3291bfcbcb7579d184dc69fbcb9df61704dc8a6874c2989f73a0`.
Configured release38045648678 is preparing a new immutable child; fresh
source/package/VM/public acceptance remains required.

Configured [release38045648678](https://github.com/snaplyze/arch-linux/actions/runs/38045648678)
prepared child `daec8e9f22ab64c0364c28f07799468c2ab7f142`, tree
`44daf5f1e686da2983413b4725aa759fed4d67a6`, canonical SHA-256
`5509025ca368b11a62d1ce226cc97bca2eb4a1141144ba2e49b7c36f2c80e13f`.
Prepare/job114194516866 passed. Independent source artifact11666728168 readback
verified ZIP SHA-256 `3974c7d8ed74481bd8bda8e993d3d3d8afb569725b49554feff70c66db643d0a`,
bundle SHA-256 `8cc2477ec300d1190c6717e181e039d3ac402823873545a91485a9d0ee993330`,
origin/child identities and deterministic derivation. Generated README/installation
1.0.7 pins and the historical release-process heading passed exact-child review.
Source-readback receipt SHA-256 `ba31768f74ab8fc7db2654f54402953ffc542afa686eb638d16c028f3a8d520b`.
Clean build/job114194560506 and protected readback/job114195461008 passed.
Independent unsigned artifact11667189401 readback verified seven packages,
sixty-four pinned source blobs and 42,193 MTREE rows; transport SHA-256
`d69e47f69e88004f210281b080fe5ba0896d06a33d9a70fd042df21f1c8956e2`,
build-metadata SHA-256 `3c0f0e56819dc87baeffab51bf2e29512dd8de19bcc0f3135feb4f5697b53b7a`,
unsigned-manifest SHA-256 `cec8557a6db3f58e6a1beaaa0f4c6f5e94471a02b66bbbef7bd492303ed4dc37`.
Readback receipt SHA-256 `16022431d9fb8305472b1007faef81ba3f5e764db39952a1dc1ea4f09b3de83f`.
Snapshot/job114195626252 passed all five release-host gates and signing.
Retained job-log SHA-256 `c8b34e705226e38fa1faf25f8a7c7d5c3b7da5dff47d42183e89eae43e563663`.
Independent Phase-A artifact11667439518 readback passed: exact fourteen assets,
twelve signed manifest rows, three outer signatures and twenty-five snapshot objects.
Transport SHA-256 `b7b708f75795ea7ff8b2761e51604f3d8a590fa3dfd593c7999d38552a1b5e01`,
release-manifest SHA-256 `d705a47c9a873d07b0e563106c8d94df03b2b8a8c0d7dbc9aa8a472cccd84095`,
repository archive SHA-256 `0b88db06db72a0983a3f09b8f2b56f5ca4c2188411daf0d0464925c31cfd0e7e`.
Build/unsigned identities match the independently verified unsigned input.
Core Minimal/job114196260752 passed at 2026-10-10T11:10:32Z, run
`minimal-20261010T105208Z-db6d2d70`. Independent artifact11668646035 readback
and the frozen strict core consumer passed all fourteen assertions: installation,
UEFI/GPT/ext4/systemd-boot, TTY firstboot, active network/DNS/no failed units,
real full `pacman -Syu`, distinct-boot reboot/TTY return/no failed units,
shutdown, clean image and no owned QEMU process. Transport SHA-256
`53e8f901c202f652e46f9ec968255fbca98e11586aa3b4f0c09bb578c34076d9`,
archive SHA-256 `6187a54bae42a4c99acaea22c158bd40bbac411a409311e290f40f297d68d4b2`,
result SHA-256 `2c80b7f64c28dee41b0115c82355097e97b054e136aca45dc8bd8721d4214e05`,
frozen consumer SHA-256 `ed131e3312b0fd846a4affb3866fb3a7c36aad17af1966849b06fe467de5e522`.
Retained terminal log SHA-256 `cd1c5b3d87c3ace1afcf145eddd7a0a2f3c458f22670cb097712bdf3d63e54c1`.
This exact-child Minimal result does not establish GNOME or public acceptance.
Core Stock Btrfs/LUKS2/GRUB/job114196260700 passed at 2026-10-10T12:34:30Z,
run `luksgrub-20261010T111246Z-e638a253`. Independent artifact11670495311
readback and the frozen strict core consumer passed all twenty-two assertions:
exact installation, encrypted boot/storage/GRUB, real GDM password login,
desktop/network/locale/shortcuts, same-session lock/password unlock, full Syu,
GRUB/package integrity, reboot/second login, shutdown/image/process cleanup.
Transport SHA-256 `106dfca9cd0564b294393a317440e17cc3f2822795ece91d169258de31b4c5fc`,
archive SHA-256 `26b1f0e5ec14cb8bb4dbc527e69bc2633a62bd0b981be924bb4151e40490be7b`,
result SHA-256 `59ae00a61a52e471401e0c8f6a08f011bd22b8c8ad5c00850df40801c7d71ea1`.
The frozen consumer SHA-256 matches the Minimal consumer recorded above.
Retained terminal log SHA-256 `18758a1fff392b0add6f37bfe8043df5614dc968fee2653aa515a1cad1969952`.
Core Marble/job114196260751 failed at 2026-10-10T13:37:35Z in
`fresh-user-login`, before extension migration/functionality. Independent frozen
artifact11671741833 failure binding retained four earlier PASS assertions and
exit1: transport SHA-256 `2cf28f4796c4e707520ed960ac1bc3ce27c55cb9515d7ebc94eb2ddaa828b1fa`,
archive SHA-256 `ce0daca0fa2573f0fa3f0049a14b7721aa9fb5c6053e69718dc561bdf96eda4e`,
result SHA-256 `51e72565b503b3339a061686d0edca23c21183aff6c31ee2112ac5b12adf2335`.
The historical FAIL consumer is not relabelled as strict PASS. Run38045648678
was normally cancelled before finalization/publication; remaining six staged
scenarios provide no accepted result. Compact diagnostics show an authentication
failure for the fresh account without a PAM session-opened event; earlier original
Shell stop timed out separately. The cause is still under investigation.
Marble migration/extension functionality, remaining VM, final eighteen-asset
closure and public acceptance remain required. Stock baseline acceptance does
not establish Marble migration or all extension functional behavior.
Independent read-only acceptance audit confirmed a remaining coverage gap:
`run_extension_functional_acceptance` exercises Dash, Clipboard and No Screenshot
Box only in Marble upgrade/postreboot. `verify_stock_session` and
`verify_marble_user_session` check exact enabled UUID sets, not functional effects
of AppIndicator, Blur, Caffeine, Just Perfection and User Themes; Stock lacks the
three existing functional rounds too. Thus the all-extension requirement in
AGENTS.md and Blur/Just Perfection behavior promises in testing.md remain open.
Current core PASS results must not be widened to cover that gap. Pinned extension
and actual Shell 51 source review identified native applied-effect observations,
public StatusNotifier registration and SessionManager inhibition as suitable
positive/control outcomes. The official interactive Looking Glass path is
separate from remote Shell.Eval and does not require changing unsafe mode.
Implementation/regression/native acceptance remain required; no claim that these
new probes have run. Its Marble FAIL is retained; this attempt is terminal CANCELLED before
immutable publication.

The new observer's local predicate/controller checks passed:
`gjs -m tests/vm/desktop-extension-observer-checks.js` reports 91 fake-native
checks after duplicate monitor-widget, unmapped shown-panel and closed-overview
negative controls. Its finite read-only bootstrap preserves normal Looking Glass and rejects
unsafe mode, wrong identity/source hashes, malformed/reordered commands and
unapplied native effects. This is source-tool evidence, not a live Shell result.
The separate AppIndicator/Caffeine helper passed 63 isolated D-Bus checks with
`timeout 60 env GIO_USE_VFS=local DESKTOP_SERVICE_PROBE_PRIVATE_BUS=1
dbus-run-session -- gjs -m tests/vm/desktop-service-probe-checks.js`.
The actual functional-round producer and fixed-input regressions first failed
against the old harness, then passed after integration: eight functional cases and
five fixed keyboard cases. They cover shared seven features and the eighth User
Themes feature on Marble. Frozen old results keep their original ten-file closure;
new source uses sixteen runtime files and requires Stock36/Marble43 assertions.
Integration includes normal Looking Glass input, exact scoped setting restoration,
Stock first/postreboot and staged Marble upgrade/postreboot plus public Marble
first/postreboot. Runtime shell/observer checks remain actual-VM NOT_TESTED.
Independent review reproduced a restoration parser error that could falsely
succeed with an empty loop and completion that could ignore original native
preferences. Synchronous validation of all ten scoped dconf paths now precedes
writes; completion requires exact raw setting readback and matching restored Blur,
panel and theme receipts. Process custody also binds boot ID. Thirty offline
custody/restoration checks passed. A source import substitution was reproduced;
four code files now live under root-owned non-writable code ancestors, separate
from user-owned metadata/receipts. Fifty-one service protocol/file checks passed.
A separate cleanup pathname substitution was reproduced in owned temporary
fixtures, then corrected with descriptor-based unlink and pathname identity
checks. Independent rereview and the actual foreign-file preservation regression
passed. The named GDM path now waits for one stable new worker after submitting
the username once; four delayed/failure fixtures changed from RED to GREEN. This
closes a test input guard gap, not the unproved cause of the prior PAM failure.
No source-tool PASS proves a native GNOME session or public update delivery. Root
`PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` subsequently completed
exit0 (runtime174/full namespace10/signer14+18/no deferral), log SHA-256
`883f5d5f11b6faee5b35480c0665e9d48aed96988bed8a47d8d5f793ab843dbf`.
A later narrow phase restriction and documentation changes have focused checks;
a new clean candidate still requires its own full suite and downstream gates.
Required GJS/private-bus test dependencies were added to the Ubuntu CI and Arch
package-build source-check environments; `bash tests/static-checks.sh` passed.

Clean local commit `fb00dba0f6b847ceb9e4ca49261567e092dc9241`, tree
`5a9014644886f40e4e45cf83c05d801fb4bd85b9`, canonical SHA-256
`7220e66c24a0546d2ddac19541a712b1722ae7813419db9a1548d7ee06c08835`,
passed its separate full source suite exit0, including runtime174 and repository
full10/signing14+18/no deferral; log SHA-256
`fdc677c8cb5e3cc9837bc7db0fec4fbca042abd693353b4f049d4b650d55091c`.
PR86 exact-head CI38057799588/job114229732392 failed four native cases after GJS
became installed in the Ubuntu container: GTK4's typelib was absent, and the Gio
lookup fixture assumed the host org.gnome.shell schema. This is a source-tool
portability failure, not a GNOME repair verdict. Add explicit GTK4 introspection
and GLib compiler dependencies, and compile the minimal settings schema inside
owned fixtures. Native identity checks and exact favorite/desktop/Exec controls
remain active; no skip or unknown-as-PASS fallback. The exact pinned Ubuntu image
passed both native cases, service runner51, observer91 and private-D-Bus63 as
nonroot with read-only source, 2 CPUs, 1 GiB and a fifteen-minute bound. A first
diagnostic container stopped at an existing UID1000 before tests; the corrected
run used that existing user and exited0. Independent focused review found no
material issue. The follow-up full source command
`PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` exited0, including
runtime174, all native fixtures and full repository10/signing14+18/deferrednone;
log SHA-256 `94b06cbf9968ae85f5de040204235e05e080d4c6462e34dcadad3a3553f298ab`.
Documentation/contract checks were repeated after these checkpoint edits.
This is a working-source result. Exact-head
[CI38058719339](https://github.com/snaplyze/arch-linux/actions/runs/38058719339)
passed at `a5f2d9b7974baf1d7d35b9112ccee983913b6976`; log SHA-256
`b64dc5e52fce874d3a3f06f93d35562f2e84ebd42a6860954e91a009ecc1f814`.
PR86 squash merged at 2026-10-10T14:18:05Z to main
`c9ea0399ecba37bd8d0e19557a5eac3111f07683`, unchanged tree
`473fa7c451aa1af186cfd1a8e912d6c50630c3d7`. The canonical checkout returned by
fast-forward with no foreign changes. Main CI38059060706 passed; its log SHA-256
is `394cedda97f2c894c35163183ae1390c592fada509c6b49e038c2bce7a8700e1`.
The configured release [38059360429](https://github.com/snaplyze/arch-linux/actions/runs/38059360429)
prepared version1.0.7, child `43410ed884fdfe7b0b2914caa8d76f4f63b2c64d`, tree
`8930e7104f960b0671bcc0c7c6f809d17d4fe128`, canonical SHA-256
`6417993bda74e0ea0b1530f7979941dac4f609b4384222ba76c0a113325f9d20`.
Source artifact11671724685 transport SHA-256
`34f1a0d25227fe7a425ec90fa1e7f037853722d99a06e225804e3c06cc1a145f`, bundle SHA-256
`cb1a8727ebcc3fbf54958a16d9a568a3029b347d47399e22032187d680654500`.
Root independently verified transport/bundle, deterministic origin/child identity,
canonical bytes and frozen README/install1.0.7 commands without changing refs,
index or source. Independent read-only review verified the bundle pack/child raw
commit and all224 mode-and-byte blob identities, exact20 deterministic child
changes, unchanged16-file harness and frozen release prose with no material
finding. Build job114234331701 passed its full child source suite and clean
seven-package build; retained log SHA-256
`d505280ccfa5f2a9ddf587a26ca08b393098778666a5fbcbffd6ba52867c80c8`.
Root unsigned readback passed artifact11672168224, ZIP SHA-256
`fc848465d271b6c7c3d181d8437d79570a40626ab327c3f039b27045ce201c55`,
build metadata SHA-256 `16934e823afdc707d8366e3be5bc3c84e171d6aacd10ab33007e8b237a1630d7`,
unsigned manifest SHA-256 `a265d5f47caa01684151f0408072ba4655417d0a16ed6692885fce248d1768f3`.
All seven metadata/payload/mtree inputs matched 64 immutable source blobs,
42193 mtree rows; refs/index and dirty documents were preserved. CI readback and
root gates/signing/all9VM/final18/public gates were pending at build readback; no old
VM result transfers to this main or its child, and 1.0.7 remains unpublished.

Release38059360429 then terminated FAIL at root gate job114235618936 before
production signing/private-secret handoff. Both repository runs reached full10/
signer14+18/deferrednone; root publication's own synthetic snapshot passed, then
its harness read failed because fixture-source omitted desktop-native.sh and the
other new native harness files. Log SHA-256
`65c0292a7f55ceae31e7de1e1dc38346ae36ea681120553b4ed16de4f8b31c0a`.
The source gate's fixture lacked this accepted harness closure despite ordinary
source tests passing. Root fixture also requires Stock functional receipts.
Keyring gates, production Phase-A, all9VM, tag/draft/final18/Pages/publication and
public VM were skipped. No tag or public asset was written; latest stays1.0.6.
The focused correction must pass its regression and all actual root gates before
another immutable child; these source/build results remain bound to43410ed8.
The focused regression reproduced the missing native source through the actual
publication fixture constructor. The correction includes six native files at0644
and preserves frame-evidence.py's0644 source mode. Both Stock and Marble use the
synthetic functional-log producer. A source regression executes actual fixture
runtime construction against its immutable consumer, checks all16 mode/byte
inputs and rejects removal of each required receipt. Signing14 tests passed with
two existing root-only skips; Bash/ShellCheck/diff passed. Independent read-only
review found no material issue; its two targeted actual-builder tests passed.
Follow-up `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` exited0,
including full repository10/signing14+18/deferrednone; log SHA-256
`16170c3c108db6b32395fcb44a77cf315dccbc5fceeb8c5ae3359acf6e254391`.
Docs/diff were checked again after checkpoint edits. This working-source result
does not establish actual five-root acceptance, which remains required before
another ready PR and immutable release child.
Clean candidate `431832a2b31967cd70eae5f4b3c2125ce094ae34`, tree
`209de612a191b24619301ad72d041855ae6d8bcd`, canonical SHA-256
`26bf1cc0b6725f1cf8a81de9be1c6b12fcc9d3c1cc37eab32e1f1a57bca326eb`
passed its separate clean full source suite, log SHA-256
`8cc667d0ee6ea040823360552febeedcd2a4ff8c26be329a09a7cd9035f58be2`.
On the dedicated runner VM, a disposable exact pinned Arch container at2CPU/
2GiB/256pids/thirty-minute bound consumed its SHA-pinned immutable Git bundle,
copied to root-owned input before use. Both nonroot repository modes reached
full10/signing14+18/deferrednone; exact env-i root publication reached sealed14/18
with FIFO/memfd/namespaces/PID1/supervisor-death checks; ordinary and privileged
keyring modes passed, the latter full10/deferrednone. Final commit/tree/clean
custody check passed. Five-root log SHA-256
`4bb8ed2bdaf4ee103be4ef59e70a2ad3d924980ce5c7b334a939d1d25cee5252`.
Independent review verified source/log/recipe identities and all five markers,
finding no material issue; it did not independently requery external cleanup.
Root verified exact container CID/label absence and no owned keyring backing
loops, then removed only the hash/metadata-checked remote bundle, recipe and CID.
This is synthetic source/root acceptance, not production signing or a GNOME VM
verdict. [PR87](https://github.com/snaplyze/arch-linux/pull/87) exact-head
CI38060997004 passed; its log SHA-256
`c90a20b7d71ebf2862681f0dd1b35e967ef8822a464264b5eae763296a51ec6a`.
PR87 squash merged at2026-10-10T14:52:50Z to main
`a9831fadecd8fb4ddf8196a129ecff4c23d916f1`, unchanged tree
`209de612a191b24619301ad72d041855ae6d8bcd`. The sole checkout's main was updated
by fast-forward before return, preserving both dirty checkpoint files byte for
byte and the clear index. Main CI38061366805 passed, log SHA-256
`1f5380a828d2e49f4ff33b023dfe33c4e11ef0809ab39572a3bfa7409149394a`.
Configured release [38061649342](https://github.com/snaplyze/arch-linux/actions/runs/38061649342)
prepared version1.0.7 child `a6887ee8593e4223af7af0a01726cd293d296ec6`, tree
`93ecae49f3c1c724d0597a1680f9119b2fa78be3`, canonical SHA-256
`0b81bfcbe6cd2cfdcefdf64b71cbc1af2c41cdf6f02313b256c451cc706a60e3`.
Root verified source artifact11673541042, ZIP SHA-256
`2262de96e34af723b40b942cb813e21588c7d362d9599b54a565268a9c0156ae`, bundle SHA-256
`85b6377e335276a3d918a3e1d14a3e64d2cdff990a1fce0ba375691478aa373f`,
deterministic main/child binding, canonical mode/bytes and frozen1.0.7 commands.
Refs/index and local checkpoint bytes were preserved. Independent read-only
review verified all224 blob identities/canonical mode-and-byte hash, exact20
deterministic child changes and commit provenance, unchanged reviewed root
fixture files/full16 harness and frozen release prose with no finding.
Build job114241007330 passed full source and clean seven-package build, log SHA-256
`25bab4d3f780b8ebce048c2e38c85cac19c66a2bacb7589ab13cd96d2335bdc7`.
CI independent unsigned readback/job114242069024 passed. Root readback passed
artifact11673432003, ZIP SHA-256
`1f86428e7d9a30db718e9bdb94bbf54abf06f7ef25a32523e36ce906727f6dfa`,
build metadata SHA-256 `c4be930853027766480e3a3d674ed7330c7f29062468830f796056c4cf4d9689`,
unsigned manifest SHA-256 `a265d5f47caa01684151f0408072ba4655417d0a16ed6692885fce248d1768f3`.
All seven package metadata/payload/mtree inputs matched64 immutable source blobs,
42193 mtree rows. Actual child root gates/job114242248253 passed both repository
modes full10/signing14+18/deferrednone, sealed publication fixture14/18 and both
keyring modes (privileged full10/deferrednone), then production Phase-A signing.
Job log SHA-256 `ded664df270e814fafc2153158f766f8c89b88a3c6bb1ca911814d7f3784b8a1`.
Root independently verified exact14 Phase-A files/artifact11673632054, ZIP SHA-256
`9fff5b253c836c2129b5639cd80784e7115cd09447608d1c792e766e5000555e`,
exact12 signed manifest rows and three top-level signatures from the source-bound
signing subkey/certification primary; installer/bootstrap/trust bytes and both
unsigned metadata files matched their accepted inputs. Manifest SHA-256
`e94983a068d5d2d8b7fedd1a1989637d47780fe85ac5a228b582ee4c115cff29`, snapshot SHA-256
`2775a66797f6935391b15a0c5ec58ddbd47d92c3a9e66212800dead32dce39e2`;
immutable snapshot contract matched25 objects. Core Minimal VM/job114242966715
started. Independent readback also verified all10 inner signatures (seven
packages, database/files and inner manifest), seven signed payloads against the
accepted unsigned bytes, and repository metadata. Cancellation was requested
after independent finite native GJS reproduction confirmed a GTK source-path
provenance defect: actual extracted receipt validation accepted foreign-code
receipts after the user-owned probe pathname was replaced with original bytes.
The live PID/executable/argv/start-time checks did not detect that substitution.
The reproduction changed no desktop, bus or settings and removed its own fixture
and process. The run is terminal CANCELLED (all9VM cancelled); Minimal terminal
log SHA-256 `f28b518641f71e6dc713d116aa828a4235ab574322928976619d992d00de120e`
records job cleanup complete. No VM PASS is accepted for this candidate; GNOME functional
acceptance, all9VM and final18/public gates remain unfulfilled. A focused
root-owned0555 GTK execution path under root-owned0755 ancestors now replaces
the user-owned executable copy. The JS hashes its own loaded module URI;
launch/receipt/cleanup bind the exact code path. Native GJS executes foreign
user-path code and restores original bytes, then actual receipt validation
rejects it while canonical execution remains accepted. Independent focused
review repeated both native tests, Bash syntax and ShellCheck successfully,
with no material finding. Full source verification is running; actual GNOME VM
acceptance remains untested for this correction. The first root source invocation
used umask077 and failed three existing GDM helper mode checks (0700 vs0755);
this was a diagnostic invocation error, not a product regression. Failed log
SHA-256 `d742201d695d3896697a37d006ab072d647e63224204519850b644cd7029998f`.
The stable source suite passed with normal umask022 (`bash tests/source-tests.sh`),
log SHA-256 `755d75a75eee74b69280c295874019c4c65974013d357de28920a0435f4d04b2`;
full10/signing14+18/deferrednone repository fixtures and final ShellCheck passed.
These fixtures do not establish production or GUI acceptance;
version1.0.7 UNPUBLISHED. Local checkpoint
edits are outside431832a/a9831fa/a6887ee's trees; no old receipt transfers.

At 2026-10-10T14:00 UTC, bounded official AUR and Arch-maintained mirror probes
again returned matching Plymouth and bibata-cursor-theme-bin HEADs as recorded
above. Availability checks remain advisory and do not promote any recipe update.

At 2026-10-10T07:19 UTC, finite read-only `git ls-remote` checks against the
official AUR succeeded for both Plymouth and Bibata. Availability is advisory:
the observed HEADs do not authorize changing the reviewed recipe pins. The
installer retains primary-first clones and falls back only after a primary clone
failure to the [Arch-maintained mirror](https://archlinux.org/news/recent-services-outages/),
using an independent attempt directory and the same immutable verification.

At 2026-10-10T12:01 UTC, bounded primary AUR `git ls-remote` probes passed
again for Plymouth and Bibata. The Arch-maintained mirror responded with matching
branch HEADs (`6c040c458108213626650a2dbc943517308dfd2a` and
`5d418e2c328f988b0b5c4fc51e6ca9619bfda293`, respectively). This is availability
evidence only, not approval of a newer recipe or new pin. Read-only source review
confirmed both primary and mirror clones have 300-second deadlines with TERM/KILL
cleanup, independent attempt directories and the same immutable identity gate.
Core Stock/job114196260700 was still active; no exact live VM phase or new
GNOME verdict was available from the public job status.

At 2026-10-10T12:19–12:23 UTC, current runner/inner-guest observation became
available through the existing dedicated SSH identity and known-hosts file;
strict host-key verification passed without changing trust, keys or services.
The outer domain UUID and loopback listener were bound to the existing runner,
and the project QGA client matched the frozen source SHA-256. The inner QGA
socket owner/device/inode and exact QEMU PID were validated before requests.
Core Stock run `luksgrub-20261010T111246Z-e638a253` was still installing.
An initial process-only query observed pacman and archive pipelines, including
1,100 gpg child zombies. Subsequent queries observed pacman and those zombies
gone, then unprivileged makepkg/fakeroot with active bsdtar/zstd compression.
These changing process observations establish installation progress, not a
deadlock, GNOME login, or the cause of prior desktop failures. No raw process
arguments, environment, password or installer journal was exposed; no runner,
guest or workstation configuration was changed. Root-owned compact diagnostic
outputs remain outside the source tree. The live job has not produced a verdict.
The live assertions subsequently recorded `accepted-official-arch-iso=PASS`
and `actual-installer-executes=PASS`: the accepted installer exited zero and
the harness advanced to firstboot. The installed package database reported
Shell/Mutter/GDM 51.0, GTK 4.24.1, libadwaita 1.10.0, curated extensions
1.0.0-7 and Plymouth 26.134.222-3 while Bibata was still being built. These
are intermediate observations, not session or final package-integrity acceptance.
Inner QGA diagnostics stopped before firstboot to avoid competing with the
active harness; subsequent observation reads only the outer evidence files.
At 12:30 UTC the live assertion file contained sixteen PASS entries, including
encrypted firstboot, real GDM password login, desktop/network/locale/shortcut
checks and `lock-password-unlock`. The exact unlock guest-exec status reported
`exited=true, exitcode=0`. The unmodified password-input/unlock contract passed
in this current guest; this does not retrospectively establish the cause of an
older failure. Full Syu, reboot, second login, cleanup and the final artifact
consumer subsequently passed as recorded above.

The selected version is 1.0.7, UNPUBLISHED. Generated README and installation
bootstrap pins and reviewed Unreleased notes were verified before freezing.
This child contains the filtered lifecycle observer, post-logout/early-return
checkpoints, atomic HTTPS readiness and corrected archive alarm/cleanup handling.
All prior child VM verdicts remain historical. Fresh actual installation/
migration/login/functionality, finalization and public delivery gates remain open. No workstation
package or setting has been changed; public latest remains 1.0.6 at this attempt.

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
