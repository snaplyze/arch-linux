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
Protected delivery and fresh child/build/VM acceptance remain pending.
These source results do not establish the still-pending real
GNOME 51 migration or transfer any old VM result to a changed child.

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
